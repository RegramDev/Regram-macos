#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

/// Mouse-driven selection: click-drag across text must create a non-empty selection (so toolbar
/// formatting has something to act on), and bold must then apply to it.
@available(macOS 12, *)
final class CanvasMouseSelectionTests: AppKitTestCase {
    private func makeCanvas(text: String = "Hello world") -> (DocumentCanvasView, NSWindow) {
        let v = DocumentCanvasView()
        v.setBlocks([.paragraph(ParagraphBlock(id: BlockID("h"), runs: [TextRun(text: text)]))], width: 320)
        v.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
        let win = hostInWindow(v)
        v.layoutSubtreeIfNeeded()
        return (v, win)
    }

    func test_mouseDrag_createsSelection_andBoldApplies() {
        let (v, win) = makeCanvas()
        let region = v.allLeafRegions().first { $0.ref == .paragraph(BlockID("h")) }!
        let aGlobal = region.globalStart          // before 'H'
        let bGlobal = region.globalStart + 5      // after "Hello"
        func winPt(_ g: Int) -> NSPoint {
            let r = v.caretRect(forGlobal: g)
            return v.convert(NSPoint(x: r.midX, y: r.midY), to: nil)
        }
        func ev(_ t: NSEvent.EventType, _ g: Int, _ cc: Int) -> NSEvent {
            NSEvent.mouseEvent(with: t, location: winPt(g), modifierFlags: [], timestamp: 0,
                windowNumber: win.windowNumber, context: nil, eventNumber: 0, clickCount: cc, pressure: 1)!
        }
        v.mouseDown(with: ev(.leftMouseDown, aGlobal, 1))
        v.mouseDragged(with: ev(.leftMouseDragged, bGlobal, 1))
        v.mouseUp(with: ev(.leftMouseUp, bGlobal, 1))
        XCTAssertNotEqual(v.selFrom, v.selTo, "drag should create a selection; got \(v.selFrom)..\(v.selTo)")
        v.toggleBold()
        let bold = v.currentBlocks().compactMap { b -> String? in
            if case .paragraph(let p) = b, p.id == BlockID("h") {
                return p.runs.filter { $0.attributes.bold }.map(\.text).joined()
            }
            return nil
        }.joined()
        XCTAssertFalse(bold.isEmpty, "bold should apply to the drag-selected text; bold runs=\"\(bold)\"")
    }

    func test_doubleClickSelectsComposedEmojiAndPunctuation() throws {
        for (text, token) in [
            ("你好世界，富文本选词测试", "文本"),
            ("Hello 🧑‍💻 world", "🧑‍💻"),
            ("Hello 👨‍👩‍👧‍👦 world", "👨‍👩‍👧‍👦"),
            ("Hello 🇸🇬 world", "🇸🇬"),
            ("Hello 👍🏽 world", "👍🏽"),
            ("Hello 。 world", "。"),
            ("Hello e\u{301} world", "e\u{301}")
        ] {
            let (canvas, window) = makeCanvas(text: text)
            let region = try XCTUnwrap(canvas.allLeafRegions().first)
            let range = (text as NSString).range(of: token)
            let rect = try XCTUnwrap(canvas.selectionRects(globalFrom: region.globalStart + range.location, globalTo: region.globalStart + NSMaxRange(range)).first)
            let point = canvas.convert(NSPoint(x: rect.minX + min(1, rect.width / 4), y: rect.midY), to: nil)
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 1))
            canvas.mouseDown(with: event)
            XCTAssertEqual(canvas.selFrom, region.globalStart + range.location, token)
            XCTAssertEqual(canvas.selTo, region.globalStart + NSMaxRange(range), token)
            XCTAssertFalse(canvas.selectionRects(globalFrom: canvas.selFrom, globalTo: canvas.selTo).isEmpty, token)
        }
    }

    func test_editorFacadeRoutesDoubleClickAndDragToTextCanvas() throws {
        for scrollEnabled in [true, false] {
            let editor = RichTextEditorView(frame: NSRect(x: 0, y: 0, width: 320, height: 200))
            editor.isScrollEnabled = scrollEnabled
            editor.document = Document(blocks: [.paragraph(ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: "Hello world 中文选词")]))])
            let window = hostInWindow(editor)
            editor.layoutSubtreeIfNeeded()
            let canvas = editor.canvas
            let region = try XCTUnwrap(canvas.allLeafRegions().first)
            let rect = try XCTUnwrap(canvas.selectionRects(globalFrom: region.globalStart, globalTo: region.globalStart + 5).first)
            let point = canvas.convert(NSPoint(x: rect.minX + 1, y: rect.midY), to: nil)
            let target = try XCTUnwrap(window.contentView?.hitTest(point))
            XCTAssertTrue(target === canvas, "scrollEnabled=\(scrollEnabled)")
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 1))
            target.mouseDown(with: event)
            XCTAssertEqual(editor.selectedText(), "Hello")
            XCTAssertTrue(editor.hasSelection)
            func dragEvent(_ type: NSEvent.EventType, offset: Int) throws -> NSEvent {
                let caret = canvas.caretRect(forGlobal: region.globalStart + offset)
                let location = canvas.convert(NSPoint(x: caret.midX, y: caret.midY), to: nil)
                return try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1))
            }
            target.mouseDown(with: try dragEvent(.leftMouseDown, offset: 6))
            target.mouseDragged(with: try dragEvent(.leftMouseDragged, offset: 11))
            target.mouseUp(with: try dragEvent(.leftMouseUp, offset: 11))
            XCTAssertEqual(editor.selectedText(), "world")
            XCTAssertTrue(editor.hasSelection)
        }
    }
}
#endif
