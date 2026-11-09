import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import LocalAnimations
import GeneralRows
import ShortPeerRow
import AlertsUI
import CommunityUI
import SelectPeersUI
import ChatUI

private struct CommunityChildPreview: Equatable {
    var messages: [Message]
    var readCounters: EnginePeerReadCounters

    var timestamp: Int32 {
        return messages.map(\.timestamp).max() ?? 0
    }

    static func == (lhs: CommunityChildPreview, rhs: CommunityChildPreview) -> Bool {
        if lhs.readCounters != rhs.readCounters { return false }
        if lhs.messages.count != rhs.messages.count { return false }
        for (l, r) in zip(lhs.messages, rhs.messages) {
            if l.id != r.id || l.stableVersion != r.stableVersion { return false }
        }
        return true
    }
}

private func communityChildPreviewSignal(context: any AccountContextProtocol, peerId: PeerId) -> Signal<(PeerId, CommunityChildPreview), NoError> {
    var ignoredNamespaces = Set<Int32>()
    ignoredNamespaces = ignoredNamespaces.union(Namespaces.Message.allNonRegular)
    ignoredNamespaces = ignoredNamespaces.union(Namespaces.Message.allEphemeral)
    return combineLatest(
        context.account.postbox.aroundMessageHistoryViewForLocation(.peer(peerId: peerId, threadId: nil), anchor: .upperBound, ignoreMessagesInTimestampRange: nil, ignoreMessageIds: Set(), count: 10, clipHoles: false, fixedCombinedReadStates: nil, topTaggedMessageIdNamespaces: Set(), tag: nil, appendMessagesFromTheSameGroup: false, namespaces: .not(ignoredNamespaces), orderStatistics: []),
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Messages.PeerReadCounters(id: peerId))
    ) |> map { viewData, readCounters -> (PeerId, CommunityChildPreview) in
        let (view, _, _) = viewData
        var messages: [Message] = []
        for i in (0 ..< view.entries.count).reversed() {
            if messages.isEmpty {
                messages.append(view.entries[i].message)
            } else if messages[0].groupingKey != nil && messages[0].groupingKey == view.entries[i].message.groupingKey {
                messages.append(view.entries[i].message)
            }
        }
        messages = messages.reversed()
        return (peerId, CommunityChildPreview(messages: messages, readCounters: readCounters))
    }
}

private enum CommunityListSection {
    case joined
    case visible
    case requestable
}

private func bucket(_ peer: EnginePeer, canViewHistory: Bool, botHasPreview: Bool) -> CommunityListSection {
    if case let .channel(channel) = peer, case .member = channel.participationStatus {
        return .joined
    }
    // Bots aren't joinable chats (mirrors iOS): with a preview they read as "you are in", otherwise
    // they fall into the requestable bucket — never the plain "you can view" list.
    if case let .user(user) = peer, user.botInfo != nil {
        return botHasPreview ? .joined : .requestable
    }
    // `communityPeer.can_view_history` (layer 228): the history is readable right now without joining.
    // Public chats stay visible as a fallback for stale caches that predate the flag.
    if canViewHistory || peer.addressName != nil {
        return .visible
    }
    return .requestable
}

private struct CommunityListState: Equatable {
    var community: TelegramCommunity?
    var cachedData: CachedCommunityData?
    var peers: [PeerId: EnginePeer] = [:]
    var memberCounts: [PeerId: Int32] = [:]
    var previews: [PeerId: CommunityChildPreview] = [:]
    var hasLoadedLinkedPeerData: Bool = false
    var peersLimit: Int32 = 100
    var isAdmin: Bool { return (community?.adminRights != nil || community?.flags.contains(.isCreator) == true)  }
    var canAddChats: Bool {
        if (cachedData?.linkedPeers.count ?? 0) >= Int(peersLimit) { return false }
        if isAdmin { return true }
        return community?.defaultBannedRights?.flags.contains(.banManageLinkedPeers) != true
    }

    static func == (lhs: CommunityListState, rhs: CommunityListState) -> Bool {
        if lhs.community != rhs.community { return false }
        if lhs.cachedData?.linkedPeers != rhs.cachedData?.linkedPeers { return false }
        if lhs.cachedData?.pendingRequests != rhs.cachedData?.pendingRequests { return false }
        if lhs.cachedData?.adminsCount != rhs.cachedData?.adminsCount { return false }
        if lhs.peers != rhs.peers { return false }
        if lhs.memberCounts != rhs.memberCounts { return false }
        if lhs.previews != rhs.previews { return false }
        if lhs.hasLoadedLinkedPeerData != rhs.hasLoadedLinkedPeerData { return false }
        if lhs.peersLimit != rhs.peersLimit { return false }
        return true
    }
}

private final class CommunityListArguments {
    let context: any AccountContextProtocol
    let openPeer: (PeerId) -> Void
    let openPending: () -> Void
    let addChat: () -> Void
    let getState: () -> PeerListState
    let getNavigationHeight: () -> CGFloat
    let canRemove: () -> Bool
    let removeFromCommunity: (PeerId) -> Void
    init(context: any AccountContextProtocol, openPeer: @escaping (PeerId) -> Void, openPending: @escaping () -> Void, addChat: @escaping () -> Void, getState: @escaping () -> PeerListState, getNavigationHeight: @escaping () -> CGFloat, canRemove: @escaping () -> Bool, removeFromCommunity: @escaping (PeerId) -> Void) {
        self.context = context
        self.openPeer = openPeer
        self.openPending = openPending
        self.addChat = addChat
        self.getState = getState
        self.getNavigationHeight = getNavigationHeight
        self.canRemove = canRemove
        self.removeFromCommunity = removeFromCommunity
    }
}

private enum CommunityListEntryId: Hashable {
    case space
    case pending
    case section(Int)
    case peer(PeerId)
}

private enum CommunityListEntry: Comparable, Identifiable {
    case space(Int)
    case pending(Int32, Int)
    case section(Int, String, Int)
    case chat(EnginePeer, CommunityChildPreview?, Bool, Int)
    case requestable(EnginePeer, Int32?, GeneralViewType, Int)

    var stableId: CommunityListEntryId {
        switch self {
        case .space: return .space
        case .pending: return .pending
        case let .section(id, _, _): return .section(id)
        case let .chat(peer, _, _, _): return .peer(peer.id)
        case let .requestable(peer, _, _, _): return .peer(peer.id)
        }
    }
    var index: Int {
        switch self {
        case let .space(i): return i
        case let .pending(_, i): return i
        case let .section(_, _, i): return i
        case let .chat(_, _, _, i): return i
        case let .requestable(_, _, _, i): return i
        }
    }
    static func < (lhs: CommunityListEntry, rhs: CommunityListEntry) -> Bool {
        return lhs.index < rhs.index
    }
}

private func communityListEntries(_ state: CommunityListState) -> [CommunityListEntry] {
    var entries: [CommunityListEntry] = []
    var index: Int = 0

    entries.append(.space(index)); index += 1

    if state.isAdmin, let pending = state.cachedData?.pendingRequests, pending > 0 {
        entries.append(.pending(pending, index)); index += 1
    }

    guard let cachedData = state.cachedData else {
        return entries
    }
    let resolved: [EnginePeer] = cachedData.linkedPeers.compactMap { state.peers[$0.peerId] }
    var hiddenById: [PeerId: Bool] = [:]
    var canViewHistoryById: [PeerId: Bool] = [:]
    for linkedPeer in cachedData.linkedPeers {
        hiddenById[linkedPeer.peerId] = (linkedPeer.visible == false)
        canViewHistoryById[linkedPeer.peerId] = linkedPeer.canViewHistory
    }

    func appendSection(_ section: CommunityListSection, _ title: String, _ sectionId: Int) {
        let rows = resolved.filter { bucket($0, canViewHistory: canViewHistoryById[$0.id] ?? false, botHasPreview: state.previews[$0.id]?.messages.isEmpty == false) == section }
            .enumerated()
            .sorted { lhs, rhs in
                let lhsTimestamp = state.previews[lhs.element.id]?.timestamp ?? 0
                let rhsTimestamp = state.previews[rhs.element.id]?.timestamp ?? 0
                if lhsTimestamp != rhsTimestamp {
                    return lhsTimestamp > rhsTimestamp
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
        if rows.isEmpty { return }
        entries.append(.section(sectionId, title, index)); index += 1
        for peer in rows {
            if section == .requestable {
                let viewType: GeneralViewType = .innerItem
                entries.append(.requestable(peer, state.memberCounts[peer.id], viewType, index)); index += 1
            } else {
                entries.append(.chat(peer, state.previews[peer.id], hiddenById[peer.id] ?? false, index)); index += 1
            }
        }
    }

    appendSection(.joined, strings().communityListSectionJoined, 0)
    appendSection(.visible, strings().communityListSectionVisible, 1)
    appendSection(.requestable, strings().communityListSectionRequestable, 2)

    return entries
}

private func prepareCommunityTransition(from: [AppearanceWrapperEntry<CommunityListEntry>]?, to: [AppearanceWrapperEntry<CommunityListEntry>], arguments: CommunityListArguments, initialSize: NSSize, animated: Bool) -> Signal<TableUpdateTransition, NoError> {
    return Signal { subscriber in
        let context = arguments.context
        let (deleted, inserted, updated) = proccessEntriesWithoutReverse(from, right: to, { entry -> TableRowItem in
            switch entry.entry {
            case .space:
                return ChatListSpaceItem(initialSize, stableId: entry.stableId, getState: arguments.getState, getDeltaProgress: { nil }, getInterfaceState: { .concealed }, getNavigationHeight: arguments.getNavigationHeight)
            case let .pending(count, _):
                return CommunityPendingRowItem(initialSize, stableId: entry.stableId, context: context, count: count, action: arguments.openPending)
            case let .section(_, title, _):
                return SeparatorRowItem(initialSize, entry.stableId, string: title.uppercased(), height: 26)
            case let .chat(peer, preview, hidden, _):
                let item = ChatListRowItem(initialSize, context: context, stableId: UIChatListEntryId.chatId(.chatList(peer.id), peer.id, -1), mode: .chat, messages: preview?.messages ?? [], index: nil, readState: preview?.readCounters, draft: nil, pinnedType: .none, renderedPeer: EngineRenderedPeer(peer: peer), peerPresence: nil, forumTopicData: nil, forumTopicItems: [], activities: [], highlightText: nil, associatedGroupId: .root, isMuted: false, filter: .allChats, hideStatus: nil, titleMode: .normal, appearMode: .normal)
                item.communityHidden = hidden
                item.disableCommunityDropdown = true
                if arguments.canRemove() {
                    item.communityRemoveAction = {
                        arguments.removeFromCommunity(peer.id)
                    }
                }
                return item
            case let .requestable(peer, memberCount, viewType, _):
                let status: String?
                if let count = memberCount, count > 0 {
                    status = strings().communityListMembersOther(Int(count))
                } else {
                    status = nil
                }
                // A request-to-join chat can't be opened or previewed — tapping it explains why (invite-only)
                // rather than navigating into an inaccessible chat.
                return ShortPeerRowItem(initialSize, peer: peer._asPeer(), account: context.account, context: context, stableId: UIChatListEntryId.chatId(.chatList(peer.id), peer.id, -1), status: status, inset: NSEdgeInsets(left: 0, right: 0), generalType: .none, viewType: viewType, action: {
                    showModalText(for: context.window, text: strings().communityInviteOnlyInfo)
                })
            }
        })
        let transition = TableUpdateTransition(deleted: deleted, inserted: inserted, updated: updated, animated: animated, state: .none(nil))
        subscriber.putNext(transition)
        subscriber.putCompletion()
        return ActionDisposable {}
    } |> runOn(animated ? prepareQueue : .mainQueue())
}

open class CommunityListController<Context: AccountContextProtocol>: PeersListController<Context> {
    private let communityId: PeerId
    private let disposable = DisposableSet()
    private let previousEntries: Atomic<[AppearanceWrapperEntry<CommunityListEntry>]?> = Atomic(value: nil)
    private let communityStateValue = Atomic(value: CommunityListState())
    private let statePromise = ValuePromise(CommunityListState(), ignoreRepeated: true)
    private let addChatButton = TextButton()
    private var addChatButtonNaturalWidth: CGFloat = 0

    public init(_ context: Context, communityId: PeerId) {
        self.communityId = communityId
        super.init(context, followGlobal: true, mode: .community(communityId), searchOptions: [.chats, .messages])
    }

    private func updateState(_ f: (CommunityListState) -> CommunityListState) {
        statePromise.set(communityStateValue.modify(f))
    }

    open override var defaultBarTitle: String {
        return communityStateValue.with { $0.community?.title } ?? strings().communityListDefaultTitle
    }

    open override func viewDidLoad() {
        super.viewDidLoad()

        let context = self.context
        let communityId = self.communityId

        updateState { var c = $0; c.peersLimit = context.appConfiguration.getGeneralValue("community_peers_limit", orElse: 100); return c }

        self.setCenterTitle(self.defaultBarTitle)

        configureAddChatButton()
        genericView.addSubview(addChatButton)
        addChatButton.isHidden = true
        addChatButton.set(handler: { [weak self] _ in
            self?.addChat()
        }, for: .Click)

        disposable.add((statePromise.get() |> map { $0.canAddChats } |> distinctUntilChanged |> deliverOnMainQueue).start(next: { [weak self] _ in
            self?.updateAddChatButtonVisibility()
            self?.updateAddChatButtonFrame()
        }))

        disposable.add((stateUpdater |> map { $0.searchState == .Focus } |> distinctUntilChanged |> deliverOnMainQueue).start(next: { [weak self] _ in
            self?.updateAddChatButtonVisibility()
        }))

        let arguments = CommunityListArguments(context: context, openPeer: { peerId in
            ChatUIHooks.shared.navigateToChat(context.bindings.rootNavigation(), context, .peer(peerId))
        }, openPending: {
            showModal(with: CommunityRequestsController(context, communityId: communityId), for: context.window)
        }, addChat: { [weak self] in
            self?.addChat()
        }, getState: { [weak self] in
            return self?.stateValue.with { $0 } ?? .initialize(false)
        }, getNavigationHeight: { [weak self] in
            return self?.genericView.navigationHeight ?? 50
        }, canRemove: { [weak self] in
            return self?.communityStateValue.with { $0.isAdmin } ?? false
        }, removeFromCommunity: { [weak self] peerId in
            guard let self else { return }
            verifyAlert(for: context.window, information: strings().communityListRemoveChatConfirm, ok: strings().communityListRemove, successHandler: { _ in
                self.disposable.add((context.engine.peers.toggleCommunityPeerLink(communityId: communityId, peerId: peerId, action: .unlink) |> deliverOnMainQueue).start(error: { _ in
                    alert(for: context.window, info: strings().communityListErrorGeneric)
                }))
            })
        })

        disposable.add(combineLatest(queue: .mainQueue(),
            context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: communityId)),
            context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.CachedData(id: communityId))
        ).start(next: { [weak self] peer, cachedData in
            var community: TelegramCommunity? = nil
            if case let .community(value) = peer { community = value }
            self?.updateState { var c = $0; c.community = community; c.cachedData = cachedData as? CachedCommunityData; return c }
            self?.genericView.communityTitle = community?.title
            self?.setCenterTitle(self?.defaultBarTitle ?? strings().communityListDefaultTitle)
        }))
        context.account.viewTracker.forceUpdateCachedPeerData(peerId: communityId)

        let linkedPeerIds = statePromise.get()
            |> map { state -> [PeerId]? in
                return state.cachedData?.linkedPeers.map { $0.peerId }
            }
            |> distinctUntilChanged
        disposable.add(linkedPeerIds.start(next: { ids in
            for id in ids ?? [] { context.account.viewTracker.forceUpdateCachedPeerData(peerId: id) }
        }))
        let linkedPeerDataSignal = linkedPeerIds |> mapToSignal { maybeIds -> Signal<([PeerId: EnginePeer], [PeerId: Int32], [PeerId: CommunityChildPreview]), NoError> in
            guard let ids = maybeIds else { return .never() }
            if ids.isEmpty { return .single(([:], [:], [:])) }

            let peersSignal = combineLatest(
                context.engine.data.subscribe(EngineDataMap(ids.map { TelegramEngine.EngineData.Item.Peer.Peer(id: $0) })),
                context.engine.data.subscribe(EngineDataMap(ids.map { TelegramEngine.EngineData.Item.Peer.CachedData(id: $0) }))
            ) |> map { peers, cachedDatas in
                var peerMap: [PeerId: EnginePeer] = [:]
                var counts: [PeerId: Int32] = [:]
                for id in ids {
                    if let maybePeer = peers[id], let peer = maybePeer { peerMap[id] = peer }
                    let cached: CachedPeerData? = cachedDatas[id] ?? nil
                    if let c = cached as? CachedChannelData, let memberCount = c.participantsSummary.memberCount { counts[id] = memberCount }
                    else if let c = cached as? CachedGroupData, let p = c.participants { counts[id] = Int32(p.participants.count) }
                }
                return (peerMap, counts)
            }

            let previewsSignal = combineLatest(ids.map { communityChildPreviewSignal(context: context, peerId: $0) })
            |> map { values -> [PeerId: CommunityChildPreview] in
                var result: [PeerId: CommunityChildPreview] = [:]
                for (peerId, preview) in values { result[peerId] = preview }
                return result
            }

            return combineLatest(peersSignal, previewsSignal)
            |> map { peersAndCounts, previews in
                return (peersAndCounts.0, peersAndCounts.1, previews)
            }
        }
        disposable.add(linkedPeerDataSignal.start(next: { [weak self] peers, counts, previews in
            self?.updateState {
                var c = $0
                c.peers = peers
                c.memberCounts = counts
                c.previews = previews
                c.hasLoadedLinkedPeerData = true
                return c
            }
        }))

        let previousEntries = self.previousEntries
        let hasAppliedInitialLinkedPeerData = Atomic(value: false)
        let initialSize = self.atomicSize
        let transition = combineLatest(queue: prepareQueue, statePromise.get(), appearanceSignal)
            |> mapToQueue { state, appearance -> Signal<TableUpdateTransition, NoError> in
                let entries = communityListEntries(state).map { AppearanceWrapperEntry(entry: $0, appearance: appearance) }
                let previous = previousEntries.swap(entries)
                let hadAppliedInitialLinkedPeerData = hasAppliedInitialLinkedPeerData.swap(state.hasLoadedLinkedPeerData)
                return prepareCommunityTransition(from: previous, to: entries, arguments: arguments, initialSize: initialSize.with { $0 }, animated: previous != nil && hadAppliedInitialLinkedPeerData)
            }
            |> deliverOnMainQueue

        disposable.add(transition.start(next: { [weak self] transition in
            self?.genericView.tableView.merge(with: transition)
            self?.readyOnce()
            self?.afterTransaction(transition)
        }))
    }

    private func addChat() {
        let context = self.context
        let communityId = self.communityId
        let excluded = communityStateValue.with { ($0.cachedData?.linkedPeers ?? []).map { $0.peerId } }
        disposable.add(selectModalPeers(window: context.window, context: context, title: strings().communityListAddChatToCommunity, settings: [.groups, .channels], excludePeerIds: excluded, limit: 1, behavior: SelectCommunityChatsBehavior(excludePeerIds: excluded, limit: 1)).start(next: { peerIds in
            guard let peerId = peerIds.first else { return }
            showModal(with: CommunityAddController(context, communityId: communityId, peerId: peerId, completed: {
                context.account.viewTracker.forceUpdateCachedPeerData(peerId: communityId)
            }), for: context.window)
        }))
    }

    open override func selectionWillChange(row: Int, item: TableRowItem, byClick: Bool) -> Bool {
        if let item = item as? ChatListRowItem, item.peer != nil {
            return true
        }
        if item is ShortPeerRowItem {
            return true
        }
        return false
    }

    open override func selectionDidChange(row: Int, item: TableRowItem, byClick: Bool, isNew: Bool) -> Void {
        if let item = item as? ChatListRowItem {
            ChatListUIHooks.shared.updateGlobalPeer(context)
            open(with: item.entryId, initialAction: nil, addition: false, openAsTopics: item.isForum, fullWidthTopics: true)
        } else if let item = item as? ShortPeerRowItem {
            // Open the requestable chat through the same path as the chat rows so the global peer is set
            // (not merely refreshed) and the row's selection stays in sync.
            ChatListUIHooks.shared.updateGlobalPeer(context)
            open(with: .chatId(.chatList(item.peer.id), item.peer.id, -1), initialAction: nil, addition: false)
        }
    }

    private func configureAddChatButton() {
        let button = addChatButton
        button.set(font: .medium(.text), for: .Normal)
        button.set(text: strings().communityListAddChatToCommunity, for: .Normal)
        addChatButton.setAccessibilityLabel(strings().communityListAddChatToCommunity)
        button.set(color: theme.colors.underSelectedColor, for: .Normal)
        button.set(background: .clear, for: .Normal)
        button.set(image: generateCommunityAddChatIcon(), for: .Normal)
        button.direction = .left
        button.buttonImageInset = 8
        button.autohighlight = false
        button.scaleOnClick = true
        button.setGlassEffect(tintColor: theme.colors.accent)
        button.glassTintColor = theme.colors.accent
        _ = button.sizeToFit(NSMakeSize(48, 0))
        addChatButtonNaturalWidth = button.frame.width
    }

    private func updateAddChatButtonFrame() {
        let size = genericView.frame.size
        guard size.width > 0, size.height > 0 else { return }
        let height: CGFloat = 40
        let width = max(0, min(size.width - 40, addChatButtonNaturalWidth))
        let x = round((size.width - width) / 2)
        let y = size.height - containerContentInsets.bottom - height - 16
        addChatButton.frame = NSMakeRect(x, y, width, height)
        addChatButton.layer?.cornerRadius = height / 2
        genericView.contentBottomInset = containerContentInsets.bottom + (addChatButton.isHidden ? 0 : height + 16)
    }

    private func updateAddChatButtonVisibility() {
        let canAdd = communityStateValue.with { $0.canAddChats }
        let searching = genericView.searchView.state == .Focus
        addChatButton.isHidden = !canAdd || searching
        updateAddChatButtonFrame()
    }

    open override func updateContainerContentInsets(_ insets: NSEdgeInsets, transition: ContainedViewLayoutTransition) {
        super.updateContainerContentInsets(insets, transition: transition)
        guard isLoaded() else { return }
        updateAddChatButtonFrame()
    }

    open override func viewDidResized(_ size: NSSize) {
        super.viewDidResized(size)
        updateAddChatButtonFrame()
    }

    open override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        configureAddChatButton()
        updateAddChatButtonFrame()
    }

    open override func customContextMenu() -> ContextMenu? {
        let context = self.context
        let communityId = self.communityId
        let state = communityStateValue.with { $0 }
        let menu = ContextMenu()
        var hasActions = false
        if state.isAdmin {
            menu.addItem(ContextMenuItem(strings().communityListEditCommunity, handler: {
                context.bindings.rootNavigation().push(CommunityEditController(context, communityId: communityId))
            }, itemImage: MenuAnimation.menu_edit.value))
            hasActions = true
        }
        if state.canAddChats {
            menu.addItem(ContextMenuItem(strings().communityListAddChat, handler: { [weak self] in
                self?.addChat()
            }, itemImage: MenuAnimation.menu_plus.value))
            hasActions = true
        }
        if hasActions {
            menu.addItem(ContextSeparatorItem())
        }
        let isCollapsed = state.community?.collapsedInDialogs == true
        menu.addItem(ContextMenuItem(strings().communityListShowAsOneChat, handler: { [weak self] in
            guard let self else { return }
            let disposable = MetaDisposable()
            disposable.set(context.engine.peers.toggleCommunityCollapsedInDialogs(communityId: communityId, collapsed: false).start(error: { _ in
                disposable.dispose()
            }, completed: {
                disposable.dispose()
            }))
            self.navigationController?.back()
        }, itemImage: isCollapsed ? MenuAnimation.menu_check_selected.value : nil))
        return menu
    }

    open override func scrollup(force: Bool = false) {
        if force {
            genericView.tableView.scroll(to: .up(true), ignoreLayerAnimation: true)
            return
        }
        if genericView.searchView.state == .Focus {
            genericView.searchView.cancel(true)
            return
        }
        if genericView.tableView.contentOffset.y <= 0 {
            navigationController?.back()
            return
        }
        genericView.tableView.scroll(to: .up(true), ignoreLayerAnimation: true)
    }

    open override func escapeKeyAction() -> KeyHandlerResult {
        if genericView.searchView.state == .Focus {
            genericView.searchView.cancel(true)
            return .invoked
        }
        if let navigation = navigationController {
            navigation.back()
            return .invoked
        }
        return super.escapeKeyAction()
    }

    deinit {
        disposable.dispose()
    }
}

private final class CommunityPendingRowItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let titleLayout: TextViewLayout
    fileprivate let badge: BadgeNode
    fileprivate let pendingAction: () -> Void
    fileprivate let count: Int32
    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, count: Int32, action: @escaping () -> Void) {
        self.context = context
        self.count = count
        self.pendingAction = action
        self.titleLayout = TextViewLayout(.initialize(string: strings().communityListPendingRequests, color: theme.colors.text, font: .normal(.title)), maximumNumberOfLines: 1)
        self.badge = BadgeNode(.initialize(string: "\(count)", color: theme.chatList.badgeTextColor, font: .medium(.small)), theme.colors.accent)
        super.init(initialSize, height: 56, stableId: stableId, viewType: .legacy, inset: NSEdgeInsets(left: 20, right: 20))
    }
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        titleLayout.measure(width: width - 150)
        return true
    }
    override func viewClass() -> AnyClass {
        return CommunityPendingRowView.self
    }
    override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }
    override var accessibilityValue: String? {
        return "\(count)"
    }
    override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }
    override var accessibilityIncludesChildren: Bool {
        return false
    }
    override func accessibilityPerformPress() -> Bool {
        pendingAction()
        return true
    }
}

private final class CommunityPendingRowView: TableRowView {
    private let imageView = ImageView()
    private let textView = TextView()
    private let chevron = ImageView()
    private let badgeView = View()
    private let control = Control()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(control)
        addSubview(imageView)
        addSubview(textView)
        addSubview(badgeView)
        addSubview(chevron)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        textView.isEventLess = true
        badgeView.isEventLess = true
        imageView.isAccessibilityDecorative = true
        chevron.isAccessibilityDecorative = true
        control.setAccessibilityLabel(strings().communityListPendingRequests)
        control.set(handler: { [weak self] _ in
            if let item = self?.item as? CommunityPendingRowItem { item.pendingAction() }
        }, for: .Click)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    override var backdorColor: NSColor {
        return theme.colors.background
    }
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? CommunityPendingRowItem else { return }
        imageView.image = TelegramThemeHooks.shared.image(.iconCommunityPendingRequests).precomposed()
        imageView.sizeToFit()
        textView.update(item.titleLayout)
        item.badge.view = badgeView
        badgeView.setFrameSize(item.badge.size)
        item.badge.setNeedDisplay()
        chevron.image = theme.icons.generalNext
        chevron.sizeToFit()
        needsLayout = true
    }
    override func layout() {
        super.layout()
        control.frame = bounds
        imageView.centerY(x: 20)
        textView.centerY(x: imageView.frame.maxX + 12)
        chevron.centerY(x: frame.width - chevron.frame.width - 20)
        badgeView.centerY(x: chevron.frame.minX - badgeView.frame.width - 8)
    }
}

private func generateCommunityAddChatIcon() -> CGImage {
    let size = NSMakeSize(22, 22)
    return generateImage(size, contextGenerator: { size, ctx in
        ctx.clear(CGRect(origin: .zero, size: size))
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(origin: .zero, size: size))
        ctx.setBlendMode(.clear)
        ctx.setLineWidth(3)
        ctx.setLineCap(.round)
        let inset: CGFloat = 6
        ctx.move(to: CGPoint(x: size.width / 2, y: inset))
        ctx.addLine(to: CGPoint(x: size.width / 2, y: size.height - inset))
        ctx.move(to: CGPoint(x: inset, y: size.height / 2))
        ctx.addLine(to: CGPoint(x: size.width - inset, y: size.height / 2))
        ctx.strokePath()
    })!
}
