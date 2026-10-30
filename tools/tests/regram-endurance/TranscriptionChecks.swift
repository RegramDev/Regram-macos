import Foundation
import SwiftSignalKit

struct PeerId: Hashable {
    let value: Int64
    func toInt64() -> Int64 { value }
}

struct MessageId: Hashable {
    let peerId: PeerId
    let namespace: Int32
    let id: Int32
}

struct TelegramMediaFile {
    struct Resource { let id: Int }
    let isVoice = true
    let isInstantVideo = false
    let resource: Resource
}

final class Message {
    let id: MessageId
    let stableVersion: UInt32 = 1
    let threadId: Int64? = 9
    let media: [Any] = [TelegramMediaFile(resource: .init(id: 2))]
    let payload = Data(repeating: 2, count: 4096)
    init(_ id: MessageId) { self.id = id }
}

final class WeakMessage {
    weak var value: Message?
    init(_ value: Message) { self.value = value }
}

struct CachedUserData {
    struct Flags: OptionSet {
        let rawValue: Int
        static let copyProtectionEnabled = Flags(rawValue: 1)
        static let myCopyProtectionEnabled = Flags(rawValue: 2)
    }
    let flags: Flags
}

final class Postbox {
    var current: Message?
    var fetched: [MessageId] = []
    func transaction<T>(_ body: @escaping (Postbox) -> T) -> Signal<T, NoError> {
        Signal { subscriber in
            subscriber.putNext(body(self))
            subscriber.putCompletion()
            return EmptyDisposable
        }
    }
    func getPeerCachedData(peerId: PeerId) -> Any? { nil }
    func getMessage(_ id: MessageId) -> Message? {
        fetched.append(id)
        return current?.id == id ? current : nil
    }
}

final class Account {
    let peerId = PeerId(value: 87)
    let postbox = Postbox()
}

struct RegramAccountSettings {}

final class RegramPreferences {
    static let shared = RegramPreferences()
    func settings(accountId: Int64) -> RegramAccountSettings { .init() }
}

enum RegramTranscriptionLifecycle {
    static let shared = false
}

private var recognizedMessageIds: [MessageId] = []

private func regramPerformTranscription(account: Account, message: Message, settings: RegramAccountSettings, language: String, isCurrent: @escaping () -> Bool) -> Signal<Void, RGTranscriptionError> {
    verify(isCurrent() && language == "en", "Retry used stale state or changed its language")
    recognizedMessageIds.append(message.id)
    return .complete()
}

func verify(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}

@main
struct TranscriptionChecks {
    static func main() {
        let account = Account()
        let accountId = account.peerId.toInt64()
        let tasks = RegramTranscriptionTasks.shared
        var snapshots: [RegramTranscriptionTaskSnapshot] = []
        let observation = tasks.signal(accountId: accountId).start(next: { snapshots = $0 })
        defer { observation.dispose(); tasks.cancelAccount(accountId) }
        let cycles = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 300
        var originalMessages: [WeakMessage] = []
        for index in 0..<cycles {
            autoreleasepool {
                let message = Message(MessageId(peerId: PeerId(value: 2), namespace: 0, id: Int32(index)))
                originalMessages.append(WeakMessage(message))
                var cancelled = false
                let request = regramTranscribeMessage(account: account, message: message, settings: .init(), language: "en").start(error: { if case .cancelled = $0 { cancelled = true } })
                verify(cancelled, "Missing messages must cancel before recognition")
                request.dispose()
            }
            verify(originalMessages.allSatisfy { $0.value == nil }, "A retained retry operation kept the original Message alive")
            verify(snapshots.count <= 100, "History exceeded its existing cap")
        }
        let id = MessageId(peerId: PeerId(value: 2), namespace: 0, id: Int32(cycles - 1))
        let key = regramTranscriptionTaskKey(accountId: accountId, messageId: id)
        verify(tasks.snapshot(key)?.state == .failed, "Latest failure must remain available for retry")
        account.postbox.current = Message(id)
        tasks.retry(key)
        verify(tasks.snapshot(key)?.state == .completed, "Retry failed to use the current stored Message")
        verify(recognizedMessageIds == [id], "Retry recognized an unexpected Message")
        verify(account.postbox.fetched.count == cycles + 1, "Retry skipped the current database lookup")
        account.postbox.current = nil
        tasks.clearFinished(accountId: accountId)
        verify(snapshots.isEmpty, "Finished history failed to clear")
        let report: [String: Any] = ["cycles": cycles, "originalMessagesRetained": originalMessages.filter { $0.value != nil }.count, "remainingHistory": snapshots.count, "currentMessageRetried": true, "networkRequests": 0, "realAccountAccess": false]
        let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }
}
