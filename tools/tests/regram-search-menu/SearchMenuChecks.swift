import Foundation

struct FixturePeerId { let value: Int64; func toInt64() -> Int64 { value } }
final class FixtureContext { let peerId: FixturePeerId; init(_ id: Int64) { peerId = FixturePeerId(value: id) } }
struct FixtureFlag { let bool: Bool }
struct FixtureSettings { let enabled: Bool; subscript(_ key: String) -> FixtureFlag { precondition(key == "messageBookmarksEnabled"); return FixtureFlag(bool: enabled) } }
final class RegramPreferences {
    static let shared = RegramPreferences()
    var values: [Int64: Bool] = [:]
    func settings(accountId: Int64) -> FixtureSettings { FixtureSettings(enabled: values[accountId] ?? false) }
}
class ContextMenuItem {
    let title: String
    let handler: () -> Void
    init(_ title: String, handler: @escaping () -> Void, itemImage: String?) { self.title = title; self.handler = handler }
}
final class ContextSeparatorItem: ContextMenuItem { init() { super.init("separator", handler: {}, itemImage: nil) } }
final class ContextMenu { var items: [ContextMenuItem] = []; func addItem(_ item: ContextMenuItem) { items.append(item) } }
struct FixtureStrings { let composePopoverNewGroup = "group"; let composePopoverNewSecretChat = "secret"; let composePopoverNewChannel = "channel" }
func strings() -> FixtureStrings { FixtureStrings() }
enum MenuAnimation: String { case menu_create_group, menu_lock, menu_channel, menu_bookmark; var value: String { rawValue } }
struct FixtureLanguage { let languageCode = "zh-hans" }
struct FixtureCurrentLanguage { let primaryLanguage = FixtureLanguage() }
let appCurrentLanguage = FixtureCurrentLanguage()
func regramLocalizedString(_ key: String, languageCode: String) -> String { key }
struct FixtureController { let accountId: Int64; let route: String }
enum FeatureNavigationHooks {
    static var shared = FeatureNavigationHooksHolder()
    struct FeatureNavigationHooksHolder {
        var routes: [Int64] = []
        mutating func makeRegramController(_ context: FixtureContext, _ route: String) -> FixtureController? {
            routes.append(context.peerId.value)
            return FixtureController(accountId: context.peerId.value, route: route)
        }
    }
}
struct ChatListUIHooks {
    static let shared = ChatListUIHooks()
    func composeCreateGroup(_ context: FixtureContext?) { MenuOwner.compositions.append("group") }
    func composeCreateSecretChat(_ context: FixtureContext?) { MenuOwner.compositions.append("secret") }
    func composeCreateChannel(_ context: FixtureContext?) { MenuOwner.compositions.append("channel") }
}
final class MenuOwner {
    static var compositions: [String] = []
    let context: FixtureContext
    var pushed: [FixtureController] = []
    init(_ id: Int64) { context = FixtureContext(id) }
    func menu() -> ContextMenu {
        let menu = ContextMenu()
        let context = self.context
        let pushController: (FixtureController) -> Void = { self.pushed.append($0) }
        PRODUCTION_MENU_BODY
        return menu
    }
}

final class ScrollableSegmentItem: Equatable {
    let index: Int
    let title = "Same folder title"
    let uniqueId: Int64
    let selected = false
    let theme = 1
    let insets = 14
    let equatable = 7
    init(_ id: Int64, index: Int) { uniqueId = id; self.index = index }
    PRODUCTION_SEGMENT_EQUALITY
}
enum FixtureFilter: Equatable { case allChats, folder(String) }
final class FixtureHeaderItem {
    let tabs: [FixtureFilter]
    let action: ((FixtureFilter) -> Void)?
    let openSettings: (() -> Void)?
    init(_ tabs: [FixtureFilter], action: @escaping (FixtureFilter) -> Void, openSettings: @escaping () -> Void = {}) {
        self.tabs = tabs; self.action = action; self.openSettings = openSettings
    }
}
final class FixtureSegmentView {
    var items: [ScrollableSegmentItem] = []
    var didChangeSelectedItem: ((ScrollableSegmentItem) -> Void)?
    func updateItems(_ items: [ScrollableSegmentItem], animated: Bool) { self.items = items }
}
final class FixtureHeader {
    let segmentView = FixtureSegmentView()
    var segmentItems: [ScrollableSegmentItem] = []
    func bind(_ items: [ScrollableSegmentItem], item: FixtureHeaderItem, animated: Bool = false) {
        PRODUCTION_SEGMENT_CACHE
        PRODUCTION_SELECTION_CALLBACK
    }
}

@main
struct SearchMenuChecks {
    static var count = 0
    static var failures: [String] = []
    static func check(_ value: @autoclosure () -> Bool, _ label: String) {
        count += 1
        if !value() { failures.append(label); print("FAIL \(label)") }
    }
    static func menuChecks() {
        let a = MenuOwner(1), b = MenuOwner(2)
        RegramPreferences.shared.values = [1: true, 2: false]
        let enabled = a.menu()
        check(enabled.items.map(\.title) == ["group", "secret", "channel", "separator", "bookmarks"], "enabled account retains exact menu order and complete bookmark group")
        let disabled = b.menu()
        check(disabled.items.map(\.title) == ["group", "secret", "channel"], "disabled account omits both bookmark item and separator")
        for item in enabled.items.prefix(3) { item.handler() }
        check(MenuOwner.compositions == ["group", "secret", "channel"], "base creation actions retain behavior")
        let staleAction = enabled.items.last!.handler
        RegramPreferences.shared.values[1] = false
        RegramPreferences.shared.values[2] = true
        staleAction()
        check(a.pushed.isEmpty && FeatureNavigationHooks.shared.routes.isEmpty, "old bookmark action rechecks original account flag before navigation factory")
        check(a.menu().items.count == 3, "rebuilding disabled original account removes group")
        let other = b.menu()
        check(other.items.last?.title == "bookmarks", "separate enabled account exposes its own bookmark entry")
        other.items.last!.handler()
        check(b.pushed.map(\.accountId) == [2] && b.pushed.map(\.route) == ["bookmarks"], "enabled second account opens its own bookmark controller")
        RegramPreferences.shared.values[1] = true
        let beforeReenable = a.pushed.count
        staleAction()
        check(a.pushed.count == beforeReenable + 1 && a.pushed.last?.accountId == 1, "old action works after original account is reenabled")
        RegramPreferences.shared.values[1] = false
        let pushed = a.pushed.count
        staleAction()
        check(a.pushed.count == pushed, "second disabling also invalidates retained old action")
    }
    static func headerChecks() {
        var oldSelections: [FixtureFilter] = [], newSelections: [FixtureFilter] = []
        var settings = 0
        let oldItem = FixtureHeaderItem([.folder("old filter data")], action: { oldSelections.append($0) })
        let currentItem = FixtureHeaderItem([.folder("updated filter data")], action: { newSelections.append($0) }, openSettings: { settings += 1 })
        let header = FixtureHeader()
        let original = ScrollableSegmentItem(10, index: 0)
        header.bind([original], item: oldItem)
        let equal = ScrollableSegmentItem(10, index: 0)
        header.bind([equal], item: currentItem)
        check(header.segmentView.items[0] === original, "equal native model retains existing view identity")
        header.segmentView.didChangeSelectedItem?(header.segmentView.items[0])
        check(oldSelections.isEmpty && newSelections == [.folder("updated filter data")], "reused equal model resolves filter payload from latest header item")
        header.segmentView.didChangeSelectedItem?(ScrollableSegmentItem(-1, index: 0))
        header.segmentView.didChangeSelectedItem?(ScrollableSegmentItem(-2, index: 0))
        check(newSelections.last == .allChats && settings == 1, "special tab callbacks also use latest header item")
        let reorderedItem = FixtureHeaderItem([.folder("other"), .folder("reordered updated filter")], action: { newSelections.append($0) })
        let moved = ScrollableSegmentItem(10, index: 1)
        header.bind([ScrollableSegmentItem(20, index: 0), moved], item: reorderedItem)
        check(header.segmentView.items[1] === moved && header.segmentView.items[1] !== original, "native equality prevents reuse of outdated index after reorder")
        header.segmentView.didChangeSelectedItem?(header.segmentView.items[1])
        check(newSelections.last == .folder("reordered updated filter"), "reordered callback resolves current index and current filter")
        withExtendedLifetime((oldItem, currentItem, reorderedItem)) {}
    }
    static func main() throws {
        menuChecks(); headerChecks()
        let report: [String: Any] = ["checks": count, "failures": failures, "productionMenuBody": true, "productionHeaderCallbackAndCache": true, "userInterfaceOrAccountAccess": false]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("report.json"))
        print("search menu checks=\(count), failures=\(failures.count)")
        if !failures.isEmpty { exit(1) }
    }
}
