import XCTest
@testable import RegramCore

final class RegramMessageSettingsParityTests: XCTestCase {
    func testMenuUsesSourceDefaultsAndObservedConditionalActions() {
        let name = "regram-menu-parity-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let inventory = RegramMessageMenuInventory(defaults: defaults)
        XCTAssertFalse(inventory.available(accountId: 1).contains(.sendGift))
        XCTAssertTrue(inventory.available(accountId: 1).contains(.speak))
        inventory.record([.sendGift, .sendMoney], accountId: 1)
        XCTAssertTrue(inventory.available(accountId: 1).contains(.sendGift))
        XCTAssertFalse(inventory.available(accountId: 1).contains(.sendMoney))
        XCTAssertFalse(inventory.available(accountId: 2).contains(.sendGift))
        var settings = RegramAccountSettings()
        XCTAssertFalse(RegramContextMenuConfiguration(settings: settings).isEnabled(.json))
        settings["contextShowJson"] = .bool(true)
        settings["contextMenuDisabledItems"] = .strings(["json", "copy"])
        XCTAssertTrue(RegramContextMenuConfiguration(settings: settings).isEnabled(.json))
        XCTAssertFalse(RegramContextMenuConfiguration(settings: settings).isEnabled(.copy))
        inventory.clear(accountId: 1)
        XCTAssertFalse(inventory.available(accountId: 1).contains(.sendGift))
    }

    func testStartupFolderUsesSourceAccountKeyAndKeepsAccountsSeparate() {
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
        settings["features.startupFolders"] = .dictionary(["1": "-1"])
        XCTAssertEqual(RegramChatListPolicy.startupFolderId(settings: settings, accountId: 1, defaults: defaults), -1)
        XCTAssertNil(RegramChatListPolicy.startupFolderId(settings: settings, accountId: 2, defaults: defaults))
        settings["features.chatListFolderTabDisplayMode"] = .string("both")
        XCTAssertEqual(RegramChatListPolicy.folderTitle(text: "Native", icon: "X", allChats: true, shortAllChats: "All", longAllChats: "All Chats", settings: settings), "Native")
        settings["allChatsTitleLengthOverride"] = .string("long")
        XCTAssertEqual(RegramChatListPolicy.folderTitle(text: "unused", icon: "X", allChats: true, shortAllChats: "All", longAllChats: "All Chats", settings: settings), "unused")
    }
}
