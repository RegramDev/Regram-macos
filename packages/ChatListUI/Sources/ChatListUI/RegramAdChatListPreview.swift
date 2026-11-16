import ChatHistoryModel
import Foundation
import Postbox
import RegramCore
import SwiftSignalKit
import TelegramCore

@available(macOS 12, *)
final class RegramAdChatListPreview {
    private typealias Presentation = RegramChatListPreviewCoordinator.Presentation

    private struct Source: Equatable {
        let upperBound: MessageIndex
        let threadId: Int64?
        let payloads: [RegramMessageFilterPayload]
    }

    private final class Fallback {
        let source: Source
        let scope = RegramAdFilterSession.Scope.chatListFallback(UUID())
        var preview: [Message] = []
        var request: RGAdWorkRequest?
        var observation: Disposable?

        init(source: Source) {
            self.source = source
        }
    }

    private struct PreviewStamp {
        let messages: [RegramChatListSourceMessageKey]
        let revision: Int64
    }

    private let account: Account
    private let accountPeerId: PeerId
    private let queue: Queue
    private let session: RegramAdFilterSession
    private let topScope: RegramAdFilterWorkScope
    private let query = MetaDisposable()
    private var fallbacks: [UIChatListEntryId: Fallback] = [:]
    private var pending: [UIChatListEntryId] = []
    private var runningBatch: UUID?
    private var activeScans = Set<UIChatListEntryId>()
    private var previewStamps: [UIChatListEntryId: PreviewStamp] = [:]
    private var nextPreviewRevision: Int64 = 0
    private var preferencesRevision: Int64?
    private var preparationRevision: UInt64?
    private var refreshRevision: UInt64 = 0
    private var refreshScheduled = false
    private let refresh = ValuePromise<UInt64>(0, ignoreRepeated: true)

    var changes: Signal<Void, NoError> {
        combineLatest(session.changes, refresh.get()) |> map { _, _ in () }
    }

    init(account: Account, accountPeerId: PeerId, queue: Queue) {
        self.account = account
        self.accountPeerId = accountPeerId
        self.queue = queue
        session = RegramAdFilterSession.get(account)
        topScope = RegramAdFilterWorkScope(session: session, scope: .chatList(UUID()))
    }

    deinit {
        query.dispose()
        for fallback in fallbacks.values {
            fallback.request?.cancel()
            fallback.observation?.dispose()
            session.release(scope: fallback.scope)
        }
    }

    func update(_ presentation: RegramChatListPreviewCoordinator.Presentation) -> RegramChatListPreviewCoordinator.Presentation {
        let accountId = accountPeerId.toInt64()
        let preferencesRevision = RegramPreferences.shared.revision(accountId: accountId)
        let preparationRevision = session.preparationRevision
        if self.preferencesRevision != preferencesRevision || self.preparationRevision != preparationRevision {
            self.preferencesRevision = preferencesRevision
            self.preparationRevision = preparationRevision
            for id in Array(fallbacks.keys) { removeFallback(id) }
            pending.removeAll()
            runningBatch = nil
            query.set(nil)
        }

        let chats = presentation.entries.compactMap { entry -> (UIChatListEntryId, Int64?, [Message])? in
            guard case .chat(let item, _, let additionalItem, _, _, _, _, _, _, _, _, _) = entry, additionalItem == nil else { return nil }
            let threadId: Int64?
            if case .forum(let id) = item.id { threadId = id } else { threadId = nil }
            let messages = presentation.previews[entry.stableId] ?? item.messages.map { $0._asMessage() }
            return (entry.stableId, threadId, messages)
        }
        let groupMessages = presentation.entries.compactMap { entry -> Message? in
            guard case .group(_, let item, _, _, _, _, _) = entry else { return nil }
            return item.topMessage?._asMessage()
        }
        topScope.prepare(chats.flatMap { $0.2 } + groupMessages, accountPeerId: accountPeerId)
        var previews = presentation.previews
        var changes: [UIChatListEntryId: [Message]] = [:]
        var needed = Set<UIChatListEntryId>()
        for (id, threadId, messages) in chats where !messages.isEmpty {
            let hidden = session.hiddenMessageIds(in: messages, accountPeerId: accountPeerId, scope: topScope.scope)
            let visible = messages.filter { !hidden.contains($0.id) }
            if !visible.isEmpty {
                let displayed = visible.map {
                    session.display($0, accountPeerId: accountPeerId, scope: topScope.scope, includeReply: false)
                }
                if !hidden.isEmpty || zip(displayed, visible).contains(where: { $0.0 !== $0.1 }) { changes[id] = displayed }
                continue
            }
            guard let upperBound = regramChatListPreviewUpperBound(messages) else { continue }
            let source = Source(upperBound: upperBound, threadId: threadId, payloads: messages.map(RegramMessageFilterPayload.init))
            needed.insert(id)
            if fallbacks[id]?.source != source {
                removeFallback(id)
                fallbacks[id] = Fallback(source: source)
                pending.append(id)
            }
            changes[id] = fallbacks[id]?.preview ?? []
        }
        for id in Array(fallbacks.keys) where !needed.contains(id) { removeFallback(id) }
        pending.removeAll { !needed.contains($0) }
        loadNextBatch()
        var stamps: [UIChatListEntryId: PreviewStamp] = [:]
        for (id, messages) in changes {
            previews[id] = messages
            let keys = regramChatListSourceKeys(messages)
            if let previous = previewStamps[id], previous.messages == keys {
                stamps[id] = previous
            } else {
                nextPreviewRevision &+= 1
                stamps[id] = PreviewStamp(messages: keys, revision: nextPreviewRevision)
            }
        }
        previewStamps = stamps
        let entries = presentation.entries.map { entry -> UIChatListEntry in
            if let stamp = stamps[entry.stableId],
                case .chat(
                    let item, let activities, let addition, let filter, let hidden, let forum, let appear, let hideContent, let folders,
                    let categories, let canPreview, let revision) = entry
            {
                return .chat(
                    item, activities, addition, filter: filter, generalStatus: hidden, selectedForum: forum, appearMode: appear,
                    hideContent: hideContent, folders: folders, communityCategories: categories, canPreviewChat: canPreview,
                    regramRevision: revision &+ (stamp.revision << 32))
            }
            if case .group(let index, let item, let animated, let hidden, let appear, let hideContent, let stories) = entry,
                let message = item.topMessage?._asMessage()
            {
                let display =
                    session.shouldHide(message, accountPeerId: accountPeerId, scope: topScope.scope)
                    ? nil : session.display(message, accountPeerId: accountPeerId, scope: topScope.scope, includeReply: false)
                if display !== message {
                    let group = EngineChatList.GroupItem(
                        id: item.id, topMessage: display.map(EngineMessage.init), items: item.items, unreadCount: item.unreadCount)
                    return .group(index, group, animated, hidden, appear, hideContent, stories)
                }
            }
            return entry
        }
        return Presentation(entries: entries, previews: previews)
    }

    private func removeFallback(_ id: UIChatListEntryId) {
        guard let fallback = fallbacks.removeValue(forKey: id) else { return }
        fallback.request?.cancel()
        fallback.observation?.dispose()
        session.release(scope: fallback.scope)
        activeScans.remove(id)
        pending.removeAll { $0 == id }
    }

    private func loadNextBatch() {
        guard runningBatch == nil, activeScans.isEmpty, !pending.isEmpty else { return }
        let requests = pending.prefix(16).compactMap { id in fallbacks[id].map { (id, $0) } }
        pending.removeFirst(min(16, pending.count))
        guard !requests.isEmpty else { return }
        let batch = UUID()
        runningBatch = batch
        let sources = requests.map { ($0.0, $0.1.source) }
        query.set(
            (account.postbox.transaction { transaction in
                sources.map { id, source -> (UIChatListEntryId, [[Message]]) in
                    let peerId = source.upperBound.id.peerId
                    let namespace = Namespaces.Message.Cloud
                    let lower = MessageIndex.lowerBound(peerId: peerId, namespace: namespace)
                    let before = source.upperBound
                    let recent: [Message]
                    if let threadId = source.threadId {
                        recent = transaction.getMessagesWithThreadId(
                            peerId: peerId, namespace: namespace, threadId: threadId, from: before, includeFrom: false, to: lower, limit: 50
                        )
                    } else {
                        recent = transaction.getMessages(
                            peerId: peerId, namespace: namespace, from: before, includeFrom: false, to: lower, limit: 50)
                    }
                    var seen = Set<MessageId>()
                    let groups = recent.sorted { $0.index > $1.index }.compactMap { message -> [Message]? in
                        guard seen.insert(message.id).inserted else { return nil }
                        let group = transaction.getMessageGroup(message.id) ?? [message]
                        guard !group.isEmpty,
                            group.allSatisfy({ $0.index < before && (source.threadId == nil || $0.threadId == source.threadId) })
                        else { return nil }
                        seen.formUnion(group.map(\.id))
                        return group.sorted { $0.index < $1.index }
                    }
                    return (id, groups)
                }
            } |> deliverOn(queue)).start(next: { [weak self] rows in
                guard let self, self.runningBatch == batch else { return }
                self.runningBatch = nil
                let current = zip(requests, rows).filter { self.fallbacks[$0.0.0] === $0.0.1 && !$0.1.1.isEmpty }
                self.activeScans = Set(current.map { $0.0.0 })
                for ((id, fallback), (_, groups)) in current {
                    self.scan(groups[...], id: id, fallback: fallback)
                }
                self.loadNextBatch()
            }))
    }

    private func scan(_ groups: ArraySlice<[Message]>, id: UIChatListEntryId, fallback: Fallback) {
        let accountId = accountPeerId.toInt64()
        let captured = RegramPreferences.shared.captureFilter(accountId: accountId)
        guard
            let index = groups.firstIndex(where: { group in
                group.contains {
                    !regramChatListMessageIsHidden($0, accountId: accountId, filter: captured.filter, revision: captured.revision)
                }
            })
        else {
            finishScan(id)
            return
        }
        let group = groups[index]
        fallback.request = session.prepare(group, accountPeerId: accountPeerId, scope: fallback.scope) { [weak self, weak fallback] in
            self?.queue.async { [weak self, weak fallback] in
                guard let self, let fallback, self.fallbacks[id] === fallback else { return }
                let peer = self.accountPeerId
                let hidden = self.session.hiddenMessageIds(in: group, accountPeerId: peer, scope: fallback.scope)
                let visible = group.filter {
                    !hidden.contains($0.id)
                        && !regramChatListMessageIsHidden($0, accountId: accountId, filter: captured.filter, revision: captured.revision)
                }
                if visible.isEmpty {
                    self.scan(groups[groups.index(after: index)...], id: id, fallback: fallback)
                    return
                }
                if visible.allSatisfy({ self.session.isPrepared($0, accountPeerId: peer, scope: fallback.scope) }) {
                    fallback.preview = visible.map {
                        self.session.display($0, accountPeerId: peer, scope: fallback.scope, includeReply: false)
                    }
                    self.observe(group, id: id, fallback: fallback)
                    self.emitChange()
                }
                self.finishScan(id)
            }
        }
    }

    private func observe(_ group: [Message], id: UIChatListEntryId, fallback: Fallback) {
        let subscriptions = DisposableSet()
        for message in group {
            subscriptions.add(
                (account.postbox.messageView(message.id) |> deliverOn(queue)).start(next: { [weak self, weak fallback] view in
                    guard let self, let fallback, self.fallbacks[id] === fallback else { return }
                    if let current = view.message, RegramMessageFilterPayload(current) == RegramMessageFilterPayload(message),
                        rgAdInput(current) == rgAdInput(message), current.media.elementsEqual(message.media, by: { $0.isEqual(to: $1) })
                    {
                        return
                    }
                    self.removeFallback(id)
                    self.emitChange()
                }))
        }
        fallback.observation = subscriptions
    }

    private func finishScan(_ id: UIChatListEntryId) {
        activeScans.remove(id)
        loadNextBatch()
    }

    private func emitChange() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        queue.after(0.02) { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.refreshRevision &+= 1
            self.refresh.set(self.refreshRevision)
        }
    }
}
