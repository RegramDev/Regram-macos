import AppKit
import XCTest
import SwiftSignalKit

private struct DiagnosticsState {
    var revision: Int64 = 0
    var testing = false
}

private final class Benchmark {
    var running = false
    func cancel() { running = false }
}

private final class InputDataController {
    var didAppear: ((InputDataController) -> Void)?
    var willDisappear: ((InputDataController) -> Void)?
    var onDeinit: (() -> Void)?
}

private struct DiagnosticsHarness {
    let appear: () -> Void
    let disappear: () -> Void
    let activate: (Bool) -> Void
    let revision: () -> Int64
    let begin: () -> Void
    let benchmarking: () -> Bool
    let dispose: () -> Void
}

private func makeDiagnostics() -> DiagnosticsHarness {
    var active = true
    var state = DiagnosticsState()
    let benchmark = Benchmark()
    func update(_ transform: (inout DiagnosticsState) -> Void) { transform(&state) }
    __LIFECYCLE__
    let controller = InputDataController()
    __BINDINGS__
    return DiagnosticsHarness(appear: { controller.didAppear?(controller) }, disappear: { controller.willDisappear?(controller) }, activate: { value in
        active = value
        NotificationCenter.default.post(name: value ? NSApplication.didBecomeActiveNotification : NSApplication.didResignActiveNotification, object: nil)
    }, revision: { state.revision }, begin: { benchmark.running = true; state.testing = true }, benchmarking: { benchmark.running }, dispose: { controller.onDeinit?() })
}

final class PerformanceAuditTests: XCTestCase {
    private func runTimers(_ interval: TimeInterval = 0.06) {
        RunLoop.main.run(until: Date().addingTimeInterval(interval))
    }

    func testDiagnosticsOnlyRefreshesWhileVisibleAndActive() {
        let harness = makeDiagnostics()
        defer { harness.dispose() }
        runTimers()
        XCTAssertEqual(harness.revision(), 0)
        harness.appear()
        XCTAssertEqual(harness.revision(), 1)
        runTimers()
        XCTAssertGreaterThan(harness.revision(), 1)
        harness.begin()
        harness.disappear()
        XCTAssertFalse(harness.benchmarking())
        let hidden = harness.revision()
        runTimers()
        XCTAssertEqual(harness.revision(), hidden)
        harness.activate(false)
        harness.activate(true)
        runTimers()
        XCTAssertEqual(harness.revision(), hidden)
        harness.appear()
        XCTAssertEqual(harness.revision(), hidden + 1)
        harness.activate(false)
        let inactive = harness.revision()
        runTimers()
        XCTAssertEqual(harness.revision(), inactive)
        harness.activate(true)
        XCTAssertEqual(harness.revision(), inactive + 1)
        runTimers()
        XCTAssertGreaterThan(harness.revision(), inactive + 1)
    }

    func testRepeatedAppearanceDoesNotMultiplyTimersAndCleanupStopsNotifications() {
        let harness = makeDiagnostics()
        for _ in 0..<100 { harness.appear(); harness.activate(true) }
        XCTAssertEqual(harness.revision(), 1)
        runTimers()
        XCTAssertLessThanOrEqual(harness.revision(), 9)
        harness.dispose()
        let stopped = harness.revision()
        harness.activate(false)
        harness.activate(true)
        runTimers()
        XCTAssertEqual(harness.revision(), stopped)
    }

    private func imageData() -> Data {
        Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==")!
    }

    func testHistoryImageLoadsOffMainAndReturnsOriginalBytes() throws {
        let bytes = imageData()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let done = expectation(description: "image")
        let disposable = (regramLoadHistoryImage(path: url.path, maximumBytes: bytes.count, shouldLoad: {
            XCTAssertFalse(Thread.isMainThread)
            return true
        }) |> deliverOnMainQueue).start(next: { result in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(result?.0, bytes)
            XCTAssertEqual(result?.1.size, NSSize(width: 1, height: 1))
            done.fulfill()
        })
        wait(for: [done], timeout: 3)
        disposable.dispose()
    }

    func testHistoryImageRejectsMissingOversizeAndCancelledSources() throws {
        let bytes = imageData()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        for (path, maximum, allowed) in [(url.path, bytes.count - 1, true), (url.path, bytes.count, false), (url.path + ".missing", bytes.count, true)] {
            let done = expectation(description: "rejected")
            let disposable = regramLoadHistoryImage(path: path, maximumBytes: maximum, shouldLoad: { allowed }).start(next: { result in
                XCTAssertNil(result)
            }, completed: { done.fulfill() })
            wait(for: [done], timeout: 3)
            disposable.dispose()
        }
    }

    func testCachedHistoryPreparationRunsOffMainAndSkipsObsoleteWork() {
        let done = expectation(description: "prepared")
        let bytes = imageData()
        let disposable = regramPrepareHistoryImages({
            XCTAssertFalse(Thread.isMainThread)
            return [0: bytes, 1: Data("invalid".utf8), 2: bytes]
        }, shouldLoad: { true }).start(next: { images in
            XCTAssertEqual(Set(images.keys), Set([0, 2]))
            done.fulfill()
        })
        wait(for: [done], timeout: 3)
        disposable.dispose()
        let cancelled = expectation(description: "obsolete")
        let obsolete = regramPrepareHistoryImages({
            XCTFail("obsolete load must not read the cache")
            return [:]
        }, shouldLoad: { false }).start(next: { images in
            XCTAssertTrue(images.isEmpty)
            cancelled.fulfill()
        })
        wait(for: [cancelled], timeout: 3)
        obsolete.dispose()
    }

    func testDisposedHistoryPreparationDoesNotDeliverLateResults() {
        let started = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = expectation(description: "worker finished")
        let delivered = expectation(description: "cancelled delivery")
        delivered.isInverted = true
        let disposable = regramPrepareHistoryImages({
            started.signal()
            _ = release.wait(timeout: .now() + 2)
            finished.fulfill()
            return [:]
        }, shouldLoad: { true }).start(next: { _ in delivered.fulfill() })
        XCTAssertEqual(started.wait(timeout: .now() + 2), .success)
        disposable.dispose()
        release.signal()
        wait(for: [finished, delivered], timeout: 0.2)
    }
}
