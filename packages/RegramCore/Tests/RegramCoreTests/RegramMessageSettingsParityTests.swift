import XCTest
@testable import RegramCore

final class RegramMessageSettingsParityTests: XCTestCase {
    func testMenuUsesSourceDefaultsAndObservedConditionalActions() {
        let name = "regram-menu-parity-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let inventory = RegramMessageMenuInventory(defaults: defaults)
        XCTAssertFalse(inventory.available().contains(.sendGift))
        XCTAssertTrue(inventory.available().contains(.speak))
        inventory.record([.sendGift, .sendMoney])
        XCTAssertTrue(inventory.available().contains(.sendGift))
        XCTAssertFalse(inventory.available().contains(.sendMoney))
        var settings = RegramAccountSettings()
        XCTAssertFalse(RegramContextMenuConfiguration(settings: settings).isEnabled(.json))
        settings["contextShowJson"] = .bool(true)
        settings["contextMenuDisabledItems"] = .strings(["json", "copy"])
        XCTAssertTrue(RegramContextMenuConfiguration(settings: settings).isEnabled(.json))
        XCTAssertFalse(RegramContextMenuConfiguration(settings: settings).isEnabled(.copy))
        XCTAssertTrue(RegramMessageMenuInventory(defaults: defaults).available().contains(.sendGift))
    }

    func testRetiredScreenshotActionIsIgnoredInLegacyMenuSettings() {
        let name = "regram-menu-parity-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(["messageScreenshot", "sendGift"], forKey: "rg_contextMenuObserved_1")
        defaults.set(["sendMoney"], forKey: "rg_contextMenuObserved_2")
        let inventory = RegramMessageMenuInventory(defaults: defaults)
        XCTAssertTrue(inventory.available().contains(.sendGift))
        XCTAssertFalse(inventory.available().contains(.sendMoney))
        XCTAssertFalse(inventory.available().map(\.rawValue).contains("messageScreenshot"))

        let settings = RegramAccountSettings(values: [
            "contextMenuOrder": .strings(["translate", "messageScreenshot", "copy", "reply"]),
            "contextMenuDisabledItems": .strings(["messageScreenshot", "copy"])
        ])
        let menu = RegramContextMenuConfiguration(settings: settings)
        XCTAssertEqual(Array(menu.order.prefix(3)), [.translate, .copy, .reply])
        XCTAssertFalse(menu.order.map(\.rawValue).contains("messageScreenshot"))
        XCTAssertEqual(menu.disabled, [.copy])
    }

    func testStartupFolderSharesNamedSelectionAndRemembersEachAccountsLastVisit() throws {
        let name = "regram-folder-parity-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var settings = RegramAccountSettings()
        RegramChatListPolicy.recordSelectedFolderId(8, accountId: 1, defaults: defaults)
        RegramChatListPolicy.recordSelectedFolderId(9, accountId: 2, defaults: defaults)
        settings["features.chatListStartupFolderMode"] = .string("last")
        XCTAssertEqual(RegramChatListPolicy.startupFolderId(settings: settings, accountId: 1, defaults: defaults), 8)
        XCTAssertEqual(RegramChatListPolicy.startupFolderId(settings: settings, accountId: 2, defaults: defaults), 9)
        RegramChatListPolicy.clear(accountId: 1, defaults: defaults)
        XCTAssertNil(RegramChatListPolicy.startupFolderId(settings: settings, accountId: 1, defaults: defaults))
        XCTAssertEqual(RegramChatListPolicy.startupFolderId(settings: settings, accountId: 2, defaults: defaults), 9)
        settings["features.chatListStartupFolderMode"] = .string("specific")
        settings["features.startupFolders"] = .dictionary(["1": "5", "2": "7"])
        RegramChatListPolicy.keepLegacyStartupFolder(settings: &settings, accountId: 1)
        RegramChatListPolicy.migrateLegacyStartupFolder(settings: &settings, accountId: 1, folders: [(5, "Work")])
        XCTAssertEqual(RegramChatListPolicy.startupFolder(settings: settings), .named("Work"))
        let backup = try RegramSettingsBackup.decode(RegramSettingsBackup(settings: settings, categories: [.appearance]).encoded())
        settings = backup.applying(to: RegramAccountSettings(), legacyAccountId: 2)
        XCTAssertEqual(RegramChatListPolicy.startupFolderId(settings: settings, accountId: 1, folders: [(5, "Work")], defaults: defaults), 5)
        XCTAssertEqual(RegramChatListPolicy.startupFolderId(settings: settings, accountId: 2, folders: [(5, "Personal"), (7, "Work")], defaults: defaults), 7)
        XCTAssertNil(RegramChatListPolicy.startupFolderId(settings: settings, accountId: 2, folders: [(5, "Personal")], defaults: defaults))
        settings["features.startupFolders"] = RegramChatListPolicy.StartupFolder.allChats.storedValue
        XCTAssertEqual(RegramChatListPolicy.startupFolderId(settings: settings, accountId: 2, defaults: defaults), -1)
        settings["features.chatListFolderTabDisplayMode"] = .string("both")
        XCTAssertEqual(RegramChatListPolicy.folderTitle(text: "Native", icon: "X", allChats: true, shortAllChats: "All", longAllChats: "All Chats", settings: settings), "Native")
        settings["allChatsTitleLengthOverride"] = .string("long")
        XCTAssertEqual(RegramChatListPolicy.folderTitle(text: "unused", icon: "X", allChats: true, shortAllChats: "All", longAllChats: "All Chats", settings: settings), "unused")
    }
}
