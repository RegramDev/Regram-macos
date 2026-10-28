#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasCompositionTests: AppKitTestCase {
    private func canvas(_ text: String = "與調整") -> DocumentCanvasView {
        let view = DocumentCanvasView()
        view.setParagraphs([ParagraphBlock(id: BlockID("heading"), runs: [TextRun(text: text)])], width: 420)
        view.frame = CGRect(x: 0, y: 0, width: 420, height: 260)
        view.layoutSubtreeIfNeeded()
        view.selectedGlobalRange = (view.boxes[0].textStart, view.boxes[0].textStart)
        return view
    }

    private func text(_ view: DocumentCanvasView) -> String {
        view.text(inGlobalRange: 0, view.documentSizeValue)
    }

    func testPinyinUpdatesReplaceProvisionalTextBeforeCommit() {
        let view = canvas()
        let start = view.head
        for preedit in ["x", "xi", "xiu", "xiu f", "xiu fu"] {
            view.setMarkedText(preedit, selectedRange: NSRange(location: preedit.utf16.count, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertEqual(text(view), preedit + "與調整")
            XCTAssertTrue(view.hasMarkedText())
            XCTAssertEqual(view.markedRange(), NSRange(location: start, length: preedit.utf16.count))
        }
        view.insertText("修復", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(text(view), "修復與調整")
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(view.head, start + 2)
    }

    func testSystemCompositionProfilesPreserveCandidateSelection() {
        let profiles = [["ㄒ", "ㄒㄧㄡ", "ㄒㄧㄡㄈㄨˋ", "修復"], ["a", "ab", "日月", "明"], ["k", "ka", "かな", "仮名"], ["ㅎ", "하", "한", "한국어"], ["e", "e\u{301}", "é"], ["👩", "👩🏽", "👩🏽‍💻"]]
        for profile in profiles {
            let view = canvas("📌 後文")
            let start = view.head
            for preedit in profile {
                let relative = NSRange(location: 0, length: preedit.utf16.count)
                view.setMarkedText(NSAttributedString(string: preedit), selectedRange: relative, replacementRange: NSRange(location: NSNotFound, length: 0))
                XCTAssertEqual(text(view), preedit + "📌 後文")
                XCTAssertEqual(view.selectedRange(), NSRange(location: start, length: preedit.utf16.count))
                XCTAssertEqual(view.markedRange(), NSRange(location: start, length: preedit.utf16.count))
            }
            view.unmarkText()
            XCTAssertEqual(text(view), profile.last! + "📌 後文")
            XCTAssertFalse(view.hasMarkedText())
        }
    }

    func testExplicitReplacementRangeIsHonoredForMarkedAndCommittedText() {
        let view = canvas("前舊文字後")
        let start = view.boxes[0].textStart + 1
        view.setMarkedText("xin", selectedRange: NSRange(location: 1, length: 1), replacementRange: NSRange(location: start, length: 3))
        XCTAssertEqual(text(view), "前xin後")
        XCTAssertEqual(view.selectedRange(), NSRange(location: start + 1, length: 1))
        view.insertText("新文字", replacementRange: view.markedRange())
        XCTAssertEqual(text(view), "前新文字後")
        view.insertText("替換", replacementRange: NSRange(location: start, length: 3))
        XCTAssertEqual(text(view), "前替換後")
    }

    func testCompositionIsOneUndoStepAndRedoDoesNotRestoreMarkedState() {
        let view = canvas()
        let undo = UndoManager()
        undo.groupsByEvent = false
        view.undoManagerOverride = undo
        undo.beginUndoGrouping()
        for value in ["x", "xi", "xiu", "xiu fu"] {
            view.setMarkedText(value, selectedRange: NSRange(location: value.utf16.count, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        view.insertText("修復", replacementRange: NSRange(location: NSNotFound, length: 0))
        undo.endUndoGrouping()
        XCTAssertEqual(text(view), "修復與調整")
        undo.undo()
        XCTAssertEqual(text(view), "與調整")
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertFalse(undo.canUndo)
        undo.redo()
        XCTAssertEqual(text(view), "修復與調整")
        XCTAssertFalse(view.hasMarkedText())
    }

    func testCancelRemovesOnlyPreeditAndRegistersNoEmptyUndoStep() {
        let view = canvas()
        let undo = UndoManager()
        undo.groupsByEvent = false
        view.undoManagerOverride = undo
        view.setMarkedText("xiu", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(text(view), "與調整")
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertFalse(undo.canUndo)
    }

    func testReturnConfirmsCompositionWithoutAddingNewlineOrSending() {
        let view = canvas()
        var sends = 0
        view.onReturnKey = { sends += 1; return true }
        view.setMarkedText("修復", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.insertNewline(nil)
        XCTAssertEqual(text(view), "修復與調整")
        XCTAssertEqual(sends, 0)
        XCTAssertFalse(view.hasMarkedText())
    }

    func testUnknownRangeAnchorsCaretWithoutChangingPreedit() {
        let view = canvas()
        let window = hostInWindow(view)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        view.setMarkedText("ㄒㄧㄡ", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.layoutSubtreeIfNeeded()
        let expected = view.firstRect(forCharacterRange: NSRange(location: view.head, length: 0), actualRange: nil)
        var actual = NSRange(location: NSNotFound, length: 0)
        let result = view.firstRect(forCharacterRange: NSRange(location: NSNotFound, length: 0), actualRange: &actual)
        XCTAssertEqual(result, expected)
        XCTAssertGreaterThan(result.height, 0)
        XCTAssertNotEqual(actual.location, NSNotFound)
        XCTAssertTrue(view.hasMarkedText())
        XCTAssertEqual(text(view), "ㄒㄧㄡ與調整")
    }

    func testCompositionPreservesHeadingAndPendingBoldFormatting() {
        let view = canvas()
        view.setParagraphStyle(.heading1)
        for value in ["x", "xi", "xiu", "xiu fu"] {
            view.setMarkedText(value, selectedRange: NSRange(location: value.utf16.count, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertEqual((view.boxes[0] as! BlockBox).style, .heading1)
        }
        view.insertText("修復", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(text(view), "修復與調整")
        XCTAssertEqual((view.boxes[0] as! BlockBox).style, .heading1)
        let body = canvas("後文")
        body.toggleBold()
        for value in ["x", "xi", "xiu"] {
            body.setMarkedText(value, selectedRange: NSRange(location: value.utf16.count, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        }
        body.insertText("修復", replacementRange: NSRange(location: NSNotFound, length: 0))
        let paragraph = (body.boxes[0] as! BlockBox).currentParagraph()
        XCTAssertEqual(paragraph.runs.filter { $0.attributes.bold }.map(\.text).joined(), "修復")
        XCTAssertEqual(paragraph.runs.filter { !$0.attributes.bold }.map(\.text).joined(), "後文")
    }

    func testCompositionSurvivesWidthReflowAndClampsOversizedRange() {
        let view = canvas()
        view.setMarkedText("繁體中文注音測試", selectedRange: NSRange(location: 8, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let marked = view.markedRange()
        for width: CGFloat in [140, 600, 200, 420] {
            view.frame.size.width = width
            view.setParagraphsWidthIfNeeded(width)
            view.layoutSubtreeIfNeeded()
            XCTAssertEqual(view.markedRange(), marked)
            XCTAssertEqual(text(view), "繁體中文注音測試與調整")
            var actual = NSRange(location: NSNotFound, length: 0)
            let rect = view.firstRect(forCharacterRange: NSRange(location: NSNotFound, length: Int.max), actualRange: &actual)
            XCTAssertGreaterThan(rect.height, 0)
            XCTAssertEqual(actual.location, view.head)
        }
    }

    func testCompositionRoutesIntoTableCell() {
        let view = DocumentCanvasView()
        let cell = Cell(id: BlockID("cell"), blocks: [.paragraph(ParagraphBlock(id: BlockID("cell-text"), runs: [TextRun(text: "後文")]))])
        view.setBlocks([.table(TableBlock(id: BlockID("table"), columns: [ColumnSpec(width: 180)], rows: [Row(id: BlockID("row"), cells: [cell])]))], width: 420)
        view.frame = CGRect(x: 0, y: 0, width: 420, height: 260)
        view.layoutSubtreeIfNeeded()
        let region = view.allLeafRegions()[0]
        view.selectedGlobalRange = (region.globalStart, region.globalStart)
        for value in ["x", "xiu", "xiu fu"] {
            view.setMarkedText(value, selectedRange: NSRange(location: value.utf16.count, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            XCTAssertEqual(text(view), value + "後文")
        }
        view.insertText("修復", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(text(view), "修復後文")
        XCTAssertTrue(view.boxes[0] is TableBlockBox)
    }

    func testLosingFocusFinalizesCompositionAndNewInputDoesNotReplaceOldText() {
        let view = canvas()
        let window = hostInWindow(view)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        view.setMarkedText("修復", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let other = NSTextView(frame: NSRect(x: 0, y: 350, width: 200, height: 30))
        window.contentView!.addSubview(other)
        XCTAssertTrue(window.makeFirstResponder(other))
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(text(view), "修復與調整")
        XCTAssertTrue(window.makeFirstResponder(view))
        view.setMarkedText("t", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(text(view), "修復t與調整")
    }

    func testSelectAllEndsCompositionBeforeReplacingDocument() {
        let view = canvas()
        view.setMarkedText("xiu fu", selectedRange: NSRange(location: 6, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.selectAllText()
        XCTAssertFalse(view.hasMarkedText())
        view.insertText("新正文", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(text(view), "新正文")
    }
}
#endif
