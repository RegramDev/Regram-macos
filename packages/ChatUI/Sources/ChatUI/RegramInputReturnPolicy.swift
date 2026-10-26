import AppKit

enum RegramInputReturnPolicy {
    static func handleCommandReturn(_ event: NSEvent, responder: NSResponder?, inputRoot: NSView) -> Bool {
        guard event.keyCode == 36 || event.keyCode == 76, event.modifierFlags.contains(.command),
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
        !hasMarkedText && sendWithReturn && modifiers.intersection([.command, .shift, .control, .option]).isEmpty
    }
}
