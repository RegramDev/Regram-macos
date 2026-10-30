import Foundation
import RegramCore
import SwiftSignalKit

func verify(_ condition: @autoclosure () -> Bool, _ message: String = "Fixture assertion failed", line: UInt = #line) {
    guard condition() else {
        FileHandle.standardError.write(Data((message + " at line " + String(line) + "\n").utf8))
        exit(1)
    }
}

struct PeerId: Hashable {
    let value: Int64
    init(_ value: Int64) { self.value = value }
    func toInt64() -> Int64 { value }
}
struct MessageId: Hashable {
    let peerId: PeerId
    let namespace: Int32
    let id: Int32
}
struct Peer: Equatable { let displayTitle: String; let id = PeerId(17) }
struct PeerEquatable: Equatable { let peer: Peer }
struct Message {
    let id: MessageId
    let timestamp: Int32
    let author: Peer?
    let text: String
}
let fixtureInsideTransaction = "RegramFixtureInsideTransaction"
let previewCount = Atomic(value: 0)
let bookmarkReadCount = Atomic(value: 0)
let messageReadCount = Atomic(value: 0)
let transactionCount = Atomic(value: 0)

final class FixtureBookmarks {
    let records = (0..<1000).map { index in
        RGMessageBookmark(messageId: .init(peerId: 17, namespace: 0, id: Int32(index)), threadId: nil, addedAt: Double(index), tags: ["tag"])
    }
    func bookmarks(accountId: Int64) -> [RGMessageBookmark] {
        verify(!Thread.isMainThread)
        _ = bookmarkReadCount.modify { $0 + 1 }
        return records
    }
    func tags(accountId: Int64) -> [String] { ["tag"] }
    func bookmark(accountId: Int64, messageId: RGBookmarkMessageId) -> RGMessageBookmark? {
        records.first { $0.messageId == messageId }
    }
}
let fixtureBookmarks = FixtureBookmarks()
final class RGGroupRemarks {
    static let shared = RGGroupRemarks()
    func name(accountId: Int64, peerId: Int64) -> String? { nil }
}
func regramString(_ key: String) -> String { key }
func regramSearchIsGroup(_ peer: Peer) -> Bool { false }
func regramSearchDateFormatter() -> DateFormatter {
    verify(!Thread.isMainThread && Thread.current.threadDictionary[fixtureInsideTransaction] == nil)
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    return formatter
}
struct FixturePreview { let preview: String }
func regramSearchMessageRow(_ message: Message, group: Peer?, groupPeerId: PeerId, accountId: Int64, dateFormatter: DateFormatter) -> FixturePreview {
    verify(!Thread.isMainThread && Thread.current.threadDictionary[fixtureInsideTransaction] == nil)
    _ = previewCount.modify { $0 + 1 }
    return FixturePreview(preview: message.text)
}
func regramRemarkChanges(accountId: Int64) -> Signal<Void, NoError> { .single(()) }
func regramBookmarkCanFetchFromCloud(_ messageId: MessageId) -> Bool { true }

final class FixtureTransaction {
    func getMessage(_ id: MessageId) -> Message? {
        verify(Thread.current.threadDictionary[fixtureInsideTransaction] != nil)
        _ = messageReadCount.modify { $0 + 1 }
        return Message(id: id, timestamp: id.id, author: nil, text: "needle-\(id.id)")
    }
    func getPeer(_ id: PeerId) -> Peer? { Peer(displayTitle: "Chat") }
}
final class FixturePostbox {
    let queue = Queue(name: "regram.fixture.bookmark-postbox")
    let beforeBody = Atomic<(() -> Void)?>(value: nil)
    func transaction<T>(_ body: @escaping (FixtureTransaction) -> T) -> Signal<T, NoError> {
        Signal { subscriber in
            let cancelled = Atomic(value: false)
            self.queue.async {
                guard !cancelled.with({ $0 }) else { return }
                _ = transactionCount.modify { $0 + 1 }
                self.beforeBody.with { $0 }?()
                Thread.current.threadDictionary[fixtureInsideTransaction] = true
                let result = body(FixtureTransaction())
                subscriber.putNext(result)
                subscriber.putCompletion()
                Thread.current.threadDictionary.removeObject(forKey: fixtureInsideTransaction)
            }
            return ActionDisposable { _ = cancelled.swap(true) }
        }
    }
}
enum FixtureLoadResult { case loading, result([Message]) }
enum FixtureLoadError { case unavailable }
enum FixtureLoadStrategy { case local, cloud(skipLocal: Bool) }
final class FixtureFetch {
    var subscriber: Subscriber<FixtureLoadResult, FixtureLoadError>?
    var cancelled = false
    func signal() -> Signal<FixtureLoadResult, FixtureLoadError> {
        Signal { subscriber in
            self.subscriber = subscriber
            return ActionDisposable { self.cancelled = true }
        }
    }
}
final class FixtureMessages {
    var fetches: [FixtureFetch] = []
    func getMessagesLoadIfNecessary(_ ids: [MessageId], strategy: FixtureLoadStrategy) -> Signal<FixtureLoadResult, FixtureLoadError> {
        let fetch = FixtureFetch()
        fetches.append(fetch)
        return fetch.signal()
    }
}
struct FixtureEngine { let messages = FixtureMessages() }
struct FixtureAccount { let postbox = FixturePostbox() }
final class FixtureContext {
    let peerId = PeerId(42)
    let account = FixtureAccount()
    let engine = FixtureEngine()
    var isFrozen = false
}
final class FixtureHooks {
    var opened: [MessageId] = []
    func openMessage(_ context: FixtureContext, _ id: MessageId, _ threadId: Int64?) { opened.append(id) }
}
enum RegramUIHooks { static let shared = FixtureHooks() }
final class FixtureController {
    var didAppear: ((Bool) -> Void)?
    var willDisappear: ((Bool) -> Void)?
    var onDeinit: (() -> Void)?
}
func waitUntil(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(5)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
    verify(condition())
}
func drain() { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }

@main
struct BookmarkLoadingChecks {
    static func main() {
        let context = FixtureContext()
        __LOADING_PIPELINE__
        let reload: () -> Void = { updateRequest { current in var current = current; current.revision &+= 1; return current } }
        __FETCH_PIPELINE__
        let controller = FixtureController()
        __LIFECYCLE__
        defer { controller.onDeinit?() }

        drain()
        verify(transactionCount.with { $0 } == 0 && bookmarkReadCount.with { $0 } == 0)
        controller.didAppear?(false)
        waitUntil { stateValue.with { !$0.loading && $0.rows.count == 100 } }
        verify(stateValue.with { $0.total } == 1000)
        verify(messageReadCount.with { $0 } == 100 && previewCount.with { $0 } == 100)

        let blocked = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        loadingQueue.async { blocked.signal(); verify(release.wait(timeout: .now() + 4) == .success) }
        verify(blocked.wait(timeout: .now() + 2) == .success)
        let readsBefore = bookmarkReadCount.with { $0 }
        for index in 0..<100 { updateRequest { current in var current = current; current.query = "old-\(index)"; return current } }
        updateRequest { current in var current = current; current.query = "needle-999"; return current }
        release.signal()
        waitUntil { stateValue.with { $0.query == "needle-999" } }
        verify(stateValue.with { $0.rows.count == 1 && $0.rows[0].bookmark.messageId.id == 999 })
        verify(bookmarkReadCount.with { $0 } - readsBefore == 1)

        let enteredDB = Atomic(value: false)
        let releaseDB = DispatchSemaphore(value: 0)
        _ = context.account.postbox.beforeBody.swap { _ = enteredDB.swap(true); verify(releaseDB.wait(timeout: .now() + 4) == .success) }
        let messagesBefore = messageReadCount.with { $0 }
        updateRequest { current in var current = current; current.query = "needle-12"; return current }
        waitUntil { enteredDB.with { $0 } }
        controller.willDisappear?(false)
        _ = context.account.postbox.beforeBody.swap(nil)
        releaseDB.signal()
        drain()
        verify(messageReadCount.with { $0 } == messagesBefore)
        verify(stateValue.with { $0.query } == "needle-999")
        controller.didAppear?(false)
        waitUntil { stateValue.with { $0.query == "needle-12" } }
        verify(stateValue.with { $0.rows.count } == 11)

        let row = stateValue.with { $0.rows[0] }
        fetch(row, true)
        let first = context.engine.messages.fetches.last!
        verify(!first.cancelled)
        controller.willDisappear?(false)
        verify(first.cancelled)
        verify(stateValue.with { $0.availability[row.bookmark.messageId] } == nil)
        first.subscriber?.putNext(.result([Message(id: MessageId(peerId: PeerId(17), namespace: 0, id: row.bookmark.messageId.id), timestamp: 0, author: nil, text: "late")]))
        drain()
        verify(RegramUIHooks.shared.opened.isEmpty)
        controller.didAppear?(false)
        waitUntil { stateValue.with { $0.rows.count } == 11 }
        fetch(row, true)
        let second = context.engine.messages.fetches.last!
        verify(second !== first)
        let id = MessageId(peerId: PeerId(17), namespace: 0, id: row.bookmark.messageId.id)
        second.subscriber?.putNext(.result([Message(id: id, timestamp: 0, author: nil, text: "current")]))
        drain()
        verify(RegramUIHooks.shared.opened == [id])
        controller.willDisappear?(false)
        let readsWhileHidden = bookmarkReadCount.with { $0 }
        NotificationCenter.default.post(name: RGMessageBookmarks.didChange, object: Int64(42))
        drain()
        verify(bookmarkReadCount.with { $0 } == readsWhileHidden)
        print("Bookmark production loading/fetch checks passed: hidden page idle, latest of 101 queued queries only, projection off main and DB queues, hide before DB work, return reload, fetch cancellation and late navigation suppression; isolated records and engine only")
    }
}
