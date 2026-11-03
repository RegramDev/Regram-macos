import XCTest
import SwiftSignalKit
import RegramSignals

final class RegramSponsoredContentTests: XCTestCase {
    private struct Messages: Equatable {
        let fixed: Int?
        let dynamic: [Int]
        let version: Int

        static let empty = Messages(fixed: nil, dynamic: [], version: 0)
    }

    func testHiddenContentEmitsEmptyWithoutStartingOrWaitingForARequest() {
        let hidden = ValuePromise(true)
        var starts = 0
        var values: [[Int]] = []
        let disposable = regramSponsoredContent(hidden: hidden.get(), empty: [Int]()) {
            starts += 1
            return .never()
        }.start(next: { values.append($0) })
        XCTAssertEqual(starts, 0)
        XCTAssertEqual(values, [[]])
        disposable.dispose()
    }

    func testHidingClearsFixedAndDynamicAdsAndRestoresCurrentCacheWhenEnabled() {
        let hidden = ValuePromise(false)
        let initial = Messages(fixed: 1, dynamic: [2, 3], version: 4)
        let latest = Messages(fixed: 5, dynamic: [6], version: 7)
        let source = Promise(initial)
        var values: [Messages] = []
        let disposable = regramSponsoredContent(hidden: hidden.get(), empty: Messages.empty, source: source.get).start(next: { values.append($0) })
        hidden.set(true)
        source.set(.single(latest))
        XCTAssertEqual(values, [initial, .empty])
        hidden.set(false)
        XCTAssertEqual(values, [initial, .empty, latest])
        disposable.dispose()
    }

    func testHidingCancelsRequestsAndRejectsLateCallbacksFromPreviousRequests() {
        let hidden = ValuePromise(false)
        var callbacks: [([Int]) -> Void] = []
        var cancellations = 0
        var values: [[Int]] = []
        let disposable = regramSponsoredContent(hidden: hidden.get(), empty: [Int]()) {
            Signal { subscriber in
                callbacks.append { subscriber.putNext($0) }
                return ActionDisposable { cancellations += 1 }
            }
        }.start(next: { values.append($0) })
        XCTAssertEqual(callbacks.count, 1)
        callbacks[0]([1])
        hidden.set(true)
        XCTAssertEqual(cancellations, 1)
        callbacks[0]([2])
        XCTAssertEqual(values, [[1], []])
        hidden.set(false)
        XCTAssertEqual(callbacks.count, 2)
        callbacks[0]([3])
        callbacks[1]([4])
        XCTAssertEqual(values, [[1], [], [4]])
        disposable.dispose()
        XCTAssertEqual(cancellations, 2)
        callbacks[1]([5])
        hidden.set(true)
        XCTAssertEqual(values, [[1], [], [4]])
    }

    func testRepeatedVisibilityValuesDoNotRestartTheActiveRequest() {
        let hidden = ValuePromise(false, ignoreRepeated: false)
        var starts = 0
        var values: [[Int]] = []
        let disposable = regramSponsoredContent(hidden: hidden.get(), empty: [Int]()) {
            starts += 1
            return .single([starts])
        }.start(next: { values.append($0) })
        hidden.set(false)
        hidden.set(false)
        XCTAssertEqual(starts, 1)
        hidden.set(true)
        hidden.set(true)
        XCTAssertEqual(values, [[1], []])
        hidden.set(false)
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(values, [[1], [], [2]])
        disposable.dispose()
    }

    func testCompletedRequestStillRespondsToLaterPreferenceChanges() {
        let hidden = ValuePromise(false)
        var values: [Bool] = []
        let disposable = regramSponsoredContent(hidden: hidden.get(), empty: false, source: { .single(true) }).start(next: { values.append($0) })
        hidden.set(true)
        hidden.set(false)
        hidden.set(true)
        XCTAssertEqual(values, [true, false, true, false])
        disposable.dispose()
    }

    func testIndependentVisibilityStreamsDoNotAffectEachOther() {
        let first = ValuePromise(false)
        let second = ValuePromise(true)
        var firstValues: [[Int]] = []
        var secondValues: [[Int]] = []
        let firstDisposable = regramSponsoredContent(hidden: first.get(), empty: [Int](), source: { .single([1]) }).start(next: { firstValues.append($0) })
        let secondDisposable = regramSponsoredContent(hidden: second.get(), empty: [Int](), source: { .single([2]) }).start(next: { secondValues.append($0) })
        first.set(true)
        XCTAssertEqual(firstValues, [[1], []])
        XCTAssertEqual(secondValues, [[]])
        second.set(false)
        XCTAssertEqual(firstValues, [[1], []])
        XCTAssertEqual(secondValues, [[], [2]])
        firstDisposable.dispose()
        secondDisposable.dispose()
    }
}
