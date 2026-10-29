import Postbox
import TelegramCore
import ChatHistoryModel
import TelegramTheme
import RegramCore
import SwiftSignalKit

final class RegramChatListPreviewCoordinator {
    private typealias CacheId = RegramChatListPeerKey
    struct Presentation {
        let entries: [UIChatListEntry]
        let previews: [UIChatListEntryId: [Message]]
    }

    private struct SourceKey: Equatable {
        let accountId: Int64
        let messageId: MessageId
        let stableVersion: UInt32
        let filterRevision: Int64
        let preferencesRevision: Int64
        let threadId: Int64?
        let suppliedMessages: [RegramChatListSourceMessageKey]
        let payloads: [RegramMessageFilterPayload]
        let readEligible: Bool
    }

    private struct Stream {
        var cursor: MessageIndex
        var candidate: Message?
        var exhausted = false
    }

    private struct State {
        let key: SourceKey
        let upperBound: MessageIndex
        let filter: RegramFilterSnapshot
        var streams: [MessageId.Namespace: Stream]
        var messages: [Message]
        var previewPayloads: [RegramMessageFilterPayload]
        var completed: Bool
        var usesSuppliedMessages: Bool
    }

    private struct Request {
        let id: CacheId
        let key: SourceKey
        let upperBound: MessageIndex
        let streams: [MessageId.Namespace: Stream]
        let filter: RegramFilterSnapshot
    }

    private struct UnreadRequest: Equatable {
        let id: UIChatListEntryId
        let source: SourceKey
        let snapshot: RegramChatListUnreadSnapshot
    }

    private struct Result {
        let request: Request
        let pages: [MessageId.Namespace: [Message]]
    }

    private struct UnreadAttempt {
        let source: SourceKey
        let snapshot: RegramChatListUnreadSnapshot
        let evidenceRevision: UInt64
    }

    private struct UnreadObservation {
        let disposable: MetaDisposable
        let token: UInt64
        let associatedPeerId: PeerId?
        let source: SourceKey
    }

    private let account: Account
    private let postbox: Postbox
    private let accountId: Int64
    private let queue: Queue
    private let scanDisposable = MetaDisposable()
    private let disposed = Atomic(value: false)
    private var generation: UInt64 = 0
    private var filterRevision: Int64?
    private var states: [CacheId: State] = [:]
    private var pending: [CacheId] = []
    private var inFlight: [CacheId: SourceKey] = [:]
    private var candidateDisposables: [CacheId: MetaDisposable] = [:]
    private var candidateTokens: [CacheId: UInt64] = [:]
    private var sourceDisposables: [CacheId: MetaDisposable] = [:]
    private var sourceTokens: [CacheId: UInt64] = [:]
    private var nextCandidateToken: UInt64 = 0
    private var remoteQueue: [Request] = []
    private var remoteDisposables: [CacheId: MetaDisposable] = [:]
    private var remoteCompletedKeys: [CacheId: SourceKey] = [:]
    private let unreadLease = Atomic<[UIChatListEntryId: UnreadRequest]?>(value: [:])
    private var pendingUnread: [UnreadRequest] = []
    private var unreadQueueGeneration: UInt64 = 0
    private var unreadStartedInBatch = 0
    private var unreadContinuationScheduled = false
    private var unreadDisposables: [UIChatListEntryId: (UnreadRequest, MetaDisposable)] = [:]
    private var lastVisibleTopMessages: [CacheId: Message] = [:]
    private let previewLease = Atomic<[CacheId: SourceKey]?>(value: [:])
    private var activePreviewKeys = Set<CacheId>()
    private var inactivePreviewLRU: [CacheId] = []
    private var unreadAttempts: [CacheId: UnreadAttempt] = [:]
    private var unreadEvidenceRevisions: [CacheId: UInt64] = [:]
    private var unreadObservations: [CacheId: UnreadObservation] = [:]
    private var currentUnreadRequests: [CacheId: UnreadRequest] = [:]
    private var nextUnreadObservationToken: UInt64 = 0
    private var running = false
    private var revision: Int64 = 0
    let changes = ValuePromise<Int64>(0, ignoreRepeated: true)

    init(account: Account, accountId: Int64, queue: Queue = prepareQueue) {
        self.account = account
        self.postbox = account.postbox
        self.accountId = accountId
        self.queue = queue
    }

    private func streams(key: SourceKey, upperBound: MessageIndex) -> [MessageId.Namespace: Stream] {
        let namespaces: [MessageId.Namespace]
        if key.messageId.peerId.namespace == Namespaces.Peer.SecretChat {
            namespaces = [Namespaces.Message.Local, Namespaces.Message.SecretIncoming]
        } else {
            namespaces = [Namespaces.Message.Cloud, Namespaces.Message.Local, Namespaces.Message.EphemeralLocal]
        }
        return Dictionary(uniqueKeysWithValues: namespaces.map { namespace in
            let cursor = namespace == upperBound.id.namespace ? upperBound : MessageIndex.upperBound(peerId: key.messageId.peerId, timestamp: upperBound.timestamp, namespace: namespace)
            return (namespace, Stream(cursor: cursor))
        })
    }

    func update(_ entries: [UIChatListEntry], filterRevision: Int64, pagingFloor: MessageIndex?) -> Presentation {
        guard !disposed.with({ $0 }) else { return Presentation(entries: entries, previews: [:]) }
        let captured = RegramPreferences.shared.captureFilter(accountId: accountId)
        let preferencesRevision = captured.revision
        let filter = captured.filter
        let reset = self.filterRevision != filterRevision || states.values.contains { $0.key.preferencesRevision != preferencesRevision }
        self.filterRevision = filterRevision
        if reset {
            generation &+= 1
            scanDisposable.set(nil)
            running = false
            inFlight.removeAll()
            lastVisibleTopMessages.removeAll()
        }
        if filter.isEmpty {
            clearPreviewWork()
            replaceUnreadRequests([])
            return Presentation(entries: entries, previews: [:])
        }
        var nextStates: [CacheId: State] = reset ? [:] : states
        var order: [CacheId] = []
        var activeEntries: [UIChatListEntryId: CacheId] = [:]
        var unreadOrder: [UIChatListEntryId] = []
        var sourcesToObserve: [(CacheId, State, [Message])] = []
        var candidatesToObserve: [(CacheId, State, Message)] = []
        var unreadRequests: [UIChatListEntryId: UnreadRequest] = [:]
        var allHiddenIds = Set<UIChatListEntryId>()
        var changed = reset
        for entry in entries {
            guard case let .chat(item, _, additionalItem, _, _, _, _, _, _, _, _, _) = entry, additionalItem == nil else { continue }
            let messages = item.messages.map { $0._asMessage() }
            guard let newest = regramChatListSourceTop(messages),
                  !RegramTemporaryReveal.shared.isRevealed(accountId: accountId, peerId: newest.id.peerId.toInt64()) else { continue }
            let threadId: Int64?
            if case let .forum(id) = item.id { threadId = id } else { threadId = nil }
            let cacheId = CacheId(accountId: accountId, peerId: newest.id.peerId, threadId: threadId)
            let visible = messages.filter { !regramShouldHideMessage($0, accountId: accountId, filter: filter, revision: preferencesRevision) }
            if case .chatList = item.id, let visibleTop = visible.max(by: { $0.index < $1.index }) {
                lastVisibleTopMessages[cacheId] = visibleTop
            }
            if visible.count == messages.count {
                if nextStates.removeValue(forKey: cacheId) != nil { changed = true }
                continue
            }
            activeEntries[entry.stableId] = cacheId
            let readEligible = item.renderedPeer.peer.map { value -> Bool in
                let peer = value._asPeer()
                guard !peer.isForumOrMonoForum else { return false }
                if let channel = peer as? TelegramChannel { return channel.participationStatus == .member }
                return true
            } ?? false
            let key = SourceKey(accountId: accountId, messageId: newest.id, stableVersion: newest.stableVersion, filterRevision: filterRevision, preferencesRevision: preferencesRevision, threadId: threadId, suppliedMessages: regramChatListSourceKeys(messages), payloads: messages.sorted { $0.id < $1.id }.map(RegramMessageFilterPayload.init), readEligible: readEligible)
            if visible.isEmpty {
                allHiddenIds.insert(entry.stableId)
                if case let .chatList(peerId) = item.id, peerId == newest.id.peerId,
                   newest.id.namespace == Namespaces.Message.Cloud,
                   let readState = item.readCounters?._asReadCounters(), readState.count > 0, readState.count <= 50, !readState.markedUnread,
                   readState.states.allSatisfy({ $0.0 == Namespaces.Message.Cloud || $0.1.count == 0 && !$0.1.markedUnread }),
                   item.threadData == nil, !item.displayAsTopicList,
                   readEligible {
                    unreadOrder.append(entry.stableId)
                    unreadRequests[entry.stableId] = UnreadRequest(id: entry.stableId, source: key, snapshot: RegramChatListUnreadSnapshot(sourceTop: newest.index, sourceMessages: key.suppliedMessages, readState: readState))
                }
            }
            if var state = states[cacheId], state.key == key {
                let payloads = state.messages.map(RegramMessageFilterPayload.init)
                if !state.usesSuppliedMessages, payloads != state.previewPayloads {
                    state.messages = state.messages.filter { !regramShouldHideMessage($0, accountId: accountId, filter: filter, revision: preferencesRevision) }
                    state.previewPayloads = state.messages.map(RegramMessageFilterPayload.init)
                    if state.messages.isEmpty {
                        state.completed = false
                        state.streams = streams(key: key, upperBound: state.upperBound)
                        candidateTokens.removeValue(forKey: cacheId)
                        candidateDisposables.removeValue(forKey: cacheId)?.dispose()
                    }
                    changed = true
                }
                nextStates[cacheId] = state
            } else {
                let upperBound = regramChatListPreviewUpperBound(messages) ?? newest.index
                let provisional = lastVisibleTopMessages[cacheId].flatMap { message -> Message? in
                    guard visible.isEmpty, message.id.peerId == newest.id.peerId, message.index < upperBound,
                          !regramShouldHideMessage(message, accountId: accountId, filter: filter, revision: preferencesRevision) else { return nil }
                    return message
                }
                let previewMessages = provisional.map { [$0] } ?? visible
                let state = State(key: key, upperBound: upperBound, filter: filter, streams: streams(key: key, upperBound: upperBound), messages: previewMessages, previewPayloads: previewMessages.map(RegramMessageFilterPayload.init), completed: !visible.isEmpty, usesSuppliedMessages: !visible.isEmpty)
                nextStates[cacheId] = state
                sourcesToObserve.append((cacheId, state, messages))
                if let provisional { candidatesToObserve.append((cacheId, state, provisional)) }
                changed = true
            }
            order.append(cacheId)
        }
        let activeKeys = Set(order)
        inactivePreviewLRU.removeAll { activeKeys.contains($0) || nextStates[$0] == nil }
        for id in activePreviewKeys where !activeKeys.contains(id) && nextStates[id] != nil && !inactivePreviewLRU.contains(id) { inactivePreviewLRU.append(id) }
        if reset { inactivePreviewLRU.removeAll() }
        while inactivePreviewLRU.count > 128 {
            nextStates.removeValue(forKey: inactivePreviewLRU.removeFirst())
            changed = true
        }
        if activePreviewKeys != activeKeys { changed = true }
        activePreviewKeys = activeKeys
        _ = previewLease.modify { $0 == nil ? nil : Dictionary(uniqueKeysWithValues: order.compactMap { id in nextStates[id].map { (id, $0.key) } }) }
        for id in remoteDisposables.keys.filter({ !activeKeys.contains($0) }) { remoteDisposables.removeValue(forKey: id)?.dispose() }
        if nextStates.count != states.count { changed = true }
        if changed {
            for id in remoteDisposables.keys.filter({ nextStates[$0]?.key != states[$0]?.key }) {
                remoteDisposables.removeValue(forKey: id)?.dispose()
            }
            remoteCompletedKeys = remoteCompletedKeys.filter { nextStates[$0.key]?.key == $0.value }
            remoteQueue.removeAll { nextStates[$0.id]?.key != $0.key }
            let staleObservers = candidateDisposables.keys.filter { nextStates[$0]?.key != states[$0]?.key }
            for id in staleObservers {
                candidateTokens.removeValue(forKey: id)
                candidateDisposables.removeValue(forKey: id)?.dispose()
            }
            for id in sourceDisposables.keys.filter({ nextStates[$0]?.key != states[$0]?.key }) {
                sourceTokens.removeValue(forKey: id)
                sourceDisposables.removeValue(forKey: id)?.dispose()
            }
            states = nextStates
            let previousPending = pending.filter { activePreviewKeys.contains($0) && states[$0]?.completed == false && inFlight[$0] != states[$0]?.key }
            var seen = Set(previousPending)
            pending = previousPending + order.filter { states[$0]?.completed == false && inFlight[$0] != states[$0]?.key && seen.insert($0).inserted }
        }
        if lastVisibleTopMessages.count > 1024 {
            lastVisibleTopMessages = lastVisibleTopMessages.filter { activeKeys.contains($0.key) || nextStates[$0.key] != nil }
        }
        replaceUnreadRequests(unreadOrder.compactMap { unreadRequests[$0] })
        for (id, state, messages) in sourcesToObserve { observeSuppliedMessages(id: id, state: state, messages: messages) }
        for (id, state, candidate) in candidatesToObserve { observeCandidate(id: id, state: state, candidate: candidate) }
        if !running { loadNext() }
        for id in order {
            guard let state = states[id], state.completed, state.messages.isEmpty, !state.usesSuppliedMessages,
                  state.key.messageId.namespace == Namespaces.Message.Cloud,
                  remoteCompletedKeys[id] != state.key, remoteDisposables[id] == nil,
                  !remoteQueue.contains(where: { $0.id == id }) else { continue }
            remoteQueue.append(Request(id: id, key: state.key, upperBound: state.upperBound, streams: state.streams, filter: state.filter))
        }
        loadNextRemote()
        loadNextUnread()
        guard RegramPreferences.shared.revision(accountId: accountId) == preferencesRevision else { return Presentation(entries: entries, previews: [:]) }
        let presentedEntries = entries.map { entry -> UIChatListEntry in
            guard allHiddenIds.contains(entry.stableId), let cacheId = activeEntries[entry.stableId], let state = states[cacheId], !state.usesSuppliedMessages,
                  let replacement = state.messages.max(by: { $0.index < $1.index }), replacement.index < state.upperBound,
                  replacement.id.peerId == state.key.messageId.peerId,
                  !regramShouldHideMessage(replacement, accountId: accountId, filter: filter, revision: preferencesRevision),
                  !RegramTemporaryReveal.shared.isRevealed(accountId: accountId, peerId: replacement.id.peerId.toInt64()),
                  case let .chat(item, activities, additionalItem, filter, status, forum, appearance, hideContent, folders, categories, canPreview, revision) = entry,
                  additionalItem == nil, case .chatList = item.id, case let .chatList(nativeIndex) = item.index,
                  let sourceTop = regramChatListSourceTop(item.messages.map({ $0._asMessage() })) else { return entry }
            let displayIndex = regramChatListDisplayIndex(native: nativeIndex, sourceTop: sourceTop.index, replacement: replacement.index, pagingFloor: pagingFloor)
            guard displayIndex != nativeIndex else { return entry }
            return .chat(regramChatListItemWithDisplayIndex(item, displayIndex), activities, additionalItem, filter: filter, generalStatus: status, selectedForum: forum, appearMode: appearance, hideContent: hideContent, folders: folders, communityCategories: categories, canPreviewChat: canPreview, regramRevision: revision)
        }
        return Presentation(entries: presentedEntries, previews: Dictionary(uniqueKeysWithValues: activeEntries.compactMap { id, key in states[key].map { (id, $0.messages) } }))
    }

    private func unreadKey(_ request: UnreadRequest) -> CacheId {
        CacheId(accountId: request.source.accountId, peerId: request.snapshot.sourceTop.id.peerId, threadId: nil)
    }

    private func unreadWasAttempted(_ request: UnreadRequest) -> Bool {
        let key = unreadKey(request)
        guard let attempt = unreadAttempts[key] else { return false }
        return attempt.source == request.source && attempt.snapshot == request.snapshot && attempt.evidenceRevision == (unreadEvidenceRevisions[key] ?? 0)
    }

    private func replaceUnreadRequests(_ requests: [UnreadRequest]) {
        let currentRequests = Dictionary(requests.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        _ = unreadLease.modify { $0 == nil ? nil : currentRequests }
        currentUnreadRequests = Dictionary(requests.map { (unreadKey($0), $0) }, uniquingKeysWith: { _, last in last })
        for key in unreadObservations.keys.filter({ currentUnreadRequests[$0]?.source != unreadObservations[$0]?.source }) {
            unreadObservations.removeValue(forKey: key)?.disposable.dispose()
        }
        unreadAttempts = unreadAttempts.filter { currentUnreadRequests[$0.key] != nil }
        unreadEvidenceRevisions = unreadEvidenceRevisions.filter { currentUnreadRequests[$0.key] != nil }
        for id in unreadDisposables.keys.filter({ currentRequests[$0] != unreadDisposables[$0]?.0 }) {
            guard let cancelled = unreadDisposables.removeValue(forKey: id) else { continue }
            let key = unreadKey(cancelled.0)
            if unreadAttempts[key]?.source == cancelled.0.source, unreadAttempts[key]?.snapshot == cancelled.0.snapshot {
                unreadAttempts.removeValue(forKey: key)
            }
            cancelled.1.dispose()
        }
        unreadQueueGeneration &+= 1
        unreadStartedInBatch = 0
        unreadContinuationScheduled = false
        pendingUnread = requests.filter { unreadDisposables[$0.id] == nil && !unreadWasAttempted($0) }
    }

    private func invalidateUnreadEvidence(_ key: CacheId) {
        guard !disposed.with({ $0 }), let request = currentUnreadRequests[key] else { return }
        unreadEvidenceRevisions[key, default: 0] &+= 1
        unreadAttempts.removeValue(forKey: key)
        if !pendingUnread.contains(request) { pendingUnread.append(request) }
        loadNextUnread()
    }

    private func observeUnreadEvidence(_ request: UnreadRequest, associatedPeerId: PeerId?) {
        let key = unreadKey(request)
        guard currentUnreadRequests[key]?.source == request.source else { return }
        if let existing = unreadObservations[key], existing.source == request.source, existing.associatedPeerId == associatedPeerId { return }
        unreadObservations.removeValue(forKey: key)?.disposable.dispose()
        let disposable = MetaDisposable()
        nextUnreadObservationToken &+= 1
        let token = nextUnreadObservationToken
        unreadObservations[key] = UnreadObservation(disposable: disposable, token: token, associatedPeerId: associatedPeerId, source: request.source)
        let historyKey = PostboxViewKey.historyView(.init(peerId: key.peerId, threadId: nil, clipHoles: false, trackHoles: false, anchor: .upperBound, appendMessagesFromTheSameGroup: false, namespaces: .just([Namespaces.Message.Cloud]), count: 50))
        let cachedKey = PostboxViewKey.cachedPeerData(peerId: key.peerId)
        var keys: [PostboxViewKey] = [historyKey, cachedKey, .combinedReadState(peerId: key.peerId, handleThreads: false), .basicPeer(key.peerId)]
        if let associatedPeerId, associatedPeerId != key.peerId { keys.append(.combinedReadState(peerId: associatedPeerId, handleThreads: false)) }
        disposable.set((postbox.combinedView(keys: keys) |> deliverOn(self.queue)).start(next: { [weak self] view in
            guard let self, !self.disposed.with({ $0 }), self.unreadObservations[key]?.token == token,
                  let current = self.currentUnreadRequests[key], current.source == request.source else { return }
            let currentAssociated = (view.views[cachedKey] as? CachedPeerDataView)?.cachedPeerData?.associatedHistoryMessageId?.peerId
            self.invalidateUnreadEvidence(key)
            if currentAssociated != associatedPeerId { self.observeUnreadEvidence(current, associatedPeerId: currentAssociated) }
        }))
    }

    private func loadNextUnread() {
        guard !disposed.with({ $0 }) else { return }
        while unreadDisposables.count < 2, !pendingUnread.isEmpty {
            if unreadStartedInBatch == 16 {
                if !unreadContinuationScheduled {
                    unreadContinuationScheduled = true
                    let generation = unreadQueueGeneration
                    self.queue.justDispatch { [weak self] in
                        guard let self, !self.disposed.with({ $0 }), self.unreadQueueGeneration == generation else { return }
                        self.unreadContinuationScheduled = false
                        self.unreadStartedInBatch = 0
                        self.loadNextUnread()
                    }
                }
                return
            }
            let request = pendingUnread.removeFirst()
            guard unreadLease.with({ $0?[request.id] == request }), !unreadWasAttempted(request) else { continue }
            let captured = RegramPreferences.shared.captureFilter(accountId: accountId)
            guard captured.revision == request.source.preferencesRevision else { continue }
            if unreadDisposables[request.id] != nil {
                pendingUnread.append(request)
                return
            }
            let evidenceKey = unreadKey(request)
            unreadAttempts[evidenceKey] = UnreadAttempt(source: request.source, snapshot: request.snapshot, evidenceRevision: unreadEvidenceRevisions[evidenceKey] ?? 0)
            unreadStartedInBatch += 1
            let disposable = MetaDisposable()
            unreadDisposables[request.id] = (request, disposable)
            let lease = unreadLease
            let filter = captured.filter
            let retryable = Atomic(value: false)
            let associatedPeer = Atomic<PeerId?>(value: nil)
            let result = (postbox.transaction { transaction -> [Message]? in
                guard lease.with({ $0?[request.id] == request }) else { return nil }
                guard let messages = regramChatListUnreadMessages(transaction: transaction, snapshot: request.snapshot) else { return nil }
                _ = associatedPeer.swap(transaction.getPeerCachedData(peerId: request.snapshot.sourceTop.id.peerId)?.associatedHistoryMessageId?.peerId)
                return messages
            } |> deliverOn(self.queue) |> mapToSignal { messages -> Signal<Bool, NoError> in
                guard lease.with({ $0?[request.id] == request }), let messages else { return .single(false) }
                _ = retryable.swap(true)
                let visibility = RegramChatListPreparedVisibility(messages: messages, accountId: request.source.accountId, filter: filter, revision: request.source.preferencesRevision)
                return regramApplyMaxReadIndexInteractively(account: self.account, index: request.snapshot.sourceTop, when: { transaction, apply in
                    guard lease.with({ $0?[request.id] == request }),
                          regramChatListCanReadHiddenUnread(transaction: transaction, snapshot: request.snapshot, isHidden: visibility.isHidden) else { return }
                    lease.with { current in
                        guard current?[request.id] == request else { return }
                        _ = RegramPreferences.shared.withCurrentRevision(accountId: request.source.accountId, revision: request.source.preferencesRevision) {
                            _ = RegramTemporaryReveal.shared.withUnrevealed(accountId: request.source.accountId, peerId: request.snapshot.sourceTop.id.peerId.toInt64()) { apply() }
                        }
                    }
                })
            }) |> deliverOn(self.queue)
            disposable.set(result.start(next: { [weak self] applied in
                guard let self, !self.disposed.with({ $0 }), self.unreadDisposables[request.id]?.0 == request else { return }
                if !applied, retryable.with({ $0 }) {
                    self.observeUnreadEvidence(request, associatedPeerId: associatedPeer.with { $0 })
                }
            }, completed: { [weak self] in
                guard let self, self.unreadDisposables[request.id]?.0 == request else { return }
                self.unreadDisposables.removeValue(forKey: request.id)?.1.dispose()
                self.loadNextUnread()
            }))
        }
    }

    func refreshExhaustedEmpty() {
        self.queue.async { [weak self] in
            guard let self, !self.disposed.with({ $0 }) else { return }
            let ids = self.states.compactMap { id, state in self.activePreviewKeys.contains(id) && state.completed && state.messages.isEmpty ? id : nil }
            for id in ids {
                guard var state = self.states[id] else { continue }
                state.completed = false
                state.streams = self.streams(key: state.key, upperBound: state.upperBound)
                self.states[id] = state
                self.remoteCompletedKeys.removeValue(forKey: id)
                if self.activePreviewKeys.contains(id), !self.pending.contains(id) { self.pending.append(id) }
            }
            if !self.running { self.loadNext() }
        }
    }

    private func loadNext() {
        guard !disposed.with({ $0 }), !running, !pending.isEmpty else { return }
        let ids = Array(pending.prefix(8))
        pending.removeFirst(ids.count)
        let requests = ids.compactMap { id -> Request? in
            guard activePreviewKeys.contains(id), let state = states[id], !state.completed else { return nil }
            return Request(id: id, key: state.key, upperBound: state.upperBound, streams: state.streams, filter: state.filter)
        }
        guard !requests.isEmpty else { loadNext(); return }
        running = true
        inFlight = Dictionary(uniqueKeysWithValues: requests.map { ($0.id, $0.key) })
        let generation = self.generation
        let lease = previewLease
        scanDisposable.set((postbox.transaction { transaction -> [Result] in
            requests.compactMap { request in
                guard lease.with({ $0?[request.id] == request.key }) else { return nil }
                let peerId = request.key.messageId.peerId
                var pages: [MessageId.Namespace: [Message]] = [:]
                for (namespace, stream) in request.streams where !stream.exhausted && stream.candidate == nil {
                    let lower = MessageIndex.lowerBound(peerId: peerId, namespace: namespace)
                    if let threadId = request.key.threadId {
                        pages[namespace] = transaction.getMessagesWithThreadId(peerId: peerId, namespace: namespace, threadId: threadId, from: stream.cursor, includeFrom: false, to: lower, limit: 32)
                    } else {
                        pages[namespace] = transaction.getMessages(peerId: peerId, namespace: namespace, from: stream.cursor, includeFrom: false, to: lower, limit: 32)
                    }
                }
                return Result(request: request, pages: pages)
            }
        } |> deliverOn(self.queue)).start(next: { [weak self] results in
            guard let self, !self.disposed.with({ $0 }), self.generation == generation else { return }
            self.running = false
            self.inFlight.removeAll()
            var changed = false
            var found: [(CacheId, State, Message)] = []
            for result in results {
                guard var state = self.states[result.request.id], state.key == result.request.key, !state.completed else { continue }
                for (namespace, messages) in result.pages {
                    guard let stream = result.request.streams[namespace] else { continue }
                    let ordered = messages.sorted { $0.index > $1.index }
                    let candidate = ordered.first { $0.index < result.request.upperBound && !regramShouldHideMessage($0, accountId: self.accountId, filter: result.request.filter, revision: result.request.key.preferencesRevision) }
                    let nextCursor = ordered.last?.index
                    state.streams[namespace] = Stream(cursor: nextCursor ?? stream.cursor, candidate: candidate, exhausted: messages.count < 32 || nextCursor == nil || nextCursor! >= stream.cursor)
                }
                if let candidate = state.streams.values.compactMap(\.candidate).max(by: { $0.index < $1.index }),
                   !state.streams.values.contains(where: { !$0.exhausted && $0.candidate == nil && $0.cursor > candidate.index }) {
                    state.messages = [candidate]
                    state.previewPayloads = [RegramMessageFilterPayload(candidate)]
                    state.completed = true
                    found.append((result.request.id, state, candidate))
                    changed = true
                } else if state.streams.values.allSatisfy({ $0.exhausted && $0.candidate == nil }) {
                    state.completed = true
                    changed = true
                    if state.key.messageId.namespace == Namespaces.Message.Cloud,
                       self.remoteCompletedKeys[result.request.id] != state.key,
                       self.remoteDisposables[result.request.id] == nil,
                       !self.remoteQueue.contains(where: { $0.id == result.request.id }) {
                        self.remoteQueue.append(result.request)
                    }
                } else if self.activePreviewKeys.contains(result.request.id), !self.pending.contains(result.request.id) {
                    self.pending.append(result.request.id)
                }
                self.states[result.request.id] = state
            }
            for request in requests {
                guard !self.disposed.with({ $0 }), self.activePreviewKeys.contains(request.id),
                      let state = self.states[request.id], state.key == request.key, !state.completed,
                      self.inFlight[request.id] == nil, !self.pending.contains(request.id) else { continue }
                self.pending.append(request.id)
            }
            for (id, state, candidate) in found { self.observeCandidate(id: id, state: state, candidate: candidate) }
            if changed, results.contains(where: { self.activePreviewKeys.contains($0.request.id) }) { self.emitChange() }
            self.loadNextRemote()
            self.queue.after(0.005) { [weak self] in
                guard let self, self.generation == generation else { return }
                self.loadNext()
            }
        }))
    }

    private func loadNextRemote() {
        guard !disposed.with({ $0 }) else { return }
        while remoteDisposables.count < 2, !remoteQueue.isEmpty {
            let request = remoteQueue.removeFirst()
            guard activePreviewKeys.contains(request.id), states[request.id]?.key == request.key else { continue }
            let disposable = MetaDisposable()
            remoteDisposables[request.id] = disposable
            loadRemotePage(request, offsetId: request.upperBound.id.id, number: 0, disposable: disposable)
        }
    }

    private func finishRemote(_ request: Request, candidate: Message?) {
        guard var current = states[request.id], current.key == request.key else { return }
        if let candidate {
            current.messages = [candidate]
            current.previewPayloads = [RegramMessageFilterPayload(candidate)]
            current.usesSuppliedMessages = false
        }
        current.completed = true
        states[request.id] = current
        if let candidate { observeCandidate(id: request.id, state: current, candidate: candidate) }
        remoteCompletedKeys[request.id] = request.key
        remoteDisposables.removeValue(forKey: request.id)?.dispose()
        emitChange(for: request.id)
        loadNextRemote()
    }

    private func isCurrentRemoteRequest(_ request: Request, disposable: MetaDisposable) -> Bool {
        return !disposed.with({ $0 }) && activePreviewKeys.contains(request.id) && states[request.id]?.key == request.key && remoteDisposables[request.id] === disposable
    }

    private func loadRemotePage(_ request: Request, offsetId: Int32, number: Int, disposable: MetaDisposable) {
        guard isCurrentRemoteRequest(request, disposable: disposable) else { return }
        let result: Signal<RegramMessageHistoryPage?, NoError> = regramMessageHistoryPage(account: account, peerId: request.key.messageId.peerId, threadId: request.key.threadId, offsetId: offsetId, offsetDate: 0, limit: 50)
        |> map(Optional.init) |> `catch` { _ in .single(nil) }
        |> timeout(15, queue: queue, alternate: .single(nil)) |> deliverOn(self.queue)
        disposable.set(result.start(next: { [weak self] response in
            guard let self, self.isCurrentRemoteRequest(request, disposable: disposable) else { return }
            guard let response else { self.finishRemote(request, candidate: nil); return }
            let candidate = response.messages.sorted { $0.index > $1.index }.first { message in
                message.index < request.upperBound && !regramShouldHideMessage(message, accountId: self.accountId, filter: request.filter, revision: request.key.preferencesRevision)
            }
            if let candidate { self.finishRemote(request, candidate: candidate) }
            else if let offset = response.nextOffsetId, offset > 0, offset != offsetId, number < 20 {
                self.queue.after(0.05) { [weak self] in self?.loadRemotePage(request, offsetId: offset, number: number + 1, disposable: disposable) }
            } else { self.finishRemote(request, candidate: nil) }
        }))
    }

    private func observeSuppliedMessages(id: CacheId, state: State, messages: [Message]) {
        sourceDisposables[id]?.dispose()
        let disposable = MetaDisposable()
        sourceDisposables[id] = disposable
        nextCandidateToken &+= 1
        let token = nextCandidateToken
        sourceTokens[id] = token
        disposable.set((combineLatest(messages.map { postbox.messageView($0.id) }) |> deliverOn(self.queue)).start(next: { [weak self] views in
            guard let self, !self.disposed.with({ $0 }), self.sourceTokens[id] == token, var current = self.states[id], current.key == state.key else { return }
            let visible = views.compactMap(\.message).filter { !regramShouldHideMessage($0, accountId: self.accountId, filter: current.filter, revision: current.key.preferencesRevision) }
            if !visible.isEmpty {
                let keys = regramChatListSourceKeys(visible)
                let previous = regramChatListSourceKeys(current.messages)
                let payloads = visible.map(RegramMessageFilterPayload.init)
                guard !current.usesSuppliedMessages || keys != previous || current.previewPayloads != payloads else { return }
                current.messages = visible
                current.previewPayloads = payloads
                current.completed = true
                current.usesSuppliedMessages = true
                self.states[id] = current
                self.remoteCompletedKeys.removeValue(forKey: id)
                self.pending.removeAll { $0 == id }
                self.candidateTokens.removeValue(forKey: id)
                self.candidateDisposables.removeValue(forKey: id)?.dispose()
                self.emitChange(for: id)
            } else if current.usesSuppliedMessages {
                current.messages = []
                current.previewPayloads = []
                current.completed = false
                current.usesSuppliedMessages = false
                current.streams = self.streams(key: current.key, upperBound: current.upperBound)
                self.states[id] = current
                if self.activePreviewKeys.contains(id), !self.pending.contains(id) { self.pending.append(id) }
                self.emitChange(for: id)
                self.loadNext()
            }
        }))
    }

    private func observeCandidate(id: CacheId, state: State, candidate: Message) {
        candidateDisposables[id]?.dispose()
        let disposable = MetaDisposable()
        candidateDisposables[id] = disposable
        nextCandidateToken &+= 1
        let token = nextCandidateToken
        candidateTokens[id] = token
        disposable.set((postbox.messageView(candidate.id) |> deliverOn(self.queue)).start(next: { [weak self] view in
            guard let self, !self.disposed.with({ $0 }), self.candidateTokens[id] == token, var current = self.states[id], current.key == state.key else { return }
            if let message = view.message, message.index < current.upperBound, !regramShouldHideMessage(message, accountId: self.accountId, filter: current.filter, revision: current.key.preferencesRevision) {
                guard current.messages.first?.id != message.id || current.messages.first?.stableVersion != message.stableVersion || current.previewPayloads != [RegramMessageFilterPayload(message)] else { return }
                current.messages = [message]
                current.previewPayloads = [RegramMessageFilterPayload(message)]
                self.states[id] = current
                self.emitChange(for: id)
            } else {
                current.messages = []
                current.previewPayloads = []
                current.completed = false
                current.streams = self.streams(key: current.key, upperBound: current.upperBound)
                self.states[id] = current
                self.remoteCompletedKeys.removeValue(forKey: id)
                self.candidateTokens.removeValue(forKey: id)
                self.candidateDisposables.removeValue(forKey: id)?.dispose()
                if self.activePreviewKeys.contains(id), !self.pending.contains(id) { self.pending.append(id) }
                self.emitChange(for: id)
                self.loadNext()
            }
        }))
    }

    private func clearPreviewWork() {
        generation &+= 1
        scanDisposable.set(nil)
        running = false
        inFlight.removeAll()
        pending.removeAll()
        states.removeAll()
        activePreviewKeys.removeAll()
        inactivePreviewLRU.removeAll()
        _ = previewLease.modify { $0 == nil ? nil : [:] }
        candidateDisposables.values.forEach { $0.dispose() }
        candidateDisposables.removeAll()
        candidateTokens.removeAll()
        sourceDisposables.values.forEach { $0.dispose() }
        sourceDisposables.removeAll()
        sourceTokens.removeAll()
        remoteDisposables.values.forEach { $0.dispose() }
        remoteDisposables.removeAll()
        remoteQueue.removeAll()
        remoteCompletedKeys.removeAll()
        lastVisibleTopMessages.removeAll()
    }

    private func emitChange(for id: CacheId? = nil) {
        if let id, !activePreviewKeys.contains(id) { return }
        revision &+= 1
        changes.set(revision)
    }

    func dispose() {
        _ = previewLease.swap(nil)
        _ = unreadLease.swap(nil)
        guard !disposed.swap(true) else { return }
        scanDisposable.dispose()
        self.queue.async { [self] in
            candidateDisposables.values.forEach { $0.dispose() }
            candidateDisposables.removeAll()
            candidateTokens.removeAll()
            sourceDisposables.values.forEach { $0.dispose() }
            sourceDisposables.removeAll()
            sourceTokens.removeAll()
            remoteDisposables.values.forEach { $0.dispose() }
            remoteDisposables.removeAll()
            remoteQueue.removeAll()
            remoteCompletedKeys.removeAll()
            unreadDisposables.values.forEach { $0.1.dispose() }
            unreadDisposables.removeAll()
            unreadObservations.values.forEach { $0.disposable.dispose() }
            unreadObservations.removeAll()
            unreadAttempts.removeAll()
            unreadEvidenceRevisions.removeAll()
            currentUnreadRequests.removeAll()
            pendingUnread.removeAll()
            lastVisibleTopMessages.removeAll()
        }
    }

    deinit {
        _ = previewLease.swap(nil)
        _ = unreadLease.swap(nil)
        unreadDisposables.values.forEach { $0.1.dispose() }
        unreadObservations.values.forEach { $0.disposable.dispose() }
        scanDisposable.dispose()
        candidateDisposables.values.forEach { $0.dispose() }
        sourceDisposables.values.forEach { $0.dispose() }
        remoteDisposables.values.forEach { $0.dispose() }
    }
}
