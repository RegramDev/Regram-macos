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
import GeneralRows
import RegramCore
import RegramSignals
import ChatHistoryModel
import ShortPeerRow

private let authorMessagesSearchId = InputDataIdentifier("authorMessages.search")

private struct AuthorMessagesState: Equatable {
    var authorTitle = ""
    var author: PeerEquatable?
    var query = ""
    var groupTitle = ""
    var rows: [RegramSearchMessageRow] = []
    var loading = true
    var available = true
    var failed = false
    var paused = false
    var hasMore = true
}

private struct AuthorMessagesIdentity: Equatable {
    let author: PeerEquatable?
    let groupTitle: String
}

private final class AuthorMessagesSearch {
    let context: any AccountContextProtocol
    let chatPeerId: PeerId
    let authorPeerId: PeerId
    let threadId: Int64?
    let state = ValuePromise(AuthorMessagesState(), ignoreRepeated: true)
    private let subscriptions = DisposableSet()
    private let request = MetaDisposable()
    private var generation = 0
    private var visible = false
    private var paused = false
    private var loading = false
    private var failed = false
    private var peersResolved = false
    private var allowed = false
    private var authorTitle = ""
    private var author: Peer?
    private var group: Peer?
    private var query = ""
    private var inputQuery = ""
    var currentQuery: String { inputQuery }
    private var cursor: SearchMessagesState?
    private var messages: [MessageId: Message] = [:]
    private var loaded = false
    private var hasMore = true
    private var visibleLimit = RegramMessageSearchPolicy.displayPageSize

    init(context: any AccountContextProtocol, chatPeerId: PeerId, authorPeerId: PeerId, threadId: Int64?) {
        self.context = context
        self.chatPeerId = chatPeerId
        self.authorPeerId = authorPeerId
        self.threadId = threadId
        subscriptions.add((combineLatest(context.account.postbox.peerView(id: chatPeerId), context.account.postbox.peerView(id: authorPeerId)) |> deliverOnMainQueue).start(next: { [weak self] groupView, authorView in
            guard let self else { return }
            self.peersResolved = true
            self.group = peerViewMainPeer(groupView)
            let author = peerViewMainPeer(authorView)
            self.author = author
            self.authorTitle = author?.displayTitle ?? ""
            self.allowed = self.group.map(regramSearchIsGroup) == true && author?.id == authorPeerId
            if !self.allowed { self.cancelRequest() }
            self.publish()
            self.schedule()
        }))
        subscriptions.add((regramMessageFilterChanges(accountId: context.peerId.toInt64()) |> deliverOnMainQueue).start(next: { [weak self] in
            self?.publish()
            self?.schedule()
        }))
        subscriptions.add((regramRemarkChanges(accountId: context.peerId.toInt64()) |> deliverOnMainQueue).start(next: { [weak self] in self?.publish() }))
    }

    private func filteredMessages() -> [Message] {
        guard allowed else { return [] }
        return regramVisibleMessages(Array(messages.values), accountId: context.peerId.toInt64()).sorted { regramSearchMessageOrder($0) > regramSearchMessageOrder($1) }
    }

    private func publish() {
        let accountId = context.peerId.toInt64()
        let formatter = regramSearchDateFormatter()
        var value = AuthorMessagesState()
        value.authorTitle = authorTitle
        value.author = author.map { PeerEquatable(peer: $0) }
        value.query = inputQuery
        value.groupTitle = regramSearchGroupTitle(group, peerId: chatPeerId, accountId: accountId)
        value.available = !peersResolved || allowed
        value.loading = loading || (!peersResolved && visible)
        value.failed = failed
        value.paused = paused
        let filtered = filteredMessages()
        value.rows = filtered.prefix(visibleLimit).map { regramSearchMessageRow($0, group: group, groupPeerId: chatPeerId, accountId: accountId, dateFormatter: formatter, threadId: threadId) }
        value.hasMore = hasMore || filtered.count > visibleLimit
        state.set(value)
    }

    func resume() {
        visible = true
        publish()
        schedule()
    }

    private func cancelRequest() {
        generation &+= 1
        request.set(nil)
        loading = false
    }

    func pause() {
        visible = false
        cancelRequest()
        publish()
    }

    func primaryAction() {
        if loading {
            paused = true
            cancelRequest()
            publish()
        } else if paused || failed {
            paused = false
            failed = false
            schedule(force: true)
        } else {
            reset(debounce: false)
        }
    }

    func updateQuery(_ value: String) {
        guard inputQuery != value else { return }
        inputQuery = value
        let query = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query != self.query else { publish(); return }
        self.query = query
        reset(debounce: !query.isEmpty)
    }

    private func reset(debounce: Bool) {
        cancelRequest()
        cursor = nil
        messages.removeAll()
        loaded = false
        hasMore = true
        failed = false
        paused = false
        visibleLimit = RegramMessageSearchPolicy.displayPageSize
        publish()
        load(debounce: debounce)
    }

    func loadMore() {
        guard visible, allowed, !loading, !paused, !failed, hasMore || filteredMessages().count > visibleLimit else { return }
        visibleLimit += RegramMessageSearchPolicy.displayPageSize
        publish()
        schedule()
    }

    private func schedule(force: Bool = false) {
        guard visible, allowed, !loading, !paused, !failed, hasMore else { return }
        guard force || !loaded || filteredMessages().count < visibleLimit else { return }
        load(debounce: false)
    }

    private func load(debounce: Bool) {
        guard visible, allowed, !loading, !paused, !failed, hasMore else { return }
        loading = true
        publish()
        let token = generation
        let oldCursor = cursor
        let location = SearchMessagesLocation.peer(peerId: chatPeerId, fromId: authorPeerId, tags: nil, reactions: nil, threadId: threadId, minDate: nil, maxDate: nil)
        let signal = Signal<String, NoError>.single(query)
        |> delay(debounce ? 0.3 : 0.0, queue: .mainQueue())
        |> mapToSignal { [context] query in context.engine.messages.searchMessages(location: location, query: query, state: oldCursor, limit: 50) }
        |> map { result, cursor -> (SearchMessagesResult, SearchMessagesState)? in (result, cursor) }
        |> take(1)
        |> timeout(25, queue: .mainQueue(), alternate: .single(nil))
        |> deliverOnMainQueue
        request.set(signal.start(next: { [weak self] response in
            guard let self, self.visible, self.generation == token else { return }
            self.loading = false
            guard let (result, nextCursor) = response, !result.rgRequestFailed, result.completed || nextCursor != oldCursor else {
                self.failed = true
                self.publish()
                return
            }
            self.cursor = nextCursor
            self.loaded = true
            self.hasMore = !result.completed
            for message in result.messages where message.author?.id == self.authorPeerId {
                self.messages[message.id] = message
            }
            self.publish()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.schedule()
            }
        }))
    }

    func dispose() {
        cancelRequest()
        subscriptions.dispose()
    }

    deinit {
        request.dispose()
        subscriptions.dispose()
    }
}

private func authorMessagesEntries(_ state: AuthorMessagesState, context: any AccountContextProtocol, authorPeerId: PeerId, search: AuthorMessagesSearch) -> [InputDataEntry] {
    var entries: [InputDataEntry] = [.sectionId(0, type: .normal)]
    var index: Int32 = 0
    if let author = state.author?.peer {
        entries.append(.custom(sectionId: 1, index: index, value: .none, identifier: InputDataIdentifier("authorMessages.author"), equatable: InputDataEquatable(AuthorMessagesIdentity(author: state.author, groupTitle: state.groupTitle)), comparable: nil, item: { size, stableId in
            ShortPeerRowItem(size, peer: author, account: context.account, context: context, stableId: stableId, height: 64, photoSize: NSSize(width: 40, height: 40), status: state.groupTitle, viewType: .firstItem, action: { RegramUIHooks.shared.openPeerInfo(context, authorPeerId) })
        }))
        index += 1
    }
    entries.append(regramSearchEntry(sectionId: 1, index: index, value: state.query, identifier: authorMessagesSearchId, viewType: state.author == nil ? .singleItem : .lastItem, update: search.updateQuery))
    index += 1
    entries.append(.desc(sectionId: 1, index: index, text: .plain(regramString("AuthorMessages.Scope")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1
    entries.append(.sectionId(2, type: .normal))
    if state.rows.isEmpty {
        let key = !state.available ? "AuthorMessages.Unavailable" : state.loading ? "AuthorMessages.Loading" : state.failed ? "AuthorMessages.LoadFailed" : state.paused ? "AuthorMessages.Paused" : state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "AuthorMessages.Empty" : "AuthorMessages.NoResults"
        let action: SearchEmptyRowItem.Action? = state.available && !state.loading && (state.failed || state.paused) ? .init(click: search.primaryAction, title: regramString(state.failed ? "AuthorMessages.Retry" : "CommonGroups.Continue")) : nil
        entries.append(.custom(sectionId: 3, index: index, value: .none, identifier: InputDataIdentifier("authorMessages.empty"), equatable: InputDataEquatable(state), comparable: nil, item: { size, stableId in
            SearchEmptyRowItem(size, stableId: stableId, height: action == nil ? 180 : 210, isLoading: state.available && state.loading, text: regramString(key), action: action)
        }))
        index += 1
    } else {
        entries.append(.desc(sectionId: 3, index: index, text: .plain(String(format: regramString("AuthorMessages.Loaded"), state.rows.count)), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
        entries.append(contentsOf: regramSearchMessageEntries(state.rows, context: context, sectionId: 3, index: &index, author: state.author?.peer, query: state.query))
        if state.failed || state.paused {
            entries.append(.desc(sectionId: 3, index: index, text: .plain(regramString(state.failed ? "AuthorMessages.LoadFailed" : "AuthorMessages.Paused")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
            index += 1
        }
    }
    if state.available && (!state.rows.isEmpty || state.loading || (!state.failed && !state.paused)) {
        entries.append(.sectionId(4, type: .normal))
        let key = state.loading ? "CommonGroups.Cancel" : state.paused ? "CommonGroups.Continue" : state.failed ? "AuthorMessages.Retry" : "CommonGroups.Refresh"
        let showMore = state.hasMore && !state.loading && !state.paused && !state.failed && !state.rows.isEmpty
        entries.append(.general(sectionId: 5, index: index, value: .none, error: nil, identifier: InputDataIdentifier("authorMessages.primary"), data: .init(name: regramString(key), color: theme.colors.accent, type: state.loading && !state.rows.isEmpty ? .loading : .none, viewType: showMore ? .firstItem : .singleItem, action: search.primaryAction)))
        index += 1
        if showMore {
            entries.append(.general(sectionId: 5, index: index, value: .none, error: nil, identifier: InputDataIdentifier("authorMessages.more"), data: .init(name: regramString("CommonGroups.LoadMore"), color: theme.colors.accent, type: .none, viewType: .lastItem, action: search.loadMore)))
            index += 1
        } else if !state.hasMore && !state.loading && !state.rows.isEmpty {
            entries.append(.desc(sectionId: 5, index: index, text: .plain(regramString("CommonGroups.AllLoaded")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
            index += 1
        }
    }
    return entries
}

public func RegramAuthorMessagesController(context: any AccountContextProtocol, chatPeerId: PeerId, authorPeerId: PeerId, threadId: Int64? = nil, focusSetting: String? = nil) -> InputDataController {
    let search = AuthorMessagesSearch(context: context, chatPeerId: chatPeerId, authorPeerId: authorPeerId, threadId: threadId)
    let signal = combineLatest(search.state.get(), appearanceSignal) |> deliverOnPrepareQueue |> map { state, _ in
        InputDataSignalValue(entries: authorMessagesEntries(state, context: context, authorPeerId: authorPeerId, search: search))
    }
    let controller = InputDataController(dataSignal: signal, title: regramString("AuthorMessages.PageTitle"), updateDatas: { data in
        if let query = data[authorMessagesSearchId]?.stringValue { search.updateQuery(query) }
        return .fail(.none)
    }, removeAfterDisappear: false, hasDone: false, identifier: "regram.authorMessages")
    controller.contextObject = search
    controller.didAppear = { _ in search.resume() }
    controller.willDisappear = { _ in search.pause() }
    controller.didLoad = { controller, _ in
        controller.tableView.setScrollHandler { position in
            if case .bottom = position.direction { search.loadMore() }
        }
    }
    regramRestoreSearchQuery(controller, identifier: authorMessagesSearchId, query: { search.currentQuery })
    controller.onDeinit = { search.dispose() }
    regramFocusSettings(controller, page: "authorMessages", item: focusSetting)
    return controller
}
