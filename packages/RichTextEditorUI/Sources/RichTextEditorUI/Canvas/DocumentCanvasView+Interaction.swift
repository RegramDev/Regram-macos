#if canImport(AppKit)
import AppKit

/// Mouse-driven selection for the AppKit canvas. Replaces the UIKit gesture-recognizer stack
/// (single/double/triple tap + long-press loupe + handle pan). On macOS:
///   - `NSEvent.clickCount` gives 1/2/3 natively (no manual multi-tap timing/slop machinery),
///   - click-drag to select is expected (there is no enclosing scroll-pan to arbitrate against — the
///     host `NSScrollView` scrolls via the scroller / trackpad, not a drag inside the canvas),
///   - the right-click / Control-click context menu is built by `menu(for:)` (see +EditMenu.swift),
///   - there is no loupe / `UITextSelectionDisplayInteraction` — the caret is self-drawn (see the base).
@available(macOS 12, *)
extension DocumentCanvasView {
    /// The façade may still call this; on AppKit there is nothing to install (mouse events arrive on the
    /// responder directly, the caret is self-drawn, and the menu is built lazily in `menu(for:)`).
    func installSelectionInteractions() {}

    override func mouseDown(with event: NSEvent) {
        finishInputComposition()
        window?.makeFirstResponder(self)
        // Control-click IS a context-menu click: the overridden mouseDown would otherwise swallow it as
        // a caret-placing left click (clearing the selection and never showing a menu). Route it through
        // the same `menu(for:)` path a right-click takes — which preserves an active selection.
        if event.modifierFlags.contains(.control) {
            if let menu = menu(for: event) {
                NSMenu.popUpContextMenu(menu, with: event, for: self)
            }
            return
        }
        selectedCollageTile = nil                        // a click off a tile overlay clears any tile selection
        let p = convert(event.locationInWindow, from: nil)
        // Table handle / knob hit-test first (a knob starts a range-drag; a handle selects a row/column).
        if tableSelection != nil, let end = tableResizeKnob(at: p) {
            draggingTableKnob = end
            return
        }
        // A click in a table's row/column handle gutter selects that row/column on the FIRST click,
        // independent of the caret (the drawn ⋮/••• handles otherwise only track the caret's cell).
        if let hit = geometricTableHandleHit(at: p) {
            // Shift-click extends the existing row/column selection (grows it to span the clicked one).
            let extending = event.modifierFlags.contains(.shift)
            switch hit.kind {
            case .rows(let r):    selectTableRows(r, in: hit.box, extending: extending)
            case .columns(let c): selectTableColumns(c, in: hit.box, extending: extending)
            }
            return
        }
        if let action = tableHandleTap(at: p) {
            handleTableHandleAction(action)
            return
        }
        // (The code block's header band — copy zone + language-editor click — is gone: the language is
        // now authored directly in the block's always-visible, editable language line, so a click there
        // just places the caret via the normal path below.)
        // A click on a BlockQuoteBox's collapse/expand glyph toggles collapsed state (incl. nested quotes).
        if event.clickCount == 1, let bq = firstBlockQuoteGlyphHit(at: p) {
            clearTableSelection()
            toggleCollapsed(box: bq)
            return
        }
        // Tapping a checklist checkbox toggles it (the marker sits in the gutter, left of the text).
        if let box = checklistBox(atCanvasPoint: p) {
            toggleChecklist(box)
            return
        }
        clearTableSelection()                            // a non-handle click clears any structural selection
        // A click on a button pill / the row's "…" affordance opens the editor sheet / row menu (falls
        // through to plain caret placement when no host wired the button editor).
        if event.clickCount == 1, handleButtonClickIfNeeded(at: p) {
            return
        }
        // Clicking an image's bitmap selects it (accent wash + toggle), like the other media — rather than
        // dropping a gap cursor before it.
        if event.clickCount == 1, let img = imageBoxAtCanvasPoint(p) {
            selectImageBlock(img)
            return
        }
        // Clicking an inline formula selects the atom (accent wash) rather than dropping a caret beside it.
        if event.clickCount == 1, selectFormula(atCanvasPoint: p) {
            return
        }
        let pos = closestGlobalPosition(to: p)
        switch event.clickCount {
        case 1:
            setCaret(global: pos)
            draggingEndpoint = .head                      // a drag from here extends the head
            textDragOrigin = p                            // …but only past a small move threshold
            anchor = pos
            head = pos
        case 2:
            selectWord(at: pos)
        default:                                          // 3+ clicks → paragraph
            selectParagraph(at: pos)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let end = draggingTableKnob {
            extendTableSelection(end: end, toward: p)
            return
        }
        // Only extend a TEXT selection when a text drag is actually in progress (armed by a text click).
        // A drag right after a table-handle click — which just selected a row/column — must NOT clobber
        // that structural selection with a text selection (the "selects for a frame then turns into text"
        // bug: mouseDown selected the row/column, then a tiny move fired this and overwrote it).
        guard draggingEndpoint != nil else { return }
        // Ignore sub-threshold movement so a click (with a tiny tremor) doesn't become a text selection.
        if let origin = textDragOrigin {
            if hypot(p.x - origin.x, p.y - origin.y) < 4 { return }
            textDragOrigin = nil
        }
        setSelectionHead(global: closestGlobalPosition(to: p))
    }

    override func mouseUp(with event: NSEvent) {
        draggingTableKnob = nil
        draggingEndpoint = nil
        textDragOrigin = nil
    }

    /// First-tap handling of a table row/column handle: select that row/column. (On macOS the menu opens
    /// from `menu(for:)` on a right/Control-click — there is no left-click menu toggle, so a `.menu` tap on
    /// the already-selected handle just re-selects it, a harmless no-op.)
    func handleTableHandleAction(_ action: TableHandleTap) {
        switch action {
        case .select(let kind):
            switch kind {
            case .rows(let r): selectTableRows(r)
            case .columns(let c): selectTableColumns(c)
            }
        case .menu:
            // The handle is already structurally selected; the context menu is raised via `menu(for:)`.
            break
        }
    }
}
#endif
