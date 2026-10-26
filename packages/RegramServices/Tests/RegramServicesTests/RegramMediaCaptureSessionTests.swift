import XCTest
@testable import RegramServices

final class RegramMediaCaptureSessionTests: XCTestCase {
    func testConstructionDoesNotOpenDevicesAndCancellationRejectsQueuedActions() {
        let session = RegramMediaCaptureSession { _ in XCTFail("Cancelled capture completed") }
        XCTAssertFalse(session.captureSession.isRunning)
        XCTAssertTrue(session.captureSession.inputs.isEmpty)
        XCTAssertTrue(session.captureSession.outputs.isEmpty)
        session.cancel()
        session.start()
        session.takePhoto()
        session.startRecording()
        session.stopRecording()
        session.cancel()
        let settled = expectation(description: "Queued cancellation settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertFalse(session.captureSession.isRunning)
            XCTAssertTrue(session.captureSession.inputs.isEmpty)
            XCTAssertTrue(session.captureSession.outputs.isEmpty)
            settled.fulfill()
        }
        wait(for: [settled], timeout: 2)
    }

    func testCancelledSessionReleasesAfterCleanup() {
        weak var released: RegramMediaCaptureSession?
        autoreleasepool {
            let session = RegramMediaCaptureSession { _ in XCTFail("Empty capture completed") }
            released = session
            session.cancel()
        }
        let settled = expectation(description: "Capture released")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertNil(released)
            settled.fulfill()
        }
        wait(for: [settled], timeout: 2)
    }
}
