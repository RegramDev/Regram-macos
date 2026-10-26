import Foundation
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
import ChatHistoryModel

private struct CommonMessageGroupChoice: Equatable {
    let peerId: PeerId
    let title: String
}

private struct CommonGroupMessagesState: Equatable {
    var authorTitle = ""
    var rows: [RegramSearchMessageRow] = []
    var groups: [CommonMessageGroupChoice] = []
    var selectedGroup: PeerId?
    var loading = true
    var loadingGroups = true
    var available = true
    var failed = false
    var paused = false
    var hasMore = true
    var searchedGroups = 0
}

private final class CommonMessageGroupSearch {
    var peer: Peer
    var status: RegramGroupSearchStatus
    var cursor: SearchMessagesState?

    init(peer: Peer) {
        self.peer = peer
        self.status = RegramGroupSearchStatus(peerId: peer.id.toInt64())
    }
}

private final class CommonGroupMessagesSearch {
    let context: any AccountContextProtocol
    let authorPeerId: PeerId
    let state = ValuePromise(CommonGroupMessagesState(), ignoreRepeated: true)
    private let subscriptions = DisposableSet()
    private let groupsDisposable = MetaDisposable()
    private var groupsContext: GroupsInCommonContext?
    private var groupsTimer: SwiftSignalKit.Timer?
    private var groups: [PeerId: CommonMessageGroupSearch] = [:]
    private var requests: [PeerId: MetaDisposable] = [:]
    private var messages: [MessageId: Message] = [:]
    private var messageGroups: [MessageId: PeerId] = [:]
    private var selectedGroup: PeerId?
    private var generation = 0
    private var visible = false
    private var paused = false
    private var peersResolved = false
    private var allowed = false
    private var authorTitle = ""
    private var groupsComplete = false
    private var groupsFailed = false
    private var visibleLimit = RegramMessageSearchPolicy.displayPageSize

    private var busy: Bool { groupsContext != nil || !requests.isEmpty }
    private var failed: Bool { groupsFailed || groups.values.contains { (selectedGroup == nil || $0.peer.id == selectedGroup) && $0.status.failed } }

    init(context: any AccountContextProtocol, authorPeerId: PeerId) {
        self.context = context
        self.authorPeerId = authorPeerId
        subscriptions.add((context.account.postbox.peerView(id: authorPeerId) |> deliverOnMainQueue).start(next: { [weak self] view in
            guard let self else { return }
            let author = peerViewMainPeer(view)
            self.peersResolved = true
            self.authorTitle = author?.displayTitle ?? ""
            self.allowed = author is TelegramUser && author?.id == authorPeerId && authorPeerId.namespace == Namespaces.Peer.CloudUser && authorPeerId != context.peerId
            if !self.allowed { self.cancelRequests() }
            self.publish()
            self.resumeWork()
        }))
        subscriptions.add((regramMessageFilterChanges(accountId: context.peerId.toInt64()) |> deliverOnMainQueue).start(next: { [weak self] in
            self?.publish()
            self?.scheduleMessages()
        }))
        subscriptions.add((regramRemarkChanges(accountId: context.peerId.toInt64()) |> deliverOnMainQueue).start(next: { [weak self] in self?.publish() }))
    }

    private func filteredMessages() -> [Message] {
        guard allowed else { return [] }
        let scoped = messages.values.filter { selectedGroup == nil || messageGroups[$0.id] == selectedGroup }
        return regramVisibleMessages(scoped, accountId: context.peerId.toInt64()).sorted { regramSearchMessageOrder($0) > regramSearchMessageOrder($1) }
    }

    private var canLoadMore: Bool {
        filteredMessages().count > visibleLimit || groups.values.contains { (selectedGroup == nil || $0.peer.id == selectedGroup) && $0.status.hasMore && !$0.status.failed }
    }

    private func publish() {
        let accountId = context.peerId.toInt64()
        let formatter = regramSearchDateFormatter()
        var value = CommonGroupMessagesState()
        value.authorTitle = authorTitle
        value.available = !peersResolved || allowed
        value.loadingGroups = groupsContext != nil
        value.loading = busy || (!peersResolved && visible)
        value.paused = paused
        value.failed = failed
        value.selectedGroup = selectedGroup
        value.groups = groups.values.map { CommonMessageGroupChoice(peerId: $0.peer.id, title: regramSearchGroupTitle($0.peer, peerId: $0.peer.id, accountId: accountId)) }.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        value.rows = filteredMessages().prefix(visibleLimit).compactMap { message in
            guard let groupId = messageGroups[message.id] else { return nil }
            return regramSearchMessageRow(message, group: groups[groupId]?.peer, groupPeerId: groupId, accountId: accountId, dateFormatter: formatter)
        }
        value.searchedGroups = groups.values.filter { $0.status.loaded && (selectedGroup == nil || $0.peer.id == selectedGroup) }.count
        value.hasMore = !groupsComplete || canLoadMore
        state.set(value)
    }

    func resume() {
        visible = true
        publish()
        resumeWork()
    }

    private func resumeWork() {
        guard visible, allowed, !paused else { return }
        if !groupsComplete && !groupsFailed {
            loadGroups()
        } else {
            scheduleMessages()
        }
    }

    private func cancelRequests() {
        generation &+= 1
        groupsTimer?.invalidate()
        groupsTimer = nil
        groupsDisposable.set(nil)
        groupsContext = nil
        let current = requests
        requests.removeAll()
        current.values.forEach { $0.dispose() }
        groups.values.forEach { $0.status.loading = false }
    }

    func pause() {
        visible = false
        cancelRequests()
        publish()
    }

    func primaryAction() {
        if busy {
            paused = true
            cancelRequests()
            publish()
        } else if paused || failed {
            paused = false
            groupsFailed = false
            groups.values.forEach { $0.status.failed = false }
            resumeWork()
        } else {
            cancelRequests()
            groups.removeAll()
            messages.removeAll()
            messageGroups.removeAll()
            groupsComplete = false
            groupsFailed = false
            selectedGroup = nil
            visibleLimit = RegramMessageSearchPolicy.displayPageSize
            publish()
            resumeWork()
        }
    }

    func selectGroup(_ peerId: PeerId?) {
        if let peerId, groups[peerId] == nil { return }
        guard selectedGroup != peerId else { return }
        cancelRequests()
        selectedGroup = peerId
        visibleLimit = RegramMessageSearchPolicy.displayPageSize
        publish()
        resumeWork()
    }

    func loadMore() {
        guard visible, allowed, !busy, !paused, !failed, canLoadMore else { return }
        visibleLimit += RegramMessageSearchPolicy.displayPageSize
        publish()
        scheduleMessages()
    }

    private func loadGroups() {
        guard groupsContext == nil, visible, allowed, !paused else { return }
        let token = generation
        let common = GroupsInCommonContext(account: context.account, peerId: authorPeerId)
        groupsContext = common
        var confirmedIds = Set<PeerId>()
        groupsDisposable.set((common.state |> deliverOnMainQueue).start(next: { [weak self, weak common] value in
            guard let self, let common, self.generation == token, self.visible, !self.paused else { return }
            self.groupsTimer?.invalidate()
            self.groupsTimer = nil
            switch value.dataState {
            case .loading:
                let timer = SwiftSignalKit.Timer(timeout: 25, repeat: false, completion: { [weak self] in
                    guard let self, self.generation == token, self.visible else { return }
                    self.finishGroups(failed: true, confirmedIds: confirmedIds)
                }, queue: .mainQueue())
                self.groupsTimer = timer
                timer.start()
            case let .ready(canLoadMore):
                if value.loadFailed {
                    self.finishGroups(failed: true, confirmedIds: confirmedIds)
                    return
                }
                for rendered in value.peers {
                    guard let peer = rendered.peers[rendered.peerId], regramSearchIsGroup(peer) else { continue }
                    confirmedIds.insert(peer.id)
                    if let group = self.groups[peer.id] { group.peer = peer }
                    else { self.groups[peer.id] = CommonMessageGroupSearch(peer: peer) }
                }
                if canLoadMore {
                    DispatchQueue.main.async { [weak self, weak common] in
                        guard let self, self.generation == token, self.visible, !self.paused else { return }
                        common?.loadMore()
                    }
                } else {
                    self.finishGroups(failed: false, confirmedIds: confirmedIds)
                    return
                }
            }
            self.publish()
        }))
        publish()
    }

    private func finishGroups(failed: Bool, confirmedIds: Set<PeerId>) {
        groupsTimer?.invalidate()
        groupsTimer = nil
        groupsDisposable.set(nil)
        groupsContext = nil
        groupsComplete = !failed
        groupsFailed = failed
        if !failed {
            groups = groups.filter { confirmedIds.contains($0.key) }
            messageGroups = messageGroups.filter { confirmedIds.contains($0.value) }
            messages = messages.filter { messageGroups[$0.key] != nil }
            if let selectedGroup, groups[selectedGroup] == nil { self.selectedGroup = nil }
        }
        publish()
        scheduleMessages()
    }

    private func scheduleMessages() {
        guard visible, allowed, !paused, groupsComplete || groupsFailed else { return }
        let next = RegramMessageSearchPolicy.nextGroups(groups.values.map(\.status), orders: filteredMessages().map(regramSearchMessageOrder), visibleLimit: visibleLimit, selectedGroup: selectedGroup?.toInt64())
        for rawId in next {
            if let group = groups[PeerId(rawId)] { loadMessages(group) }
        }
        publish()
    }

    private func loadMessages(_ group: CommonMessageGroupSearch) {
        let peerId = group.peer.id
        let token = generation
        let oldCursor = group.cursor
        group.status.loading = true
        let request = MetaDisposable()
        requests[peerId] = request
        let location = SearchMessagesLocation.peer(peerId: peerId, fromId: authorPeerId, tags: nil, reactions: nil, threadId: nil, minDate: nil, maxDate: nil)
        let signal = context.engine.messages.searchMessages(location: location, query: "", state: oldCursor, limit: RegramMessageSearchPolicy.pageSize)
        |> map { result, cursor -> (SearchMessagesResult, SearchMessagesState)? in (result, cursor) }
        |> take(1)
        |> timeout(25, queue: .mainQueue(), alternate: .single(nil))
        |> deliverOnMainQueue
        request.set(signal.start(next: { [weak self, weak group] response in
            guard let self, let group, self.generation == token, self.visible, !self.paused else { return }
            self.requests.removeValue(forKey: peerId)?.dispose()
            group.status.loading = false
            if let (result, cursor) = response, !result.rgRequestFailed, result.completed || cursor != oldCursor {
                group.cursor = cursor
                group.status.loaded = true
                group.status.hasMore = !result.completed
                if let oldest = result.messages.map(regramSearchMessageOrder).min() {
                    group.status.oldest = min(group.status.oldest ?? oldest, oldest)
                }
                for message in result.messages where message.author?.id == self.authorPeerId {
                    self.messages[message.id] = message
                    self.messageGroups[message.id] = peerId
                }
            } else {
                group.status.failed = true
            }
            self.publish()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.scheduleMessages()
            }
        }))
    }

    func dispose() {
        cancelRequests()
        subscriptions.dispose()
    }

    deinit {
        groupsTimer?.invalidate()
        groupsDisposable.dispose()
        requests.values.forEach { $0.dispose() }
        subscriptions.dispose()
    }
}

private func commonGroupMessagesEntries(_ state: CommonGroupMessagesState, context: any AccountContextProtocol, authorPeerId: PeerId, search: CommonGroupMessagesSearch) -> [InputDataEntry] {
    var entries: [InputDataEntry] = [.sectionId(0, type: .normal)]
    var index: Int32 = 0
    entries.append(.general(sectionId: 1, index: index, value: .none, error: nil, identifier: InputDataIdentifier("commonGroupMessages.author"), data: .init(name: state.authorTitle.isEmpty ? regramString("CommonGroups.PageTitle") : state.authorTitle, color: theme.colors.text, type: .next, viewType: .firstItem, action: { RegramUIHooks.shared.openPeerInfo(context, authorPeerId) })))
    index += 1
    let choices = [ContextMenuItem(regramString("CommonGroups.All"), handler: { search.selectGroup(nil) }, state: state.selectedGroup == nil ? .on : .off)] + state.groups.map { group in
        ContextMenuItem(group.title, handler: { search.selectGroup(group.peerId) }, state: state.selectedGroup == group.peerId ? .on : .off)
    }
    let selected = state.groups.first { $0.peerId == state.selectedGroup }?.title ?? regramString("CommonGroups.All")
    entries.append(.general(sectionId: 1, index: index, value: .none, error: nil, identifier: InputDataIdentifier("commonGroupMessages.filter"), data: .init(name: regramString("CommonGroups.Filter"), color: theme.colors.text, type: .contextSelector(selected, choices), viewType: .lastItem, enabled: !state.groups.isEmpty && !state.loadingGroups)))
    index += 1
    entries.append(.desc(sectionId: 1, index: index, text: .plain(String(format: regramString("CommonGroups.LoadedSummary"), state.rows.count, state.searchedGroups, state.selectedGroup == nil ? state.groups.count : 1)), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1
    entries.append(.sectionId(2, type: .normal))
    entries.append(contentsOf: regramSearchMessageEntries(state.rows, context: context, sectionId: 3, index: &index))
    if !state.available || state.rows.isEmpty || state.failed || state.paused {
        let key = !state.available ? "CommonGroups.Unavailable" : state.loadingGroups ? "CommonGroups.LoadingGroups" : state.loading ? "CommonGroups.Loading" : state.failed ? "CommonGroups.PartialFailure" : state.paused ? "CommonGroups.Paused" : state.groups.isEmpty ? "CommonGroups.NoGroups" : "CommonGroups.Empty"
        entries.append(.desc(sectionId: 3, index: index, text: .plain(regramString(key)), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
    }
    if state.available {
        entries.append(.sectionId(4, type: .normal))
        let key = state.loading ? "CommonGroups.Cancel" : state.paused ? "CommonGroups.Continue" : state.failed ? "CommonGroups.Retry" : "CommonGroups.Refresh"
        entries.append(.general(sectionId: 5, index: index, value: .none, error: nil, identifier: InputDataIdentifier("commonGroupMessages.primary"), data: .init(name: regramString(key), color: theme.colors.accent, type: .none, viewType: state.hasMore && !state.loading ? .firstItem : .singleItem, action: search.primaryAction)))
        index += 1
        if state.hasMore && !state.loading {
            entries.append(.general(sectionId: 5, index: index, value: .none, error: nil, identifier: InputDataIdentifier("commonGroupMessages.more"), data: .init(name: regramString("CommonGroups.LoadMore"), color: theme.colors.accent, type: .none, viewType: .lastItem, enabled: !state.paused && !state.failed, action: search.loadMore)))
            index += 1
        } else if !state.hasMore && !state.loading {
            entries.append(.desc(sectionId: 5, index: index, text: .plain(regramString("CommonGroups.AllLoaded")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
            index += 1
        }
    }
    entries.append(.desc(sectionId: 5, index: index, text: .plain(regramString("CommonGroups.Scope")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    return entries
}

public func RegramCommonGroupMessagesController(context: any AccountContextProtocol, authorPeerId: PeerId) -> InputDataController {
    let search = CommonGroupMessagesSearch(context: context, authorPeerId: authorPeerId)
    let signal = combineLatest(search.state.get(), appearanceSignal) |> deliverOnPrepareQueue |> map { state, _ in
        InputDataSignalValue(entries: commonGroupMessagesEntries(state, context: context, authorPeerId: authorPeerId, search: search))
    }
    let controller = InputDataController(dataSignal: signal, title: regramString("CommonGroups.PageTitle"), removeAfterDisappear: false, hasDone: false, identifier: "regram.commonGroupMessages")
    controller.contextObject = search
    controller.didAppear = { _ in search.resume() }
    controller.willDisappear = { _ in search.pause() }
    controller.didLoad = { controller, _ in
        controller.tableView.setScrollHandler { position in
            if case .bottom = position.direction { search.loadMore() }
        }
    }
    controller.onDeinit = { search.dispose() }
    return controller
}
