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
import RegramCore
import RegramSignals
import ChatHistoryModel

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
}

private struct BookmarkRequest: Equatable {
    var tag: String?
    var limit = 100
    var revision = 0
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
}

private final class BookmarkArguments {
    let context: any AccountContextProtocol
    var setTag: (String?) -> Void = { _ in }
    var toggleSelecting: () -> Void = {}
    var toggle: (RGBookmarkMessageId) -> Void = { _ in }
    var selectAll: () -> Void = {}
    var open: (BookmarkRow) -> Void = { _ in }
    var fetch: (BookmarkRow) -> Void = { _ in }
    var editTags: (RGMessageBookmark) -> Void = { _ in }
    var bulkTags: (Bool) -> Void = { _ in }
    var remove: (Set<RGBookmarkMessageId>) -> Void = { _ in }
    var loadMore: () -> Void = {}

    init(context: any AccountContextProtocol) { self.context = context }
}

private func bookmarkEntries(_ state: BookmarkState, arguments: BookmarkArguments) -> [InputDataEntry] {
    var rows: [InputDataEntry] = [.sectionId(0, type: .normal)]
    let filters = [(regramString("bookmarks.all"), Optional<String>.none), (regramString("bookmarks.untagged"), Optional(""))] + state.tags.map { ($0, Optional($0)) }
    let items = filters.map { title, tag in ContextMenuItem(title, handler: { arguments.setTag(tag) }, state: state.tag == tag ? .on : .off) }
    let tagTitle = state.tag.map { $0.isEmpty ? regramString("bookmarks.untagged") : $0 } ?? regramString("bookmarks.all")
    rows.append(.general(sectionId: 1, index: 0, value: .none, error: nil, identifier: InputDataIdentifier("bookmarks_filter"), data: .init(name: regramString("bookmarks.filter"), color: theme.colors.text, type: .contextSelector(tagTitle, items), viewType: .firstItem)))
    rows.append(.general(sectionId: 1, index: 1, value: .none, error: nil, identifier: InputDataIdentifier("bookmarks_select"), data: .init(name: regramString(state.selecting ? "bookmarks.doneSelecting" : "bookmarks.select"), color: theme.colors.accent, type: .none, viewType: .lastItem, action: arguments.toggleSelecting)))
    rows.append(.desc(sectionId: 1, index: 2, text: .plain(regramString("bookmarks.notice")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    if state.selecting {
        rows.append(.sectionId(2, type: .normal))
        rows.append(.general(sectionId: 3, index: 3, value: .none, error: nil, identifier: InputDataIdentifier("bookmarks_select_all"), data: .init(name: regramString("bookmarks.selectVisible"), color: theme.colors.accent, type: .context(String(state.selected.count)), viewType: .firstItem, action: arguments.selectAll)))
        rows.append(.general(sectionId: 3, index: 4, value: .none, error: nil, identifier: InputDataIdentifier("bookmarks_add_tag"), data: .init(name: regramString("bookmarks.addTag"), color: theme.colors.text, type: .next, viewType: .innerItem, enabled: !state.selected.isEmpty, action: { arguments.bulkTags(false) })))
        rows.append(.general(sectionId: 3, index: 5, value: .none, error: nil, identifier: InputDataIdentifier("bookmarks_remove_tag"), data: .init(name: regramString("bookmarks.removeTag"), color: theme.colors.text, type: .next, viewType: .innerItem, enabled: !state.selected.isEmpty, action: { arguments.bulkTags(true) })))
        rows.append(.general(sectionId: 3, index: 6, value: .none, error: nil, identifier: InputDataIdentifier("bookmarks_remove_selected"), data: .init(name: regramString("bookmarks.removeSelected"), color: theme.colors.redUI, type: .none, viewType: .lastItem, enabled: !state.selected.isEmpty, action: { arguments.remove(state.selected) })))
    }
    for (index, row) in state.rows.enumerated() {
        let bookmark = row.bookmark
        let id = bookmark.messageId
        let key = "\(id.peerId)_\(id.namespace)_\(id.id)"
        let section = Int32(5 + index * 2)
        let messageId = MessageId(peerId: PeerId(id.peerId), namespace: id.namespace, id: id.id)
        let canFetchFromCloud = regramBookmarkCanFetchFromCloud(messageId)
        let availability = state.availability[id] ?? (row.preview == nil ? canFetchFromCloud ? .notCached : .unavailable : .cached)
        rows.append(.sectionId(section - 1, type: .normal))
        rows.append(.general(sectionId: section, index: 0, value: .none, error: nil, identifier: InputDataIdentifier("bookmark_" + key), data: .init(name: row.title, color: theme.colors.text, type: state.selecting ? .selectable(state.selected.contains(id)) : .next, viewType: .firstItem, description: row.preview ?? regramString("bookmarks.state." + availability.key), action: {
            if state.selecting { arguments.toggle(id) } else { arguments.open(row) }
        })))
        rows.append(.general(sectionId: section, index: 1, value: .none, error: nil, identifier: InputDataIdentifier("bookmark_tags_" + key), data: .init(name: regramString("tags"), color: theme.colors.text, type: .nextContext(bookmark.tags.map { "#" + $0 }.joined(separator: " ")), viewType: .innerItem, action: { arguments.editTags(bookmark) })))
        if availability != .cached, canFetchFromCloud {
            rows.append(.general(sectionId: section, index: 2, value: .none, error: nil, identifier: InputDataIdentifier("bookmark_fetch_" + key), data: .init(name: regramString(availability == .loading ? "bookmarks.state.loading" : availability == .notCached ? "bookmarks.fetch" : "bookmarks.retry"), color: theme.colors.accent, type: availability == .loading ? .loading : .none, viewType: .innerItem, enabled: availability != .loading, description: regramString("bookmarks.state." + availability.key), action: { arguments.fetch(row) })))
        }
        rows.append(.general(sectionId: section, index: 3, value: .none, error: nil, identifier: InputDataIdentifier("bookmark_remove_" + key), data: .init(name: regramString("remove"), color: theme.colors.redUI, type: .none, viewType: .lastItem, action: { arguments.remove([id]) })))
    }
    if state.rows.isEmpty {
        rows.append(.desc(sectionId: 4, index: 0, text: .plain(regramString(state.loading ? "bookmarks.state.loading" : "emptyBookmarks")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    }
    if state.rows.count < state.total {
        let section = Int32(5 + state.rows.count * 2)
        rows.append(.sectionId(section, type: .normal))
        rows.append(.general(sectionId: section + 1, index: 0, value: .none, error: nil, identifier: InputDataIdentifier("bookmarks_more"), data: .init(name: regramString("bookmarks.loadMore"), color: theme.colors.accent, type: .none, viewType: .singleItem, action: arguments.loadMore)))
    }
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
    let changes: Signal<Void, NoError> = Signal { subscriber in
        let token = NotificationCenter.default.addObserver(forName: RGMessageBookmarks.didChange, object: nil, queue: nil) { notification in
            if notification.object as? Int64 == accountId { subscriber.putNext(()) }
        }
        subscriber.putNext(())
        return ActionDisposable { NotificationCenter.default.removeObserver(token) }
    }
    disposables.add((combineLatest(changes, request.get(), regramRemarkChanges(accountId: accountId)) |> mapToSignal { _, request, _ in
        let all = RGMessageBookmarks.shared.bookmarks(accountId: accountId)
        let filtered = all.filter { bookmark in
            guard let tag = request.tag else { return true }
            return tag.isEmpty ? bookmark.tags.isEmpty : bookmark.tags.contains { $0.compare(tag, options: [.caseInsensitive, .widthInsensitive]) == .orderedSame }
        }
        let bookmarks = Array(filtered.prefix(request.limit))
        let tags = RGMessageBookmarks.shared.tags(accountId: accountId)
        return context.account.postbox.transaction { transaction -> ([BookmarkRow], [String], Int, String?) in
            let rows = bookmarks.map { bookmark -> BookmarkRow in
                let id = MessageId(peerId: PeerId(bookmark.messageId.peerId), namespace: bookmark.messageId.namespace, id: bookmark.messageId.id)
                let message = transaction.getMessage(id)
                let peer = transaction.getPeer(id.peerId)
                let title = RGGroupRemarks.shared.name(accountId: accountId, peerId: bookmark.messageId.peerId) ?? peer?.displayTitle ?? regramString("bookmarks.unknownChat")
                let preview = message.map { $0.text.isEmpty ? regramString("bookmarks.media") : String($0.text.replacingOccurrences(of: "\n", with: " ").prefix(160)) }
                return BookmarkRow(bookmark: bookmark, title: title, preview: preview)
            }
            return (rows, tags, filtered.count, request.tag)
        }
    } |> deliverOnMainQueue).start(next: { rows, tags, total, tag in
        updateState { current in
            var current = current
            current.rows = rows
            current.tags = tags
            current.total = total
            current.tag = tag
            current.loading = false
            current.selected.formIntersection(Set(rows.map { $0.bookmark.messageId }))
            return current
        }
    }))
    let arguments = BookmarkArguments(context: context)
    let reload: () -> Void = { updateRequest { current in var current = current; current.revision &+= 1; return current } }
    enum FetchError: Error, Equatable { case inaccessible; case failed }
    let fetch: (BookmarkRow, Bool) -> Void = { row, openAfter in
        let id = row.bookmark.messageId
        guard fetches[id] == nil else { return }
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
            fetches.removeValue(forKey: id)
            guard RGMessageBookmarks.shared.bookmark(accountId: accountId, messageId: id) != nil else { return }
            if case let .result(messages) = result {
                let loaded = messages.contains { $0.id == messageId }
                updateState { current in var current = current; current.availability[id] = loaded ? .cached : canFetchFromCloud ? .failed : .unavailable; return current }
                reload()
                if loaded, openAfter { RegramUIHooks.shared.openMessage(context, messageId, row.bookmark.threadId) }
            }
        }, error: { error in
            fetches.removeValue(forKey: id)
            updateState { current in var current = current; current.availability[id] = error == .inaccessible ? .unavailable : .failed; return current }
        }))
    }
    arguments.setTag = { tag in
        updateState { current in var current = current; current.selected.removeAll(); current.loading = true; return current }
        updateRequest { current in var current = current; current.tag = tag; current.limit = 100; return current }
    }
    arguments.toggleSelecting = { updateState { current in var current = current; current.selecting.toggle(); current.selected.removeAll(); return current } }
    arguments.toggle = { id in updateState { current in var current = current; if !current.selected.insert(id).inserted { current.selected.remove(id) }; return current } }
    arguments.selectAll = { updateState { current in var current = current; current.selected = Set(current.rows.map { $0.bookmark.messageId }); return current } }
    arguments.open = { row in
        if row.preview != nil {
            let id = row.bookmark.messageId
            RegramUIHooks.shared.openMessage(context, MessageId(peerId: PeerId(id.peerId), namespace: id.namespace, id: id.id), row.bookmark.threadId)
        } else { fetch(row, true) }
    }
    arguments.fetch = { fetch($0, false) }
    arguments.editTags = { context.bindings.rootNavigation().push(RegramBookmarkTagsController(context: context, bookmark: $0)) }
    arguments.bulkTags = { removing in
        let ids = stateValue.with { $0.selected }
        context.bindings.rootNavigation().push(RegramBookmarkBulkTagsController(context: context, ids: ids, removing: removing))
    }
    arguments.remove = { ids in
        verifyAlert(for: context.window, header: regramString("bookmarks.removeSelected"), information: String(format: regramString("bookmarks.removeConfirm"), ids.count), successHandler: { _ in RGMessageBookmarks.shared.remove(accountId: accountId, messageIds: ids) })
    }
    arguments.loadMore = { updateRequest { current in var current = current; current.limit += 100; return current } }
    let signal = combineLatest(state.get(), appearanceSignal) |> deliverOnPrepareQueue |> map { state, _ in InputDataSignalValue(entries: bookmarkEntries(state, arguments: arguments)) }
    let controller = InputDataController(dataSignal: signal, title: regramString("bookmarks"), removeAfterDisappear: false, hasDone: false, identifier: "regram.bookmarks")
    controller.didAppear = { _ in reload() }
    controller.onDeinit = { disposables.dispose(); fetches.values.forEach { $0.dispose() }; fetches.removeAll() }
    return controller
}

private func RegramBookmarkTagsController(context: any AccountContextProtocol, bookmark: RGMessageBookmark) -> InputDataController {
    let id = InputDataIdentifier("regram_tags")
    let entries: [InputDataEntry] = [.sectionId(0, type: .normal), .input(sectionId: 1, index: 0, value: .string(bookmark.tags.joined(separator: ", ")), error: nil, identifier: id, mode: .plain, data: .init(viewType: .singleItem), placeholder: nil, inputPlaceholder: regramString("tags"), filter: { $0 }, limit: 512)]
    return InputDataController(dataSignal: .single(InputDataSignalValue(entries: entries)), title: regramString("tags"), validateData: { data in
        RGMessageBookmarks.shared.save(accountId: context.peerId.toInt64(), messageId: bookmark.messageId, threadId: bookmark.threadId, tags: (data[id]?.stringValue ?? "").components(separatedBy: ","))
        return .success(.navigationBack)
    }, removeAfterDisappear: false)
}

private func RegramBookmarkBulkTagsController(context: any AccountContextProtocol, ids: Set<RGBookmarkMessageId>, removing: Bool) -> InputDataController {
    let id = InputDataIdentifier("regram_bulk_tags")
    let entries: [InputDataEntry] = [.sectionId(0, type: .normal), .input(sectionId: 1, index: 0, value: .string(""), error: nil, identifier: id, mode: .plain, data: .init(viewType: .singleItem), placeholder: nil, inputPlaceholder: regramString("tags"), filter: { $0 }, limit: 512)]
    return InputDataController(dataSignal: .single(InputDataSignalValue(entries: entries)), title: regramString(removing ? "bookmarks.removeTag" : "bookmarks.addTag"), validateData: { data in
        let tags = (data[id]?.stringValue ?? "").components(separatedBy: ",")
        guard !RGMessageBookmarks.normalizedTags(tags).isEmpty else { return .fail(.fields([id: .shake])) }
        RGMessageBookmarks.shared.updateTags(accountId: context.peerId.toInt64(), messageIds: ids, adding: removing ? [] : tags, removing: removing ? tags : [])
        return .success(.navigationBack)
    }, removeAfterDisappear: false)
}
