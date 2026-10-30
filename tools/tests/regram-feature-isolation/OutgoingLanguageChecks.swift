import Foundation
import RegramCore

final class FixtureNavigation {
    var returns = 0
    func back() { returns += 1 }
}
struct FixtureBindings {
    let navigation = FixtureNavigation()
    func rootNavigation() -> FixtureNavigation { navigation }
}
struct FixtureContext { let bindings = FixtureBindings() }

@main
struct OutgoingLanguageChecks {
    static func main() {
        let suite = "RegramOutgoingLanguageChecks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let testPreferences = RegramPreferences(defaults: defaults)
        let context = FixtureContext()
        let accountId: Int64 = 42
        var key = ""
        __SELECT_LANGUAGE__
        testPreferences.update(accountId: accountId) { $0["outgoingLanguageTranslation"] = .dictionary(["42:17": "de"]) }
        let peers: [Int64] = [17, (1 << 32) | 17, (2 << 32) | 17]
        for (index, peerId) in peers.enumerated() {
            key = RegramOutgoingTranslationPolicy.key(accountId: accountId, peerId: peerId)
            select(["en", "ja", "fr"][index])
        }
        key = RegramOutgoingTranslationPolicy.key(accountId: accountId, peerId: peers[1])
        select("off")
        let saved = RegramPreferences(defaults: defaults).settings(accountId: accountId)
        precondition(RegramOutgoingTranslationPolicy.language(settings: saved, accountId: accountId, peerId: peers[0]) == "en")
        precondition(RegramOutgoingTranslationPolicy.language(settings: saved, accountId: accountId, peerId: peers[1]) == nil)
        precondition(RegramOutgoingTranslationPolicy.language(settings: saved, accountId: accountId, peerId: peers[2]) == "fr")
        if case let .dictionary(values) = saved["outgoingLanguageTranslation"] {
            precondition(values.count == 4 && values["42:17"] == "de")
        } else { preconditionFailure("Stored language choices missing") }
        precondition(testPreferences.settings(accountId: 43).values.isEmpty)
        precondition(context.bindings.navigation.returns == 4)
        print("Outgoing language production action checks passed: separate user/group/channel choices, off action, persisted reload, other-account and legacy-record preservation; isolated preferences only")
    }
}
