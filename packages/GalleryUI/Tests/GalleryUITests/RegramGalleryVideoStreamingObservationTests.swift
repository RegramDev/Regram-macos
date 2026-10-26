import XCTest
@testable import GalleryUI

final class RegramGalleryVideoStreamingObservationTests: XCTestCase {
    func testUnloadedAndNonstreamingPlayersNeverEvaluateLazyStatusProvider() {
        let observation = RegramGalleryVideoStreamingObservation()
        var statusReads = 0
        let status: (@escaping (Bool) -> Void) -> (() -> Void) = { _ in
            statusReads += 1
            XCTFail("Status cannot be read before the native player exists")
            return {}
        }
        observation.start(playerIsLoaded: false, isStreamable: true, observe: status, acquirePriority: { {} })
        observation.start(playerIsLoaded: true, isStreamable: false, observe: status, acquirePriority: { {} })
        XCTAssertEqual(statusReads, 0)
    }

    func testPlayerReadinessStartsOnceAndPlaybackOwnsPriorityUntilPause() {
        let observation = RegramGalleryVideoStreamingObservation()
        var playerExists = false
        var statusReads = 0
        var update: ((Bool) -> Void)?
        var acquisitions = 0
        var releases = 0
        let status: (@escaping (Bool) -> Void) -> (() -> Void) = { callback in
            XCTAssertTrue(playerExists)
            statusReads += 1
            update = callback
            callback(true)
            return {}
        }
        let acquire: () -> (() -> Void) = {
            acquisitions += 1
            return { releases += 1 }
        }
        observation.start(playerIsLoaded: playerExists, isStreamable: true, observe: status, acquirePriority: acquire)
        playerExists = true
        observation.start(playerIsLoaded: playerExists, isStreamable: true, observe: status, acquirePriority: acquire)
        observation.start(playerIsLoaded: playerExists, isStreamable: true, observe: status, acquirePriority: acquire)
        update?(true)
        update?(true)
        XCTAssertEqual(statusReads, 1)
        XCTAssertEqual(acquisitions, 1)
        XCTAssertEqual(releases, 0)
        update?(false)
        update?(false)
        XCTAssertEqual(releases, 1)
        update?(true)
        XCTAssertEqual(acquisitions, 2)
    }

    func testItemLifetimeKeepsObservationAliveAndDisposesPlayingLeaseOnce() {
        var observation: RegramGalleryVideoStreamingObservation? = RegramGalleryVideoStreamingObservation()
        var update: ((Bool) -> Void)?
        var cancellations = 0
        var acquisitions = 0
        var releases = 0
        observation?.start(playerIsLoaded: true, isStreamable: true, observe: { callback in
            update = callback
            callback(true)
            return { cancellations += 1 }
        }, acquirePriority: {
            acquisitions += 1
            return { releases += 1 }
        })
        update?(true)
        XCTAssertEqual(cancellations, 0)
        XCTAssertEqual(releases, 0)
        observation = nil
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(releases, 1)
        update?(false)
        update?(true)
        XCTAssertEqual(acquisitions, 1)
        XCTAssertEqual(releases, 1)
    }
}
