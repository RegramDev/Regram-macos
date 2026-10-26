import XCTest
@testable import RegramCore

final class RegramMediaLoadingPolicyTests: XCTestCase {
    func testManualSlotAndVisibleOrderingLeaveStreamingHeadroom() {
        let candidates: [RegramMediaFetchCandidate] = [
            .init(resourceId: "manual", isUserInitiated: true),
            .init(resourceId: "queuedManual", isUserInitiated: true),
            .init(resourceId: "background"),
            .init(resourceId: "visible2"),
            .init(resourceId: "preload", isForegroundPrefetch: true),
            .init(resourceId: "visible1"),
            .init(resourceId: "paused", isPaused: true)
        ]
        XCTAssertEqual(RegramMediaLoadingPolicy.selectedResources(candidates: candidates, visible: ["visible1", "visible2"], preload: ["preload"], streaming: []), ["manual", "visible1", "visible2"])
        XCTAssertEqual(RegramMediaLoadingPolicy.selectedResources(candidates: candidates, visible: ["visible2"], preload: ["preload"], streaming: ["directStream"]), ["manual", "visible2"])
        XCTAssertEqual(RegramMediaLoadingPolicy.selectedResources(candidates: candidates, visible: [], preload: ["preload"], streaming: ["directStream"]), ["manual"])
        XCTAssertEqual(RegramMediaLoadingPolicy.selectedResources(candidates: candidates, visible: ["paused"], preload: [], streaming: ["preload"]), ["manual", "preload"])
    }

    func testCoveredScreensAndSharedStreamingOwnersReleaseIndependently() {
        var state = RegramMediaPriorityState()
        XCTAssertTrue(state.updateScreen(owner: 1, visible: ["a", "a"], preload: ["p"]))
        XCTAssertTrue(state.updateScreen(owner: 2, visible: ["b"], preload: []))
        XCTAssertFalse(state.updateScreen(owner: 1, visible: ["a"], preload: ["p"]))
        XCTAssertEqual(state.visible, ["b"])
        XCTAssertTrue(state.updateScreen(owner: 1, visible: [], preload: []))
        XCTAssertEqual(state.visible, ["b"])
        state.acquireStreaming("stream")
        state.acquireStreaming("stream")
        state.releaseStreaming("stream")
        XCTAssertEqual(state.streaming, ["stream"])
        XCTAssertEqual(state.weights(enabled: true)["stream"], 100)
        XCTAssertTrue(state.weights(enabled: false).isEmpty)
        state.releaseStreaming("stream")
        XCTAssertTrue(state.streaming.isEmpty)
        XCTAssertTrue(state.updateScreen(owner: 2, visible: [], preload: []))
        XCTAssertTrue(state.visible.isEmpty)
    }

    func testPreloadRescueRejectsOldTimerAndBoundsRetainedJobs() {
        var retention = RegramMediaPreloadRetention<String>()
        let first = retention.deferRemoval("a", now: 10)
        XCTAssertFalse(retention.expire("a", ticket: first.ticket, now: 11))
        retention.rescue("a")
        let replacement = retention.deferRemoval("a", now: 11)
        XCTAssertNotEqual(first.ticket.generation, replacement.ticket.generation)
        XCTAssertFalse(retention.expire("a", ticket: first.ticket, now: 100))
        _ = retention.deferRemoval("b", now: 11)
        _ = retention.deferRemoval("c", now: 11)
        let overflow = retention.deferRemoval("d", now: 11)
        XCTAssertEqual(overflow.evicted, ["a"])
        XCTAssertEqual(retention.pending.count, 3)
        XCTAssertTrue(retention.expire("d", ticket: overflow.ticket, now: 12.5))
        retention.reset()
        XCTAssertTrue(retention.pending.isEmpty)
    }

    func testInlinePlaybackPrioritizesAudibleOwnerAndVisibleCenter() {
        func candidate(_ id: Int64, distance: Double, visible: Double = 1, sound: Bool = false) -> RegramInlineVideoCandidate {
            .init(id: id, stableId: id, eligible: true, visibleFraction: visible, distanceFromCenter: distance, userInitiated: sound, hasSound: sound, alreadyAdmitted: false)
        }
        let candidates = [candidate(1, distance: 1), candidate(2, distance: 100, sound: true), candidate(3, distance: 2), candidate(4, distance: 0, visible: 0)]
        XCTAssertEqual(RegramMediaLoadingPolicy.selectedInlineVideos(candidates, active: true, thermalCritical: false), [2, 1])
        XCTAssertTrue(RegramMediaLoadingPolicy.selectedInlineVideos(candidates, active: false, thermalCritical: false).isEmpty)
        XCTAssertTrue(RegramMediaLoadingPolicy.selectedInlineVideos(candidates, active: true, thermalCritical: true).isEmpty)
    }
}
