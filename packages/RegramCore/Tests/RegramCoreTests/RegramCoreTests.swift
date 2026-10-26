import XCTest
@testable import RegramCore

final class RegramCoreTests: XCTestCase {
    func testNotificationFeaturesAreExcludedFromSettingsAndBackups() throws {
        XCTAssertFalse(RegramSettingsScope.includesNotifications)
        XCTAssertFalse(RegramBackupCategory.available.contains(.notifications))
        XCTAssertNil(RegramSettingsRoute(page: "notifications"))
        let data = Data("{\"version\":1,\"createdAt\":\"2026-10-25T00:00:00Z\",\"values\":{\"filterNotifications\":true,\"pinnedMessageNotifications\":\"disabled\"}}".utf8)
        let backup = try RegramSettingsBackup.decode(data)
        XCTAssertEqual(backup.skippedKeys, ["filterNotifications", "pinnedMessageNotifications"])
        XCTAssertTrue(backup.applying(to: RegramAccountSettings()).values.isEmpty)
    }

    func testQuickTranslationCancellationKeepsAccountsAndNewRequestsIsolated() throws {
        let tasks = RegramQuickTranslationTasks()
        let id = RGBookmarkMessageId(peerId: 20, namespace: 0, id: 1)
        let first = try XCTUnwrap(tasks.begin(accountId: 1, messageId: id, language: "en"))
        XCTAssertNil(tasks.begin(accountId: 1, messageId: id, language: "fr"))
        XCTAssertNotNil(tasks.begin(accountId: 2, messageId: id, language: "fr"))
        XCTAssertTrue(tasks.finish(accountId: 1, messageId: id, token: first))
        let replacement = try XCTUnwrap(tasks.begin(accountId: 1, messageId: id, language: "de"))
        XCTAssertFalse(tasks.finish(accountId: 1, messageId: id, token: first))
        XCTAssertEqual(tasks.task(accountId: 1, messageId: id)?.token, replacement)
        XCTAssertEqual(tasks.task(accountId: 2, messageId: id)?.language, "fr")
        for number in 2...3 { XCTAssertNotNil(tasks.begin(accountId: 1, messageId: RGBookmarkMessageId(peerId: 20, namespace: 0, id: Int32(number)), language: "en")) }
        XCTAssertNil(tasks.begin(accountId: 1, messageId: RGBookmarkMessageId(peerId: 20, namespace: 0, id: 4), language: "en"))
    }

    func testMenuOrderPreservesPermissionsAndConditionalActions() {
        var settings = RegramAccountSettings()
        settings["contextMenuOrder"] = .strings(["copy", "removed-action", "copy", "reply"])
        settings["contextMenuDisabledItems"] = .strings(["delete", "sendMoney"])
        let menu = RegramContextMenuConfiguration(settings: settings)
        XCTAssertEqual(Array(menu.order.prefix(2)), [.copy, .reply])
        XCTAssertEqual(Set(menu.order), Set(RGContextMenuItemId.allCases))
        XCTAssertEqual(menu.orderedItems([(.reply, "reply"), (.delete, "delete"), (.copy, "selected text"), (.copy, "message text")]), ["selected text", "message text", "reply"])
        XCTAssertFalse(menu.orderedItems([(.copy, "copy")]).contains("reply"))
        XCTAssertTrue(menu.isEnabled(.sendMoney))
        let reordered = menu.reorderingVisible([.reply, .copy])
        XCTAssertEqual(Array(reordered.prefix(2)), [.reply, .copy])
        XCTAssertEqual(Array(reordered.dropFirst(2)), Array(menu.order.dropFirst(2)))
    }

    func testSettingsLinksOnlyNavigateToKnownDestinations() throws {
        let route = try XCTUnwrap(RegramSettingsRoute(page: "privacy", item: "antiRevoke"))
        XCTAssertEqual(RegramSettingsRoute(url: route.url), route)
        for link in ["regram://settings?page=privacy&clear=true", "regram://settings?page=privacy&page=tools", "regram://settings?page=privacy&item=panguSpacing", "https://settings?page=privacy", "regram://settings?page=unknown"] {
            XCTAssertNil(RegramSettingsRoute(url: try XCTUnwrap(URL(string: link))))
        }
    }

    func testBackupMigratesRemovedModesAndExcludesNonportablePremium() throws {
        let data = Data("{\"version\":1,\"createdAt\":\"2026-10-25T00:00:00Z\",\"values\":{\"translationBackend\":\"gtranslate\",\"downloadSpeedBoost\":\"maximum\",\"chatListLines\":\"3\",\"mediaLoadingExperiment\":true,\"localPremium\":true}}".utf8)
        let backup = try RegramSettingsBackup.decode(data)
        let settings = backup.applying(to: RegramAccountSettings())
        XCTAssertEqual(settings["translationBackend"].string, "google")
        XCTAssertEqual(settings["downloadSpeedBoost"].string, "medium")
        XCTAssertEqual(settings["chatListLines"].string, "2")
        XCTAssertFalse(settings["localPremium"].bool)
        XCTAssertNil(backup.values["localPremium"])
        XCTAssertTrue(settings["mediaLoadingExperiment"].bool)
        XCTAssertTrue(backup.skippedKeys.isEmpty)
        let invalid = Data("{\"version\":1,\"createdAt\":\"2026-10-25T00:00:00Z\",\"values\":{\"messageFilterRules\":\"invalid\"}}".utf8)
        XCTAssertThrowsError(try RegramSettingsBackup.decode(invalid))
    }

    func testChatPreferencesKeepPackedIdentifiersAndAccountScope() throws {
        let peer: Int64 = 9007199254740993
        let values = [RGChatPreferences.key(accountId: 1, peerId: peer): RGChatPreferences(formatting: "bold", panguSpacing: true)]
        var settings = RegramAccountSettings()
        settings["chatPreferences"] = .string(String(decoding: try JSONEncoder().encode(values), as: UTF8.self))
        XCTAssertEqual(settings.chatPreferences(accountId: 1, peerId: peer).formatting, "bold")
        XCTAssertNil(settings.chatPreferences(accountId: 2, peerId: peer).formatting)
    }

    func testTransferPolicyPreservesSmallFilesAndAdaptiveScheduling() {
        XCTAssertEqual(RegramTransferPolicy.downloadPartSize(defaultValue: 131072, fileSize: 1024, enabled: true, adaptive: false), 131072)
        XCTAssertEqual(RegramTransferPolicy.downloadPartSize(defaultValue: 131072, fileSize: 2000000, enabled: true, adaptive: false), 524288)
        XCTAssertEqual(RegramTransferPolicy.downloadPartSize(defaultValue: 131072, fileSize: 2000000, enabled: true, adaptive: true), 131072)
        XCTAssertEqual(RegramTransferPolicy.pendingParts(defaultValue: 12, enabled: true, adaptive: true), 12)
    }

    func testKeepRuleDoesNotUnhideBlockedAuthorOrOutgoingMessages() {
        var settings = RegramAccountSettings()
        settings.filterRules = [RGMessageFilterRule(pattern: "spam"), RGMessageFilterRule(pattern: "trusted", isException: true)]
        XCTAssertTrue(settings.shouldHide(text: "SPAM", peerId: 20, authorId: 30, incoming: true))
        XCTAssertFalse(settings.shouldHide(text: "trusted spam", peerId: 20, authorId: 30, incoming: true))
        settings["blockedPeerIds"] = .strings(["30"])
        XCTAssertTrue(settings.shouldHide(text: "trusted spam", peerId: 20, authorId: 30, incoming: true))
        XCTAssertFalse(settings.shouldHide(text: "spam", peerId: 20, authorId: 30, incoming: false))
        settings["messageFilterDisabledPeerIds"] = .strings(["20"])
        XCTAssertTrue(settings.shouldHide(text: "trusted", peerId: 20, authorId: 30, incoming: true))
        XCTAssertFalse(settings.shouldHide(text: "spam", peerId: 20, authorId: 40, incoming: true))
    }

    func testLegacyRuleDefaultsAndExactPeerIdentifiers() throws {
        let raw = "[{\"id\":\"legacy\",\"pattern\":\"blocked\",\"isRegex\":false,\"peerIds\":[9007199254740993]}]"
        let rules = RGMessageFilter.decode(raw)
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.peerIds, [9007199254740993])
        XCTAssertEqual(rules.first?.isEnabled, true)
        XCTAssertEqual(rules.first?.isException, false)
        XCTAssertTrue(RGMessageFilter.shouldHide(text: "blocked", peerId: 9007199254740993, rules: rules))
        XCTAssertFalse(RGMessageFilter.shouldHide(text: "blocked", peerId: 9007199254740992, rules: rules))
        XCTAssertFalse(RGMessageFilter.shouldHide(text: "blocked", peerId: nil, rules: rules))
    }

    func testInvalidAndDisabledRegexStayVisible() {
        XCTAssertEqual(RGMessageFilter.matchResult(rule: RGMessageFilterRule(pattern: "[", isRegex: true), text: "text"), .invalidRegex)
        XCTAssertEqual(RGMessageFilter.matchResult(rule: RGMessageFilterRule(pattern: ".*", isRegex: true, isEnabled: false), text: "text"), .disabled)
    }

    func testSettingsPersistAndRemainIsolatedBetweenAccounts() throws {
        let name = "RegramCoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = RegramPreferences(defaults: defaults)
        store.update(accountId: 10) { $0["panguSpacing"] = .bool(true) }
        store.update(accountId: 20) { $0["defaultOutgoingFormatting"] = .string("bold") }
        let restored = RegramPreferences(defaults: defaults)
        XCTAssertTrue(restored.settings(accountId: 10)["panguSpacing"].bool)
        XCTAssertFalse(restored.settings(accountId: 20)["panguSpacing"].bool)
        XCTAssertEqual(restored.settings(accountId: 20)["defaultOutgoingFormatting"].string, "bold")
        store.reset(accountId: 10, category: .input)
        XCTAssertFalse(store.settings(accountId: 10)["panguSpacing"].bool)
        XCTAssertEqual(store.settings(accountId: 20)["defaultOutgoingFormatting"].string, "bold")
    }

    func testBackupRejectsUnsupportedVersionAndDoesNotImportCredentials() throws {
        let data = Data("{\"version\":1,\"createdAt\":\"2026-10-25T00:00:00Z\",\"values\":{\"panguSpacing\":true,\"apiKey\":\"fixture-only\",\"mobileOnly\":1.5}}".utf8)
        let backup = try RegramSettingsBackup.decode(data)
        XCTAssertTrue(backup.values.keys.allSatisfy { !["apiKey", "mobileOnly"].contains($0) })
        let applied = backup.applying(to: RegramAccountSettings(), categories: [.messages])
        XCTAssertTrue(applied["panguSpacing"].bool)
        XCTAssertNil(applied.values["apiKey"])
        XCTAssertThrowsError(try RegramSettingsBackup.decode(Data("{\"version\":5,\"createdAt\":\"2026-10-25T00:00:00Z\",\"values\":{}}".utf8)))
    }

    func testBackupCategorySelectionAndRoundTrip() throws {
        var settings = RegramAccountSettings()
        settings["panguSpacing"] = .bool(true)
        settings["ghostDontSendOnline"] = .bool(true)
        let backup = RegramSettingsBackup(settings: settings, categories: [.messages])
        let decoded = try RegramSettingsBackup.decode(backup.encoded())
        let restored = decoded.applying(to: RegramAccountSettings())
        XCTAssertTrue(restored["panguSpacing"].bool)
        XCTAssertFalse(restored["ghostDontSendOnline"].bool)
        XCTAssertNil(decoded.values["ghostDontSendOnline"])
    }

    func testPanguPreservesProtectedUtf16Ranges() {
        let text = "你好world 链接abc"
        let protected = (text as NSString).range(of: "链接abc")
        let transformed = RGFeaturePangu.transform(text, protectedUtf16Ranges: [protected.location..<(protected.location + protected.length)])
        XCTAssertTrue(transformed.text.contains("你好 world"))
        XCTAssertTrue(transformed.text.contains("链接abc"))
    }

    func testPreviewRepairOnlyChangesTheRequestHost() {
        let original = "https://x.com/example/status/123?text=a%20b#media"
        XCTAssertEqual(RGLinkPreviewRules.repair(original, enabled: false, xHost: "fixupx.com", instagramHost: "ddinstagram.com"), original)
        let repaired = RGLinkPreviewRules.repair(original, enabled: true, xHost: "fixupx.com", instagramHost: "ddinstagram.com")
        XCTAssertEqual(URLComponents(string: repaired)?.host, "fixupx.com")
        XCTAssertEqual(URLComponents(string: repaired)?.path, "/example/status/123")
        XCTAssertEqual(URLComponents(string: repaired)?.fragment, "media")
        XCTAssertFalse(RGLinkPreviewRules.isValidHost("https://invalid.example/path"))
    }

    func testBookmarkTagsAndAccountIsolation() throws {
        let name = "RegramBookmarkTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = RGMessageBookmarks(defaults: defaults)
        let id = RGBookmarkMessageId(peerId: 40, namespace: 0, id: 9)
        store.save(accountId: 1, messageId: id, threadId: 3, tags: [" Tag ", "tag", "line\nbreak"])
        XCTAssertEqual(store.bookmarks(accountId: 1).first?.tags, ["Tag", "line break"])
        XCTAssertEqual(store.bookmarks(accountId: 1).first?.threadId, 3)
        XCTAssertTrue(store.bookmarks(accountId: 2).isEmpty)
        XCTAssertEqual(RGMessageBookmarks(defaults: defaults).bookmarks(accountId: 1).count, 1)
    }
}
