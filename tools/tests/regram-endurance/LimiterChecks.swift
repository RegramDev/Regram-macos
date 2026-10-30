import Foundation
import SwiftSignalKit

private enum LimiterCheckError: Error { case failed }

func verify(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }
}

@main
struct LimiterChecks {
    static func main() {
        let limiter = RGTranslationRequestLimiter(limit: 3)
        let queue = Mirror(reflecting: limiter).children.first { $0.label == "queue" }!.value as! Queue
        func drain() { queue.sync {} }
        func count(_ name: String) -> Int {
            var result = 0
            queue.sync {
                let value = Mirror(reflecting: limiter).children.first { $0.label == name }!.value
                result = value as? Int ?? Mirror(reflecting: value).children.count
            }
            return result
        }
        let starts = Atomic(value: 0)
        let running = (0..<3).map { _ in
            limiter.limited(Signal<Void, NoError> { _ in
                _ = starts.modify { $0 + 1 }
                return EmptyDisposable
            }).start()
        }
        drain()
        verify(count("runningCount") == 3 && starts.with { $0 } == 3, "Expected three active operations")
        var maximumPendingAfterCancellation = 0
        let cycles = CommandLine.arguments.dropFirst().first.flatMap(Int.init) ?? 20
        for _ in 0..<cycles {
            let waiting = (0..<100).map { _ in
                limiter.limited(Signal<Void, NoError> { _ in
                    _ = starts.modify { $0 + 1 }
                    return EmptyDisposable
                }).start()
            }
            drain()
            verify(count("pending") == 100, "Expected one hundred waiting operations")
            waiting.forEach { $0.dispose() }
            drain()
            maximumPendingAfterCancellation = max(maximumPendingAfterCancellation, count("pending"))
            verify(count("pending") == 0, "Cancelled waiting entries remain retained behind active operations")
            verify(starts.with { $0 } == 3, "A cancelled waiting operation started")
        }
        running.forEach { $0.dispose() }
        drain()
        verify(count("runningCount") == 0 && count("pending") == 0, "Limiter failed to return to idle")
        let done = DispatchSemaphore(value: 0)
        let request = limiter.limited(Signal<Int, NoError>.single(1)).start(completed: { done.signal() })
        verify(done.wait(timeout: .now() + 3) == .success, "New work failed after repeated cancellation")
        request.dispose()
        drain()
        verify(count("runningCount") == 0, "Completed work retained a concurrency slot")
        let order = Atomic(value: [Int]())
        let controls = Atomic(value: [Int: Subscriber<Void, LimiterCheckError>]())
        let failures = Atomic(value: 0)
        let recovered = (0..<6).map { index in
            limiter.limited(Signal<Void, LimiterCheckError> { subscriber in
                _ = order.modify { $0 + [index] }
                _ = controls.modify { current in var next = current; next[index] = subscriber; return next }
                return EmptyDisposable
            }).start(error: { _ in _ = failures.modify { $0 + 1 } })
        }
        drain()
        verify(order.with { $0 } == [0, 1, 2], "The concurrency limit was exceeded")
        recovered[0].dispose()
        recovered[4].dispose()
        drain()
        controls.with { $0[1] }!.putError(.failed)
        drain()
        verify(order.with { $0 } == [0, 1, 2, 3, 5], "Cancellation or failure broke FIFO recovery")
        verify(failures.with { $0 } == 1, "Provider failure did not reach its caller")
        for index in [2, 3, 5] { controls.with { $0[index] }!.putCompletion() }
        drain()
        recovered.forEach { $0.dispose() }
        drain()
        verify(count("runningCount") == 0 && count("pending") == 0, "Mixed completion retained work")
        let report: [String: Any] = ["cycles": cycles, "cancelledWaitingOperations": cycles * 100, "maximumPendingAfterCancellation": maximumPendingAfterCancellation, "remainingActive": count("runningCount"), "remainingPending": count("pending"), "mixedFailureAndCancellationRecovery": true, "networkRequests": 0, "realAccountAccess": false]
        let data = try! JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8)!)
    }
}
