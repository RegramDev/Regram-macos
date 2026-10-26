import AppKit
import XCTest
@testable import TGUIKit

final class SearchViewInputGeometryTests: XCTestCase {
    private func drainCoordinates() {
        let done = expectation(description: "input coordinates delivered")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 1)
    }

    private func assertSameRect(_ actual: NSRect, _ expected: NSRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.5, file: file, line: line)
    }

    func testUnknownRangeUsesCurrentCaretAndPreservesMarkedText() {
        let fixture = SearchGeometryFixture()
        defer { fixture.window.close() }
        fixture.mark("a", after: "就是这个样子")
        let input = fixture.search.input
        let marked = input.markedRange()
        let selected = input.selectedRange()
        let query = fixture.search.query
        let expected = input.firstRect(forCharacterRange: selected, actualRange: nil)
        var actual = NSRange(location: NSNotFound, length: 0)
        let result = input.firstRect(forCharacterRange: NSRange(location: NSNotFound, length: 0), actualRange: &actual)
        XCTAssertGreaterThan(result.height, 0)
        assertSameRect(result, expected)
        XCTAssertNotEqual(actual.location, NSNotFound)
        XCTAssertLessThanOrEqual(NSMaxRange(actual), query.utf16.count)
        XCTAssertEqual(fixture.search.query, query)
        XCTAssertTrue(input.hasMarkedText())
        XCTAssertEqual(input.markedRange(), marked)
        XCTAssertEqual(input.selectedRange(), selected)
    }

    func testMarkedRangeAfterEmojiUsesUTF16OffsetsAndClampsInvalidRequests() {
        let fixture = SearchGeometryFixture()
        defer { fixture.window.close() }
        let prefix = "📌 群聊 "
        fixture.mark("sousuo", after: prefix)
        let input = fixture.search.input
        XCTAssertEqual(input.markedRange(), NSRange(location: prefix.utf16.count, length: 6))
        var actual = NSRange(location: NSNotFound, length: 0)
        let markedRect = input.firstRect(forCharacterRange: input.markedRange(), actualRange: &actual)
        XCTAssertGreaterThan(markedRect.height, 0)
        XCTAssertLessThanOrEqual(NSMaxRange(actual), fixture.search.query.utf16.count)
        let selectedRect = input.firstRect(forCharacterRange: input.selectedRange(), actualRange: nil)
        let invalid = NSRange(location: fixture.search.query.utf16.count + 200, length: Int.max)
        let clampedRect = input.firstRect(forCharacterRange: invalid, actualRange: &actual)
        assertSameRect(clampedRect, selectedRect)
        XCTAssertLessThanOrEqual(NSMaxRange(actual), fixture.search.query.utf16.count)
        XCTAssertEqual(input.markedRange(), NSRange(location: prefix.utf16.count, length: 6))
    }

    func testIncrementalCompositionReturnsTheRequestedCharacterBeforeDeferredLayout() {
        let fixture = SearchGeometryFixture(width: 140)
        defer { fixture.window.close() }
        let input = fixture.search.input
        for length in 1...40 {
            let text = String(repeating: "w", count: length)
            input.setMarkedText(text, selectedRange: NSRange(location: length, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            let requested = NSRange(location: length - 1, length: 1)
            var actual = NSRange(location: NSNotFound, length: 0)
            let rect = input.firstRect(forCharacterRange: requested, actualRange: &actual)
            XCTAssertGreaterThan(rect.height, 0, "composition length \(length)")
            XCTAssertEqual(actual, requested, "composition length \(length)")
            let visible = fixture.window.convertToScreen(input.convert(input.visibleRect, to: nil))
            XCTAssertTrue(visible.insetBy(dx: -1, dy: -1).contains(rect.origin), "composition length \(length)")
            XCTAssertGreaterThan(input.firstRect(forCharacterRange: NSRange(location: NSNotFound, length: 0), actualRange: nil).height, 0)
            XCTAssertTrue(input.hasMarkedText())
            XCTAssertEqual(input.markedRange(), NSRange(location: 0, length: length))
            XCTAssertEqual(input.selectedRange(), NSRange(location: length, length: 0))
            fixture.search.layoutSubtreeIfNeeded()
        }
    }

    func testCompositionAfterLongUnicodePrefixReturnsCoordinatesBeforeDeferredLayout() {
        let fixture = SearchGeometryFixture(width: 250)
        defer { fixture.window.close() }
        let prefix = String(repeating: "📌 中文", count: 15)
        fixture.search.setString(prefix)
        fixture.search.layoutSubtreeIfNeeded()
        let input = fixture.search.input
        input.setSelectedRange(NSRange(location: prefix.utf16.count, length: 0))
        for length in 1...20 {
            let text = String(repeating: "w", count: length)
            input.setMarkedText(text, selectedRange: NSRange(location: length, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            let requested = NSRange(location: prefix.utf16.count + length - 1, length: 1)
            var actual = NSRange(location: NSNotFound, length: 0)
            let rect = input.firstRect(forCharacterRange: requested, actualRange: &actual)
            XCTAssertGreaterThan(rect.height, 0, "composition length \(length)")
            XCTAssertEqual(actual, requested, "composition length \(length)")
            let visible = fixture.window.convertToScreen(input.convert(input.visibleRect, to: nil))
            XCTAssertTrue(visible.insetBy(dx: -1, dy: -1).contains(rect.origin), "composition length \(length)")
            XCTAssertEqual(input.markedRange(), NSRange(location: prefix.utf16.count, length: length))
            XCTAssertEqual(fixture.search.query, prefix + text)
            fixture.search.layoutSubtreeIfNeeded()
        }
    }

    func testDirectFocusSurvivesDelegateReflowAndReturnsVisibleCoordinates() {
        let fixture = SearchGeometryFixture(focus: false)
        defer { fixture.window.close() }
        var focusedCallbacks = 0
        fixture.search.searchInteractions = SearchInteractions({ [weak search = fixture.search] state, _ in
            guard state.state == .Focus, let search else { return }
            focusedCallbacks += 1
            search.frame.origin.x += 25
            search.updateLayout(size: search.frame.size, transition: .immediate)
        }, { _ in })
        XCTAssertTrue(fixture.window.makeFirstResponder(fixture.search.input))
        fixture.mark("a", after: "就是这个样子")
        XCTAssertEqual(focusedCallbacks, 1)
        XCTAssertTrue(fixture.window.firstResponder === fixture.search.input)
        XCTAssertFalse(fixture.search.input.isHiddenOrHasHiddenAncestor)
        let rect = fixture.search.input.firstRect(forCharacterRange: NSRange(location: NSNotFound, length: 0), actualRange: nil)
        let visible = fixture.window.convertToScreen(fixture.search.input.convert(fixture.search.input.visibleRect, to: nil))
        XCTAssertGreaterThan(rect.height, 0)
        XCTAssertTrue(visible.insetBy(dx: -2, dy: -2).contains(rect.origin))
    }

    func testLongMarkedQueryTracksHorizontalClipOffset() throws {
        let fixture = SearchGeometryFixture()
        defer { fixture.window.close() }
        fixture.mark("a", after: String(repeating: "中文 📌 search ", count: 30))
        let input = fixture.search.input
        input.scrollRangeToVisible(input.markedRange())
        let clip = try XCTUnwrap(input.enclosingScrollView?.contentView)
        let before = input.firstRect(forCharacterRange: input.markedRange(), actualRange: nil)
        XCTAssertGreaterThan(before.height, 0)
        XCTAssertGreaterThan(clip.bounds.minX, 2)
        let oldOrigin = clip.bounds.origin
        clip.scroll(to: NSPoint(x: oldOrigin.x - 2, y: oldOrigin.y))
        let after = input.firstRect(forCharacterRange: input.markedRange(), actualRange: nil)
        XCTAssertGreaterThan(after.height, 0)
        XCTAssertEqual(after.minX - before.minX, oldOrigin.x - clip.bounds.minX, accuracy: 0.5)
        XCTAssertEqual(after.minY, before.minY, accuracy: 0.5)
        XCTAssertTrue(input.hasMarkedText())
    }

    func testAncestorAndWindowMovementUseScreenCoordinatesIncludingNegativeOrigins() {
        let fixture = SearchGeometryFixture()
        defer { fixture.window.close() }
        fixture.mark("a", after: "就是这个样子")
        let input = fixture.search.input
        let range = input.markedRange()
        let before = input.firstRect(forCharacterRange: range, actualRange: nil)
        fixture.host.frame.origin.x += 31
        fixture.host.frame.origin.y += 19
        let moved = input.firstRect(forCharacterRange: range, actualRange: nil)
        XCTAssertEqual(moved.minX - before.minX, 31, accuracy: 0.5)
        XCTAssertEqual(moved.minY - before.minY, 19, accuracy: 0.5)
        for origin in [NSPoint(x: -750, y: 180), NSPoint(x: 1850, y: 380)] {
            let oldOrigin = fixture.window.frame.origin
            let previous = input.firstRect(forCharacterRange: range, actualRange: nil)
            fixture.window.setFrameOrigin(origin)
            let current = input.firstRect(forCharacterRange: range, actualRange: nil)
            XCTAssertGreaterThan(current.height, 0)
            XCTAssertEqual(current.minX - previous.minX, fixture.window.frame.minX - oldOrigin.x, accuracy: 0.5)
            XCTAssertEqual(current.minY - previous.minY, fixture.window.frame.minY - oldOrigin.y, accuracy: 0.5)
        }
    }

    func testFocusedClientRegistersCoalescedGeometryInvalidationsWithoutLooping() {
        let fixture = TrackingSearchGeometryFixture()
        defer { fixture.window.close() }
        fixture.input.tracker.onInvalidate = { [weak input = fixture.input] in
            _ = input?.firstRect(forCharacterRange: NSRange(location: NSNotFound, length: 0), actualRange: nil)
        }
        _ = fixture.input.firstRect(forCharacterRange: fixture.input.markedRange(), actualRange: nil)
        drainCoordinates()
        drainCoordinates()
        fixture.input.tracker.invalidations = 0
        for index in 1...8 { fixture.host.frame.origin.x = CGFloat(index) }
        let immediate = fixture.input.tracker.invalidations
        drainCoordinates()
        XCTAssertEqual(fixture.input.tracker.invalidations - immediate, 1)
        let settled = fixture.input.tracker.invalidations
        drainCoordinates()
        XCTAssertEqual(fixture.input.tracker.invalidations, settled)
        XCTAssertTrue(fixture.window.firstResponder === fixture.input)
        XCTAssertTrue(fixture.input.hasMarkedText())
    }

    func testClipBoundsAndWindowScreenChangesInvalidateFocusedClient() {
        let fixture = TrackingSearchGeometryFixture()
        defer { fixture.window.close() }
        drainCoordinates()
        fixture.input.tracker.invalidations = 0
        fixture.scroll.contentView.setBoundsOrigin(NSPoint(x: 10, y: 0))
        drainCoordinates()
        XCTAssertGreaterThan(fixture.input.tracker.invalidations, 0)
        fixture.input.tracker.invalidations = 0
        NotificationCenter.default.post(name: NSWindow.didChangeScreenNotification, object: fixture.window)
        NotificationCenter.default.post(name: NSWindow.didChangeBackingPropertiesNotification, object: fixture.window)
        drainCoordinates()
        XCTAssertEqual(fixture.input.tracker.invalidations, 1)
    }

    func testResignedAndDetachedClientsIgnorePendingGeometryCallbacks() {
        let fixture = TrackingSearchGeometryFixture()
        defer { fixture.window.close() }
        drainCoordinates()
        fixture.input.tracker.invalidations = 0
        fixture.host.frame.origin.x += 10
        XCTAssertTrue(fixture.window.makeFirstResponder(nil))
        fixture.input.removeFromSuperview()
        fixture.host.frame.origin.x += 10
        NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: fixture.window)
        drainCoordinates()
        drainCoordinates()
        XCTAssertEqual(fixture.input.tracker.invalidations, 0)
    }
}

private final class SearchGeometryFixture {
    let window: Window
    let host: NSView
    let search: SearchView

    init(focus: Bool = true, width: CGFloat = 470) {
        TGUIKitTestBootstrap.install()
        window = Window(contentRect: NSRect(x: 350, y: 250, width: 650, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        host = NSView(frame: window.contentView!.bounds)
        window.contentView?.addSubview(host)
        search = SearchView(frame: NSRect(x: 70, y: 420, width: width, height: 30))
        host.addSubview(search)
        if focus { search.change(state: .Focus, false) }
    }

    func mark(_ text: String, after prefix: String) {
        search.setString(prefix)
        search.input.setSelectedRange(NSRange(location: prefix.utf16.count, length: 0))
        search.input.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        search.layoutSubtreeIfNeeded()
    }
}

private final class RecordingSearchInputContext: NSTextInputContext {
    var invalidations = 0
    var onInvalidate: (() -> Void)?

    override func invalidateCharacterCoordinates() {
        invalidations += 1
        onInvalidate?()
    }
}

private final class TrackingSearchTextField: SearchTextField {
    lazy var tracker = RecordingSearchInputContext(client: self)
    override var inputContext: NSTextInputContext? { tracker }
}

private final class TrackingSearchGeometryFixture {
    let window: Window
    let host: NSView
    let scroll: NSScrollView
    let input: TrackingSearchTextField

    init() {
        TGUIKitTestBootstrap.install()
        window = Window(contentRect: NSRect(x: 350, y: 250, width: 650, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        host = NSView(frame: window.contentView!.bounds)
        window.contentView?.addSubview(host)
        scroll = NSScrollView(frame: NSRect(x: 70, y: 420, width: 300, height: 30))
        host.addSubview(scroll)
        input = TrackingSearchTextField()
        input.frame = NSRect(x: 0, y: 0, width: 900, height: 24)
        input.font = .systemFont(ofSize: 13)
        scroll.documentView = input
        _ = window.makeFirstResponder(input)
        input.setMarkedText("pin", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
    }
}
