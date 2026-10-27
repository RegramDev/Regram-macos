import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramContext
import TelegramTheme
import TelegramUtils
import InputDataUI
import RegramCore
import RegramSignals
import ShortPeerRow
import GeneralRows

private struct RegramPeerSettingPresentation: Equatable {
    let peer: EnginePeer
    let viewType: GeneralViewType
}

private func recordChanges(_ name: Notification.Name, accountId: Int64) -> Signal<Void, NoError> {
    Signal { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { notification in
            guard notification.object as? Int64 == accountId else { return }
            subscriber.putNext(())
        }
        subscriber.putNext(())
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    }
}

public func RegramRecentChatsController(context: any AccountContextProtocol) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let signal = combineLatest(recordChanges(RegramRecentChats.didChange, accountId: accountId), appearanceSignal, regramRemarkChanges(accountId: accountId)) |> mapToSignal { _, _, _ in
        context.account.postbox.transaction { transaction in RegramRecentChats.shared.peers(accountId: accountId).compactMap { transaction.getPeer(PeerId($0)) } }
    } |> deliverOnMainQueue |> map { peers -> InputDataSignalValue in
        var rows: [InputDataEntry] = [.sectionId(0, type: .normal)]
        for (index, peer) in peers.enumerated() {
            rows.append(.general(sectionId: 1, index: Int32(index), value: .none, error: nil, identifier: InputDataIdentifier("recent_\(peer.id.toInt64())"), data: .init(name: RGGroupRemarks.shared.name(accountId: accountId, peerId: peer.id.toInt64()) ?? peer.displayTitle, color: theme.colors.text, type: .next, viewType: peers.count == 1 ? .singleItem : index == 0 ? .firstItem : index == peers.count - 1 ? .lastItem : .innerItem, action: { RegramUIHooks.shared.openPeer(context, peer.id) })))
        }
        if peers.isEmpty { rows.append(.desc(sectionId: 1, index: 0, text: .plain(regramString("recent.empty")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem))) }
        rows.append(.sectionId(1, type: .normal))
        rows.append(.general(sectionId: 2, index: Int32(peers.count), value: .none, error: nil, identifier: InputDataIdentifier("recent_clear"), data: .init(name: regramString("clearRecent"), color: theme.colors.redUI, type: .none, viewType: .singleItem, action: { RegramRecentChats.shared.clear(accountId: accountId) })))
        return InputDataSignalValue(entries: rows)
    }
    return InputDataController(dataSignal: signal, title: regramString("recent"), removeAfterDisappear: false, hasDone: false, identifier: "regram.recent")
}

public func RegramHiddenPeersController(context: any AccountContextProtocol, focusSetting: String? = nil) -> InputDataController {
    regramPeerSettingListController(context: context, key: "blockedPeerIds", title: "HiddenUsers.Title", notice: "HiddenUsers.Notice", empty: "HiddenUsers.Empty", focusSetting: focusSetting)
}

public func RegramAntiRevokeChatsController(context: any AccountContextProtocol, focusSetting: String? = nil) -> InputDataController {
    regramPeerSettingListController(context: context, key: "antiRevokePeerIds", title: "AntiRevoke.Chats.Title", notice: "AntiRevoke.Chats.Notice", empty: "AntiRevoke.Chats.Empty", focusSetting: focusSetting)
}

private func regramPeerSettingListController(context: any AccountContextProtocol, key: String, title: String, notice: String, empty: String, focusSetting: String?) -> InputDataController {
    let accountId = context.peerId.toInt64()
    func remove(_ id: PeerId) {
        RegramPreferences.shared.update(accountId: accountId) { $0[key] = .strings($0[key].strings.filter { $0 != String(id.toInt64()) }) }
    }
    let peersSignal: Signal<[(Int64, Peer?)], NoError> = combineLatest(regramPreferenceChanges(accountId: accountId), appearanceSignal) |> mapToSignal { settings, _ in
        context.account.postbox.transaction { transaction in
            let records: [(Int64, Peer?)] = settings[key].strings.compactMap(Int64.init).map { ($0, transaction.getPeer(PeerId($0))) }
            return records.sorted {
                ($0.1?.displayTitle ?? "ID \($0.0)").localizedCaseInsensitiveCompare($1.1?.displayTitle ?? "ID \($1.0)") == .orderedAscending
            }
        }
    }
    let signal = peersSignal |> deliverOnMainQueue |> map { peers -> InputDataSignalValue in
        var rows: [InputDataEntry] = [.sectionId(0, type: .normal)]
        rows.append(.desc(sectionId: 1, index: 0, text: .plain(regramString(peers.isEmpty ? empty : notice)), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        for (index, record) in peers.enumerated() {
            let viewType: GeneralViewType = peers.count == 1 ? .singleItem : index == 0 ? .firstItem : index + 1 == peers.count ? .lastItem : .innerItem
            let peerId = PeerId(record.0)
            let identifier = InputDataIdentifier("peerSetting_\(record.0)")
            if let peer = record.1 {
                rows.append(.custom(sectionId: 1, index: Int32(index + 1), value: .none, identifier: identifier, equatable: InputDataEquatable(RegramPeerSettingPresentation(peer: EnginePeer(peer), viewType: viewType)), comparable: nil, item: { size, stableId in
                    ShortPeerRowItem(size, peer: peer, account: context.account, context: context, stableId: stableId, interactionType: .deletable(onRemove: remove, deletable: true), viewType: viewType, action: { RegramUIHooks.shared.openPeerInfo(context, peerId) }, contextMenuItems: { .single([ContextMenuItem(regramString("MessageFilter.Rule.Delete"), handler: { remove(peerId) })]) })
                }))
            } else {
                rows.append(.general(sectionId: 1, index: Int32(index + 1), value: .none, error: nil, identifier: identifier, data: .init(name: "ID \(record.0)", color: theme.colors.text, type: .next, viewType: viewType, action: { RegramUIHooks.shared.openPeerInfo(context, peerId) }, menuItems: { [ContextMenuItem(regramString("MessageFilter.Rule.Delete"), handler: { remove(peerId) })] })))
            }
        }
        return InputDataSignalValue(entries: rows)
    }
    let controller = InputDataController(dataSignal: signal, title: regramString(title), removeAfterDisappear: false, hasDone: false, identifier: "regram." + (key == "blockedPeerIds" ? "hiddenUsers" : "antiRevokeChats"))
    regramFocusSettings(controller, page: key == "blockedPeerIds" ? "hiddenUsers" : "antiRevokeChats", item: focusSetting)
    return controller
}
