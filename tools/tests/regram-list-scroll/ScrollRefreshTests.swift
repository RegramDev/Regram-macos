import Foundation
import XCTest
import SwiftSignalKit

final class ScrollRefreshTests: XCTestCase {
    private func run(_ queue: Queue, _ body: @escaping () -> Void = {}) {
        let done = expectation(description: "queue processed")
        queue.justDispatch { body(); done.fulfill() }
        wait(for: [done], timeout: 3)
    }

    private func settle(_ queue: Queue, _ body: @escaping () -> Void) {
        let done = expectation(description: "scroll settled")
        queue.after(0.23) { body(); done.fulfill() }
        wait(for: [done], timeout: 3)
    }

    func testInitialRefreshWaitsForScrollingToSettle() {
        let queue = Queue(name: "initialScrollRefresh")
        let events = ValuePipe<Void>()
        let count = Atomic(value: 0)
        let disposable = chatListSettledScrollUpdates(events.signal(), visibility: .single(true), queue: queue).start(next: { _ = count.modify { $0 + 1 } })
        run(queue) { XCTAssertEqual(count.with { $0 }, 0) }
        settle(queue) { XCTAssertEqual(count.with { $0 }, 1) }
        disposable.dispose()
    }

    func testRapidVisibleRangeChangesRefreshLatestPeersOnce() {
        let queue = Queue(name: "rapidScrollRefresh")
        let events = ValuePipe<Void>()
        let current = Atomic(value: 0)
        let received = Atomic<[Int]>(value: [])
        let disposable = chatListSettledScrollUpdates(events.signal(), visibility: .single(true), queue: queue).start(next: {
            let value = current.with { $0 }
            _ = received.modify { $0 + [value] }
        })
        run(queue) {
            for value in 1...500 {
                _ = current.swap(value)
                events.putNext(())
            }
        }
        settle(queue) { XCTAssertEqual(received.with { $0 }, [500]) }
        disposable.dispose()
    }

    func testHiddenListDoesNotRefreshPeers() {
        let queue = Queue(name: "hiddenScrollRefresh")
        let events = ValuePipe<Void>()
        let count = Atomic(value: 0)
        let disposable = chatListSettledScrollUpdates(events.signal(), visibility: .single(false), queue: queue).start(next: { _ = count.modify { $0 + 1 } })
        run(queue) { for _ in 0..<500 { events.putNext(()) } }
        settle(queue) { XCTAssertEqual(count.with { $0 }, 0) }
        disposable.dispose()
    }

    func testHidingListCancelsPendingRefresh() {
        let queue = Queue(name: "cancelledScrollRefresh")
        let events = ValuePipe<Void>()
        let visible = ValuePromise(true)
        let count = Atomic(value: 0)
        let disposable = chatListSettledScrollUpdates(events.signal(), visibility: visible.get(), queue: queue).start(next: { _ = count.modify { $0 + 1 } })
        run(queue) { events.putNext(()); visible.set(false) }
        settle(queue) { XCTAssertEqual(count.with { $0 }, 0) }
        disposable.dispose()
    }

    func testReturningListRefreshesCurrentPeersOnce() {
        let queue = Queue(name: "returningScrollRefresh")
        let events = ValuePipe<Void>()
        let visible = ValuePromise(true)
        let current = Atomic(value: 1)
        let received = Atomic<[Int]>(value: [])
        let disposable = chatListSettledScrollUpdates(events.signal(), visibility: visible.get(), queue: queue).start(next: {
            let value = current.with { $0 }
            _ = received.modify { $0 + [value] }
        })
        run(queue) {
            events.putNext(())
            visible.set(false)
            _ = current.swap(2)
            events.putNext(())
            visible.set(true)
        }
        settle(queue) { XCTAssertEqual(received.with { $0 }, [2]) }
        disposable.dispose()
    }

    func testDisposalCancelsPendingRefresh() {
        let queue = Queue(name: "disposedScrollRefresh")
        let events = ValuePipe<Void>()
        let count = Atomic(value: 0)
        let disposable = chatListSettledScrollUpdates(events.signal(), visibility: .single(true), queue: queue).start(next: { _ = count.modify { $0 + 1 } })
        run(queue)
        disposable.dispose()
        settle(queue) { XCTAssertEqual(count.with { $0 }, 0) }
    }

    func testSeparateScrollBurstsEachRefresh() {
        let queue = Queue(name: "separateScrollRefresh")
        let events = ValuePipe<Void>()
        let count = Atomic(value: 0)
        let disposable = chatListSettledScrollUpdates(events.signal(), visibility: .single(true), queue: queue).start(next: { _ = count.modify { $0 + 1 } })
        run(queue) { for _ in 0..<100 { events.putNext(()) } }
        settle(queue) { XCTAssertEqual(count.with { $0 }, 1) }
        run(queue) { for _ in 0..<100 { events.putNext(()) } }
        settle(queue) { XCTAssertEqual(count.with { $0 }, 2) }
        disposable.dispose()
    }

    func testVisibilityNoiseDoesNotRestartRefresh() {
        let queue = Queue(name: "visibilityScrollRefresh")
        let events = ValuePipe<Void>()
        let visible = ValuePromise(true)
        let count = Atomic(value: 0)
        let disposable = chatListSettledScrollUpdates(events.signal(), visibility: visible.get(), queue: queue).start(next: { _ = count.modify { $0 + 1 } })
        run(queue) { for _ in 0..<100 { visible.set(true) } }
        settle(queue) { XCTAssertEqual(count.with { $0 }, 1) }
        run(queue) { for _ in 0..<100 { visible.set(true) } }
        settle(queue) { XCTAssertEqual(count.with { $0 }, 1) }
        disposable.dispose()
    }
}
