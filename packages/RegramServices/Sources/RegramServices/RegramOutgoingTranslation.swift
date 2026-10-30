import Foundation
import RegramCore

public enum RegramOutgoingTranslationPolicy {
    public static func key(accountId: Int64, peerId: Int64) -> String {
        "v2:\(accountId):\(peerId)"
    }

    public static func language(settings: RegramAccountSettings, accountId: Int64, peerId: Int64) -> String? {
        guard case let .dictionary(values) = settings["outgoingLanguageTranslation"] else { return nil }
        let choice = values[key(accountId: accountId, peerId: peerId)]
        guard let choice, choice != "off", !choice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return choice
    }
}
