#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// Pure, directly-callable selection logic, factored OUT of the gesture/menu callbacks so it can be
/// unit-tested without synthesizing touch events. The mouse handlers (DocumentCanvasView+Interaction) and
/// the menu actions (DocumentCanvasView+EditMenu) are thin wrappers over these.
@available(macOS 12, *)
extension DocumentCanvasView {
    /// What a single tap at `resolved` should do. `.toggleMenu` — the tap landed on the existing collapsed
    /// caret OR inside the active selection → toggle the edit menu, KEEPING the current caret/selection (the
    /// gesture handler presents or dismisses depending on whether the menu is already showing). `.setCaret`
    /// — the tap landed elsewhere → place the caret there (collapsing any selection) and dismiss the menu.
    enum TapOutcome: Equatable { case toggleMenu, setCaret(Int) }

    func tapOutcome(forResolvedPosition resolved: Int) -> TapOutcome {
        if selFrom != selTo {
            // Tap inside the selection → toggle the menu (keep the selection); outside → collapse to a caret.
            return (resolved >= selFrom && resolved <= selTo) ? .toggleMenu : .setCaret(resolved)
        }
        return resolved == head ? .toggleMenu : .setCaret(resolved)
    }

    /// Which selection endpoint a drag should move, by global-offset proximity. nil when collapsed.
    enum SelectionEndpoint: Equatable { case anchor, head }

    func nearerSelectionEndpoint(toGlobal pos: Int) -> SelectionEndpoint? {
        guard selFrom != selTo else { return nil }
        return abs(pos - anchor) <= abs(pos - head) ? .anchor : .head
    }

    /// Select the word enclosing `pos` (Select menu item / double click). No-op at a structural gap.
    func selectWord(at pos: Int) {
        guard let (from, to) = tokenizer.wordRange(atGlobal: pos) else { return }
        applySelection(from: from, to: to)
    }

    /// Select the paragraph/region enclosing `pos` (triple click). No-op at a structural gap.
    func selectParagraph(at pos: Int) {
        guard let (from, to) = tokenizer.paragraphRange(atGlobal: pos) else { return }
        applySelection(from: from, to: to)
    }

    /// Select the whole document. Starts at the first block's `nodeStart` (not the first *renderable*
    /// text position) so a LEADING media block's atom is inside the selection — otherwise select-all
    /// would skip a leading map/file/audio (it wouldn't highlight or delete). End is the last renderable.
    func selectAllText() {
        applySelection(from: boxes.first?.nodeStart ?? firstRenderableGlobal(), to: lastRenderableGlobal())
    }

    /// If `p` lands on a formula atom, select it (the accent wash covers the atom) and return true; else
    /// false (the caller falls back to a normal caret). Single-click handler for formulas.
    func selectFormula(atCanvasPoint p: NSPoint) -> Bool {
        guard let (lo, hi) = formulaAtomRange(atCanvasPoint: p) else { return false }
        applySelection(from: lo, to: hi)
        return true
    }

    private func applySelection(from: Int, to: Int) {
        finishInputComposition()
        anchor = clampGlobal(from); head = clampGlobal(to)
        needsDisplay = true; notifySelectionChanged()
    }
}
#endif
