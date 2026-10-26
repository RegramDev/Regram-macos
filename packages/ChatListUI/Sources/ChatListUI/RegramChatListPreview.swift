import Postbox
import TelegramCore
import ChatHistoryModel
import TelegramTheme
import RegramCore
import SwiftSignalKit

final class RegramChatListPreviewCoordinator {
    private struct SourceMessageKey: Equatable {
        let id: MessageId
        let version: UInt32
    }

    private struct SourceKey: Equatable {
        let accountId: Int64
        let messageId: MessageId
        let stableVersion: UInt32
        let filterRevision: Int64
        let threadId: Int64?
        let suppliedMessages: [SourceMessageKey]
    }

    private struct Stream {
        var cursor: MessageIndex
        var candidate: Message?
        var exhausted = false
    }

    private struct State {
        let key: SourceKey
        let upperBound: MessageIndex
        var streams: [MessageId.Namespace: Stream]
        var messages: [Message]
        var completed: Bool
        var usesSuppliedMessages: Bool
    }

    private struct Request {
        let id: UIChatListEntryId
        let key: SourceKey
        let upperBound: MessageIndex
        let streams: [MessageId.Namespace: Stream]
    }

    private struct Result {
        let request: Request
        let streams: [MessageId.Namespace: Stream]
    }

    private let postbox: Postbox
    private let accountId: Int64
    private let scanDisposable = MetaDisposable()
    private let disposed = Atomic(value: false)
    private var generation: UInt64 = 0
    private var filterRevision: Int64?
    private var states: [UIChatListEntryId: State] = [:]
    private var pending: [UIChatListEntryId] = []
    private var inFlight: [UIChatListEntryId: SourceKey] = [:]
    private var candidateDisposables: [UIChatListEntryId: MetaDisposable] = [:]
    private var candidateTokens: [UIChatListEntryId: UInt64] = [:]
    private var sourceDisposables: [UIChatListEntryId: MetaDisposable] = [:]
    private var sourceTokens: [UIChatListEntryId: UInt64] = [:]
    private var nextCandidateToken: UInt64 = 0
    private var running = false
    private var revision: Int64 = 0
    let changes = ValuePromise<Int64>(0, ignoreRepeated: true)

    init(postbox: Postbox, accountId: Int64) {
        self.postbox = postbox
        self.accountId = accountId
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

    func update(_ entries: [UIChatListEntry], filterRevision: Int64) -> [UIChatListEntryId: [Message]] {
        guard !disposed.with({ $0 }) else { return [:] }
        let reset = self.filterRevision != filterRevision
        self.filterRevision = filterRevision
        if reset {
            generation &+= 1
            scanDisposable.set(nil)
            running = false
            inFlight.removeAll()
        }
        var nextStates: [UIChatListEntryId: State] = [:]
        var order: [UIChatListEntryId] = []
        var sourcesToObserve: [(UIChatListEntryId, State, [Message])] = []
        var changed = reset
        for entry in entries {
            guard case let .chat(item, _, _, _, _, _, _, _, _, _, _, _) = entry else { continue }
            let messages = item.messages.map { $0._asMessage() }
            guard let newest = messages.first, regramShouldHideMessage(newest, accountId: accountId) else { continue }
            let threadId: Int64?
            if case let .forum(id) = item.id { threadId = id } else { threadId = nil }
            let key = SourceKey(accountId: accountId, messageId: newest.id, stableVersion: newest.stableVersion, filterRevision: filterRevision, threadId: threadId, suppliedMessages: messages.map { SourceMessageKey(id: $0.id, version: $0.stableVersion) })
            if let state = states[entry.stableId], state.key == key {
                nextStates[entry.stableId] = state
            } else {
                let visible = regramVisibleMessages(messages, accountId: accountId)
                let upperBound = messages.map(\.index).min() ?? newest.index
                let state = State(key: key, upperBound: upperBound, streams: streams(key: key, upperBound: upperBound), messages: visible, completed: !visible.isEmpty, usesSuppliedMessages: !visible.isEmpty)
                nextStates[entry.stableId] = state
                sourcesToObserve.append((entry.stableId, state, messages))
                changed = true
            }
            order.append(entry.stableId)
        }
        if nextStates.count != states.count { changed = true }
        if changed {
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
            let previousPending = pending.filter { states[$0]?.completed == false && inFlight[$0] != states[$0]?.key }
            var seen = Set(previousPending)
            pending = previousPending + order.filter { states[$0]?.completed == false && inFlight[$0] != states[$0]?.key && seen.insert($0).inserted }
        }
        for (id, state, messages) in sourcesToObserve { observeSuppliedMessages(id: id, state: state, messages: messages) }
        if !running { loadNext() }
        return states.mapValues(\.messages)
    }

    func refreshExhaustedEmpty() {
        prepareQueue.async { [weak self] in
            guard let self, !self.disposed.with({ $0 }) else { return }
            let ids = self.states.compactMap { id, state in state.completed && state.messages.isEmpty ? id : nil }
            for id in ids {
                guard var state = self.states[id] else { continue }
                state.completed = false
                state.streams = self.streams(key: state.key, upperBound: state.upperBound)
                self.states[id] = state
                if !self.pending.contains(id) { self.pending.append(id) }
            }
            if !self.running { self.loadNext() }
        }
    }

    private func loadNext() {
        guard !disposed.with({ $0 }), !running, !pending.isEmpty else { return }
        let ids = Array(pending.prefix(8))
        pending.removeFirst(ids.count)
        let requests = ids.compactMap { id -> Request? in
            guard let state = states[id], !state.completed else { return nil }
            return Request(id: id, key: state.key, upperBound: state.upperBound, streams: state.streams)
        }
        guard !requests.isEmpty else { loadNext(); return }
        running = true
        inFlight = Dictionary(uniqueKeysWithValues: requests.map { ($0.id, $0.key) })
        let generation = self.generation
        scanDisposable.set((postbox.transaction { transaction -> [Result] in
            requests.map { request in
                let peerId = request.key.messageId.peerId
                var streams = request.streams
                for (namespace, stream) in request.streams where !stream.exhausted && stream.candidate == nil {
                    let lower = MessageIndex.lowerBound(peerId: peerId, namespace: namespace)
                    let messages: [Message]
                    if let threadId = request.key.threadId {
                        messages = transaction.getMessagesWithThreadId(peerId: peerId, namespace: namespace, threadId: threadId, from: stream.cursor, includeFrom: false, to: lower, limit: 32)
                    } else {
                        messages = transaction.getMessages(peerId: peerId, namespace: namespace, from: stream.cursor, includeFrom: false, to: lower, limit: 32)
                    }
                    let ordered = messages.sorted { $0.index > $1.index }
                    let candidate = ordered.first { $0.index < request.upperBound && !regramShouldHideMessage($0, accountId: request.key.accountId) }
                    let nextCursor = ordered.last?.index
                    streams[namespace] = Stream(cursor: nextCursor ?? stream.cursor, candidate: candidate, exhausted: messages.count < 32 || nextCursor == nil || nextCursor! >= stream.cursor)
                }
                return Result(request: request, streams: streams)
            }
        } |> deliverOn(prepareQueue)).start(next: { [weak self] results in
            guard let self, !self.disposed.with({ $0 }), self.generation == generation else { return }
            self.running = false
            self.inFlight.removeAll()
            var changed = false
            var found: [(UIChatListEntryId, State, Message)] = []
            for result in results {
                guard var state = self.states[result.request.id], state.key == result.request.key, !state.completed else { continue }
                state.streams = result.streams
                if let candidate = state.streams.values.compactMap(\.candidate).max(by: { $0.index < $1.index }),
                   !state.streams.values.contains(where: { !$0.exhausted && $0.candidate == nil && $0.cursor > candidate.index }) {
                    state.messages = [candidate]
                    state.completed = true
                    found.append((result.request.id, state, candidate))
                    changed = true
                } else if state.streams.values.allSatisfy({ $0.exhausted && $0.candidate == nil }) {
                    state.completed = true
                } else if !self.pending.contains(result.request.id) {
                    self.pending.append(result.request.id)
                }
                self.states[result.request.id] = state
            }
            for (id, state, candidate) in found { self.observeCandidate(id: id, state: state, candidate: candidate) }
            if changed { self.emitChange() }
            prepareQueue.after(0.005) { [weak self] in
                guard let self, self.generation == generation else { return }
                self.loadNext()
            }
        }))
    }

    private func observeSuppliedMessages(id: UIChatListEntryId, state: State, messages: [Message]) {
        sourceDisposables[id]?.dispose()
        let disposable = MetaDisposable()
        sourceDisposables[id] = disposable
        nextCandidateToken &+= 1
        let token = nextCandidateToken
        sourceTokens[id] = token
        disposable.set((combineLatest(messages.map { postbox.messageView($0.id) }) |> deliverOn(prepareQueue)).start(next: { [weak self] views in
            guard let self, !self.disposed.with({ $0 }), self.sourceTokens[id] == token, var current = self.states[id], current.key == state.key else { return }
            let visible = regramVisibleMessages(views.compactMap(\.message), accountId: self.accountId)
            if !visible.isEmpty {
                let keys = visible.map { SourceMessageKey(id: $0.id, version: $0.stableVersion) }
                let previous = current.messages.map { SourceMessageKey(id: $0.id, version: $0.stableVersion) }
                guard !current.usesSuppliedMessages || keys != previous else { return }
                current.messages = visible
                current.completed = true
                current.usesSuppliedMessages = true
                self.states[id] = current
                self.pending.removeAll { $0 == id }
                self.candidateTokens.removeValue(forKey: id)
                self.candidateDisposables.removeValue(forKey: id)?.dispose()
                self.emitChange()
            } else if current.usesSuppliedMessages {
                current.messages = []
                current.completed = false
                current.usesSuppliedMessages = false
                current.streams = self.streams(key: current.key, upperBound: current.upperBound)
                self.states[id] = current
                if !self.pending.contains(id) { self.pending.append(id) }
                self.emitChange()
                self.loadNext()
            }
        }))
    }

    private func observeCandidate(id: UIChatListEntryId, state: State, candidate: Message) {
        candidateDisposables[id]?.dispose()
        let disposable = MetaDisposable()
        candidateDisposables[id] = disposable
        nextCandidateToken &+= 1
        let token = nextCandidateToken
        candidateTokens[id] = token
        disposable.set((postbox.messageView(candidate.id) |> deliverOn(prepareQueue)).start(next: { [weak self] view in
            guard let self, !self.disposed.with({ $0 }), self.candidateTokens[id] == token, var current = self.states[id], current.key == state.key else { return }
            if let message = view.message, message.index < current.upperBound, !regramShouldHideMessage(message, accountId: self.accountId) {
                guard current.messages.first?.id != message.id || current.messages.first?.stableVersion != message.stableVersion else { return }
                current.messages = [message]
                self.states[id] = current
                self.emitChange()
            } else {
                current.messages = []
                current.completed = false
                current.streams = self.streams(key: current.key, upperBound: current.upperBound)
                self.states[id] = current
                self.candidateTokens.removeValue(forKey: id)
                self.candidateDisposables.removeValue(forKey: id)?.dispose()
                if !self.pending.contains(id) { self.pending.append(id) }
                self.emitChange()
                self.loadNext()
            }
        }))
    }

    private func emitChange() {
        revision &+= 1
        changes.set(revision)
    }

    func dispose() {
        guard !disposed.swap(true) else { return }
        scanDisposable.dispose()
        prepareQueue.async { [self] in
            candidateDisposables.values.forEach { $0.dispose() }
            candidateDisposables.removeAll()
            candidateTokens.removeAll()
            sourceDisposables.values.forEach { $0.dispose() }
            sourceDisposables.removeAll()
            sourceTokens.removeAll()
        }
    }

    deinit {
        scanDisposable.dispose()
        candidateDisposables.values.forEach { $0.dispose() }
        sourceDisposables.values.forEach { $0.dispose() }
    }
}
