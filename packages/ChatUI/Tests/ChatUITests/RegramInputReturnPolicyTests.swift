import AppKit
import XCTest
@testable import ChatUI

final class RegramInputReturnPolicyTests: XCTestCase {
    func testPlainReturnFollowsPreferenceAndCommandReturnNeverSends() {
        XCTAssertTrue(RegramInputReturnPolicy.shouldSend(sendWithReturn: true, modifiers: [], hasMarkedText: false))
        XCTAssertFalse(RegramInputReturnPolicy.shouldSend(sendWithReturn: false, modifiers: [], hasMarkedText: false))
        let combinations: [NSEvent.ModifierFlags] = [.command, .shift, .option, .control, [.command, .shift], [.command, .option]]
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
        for modifiers in combinations {
            XCTAssertFalse(RegramInputReturnPolicy.shouldSend(sendWithReturn: true, modifiers: modifiers, hasMarkedText: input.hasMarkedText()))
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
        XCTAssertTrue(RegramInputReturnPolicy.handleCommandReturn(event, responder: input, inputRoot: root))
        XCTAssertEqual(input.string, "draft\n")
        let otherRoot = NSView(frame: root.bounds)
        XCTAssertFalse(RegramInputReturnPolicy.handleCommandReturn(event, responder: input, inputRoot: otherRoot))
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
        XCTAssertTrue(RegramInputReturnPolicy.handleCommandReturn(event, responder: input, inputRoot: root))
        XCTAssertEqual(input.string, "caption\n")
    }
}
