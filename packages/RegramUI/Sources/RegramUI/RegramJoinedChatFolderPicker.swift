import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import InputDataUI
import GeneralRows
import AlertsUI
import RegramCore

private struct RegramJoinedFolderCandidate: Equatable {
    let id: Int32
    let title: String
}

private struct RegramJoinedFolderState: Equatable {
    let chatTitle: String
    let candidates: [RegramJoinedFolderCandidate]
}

private final class RegramJoinedFolderArguments {
    let select: (RegramJoinedFolderCandidate) -> Void
    init(select: @escaping (RegramJoinedFolderCandidate) -> Void) { self.select = select }
}

private func regramJoinedFolderEntries(_ state: RegramJoinedFolderState, arguments: RegramJoinedFolderArguments) -> [InputDataEntry] {
    var rows: [InputDataEntry] = [.sectionId(0, type: .normal)]
    let title = String(format: regramString("ios.JoinFolder.Picker.Title"), state.chatTitle)
    rows.append(.desc(sectionId: 1, index: 0, text: .plain(title), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    for (index, candidate) in state.candidates.enumerated() {
        let viewType: GeneralViewType = state.candidates.count == 1 ? .singleItem : index == 0 ? .firstItem : index == state.candidates.count - 1 ? .lastItem : .innerItem
        rows.append(.general(sectionId: 1, index: Int32(index + 1), value: .none, error: nil, identifier: InputDataIdentifier("joinedFolder_" + String(candidate.id)), data: .init(name: candidate.title, color: theme.colors.accent, type: .none, viewType: viewType, action: { arguments.select(candidate) })))
    }
    return rows
}

private func regramJoinedPeerIsMuted(peer: EnginePeer, notificationSettings: EnginePeer.NotificationSettings, global: EngineGlobalNotificationSettings) -> Bool {
    switch notificationSettings.muteState {
    case let .muted(until): return until >= Int32(Date().timeIntervalSince1970)
    case .unmuted: return false
    case .default:
        switch peer {
        case .user: return !global.privateChats.enabled
        case .legacyGroup: return !global.groupChats.enabled
        case let .channel(channel):
            if case .broadcast = channel.info { return !global.channels.enabled }
            return !global.groupChats.enabled
        case .community: return true
        case .secretChat: return false
        }
    }
}

private func regramJoinedFolderAlreadyShows(data: ChatListFilterData, peer: EnginePeer, isMuted: Bool) -> Bool {
    if data.includePeers.peers.contains(peer.id) || data.includePeers.pinnedPeers.contains(peer.id) { return true }
    if data.excludePeers.contains(peer.id) || data.excludeRead || data.excludeMuted && isMuted { return false }
    switch peer {
    case .legacyGroup, .community: return data.categories.contains(.groups)
    case let .channel(channel):
        if case .broadcast = channel.info { return data.categories.contains(.channels) }
        return data.categories.contains(.groups)
    case .user, .secretChat: return false
    }
}

public func RegramPresentFolderPickerAfterJoining(context: any AccountContextProtocol, peerId: PeerId) {
    let accountId = context.peerId.toInt64()
    guard peerId.namespace != Namespaces.Peer.SecretChat, RegramPreferences.shared.settings(accountId: accountId)["chooseFolderAfterJoining"].bool else { return }
    let source = combineLatest(context.engine.peers.updatedChatListFilters() |> take(1), context.engine.data.get(
        TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId),
        TelegramEngine.EngineData.Item.Configuration.UserLimits(isPremium: false),
        TelegramEngine.EngineData.Item.Configuration.UserLimits(isPremium: true),
        TelegramEngine.EngineData.Item.Peer.Peer(id: peerId),
        TelegramEngine.EngineData.Item.Peer.NotificationSettings(id: peerId),
        TelegramEngine.EngineData.Item.NotificationSettings.Global()
    )) |> take(1) |> deliverOnMainQueue
    _ = source.startStandalone(next: { filters, values in
        guard RegramPreferences.shared.settings(accountId: accountId)["chooseFolderAfterJoining"].bool else { return }
        let (accountPeer, limits, premiumLimits, peer, notificationSettings, global) = values
        guard let peer else { return }
        let premium: Bool
        if case let .user(user)? = accountPeer { premium = user.flags.contains(.isPremium) } else { premium = false }
        let limit = Int(premium ? premiumLimits.maxFolderChatsCount : limits.maxFolderChatsCount)
        let muted = regramJoinedPeerIsMuted(peer: peer, notificationSettings: notificationSettings, global: global)
        let candidates = filters.compactMap { filter -> RegramJoinedFolderCandidate? in
            guard case let .filter(id, title, _, data) = filter, !regramJoinedFolderAlreadyShows(data: data, peer: peer, isMuted: muted), data.includePeers.peers.count < limit else { return nil }
            var updated = data
            guard updated.addIncludePeer(peerId: peerId) else { return nil }
            return RegramJoinedFolderCandidate(id: id, title: title.text)
        }
        guard !candidates.isEmpty else { return }
        let state = RegramJoinedFolderState(chatTitle: peer._asPeer().compactDisplayTitle, candidates: candidates)
        let statePromise = ValuePromise(state, ignoreRepeated: true)
        var close: (() -> Void)?
        let arguments = RegramJoinedFolderArguments(select: { candidate in
            close?()
            let add = context.engine.peers.updateChatListFiltersInteractively { filters in
                filters.map { filter in
                    guard case let .filter(id, title, emoticon, data) = filter, id == candidate.id, data.includePeers.peers.count < limit else { return filter }
                    var updated = data
                    guard updated.addIncludePeer(peerId: peerId) else { return filter }
                    return .filter(id: id, title: title, emoticon: emoticon, data: updated)
                }
            } |> take(1) |> deliverOnMainQueue
            _ = add.startStandalone(next: { filters in
                let added = filters.contains { filter in
                    guard case let .filter(id, _, _, data) = filter, id == candidate.id else { return false }
                    return data.includePeers.peers.contains(peerId) || data.includePeers.pinnedPeers.contains(peerId)
                }
                if added { _ = showModalSuccess(for: context.window, icon: theme.icons.successModalProgress, delay: 1.5).startStandalone() }
                else { alert(for: context.window, info: regramString("ios.JoinFolder.Unavailable")) }
            })
        })
        let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in InputDataSignalValue(entries: regramJoinedFolderEntries(state, arguments: arguments)) }
        let controller = InputDataController(dataSignal: signal, title: strings().chatListFilterAddToFolder, removeAfterDisappear: false, hasDone: false)
        let modal = InputDataModalController(controller, size: NSMakeSize(360, 350))
        close = { [weak modal] in modal?.modal?.close() }
        controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { close?() })
        showModal(with: modal, for: context.window)
    })
}
