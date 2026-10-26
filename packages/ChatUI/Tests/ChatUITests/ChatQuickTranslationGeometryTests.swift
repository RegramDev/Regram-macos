import AppKit
import XCTest
@testable import ChatUI

final class ChatQuickTranslationGeometryTests: XCTestCase {
    func testTranslationStacksAboveUnmovedNativeShareAnchorForShortAndTallBubbles() {
        let heights: [CGFloat] = [ChatRowGeometry.translationStackMinimumHeight, 120, 300]
        let widths: [CGFloat] = [160, 400]
        for height in heights {
            for rowWidth in widths {
                let bubble = ChatRowGeometry.bubbleFrame(.init(rowWidth: rowWidth, layoutFrame: CGRect(x: 10, y: 2, width: max(40, rowWidth - 70), height: height - 4), leftInset: 0, isIncoming: true, isCenteredThread: false))
                let nativePoint = CGPoint(x: bubble.maxX + 10, y: bubble.maxY - 34.65 + 3)
                let share = CGRect(origin: nativePoint, size: CGSize(width: 31.5, height: 31.5))
                let translation = ChatRowGeometry.quickTranslationFrame(shareFrame: share, stacked: true, rowHeight: height)
                XCTAssertEqual(share.origin, nativePoint)
                XCTAssertEqual(translation.midX, share.midX)
                XCTAssertEqual(translation.maxY + 4, share.minY, accuracy: 0.01)
                XCTAssertGreaterThanOrEqual(translation.minY, 0)
                XCTAssertLessThanOrEqual(share.maxY, height)
                XCTAssertLessThanOrEqual(translation.maxX, rowWidth)
            }
        }
    }

    func testSingleTranslationAndListStackRemainInsideOwnRow() {
        let single = ChatRowGeometry.quickTranslationFrame(shareFrame: CGRect(x: 100, y: -3, width: 31.5, height: 31.5), stacked: false, rowHeight: 40)
        XCTAssertEqual(single.minY, 0)
        XCTAssertLessThanOrEqual(single.maxY, 40)
        let share = CGRect(x: 100, y: 34, width: 31.5, height: 31.5)
        let stacked = ChatRowGeometry.quickTranslationFrame(shareFrame: share, stacked: true, rowHeight: ChatRowGeometry.translationStackMinimumHeight)
        XCTAssertEqual(stacked.midX, share.midX)
        XCTAssertEqual(stacked.minY, 0)
        XCTAssertFalse(stacked.intersects(share))
    }
}
