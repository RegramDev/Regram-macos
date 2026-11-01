#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class FullBleedLayoutTests: XCTestCase {
    private func canvas(_ blocks: [CanvasModelBlock], width: CGFloat) -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.mediaBlockViewProvider = { _, _, _, width in
            NSView(frame: CGRect(x: 0, y: 0, width: width, height: 50))
        }
        v.setModelBlocks(blocks, width: width)
        v.frame = CGRect(x: 0, y: 0, width: width, height: 600)
        v.layoutSubtreeIfNeeded()
        return v
    }

    func test_paragraphText_insetByPageMargin() {
        let v = canvas([.core(.paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Hi")])))], width: 390)
        let box = v.boxes[0] as! BlockBox
        XCTAssertEqual(box.textOrigin.x, CanvasMetrics.pageMargin, accuracy: 0.5)   // 16pt, not 8
    }

    func test_hostedImage_fullBleedToCanvasEdges() throws {
        let v = canvas([
            .media(MediaBlock(id: BlockID("img"), kind: .image, mediaID: "x", naturalSize: Size2D(width: 100, height: 50),
                              caption: [TextRun(text: "Cap")]))
        ], width: 390)
        let img = try XCTUnwrap(v.boxes[0] as? MediaBlockBox)
        XCTAssertEqual(img.kind, .image)
        let rect = try XCTUnwrap(v.mediaBlockViews[img.id.rawValue]).view.frame
        XCTAssertEqual(rect.minX, 0, accuracy: 0.5)          // bleeds to the left edge
        XCTAssertEqual(rect.width, 390, accuracy: 0.5)        // full canvas width
    }

    func test_caption_insetByPageMargin() throws {
        let v = canvas([
            .media(MediaBlock(id: BlockID("img"), kind: .image, mediaID: "x", naturalSize: Size2D(width: 100, height: 50),
                              caption: [TextRun(text: "Cap")]))
        ], width: 390)
        let img = try XCTUnwrap(v.boxes[0] as? MediaBlockBox)
        XCTAssertEqual(img.textOrigin.x, CanvasMetrics.pageMargin, accuracy: 0.5)   // caption at 16
    }

    private func cell(_ id: String, _ t: String) -> Cell {
        Cell(id: BlockID(id), blocks: [.paragraph(ParagraphBlock(id: BlockID(id+"p"), runs: [TextRun(text: t)]))])
    }

    func test_tableGrid_insetByPageMargin() {
        let v = canvas([.core(.table(TableBlock(id: BlockID("t"),
            columns: [ColumnSpec(width: 100), ColumnSpec(width: 100)],
            rows: [Row(id: BlockID("r0"), isHeader: true, cells: [cell("a","Name"), cell("b","Role")]),
                   Row(id: BlockID("r1"), cells: [cell("c","Ada"), cell("d","Eng")])])))], width: 390)
        let t = v.boxes[0] as! TableBlockBox
        let r0c0 = t.cellRect(row: 0, column: 0)!
        XCTAssertGreaterThanOrEqual(r0c0.minX, CanvasMetrics.pageMargin)   // grid inset, not at x=0
    }

    func test_cellText_isTight_notPageMarginInset() {
        let v = canvas([.core(.table(TableBlock(id: BlockID("t"),
            columns: [ColumnSpec(width: 100), ColumnSpec(width: 100)],
            rows: [Row(id: BlockID("r0"), isHeader: true, cells: [cell("a","Name"), cell("b","Role")]),
                   Row(id: BlockID("r1"), cells: [cell("c","Ada"), cell("d","Eng")])])))], width: 390)
        let t = v.boxes[0] as! TableBlockBox
        let innerBox = t.cells[0][0].boxes[0] as! BlockBox
        let cellLeft = t.cellRect(row: 0, column: 0)!.minX
        // Cell text must sit within ~cellPadding of the cell's left border (NOT pageMargin-inset).
        XCTAssertLessThanOrEqual(innerBox.textOrigin.x - cellLeft, TableBlockBox.cellPadding + 2)   // +2: 1pt cell border + sub-pixel rounding
    }
}
#endif
