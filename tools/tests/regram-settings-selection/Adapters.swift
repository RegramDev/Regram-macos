import Foundation

public class ViewController {
    var navigation: ViewController?
    func navigationWillChangeController() {}
}

public enum ChatMode {
    case history, scheduled, thread, customChatContents, customLink
}

public struct ChatLocation {
    public let peerId: Int64
}

struct FixtureContext {
    let peerId: Int64
}

enum AccountInfoEntryId: Hashable {
    case index(Int)
}

class InputDataController: ViewController {
    let identifier: String
    init(_ identifier: String) { self.identifier = identifier }
}

final class MajorNavigationController: ViewController {
    var stack: [ViewController]
    var controller: ViewController { stack.last! }
    init(_ stack: [ViewController]) { self.stack = stack }
    func enumerateControllers(_ callback: (ViewController, Int) -> Bool) {
        for index in stack.indices.reversed() {
            if callback(stack[index], index) { break }
        }
    }
}

enum SettingsSection {
    case dataAndStorage, stickers, sessions, passport, premium
}

protocol SettingsSectionController {
    var settingsSection: SettingsSection { get }
}

protocol SettingsPeerInfoController {
    var peerId: Int64 { get }
}

final class PrivacyAndSecurityViewController<Context>: ViewController {}
final class GeneralSettingsViewController<Context>: ViewController {}

final class FixtureRow {
    let id: AnyHashable
    init(_ id: AccountInfoEntryId) { self.id = AnyHashable(id) }
}

final class FixtureTable {
    var rows = Dictionary(uniqueKeysWithValues: [-102, -101, -100, 0, 6, 7, 8, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20].map { (AnyHashable(AccountInfoEntryId.index($0)), FixtureRow(.index($0))) })
    var selected: AnyHashable? = AnyHashable(AccountInfoEntryId.index(-100))
    func item(stableId: AnyHashable) -> FixtureRow? { rows[stableId] }
    func select(item: FixtureRow) -> Bool {
        let changed = selected != item.id
        selected = item.id
        return changed
    }
    func cancelSelection() { selected = nil }
}
