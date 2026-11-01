import Cocoa
import CoreText
import XCTest
import Postbox
import TelegramCore
import InstantPageUI
import InAppSettings
@testable import ChatUI

private final class RichTextSelectionSource: ChatBubbleCustomTextSelection {
    weak var view: InstantPageV2View?

    func applyBubbleSelection(begin: NSPoint, end: NSPoint, isStartRow: Bool, isEndRow: Bool, reversed: Bool) -> [ChatBubbleSelectionFragment] {
        return view?.applySelection(begin: begin, end: end, isStartRow: isStartRow, isEndRow: isEndRow, reversed: reversed) ?? []
    }

    func clearBubbleSelection() {
        view?.clearBubbleSelection()
    }
}

final class ChatRichTextWordSelectionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
        selectManager.removeAll()
    }

    override func tearDown() {
        selectManager.removeAll()
        super.tearDown()
    }

    func testDoubleClickUsesNativeWordsAndCompleteGraphemes() throws {
        for (text, token) in [
            ("Hello world", "Hello"),
            ("你好世界，富文本选词测试", "文本"),
            ("Hello 🧑‍💻 world", "🧑‍💻"),
            ("Hello 👨‍👩‍👧‍👦 world", "👨‍👩‍👧‍👦"),
            ("Hello 🇸🇬 world", "🇸🇬"),
            ("Hello 👍🏽 world", "👍🏽"),
            ("Cafe\u{301} noir", "Cafe\u{301}"),
            ("Hello 。 world", "。")
        ] {
            selectManager.removeAll()
            let page = InstantPage(blocks: [.paragraph(.plain(text))], media: [:], isComplete: true, rtl: false, url: "", views: nil)
            let content = TelegramMediaWebpageLoadedContent(url: "", displayUrl: "", hash: 0, type: nil, websiteName: nil, title: nil, text: nil, embedUrl: nil, embedType: nil, embedSize: nil, duration: nil, author: nil, isMediaLargeByDefault: nil, imageIsVideoCover: false, image: nil, file: nil, story: nil, attributes: [], instantPage: page)
            let webpage = TelegramMediaWebpage(webpageId: MediaId(namespace: 0, id: 1), content: .Loaded(content))
            let presentation = instantPageThemeForType(.light, settings: .defaultSettings)
            let layout = layoutInstantPageV2(webpage: webpage, instantPage: page, boundingWidth: 480, horizontalInset: 0, theme: presentation)
            let view = InstantPageV2View(frame: NSRect(x: 0, y: 0, width: 480, height: 180))
            let source = RichTextSelectionSource()
            source.view = view
            view.bubbleSelectionSource = source
            view.bubbleSelectionStableId = AnyHashable(1)
            view.update(layout: layout, theme: presentation)
            let window = NSWindow(contentRect: view.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            let textItem = try XCTUnwrap(layout.items.compactMap { item in
                if case let .text(text) = item { return text }
                return nil
            }.first)
            let line = try XCTUnwrap(textItem.textItem.lines.first)
            let range = (text as NSString).range(of: token)
            let offset = CTLineGetOffsetForStringIndex(line.line, range.location, nil)
            let lineFrame = textItem.textItem.alignedLineFrame(line)
            let local = NSPoint(x: textItem.frame.minX + lineFrame.minX + offset + 1, y: textItem.frame.minY + lineFrame.midY)
            let location = view.convert(local, to: nil)
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 2, pressure: 1))
            let target = try XCTUnwrap(view.hitTest(local))
            target.mouseDown(with: event)
            XCTAssertEqual(selectManager.selectedText.string, token, text)
            XCTAssertTrue(line.selectRect.width > 0, text)
            XCTAssertTrue(window.firstResponder === selectManager, text)
        }
    }
}
