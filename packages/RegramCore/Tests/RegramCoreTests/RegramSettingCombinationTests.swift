import XCTest
import RegramSignals
import SwiftSignalKit
@testable import RegramCore

final class RegramSettingCombinationTests: XCTestCase {
    private func alternate(_ setting: RegramSetting) -> RegramValue {
        switch setting.key {
        case "messageFilterRules": return .string(RGMessageFilter.encode([RGMessageFilterRule(pattern: "blocked")]))
        case "chatPreferences": return .string("{\"101:2\":{\"formatting\":\"none\",\"panguSpacing\":false}}")
        case "customDoHEndpoint": return .string("https://resolver.example.test/dns-query")
        case "linkPreviewXHost": return .string("fixupx.com")
        case "linkPreviewInstagramHost": return .string("example.test")
        case "fontImportedLatin", "fontImportedChinese": return .string(String(repeating: "a", count: 64))
        case "features.groupProfileSettingItems": return .string("admins,members,permissions")
        case "features.startupFolders": return .dictionary(["101": "12", "202": "15"])
        case "bottomBarLayout":
            return .dictionary(RegramBottomBarSettings(automaticWidth: false, hiddenItems: [.contacts, .calls, .search], showLabels: true, buttonWidthFillRatio: 75).storedValues)
        case "tabBarWidthPercent": return .integer(75)
        case "contextMenuOrder": return .strings(["translate", "bookmark", "copy", "reply"])
        case "contextMenuDisabledItems": return .strings(["translate", "bookmark"])
        case "sidebarOrder": return .strings(["settings", "chats", "contacts"])
        case "sidebarHiddenTabs": return .strings(["contacts"])
        case "outgoingLanguageTranslation": return .dictionary(["v2:101:2": "ja", "v2:101:3": "off"])
        case "localPremiumEmojiStatus": return .dictionary(["101": "42"])
        case "revokedMarkerColor": return .string("#123456")
        default: break
        }
        if let choice = setting.choices.first(where: { $0 != setting.defaultValue }) { return choice }
        switch setting.defaultValue {
        case let .bool(value): return .bool(!value)
        case let .integer(value): return .integer(value + 1)
        case let .number(value): return .number(value + 1)
        case .string: return .string("fixture")
        case .strings: return .strings(["3"])
        case .dictionary: return .dictionary(["101": "2"])
        }
    }

    private func enabledSettings() -> RegramAccountSettings {
        var settings = RegramAccountSettings()
        for entry in RegramSetting.all {
            if case .bool = entry.defaultValue { settings[entry.key] = .bool(true) }
            else { settings[entry.key] = alternate(entry) }
        }
        return settings
    }

    func testEverySettingPairPreservesValuesInBothWriteOrdersAndCodableRoundTrip() throws {
        let settings = RegramSetting.all
        let aliasKeys: Set<String> = ["native.enableVoipTcp", "enableVoipTcp"]
        var pairs = 0
        var cases = 0
        for first in settings.indices {
            for second in settings.indices where second > first {
                let a = settings[first]
                let b = settings[second]
                pairs += 1
                for av in [a.defaultValue, alternate(a)] {
                    for bv in [b.defaultValue, alternate(b)] {
                        var forward = RegramAccountSettings()
                        forward[a.key] = av
                        forward[b.key] = bv
                        var reverse = RegramAccountSettings()
                        reverse[b.key] = bv
                        reverse[a.key] = av
                        let label = a.key + "/" + b.key
                        if aliasKeys.contains(a.key) && aliasKeys.contains(b.key) {
                            XCTAssertEqual(forward[a.key], bv, label)
                            XCTAssertEqual(reverse[b.key], av, label)
                        } else {
                            XCTAssertEqual(forward[a.key], av, label)
                            XCTAssertEqual(forward[b.key], bv, label)
                            XCTAssertEqual(reverse[a.key], av, label)
                            XCTAssertEqual(reverse[b.key], bv, label)
                            XCTAssertEqual(forward, reverse, label)
                        }
                        let restored = try JSONDecoder().decode(RegramAccountSettings.self, from: JSONEncoder().encode(forward))
                        XCTAssertEqual(restored, forward, label)
                        cases += 1
                    }
                }
            }
        }
        print("SETTING_PAIR_COVERAGE settings=\(settings.count) pairs=\(pairs) cases=\(cases) writeOrders=2")
    }

    func testFilteringAndRevokePrioritiesWithOtherFeaturesEnabled() {
        let baseline = enabledSettings()
        for mask in 0..<4096 {
            func bit(_ index: Int) -> Bool { mask & (1 << index) != 0 }
            var settings = baseline
            settings.filterRules = [RGMessageFilterRule(pattern: "blocked", isEnabled: bit(0)), RGMessageFilterRule(pattern: "keep", isEnabled: bit(1), isException: true)]
            settings["blockedPeerIds"] = .strings(bit(2) ? ["9"] : [])
            settings["messageFilterDisabledPeerIds"] = .strings(bit(3) ? ["2"] : [])
            settings["antiRevoke"] = .bool(bit(5))
            settings["antiRevokePeerIds"] = .strings(bit(6) ? ["2"] : [])
            settings["antiRevokeSkipBots"] = .bool(bit(7))
            settings["allowSavingProtectedContent"] = .bool(bit(9))
            settings["quickTranslateButton"] = .bool(bit(10))
            settings["features.enablePanguOnReceiving"] = .bool(bit(11))
            let shouldHide = bit(4) && (bit(2) || (bit(0) && !bit(3) && !bit(1)))
            let filter = RegramFilterSnapshot(settings: settings)
            XCTAssertEqual(filter.shouldHide(text: "blocked keep", peerId: 2, authorId: 9, incoming: bit(4)), shouldHide, "mask \(mask)")
            XCTAssertEqual(settings.shouldHide(text: "blocked keep", peerId: 2, authorId: 9, incoming: bit(4)), shouldHide, "mask \(mask)")
            XCTAssertEqual(settings.shouldRetainRevokedMessage(peerId: 2, authorIsBot: bit(8)), (bit(5) || bit(6)) && (!bit(7) || !bit(8)), "mask \(mask)")
            XCTAssertEqual(settings.shouldRetainRevokedMessage(peerId: 3, authorIsBot: bit(8)), bit(5) && (!bit(7) || !bit(8)), "mask \(mask)")
            XCTAssertEqual(settings.chatPreferences(accountId: 101, peerId: 2), RGChatPreferences(formatting: "none", panguSpacing: false))
        }
        print("PRIVACY_COMBINATIONS cases=4096")
    }

    func testNetworkMediaAndNavigationChangesPreserveEachOther() {
        var cases = 0
        for mode in RegramNetworkPolicy.DNSMode.allCases {
            for ip in RegramNetworkPolicy.IPVersion.allCases {
                for mask in 0..<64 {
                    func bit(_ index: Int) -> Bool { mask & (1 << index) != 0 }
                    var settings = enabledSettings()
                    settings["outgoingPhotoQuality"] = .integer(72)
                    settings["sendLargePhotos"] = .bool(bit(0))
                    settings["clipboardOriginalImages"] = .bool(bit(1))
                    settings["native.showCallsTab"] = .bool(bit(2))
                    settings["uploadSpeedBoost"] = .bool(bit(3))
                    settings["downloadSpeedBoost"] = .string(bit(4) ? "medium" : "none")
                    settings["enableVoipTcp"] = .bool(bit(5))
                    let before = settings
                    var layout = RegramBottomBarSettings(settings: settings)
                    layout.showLabels = bit(0)
                    layout.automaticWidth = false
                    layout.buttonWidthFillRatio = 75
                    layout.setVisible(.contacts, visible: bit(1))
                    layout.apply(to: &settings)
                    var network = RegramNetworkPolicy(settings: settings)
                    network.dnsMode = mode
                    network.ipVersion = ip
                    network.endpoint = "https://resolver.example.test/dns-query"
                    network.apply(to: &settings)
                    XCTAssertEqual(RegramNetworkPolicy(settings: settings), network)
                    XCTAssertEqual(RGMediaPolicy.photoQuality(settings: settings), 0.72)
                    XCTAssertEqual(RGMediaPolicy.photoQuality(settings: settings, pasted: true), 1)
                    XCTAssertEqual(RGMediaPolicy.photoMaximumDimension(native: 1280, settings: settings), bit(0) ? 2560 : 1280)
                    XCTAssertEqual(settings["native.enableVoipTcp"].bool, bit(5))
                    XCTAssertEqual(settings["native.showCallsTab"].bool, bit(2))
                    XCTAssertEqual(RegramBottomBarSettings(settings: settings).showLabels, bit(0))
                    XCTAssertEqual(RegramBottomBarSettings(settings: settings).isVisible(.contacts), bit(1))
                    XCTAssertEqual(settings.translationIdentity, before.translationIdentity)
                    XCTAssertTrue(settings.hasSameTranscriptionConfiguration(as: before))
                    XCTAssertEqual(settings["chatPreferences"], before["chatPreferences"])
                    XCTAssertEqual(RegramTransferPolicy.pendingParts(defaultValue: 2, enabled: bit(3), adaptive: false), bit(3) ? 8 : 2)
                    cases += 1
                }
            }
        }
        print("NETWORK_MEDIA_NAVIGATION_COMBINATIONS cases=\(cases)")
    }

    func testEveryPartialBackupSelectionPreservesUnselectedFeaturesAndAccountIsolation() throws {
        let suite = "RegramSettingCombinationTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RegramPreferences(defaults: defaults)
        let source = enabledSettings()
        let target = RegramAccountSettings()
        let categories = RegramBackupCategory.available
        var cases = 0
        for mask in 0..<(1 << categories.count) {
            let selected = Set(categories.indices.filter { mask & (1 << $0) != 0 }.map { categories[$0] })
            let backup = try RegramSettingsBackup.decode(RegramSettingsBackup(settings: source, categories: selected).encoded())
            let restored = backup.applying(to: target, categories: selected)
            for entry in RegramSetting.all {
                if RegramSettingsBackup.category(for: entry.key).map({ !selected.contains($0) }) ?? true {
                    if entry.key == "enableVoipTcp", selected.contains(.media) { continue }
                    XCTAssertEqual(restored[entry.key], target[entry.key], "\(mask): \(entry.key)")
                }
            }
            store.update(accountId: 101) { $0 = restored }
            let reopened = RegramPreferences(defaults: defaults).settings(accountId: 101)
            for key in restored.values.keys { XCTAssertEqual(reopened[key], restored[key], "\(mask): \(key)") }
            XCTAssertEqual(store.settings(accountId: 202), target)
            cases += 1
        }
        print("PARTIAL_BACKUP_COMBINATIONS categories=\(categories.count) cases=\(cases)")
    }

    func testIndependentSettingsKeepActiveTranslationAndSpeechIdentitiesInDenseConfiguration() {
        let original = enabledSettings()
        let translationKeys: Set<String> = ["translationBackend", "serviceConfigurationRevision", "translationConfigurationRevision"]
        let speechKeys: Set<String> = ["transcriptionBackend", "serviceConfigurationRevision", "transcriptionConfigurationRevision", "sttBaseURL", "sttEndpoint", "sttModel", "sttLanguage", "sttPrompt"]
        let identity = original.translationIdentity
        for entry in RegramSetting.all {
            var changed = original
            changed[entry.key] = entry.defaultValue
            if !translationKeys.contains(entry.key), !entry.key.hasPrefix("translationLLM") {
                XCTAssertEqual(changed.translationIdentity, identity, entry.key)
            }
            if !speechKeys.contains(entry.key) {
                XCTAssertTrue(changed.hasSameTranscriptionConfiguration(as: original), entry.key)
            }
        }
    }

    func testEveryCategoryResetCombinationPreservesOtherEnabledFeatures() {
        let original = enabledSettings()
        let defaults = RegramAccountSettings()
        let categories = RegramBackupCategory.available
        for mask in 0..<(1 << categories.count) {
            let selected = Set(categories.indices.filter { mask & (1 << $0) != 0 }.map { categories[$0] })
            let result = RegramSettingsBackup(values: [:]).applying(to: original, categories: [], resetCategories: selected)
            for entry in RegramSetting.all {
                let reset = entry.key == "enableVoipTcp" ? selected.contains(.media) : RegramSettingsBackup.category(for: entry.key).map(selected.contains) ?? false
                XCTAssertEqual(result[entry.key], reset ? defaults[entry.key] : original[entry.key], "\(mask): \(entry.key)")
            }
        }
        print("CATEGORY_RESET_COMBINATIONS cases=\(1 << categories.count)")
    }

    func testMenusAndDoubleClickOverridesRespectPermissionsWithOtherFeaturesEnabled() {
        let actions = RGMessageDoubleClickAction.allCases
        let overrides = ["sameAsUnified"] + actions.map(\.rawValue)
        let order: [RGContextMenuItemId] = [.translate, .reply, .bookmark, .delete, .select]
        var cases = 0
        for action in actions {
            for override in overrides {
                for permissionMask in 0..<16 {
                    let canEdit = permissionMask & 1 != 0
                    let canReply = permissionMask & 2 != 0
                    let bookmarks = permissionMask & 4 != 0
                    let canTranslate = permissionMask & 8 != 0
                    for menuMask in 0..<4 {
                        let showReply = menuMask & 1 != 0
                        let hideTranslation = menuMask & 2 != 0
                        for featureMask in 0..<8 {
                            var settings = RegramAccountSettings()
                            settings["messageDoubleTapAction"] = .string(action.rawValue)
                            settings["messageDoubleTapActionWithoutEditPermission"] = .string(override)
                            settings["messageBookmarksEnabled"] = .bool(bookmarks)
                            settings["hideReactions"] = .bool(featureMask & 1 != 0)
                            settings["quickTranslateButton"] = .bool(featureMask & 2 != 0)
                            settings["allowSavingProtectedContent"] = .bool(featureMask & 4 != 0)
                            settings["antiRevoke"] = .bool(featureMask & 4 != 0)
                            settings["contextShowReply"] = .bool(showReply)
                            settings["contextMenuOrder"] = .strings((order + [.reply, .translate]).map(\.rawValue))
                            settings["contextMenuDisabledItems"] = .strings(hideTranslation ? ["translate"] : [])
                            let selected = !canEdit && override != "sameAsUnified" ? RGMessageDoubleClickAction(rawValue: override)! : action
                            let expectedAction: RGMessageDoubleClickAction = !canEdit && selected == .edit ? .sendReaction : selected
                            XCTAssertEqual(RGMessageDoubleClickAction.resolved(settings: settings, canEdit: canEdit), expectedAction)
                            var generated: [(RGContextMenuItemId, String)] = [(.delete, "delete"), (.select, "select")]
                            if canReply { generated.append((.reply, "reply")) }
                            if bookmarks { generated.append((.bookmark, "bookmark")) }
                            if canTranslate { generated.append((.translate, "translate")) }
                            var expected: [String] = []
                            if canTranslate && !hideTranslation { expected.append("translate") }
                            if canReply && showReply { expected.append("reply") }
                            if bookmarks { expected.append("bookmark") }
                            expected += ["delete", "select"]
                            XCTAssertEqual(RegramContextMenuConfiguration(settings: settings).orderedItems(generated), expected)
                            cases += 1
                        }
                    }
                }
            }
        }
        print("MENU_DOUBLE_CLICK_COMBINATIONS cases=\(cases)")
    }

    func testBatchedSettingPairsNotifyEveryRelevantScopeWithoutCrossingAccounts() {
        let accountId = Int64.max - 57
        let scopes: [Set<String>] = [
            ["panguSpacing", "defaultOutgoingFormatting", "chatPreferences", "sendWithReturnKey"],
            ["messageFilterRules", "blockedPeerIds", "messageFilterDisabledPeerIds", "antiRevoke", "allowSavingProtectedContent"],
            Set(RegramSetting.all.map(\.key).filter { $0.hasPrefix("translationLLM") || ["translationBackend", "translationConfigurationRevision", "serviceConfigurationRevision"].contains($0) }),
            ["transcriptionBackend", "transcriptionConfigurationRevision", "serviceConfigurationRevision", "sttBaseURL", "sttModel", "sttEndpoint", "sttPrompt", "sttLanguage"],
            ["customDoHEnabled", "customDoHEndpoint", "localDNSForProxyHost", "enableVoipTcp", "native.enableVoipTcp", "ipVersionPolicy"],
            RegramBottomBarSettings.preferenceKeys
        ]
        var counts = Array(repeating: 0, count: scopes.count + 1)
        let subscriptions = scopes.indices.map { index in
            regramPreferenceChanges(accountId: accountId, keys: scopes[index]).start(next: { _ in counts[index] += 1 })
        } + [regramContentPreferenceChanges(accountId: accountId).start(next: { _ in counts[scopes.count] += 1 })]
        defer { subscriptions.forEach { $0.dispose() } }
        XCTAssertTrue(counts.allSatisfy { $0 == 1 })
        var pairs = 0
        for first in RegramSetting.all.indices {
            for second in RegramSetting.all.indices where second > first {
                let keys: Set<String> = [RegramSetting.all[first].key, RegramSetting.all[second].key]
                let before = counts
                NotificationCenter.default.post(name: RegramPreferences.didChange, object: accountId, userInfo: [RegramPreferences.changedKeysUserInfoKey: keys])
                for index in scopes.indices {
                    XCTAssertEqual(counts[index], before[index] + (keys.isDisjoint(with: scopes[index]) ? 0 : 1), "\(keys): scope \(index)")
                }
                XCTAssertEqual(counts[scopes.count], before[scopes.count] + (keys.isSubset(of: RegramBottomBarSettings.preferenceKeys) ? 0 : 1))
                let sameAccount = counts
                NotificationCenter.default.post(name: RegramPreferences.didChange, object: accountId - 1, userInfo: [RegramPreferences.changedKeysUserInfoKey: keys])
                XCTAssertEqual(counts, sameAccount)
                pairs += 1
            }
        }
        subscriptions.forEach { $0.dispose() }
        let disposed = counts
        NotificationCenter.default.post(name: RegramPreferences.didChange, object: accountId)
        XCTAssertEqual(counts, disposed)
        print("SETTING_NOTIFICATION_COMBINATIONS pairs=\(pairs) scopes=\(counts.count)")
    }
}
