import Foundation
import RegramCore
import SwiftSignalKit
import XCTest
@testable import RegramServices

private final class TranscriptionPayload {
    var calls = 0
    let bytes = Data(repeating: 1, count: 4096)
}

private final class WeakTranscriptionPayload {
    weak var value: TranscriptionPayload?
    init(_ value: TranscriptionPayload) { self.value = value }
}

private final class RetainedTranscriptionRequest {
    let key: RegramTranscriptionTaskKey
    let isCurrent: () -> Bool
    let complete: () -> Void
    let fail: () -> Void

    init(key: RegramTranscriptionTaskKey, isCurrent: @escaping () -> Bool, subscriber: Subscriber<Void, RGTranscriptionError>) {
        self.key = key
        self.isCurrent = isCurrent
        complete = { subscriber.putCompletion() }
        fail = { subscriber.putError(.cancelled) }
    }
}

final class RegramTaskRetentionTests: XCTestCase {
    private func exerciseCompletionBurst(failing: Bool) {
        let tasks = RegramTranscriptionTasks()
        var snapshots: [RegramTranscriptionTaskSnapshot] = []
        let observation = tasks.signal(accountId: 77).start(next: { snapshots = $0 })
        defer { observation.dispose() }
        var finishers: [() -> Void] = []
        var requests: [Disposable] = []
        var payloads: [WeakTranscriptionPayload] = []
        for index in 0..<400 {
            autoreleasepool {
                let payload = TranscriptionPayload()
                payloads.append(WeakTranscriptionPayload(payload))
                let key = RegramTranscriptionTaskKey(accountId: 77, messageId: RGBookmarkMessageId(peerId: 2, namespace: 0, id: Int32(index)))
                requests.append(tasks.perform(key: key, revision: 1) { _ in
                    payload.calls += 1
                    return Signal { subscriber in
                        finishers.append {
                            if failing { subscriber.putError(.cancelled) }
                            else { subscriber.putCompletion() }
                        }
                        return EmptyDisposable
                    }
                }.start())
            }
        }
        XCTAssertEqual(snapshots.filter { $0.state == .running }.count, 400)
        finishers.forEach { $0() }
        finishers.removeAll()
        requests.forEach { $0.dispose() }
        requests.removeAll()
        XCTAssertLessThanOrEqual(snapshots.count, 100, "Finished history must be bounded without waiting for another task")
        XCTAssertFalse(snapshots.contains { $0.state == .running })
        XCTAssertLessThanOrEqual(payloads.filter { $0.value != nil }.count, 100, "Evicted task operations must release their captured message payloads")
        tasks.clearFinished(accountId: 77)
        XCTAssertTrue(snapshots.isEmpty)
        XCTAssertTrue(payloads.allSatisfy { $0.value == nil })
    }

    func testCompletedBurstReleasesOldPayloadsWithoutAnotherRequest() {
        exerciseCompletionBurst(failing: false)
    }

    func testFailedBurstReleasesOldPayloadsWithoutAnotherRequest() {
        exerciseCompletionBurst(failing: true)
    }

    func testRetainedHistoryStillRetriesAndDoesNotEvictRunningTasks() {
        let tasks = RegramTranscriptionTasks()
        var starts = 0
        let runningKey = RegramTranscriptionTaskKey(accountId: 77, messageId: RGBookmarkMessageId(peerId: 2, namespace: 0, id: -1))
        let running = tasks.perform(key: runningKey, revision: 2) { _ in .never() }.start()
        defer { running.dispose(); tasks.cancelAccount(77) }
        for index in 0..<150 {
            let key = RegramTranscriptionTaskKey(accountId: 77, messageId: RGBookmarkMessageId(peerId: 2, namespace: 0, id: Int32(index)))
            let request = tasks.perform(key: key, revision: 3) { _ in starts += 1; return .complete() }.start()
            request.dispose()
        }
        XCTAssertEqual(tasks.snapshot(runningKey)?.state, .running)
        let retryKey = RegramTranscriptionTaskKey(accountId: 77, messageId: RGBookmarkMessageId(peerId: 2, namespace: 0, id: 149))
        tasks.retry(retryKey)
        XCTAssertEqual(starts, 151)
        XCTAssertEqual(tasks.snapshot(retryKey)?.state, .completed)
    }

    func testRepeatedSuspendRetryCancelAndAccountCleanupReleaseWork() {
        let tasks = RegramTranscriptionTasks()
        var snapshots: [Int64: [RegramTranscriptionTaskSnapshot]] = [:]
        let observations = [Int64(77), 78].map { accountId in
            tasks.signal(accountId: accountId).start(next: { snapshots[accountId] = $0 })
        }
        defer { observations.forEach { $0.dispose() } }
        var active = 0
        var starts = 0
        for cycle in 0..<500 {
            var payloads: [WeakTranscriptionPayload] = []
            autoreleasepool {
                var callbacks: [RetainedTranscriptionRequest] = []
                var requests: [Disposable] = []
                let keys = [Int64(77), 78].map { accountId in
                    RegramTranscriptionTaskKey(accountId: accountId, messageId: RGBookmarkMessageId(peerId: 2, namespace: 0, id: Int32(cycle)))
                }
                for key in keys {
                    let payload = TranscriptionPayload()
                    payloads.append(WeakTranscriptionPayload(payload))
                    requests.append(tasks.perform(key: key, revision: 1) { isCurrent in
                        payload.calls += 1
                        return Signal { subscriber in
                            starts += 1
                            active += 1
                            callbacks.append(RetainedTranscriptionRequest(key: key, isCurrent: isCurrent, subscriber: subscriber))
                            return ActionDisposable { active -= 1 }
                        }
                    }.start())
                }
                XCTAssertEqual(active, 2)
                XCTAssertEqual(callbacks.count, 2)
                tasks.suspend()
                XCTAssertEqual(active, 0)
                XCTAssertTrue(callbacks.allSatisfy { !$0.isCurrent() })
                XCTAssertTrue(keys.allSatisfy { tasks.snapshot($0)?.state == .interrupted })
                tasks.clearFinished(accountId: 77)
                XCTAssertEqual(tasks.snapshot(keys[0])?.state, .interrupted)
                tasks.resume()
                XCTAssertEqual(callbacks.count, 4)
                XCTAssertEqual(active, 2)
                callbacks[0].complete()
                callbacks[1].fail()
                XCTAssertTrue(keys.allSatisfy { tasks.snapshot($0)?.state == .running })
                let cancelledAttempt = callbacks.last { $0.key == keys[0] }!
                let finishedAttempt = callbacks.last { $0.key == keys[1] }!
                tasks.cancel(keys[0])
                XCTAssertFalse(cancelledAttempt.isCurrent())
                cancelledAttempt.complete()
                XCTAssertEqual(tasks.snapshot(keys[0])?.state, .cancelled)
                if cycle.isMultiple(of: 2) { finishedAttempt.complete() }
                else { finishedAttempt.fail() }
                XCTAssertEqual(active, 0)
                XCTAssertEqual(tasks.snapshot(keys[1])?.state, cycle.isMultiple(of: 2) ? .completed : .failed)
                for accountId in [Int64(77), 78] { tasks.cancelAccount(accountId) }
                requests.forEach { $0.dispose() }
                requests.removeAll()
                callbacks.removeAll()
            }
            XCTAssertTrue(payloads.allSatisfy { $0.value == nil }, "Payloads survived cycle \(cycle)")
            XCTAssertTrue(snapshots.values.allSatisfy(\.isEmpty))
        }
        XCTAssertEqual(active, 0)
        XCTAssertEqual(starts, 2000)
    }
}
