import AppKit
import XCTest
@testable import TGUIKit

final class SearchViewInputTests: XCTestCase {
    func testCancelClearsUncommittedInput() {
        let fixture = SearchInputFixture()
        defer { fixture.window.close() }
        fixture.mark("pin")

        fixture.search.cancel(false)

        XCTAssertEqual(fixture.search.state, .None)
        XCTAssertEqual(fixture.search.query, "")
        XCTAssertFalse(fixture.search.input.hasMarkedText())
        XCTAssertTrue(fixture.search.input.isHidden)
    }

    func testClearQueryEndsCompositionAndKeepsSearchFocused() {
        let fixture = SearchInputFixture()
        defer { fixture.window.close() }
        fixture.mark("拼音")
        var requests: [String] = []
        fixture.search.searchInteractions = SearchInteractions({ _, _ in }, { requests.append($0.request) })

        fixture.search.cancelSearch()

        XCTAssertEqual(fixture.search.state, .Focus)
        XCTAssertEqual(fixture.search.query, "")
        XCTAssertFalse(fixture.search.input.hasMarkedText())
        XCTAssertTrue(fixture.window.firstResponder === fixture.search.input)
        XCTAssertEqual(requests.last, "")
    }

    func testReplacingQueryWithMarkedTextAfterUnicodePrefix() {
        let fixture = SearchInputFixture()
        defer { fixture.window.close() }
        fixture.search.setString("📌 群聊 ")
        fixture.mark("sousuo")

        fixture.search.setString("搜索")

        XCTAssertEqual(fixture.search.query, "搜索")
        XCTAssertFalse(fixture.search.input.hasMarkedText())
        fixture.mark("xin")
        XCTAssertEqual(fixture.search.query, "搜索xin")
    }
}

private final class SearchInputFixture {
    let window: Window
    let search: SearchView

    init() {
        TGUIKitTestBootstrap.install()
        window = Window(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        search = SearchView(frame: NSRect(x: 0, y: 120, width: 300, height: 30))
        window.contentView?.addSubview(search)
        search.change(state: .Focus, false)
    }

    func mark(_ text: String) {
        search.input.setSelectedRange(NSRange(location: search.query.utf16.count, length: 0))
        search.input.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(search.input.hasMarkedText())
    }
}
