import XCTest
@testable import RegramCore
import RegramSignals

final class RegramLocalGiftsTests: XCTestCase {
    private func withStore(_ body: (RGLocalGiftsStore, UserDefaults) throws -> Void) throws {
        let suite = "RegramLocalGiftsTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(RGLocalGiftsStore(defaults: defaults, notifications: NotificationCenter()), defaults)
    }

    private func failure(_ result: Result<RGLocalGiftsState, RGLocalGiftsError>, _ expected: RGLocalGiftsError, file: StaticString = #filePath, line: UInt = #line) {
        guard case let .failure(error) = result else { XCTFail("Expected failure", file: file, line: line); return }
        XCTAssertEqual(String(describing: error), String(describing: expected), file: file, line: line)
    }

    func testDisabledAndInsufficientPurchasesPreserveBalancesAndRecords() throws {
        try withStore { store, _ in
            let data = Data("gift".utf8)
            let before = store.state(account: "live:1")
            failure(store.purchase(account: "live:1", title: "gift", price: 100, gift: data), .disabled)
            XCTAssertEqual(store.state(account: "live:1"), before)
            _ = try store.setEnabled(account: "live:1", enabled: true).get()
            _ = try store.setBalance(account: "live:1", balance: 100).get()
            _ = try store.setBalance(account: "live:1", balance: 9, currency: .ton).get()
            let enabled = store.state(account: "live:1")
            failure(store.purchase(account: "live:1", title: "gift", price: 101, gift: data), .insufficientStars)
            failure(store.purchase(account: "live:1", title: "gift", price: 10, gift: data, currency: .ton), .insufficientTon)
            XCTAssertEqual(store.state(account: "live:1"), enabled)
            let purchased = try store.purchase(account: "live:1", title: "gift", price: 100, gift: data).get()
            XCTAssertEqual(purchased.balance, 0)
            XCTAssertEqual(purchased.tonBalance, 9)
            XCTAssertEqual(purchased.purchases.count, 1)
        }
    }

    func testConcurrentConfirmationCannotOverdrawOrLosePurchase() throws {
        try withStore { store, _ in
            _ = try store.setEnabled(account: "live:1", enabled: true).get()
            _ = try store.setBalance(account: "live:1", balance: 25).get()
            DispatchQueue.concurrentPerform(iterations: 100) { _ in
                _ = store.purchase(account: "live:1", title: "gift", price: 1, gift: Data([1]))
            }
            let result = store.state(account: "live:1")
            XCTAssertEqual(result.balance, 0)
            XCTAssertEqual(result.purchases.count, 25)
            XCTAssertEqual(Set(result.purchases.map(\.id)).count, 25)
        }
    }

    func testUpgradeUsesExpectedPayloadAndRechecksEnabledAtCommit() throws {
        try withStore { store, defaults in
            _ = try store.setEnabled(account: "live:1", enabled: true).get()
            _ = try store.setBalance(account: "live:1", balance: 100).get()
            let original = try store.purchase(account: "live:1", title: "gift", price: 20, gift: Data([1])).get().purchases[0]
            _ = try store.setVisibility(account: "live:1", id: original.id, saved: false).get()
            _ = try RGLocalGiftsStore(defaults: defaults).setEnabled(account: "live:1", enabled: false).get()
            let disabled = store.state(account: "live:1")
            failure(store.upgrade(account: "live:1", id: original.id, expectedGift: original.gift, title: "unique", gift: Data([2]), stars: 10), .disabled)
            XCTAssertEqual(store.state(account: "live:1"), disabled)
            _ = try store.setEnabled(account: "live:1", enabled: true).get()
            let upgraded = try store.upgrade(account: "live:1", id: original.id, expectedGift: original.gift, title: "unique", gift: Data([2]), stars: 10).get()
            failure(store.upgrade(account: "live:1", id: original.id, expectedGift: original.gift, title: "duplicate", gift: Data([3]), stars: 10), .storage)
            XCTAssertEqual(store.state(account: "live:1"), upgraded)
            XCTAssertEqual(upgraded.balance, 70)
            XCTAssertEqual(upgraded.purchases[0].id, original.id)
            XCTAssertEqual(upgraded.purchases[0].date, original.date)
            XCTAssertEqual(upgraded.purchases[0].price, 30)
            XCTAssertFalse(upgraded.purchases[0].savedToProfile)
            XCTAssertEqual(RGLocalGiftsStore(defaults: defaults).state(account: "live:1"), upgraded)
        }
    }

    func testEnvironmentIsolationAndLogoutOnlyRemoveSelectedAccount() throws {
        try withStore { store, defaults in
            for account in ["live:1", "test:1", "live:2"] {
                _ = try store.setEnabled(account: account, enabled: true).get()
                _ = try store.purchase(account: account, title: account, price: 1, gift: Data([1])).get()
            }
            let test = store.state(account: "test:1")
            let other = store.state(account: "live:2")
            store.removeAccount(account: "live:1")
            XCTAssertEqual(store.state(account: "live:1"), RGLocalGiftsState())
            XCTAssertNil(defaults.data(forKey: "regram.localGifts.v1.live:1"))
            XCTAssertEqual(store.state(account: "test:1"), test)
            XCTAssertEqual(store.state(account: "live:2"), other)
            XCTAssertEqual(RGLocalGiftsStore(defaults: defaults).state(account: "test:1"), test)
        }
    }

    func testMigrationCorruptionAndIndependentPhoneRatingSettings() throws {
        try withStore { store, defaults in
            let data = Data("{\"enabled\":false,\"balance\":8,\"purchases\":[]}".utf8)
            defaults.set(data, forKey: "regram.localGifts.v1.live:1")
            let migrated = store.state(account: "live:1")
            XCTAssertEqual(migrated.tonBalance, 1_000_000_000_000)
            XCTAssertFalse(migrated.walletCardEnabled)
            _ = try store.setPhone(account: "live:1", enabled: true, number: "+888 1234 5678").get()
            let phone = try store.setRating(account: "live:1", enabled: true, level: -999).get()
            XCTAssertEqual(phone.phoneNumber, "88812345678")
            XCTAssertFalse(phone.enabled)
            XCTAssertTrue(phone.ratingEnabled)
            failure(store.setRating(account: "live:1", enabled: true, level: 1000), .invalidAmount)
            XCTAssertEqual(store.state(account: "live:1"), phone)
            let corrupt = Data("invalid".utf8)
            defaults.set(corrupt, forKey: "regram.localGifts.v1.test:1")
            failure(store.setEnabled(account: "test:1", enabled: true), .storage)
            XCTAssertEqual(defaults.data(forKey: "regram.localGifts.v1.test:1"), corrupt)
        }
    }

    func testCurrencyValidationAndPinnedRemovalClearsOnlyOwnedBindings() throws {
        XCTAssertEqual(RGLocalGiftCurrency.ton.amount(from: "1.000000001"), 1_000_000_001)
        XCTAssertEqual(RGLocalGiftCurrency.ton.amount(from: "0,5"), 500_000_000)
        for text in ["-1", "1.0000000001", "9000000.000000001", "NaN", "١٢", "1e3"] { XCTAssertNil(RGLocalGiftCurrency.ton.amount(from: text)) }
        try withStore { store, _ in
            _ = try store.setEnabled(account: "live:1", enabled: true).get()
            let gift = try store.purchase(account: "live:1", title: "gift", price: 1, gift: Data([1])).get().purchases[0]
            _ = try store.setVisibility(account: "live:1", id: gift.id, saved: false).get()
            let pinned = try store.setPinned(account: "live:1", id: gift.id, pinned: true, maximumCount: 1).get()
            XCTAssertTrue(pinned.purchases[0].savedToProfile)
            let appearance = try JSONSerialization.data(withJSONObject: ["emojiStatus": ["id": -1], "profileColor": 7, "replyFileId": -2, "backgroundFileId": -3])
            _ = try store.setAppearance(account: "live:1", profileGiftId: gift.id, nameGiftId: nil, appearance: appearance).get()
            let result = try store.remove(account: "live:1", id: gift.id, mediaIds: [-2]).get()
            let remaining = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(result.appearance)) as? [String: Any])
            XCTAssertNil(remaining["emojiStatus"])
            XCTAssertNil(remaining["replyFileId"])
            XCTAssertEqual(remaining["profileColor"] as? Int, 7)
            XCTAssertEqual(remaining["backgroundFileId"] as? Int, -3)
            XCTAssertEqual(result.balance, 9999)
        }
    }

    func testQueuedModeChangesRetainTheEnabledTransitionBeforeDisabledCommit() throws {
        let suite = "RegramLocalGiftsTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let notifications = NotificationCenter()
        let store = RGLocalGiftsStore(defaults: defaults, notifications: notifications)
        let delivered = expectation(description: "Committed transitions delivered")
        var changes: [Bool] = []
        let subscription = regramLocalGiftsChanges(account: "live:1", store: store, notifications: notifications).start(next: { state in
            changes.append(state.enabled)
            if changes.count == 3 { delivered.fulfill() }
        })
        defer { subscription.dispose() }
        _ = try store.setEnabled(account: "live:1", enabled: true).get()
        _ = try store.setEnabled(account: "live:1", enabled: false).get()
        wait(for: [delivered], timeout: 2)
        XCTAssertEqual(changes, [false, true, false])
        XCTAssertFalse(store.state(account: "live:1").enabled)
    }

    func testStarsBalanceChangesKeepCommittedAmountsAndAccountEnvironmentScope() throws {
        let suite = "RegramLocalGiftsTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let notifications = NotificationCenter()
        let store = RGLocalGiftsStore(defaults: defaults, notifications: notifications)
        let account = RGLocalGiftsStore.accountKey(accountId: 1, testingEnvironment: false)
        let delivered = expectation(description: "Stars balance commits delivered")
        var amounts: [Int64?] = []
        let subscription = regramLocalGiftsChanges(account: account, store: store, notifications: notifications).start(next: { state in
            amounts.append(state.enabled ? state.balance : nil)
            if amounts.count == 5 { delivered.fulfill() }
        })
        defer { subscription.dispose() }
        _ = try store.setEnabled(account: account, enabled: true).get()
        _ = try store.setBalance(account: account, balance: 0).get()
        _ = try store.setBalance(account: account, balance: RGLocalGiftsStore.maximumBalance).get()
        failure(store.setBalance(account: account, balance: RGLocalGiftsStore.maximumBalance + 1), .invalidAmount)
        failure(store.setBalance(account: account, balance: -1), .invalidAmount)
        for other in [RGLocalGiftsStore.accountKey(accountId: 1, testingEnvironment: true), RGLocalGiftsStore.accountKey(accountId: 2, testingEnvironment: false)] {
            _ = try store.setEnabled(account: other, enabled: true).get()
            _ = try store.setBalance(account: other, balance: 42).get()
        }
        _ = try store.setEnabled(account: account, enabled: false).get()
        wait(for: [delivered], timeout: 2)
        XCTAssertEqual(amounts, [nil, 10_000, 0, RGLocalGiftsStore.maximumBalance, nil])
        XCTAssertEqual(store.state(account: account).balance, RGLocalGiftsStore.maximumBalance)
        XCTAssertFalse(store.state(account: account).enabled)
    }

    func testNativeDetailActionsRejectDisabledUpgradedAndDeletedSnapshots() throws {
        try withStore { store, _ in
            let account = "live:1"
            _ = try store.setEnabled(account: account, enabled: true).get()
            _ = try store.setBalance(account: account, balance: 100).get()
            let purchase = try store.purchase(account: account, title: "gift", price: 20, gift: Data([1])).get().purchases[0]
            _ = try store.setPinned(account: account, id: purchase.id, pinned: true, expectedGift: purchase.gift).get()
            _ = try store.setAppearance(account: account, profileGiftId: purchase.id, nameGiftId: purchase.id, appearance: Data("{}".utf8), expectedGift: purchase.gift, expectedGiftId: purchase.id).get()
            let disabled = try store.setEnabled(account: account, enabled: false).get()
            failure(store.setVisibility(account: account, id: purchase.id, saved: false, expectedGift: purchase.gift), .disabled)
            failure(store.setPinned(account: account, id: purchase.id, pinned: false, expectedGift: purchase.gift), .disabled)
            failure(store.setAppearance(account: account, profileGiftId: nil, nameGiftId: nil, appearance: nil, expectedGift: purchase.gift, expectedGiftId: purchase.id), .disabled)
            failure(store.remove(account: account, id: purchase.id, expectedGift: purchase.gift), .disabled)
            XCTAssertEqual(store.state(account: account), disabled)
            _ = try store.setEnabled(account: account, enabled: true).get()
            let upgraded = try store.upgrade(account: account, id: purchase.id, expectedGift: purchase.gift, title: "unique", gift: Data([2]), stars: 10).get()
            failure(store.setVisibility(account: account, id: purchase.id, saved: false, expectedGift: purchase.gift), .storage)
            failure(store.setPinned(account: account, id: purchase.id, pinned: false, expectedGift: purchase.gift), .storage)
            failure(store.setAppearance(account: account, profileGiftId: nil, nameGiftId: nil, appearance: nil, expectedGift: purchase.gift, expectedGiftId: purchase.id), .storage)
            failure(store.remove(account: account, id: purchase.id, expectedGift: purchase.gift), .storage)
            XCTAssertEqual(store.state(account: account), upgraded)
            let removed = try store.remove(account: account, id: purchase.id, expectedGift: Data([2])).get()
            XCTAssertEqual(removed.balance, 70)
            XCTAssertTrue(removed.purchases.isEmpty)
            XCTAssertNil(removed.profileGiftId)
            XCTAssertNil(removed.nameGiftId)
            failure(store.setVisibility(account: account, id: purchase.id, saved: true, expectedGift: Data([2])), .storage)
            failure(store.setPinned(account: account, id: purchase.id, pinned: true, expectedGift: Data([2])), .storage)
            failure(store.setAppearance(account: account, profileGiftId: purchase.id, nameGiftId: nil, appearance: nil, expectedGift: Data([2]), expectedGiftId: purchase.id), .storage)
            failure(store.remove(account: account, id: purchase.id, expectedGift: Data([2])), .storage)
            XCTAssertEqual(store.state(account: account), removed)
        }
    }

    func testAssetsRejectTraversalAndSymlinksAndKeepOtherEnvironment() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let live = try XCTUnwrap(RGLocalGiftAssets.directory(account: "live:1", applicationSupport: root))
        let test = try XCTUnwrap(RGLocalGiftAssets.directory(account: "test:1", applicationSupport: root))
        try RGLocalGiftAssets.prepare(directory: live)
        try RGLocalGiftAssets.prepare(directory: test)
        let filename = UUID().uuidString + ".asset"
        let file = try XCTUnwrap(RGLocalGiftAssets.asset(directory: live, name: filename))
        try Data([1]).write(to: file)
        XCTAssertNil(RGLocalGiftAssets.asset(directory: live, name: "../outside"))
        XCTAssertNil(RGLocalGiftAssets.directory(account: "live:../outside", applicationSupport: root))
        let symlink = live.appendingPathComponent(UUID().uuidString + ".asset")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: test)
        XCTAssertNil(RGLocalGiftAssets.asset(directory: live, name: symlink.lastPathComponent))
        RGLocalGiftAssets.removeAccount(account: "live:1", applicationSupport: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: live.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: test.path))
    }
}
