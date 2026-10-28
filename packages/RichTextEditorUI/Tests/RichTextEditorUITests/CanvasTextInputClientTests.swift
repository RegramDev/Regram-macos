#if canImport(AppKit)
import XCTest
import AppKit
@testable import RichTextEditorUI
import RichTextEditorCore

/// Geometry/coordinate mapping for the new `NSTextInputClient` conformance (Task 2.2).
///
/// NOTE (pending): these tests can only COMPILE+RUN once the whole co-dependent canvas batch is green
/// (the `NSTextInputClient` conformance forward-references `commitText`, and `+Navigation`/`+Editing`/
/// `+TableControls` must be ported). Until then this file is AppKit-guarded but the batch build is RED,
/// so it does not run. It is the red→green signal for the geometry mapping.
@available(macOS 12, *)
final class CanvasTextInputClientTests: AppKitTestCase {
    private func canvas() -> DocumentCanvasView {
        let v = DocumentCanvasView()
        v.setParagraphs([
            ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "Alpha")]),
            ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "Beta")]),
        ], width: 300)
        v.frame = CGRect(x: 0, y: 0, width: 300, height: 200); v.layoutSubtreeIfNeeded()
        return v
    }

    // selectedRange() reports the global (selFrom, length) of the (anchor, head) selection.
    func test_selectedRange_tracksAnchorHead() {
        let v = canvas()
        let a = v.boxes[0].textStart + 1   // inside "Alpha"
        let b = v.boxes[1].textStart + 2   // inside "Beta"
        v.selectedGlobalRange = (a, b)
        let r = v.selectedRange()
        XCTAssertEqual(r.location, min(a, b))
        XCTAssertEqual(r.length, abs(b - a))
    }

    func test_selectedRange_collapsedHasZeroLength() {
        let v = canvas()
        let p = v.boxes[0].textStart + 3
        v.selectedGlobalRange = (p, p)
        let r = v.selectedRange()
        XCTAssertEqual(r.location, p)
        XCTAssertEqual(r.length, 0)
    }

    func test_attributedSubstring_returnsContiguousLeafAndMatchingActualRange() {
        let v = canvas()
        let lo = v.boxes[0].textStart + 4   // "a" of Alpha
        let hi = v.boxes[1].textStart + 1   // "B" of Beta
        var actual = NSRange(location: 0, length: 0)
        let s = v.attributedSubstring(forProposedRange: NSRange(location: lo, length: hi - lo),
                                      actualRange: &actual)
        XCTAssertEqual(s?.string, "a")
        XCTAssertEqual(actual, NSRange(location: lo, length: 1))
    }

    func test_attributedSubstring_clampsOutOfRange() {
        let v = canvas()
        let s = v.attributedSubstring(forProposedRange: NSRange(location: -5, length: 10_000),
                                      actualRange: nil)
        XCTAssertNotNil(s)   // clamped, does not crash
    }

    // characterIndex(for:) round-trips a known caret: take a caret's view rect, convert to screen, and
    // confirm it maps back near the same global offset. Requires a window for the screen conversion.
    func test_characterIndex_roundTripsKnownCaret() {
        let v = canvas()
        let w = hostInWindow(v)
        defer { w.orderOut(nil) }
        v.frame = w.contentView!.bounds; v.layoutSubtreeIfNeeded()

        let pos = v.boxes[1].textStart + 2   // inside "Beta"
        let caret = v.caretRect(forGlobal: pos)
        // A point just inside the caret rect, in view coords → screen coords.
        let viewPoint = NSPoint(x: caret.midX, y: caret.midY)
        let screenPoint = w.convertPoint(toScreen: v.convert(viewPoint, to: nil))
        let back = v.characterIndex(for: screenPoint)
        XCTAssertEqual(back, pos, accuracy: 1)
    }

    // firstRect(forCharacterRange:) returns the caret/selection rect in SCREEN coordinates (not view).
    func test_firstRect_isInScreenCoordinates() {
        let v = canvas()
        let w = hostInWindow(v)
        defer { w.orderOut(nil) }
        v.frame = w.contentView!.bounds; v.layoutSubtreeIfNeeded()

        let pos = v.boxes[0].textStart + 2
        let screenRect = v.firstRect(forCharacterRange: NSRange(location: pos, length: 0), actualRange: nil)
        let viewRect = v.caretRect(forGlobal: pos)
        // The screen rect must NOT equal the raw view rect (it was converted view→window→screen).
        XCTAssertNotEqual(screenRect.origin, viewRect.origin)
        XCTAssertEqual(screenRect.size.height, viewRect.size.height, accuracy: 0.5)
    }
}
#endif
