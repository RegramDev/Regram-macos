import AppKit
import XCTest
@testable import TGUIKit

final class WindowResponderTests: XCTestCase {
    func testUncommittedInputReceivesKeysBeforeWindowHandlers() throws {
        let fixture = MarkedInputFixture()
        defer { fixture.window.close() }
        fixture.markText()

        for (keyCode, characters): (UInt16, String) in [(36, "\r"), (76, "\r"), (125, "\u{f701}"), (126, "\u{f700}"), (53, "\u{1b}"), (48, "\t"), (51, "\u{7f}"), (0, "a")] {
            try fixture.send(keyCode: keyCode, characters: characters)
        }

        XCTAssertTrue(fixture.handledKeys.isEmpty)
        XCTAssertEqual(fixture.input.receivedKeys, [36, 76, 125, 126, 53, 48, 51, 0])
    }

    func testCommittedInputStillUsesWindowHandlers() throws {
        let fixture = MarkedInputFixture()
        defer { fixture.window.close() }

        try fixture.send(keyCode: 36, characters: "\r")

        XCTAssertEqual(fixture.handledKeys, [36])
        XCTAssertTrue(fixture.input.receivedKeys.isEmpty)
    }

    func testCommandAndControlShortcutsStillWorkDuringComposition() throws {
        let fixture = MarkedInputFixture()
        defer { fixture.window.close() }
        fixture.markText()

        try fixture.send(keyCode: 0, characters: "a", modifierFlags: [.command])
        try fixture.send(keyCode: 0, characters: "a", modifierFlags: [.control])

        XCTAssertEqual(fixture.handledKeys, [0, 0])
        XCTAssertTrue(fixture.input.receivedKeys.isEmpty)
    }

    func testTypingPreservesTheActiveTextEditorAndRestoresDefaultFocusAfterItLeaves() throws {
        TGUIKitTestBootstrap.install()
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let composer = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 100))
        let field = NSTextField(frame: NSRect(x: 0, y: 120, width: 200, height: 30))
        let textarea = NSTextView(frame: NSRect(x: 210, y: 120, width: 180, height: 100))
        window.contentView?.addSubview(composer)
        window.contentView?.addSubview(field)
        window.contentView?.addSubview(textarea)
        window.set(responder: { composer }, with: composer, priority: .medium)
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "1", charactersIgnoringModifiers: "1", isARepeat: false, keyCode: 18))
        XCTAssertTrue(window.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor())
        window.applyResponderIfNeeded(event)
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertTrue(window.makeFirstResponder(textarea))
        window.applyResponderIfNeeded(event)
        XCTAssertTrue(window.firstResponder === textarea)
        XCTAssertTrue(window.makeFirstResponder(nil))
        window.applyResponderIfNeeded(event)
        XCTAssertTrue(window.firstResponder === composer)
    }
}

private final class MarkedInputFixture {
    let window: Window
    let input: KeyRecordingTextView
    var handledKeys: [UInt16] = []
    private let owner = NSObject()

    init() {
        TGUIKitTestBootstrap.install()
        window = Window(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        input = KeyRecordingTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 30))
        window.contentView?.addSubview(input)
        XCTAssertTrue(window.makeFirstResponder(input))
        window.set(handler: { [weak self] event in
            self?.handledKeys.append(event.keyCode)
            return .invoked
        }, with: owner, for: .All, priority: .supreme)
    }

    func markText() {
        input.setMarkedText("sousuo", selectedRange: NSRange(location: 6, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(input.hasMarkedText())
    }

    func send(keyCode: UInt16, characters: String, modifierFlags: NSEvent.ModifierFlags = []) throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifierFlags, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
        window.sendEvent(event)
    }
}

private final class KeyRecordingTextView: NSTextView {
    var receivedKeys: [UInt16] = []

    override func keyDown(with event: NSEvent) {
        receivedKeys.append(event.keyCode)
    }
}
