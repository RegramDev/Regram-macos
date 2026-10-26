import Cocoa
import TGUIKit
import RegramCore

extension ContextMenuItem {
    func regramAction(_ id: RGContextMenuItemId) -> ContextMenuItem {
        identifier = NSUserInterfaceItemIdentifier("regram.message." + id.rawValue)
        return self
    }
}

func regramOrderedMessageMenu(_ items: [ContextMenuItem], accountId: Int64) -> [ContextMenuItem] {
    var remaining: [ContextMenuItem] = []
    var generated: [(RGContextMenuItemId, ContextMenuItem)] = []
    var anchor: Int?
    for item in items {
        let raw = item.identifier?.rawValue ?? ""
        if raw.hasPrefix("regram.message."), let id = RGContextMenuItemId(rawValue: String(raw.dropFirst("regram.message.".count))) {
            if anchor == nil { anchor = remaining.count }
            if id == .summarize { generated.removeAll { $0.0 == .summarize } }
            generated.append((id, item))
        } else {
            remaining.append(item)
        }
    }
    let configuration = RegramContextMenuConfiguration(settings: RegramPreferences.shared.settings(accountId: accountId))
    RegramMessageMenuInventory.shared.record(Set(generated.map { $0.0 }), accountId: accountId)
    remaining.insert(contentsOf: configuration.orderedItems(generated), at: min(anchor ?? remaining.count, remaining.count))
    var result: [ContextMenuItem] = []
    for item in remaining {
        if item.isSeparatorItem && (result.isEmpty || result.last?.isSeparatorItem == true) { continue }
        result.append(item)
    }
    if result.last?.isSeparatorItem == true { result.removeLast() }
    return result
}
