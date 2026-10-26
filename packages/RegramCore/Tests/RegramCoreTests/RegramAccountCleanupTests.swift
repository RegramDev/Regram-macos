import XCTest
@testable import RegramCore

final class RegramAccountCleanupTests: XCTestCase {
    func testRemovingAccountClearsPersistedSettingsAndCachedFiltersOnlyForThatAccount() throws {
        let name = "Regram.AccountCleanupTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = RegramPreferences(defaults: defaults)
        for account in [Int64(1), 2] {
            preferences.update(accountId: account) { $0["blockedPeerIds"] = .strings(["10"]); $0["localPremium"] = .bool(true) }
            XCTAssertTrue(preferences.filter(accountId: account).shouldHide(text: "", peerId: 30, authorId: 10, incoming: true))
        }
        preferences.removeAccount(1)
        XCTAssertFalse(preferences.settings(accountId: 1)["localPremium"].bool)
        XCTAssertFalse(preferences.filter(accountId: 1).shouldHide(text: "", peerId: 30, authorId: 10, incoming: true))
        let reloaded = RegramPreferences(defaults: defaults)
        XCTAssertFalse(reloaded.settings(accountId: 1)["localPremium"].bool)
        XCTAssertTrue(reloaded.settings(accountId: 2)["localPremium"].bool)
        XCTAssertTrue(preferences.filter(accountId: 2).shouldHide(text: "", peerId: 30, authorId: 10, incoming: true))
    }

    func testAccountTaskCleanupRejectsLateCompletionAndPreservesOtherAccount() throws {
        let tasks = RegramQuickTranslationTasks()
        let message = RGBookmarkMessageId(peerId: 30, namespace: 0, id: 10)
        let token = try XCTUnwrap(tasks.begin(accountId: 1, messageId: message, language: "en"))
        let other = try XCTUnwrap(tasks.begin(accountId: 2, messageId: message, language: "en"))
        tasks.clear(accountId: 1)
        XCTAssertFalse(tasks.finish(accountId: 1, messageId: message, token: token))
        XCTAssertEqual(tasks.task(accountId: 2, messageId: message)?.token, other)
        XCTAssertNotNil(tasks.begin(accountId: 1, messageId: message, language: "en"))
    }
}
