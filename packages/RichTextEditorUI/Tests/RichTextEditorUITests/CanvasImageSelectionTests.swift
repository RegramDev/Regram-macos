#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasImageSelectionTests: AppKitTestCase {
    private func canvas() -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.mediaBlockViewProvider = { _, _, _, width in
            NSView(frame: CGRect(x: 0, y: 0, width: width, height: 50))
        }
        v.setModelBlocks([
            .core(.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Above")]))),
            .media(MediaBlock(id: BlockID("img"), kind: .image, mediaID: "x", naturalSize: Size2D(width: 80, height: 50),
                              caption: [TextRun(text: "Caption")])),
            .core(.paragraph(ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Below")]))),
        ], width: 300)
        v.frame = CGRect(x: 0, y: 0, width: 300, height: 400); v.layoutSubtreeIfNeeded()
        return v
    }

    private func imageBox(in canvas: DocumentCanvasView) throws -> MediaBlockBox {
        let box = try XCTUnwrap(canvas.boxes.first { $0.id == BlockID("img") } as? MediaBlockBox)
        XCTAssertEqual(box.kind, .image)
        return box
    }

    func test_selectionFlowsThroughCaption() throws {
        let v = canvas()
        let imgBox = try imageBox(in: v)
        let rects = v.selectionRects(globalFrom: v.boxes[0].textStart + 2,
                                     globalTo: v.boxes[2].textStart + 2)
        func count(in box: CanvasBlock) -> Int { rects.filter { box.frame.intersects($0) }.count }
        XCTAssertGreaterThan(count(in: v.boxes[0]), 0)
        XCTAssertGreaterThan(count(in: imgBox), 0)
        XCTAssertGreaterThan(count(in: v.boxes[2]), 0)
    }

    func test_shiftEnterInImageCaption_exitsIntoNewParagraph() throws {
        let v = canvas()
        let img = try imageBox(in: v)
        v.setCaret(global: img.textStart + 2)
        let before = v.boxes.count
        let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift, timestamp: 0,
                                 windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r",
                                 isARepeat: false, keyCode: 36)!
        v.keyDown(with: e)
        XCTAssertEqual(v.boxes.count, before + 1, "Shift+Enter adds a paragraph after the image")
        XCTAssertTrue(v.boxes[2] is BlockBox, "the new block after the image is a paragraph")
        XCTAssertEqual(v.head, v.boxes[2].textStart, "caret lands in the new paragraph")
    }

    func test_clickHostedImage_resolvesImageContext() throws {
        let v = canvas()
        let img = try imageBox(in: v)
        let point = CGPoint(x: img.frame.midX, y: img.mediaOrigin.y + img.mediaAreaHeight / 2)
        let context = try XCTUnwrap(v.mediaContext(atCanvasPoint: point))
        XCTAssertEqual(context.blockID, img.id.rawValue)
        XCTAssertEqual(context.kind, "image")
        XCTAssertNil(v.mediaContext(atCanvasPoint: CGPoint(x: img.frame.midX, y: img.textOrigin.y + 1)))
    }

    func test_clickImage_selectsWithAccent_togglesOff_andDeletes() throws {
        let v = canvas()
        let img = try imageBox(in: v)
        v.selectMediaBlock(id: img.id)
        XCTAssertEqual(v.soleSelectedMediaBlock()?.id, img.id)
        XCTAssertEqual(v.mediaBoxesInSelection().map(\.id), [img.id])
        v.selectMediaBlock(id: img.id)
        XCTAssertNil(v.soleSelectedMediaBlock())
        v.selectMediaBlock(id: img.id)
        v.performDeleteBackward()
        XCTAssertFalse(v.boxes.contains { $0.id == img.id })
    }

    func test_caretInCaption_isBelowImage() throws {
        let v = canvas()
        let imgBox = try imageBox(in: v)
        let caret = v.caretRect(forGlobal: imgBox.textStart)
        XCTAssertGreaterThanOrEqual(caret.minY, imgBox.mediaOrigin.y + imgBox.mediaAreaHeight)
    }

    func test_caretAtImageGap_isVerticalBarAtImageLeadingEdge() throws {
        let v = canvas()
        let imgBox = try imageBox(in: v)
        let caret = v.caretRect(forGlobal: imgBox.nodeStart)
        XCTAssertFalse(caret.isEmpty, "gap caret must be a drawable rect, not .zero")
        XCTAssertEqual(caret.minX, imgBox.mediaOrigin.x, accuracy: 0.5)
        XCTAssertEqual(caret.minY, imgBox.mediaOrigin.y, accuracy: 0.5)
        XCTAssertEqual(caret.height, imgBox.mediaAreaHeight, accuracy: 0.5)
    }

    func test_typingInCaption_editsCaptionText() throws {
        let v = canvas()
        let imgBox = try imageBox(in: v)
        v.selectedGlobalRange = (imgBox.textStart + 7, imgBox.textStart + 7)
        v.commitText("!")
        guard case .media(let out) = v.boxes[1].currentModelBlock() else { return XCTFail() }
        XCTAssertEqual(out.caption.map(\.text).joined(), "Caption!")
    }
}
#endif
