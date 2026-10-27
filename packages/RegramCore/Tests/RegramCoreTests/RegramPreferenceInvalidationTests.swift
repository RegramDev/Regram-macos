import XCTest
import RegramSignals
import SwiftSignalKit
@testable import RegramCore

final class RegramPreferenceInvalidationTests: XCTestCase {
    func testPreferenceWritesReportChangedKeys() {
        let suite = "RegramPreferenceInvalidationTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RegramPreferences(defaults: defaults)
        let accountId = Int64.random(in: 1_000_000_000...Int64.max)
        let delivered = expectation(description: "scoped preference change")
        let observer = NotificationCenter.default.addObserver(forName: RegramPreferences.didChange, object: nil, queue: .main) { notification in
            guard notification.object as? Int64 == accountId else { return }
            XCTAssertEqual(notification.userInfo?[RegramPreferences.changedKeysUserInfoKey] as? Set<String>, ["showTabNames"])
            XCTAssertFalse(RegramPreferences.isContentChange(notification))
            delivered.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        store.update(accountId: accountId) { $0["showTabNames"] = .bool(true) }
        wait(for: [delivered], timeout: 2)
    }

    func testBottomBarChangesDoNotRefreshContentOrInvalidateMessageSnapshots() {
        let suite = "RegramPreferenceInvalidationTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RegramPreferences(defaults: defaults)
        let accountId: Int64 = 1
        let captured = store.captureFilter(accountId: accountId)
        for width in 50...100 {
            store.update(accountId: accountId) { settings in
                var layout = RegramBottomBarSettings(settings: settings)
                layout.automaticWidth = false
                layout.buttonWidthFillRatio = Int32(width)
                layout.showLabels.toggle()
                layout.apply(to: &settings)
            }
        }
        XCTAssertEqual(store.revision(accountId: accountId), captured.revision)
        XCTAssertNotNil(store.withCurrentRevision(accountId: accountId, revision: captured.revision) { true })
        store.update(accountId: accountId) { $0["showMessageId"] = .bool(true) }
        XCTAssertGreaterThan(store.revision(accountId: accountId), captured.revision)
        XCTAssertNil(store.withCurrentRevision(accountId: accountId, revision: captured.revision) { true })
    }

    func testScopedNotificationsKeepTransientRevealAndAccountResetEvents() {
        let accountId = Int64.random(in: 1_000_000_000...Int64.max)
        var bottomBarUpdates = 0
        var contentUpdates = 0
        var accountInfoUpdates = 0
        let bottomBar = regramPreferenceChanges(accountId: accountId, keys: RegramBottomBarSettings.preferenceKeys).start(next: { _ in bottomBarUpdates += 1 })
        let content = regramContentPreferenceChanges(accountId: accountId).start(next: { _ in contentUpdates += 1 })
        let accountInfo = regramPreferenceChanges(accountId: accountId, keys: ["hidePhoneInSettings"]).start(next: { _ in accountInfoUpdates += 1 })
        defer { bottomBar.dispose(); content.dispose(); accountInfo.dispose() }
        func notify(_ keys: Set<String>?, account: Int64? = nil) {
            NotificationCenter.default.post(name: RegramPreferences.didChange, object: account ?? accountId, userInfo: keys.map { [RegramPreferences.changedKeysUserInfoKey: $0] })
        }
        for _ in 0..<100 { notify(["bottomBarLayout", "showTabNames", "tabBarWidthPercent"]) }
        XCTAssertEqual(bottomBarUpdates, 101)
        XCTAssertEqual(contentUpdates, 1)
        XCTAssertEqual(accountInfoUpdates, 1)
        notify(["showMessageId"])
        XCTAssertEqual(bottomBarUpdates, 101)
        XCTAssertEqual(contentUpdates, 2)
        XCTAssertEqual(accountInfoUpdates, 1)
        notify(["hidePhoneInSettings"])
        XCTAssertEqual(accountInfoUpdates, 2)
        notify(["bottomBarLayout", "messageFilterRules"])
        XCTAssertEqual(bottomBarUpdates, 102)
        XCTAssertEqual(contentUpdates, 4)
        notify(nil)
        XCTAssertEqual(bottomBarUpdates, 103)
        XCTAssertEqual(contentUpdates, 5)
        XCTAssertEqual(accountInfoUpdates, 3)
        notify(["hidePhoneInSettings"], account: -1)
        XCTAssertEqual(accountInfoUpdates, 3)
    }
}
