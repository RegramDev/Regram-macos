import AppKit
import XCTest
import InputTextView
@testable import ChatUI

final class RegramInputReturnPolicyTests: XCTestCase {
    func testReturnAndCommandReturnFollowBothSendingPreferences() {
        XCTAssertTrue(RegramInputReturnPolicy.shouldSend(sendWithReturn: true, modifiers: [], hasMarkedText: false))
        XCTAssertFalse(RegramInputReturnPolicy.shouldSend(sendWithReturn: false, modifiers: [], hasMarkedText: false))
        XCTAssertFalse(RegramInputReturnPolicy.shouldSend(sendWithReturn: true, modifiers: .command, hasMarkedText: false))
        XCTAssertTrue(RegramInputReturnPolicy.shouldSend(sendWithReturn: false, modifiers: .command, hasMarkedText: false))
        let combinations: [NSEvent.ModifierFlags] = [.shift, .option, .control, [.command, .shift], [.command, .option]]
        for preference in [true, false] {
            for modifiers in combinations {
                XCTAssertFalse(RegramInputReturnPolicy.shouldSend(sendWithReturn: preference, modifiers: modifiers, hasMarkedText: false))
            }
        }
        XCTAssertTrue(RegramInputReturnPolicy.shouldSend(sendWithReturn: true, modifiers: [.capsLock, .numericPad], hasMarkedText: false))
    }

    func testRealMarkedTextPreventsBothReturnFormsFromSending() {
        let input = NSTextView(frame: .zero)
        input.setMarkedText("候选", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(input.hasMarkedText())
        let combinations: [NSEvent.ModifierFlags] = [[], .command, .shift]
        for preference in [true, false] {
            for modifiers in combinations {
                XCTAssertFalse(RegramInputReturnPolicy.shouldSend(sendWithReturn: preference, modifiers: modifiers, hasMarkedText: input.hasMarkedText()))
            }
        }
        input.unmarkText()
        XCTAssertFalse(input.hasMarkedText())
        XCTAssertTrue(RegramInputReturnPolicy.shouldSend(sendWithReturn: true, modifiers: [], hasMarkedText: input.hasMarkedText()))
    }

    func testCommandReturnInsertsNativeNewlineAndConsumesWindowBinding() throws {
        _ = NSApplication.shared
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        let input = NSTextView(frame: root.bounds)
        root.addSubview(input)
        input.string = "draft"
        input.setSelectedRange(NSRange(location: input.string.utf16.count, length: 0))
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        XCTAssertTrue(RegramInputReturnPolicy.handleCommandReturn(event, sendWithReturn: true, responder: input, inputRoot: root))
        XCTAssertEqual(input.string, "draft\n")
        XCTAssertFalse(RegramInputReturnPolicy.handleCommandReturn(event, sendWithReturn: false, responder: input, inputRoot: root))
        XCTAssertEqual(input.string, "draft\n")
        let otherRoot = NSView(frame: root.bounds)
        XCTAssertFalse(RegramInputReturnPolicy.handleCommandReturn(event, sendWithReturn: true, responder: input, inputRoot: otherRoot))
        XCTAssertEqual(input.string, "draft\n")
    }

    func testCommandKeypadEnterInsertsNativeNewline() throws {
        _ = NSApplication.shared
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 100))
        let input = NSTextView(frame: root.bounds)
        root.addSubview(input)
        input.string = "caption"
        input.setSelectedRange(NSRange(location: input.string.utf16.count, length: 0))
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .numericPad], timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 76))
        XCTAssertTrue(RegramInputReturnPolicy.handleCommandReturn(event, sendWithReturn: true, responder: input, inputRoot: root))
        XCTAssertEqual(input.string, "caption\n")
    }
    func testNativeComposerUsesTheSelectedReturnForSendingAndTheOtherForNewline() throws {
        UITestBootstrap.install()
        let cases: [(Bool, NSEvent.ModifierFlags, Bool)] = [(true, [], true), (true, .command, false), (false, [], false), (false, .command, true), (false, [.command, .shift], false)]
        for (sendWithReturn, modifiers, expectedSend) in cases {
            for keyCode: UInt16 in [36, 76] {
                var sends = 0
                let interactions = TextView_Interactions()
                interactions.processEnter = { event in
                    let shouldSend = RegramInputReturnPolicy.shouldSend(sendWithReturn: sendWithReturn, modifiers: event.modifierFlags, hasMarkedText: false)
                    if shouldSend { sends += 1 }
                    return shouldSend
                }
                let root = UITextView(frame: NSRect(x: 0, y: 0, width: 320, height: 120), interactions: interactions)
                let window = NSWindow(contentRect: root.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = root
                let input = root.inputView
                XCTAssertTrue(window.makeFirstResponder(input))
                input.string = "draft"
                input.setSelectedRange(NSRange(location: 5, length: 0))
                let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: keyCode))
                if modifiers.contains(.command) {
                    XCTAssertTrue(input.performKeyEquivalent(with: event))
                } else {
                    input.keyDown(with: event)
                }
                XCTAssertEqual(sends, expectedSend ? 1 : 0)
                XCTAssertEqual(input.string, expectedSend ? "draft" : "draft\n")
                window.orderOut(nil)
            }
        }
    }

}
