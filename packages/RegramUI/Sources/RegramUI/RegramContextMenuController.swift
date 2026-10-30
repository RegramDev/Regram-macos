import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import InputDataUI
import GeneralRows
import RegramCore
import RegramSignals

private func menuIdentifier(_ id: RGContextMenuItemId) -> InputDataIdentifier { InputDataIdentifier("regram_menu_" + id.rawValue) }

public func RegramContextMenuController(context: any AccountContextProtocol) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let disposables = DisposableSet()
    let promise = ValuePromise(RegramPreferences.shared.settings(accountId: accountId), ignoreRepeated: false)
    func visible(_ settings: RegramAccountSettings) -> [RGContextMenuItemId] {
        RegramContextMenuConfiguration(settings: settings).order.filter { RegramMessageMenuInventory.shared.available(accountId: accountId).contains($0) && $0.canBeCustomized }
    }
    func reorder(from: Int, to: Int) {
        RegramPreferences.shared.update(accountId: accountId) { settings in
            var items = visible(settings)
            guard items.indices.contains(from), items.indices.contains(to), from != to else { return }
            let moved = items.remove(at: from)
            items.insert(moved, at: to)
            settings["contextMenuOrder"] = .strings(RegramContextMenuConfiguration(settings: settings).reorderingVisible(items).map(\.rawValue))
        }
    }
    let signal = combineLatest(promise.get(), appearanceSignal) |> map { settings, _ -> InputDataSignalValue in
        let configuration = RegramContextMenuConfiguration(settings: settings)
        let items = visible(settings)
        var rows: [InputDataEntry] = [.sectionId(0, type: .normal)]
        for (index, id) in items.enumerated() {
            let type: GeneralViewType = items.count == 1 ? .singleItem : index == 0 ? .firstItem : index == items.count - 1 ? .lastItem : .innerItem
            rows.append(.general(sectionId: 1, index: Int32(index), value: .none, error: nil, identifier: menuIdentifier(id), data: .init(name: regramString("menu." + id.rawValue), color: theme.colors.text, type: .switchable(configuration.isEnabled(id)), viewType: type, action: {
                RegramPreferences.shared.update(accountId: accountId) { settings in
                    if let key = RegramContextMenuConfiguration.settingKey(id) {
                        settings[key] = .bool(!settings[key].bool)
                    } else {
                        var disabled = Set(settings["contextMenuDisabledItems"].strings)
                        if disabled.contains(id.rawValue) { disabled.remove(id.rawValue) }
                        else { disabled.insert(id.rawValue) }
                        settings["contextMenuDisabledItems"] = .strings(disabled.sorted())
                    }
                }
            })))
        }
        rows.append(.desc(sectionId: 1, index: Int32(items.count), text: .plain(regramString("ios.Settings.ContextMenu.Notice")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        return InputDataSignalValue(entries: rows)
    }
    let controller = RegramFormController(dataSignal: signal, title: regramString("ios.Settings.ContextMenu"), removeAfterDisappear: false, hasDone: false, identifier: "regram.contextMenu")
    controller.afterTransaction = { controller in
        let ids = Set(visible(RegramPreferences.shared.settings(accountId: accountId)).map(menuIdentifier))
        var range = NSRange(location: NSNotFound, length: 0)
        controller.tableView.enumerateItems { item in
            if let entry = item.stableId.base as? InputDataEntryId, let id = entry.identifier, ids.contains(id) {
                if range.location == NSNotFound { range.location = item.index }
                range.length += 1
            }
            return true
        }
        if range.location != NSNotFound {
            controller.tableView.resortController = .init(resortRange: range, start: { _ in }, resort: { _ in }, complete: { from, to in
                reorder(from: from - range.location, to: to - range.location)
            })
        } else {
            controller.tableView.resortController = nil
        }
    }
    disposables.add(regramPreferenceChanges(accountId: accountId).start(next: { promise.set($0) }))
    let observer = NotificationCenter.default.addObserver(forName: RegramMessageMenuInventory.didChange, object: nil, queue: .main) { notification in
        guard notification.object as? Int64 == accountId else { return }
        promise.set(RegramPreferences.shared.settings(accountId: accountId))
    }
    controller.onDeinit = { NotificationCenter.default.removeObserver(observer); disposables.dispose() }
    return controller
}
