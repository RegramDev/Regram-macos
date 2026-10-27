import XCTest
@testable import RegramCore

final class RegramMessageBookmarkPreferenceTests: XCTestCase {
    func testDefaultAndSchemaPreserveExistingBookmarkExperience() throws {
        let definition = try XCTUnwrap(RegramSetting.byKey["messageBookmarksEnabled"])
        XCTAssertEqual(definition.category, .messages)
        XCTAssertEqual(definition.defaultValue, .bool(true))
        XCTAssertTrue(RegramSetting.availableKeys.contains(definition.key))
        XCTAssertTrue(definition.accepts(.bool(false)))
        XCTAssertFalse(definition.accepts(.string("false")))
        XCTAssertTrue(RegramAccountSettings()[definition.key].bool)
    }

    func testSwitchPersistsPerAccountWithoutChangingBookmarksOrTags() throws {
        let suite = "RegramBookmarkPreferenceTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = RegramPreferences(defaults: defaults)
        let store = RGMessageBookmarks(defaults: defaults)
        let id = RGBookmarkMessageId(peerId: 40, namespace: 0, id: 9)
        store.save(accountId: 1, messageId: id, threadId: 3, tags: ["Read", "Keep"], now: 42)
        store.save(accountId: 2, messageId: id, threadId: 4, tags: ["Other"], now: 43)
        let previous = store.bookmarks(accountId: 1)
        preferences.update(accountId: 1) { $0["messageBookmarksEnabled"] = .bool(false) }
        XCTAssertFalse(RegramPreferences(defaults: defaults).settings(accountId: 1)["messageBookmarksEnabled"].bool)
        XCTAssertTrue(preferences.settings(accountId: 2)["messageBookmarksEnabled"].bool)
        XCTAssertEqual(RGMessageBookmarks(defaults: defaults).bookmarks(accountId: 1), previous)
        preferences.update(accountId: 1) { $0["messageBookmarksEnabled"] = .bool(true) }
        XCTAssertTrue(RegramPreferences(defaults: defaults).settings(accountId: 1)["messageBookmarksEnabled"].bool)
        XCTAssertEqual(RGMessageBookmarks(defaults: defaults).bookmarks(accountId: 1), previous)
        XCTAssertEqual(store.tags(accountId: 1), ["Keep", "Read"])
        XCTAssertEqual(store.tags(accountId: 2), ["Other"])
    }

    func testMessagesBackupAndResetIncludeSwitchWithoutStoringBookmarkData() throws {
        var settings = RegramAccountSettings()
        settings["messageBookmarksEnabled"] = .bool(false)
        settings["hidePhoneInSettings"] = .bool(false)
        let backup = RegramSettingsBackup(settings: settings, categories: [.messages])
        XCTAssertEqual(RegramSettingsBackup.category(for: "messageBookmarksEnabled"), .messages)
        XCTAssertEqual(backup.values["messageBookmarksEnabled"], .bool(false))
        let restored = try RegramSettingsBackup.decode(backup.encoded()).applying(to: RegramAccountSettings(), categories: [.messages])
        XCTAssertFalse(restored["messageBookmarksEnabled"].bool)
        let reset = RegramSettingsBackup(values: [:]).applying(to: settings, categories: [], resetCategories: [.messages])
        XCTAssertTrue(reset["messageBookmarksEnabled"].bool)
        XCTAssertFalse(reset["hidePhoneInSettings"].bool)
        XCTAssertNil(RegramSettingsBackup(settings: settings, categories: [.privacy]).values["messageBookmarksEnabled"])
        XCTAssertEqual(RegramSettingsBackup(settings: RegramAccountSettings(), categories: [.messages]).values["messageBookmarksEnabled"], .bool(true))
    }

    func testSwitchRemainsSearchableAndRoutesToMessageActions() throws {
        let target = "settings.messageActions/messageBookmarksEnabled"
        for (query, language) in [("bookmarks", "en"), ("书签", "zh-Hans"), ("書籤", "zh-Hant"), ("messageBookmarksEnabled", "en")] {
            let entry = try XCTUnwrap(RegramSettingsCatalog.results(query: query, language: language).first { $0.destination == target })
            XCTAssertEqual(entry.category, .messages)
            XCTAssertEqual(entry.titleKey, "Bookmarks.Title")
        }
        let route = try XCTUnwrap(RegramSettingsRoute(page: "settings.messageActions", item: "messageBookmarksEnabled"))
        XCTAssertEqual(route.destination, target)
        XCTAssertEqual(RegramSettingsRoute(url: route.url), route)
    }
}
