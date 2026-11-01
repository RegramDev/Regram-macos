#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// Computes text-unit boundaries from each leaf region's OWN string (a real character stream), NOT from
/// the global position axis (which interleaves text with structural token slots). Word: macOS semantics —
/// forward → the next word END, backward → the previous word START, scanned per region with Foundation
/// `.byWords`; crossing a region boundary uses the canvas's `nextTextPosition`/`prevTextPosition` so
/// blocks/cells/captions never glue into one word. Paragraph/line == one leaf region. Every returned
/// position is renderable by construction.
///
/// AppKit has no `UITextInputTokenizer` protocol — these are plain `Int`/`Bool` helpers the `NSResponder`
/// movement/selection selectors call directly.
@available(macOS 12, *)
final class DocumentTokenizer: NSObject {
    private unowned let canvas: DocumentCanvasView
    init(canvas: DocumentCanvasView) { self.canvas = canvas; super.init() }

    // MARK: - Boundary helpers (were the position(from:toBoundary:inDirection:) witness)

    /// Forward → the next word END after `pos`, backward → the previous word START. Crosses region
    /// boundaries (one press reaches the next word's edge) but never glues two regions into one word.
    func wordBoundary(fromGlobal pos0: Int, forward fwd: Bool) -> Int {
        wordBoundary(from: canvas.clampGlobal(pos0), forward: fwd)
    }

    /// Paragraph boundary == the enclosing leaf region's edge in the travel direction.
    func paragraphBoundary(fromGlobal pos0: Int, forward fwd: Bool) -> Int {
        regionBoundary(from: canvas.clampGlobal(pos0), forward: fwd)
    }

    /// Line boundary — v1 collapses to the region edge (same as paragraph), matching the iOS port's
    /// `.line == .paragraph == one leaf region` model.
    func lineBoundary(fromGlobal pos0: Int, forward fwd: Bool) -> Int {
        let pos = canvas.clampGlobal(pos0)
        // ⌘←/⌘→ go to the VISUAL line edge (like the plain composer), not the whole paragraph/region.
        guard let (region, local) = canvas.leafRegion(containingGlobal: pos) else {
            return regionBoundary(from: pos, forward: fwd)   // a structural gap keeps the region behavior
        }
        return region.globalStart + region.layout.visualLineBoundary(atOffset: local, forward: fwd)
    }

    // MARK: - Enclosing-unit ranges (were rangeEnclosingPosition / the Select-menu accessors)

    /// The word range enclosing `pos` (direction-independent), for double-tap / the Select menu action.
    /// nil at a gap (no owning region).
    func wordRange(atGlobal pos: Int) -> (Int, Int)? {
        enclosingWord(at: canvas.clampGlobal(pos))
    }

    /// The paragraph/region range enclosing `pos`, for triple-tap / paragraph select. nil at a gap.
    func paragraphRange(atGlobal pos: Int) -> (Int, Int)? {
        enclosingRegion(at: canvas.clampGlobal(pos))
    }

    // MARK: - Word

    private func wordRanges(_ s: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        s.enumerateSubstrings(in: NSRange(location: 0, length: s.length), options: [.byWords, .substringNotRequired]) { _, r, _, _ in
            ranges.append(r)
        }
        return ranges
    }

    /// Forward → the next word END after `pos` within its region, else cross to the next region/gap.
    /// Backward → the previous word START before `pos`, else cross to the previous region/gap.
    private func wordBoundary(from pos: Int, forward fwd: Bool) -> Int {
        guard let (r, local) = canvas.leafRegion(containingGlobal: pos) else {
            // A structural-token slot (no owning region). Image gaps ARE renderable, so step off them;
            // a pure structural slot is not, so snap onto the nearest renderable slot in the travel
            // direction first, otherwise next/prevTextPosition would walk onto another structural slot.
            if canvas.isGapPosition(pos) {
                return fwd ? canvas.nextTextPosition(after: pos) : canvas.prevTextPosition(before: pos)
            }
            return canvas.snapToRenderable(pos, forward: fwd)
        }
        let s = r.layout.attributedString.string as NSString
        let ranges = wordRanges(s)
        if fwd {
            if let end = ranges.map({ $0.location + $0.length }).filter({ $0 > local }).min() {
                return r.globalStart + end
            }
            // No further word in this region → cross into the next region and continue to ITS first
            // word end, so one Option+Right reaches the next word's end (macOS). Stop at an image gap or
            // the document end. Terminates: each cross advances strictly to a later region.
            let regionEnd = r.globalStart + r.length
            let next = canvas.nextTextPosition(after: regionEnd)
            if next == regionEnd || canvas.isGapPosition(next) { return next }
            return wordBoundary(from: next, forward: true)
        } else {
            if let start = ranges.map({ $0.location }).filter({ $0 < local }).max() {
                return r.globalStart + start
            }
            let prev = canvas.prevTextPosition(before: r.globalStart)
            if prev == r.globalStart || canvas.isGapPosition(prev) { return prev }
            return wordBoundary(from: prev, forward: false)
        }
    }

    private func enclosingWord(at pos: Int) -> (Int, Int)? {
        guard let (region, local) = canvas.leafRegion(containingGlobal: pos), region.length > 0 else { return nil }
        let range = region.layout.attributedString.doubleClick(at: min(max(0, local), region.length - 1))
        guard range.location != NSNotFound, range.length > 0 else { return nil }
        return (region.globalStart + range.location, region.globalStart + NSMaxRange(range))
    }

    // MARK: - Region (paragraph / line / sentence v1)

    private func enclosingRegion(at pos: Int) -> (Int, Int)? {
        guard let (r, _) = canvas.leafRegion(containingGlobal: pos) else { return nil }
        return (r.globalStart, r.globalStart + r.length)
    }

    private func regionBoundary(from pos: Int, forward fwd: Bool) -> Int {
        guard let (lo, hi) = enclosingRegion(at: pos) else {
            if canvas.isGapPosition(pos) {
                return fwd ? canvas.nextTextPosition(after: pos) : canvas.prevTextPosition(before: pos)
            }
            return canvas.snapToRenderable(pos, forward: fwd)
        }
        if fwd { return pos < hi ? hi : canvas.nextTextPosition(after: hi) }
        return pos > lo ? lo : canvas.prevTextPosition(before: lo)
    }
}
#endif
