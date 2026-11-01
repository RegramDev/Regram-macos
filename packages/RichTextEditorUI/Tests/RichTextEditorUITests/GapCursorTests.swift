#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class GapCursorTests: AppKitTestCase {
    private func canvas() -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.mediaBlockViewProvider = { _, _, _, width in
            NSView(frame: CGRect(x: 0, y: 0, width: width, height: 50))
        }
        v.setModelBlocks([
            .core(.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Above")]))),
            .media(MediaBlock(id: BlockID("img"), kind: .image, mediaID: "x", naturalSize: Size2D(width: 80, height: 50),
                              caption: [TextRun(text: "Cap")])),
        ], width: 300)
        v.frame = CGRect(x: 0, y: 0, width: 300, height: 300); v.layoutSubtreeIfNeeded()
        return v
    }

    func test_gapPositionIsImageNodeStart_andHasNoTextBox() {
        let v = canvas()
        let img = v.boxes[1]
        XCTAssertNil(v.box(containingGlobal: img.nodeStart))   // gap: not in any text region
        XCTAssertTrue(v.isGapPosition(img.nodeStart))
    }

    func test_tapOnImageArea_landsOnGap() throws {
        let v = canvas()
        let img = try XCTUnwrap(v.boxes[1] as? MediaBlockBox)
        let p = CGPoint(x: img.frame.midX, y: img.mediaOrigin.y + img.mediaAreaHeight / 2)
        XCTAssertEqual(v.closestGlobalPosition(to: p), img.nodeStart)
    }

    func test_rightFromEndOfParagraph_landsOnGapBeforeImage() {
        let v = canvas()
        let endOfAbove = v.boxes[0].textStart + v.boxes[0].textLength
        let next = v.nextTextPosition(after: endOfAbove)
        XCTAssertEqual(next, v.boxes[1].nodeStart)             // gap before the image
    }

    func test_rightFromGap_landsInCaption() {
        let v = canvas()
        let gap = v.boxes[1].nodeStart
        let next = v.nextTextPosition(after: gap)
        XCTAssertEqual(next, v.boxes[1].textStart)             // into the caption
    }

    func test_leftFromCaptionStart_landsOnGap() {
        let v = canvas()
        let prev = v.prevTextPosition(before: v.boxes[1].textStart)
        XCTAssertEqual(prev, v.boxes[1].nodeStart)        // caption start → gap before the image
    }

    func test_rightFromLastImageCaptionEnd_staysPut() {
        let v = canvas()
        let end = v.boxes[1].textStart + v.boxes[1].textLength
        let next = v.nextTextPosition(after: end)
        XCTAssertEqual(next, end)                         // last block → no overshoot
    }

    func test_leftFromGapBeforeFirstImage_returnsDocStart() {
        let v = DocumentCanvasView()
        v.imageProvider = { [self] _ in image(of: CGSize(width: 80, height: 50), fill: .systemTeal) }
        v.setModelBlocks([
            .media(MediaBlock(id: BlockID("img"), kind: .image, mediaID: "x", naturalSize: Size2D(width: 80, height: 50),
                              caption: [TextRun(text: "Cap")])),
            .core(.paragraph(ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: "After")]))),
        ], width: 300)
        v.frame = CGRect(x: 0, y: 0, width: 300, height: 300); v.layoutSubtreeIfNeeded()
        let prev = v.prevTextPosition(before: v.boxes[0].nodeStart)
        XCTAssertEqual(prev, 0)                           // image-first: gap → document start, no underflow
    }
}
#endif
