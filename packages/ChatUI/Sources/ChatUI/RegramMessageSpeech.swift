import Cocoa
import Postbox

final class RegramMessageSpeech {
    static let shared = RegramMessageSpeech()
    private let synthesizer = NSSpeechSynthesizer()
    private var messageId: MessageId?
    private var accountId: Int64?

    func isSpeaking(accountId: Int64, messageId: MessageId) -> Bool {
        self.accountId == accountId && self.messageId == messageId && synthesizer.isSpeaking
    }

    func toggle(text: String, accountId: Int64, messageId: MessageId) {
        let stop = isSpeaking(accountId: accountId, messageId: messageId)
        synthesizer.stopSpeaking()
        self.messageId = nil
        self.accountId = nil
        guard !stop else { return }
        if synthesizer.startSpeaking(text) {
            self.messageId = messageId
            self.accountId = accountId
        }
    }
}
