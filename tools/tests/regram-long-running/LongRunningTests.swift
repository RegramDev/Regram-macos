import Foundation
import XCTest
import SwiftSignalKit

final class Payload {
    let id: Int
    let live: Atomic<Int>
    init(_ id: Int, live: Atomic<Int>) {
        self.id = id
        self.live = live
        _ = live.modify { $0 + 1 }
    }
    deinit { _ = live.modify { $0 - 1 } }
}

final class HistoryFixture<Value> {
    let gate = ChatHistoryRenderGate()
    let visible = ValuePromise(true, ignoreRepeated: true)
    let history = ValuePipe<Value>()
    let presentation = ValuePromise(0)
    let queue = Queue(name: "historyLifetimeChecks", qos: .userInitiated)
    private let disposable = MetaDisposable()

    init(render: @escaping (Value) -> Void) {
        let gate = self.gate
        let updates = chatHistoryRenderingUpdates(history.signal(), visibility: visible.get(), gate: gate)
        disposable.set((combineLatest(queue: queue, updates, presentation.get()) |> filter { __RENDER_ACCEPT__ }).start(next: { update, _ in render(update.value) }))
    }

    func setVisible(_ value: Bool) {
        gate.setActive(value)
        visible.set(value)
    }

    func dispose() { disposable.dispose() }
    deinit { disposable.dispose() }
}

final class HistoryOwnerFixture {
    var currentRanks: Int?
    private let disposable = MetaDisposable()

    init(_ updates: Signal<Int, NoError>) {
        let pipeline = updates |> mapToQueue { __HISTORY_OWNER_CAPTURE__ data -> Signal<Int, NoError> in
            __HISTORY_OWNER_ASSIGNMENT__
            return .single(data)
        }
        disposable.set(pipeline.start())
    }

    func dispose() { disposable.dispose() }
    deinit { disposable.dispose() }
}

final class ScrollFixture {
    let gate = ChatHistoryRenderGate()
    var visibleMessageWorkEnabled = true
    var work: DispatchWorkItem?
    var requests = 0

    func schedule() {
        __SCROLL_GUARD__
        work?.cancel()
        let next = DispatchWorkItem { [weak self] in
            guard let self else { return }
            __SCROLL_GUARD__
            requests += 1
        }
        work = next
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: next)
    }

    func hide() {
        gate.setActive(false)
        __SCROLL_CANCEL__
    }

    func show() { gate.setActive(true) }
    deinit { work?.cancel() }
}

struct TestMessageId: Equatable {
    let peerId: Int64
    let id: Int32
}

struct TestIndex: Comparable {
    let id: TestMessageId
    static func < (lhs: TestIndex, rhs: TestIndex) -> Bool { lhs.id.id < rhs.id.id }
}

struct Message {
    let index: TestIndex
    let hidden: Bool
}

struct RegramMessageHistoryPage {
    let messages: [Message]
    let nextOffsetId: Int32?
}

enum NetworkError { case generic }

final class TestNetwork {
    var starts = 0
    var cancellations = 0
    var automatic: RegramMessageHistoryPage?
    var subscribers: [Subscriber<RegramMessageHistoryPage, NetworkError>] = []
    func signal() -> Signal<RegramMessageHistoryPage, NetworkError> {
        return Signal { subscriber in
            self.starts += 1
            self.subscribers.append(subscriber)
            if let automatic = self.automatic {
                subscriber.putNext(automatic)
                subscriber.putCompletion()
            }
            return ActionDisposable { self.cancellations += 1 }
        }
    }
}

struct TestAccount { let network: TestNetwork }

func regramMessageHistoryPage(account: TestAccount, peerId: Int64, threadId: Int64?, offsetId: Int32, offsetDate: Int32, limit: Int) -> Signal<RegramMessageHistoryPage, NetworkError> {
    return account.network.signal()
}

func regramShouldHideMessage(_ message: Message, accountId: Int64, filter: Int, revision: Int64) -> Bool { message.hidden }

struct SourceKey: Equatable {
    let messageId = TestMessageId(peerId: 1, id: 100)
    let threadId: Int64? = nil
    let preferencesRevision: Int64 = 1
}

struct Request {
    let id: Int = 1
    let key = SourceKey()
    let upperBound = TestIndex(id: TestMessageId(peerId: 1, id: 100))
    let filter = 0
}

struct PreviewState { let key: SourceKey }

final class RemoteFixture {
    let queue = Queue(name: "remoteLifetimeChecks")
    let disposed = Atomic(value: false)
    let account = TestAccount(network: TestNetwork())
    let accountId: Int64 = 1
    var states: [Int: PreviewState] = [1: PreviewState(key: SourceKey())]
    var activePreviewKeys: Set<Int> = [1]
    var remoteDisposables: [Int: MetaDisposable] = [:]
    var finishes = 0

    __REMOTE_METHODS__

    func start(_ holder: MetaDisposable = MetaDisposable()) -> MetaDisposable {
        remoteDisposables[1] = holder
        loadRemotePage(Request(), offsetId: 100, number: 0, disposable: holder)
        return holder
    }

    func finishRemote(_ request: Request, candidate: Message?) {
        finishes += 1
        remoteDisposables.removeValue(forKey: request.id)?.dispose()
    }

    deinit {
        _ = disposed.swap(true)
        for item in remoteDisposables.values { item.dispose() }
    }
}

final class LongRunningTests: XCTestCase {
    private func drain(_ queue: Queue, _ check: @escaping () -> Void = {}) {
        let complete = expectation(description: "queue drained")
        queue.justDispatch { check(); complete.fulfill() }
        wait(for: [complete], timeout: 2)
    }

    private func block(_ queue: Queue) -> DispatchSemaphore {
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        queue.justDispatch { started.signal(); _ = release.wait(timeout: .now() + 3) }
        XCTAssertEqual(started.wait(timeout: .now() + 1), .success)
        return release
    }

    func testInitialHistoryPreparationKeepsAllUpdatesInOrder() {
        let values = Atomic<[Int]>(value: [])
        let fixture = HistoryFixture<Int> { value in _ = values.modify { $0 + [value] } }
        for value in 0 ..< 100 { fixture.history.putNext(value) }
        drain(fixture.queue) { XCTAssertEqual(values.with { $0 }, Array(0 ..< 100)) }
    }

    func testHistorySubscriptionReleasesRemovedController() {
        let pipe = ValuePipe<Int>()
        var received = 0
        var disposed = 0
        let source = pipe.signal() |> beforeNext { _ in received += 1 } |> afterDisposed { disposed += 1 }
        var owner: HistoryOwnerFixture? = HistoryOwnerFixture(source)
        weak var weakOwner = owner
        pipe.putNext(10)
        XCTAssertEqual(owner?.currentRanks, 10)
        owner = nil
        XCTAssertNil(weakOwner)
        XCTAssertEqual(disposed, 1)
        pipe.putNext(20)
        XCTAssertEqual(received, 1)
        weakOwner?.dispose()
    }

    func testHiddenHistoryRetainsOnlyLatestAndResumesOnce() {
        let live = Atomic(value: 0)
        let values = Atomic<[Int]>(value: [])
        let fixture = HistoryFixture<Payload> { value in _ = values.modify { $0 + [value.id] } }
        fixture.setVisible(false)
        let release = block(fixture.queue)
        for value in 0 ..< 5_000 { fixture.history.putNext(Payload(value, live: live)) }
        XCTAssertLessThanOrEqual(live.with { $0 }, 1)
        release.signal()
        drain(fixture.queue) { XCTAssertEqual(values.with { $0 }, []) }
        fixture.setVisible(true)
        drain(fixture.queue) { XCTAssertEqual(values.with { $0 }, [4_999]) }
        fixture.dispose()
        XCTAssertEqual(live.with { $0 }, 0)
    }

    func testQueuedOldHistoryCannotRenderAfterHideAndResume() {
        let values = Atomic<[Int]>(value: [])
        let fixture = HistoryFixture<Int> { value in _ = values.modify { $0 + [value] } }
        let release = block(fixture.queue)
        for value in 0 ..< 1_000 { fixture.history.putNext(value) }
        fixture.setVisible(false)
        fixture.history.putNext(1_000)
        fixture.setVisible(true)
        release.signal()
        drain(fixture.queue) { XCTAssertEqual(values.with { $0 }, [1_000]) }
    }

    func testHiddenPresentationUpdatesDoNotBuildHistory() {
        let count = Atomic(value: 0)
        let fixture = HistoryFixture<Int> { _ in _ = count.modify { $0 + 1 } }
        fixture.history.putNext(1)
        drain(fixture.queue)
        fixture.setVisible(false)
        for value in 1 ..< 1_000 { fixture.presentation.set(value) }
        drain(fixture.queue) { XCTAssertEqual(count.with { $0 }, 1) }
        fixture.setVisible(true)
        drain(fixture.queue) { XCTAssertEqual(count.with { $0 }, 2) }
    }

    func testOneHiddenChatDoesNotStopAnotherChat() {
        let first = HistoryFixture<Int> { _ in XCTFail("hidden chat rendered") }
        first.setVisible(false)
        let values = Atomic<[Int]>(value: [])
        let second = HistoryFixture<Int> { value in _ = values.modify { $0 + [value] } }
        first.history.putNext(1)
        second.history.putNext(2)
        drain(first.queue)
        drain(second.queue) { XCTAssertEqual(values.with { $0 }, [2]) }
    }

    func testDisposalRejectsQueuedHistoryUpdates() {
        let fixture = HistoryFixture<Int> { _ in XCTFail("disposed chat rendered") }
        let release = block(fixture.queue)
        fixture.history.putNext(1)
        fixture.dispose()
        release.signal()
        drain(fixture.queue)
    }

    func testHiddenStoriesDoNotStartPreload() {
        let visible = ValuePromise(false)
        var starts = 0
        let disposable = chatListVisibleStoryResources(visibility: visible.get(), hidden: .single(false), empty: [Int](), load: {
            starts += 1
            return .never()
        }).start()
        XCTAssertEqual(starts, 0)
        disposable.dispose()
    }

    func testHidingStoriesCancelsCurrentSubscriptionAndClearsResources() {
        let visible = ValuePromise(true)
        var cancellations = 0
        var results: [[Int]] = []
        let disposable = chatListVisibleStoryResources(visibility: visible.get(), hidden: .single(false), empty: [Int](), load: {
            Signal { subscriber in
                subscriber.putNext([1])
                return ActionDisposable { cancellations += 1 }
            }
        }).start(next: { results.append($0) })
        visible.set(false)
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(results, [[1], []])
        disposable.dispose()
    }

    func testQueuedStoryResultCannotRestartPreloadAfterHide() {
        let visible = ValuePromise(true)
        let pipe = ValuePipe<[Int]>()
        var results: [[Int]] = []
        let disposable = chatListVisibleStoryResources(visibility: visible.get(), hidden: .single(false), empty: [Int](), load: { pipe.signal() }).start(next: { results.append($0) })
        let queued = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { pipe.putNext([1]); queued.signal() }
        XCTAssertEqual(queued.wait(timeout: .now() + 1), .success)
        visible.set(false)
        let checked = expectation(description: "late story result rejected")
        DispatchQueue.main.async { XCTAssertEqual(results, [[]]); checked.fulfill() }
        wait(for: [checked], timeout: 1)
        disposable.dispose()
    }

    func testStoryVisibilityNoiseDoesNotDuplicateSubscriptions() {
        let visible = ValuePromise(true)
        let hidden = ValuePromise(false)
        var starts = 0
        var cancellations = 0
        let disposable = chatListVisibleStoryResources(visibility: visible.get(), hidden: hidden.get(), empty: [Int](), load: {
            starts += 1
            return Signal { _ in ActionDisposable { cancellations += 1 } }
        }).start()
        for _ in 0 ..< 1_000 { visible.set(true); hidden.set(false) }
        XCTAssertEqual(starts, 1)
        visible.set(false)
        visible.set(true)
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(cancellations, 1)
        disposable.dispose()
        XCTAssertEqual(cancellations, 2)
    }

    func testCancelledDelayedRemotePageDoesNotStartNetwork() {
        let fixture = RemoteFixture()
        let checked = expectation(description: "cancelled remote continuation")
        fixture.queue.async {
            let holder = fixture.start()
            fixture.account.network.subscribers[0].putNext(RegramMessageHistoryPage(messages: [], nextOffsetId: 50))
            fixture.activePreviewKeys.removeAll()
            fixture.remoteDisposables.removeValue(forKey: 1)
            holder.dispose()
            fixture.queue.after(0.1) {
                XCTAssertEqual(fixture.account.network.starts, 1)
                checked.fulfill()
            }
        }
        wait(for: [checked], timeout: 1)
    }

    func testReplacedRemoteRequestCannotBeFinishedByOldTimer() {
        let fixture = RemoteFixture()
        let checked = expectation(description: "replaced remote continuation")
        fixture.queue.async {
            let old = fixture.start()
            fixture.account.network.subscribers[0].putNext(RegramMessageHistoryPage(messages: [], nextOffsetId: 50))
            fixture.remoteDisposables.removeValue(forKey: 1)
            old.dispose()
            let current = fixture.start()
            fixture.account.network.automatic = RegramMessageHistoryPage(messages: [], nextOffsetId: nil)
            fixture.queue.after(0.1) {
                XCTAssertEqual(fixture.account.network.starts, 2)
                XCTAssertEqual(fixture.finishes, 0)
                XCTAssertTrue(fixture.remoteDisposables[1] === current)
                checked.fulfill()
            }
        }
        wait(for: [checked], timeout: 1)
    }

    func testInactiveRemoteRequestDoesNotStartNetwork() {
        let fixture = RemoteFixture()
        fixture.queue.async {
            fixture.activePreviewKeys.removeAll()
            _ = fixture.start()
        }
        drain(fixture.queue) { XCTAssertEqual(fixture.account.network.starts, 0) }
    }

    func testActiveRemotePaginationStillCompletes() {
        let fixture = RemoteFixture()
        let checked = expectation(description: "active remote pagination")
        fixture.queue.async {
            _ = fixture.start()
            fixture.account.network.subscribers[0].putNext(RegramMessageHistoryPage(messages: [], nextOffsetId: 50))
            fixture.queue.after(0.1) {
                XCTAssertEqual(fixture.account.network.starts, 2)
                fixture.account.network.subscribers[1].putNext(RegramMessageHistoryPage(messages: [Message(index: TestIndex(id: TestMessageId(peerId: 1, id: 40)), hidden: false)], nextOffsetId: nil))
                XCTAssertEqual(fixture.finishes, 1)
                XCTAssertNil(fixture.remoteDisposables[1])
                checked.fulfill()
            }
        }
        wait(for: [checked], timeout: 1)
    }

    func testHiddenScrollWorkCannotRunAfterReturning() {
        let fixture = ScrollFixture()
        fixture.schedule()
        fixture.hide()
        fixture.show()
        let checked = expectation(description: "old scroll work cancelled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            XCTAssertEqual(fixture.requests, 0)
            checked.fulfill()
        }
        wait(for: [checked], timeout: 1)
    }
}
