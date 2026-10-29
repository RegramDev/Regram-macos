import Foundation
import XCTest
import RegramCore

struct PeerId: Hashable {
    let value: Int64
    func toInt64() -> Int64 { value }
}

struct MessageId: Hashable {
    let peerId: PeerId
    let id: Int32
}

protocol Peer {}

final class TelegramUser: Peer {
    let botInfo: Bool?
    init(bot: Bool) { botInfo = bot ? true : nil }
}

final class Channel: Peer {}

struct Message { let author: Peer? }

final class Transaction {
    var messages: [MessageId: Message] = [:]
    var reads = 0
    func getMessage(_ id: MessageId) -> Message? {
        reads += 1
        return messages[id]
    }
}

var fixturePreferences: RegramPreferences!

__RETENTION_BRIDGE__

final class RevokedBotsTests: XCTestCase {
    private var suite: String!
    private var defaults: UserDefaults!
    private let peer = PeerId(value: 20)

    override func setUp() {
        suite = "RegramRevokedBotsTests." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
        fixturePreferences = RegramPreferences(defaults: defaults)
    }

    override func tearDown() {
        fixturePreferences = nil
        defaults.removePersistentDomain(forName: suite)
    }

    private func configure(global: Bool = true, skipBots: Bool = false, peers: [String] = []) {
        fixturePreferences.update(accountId: 1) {
            $0["antiRevoke"] = .bool(global)
            $0["antiRevokeSkipBots"] = .bool(skipBots)
            $0["antiRevokePeerIds"] = .strings(peers)
        }
    }

    private func row(_ key: String, in entries: [InputDataEntry]? = nil) throws -> (section: Int32, data: InputDataGeneralData) {
        for case let .general(section, _, _, _, identifier, data) in entries ?? privacyRows().entries {
            if identifier.value == "antiFeatures." + key { return (section, data) }
        }
        throw NSError(domain: "MissingPrivacyRow", code: 1)
    }

    func testBotExclusionIsDisabledWhenRetentionIsOff() throws {
        configure(global: false)
        let child = try row("antiRevokeSkipBots").data
        XCTAssertFalse(child.enabled)
        XCTAssertEqual(child.color, theme.colors.grayText)
        child.action?()
        XCTAssertFalse(fixturePreferences.settings(accountId: 1)["antiRevokeSkipBots"].bool)
    }

    func testEnablingRetentionUnlocksBotExclusionAndExcludesOnlyBots() throws {
        configure(global: false)
        try row("antiRevoke").data.action?()
        let child = try row("antiRevokeSkipBots").data
        XCTAssertTrue(child.enabled)
        XCTAssertEqual(child.color, theme.colors.text)
        child.action?()
        XCTAssertEqual(try row("antiRevokeSkipBots").data.type, .switchable(true))
        let transaction = Transaction()
        let bot = MessageId(peerId: peer, id: 1)
        let human = MessageId(peerId: peer, id: 2)
        transaction.messages[bot] = Message(author: TelegramUser(bot: true))
        transaction.messages[human] = Message(author: TelegramUser(bot: false))
        XCTAssertFalse(rgShouldRetainRevokedMessage(accountId: 1, transaction: transaction, id: bot))
        XCTAssertTrue(rgShouldRetainRevokedMessage(accountId: 1, transaction: transaction, id: human))
    }

    func testStaleChildActionCannotToggleAfterRetentionTurnsOff() throws {
        configure()
        let child = try row("antiRevokeSkipBots").data
        try row("antiRevoke").data.action?()
        child.action?()
        XCTAssertFalse(fixturePreferences.settings(accountId: 1)["antiRevokeSkipBots"].bool)
    }

    func testDisablingRetentionKeepsChildPreferenceForReenable() throws {
        configure(skipBots: true)
        try row("antiRevoke").data.action?()
        let child = try row("antiRevokeSkipBots").data
        XCTAssertFalse(child.enabled)
        XCTAssertEqual(child.type, .switchable(true))
        child.action?()
        try row("antiRevoke").data.action?()
        XCTAssertTrue(try row("antiRevokeSkipBots").data.enabled)
        XCTAssertTrue(fixturePreferences.settings(accountId: 1)["antiRevokeSkipBots"].bool)
    }

    func testRetentionAndBotExclusionHaveTheirOwnGroup() throws {
        let parent = try row("antiRevoke")
        let child = try row("antiRevokeSkipBots")
        let history = try row("saveEditHistory")
        XCTAssertEqual(parent.section, child.section)
        XCTAssertNotEqual(child.section, history.section)
        XCTAssertEqual(parent.data.viewType, .firstItem)
        XCTAssertEqual(child.data.viewType, .lastItem)
        XCTAssertEqual(history.data.viewType, .firstItem)
        XCTAssertEqual(try row("revokedMarker").data.viewType, .lastItem)
        XCTAssertTrue(privacyRows().entries.contains { if case .sectionId(parent.section, _) = $0 { return true }; return false })
    }

    func testGhostModeKeepsItsSingleIndependentGroup() {
        let rows = privacyRows(ghostMode: true).entries.compactMap { entry -> (Int32, InputDataGeneralData)? in
            guard case let .general(section, _, _, _, _, data) = entry else { return nil }
            return (section, data)
        }
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(Set(rows.map { $0.0 }), [1])
        XCTAssertTrue(rows.allSatisfy { $0.1.enabled })
        XCTAssertEqual(rows.first?.1.viewType, .firstItem)
        XCTAssertEqual(rows.last?.1.viewType, .lastItem)
    }

    func testDefaultKeepsExistingBotRetentionWithoutMessageRead() {
        XCTAssertEqual(RegramAccountSettings()["antiRevokeSkipBots"], .bool(false))
        configure()
        let transaction = Transaction()
        let id = MessageId(peerId: peer, id: 1)
        transaction.messages[id] = Message(author: TelegramUser(bot: true))
        XCTAssertTrue(rgShouldRetainRevokedMessage(accountId: 1, transaction: transaction, id: id))
        XCTAssertEqual(transaction.reads, 0)
    }

    func testSkipBotsUsesMessageAuthorInsideMixedGroup() {
        configure(skipBots: true)
        let transaction = Transaction()
        let bot = MessageId(peerId: peer, id: 1)
        let human = MessageId(peerId: peer, id: 2)
        transaction.messages[bot] = Message(author: TelegramUser(bot: true))
        transaction.messages[human] = Message(author: TelegramUser(bot: false))
        XCTAssertFalse(rgShouldRetainRevokedMessage(accountId: 1, transaction: transaction, id: bot))
        XCTAssertTrue(rgShouldRetainRevokedMessage(accountId: 1, transaction: transaction, id: human))
    }

    func testPerChatRetentionHonorsBotExclusion() {
        configure(global: false, skipBots: true, peers: ["20"])
        let transaction = Transaction()
        let id = MessageId(peerId: peer, id: 1)
        transaction.messages[id] = Message(author: TelegramUser(bot: true))
        XCTAssertFalse(rgShouldRetainRevokedMessage(accountId: 1, transaction: transaction, id: id))
        transaction.messages[id] = Message(author: TelegramUser(bot: false))
        XCTAssertTrue(rgShouldRetainRevokedMessage(accountId: 1, transaction: transaction, id: id))
        XCTAssertFalse(rgShouldRetainRevokedMessage(accountId: 1, transaction: transaction, id: MessageId(peerId: PeerId(value: 21), id: 1)))
    }

    func testDisabledRetentionDoesNotReadMessageOrEnableRetention() {
        configure(global: false, skipBots: true)
        let transaction = Transaction()
        XCTAssertFalse(rgShouldRetainRevokedMessage(accountId: 1, transaction: transaction, id: MessageId(peerId: peer, id: 1)))
        XCTAssertEqual(transaction.reads, 0)
    }

    func testHumanMessagesToBotChatAreKept() {
        configure(skipBots: true)
        let transaction = Transaction()
        let id = MessageId(peerId: PeerId(value: 100), id: 1)
        transaction.messages[id] = Message(author: TelegramUser(bot: false))
        XCTAssertTrue(rgShouldRetainRevokedMessage(accountId: 1, transaction: transaction, id: id))
    }

    func testUnknownAndChannelAuthorsKeepExistingBehavior() {
        configure(skipBots: true)
        let transaction = Transaction()
        let id = MessageId(peerId: peer, id: 1)
        XCTAssertTrue(rgShouldRetainRevokedMessage(accountId: 1, transaction: transaction, id: id))
        transaction.messages[id] = Message(author: nil)
        XCTAssertTrue(rgShouldRetainRevokedMessage(accountId: 1, transaction: transaction, id: id))
        transaction.messages[id] = Message(author: Channel())
        XCTAssertTrue(rgShouldRetainRevokedMessage(accountId: 1, transaction: transaction, id: id))
    }

    func testSwitchCanBeTurnedOffAgain() {
        configure(skipBots: true)
        let transaction = Transaction()
        let id = MessageId(peerId: peer, id: 1)
        transaction.messages[id] = Message(author: TelegramUser(bot: true))
        XCTAssertFalse(rgShouldRetainRevokedMessage(accountId: 1, transaction: transaction, id: id))
        fixturePreferences.update(accountId: 1) { $0["antiRevokeSkipBots"] = .bool(false) }
        XCTAssertTrue(rgShouldRetainRevokedMessage(accountId: 1, transaction: transaction, id: id))
    }

    func testPreferencePersistsAndAccountsStayIndependent() {
        configure(skipBots: true)
        let reloaded = RegramPreferences(defaults: defaults)
        XCTAssertTrue(reloaded.settings(accountId: 1)["antiRevokeSkipBots"].bool)
        XCTAssertFalse(reloaded.settings(accountId: 2)["antiRevokeSkipBots"].bool)
    }

    func testPrivacyBackupRoundTripAndOldBackupDefault() throws {
        configure(skipBots: true)
        let backup = RegramSettingsBackup(settings: fixturePreferences.settings(accountId: 1), categories: [.privacy])
        let restored = try RegramSettingsBackup.decode(backup.encoded()).applying(to: RegramAccountSettings())
        XCTAssertTrue(restored["antiRevokeSkipBots"].bool)
        let old = RegramSettingsBackup(values: ["antiRevoke": .bool(true)]).applying(to: RegramAccountSettings())
        XCTAssertFalse(old["antiRevokeSkipBots"].bool)
    }

    func testSettingIsSearchableAndLocalized() throws {
        XCTAssertTrue(RegramSetting.availableKeys.contains("antiRevokeSkipBots"))
        let route = try XCTUnwrap(RegramSettingsRoute(page: "antiFeatures", item: "antiRevokeSkipBots"))
        XCTAssertEqual(route.destination, "antiFeatures/antiRevokeSkipBots")
        for language in ["en", "zh-Hans", "zh-Hant"] {
            let label = regramLocalizedString("AntiFeatures.SkipBots", languageCode: language)
            XCTAssertFalse(label.isEmpty)
            XCTAssertNotEqual(label, "AntiFeatures.SkipBots")
        }
        XCTAssertTrue(RegramSettingsCatalog.results(query: "机器人", language: "zh-Hans").contains { $0.key == "antiRevokeSkipBots" })
    }
}
