import Cocoa
import TGUIKit
import InputDataUI
import GeneralRows
import TelegramCore
import Postbox
import ChatHistoryModel
import RegramCore
import RegramSignals
import SwiftSignalKit

let fixtureSuite = "RegramToggleCombinationChecks." + UUID().uuidString
let fixtureDefaults = UserDefaults(suiteName: fixtureSuite)!
let fixturePreferences = RegramPreferences(defaults: fixtureDefaults)
let fixtureInventory = RegramMessageMenuInventory(defaults: fixtureDefaults)
let fixtureMetadata = ToggleFixtureMetadata()
let fixtureGiftAccount = "RegramToggleCombinationChecks.synthetic"
let fixtureGiftStore = RGLocalGiftsStore(defaults: fixtureDefaults)
func fixtureAlert(info: String) { preconditionFailure("Unexpected fixture validation failure: " + info) }

struct ToggleFixtureMetadata {
    func refreshIfNeeded(engine: ToggleFixtureEngine) {}
    func currentInlineBotRules() -> [RegramMetadataInlineRule] { [] }
}
struct ToggleFixturePeers {
    func updatedChatListFilters() -> Signal<[ChatListFilter], NoError> { .single([]) }
}
struct ToggleFixtureEngine { let peers = ToggleFixturePeers() }
struct ToggleFixtureNavigation {
    func push(_ controller: ViewController) { preconditionFailure("Unexpected navigation") }
}
struct ToggleFixtureBindings {
    func rootNavigation() -> ToggleFixtureNavigation { ToggleFixtureNavigation() }
}
struct ToggleFixtureContext {
    let peerId: PeerId
    let engine = ToggleFixtureEngine()
    let bindings = ToggleFixtureBindings()
}
struct RegramUIHooks {
    static let shared = RegramUIHooks()
    func openNativeSettings(_ context: ToggleFixtureContext, _ page: String) { preconditionFailure("Unexpected native settings navigation") }
}
func RegramSettingsController(context: ToggleFixtureContext, page: String) -> InputDataController { preconditionFailure("Unexpected settings navigation") }
func RegramNavigationController(context: ToggleFixtureContext) -> InputDataController { preconditionFailure("Unexpected tab customization") }
func RegramChatPreferencesController(context: ToggleFixtureContext) -> InputDataController { preconditionFailure("Unexpected chat preferences") }
func regramFocusSettings(_ controller: InputDataController, page: String?, item: String?) {}
func regramString(_ key: String) -> String { key }

@main
struct ToggleCombinationChecks {
    struct Action {
        let name: String
        let row: TableRowView
        let control: NSSwitch
        let transform: (inout RegramAccountSettings) -> Void
        func activate() {
            guard let action = control.action else { preconditionFailure("Missing native action") }
            _ = NSApplication.shared.sendAction(action, to: control.target, from: control)
        }
    }
    struct GiftAction {
        let name: String
        let row: TableRowView
        let control: NSSwitch
        let transform: (inout RGLocalGiftsState) -> Void
        func activate() {
            guard let action = control.action else { preconditionFailure("Missing native gift action") }
            _ = NSApplication.shared.sendAction(action, to: control.target, from: control)
        }
    }
    static var checks = 0
    static var failures: [String] = []
    static func check(_ value: Bool, _ name: String) {
        checks += 1
        if !value { failures.append(name) }
    }
    static func views(_ view: NSView) -> [NSView] { view.subviews.flatMap { [$0] + views($0) } }
    static func drain() {
        _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.03))
    }
    static func main() throws {
        UITestBootstrap.install()
        NSApp.setActivationPolicy(.prohibited)
        defer { fixtureDefaults.removePersistentDomain(forName: fixtureSuite) }
        let accountId: Int64 = 283392
        let context = ToggleFixtureContext(peerId: PeerId(accountId))
        fixtureInventory.record(Set(RGContextMenuItemId.allCases), accountId: accountId)
        fixturePreferences.update(accountId: accountId) { $0["showMessageId"] = .bool(true) }
        _ = fixtureGiftStore.setEnabled(account: fixtureGiftAccount, enabled: true)
        _ = fixtureGiftStore.setPhone(account: fixtureGiftAccount, enabled: false, number: "88800011111")
        _ = fixtureGiftStore.setRating(account: fixtureGiftAccount, enabled: false, level: 7)
        let controllers = [
            RegramLinkPreviewSettingsController(context: context),
            RegramInlineRulesController(context: context),
            RegramContextMenuController(context: context),
            RegramStoriesSettingsController(context: context),
            RegramAppearanceCategoryController(context: context),
            regramComposedSettingsController(context: context, category: .privacy, focus: nil),
            regramComposedSettingsController(context: context, category: .network, focus: nil),
            RegramShowroomController(context: context)
        ] + ["messageActions", "chatList", "folders"].map { RegramMessagesSettingsController(context: context, initialTab: $0) }
          + ["media", "photos", "stickers", "recording"].map { RegramMediaSettingsController(context: context, initialTab: $0) }
          + [RegramInputSettingsController(context: context)]
        var hosts: [Window] = []
        var navigations: [NavigationViewController] = []
        var actions: [Action] = []
        var giftActions: [GiftAction] = []
        defer { for host in hosts { host.contentView = nil; host.close() } }
        for controller in controllers {
            let host = Window(contentRect: NSRect(x: 0, y: 0, width: 600, height: 1800), styleMask: .borderless, backing: .buffered, defer: false)
            host.isReleasedWhenClosed = false
            let navigation = NavigationViewController(controller, host)
            navigation.loadViewIfNeeded(host.contentLayoutRect)
            host.contentView = navigation.view
            hosts.append(host)
            navigations.append(navigation)
            let deadline = Date().addingTimeInterval(3)
            while controller.tableView.count < 2 && Date() < deadline { drain() }
            check(controller.tableView.count > 1, "Production controller loads settings")
            controller.tableView.enumerateItems { item in
                guard let native = item as? RegramNativeRowItem, case .switchable = native.data.type,
                      let id = (item.stableId.base as? InputDataEntryId)?.identifier?.identifier,
                      let row = native.viewNecessary,
                      let control = views(row).compactMap({ $0 as? NSSwitch }).first else { return true }
                if id.hasPrefix("localGifts.") && id != "localGifts.localPremium" {
                    giftActions.append(GiftAction(name: id, row: row, control: control, transform: { state in
                        switch id {
                        case "localGifts.phoneEnabled": state.phoneEnabled.toggle()
                        case "localGifts.ratingEnabled": state.ratingEnabled.toggle()
                        case "localGifts.enabled": state.enabled.toggle()
                        case "localGifts.walletCard": state.walletCardEnabled.toggle()
                        default: preconditionFailure("Unexpected showroom switch: " + id)
                        }
                    }))
                } else {
                    actions.append(Action(name: id, row: row, control: control, transform: transform(id)))
                }
                return true
            }
        }
        check(actions.count > 70, "Broad toggle coverage includes menu, appearance, input, media and network pages")
        let unrelatedAccount = fixturePreferences.settings(accountId: accountId + 1)
        for mask in 0..<4 {
            fixturePreferences.update(accountId: accountId) { settings in
                for (index, key) in ["panguSpacing", "disableLinkPreview", "features.autoInlineBotEnabled", "localPremium", "translationHideOriginal"].enumerated() { settings[key] = .bool((mask & (1 << (index % 2))) != 0) }
            }
            for action in actions {
                var expected = fixturePreferences.settings(accountId: accountId)
                for _ in 0..<4 {
                    action.transform(&expected)
                    action.activate()
                    check(fixturePreferences.settings(accountId: accountId) == expected, "\(mask)/\(action.name) repeated native action uses latest stored state")
                }
            }
            drain()
        }
        var replacement = fixturePreferences.settings(accountId: accountId)
        for setting in RegramSetting.all {
            if case .bool = setting.defaultValue { replacement[setting.key] = .bool(!replacement[setting.key].bool) }
        }
        let backup = try RegramSettingsBackup.decode(RegramSettingsBackup(settings: replacement).encoded())
        fixturePreferences.update(accountId: accountId) { $0 = backup.applying(to: $0) }
        for action in actions {
            var expected = fixturePreferences.settings(accountId: accountId)
            for _ in 0..<2 {
                action.transform(&expected)
                action.activate()
                check(fixturePreferences.settings(accountId: accountId) == expected, "\(action.name) immediate action after backup restore uses restored values")
            }
        }
        for category in RegramCategory.allCases {
            fixturePreferences.reset(accountId: accountId, category: category)
            for action in actions {
                var expected = fixturePreferences.settings(accountId: accountId)
                action.transform(&expected)
                action.activate()
                check(fixturePreferences.settings(accountId: accountId) == expected, "\(category)/\(action.name) immediate action after category reset preserves other settings")
            }
        }
        drain()
        var pairs = 0
        for first in actions.indices {
            for second in actions.indices where second > first {
                var expected = fixturePreferences.settings(accountId: accountId)
                for index in [first, second, first, second] {
                    actions[index].transform(&expected)
                    actions[index].activate()
                    check(fixturePreferences.settings(accountId: accountId) == expected, "\(actions[first].name)/\(actions[second].name) interleaved toggles preserve other settings")
                }
                pairs += 1
            }
            drain()
        }
        check(fixturePreferences.settings(accountId: accountId + 1) == unrelatedAccount, "All toggle combinations preserve another account")
        check(giftActions.count == 4, "Showroom covers phone, rating, local gifts and wallet-card switches")
        for first in giftActions.indices {
            for second in giftActions.indices {
                var expected = fixtureGiftStore.state(account: fixtureGiftAccount)
                for index in [first, second, first, second] {
                    giftActions[index].transform(&expected)
                    giftActions[index].activate()
                    check(fixtureGiftStore.state(account: fixtureGiftAccount) == expected, "\(giftActions[first].name)/\(giftActions[second].name) preserves current showroom state, phone, rating and balances")
                }
            }
        }
        check(fixtureGiftStore.state(account: fixtureGiftAccount + ".other") == RGLocalGiftsState(), "Showroom toggles preserve another isolated account")
        check(hosts.allSatisfy { !$0.isVisible && !$0.isKeyWindow && !$0.isMainWindow }, "All native action fixtures remain hidden and inactive")
        check(NSApp.activationPolicy() == .prohibited, "Fixture cannot activate the user's application")
        let report: [String: Any] = ["checks": checks, "toggleBindings": actions.count, "togglePairs": pairs, "showroomBindings": giftActions.count, "failures": failures, "failedBindings": Array(Set(failures)).sorted(), "messagesSent": 0, "realAccountsUsed": false]
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("report.json"))
        print("Native toggle checks: \(checks), bindings: \(actions.count), pairs: \(pairs), failures: \(failures.count)")
        for failure in failures.prefix(20) { print("FAIL " + failure) }
        withExtendedLifetime(navigations) {}
        if !failures.isEmpty { exit(1) }
    }
    static func transform(_ id: String) -> (inout RegramAccountSettings) -> Void {
        if id.hasPrefix("regram_menu_"), let item = RGContextMenuItemId(rawValue: String(id.dropFirst("regram_menu_".count))) {
            return { settings in
                if let key = RegramContextMenuConfiguration.settingKey(item) { settings[key] = .bool(!settings[key].bool) }
                else {
                    var disabled = Set(settings["contextMenuDisabledItems"].strings)
                    if disabled.contains(item.rawValue) { disabled.remove(item.rawValue) } else { disabled.insert(item.rawValue) }
                    settings["contextMenuDisabledItems"] = .strings(disabled.sorted())
                }
            }
        }
        let key: String
        if id.hasPrefix("parity_") { key = String(id.dropFirst("parity_".count)) }
        else if id == "linkPreview.enabled" { key = "fixLinkPreviews" }
        else if id == "inlineBots.enabled" { key = "features.autoInlineBotEnabled" }
        else if id == "appearance.hideTabBarPermissionWarnings" { key = "features.hideTabBarPermissionWarnings" }
        else if id == "stories.showRepostToStory" { key = "showRepostToStoryV2" }
        else if ["stories.hideTopStories", "stories.disableChatAvatarStories"].contains(id) { key = "features." + id.split(separator: ".").last! }
        else { key = String(id.split(separator: ".").last!) }
        precondition(RegramSetting.byKey[key] != nil, "Missing setting mapping " + id + " -> " + key)
        return { settings in
            if key == "downloadSpeedBoost" { settings[key] = .string(settings[key].string == "none" ? "medium" : "none") }
            else { settings[key] = .bool(!settings[key].bool) }
        }
    }
}
