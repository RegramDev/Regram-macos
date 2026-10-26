import AppKit
import XCTest
@testable import ChatUI

final class ChatTextSendFlightGeometryTests: XCTestCase {
    private func fixedFont(_ size: CGFloat) -> NSFont {
        NSFont(name: "Menlo", size: size) ?? NSFont.userFixedPitchFont(ofSize: size) ?? NSFont.systemFont(ofSize: size)
    }

    private func geometry(date: String, bodyFont: NSFont, dateFont: NSFont) -> ChatRowGeometry.SendFlightTarget {
        let body = NSAttributedString(string: "1", attributes: [.font: bodyFont]).size()
        let date = NSAttributedString(string: date, attributes: [.font: dateFont]).size()
        let timestampSize = NSSize(width: ceil(date.width) + 20, height: 16)
        let bubble = ChatRowGeometry.bubbleFrame(.init(rowWidth: 400, layoutFrame: NSRect(x: 0, y: 2, width: ceil(body.width) + timestampSize.width + 42, height: 52), leftInset: 42, isIncoming: false, isCenteredThread: false))
        let content = ChatRowGeometry.contentFrame(.init(offset: NSPoint(x: 0, y: 8), size: NSSize(width: ceil(body.width), height: ceil(body.height)), bubbleFrame: bubble, isBubbled: true, isIncoming: false, bubbleInset: 18, additionInset: 6))
        var timestamp = ChatRowGeometry.Timestamp()
        timestamp.rowWidth = 400
        timestamp.size = timestampSize
        timestamp.bubbleFrame = bubble
        timestamp.contentFrame = content
        timestamp.isBubbled = true
        timestamp.hasBubble = true
        timestamp.bubbleInset = 18
        timestamp.additionInset = 6
        return .init(rowFrame: NSRect(x: 0, y: 0, width: 400, height: 56), bubbleFrame: bubble, contentFrame: content, timestampFrame: ChatRowGeometry.timestampFrame(timestamp))
    }

    func testServerMessageIdGrowthWouldClipBothShortTextAndTimestampWithOldFlightMask() {
        for font in [NSFont.systemFont(ofSize: 13), fixedFont(13)] {
            let pending = geometry(date: "#1 10:36:10 PM", bodyFont: font, dateFont: font)
            let delivered = geometry(date: "#305981 10:36:10 PM", bodyFont: font, dateFont: font)
            XCTAssertEqual(pending.rowFrame, delivered.rowFrame)
            XCTAssertLessThan(delivered.bubbleFrame.minX, pending.bubbleFrame.minX)
            XCTAssertFalse(pending.bubbleFrame.contains(delivered.contentFrame))
            XCTAssertFalse(pending.bubbleFrame.contains(delivered.timestampFrame))
            XCTAssertTrue(delivered.bubbleFrame.contains(delivered.contentFrame))
            XCTAssertTrue(delivered.bubbleFrame.contains(delivered.timestampFrame))
            XCTAssertFalse(pending.canContinue(with: delivered, sameItem: true))
        }
    }

    func testMessageIdSecondsAndSelectedFontChangesInvalidateUnchangedRowBounds() {
        let original = geometry(date: "10:36 PM", bodyFont: .systemFont(ofSize: 13), dateFont: .systemFont(ofSize: 11))
        let seconds = geometry(date: "10:36:10 PM", bodyFont: .systemFont(ofSize: 13), dateFont: .systemFont(ofSize: 11))
        let identifier = geometry(date: "#305981 10:36:10 PM", bodyFont: .systemFont(ofSize: 13), dateFont: .systemFont(ofSize: 11))
        let selectedFont = geometry(date: "#305981 10:36:10 PM", bodyFont: fixedFont(19), dateFont: fixedFont(15))
        for changed in [seconds, identifier, selectedFont] {
            XCTAssertEqual(original.rowFrame, changed.rowFrame)
            XCTAssertFalse(original.canContinue(with: changed, sameItem: true))
        }
        XCTAssertTrue(original.canContinue(with: original, sameItem: true))
    }

    func testReboundRowsAndTimestampOnlyLayoutChangesEndFlight() {
        let original = geometry(date: "#305981 10:36:10 PM", bodyFont: .systemFont(ofSize: 13), dateFont: .systemFont(ofSize: 11))
        XCTAssertFalse(original.canContinue(with: original, sameItem: false))
        let changed = ChatRowGeometry.SendFlightTarget(rowFrame: original.rowFrame, bubbleFrame: original.bubbleFrame, contentFrame: original.contentFrame, timestampFrame: original.timestampFrame.insetBy(dx: -4, dy: 0))
        XCTAssertFalse(original.canContinue(with: changed, sameItem: true))
        let moved = ChatRowGeometry.SendFlightTarget(rowFrame: original.rowFrame.offsetBy(dx: 0, dy: 20), bubbleFrame: original.bubbleFrame, contentFrame: original.contentFrame, timestampFrame: original.timestampFrame)
        XCTAssertFalse(original.canContinue(with: moved, sameItem: true))
    }
}
