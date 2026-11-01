#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class ImageBlockBoxTests: AppKitTestCase {
    private func solid(_ size: CGSize) -> NSImage {
        image(of: size, fill: .systemBlue)
    }
    private func mixedCanvas() -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.mediaBlockViewProvider = { _, _, _, width in
            let view = NSImageView(image: self.solid(CGSize(width: 100, height: 60)))
            view.frame = CGRect(x: 0, y: 0, width: width, height: 60)
            return view
        }
        v.setModelBlocks([
            .core(.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Above")]))),
            .media(MediaBlock(id: BlockID("img"), kind: .image, mediaID: "x", naturalSize: Size2D(width: 100, height: 60),
                              caption: [TextRun(text: "Cap")])),
            .core(.paragraph(ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Below")]))),
        ], width: 300)
        v.frame = CGRect(x: 0, y: 0, width: 300, height: 400); v.layoutSubtreeIfNeeded()
        return v
    }

    func test_imageBox_tokenMath() {
        let block = RichTextEditorUI.MediaBlock(id: BlockID("img"), kind: .image, mediaID: "x", naturalSize: Size2D(width: 100, height: 60),
                               caption: [TextRun(text: "Cap")])
        let box: CanvasBlock = ImageBlockBox(media: block, mapper: AttributedStringMapper(), width: 300)
        box.nodeStart = 5
        XCTAssertEqual(box.textLength, 3)          // "Cap"
        XCTAssertEqual(box.nodeSize, 8)            // captionLen + 5
        XCTAssertEqual(box.textStart, 7)           // nodeStart + 2
        XCTAssertEqual(box.textRef, .caption(BlockID("img")))
        guard case .media(let out) = box.currentModelBlock() else { return XCTFail("expected image") }
        XCTAssertEqual(out.caption.map(\.text).joined(), "Cap")
    }

    func test_mixedDoc_spansMatchCorePositionModel() {
        let v = mixedCanvas()
        // The public `[Block]` document drops images, so reconstruct the equivalent Core document with a
        // `.media` block standing in for the image (same caption, same node structure: atom + caption).
        let doc = Document(blocks: [
            .paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Above")])),
            .media(MediaBlock(id: BlockID("img"), mediaID: "x", naturalSize: Size2D(width: 100, height: 60),
                              caption: [TextRun(text: "Cap")])),
            .paragraph(ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Below")])),
        ])
        let tree = DocumentTree.build(from: doc)
        XCTAssertEqual(v.documentSizeValue, DocumentTree.documentSize(doc))
        // caption text start matches the Core global position of the caption text node
        let imgBox = v.boxes[1]
        let coreCaptionStart = PositionResolver.globalPosition(of: .caption(BlockID("img")), offset: 0, in: tree)
        XCTAssertEqual(imgBox.textStart, coreCaptionStart)
    }

    func test_currentBlocks_roundTripsMixedDocument() {
        let v = mixedCanvas()
        // The public `[Block]` document drops images, so the paragraph/image/paragraph order is asserted
        // against the internal canvas model (`currentModelBlocks()`), which preserves the bare `.image` case.
        let blocks = v.currentModelBlocks()
        XCTAssertEqual(blocks.count, 3)
        guard case .core(.paragraph) = blocks[0], case .media = blocks[1], case .core(.paragraph) = blocks[2]
        else { return XCTFail("expected paragraph/image/paragraph") }
    }

    func test_imageRendersNonBlank() {
        let v = mixedCanvas()
        let image = snapshot(v)
        XCTAssertNotNil(image.cgImage)
    }

    func test_caption_isLeftAligned() {
        let block = RichTextEditorUI.MediaBlock(id: BlockID("img"), kind: .image, mediaID: "x", naturalSize: Size2D(width: 100, height: 60),
                               caption: [TextRun(text: "Cap")])
        let box = ImageBlockBox(media: block, mapper: AttributedStringMapper(), width: 300)
        let ps = box.caption.attributedString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertEqual(ps?.alignment, .left)
    }

    func test_caption_isCaptionSize_andSecondaryColor() {
        // Matches the chat (ChatRichTextRowItem) caption: sans 12pt, secondary/gray colour.
        let block = RichTextEditorUI.MediaBlock(id: BlockID("img"), kind: .image, mediaID: "x", naturalSize: Size2D(width: 100, height: 60),
                               caption: [TextRun(text: "Cap")])
        let box = ImageBlockBox(media: block, mapper: AttributedStringMapper(), width: 300)
        let attrs = box.caption.attributedString.attributes(at: 0, effectiveRange: nil)
        XCTAssertEqual((attrs[.font] as? NSFont)?.pointSize ?? 0, 12, accuracy: 0.5)
        XCTAssertEqual(attrs[.foregroundColor] as? NSColor, EditorAppearance.default.secondaryForeground)
    }

    func test_imageRect_respectsExplicitDisplayWidth() {
        let block = RichTextEditorUI.MediaBlock(id: BlockID("img"), kind: .image, mediaID: "x",
                               displayWidth: 60, naturalSize: Size2D(width: 100, height: 50), caption: [])
        let box = ImageBlockBox(media: block, mapper: AttributedStringMapper(), width: 390)
        XCTAssertEqual(box.imageRect().width, 60, accuracy: 0.5)   // explicit width honored, not stretched full-bleed
    }
}
#endif
