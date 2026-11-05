import AppKit

enum RegramInputReturnPolicy {
    static func handleCommandReturn(_ event: NSEvent, sendWithReturn: Bool, responder: NSResponder?, inputRoot: NSView) -> Bool {
        guard sendWithReturn, event.keyCode == 36 || event.keyCode == 76, event.modifierFlags.contains(.command),
              let responder = responder as? NSView, responder.isDescendant(of: inputRoot),
              let client = responder as? NSTextInputClient else { return false }
        if client.hasMarkedText() {
            responder.keyDown(with: event)
        } else {
            responder.insertNewline(nil)
        }
        return true
    }

    static func shouldSend(sendWithReturn: Bool, modifiers: NSEvent.ModifierFlags, hasMarkedText: Bool) -> Bool {
        guard !hasMarkedText else { return false }
        let modifiers = modifiers.intersection([.command, .shift, .control, .option])
        return sendWithReturn ? modifiers.isEmpty : modifiers == .command
    }
}
