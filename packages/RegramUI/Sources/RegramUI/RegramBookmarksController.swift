import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramContext
import TelegramTheme
import TelegramUtils
import InputDataUI
import AlertsUI
import Localization
import RegramCore
import RegramSignals
import ChatHistoryModel
import GeneralRows

private let bookmarkSearchId = InputDataIdentifier("bookmarks_search")

private enum BookmarkAvailability: Equatable {
    case cached
    case notCached
    case loading
    case failed
    case unavailable

    var key: String {
        switch self {
        case .cached: return "cached"
        case .notCached: return "notCached"
        case .loading: return "loading"
        case .failed: return "failed"
        case .unavailable: return "unavailable"
        }
    }
}

private struct BookmarkRow: Equatable {
    let bookmark: RGMessageBookmark
    let title: String
    let preview: String?
    let peer: PeerEquatable?
    let date: String
}

private struct BookmarkSnapshot {
    let bookmark: RGMessageBookmark
    let message: Message?
    let peer: Peer?
}

private struct BookmarkRequest: Equatable {
    var tag: String?
    var limit = 100
    var revision = 0
    var query = ""
}

private struct BookmarkState: Equatable {
    var rows: [BookmarkRow] = []
    var tags: [String] = []
    var tag: String?
    var total = 0
    var loading = true
    var selecting = false
    var selected = Set<RGBookmarkMessageId>()
    var availability: [RGBookmarkMessageId: BookmarkAvailability] = [:]
    var query = ""
}

private final class BookmarkArguments {
    let context: any AccountContextProtocol
    var setTag: (String?) -> Void = { _ in }
    var setQuery: (String) -> Void = { _ in }
    var resetFilters: () -> Void = {}
    var toggleSelecting: () -> Void = {}
    var toggle: (RGBookmarkMessageId) -> Void = { _ in }
    var selectAll: () -> Void = {}
    var open: (BookmarkRow) -> Void = { _ in }
    var fetch: (BookmarkRow) -> Void = { _ in }
    var editTags: (RGMessageBookmark) -> Void = { _ in }
    var bulkTags: (Bool) -> Void = { _ in }
    var remove: (Set<RGBookmarkMessageId>) -> Void = { _ in }
    var removeSelected: () -> Void = {}
    var loadMore: () -> Void = {}

    init(context: any AccountContextProtocol) { self.context = context }
}

private struct BookmarkPresentation: Equatable {
    let row: BookmarkRow
    let availability: BookmarkAvailability
    let query: String
    let viewType: GeneralViewType
    let selection: Bool?
}

private func bookmarkEntries(_ state: BookmarkState, arguments: BookmarkArguments) -> [InputDataEntry] {
    var rows: [InputDataEntry] = [.sectionId(0, type: .normal)]
    rows.append(regramSearchEntry(sectionId: 1, index: 0, value: state.query, identifier: bookmarkSearchId, update: arguments.setQuery))
    rows.append(.sectionId(2, type: .normal))
    let filters = [(regramString("bookmarks.all"), Optional<String>.none), (regramString("bookmarks.untagged"), Optional(""))] + state.tags.map { ($0, Optional($0)) }
    let items = filters.map { title, tag in ContextMenuItem(title, handler: { arguments.setTag(tag) }, state: state.tag == tag ? .on : .off) }
    let tagTitle = state.tag.map { $0.isEmpty ? regramString("bookmarks.untagged") : $0 } ?? regramString("bookmarks.all")
    rows.append(.general(sectionId: 3, index: 0, value: .none, error: nil, identifier: InputDataIdentifier("bookmarks_filter"), data: .init(name: regramString("bookmarks.filter"), color: theme.colors.text, type: .contextSelector(tagTitle, items), viewType: .singleItem)))
    if state.selecting {
        rows.append(.sectionId(4, type: .normal))
        rows.append(.desc(sectionId: 5, index: 0, text: .plain(strings().messageActionsPanelSelectedCountOther(state.selected.count)), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        rows.append(.general(sectionId: 5, index: 1, value: .none, error: nil, identifier: InputDataIdentifier("bookmarks_select_all"), data: .init(name: regramString("bookmarks.selectVisible"), color: theme.colors.text, type: .selectable(!state.rows.isEmpty && state.selected.count == state.rows.count), viewType: .firstItem, enabled: !state.rows.isEmpty, action: arguments.selectAll)))
        rows.append(.general(sectionId: 5, index: 2, value: .none, error: nil, identifier: InputDataIdentifier("bookmarks_add_tag"), data: .init(name: regramString("bookmarks.addTag"), color: theme.colors.text, type: .next, viewType: .innerItem, enabled: !state.selected.isEmpty, action: { arguments.bulkTags(false) })))
        rows.append(.general(sectionId: 5, index: 3, value: .none, error: nil, identifier: InputDataIdentifier("bookmarks_remove_tag"), data: .init(name: regramString("bookmarks.removeTag"), color: theme.colors.text, type: .next, viewType: .innerItem, enabled: !state.selected.isEmpty, action: { arguments.bulkTags(true) })))
        rows.append(.general(sectionId: 5, index: 4, value: .none, error: nil, identifier: InputDataIdentifier("bookmarks_remove_selected"), data: .init(name: regramString("bookmarks.removeSelected"), color: theme.colors.redUI, type: .none, viewType: .lastItem, enabled: !state.selected.isEmpty, action: arguments.removeSelected)))
    }
    rows.append(.sectionId(6, type: .normal))
    for (index, row) in state.rows.enumerated() {
        let bookmark = row.bookmark
        let id = bookmark.messageId
        let key = "\(id.peerId)_\(id.namespace)_\(id.id)"
        let messageId = MessageId(peerId: PeerId(id.peerId), namespace: id.namespace, id: id.id)
        let canFetchFromCloud = regramBookmarkCanFetchFromCloud(messageId)
        let availability: BookmarkAvailability = row.preview != nil ? .cached : state.availability[id] ?? (canFetchFromCloud ? .notCached : .unavailable)
        let viewType: GeneralViewType = state.rows.count == 1 ? .singleItem : index == 0 ? .firstItem : index == state.rows.count - 1 ? .lastItem : .innerItem
        let preview = row.preview ?? regramString("bookmarks.state." + availability.key)
        let selection: Bool? = state.selecting ? state.selected.contains(id) : nil
        rows.append(.custom(sectionId: 7, index: Int32(index), value: .none, identifier: InputDataIdentifier("bookmark_" + key), equatable: InputDataEquatable(BookmarkPresentation(row: row, availability: availability, query: state.query, viewType: viewType, selection: selection)), comparable: nil, item: { size, stableId in
                regramSearchMessageRowItem(size, stableId: stableId, title: row.title, date: row.date, preview: preview, query: state.query, footer: bookmark.tags.map { "#" + $0 }.joined(separator: "  "), selection: selection, viewType: viewType, action: {
                    if state.selecting { arguments.toggle(id) } else { arguments.open(row) }
                }, menu: {
                    let open = ContextMenuItem(strings().messageContextGoto, handler: { arguments.open(row) })
                    open.isEnabled = availability != .loading
                    var items = [open]
                    if availability != .cached, canFetchFromCloud {
                        let fetch = ContextMenuItem(regramString(availability == .notCached ? "bookmarks.fetch" : "bookmarks.retry"), handler: { arguments.fetch(row) })
                        fetch.isEnabled = availability != .loading
                        items.append(fetch)
                    }
                    items.append(ContextMenuItem(regramString("Bookmarks.EditTags"), handler: { arguments.editTags(bookmark) }))
                    items.append(ContextMenuItem(regramString("Bookmarks.Remove"), handler: { arguments.remove([id]) }, itemMode: .destruct))
                    return items
                })
            }))
    }
    if state.rows.isEmpty {
        let filtered = !state.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.tag != nil
        let emptyText = regramString(filtered ? "Bookmarks.NoResults" : "emptyBookmarks")
        rows.append(.custom(sectionId: 7, index: 0, value: .none, identifier: InputDataIdentifier("bookmarks_empty"), equatable: InputDataEquatable(state), comparable: nil, item: { size, stableId in
            RegramEmptyRowItem(size, stableId: stableId, height: filtered && !state.loading ? 210 : 180, isLoading: state.loading, text: emptyText, action: filtered && !state.loading ? .init(click: arguments.resetFilters, title: regramString("bookmarks.all")) : nil)
        }))
    }
    if state.rows.count < state.total {
        rows.append(.sectionId(8, type: .normal))
        rows.append(.general(sectionId: 9, index: 0, value: .none, error: nil, identifier: InputDataIdentifier("bookmarks_more"), data: .init(name: regramString("bookmarks.loadMore"), color: theme.colors.accent, type: .none, viewType: .singleItem, action: arguments.loadMore)))
    }
    rows.append(.desc(sectionId: 10, index: 0, text: .plain(regramString("Bookmarks.LocalNotice")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    return rows
}

public func RegramBookmarksController(context: any AccountContextProtocol) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let disposables = DisposableSet()
    var fetches: [RGBookmarkMessageId: MetaDisposable] = [:]
    let initial = BookmarkState()
    let state = ValuePromise(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)
    let updateState: ((BookmarkState) -> BookmarkState) -> Void = { change in state.set(stateValue.modify(change)) }
    let request = ValuePromise(BookmarkRequest(), ignoreRepeated: true)
    let requestValue = Atomic(value: BookmarkRequest())
    let updateRequest: ((BookmarkRequest) -> BookmarkRequest) -> Void = { change in request.set(requestValue.modify(change)) }
    let visible = ValuePromise(false, ignoreRepeated: true)
    let visibleValue = Atomic(value: false)
    let loadingQueue = Queue(name: "regram.bookmarks.loading", qos: .userInitiated)
    let changes: Signal<Void, NoError> = Signal { subscriber in
        let token = NotificationCenter.default.addObserver(forName: RGMessageBookmarks.didChange, object: nil, queue: nil) { notification in
            if notification.object as? Int64 == accountId { subscriber.putNext(()) }
        }
        subscriber.putNext(())
        return ActionDisposable { NotificationCenter.default.removeObserver(token) }
    }
    disposables.add((combineLatest(changes, request.get(), regramRemarkChanges(accountId: accountId), visible.get()) |> deliverOn(loadingQueue) |> mapToSignal { _, request, _, visible -> Signal<([BookmarkRow], [String], Int, BookmarkRequest), NoError> in
        guard visible, visibleValue.with({ $0 }), requestValue.with({ $0 == request }) else { return .complete() }
        let all = RGMessageBookmarks.shared.bookmarks(accountId: accountId)
        let filtered = all.filter { bookmark in
            guard let tag = request.tag else { return true }
            return tag.isEmpty ? bookmark.tags.isEmpty : bookmark.tags.contains { $0.compare(tag, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame }
        }
        let query = request.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let bookmarks = query.isEmpty ? Array(filtered.prefix(request.limit)) : filtered
        let tags = RGMessageBookmarks.shared.tags(accountId: accountId)
        return context.account.postbox.transaction { transaction -> [BookmarkSnapshot] in
            guard visibleValue.with({ $0 }), requestValue.with({ $0 == request }) else { return [] }
            var snapshots: [BookmarkSnapshot] = []
            snapshots.reserveCapacity(bookmarks.count)
            for (index, bookmark) in bookmarks.enumerated() {
                if index % 64 == 0, !visibleValue.with({ $0 }) || !requestValue.with({ $0 == request }) { return [] }
                let id = MessageId(peerId: PeerId(bookmark.messageId.peerId), namespace: bookmark.messageId.namespace, id: bookmark.messageId.id)
                snapshots.append(BookmarkSnapshot(bookmark: bookmark, message: transaction.getMessage(id), peer: transaction.getPeer(id.peerId)))
            }
            return snapshots
        } |> deliverOn(loadingQueue) |> map { snapshots -> ([BookmarkRow], [String], Int, BookmarkRequest) in
            guard visibleValue.with({ $0 }), requestValue.with({ $0 == request }) else { return ([], tags, 0, request) }
            let dateFormatter = regramSearchDateFormatter()
            let rows = snapshots.map { snapshot -> BookmarkRow in
                let bookmark = snapshot.bookmark
                let id = MessageId(peerId: PeerId(bookmark.messageId.peerId), namespace: bookmark.messageId.namespace, id: bookmark.messageId.id)
                let message = snapshot.message
                let peer = snapshot.peer
                let title = RGGroupRemarks.shared.name(accountId: accountId, peerId: bookmark.messageId.peerId) ?? peer?.displayTitle ?? regramString("bookmarks.unknownChat")
                let preview = message.map { message -> String in
                    let body = regramSearchMessageRow(message, group: peer, groupPeerId: id.peerId, accountId: accountId, dateFormatter: dateFormatter).preview
                    if let peer, regramSearchIsGroup(peer), let author = message.author, author.id != id.peerId {
                        return author.displayTitle + ": " + body
                    }
                    return body
                }
                return BookmarkRow(bookmark: bookmark, title: title, preview: preview, peer: peer.map { PeerEquatable(peer: $0) }, date: dateFormatter.string(from: Date(timeIntervalSince1970: message.map { TimeInterval($0.timestamp) } ?? bookmark.addedAt)))
            }
            let matches = rows.filter { row in
                query.isEmpty || ([row.title, row.preview ?? ""] + row.bookmark.tags).contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil }
            }
            return (Array(matches.prefix(request.limit)), tags, query.isEmpty ? filtered.count : matches.count, request)
        }
    } |> deliverOnMainQueue).start(next: { rows, tags, total, request in
        guard visibleValue.with({ $0 }), requestValue.with({ $0 == request }) else { return }
        updateState { current in
            var current = current
            current.rows = rows
            current.tags = tags
            current.total = total
            current.tag = request.tag
            current.query = request.query
            current.loading = false
            current.selected.formIntersection(Set(rows.map { $0.bookmark.messageId }))
            return current
        }
    }))
    let arguments = BookmarkArguments(context: context)
    var clearSearch: () -> Void = {}
    let reload: () -> Void = { updateRequest { current in var current = current; current.revision &+= 1; return current } }
    enum FetchError: Error, Equatable { case inaccessible; case failed }
    let fetch: (BookmarkRow, Bool) -> Void = { row, openAfter in
        let id = row.bookmark.messageId
        guard visibleValue.with({ $0 }), !context.isFrozen, fetches[id] == nil else { return }
        let messageId = MessageId(peerId: PeerId(id.peerId), namespace: id.namespace, id: id.id)
        updateState { current in var current = current; current.availability[id] = .loading; return current }
        let pending = MetaDisposable()
        fetches[id] = pending
        let canFetchFromCloud = regramBookmarkCanFetchFromCloud(messageId)
        let signal = context.engine.messages.getMessagesLoadIfNecessary([messageId], strategy: canFetchFromCloud ? .cloud(skipLocal: false) : .local)
            |> mapError { _ in FetchError.inaccessible }
            |> filter { if case .result = $0 { return true }; return false }
            |> take(1)
            |> timeout(15, queue: .mainQueue(), alternate: .fail(.failed))
            |> deliverOnMainQueue
        pending.set(signal.start(next: { result in
            guard visibleValue.with({ $0 }), !context.isFrozen, fetches[id] === pending else { return }
            fetches.removeValue(forKey: id)
            guard RGMessageBookmarks.shared.bookmark(accountId: accountId, messageId: id) != nil else { return }
            if case let .result(messages) = result {
                let loaded = messages.contains { $0.id == messageId }
                updateState { current in var current = current; current.availability[id] = loaded ? .cached : canFetchFromCloud ? .failed : .unavailable; return current }
                reload()
                if loaded, openAfter { RegramUIHooks.shared.openMessage(context, messageId, row.bookmark.threadId) }
            }
        }, error: { error in
            guard visibleValue.with({ $0 }), fetches[id] === pending else { return }
            fetches.removeValue(forKey: id)
            updateState { current in var current = current; current.availability[id] = error == .inaccessible ? .unavailable : .failed; return current }
        }))
    }
    arguments.setTag = { tag in
        guard requestValue.with({ $0.tag }) != tag else { return }
        updateState { current in var current = current; current.selected.removeAll(); current.loading = true; return current }
        updateRequest { current in var current = current; current.tag = tag; current.limit = 100; return current }
    }
    arguments.setQuery = { query in
        guard requestValue.with({ $0.query }) != query else { return }
        updateState { current in var current = current; current.query = query; current.selected.removeAll(); current.loading = true; return current }
        updateRequest { current in var current = current; current.query = query; current.limit = 100; return current }
    }
    arguments.resetFilters = {
        updateState { current in var current = current; current.query = ""; current.tag = nil; current.selected.removeAll(); current.loading = true; return current }
        updateRequest { current in var current = current; current.query = ""; current.tag = nil; current.limit = 100; return current }
        clearSearch()
    }
    arguments.toggleSelecting = { updateState { current in var current = current; current.selecting.toggle(); current.selected.removeAll(); return current } }
    arguments.toggle = { id in updateState { current in var current = current; if !current.selected.insert(id).inserted { current.selected.remove(id) }; return current } }
    arguments.selectAll = { updateState { current in
        var current = current
        let visible = Set(current.rows.map { $0.bookmark.messageId })
        current.selected = current.selected == visible ? [] : visible
        return current
    } }
    arguments.open = { row in
        guard visibleValue.with({ $0 }), !context.isFrozen else { return }
        if row.preview != nil {
            let id = row.bookmark.messageId
            RegramUIHooks.shared.openMessage(context, MessageId(peerId: PeerId(id.peerId), namespace: id.namespace, id: id.id), row.bookmark.threadId)
        } else { fetch(row, true) }
    }
    arguments.fetch = { fetch($0, false) }
    arguments.editTags = { context.bindings.rootNavigation().push(RegramBookmarkTagsController(context: context, bookmark: $0)) }
    arguments.bulkTags = { removing in
        let ids = stateValue.with { $0.selected }
        guard !ids.isEmpty else { return }
        context.bindings.rootNavigation().push(RegramBookmarkBulkTagsController(context: context, ids: ids, removing: removing))
    }
    arguments.remove = { ids in
        guard !ids.isEmpty else { return }
        verifyAlert(for: context.window, header: regramString("bookmarks.removeSelected"), information: String(format: regramString("bookmarks.removeConfirm"), ids.count), successHandler: { _ in RGMessageBookmarks.shared.remove(accountId: accountId, messageIds: ids) })
    }
    arguments.removeSelected = { [weak arguments] in arguments?.remove(stateValue.with { $0.selected }) }
    arguments.loadMore = { updateRequest { current in var current = current; current.limit += 100; return current } }
    let signal = combineLatest(state.get(), appearanceSignal) |> deliverOnPrepareQueue |> map { state, _ in InputDataSignalValue(entries: bookmarkEntries(state, arguments: arguments)) }
    let controller = RegramFormController(dataSignal: signal, title: regramString("bookmarks"), validateData: { _ in
        arguments.toggleSelecting()
        return .fail(.none)
    }, updateDoneValue: { _ in
        let current = stateValue.with { $0 }
        return { update in
            if current.selecting {
                update(.enabled(strings().navigationDone))
            } else if current.rows.isEmpty {
                update(.disabled(strings().messageContextSelect))
            } else {
                update(.enabled(strings().messageContextSelect))
            }
        }
    }, removeAfterDisappear: false, hasDone: true, identifier: "regram.bookmarks", returnKeyInvocation: { _, _ in .nothing }, doneString: { strings().messageContextSelect })
    clearSearch = { [weak controller] in
        if let view = controller?.tableView.item(stableId: InputDataEntryId.custom(bookmarkSearchId))?.viewNecessary as? SearchRowView {
            view.searchView.setString("")
        }
    }
    regramRestoreSearchQuery(controller, identifier: bookmarkSearchId, query: { stateValue.with { $0.query } })
    controller.didAppear = { _ in
        _ = visibleValue.swap(true)
        reload()
        visible.set(true)
    }
    controller.willDisappear = { _ in
        _ = visibleValue.swap(false)
        visible.set(false)
        let pending = Array(fetches.values)
        fetches.removeAll()
        pending.forEach { $0.dispose() }
        updateState { current in
            var current = current
            current.availability = current.availability.filter { $0.value != .loading }
            return current
        }
    }
    controller.onDeinit = { disposables.dispose(); fetches.values.forEach { $0.dispose() }; fetches.removeAll() }
    return controller
}

private func RegramBookmarkTagsController(context: any AccountContextProtocol, bookmark: RGMessageBookmark) -> InputDataController {
    RegramBookmarkTagEditorController(context: context, title: regramString("Bookmarks.EditTags"), tags: bookmark.tags, requireTags: false, save: { tags in
        RGMessageBookmarks.shared.save(accountId: context.peerId.toInt64(), messageId: bookmark.messageId, threadId: bookmark.threadId, tags: tags)
    })
}

private func RegramBookmarkBulkTagsController(context: any AccountContextProtocol, ids: Set<RGBookmarkMessageId>, removing: Bool) -> InputDataController {
    RegramBookmarkTagEditorController(context: context, title: regramString(removing ? "bookmarks.removeTag" : "bookmarks.addTag"), tags: [], requireTags: true, save: { tags in
        RGMessageBookmarks.shared.updateTags(accountId: context.peerId.toInt64(), messageIds: ids, adding: removing ? [] : tags, removing: removing ? tags : [])
    })
}

private func RegramBookmarkTagEditorController(context: any AccountContextProtocol, title: String, tags: [String], requireTags: Bool, save: @escaping ([String]) -> Void) -> InputDataController {
    let id = InputDataIdentifier("regram_tags")
    let initial = tags.joined(separator: ", ")
    let state = Atomic(value: initial)
    let promise = ValuePromise(initial, ignoreRepeated: true)
    let available = RGMessageBookmarks.shared.tags(accountId: context.peerId.toInt64())
    func update(_ value: String) {
        _ = state.swap(value)
        promise.set(value)
    }
    func normalized(_ value: String) -> [String] {
        RGMessageBookmarks.normalizedTags(value.components(separatedBy: ","))
    }
    let signal = combineLatest(promise.get(), appearanceSignal) |> map { value, _ -> InputDataSignalValue in
        let selected = normalized(value)
        var entries: [InputDataEntry] = [
            .sectionId(0, type: .normal),
            .input(sectionId: 1, index: 0, value: .string(value), error: nil, identifier: id, mode: .plain, data: .init(viewType: .singleItem), placeholder: .init(regramString("Bookmarks.Tags")), inputPlaceholder: regramString("tags"), filter: { $0 }, limit: 512),
            .desc(sectionId: 1, index: 1, text: .plain(regramString("Bookmarks.TagsNotice")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem))
        ]
        if !available.isEmpty {
            entries.append(.sectionId(2, type: .normal))
            for (index, tag) in available.enumerated() {
                let contains = selected.contains { $0.compare(tag, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame }
                entries.append(.general(sectionId: 3, index: Int32(index + 2), value: .none, error: nil, identifier: InputDataIdentifier("regram_existing_tag_" + tag), data: .init(name: tag, color: theme.colors.text, type: .selectable(contains), viewType: bestGeneralViewType(available, for: tag), enabled: contains || selected.count < RGMessageBookmarks.maximumTags, action: {
                    var selected = normalized(state.with { $0 })
                    if selected.contains(where: { $0.compare(tag, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame }) {
                        selected.removeAll { $0.compare(tag, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame }
                    } else {
                        guard selected.count < RGMessageBookmarks.maximumTags else { return }
                        selected.append(tag)
                    }
                    update(RGMessageBookmarks.normalizedTags(selected).joined(separator: ", "))
                })))
            }
        }
        return InputDataSignalValue(entries: entries)
    }
    return RegramFormController(dataSignal: signal, title: title, validateData: { data in
        let tags = normalized(data[id]?.stringValue ?? state.with { $0 })
        guard !requireTags || !tags.isEmpty else { return .fail(.fields([id: .shake])) }
        save(tags)
        return .success(.navigationBack)
    }, updateDatas: { data in
        if let value = data[id]?.stringValue { update(value) }
        return .fail(.none)
    }, updateDoneValue: { _ in
        let enabled = !requireTags || !normalized(state.with { $0 }).isEmpty
        return { $0(enabled ? .enabled(strings().navigationDone) : .disabled(strings().navigationDone)) }
    }, removeAfterDisappear: false)
}
