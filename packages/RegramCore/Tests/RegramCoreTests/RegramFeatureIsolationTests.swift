import XCTest
@testable import RegramCore

final class RegramFeatureIsolationTests: XCTestCase {
    private func alternative(_ setting: RegramSetting) -> RegramValue {
        if let value = setting.choices.first(where: { $0 != setting.defaultValue }) { return value }
        switch setting.key {
        case "messageFilterRules": return .string(RGMessageFilter.encode([RGMessageFilterRule(pattern: "fixture")]))
        case "chatPreferences": return .string("{\"1:2\":{\"formatting\":\"bold\"}}")
        default: break
        }
        switch setting.defaultValue {
        case let .bool(value): return .bool(!value)
        case let .integer(value): return .integer(value + 1)
        case let .number(value): return .number(value + 1)
        case .string: return .string("fixture")
        case .strings: return .strings(["2"])
        case .dictionary: return .dictionary(["1:2": "en"])
        }
    }

    func testOnlyTranslationConfigurationChangesInvalidateTranslations() {
        let original = RegramAccountSettings()
        let identity = original.translationIdentity
        let relevant: Set<String> = ["translationBackend", "serviceConfigurationRevision", "translationConfigurationRevision"]
        for setting in RegramSetting.all {
            var changed = original
            changed[setting.key] = alternative(setting)
            XCTAssertNotEqual(changed[setting.key], original[setting.key], setting.key)
            let affectsTranslation = relevant.contains(setting.key) || setting.key.hasPrefix("translationLLM")
            XCTAssertEqual(changed.translationIdentity == identity, !affectsTranslation, setting.key)
        }
    }

    func testUnchangedServiceKeepsExistingTranslationCacheIdentity() throws {
        var settings = RegramAccountSettings()
        settings["serviceConfigurationRevision"] = .integer(7)
        let keys = RegramSetting.all.map(\.key).filter { $0.hasPrefix("translationLLM") || ["translationBackend", "serviceConfigurationRevision"].contains($0) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let legacy = try XCTUnwrap(String(data: encoder.encode(Dictionary(uniqueKeysWithValues: keys.map { ($0, settings[$0]) })), encoding: .utf8))
        XCTAssertEqual(settings.translationIdentity, legacy)
        settings["transcriptionConfigurationRevision"] = .integer(3)
        XCTAssertEqual(settings.translationIdentity, legacy)
    }

    func testOnlyTranscriptionConfigurationChangesInvalidateTranscriptions() {
        let original = RegramAccountSettings()
        let relevant: Set<String> = ["transcriptionBackend", "serviceConfigurationRevision", "transcriptionConfigurationRevision", "sttBaseURL", "sttEndpoint", "sttModel", "sttLanguage", "sttPrompt"]
        for setting in RegramSetting.all {
            var changed = original
            changed[setting.key] = alternative(setting)
            XCTAssertEqual(changed.hasSameTranscriptionConfiguration(as: original), !relevant.contains(setting.key), setting.key)
            XCTAssertEqual(original.hasSameTranscriptionConfiguration(as: changed), !relevant.contains(setting.key), setting.key)
        }
    }

    func testIndependentServiceRevisionsSurvivePersistenceWithoutCrossInvalidation() {
        let suite = "RegramFeatureIsolationTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RegramPreferences(defaults: defaults)
        let initial = store.settings(accountId: 42)
        store.update(accountId: 42) { $0["transcriptionConfigurationRevision"] = .integer(1) }
        let transcription = store.settings(accountId: 42)
        XCTAssertEqual(transcription.translationIdentity, initial.translationIdentity)
        XCTAssertFalse(transcription.hasSameTranscriptionConfiguration(as: initial))
        store.update(accountId: 42) { $0["translationConfigurationRevision"] = .integer(1) }
        let translation = RegramPreferences(defaults: defaults).settings(accountId: 42)
        XCTAssertNotEqual(translation.translationIdentity, transcription.translationIdentity)
        XCTAssertTrue(translation.hasSameTranscriptionConfiguration(as: transcription))
        XCTAssertEqual(store.settings(accountId: 43), initial)
        XCTAssertEqual(translation["serviceConfigurationRevision"].integer, 0)
    }

    func testIndependentFeaturesDoNotOverrideFilteringAndPerChatInputOverrides() {
        var original = RegramAccountSettings()
        original.filterRules = [RGMessageFilterRule(pattern: "blocked"), RGMessageFilterRule(pattern: "allowed", isException: true)]
        original["blockedPeerIds"] = .strings(["3"])
        original["messageFilterDisabledPeerIds"] = .strings(["4"])
        original["panguSpacing"] = .bool(true)
        original["defaultOutgoingFormatting"] = .string("bold")
        original["chatPreferences"] = .string("{\"1:2\":{\"formatting\":\"none\",\"panguSpacing\":false}}")
        let filterKeys: Set<String> = ["messageFilterRules", "blockedPeerIds", "messageFilterDisabledPeerIds", "chatPreferences", "panguSpacing", "defaultOutgoingFormatting"]
        for setting in RegramSetting.all where !filterKeys.contains(setting.key) {
            var changed = original
            changed[setting.key] = alternative(setting)
            let filter = RegramFilterSnapshot(settings: changed)
            XCTAssertTrue(filter.shouldHide(text: "blocked", peerId: 2, authorId: 5, incoming: true), setting.key)
            XCTAssertFalse(filter.shouldHide(text: "blocked allowed", peerId: 2, authorId: 5, incoming: true), setting.key)
            XCTAssertFalse(filter.shouldHide(text: "blocked", peerId: 4, authorId: 5, incoming: true), setting.key)
            XCTAssertTrue(filter.shouldHide(text: "allowed", peerId: 4, authorId: 3, incoming: true), setting.key)
            XCTAssertFalse(filter.shouldHide(text: "blocked", peerId: 2, authorId: 3, incoming: false), setting.key)
            XCTAssertEqual(changed.chatPreferences(accountId: 1, peerId: 2), RGChatPreferences(formatting: "none", panguSpacing: false), setting.key)
            XCTAssertEqual(changed.chatPreferences(accountId: 1, peerId: 3), RGChatPreferences(), setting.key)
        }
    }
}
