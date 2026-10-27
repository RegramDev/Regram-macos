import Foundation

extension Bundle { static var module: Bundle { .main } }

public struct PeerId: Hashable, Comparable {
    public let namespace: Int32
    public let value: Int64
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.toInt64() < rhs.toInt64() }
    public func toInt64() -> Int64 { Int64(namespace) << 56 | value }
}

public struct MessageId: Hashable, Comparable {
    public typealias Namespace = Int32
    public typealias Id = Int32
    public let peerId: PeerId
    public let namespace: Int32
    public let id: Int32
    public static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.peerId != rhs.peerId { return lhs.peerId < rhs.peerId }
        if lhs.namespace != rhs.namespace { return lhs.namespace < rhs.namespace }
        return lhs.id < rhs.id
    }
}

public struct MessageIndex: Hashable, Comparable {
    public let id: MessageId
    public let timestamp: Int32
    public static func upperBound(peerId: PeerId, namespace: Int32) -> Self { Self(id: MessageId(peerId: peerId, namespace: namespace, id: .max), timestamp: .max) }
    public static func upperBound(peerId: PeerId, timestamp: Int32, namespace: Int32) -> Self { Self(id: MessageId(peerId: peerId, namespace: namespace, id: .max), timestamp: timestamp) }
    public static func lowerBound(peerId: PeerId, namespace: Int32) -> Self { Self(id: MessageId(peerId: peerId, namespace: namespace, id: 0), timestamp: 0) }
    MESSAGE_INDEX_COMPARATOR
}

public struct ChatListIndex: Hashable, Comparable {
    public let pinningIndex: UInt16?
    public let messageIndex: MessageIndex
    CHAT_LIST_INDEX_COMPARATOR
}

public enum Namespaces {
    public enum Peer {
        public static let CloudUser: Int32 = 0
        public static let CloudGroup: Int32 = 1
        public static let CloudChannel: Int32 = 2
        public static let SecretChat: Int32 = 3
    }
    public enum Message {
        public static let Cloud: Int32 = 0
        public static let Local: Int32 = 1
        public static let SecretIncoming: Int32 = 2
        public static let ScheduledCloud: Int32 = 3
        public static let EphemeralLocal: Int32 = 4
    }
}

public struct MessageFlags: OptionSet, Equatable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let IsIncomingMask = Self(rawValue: 1)
}

public class Peer: Equatable {
    public let id: PeerId
    public var isForumOrMonoForum = false
    public var isMember = true
    public init(id: PeerId) { self.id = id }
    public static func == (lhs: Peer, rhs: Peer) -> Bool { lhs.id == rhs.id && lhs.isForumOrMonoForum == rhs.isForumOrMonoForum && lhs.isMember == rhs.isMember }
}
public final class TelegramChannel: Peer {
    public enum ParticipationStatus: Equatable { case member, left }
    public var participationStatus: ParticipationStatus { isMember ? .member : .left }
}
public typealias InstantPageBlock = String
public final class InstantPage {
    public let blocks: [String]
    public init(_ blocks: [String]) { self.blocks = blocks }
}
public protocol MessageAttribute: AnyObject {}
public final class RichTextMessageAttribute: MessageAttribute, Equatable {
    public let instantPage: InstantPage
    public var fullInstantPage: InstantPage?
    public init(_ page: InstantPage) { instantPage = page }
    public static func == (lhs: RichTextMessageAttribute, rhs: RichTextMessageAttribute) -> Bool { lhs.instantPage.blocks == rhs.instantPage.blocks && lhs.fullInstantPage?.blocks == rhs.fullInstantPage?.blocks }
}
func regramBlockText(_ blocks: [String]) -> String { blocks.joined(separator: "\n") }

public struct Message: Equatable {
    public var id: MessageId
    public var timestamp: Int32
    public var stableVersion: UInt32 = 1
    public var text = "hidden"
    public var flags: MessageFlags = .IsIncomingMask
    public var groupingKey: Int64?
    public var author: Peer?
    public var attributes: [MessageAttribute] = []
    public var media: [String] = []
    public var threadId: Int64?
    public var index: MessageIndex { MessageIndex(id: id, timestamp: timestamp) }
    public static func == (lhs: Message, rhs: Message) -> Bool { lhs.id == rhs.id && lhs.timestamp == rhs.timestamp && lhs.stableVersion == rhs.stableVersion && lhs.groupingKey == rhs.groupingKey && lhs.threadId == rhs.threadId && lhs.media == rhs.media && RegramMessageFilterPayload(lhs) == RegramMessageFilterPayload(rhs) }
    public func withUpdatedText(_ text: String) -> Message { var value = self; value.text = text; return value }
    public func withUpdatedAttributes(_ attributes: [MessageAttribute]) -> Message { var value = self; value.attributes = attributes; return value }
}

public func regramMessageText(_ message: Message) -> String {
    message.text + message.attributes.compactMap { $0 as? RichTextMessageAttribute }.map { "\n" + regramBlockText(($0.fullInstantPage ?? $0.instantPage).blocks) }.joined()
}

public struct EngineMessage: Equatable {
    public typealias Id = MessageId
    public typealias Index = MessageIndex
    let message: Message
    public func _asMessage() -> Message { message }
}

public struct EnginePeer: Equatable {
    public typealias Id = PeerId
    public typealias Presence = String
    public let peer: Peer
    public func _asPeer() -> Peer { peer }
}
public struct EngineRenderedPeer: Equatable, ExpressibleByStringLiteral {
    public let peerId: PeerId
    public let peer: EnginePeer?
    public init(peerId: PeerId, peer: EnginePeer?) { self.peerId = peerId; self.peer = peer }
    public init(stringLiteral value: String) { let id = PeerId(namespace: 0, value: 42); self.init(peerId: id, peer: EnginePeer(peer: Peer(id: id))) }
}
public typealias MessageHistoryThreadData = String
public struct EnginePeerReadCounters: Equatable { let state: CombinedPeerReadState; public func _asReadCounters() -> CombinedPeerReadState? { state } }

public struct EngineChatList {
    public typealias Draft = String
    public typealias ForumTopicData = String
    public typealias StoryStats = String
    public enum MediaDraftContentType { case audio, video }
    public var items: [Item]
    public var hasEarlier: Bool
    ENGINE_ITEM_DECLARATION
}

public struct CachedPeerData: Equatable { let associatedHistoryMessageId: MessageId? }

public final class Transaction {
    public var peers: [PeerId: Peer] = [:]
    public var messages: [MessageId: Message] = [:]
    public var readStates: [PeerId: CombinedPeerReadState] = [:]
    public var holes: [PeerId: IndexSet] = [:]
    public var cached: [PeerId: CachedPeerData] = [:]
    public var recentOverride: [Message]?
    public var applied: [MessageIndex] = []
    public var beforeNativeApply: (() -> Void)?
    public var transactionRuns = 0
    public var historyQueries = 0
    public var beforeTransaction: ((Int) -> Void)?
    public var afterTransaction: ((Int) -> Void)?
    public func getPeer(_ id: PeerId) -> Peer? { peers[id] }
    public func getCombinedPeerReadState(_ id: PeerId) -> CombinedPeerReadState? { readStates[id] }
    public func getTopPeerMessageIndex(peerId: PeerId) -> MessageIndex? { messages.values.filter { $0.id.peerId == peerId }.map(\.index).max() }
    public func getTopPeerMessageIndex(peerId: PeerId, namespace: Int32) -> MessageIndex? { messages.values.filter { $0.id.peerId == peerId && $0.id.namespace == namespace }.map(\.index).max() }
    public func getMessage(_ id: MessageId) -> Message? { messages[id] }
    public func getMessageGroup(_ id: MessageId) -> [Message]? {
        guard let message = messages[id] else { return nil }
        guard let group = message.groupingKey else { return [message] }
        return messages.values.filter { $0.id.peerId == id.peerId && $0.groupingKey == group }
    }
    public func getPeerCachedData(peerId: PeerId) -> CachedPeerData? { cached[peerId] }
    public func getHoles(peerId: PeerId, namespace: Int32) -> IndexSet { holes[peerId] ?? IndexSet() }
    public func getMessages(peerId: PeerId, namespace: Int32, from: MessageIndex, includeFrom: Bool, to: MessageIndex, limit: Int) -> [Message] {
        historyQueries += 1
        return recentOverride ?? Array(messages.values.filter { $0.id.peerId == peerId && $0.id.namespace == namespace && ($0.index < from || includeFrom && $0.index == from) && $0.index >= to }.sorted { $0.index > $1.index }.prefix(limit))
    }
    public func getMessagesWithThreadId(peerId: PeerId, namespace: Int32, threadId: Int64, from: MessageIndex, includeFrom: Bool, to: MessageIndex, limit: Int) -> [Message] {
        getMessages(peerId: peerId, namespace: namespace, from: from, includeFrom: includeFrom, to: to, limit: limit).filter { $0.threadId == threadId }
    }
}

public enum NoError: Error {}
public struct Signal<Value, Failure: Error> {
    let body: () -> Value
    var observe: ((@escaping (Value) -> Void) -> TestDisposable)?
    var countStart = true
    public static func single(_ value: Value) -> Self { Self(body: { value }) }
    public func run() -> Value { body() }
    func start(next: ((Value) -> Void)? = nil, completed: (() -> Void)? = nil) -> TestDisposable {
        let disposable = TestDisposable()
        if countStart { prepareQueue.startCalls += 1 }
        prepareQueue.enqueueResult {
            let value = self.body()
            guard !disposable.isDisposed else { return }
            next?(value)
            if let observe = self.observe {
                let child = observe { value in if !disposable.isDisposed { next?(value) } }
                disposable.onDispose = { child.dispose() }
            } else { completed?() }
        }
        return disposable
    }
}
public struct MessageView { let message: Message? }
public enum MessageIdNamespaces: Hashable { case just(Set<Int32>) }
public enum HistoryViewInputAnchor: Hashable { case upperBound }
public enum PostboxViewKey: Hashable {
    public struct HistoryView: Hashable {
        let peerId: PeerId
        let trackHoles: Bool
        init(peerId: PeerId, threadId: Int64?, clipHoles: Bool, trackHoles: Bool, anchor: HistoryViewInputAnchor, appendMessagesFromTheSameGroup: Bool, namespaces: MessageIdNamespaces, count: Int) { self.peerId = peerId; self.trackHoles = trackHoles }
    }
    case historyView(HistoryView)
    case cachedPeerData(peerId: PeerId)
    case combinedReadState(peerId: PeerId, handleThreads: Bool)
    case basicPeer(PeerId)
    case messages(Set<MessageId>)
}
public struct CachedPeerDataView { let cachedPeerData: CachedPeerData? }
public struct CombinedView { let views: [PostboxViewKey: Any] }
private struct ObservationFingerprint: Equatable {
    let payloads: [RegramMessageFilterPayload]
    let holes: [IndexSet]
    let reads: [CombinedPeerReadState?]
    let associated: [MessageId?]
    let peers: [String]
}
public final class Postbox {
    let storage = Transaction()
    let lock = NSLock()
    private final class Observer {
        let keys: [PostboxViewKey]
        var fingerprint: ObservationFingerprint
        let disposable: TestDisposable
        let emit: () -> Void
        init(keys: [PostboxViewKey], fingerprint: ObservationFingerprint, disposable: TestDisposable, emit: @escaping () -> Void) { self.keys = keys; self.fingerprint = fingerprint; self.disposable = disposable; self.emit = emit }
    }
    private var observers: [Observer] = []
    private(set) var observationStarts = 0
    public func transaction<Value>(_ body: @escaping (Transaction) -> Value) -> Signal<Value, NoError> {
        Signal(body: {
            self.lock.lock()
            self.storage.transactionRuns += 1
            self.storage.beforeTransaction?(self.storage.transactionRuns)
            TestCounters.shared.enterPostbox()
            let value = body(self.storage)
            TestCounters.shared.leavePostbox()
            self.lock.unlock()
            self.publishViews()
            self.storage.afterTransaction?(self.storage.transactionRuns)
            return value
        })
    }
    private func fingerprint(_ keys: [PostboxViewKey]) -> ObservationFingerprint {
        var peerIds = Set<PeerId>()
        for key in keys {
            switch key {
            case let .historyView(view): peerIds.insert(view.peerId)
            case let .cachedPeerData(peerId), let .combinedReadState(peerId, _), let .basicPeer(peerId): peerIds.insert(peerId)
            case let .messages(ids): peerIds.formUnion(ids.map(\.peerId))
            }
        }
        let ordered = peerIds.sorted()
        return ObservationFingerprint(payloads: storage.messages.values.filter { peerIds.contains($0.id.peerId) }.sorted { $0.id < $1.id }.map(RegramMessageFilterPayload.init), holes: ordered.map { storage.holes[$0] ?? [] }, reads: ordered.map { storage.readStates[$0] }, associated: ordered.map { storage.cached[$0]?.associatedHistoryMessageId }, peers: ordered.map { String(storage.peers[$0]?.isMember ?? false) + String(storage.peers[$0]?.isForumOrMonoForum ?? false) })
    }
    func publishViews() {
        observers.removeAll { $0.disposable.isDisposed }
        for observer in observers {
            let current = fingerprint(observer.keys)
            if current != observer.fingerprint {
                observer.fingerprint = current
                prepareQueue.enqueueResult { if !observer.disposable.isDisposed { observer.emit() } }
            }
        }
    }
    private func live<Value>(keys: [PostboxViewKey], value: @escaping () -> Value) -> Signal<Value, NoError> {
        Signal(body: value, observe: { emit in
            let disposable = TestDisposable()
            self.observationStarts += 1
            self.observers.append(Observer(keys: keys, fingerprint: self.fingerprint(keys), disposable: disposable, emit: { emit(value()) }))
            return disposable
        }, countStart: false)
    }
    public func combinedView(keys: [PostboxViewKey]) -> Signal<CombinedView, NoError> {
        live(keys: keys) { CombinedView(views: Dictionary(uniqueKeysWithValues: keys.compactMap { key -> (PostboxViewKey, Any)? in
            if case let .cachedPeerData(peerId) = key { return (key, CachedPeerDataView(cachedPeerData: self.storage.cached[peerId])) }
            return nil
        })) }
    }
    public func messageView(_ id: MessageId) -> Signal<MessageView, NoError> { live(keys: [.messages([id])]) { MessageView(message: self.storage.messages[id]) } }
}
public struct AccountStateManager {}
public struct Account {
    public let postbox = Postbox()
    public let stateManager = AccountStateManager()
}
func peerKeepsReadState(_ peer: Peer?) -> Bool { peer?.isMember != false }
func _internal_applyMaxReadIndexInteractively(transaction: Transaction, stateManager: AccountStateManager, index: MessageIndex) {
    transaction.beforeNativeApply?()
    transaction.applied.append(index)
    let old = transaction.readStates[index.id.peerId]
    transaction.readStates[index.id.peerId] = CombinedPeerReadState(states: old?.states.map { namespace, state in
        guard namespace == index.id.namespace else { return (namespace, state) }
        return (namespace, PeerReadState.idBased(maxIncomingReadId: index.id.id, maxOutgoingReadId: 0, maxKnownId: index.id.id, count: 0, markedUnread: false))
    } ?? [])
}

struct UnreadSource: Equatable { let accountId: Int64; let preferencesRevision: Int64 }
struct UnreadRequest: Equatable { let id: Int; let source: UnreadSource; let snapshot: RegramChatListUnreadSnapshot }

final class TestDisposable {
    private(set) var isDisposed = false
    var onDispose: (() -> Void)?
    func dispose() { guard !isDisposed else { return }; isDisposed = true; onDispose?(); onDispose = nil }
}

final class MetaDisposable {
    private var current: TestDisposable?
    private var isDisposed = false
    func set(_ value: TestDisposable?) {
        current?.dispose()
        if isDisposed { value?.dispose() } else { current = value }
    }
    func dispose() { isDisposed = true; current?.dispose(); current = nil }
    deinit { dispose() }
}

final class SchedulingQueue {
    private var events: [() -> Void] = []
    private(set) var continuationDispatches = 0
    var startCalls = 0
    func async(_ body: @escaping () -> Void) { events.append(body) }
    func after(_ delay: Double, _ body: @escaping () -> Void) { events.append(body) }
    func enqueueResult(_ body: @escaping () -> Void) { events.append(body) }
    func justDispatch(_ body: @escaping () -> Void) { continuationDispatches += 1; events.append(body) }
    func runNext() -> Bool {
        guard !events.isEmpty else { return false }
        events.removeFirst()()
        return true
    }
    func reset() { precondition(events.isEmpty); continuationDispatches = 0; startCalls = 0 }
}

let prepareQueue = SchedulingQueue()
infix operator |> : AdditionPrecedence
func |> <A, B>(value: A, transform: (A) -> B) -> B { transform(value) }
func deliverOn<Value, Failure>(_ queue: SchedulingQueue) -> (Signal<Value, Failure>) -> Signal<Value, Failure> { { $0 } }

func mapToSignal<A, B, E>(_ transform: @escaping (A) -> Signal<B, E>) -> (Signal<A, E>) -> Signal<B, E> { { signal in Signal<B, E>(body: { transform(signal.run()).run() }) } }
func combineLatest(_ signals: [Signal<MessageView, NoError>]) -> Signal<[MessageView], NoError> {
    Signal(body: { signals.map { $0.run() } }, observe: { emit in
        var children: [TestDisposable] = []
        for signal in signals { children.append(signal.start(next: { _ in emit(signals.map { $0.run() }) })) }
        let parent = TestDisposable(); parent.onDispose = { children.forEach { $0.dispose() } }; return parent
    }, countStart: false)
}
final class ValuePromise<Value> {
    private(set) var value: Value
    init(_ value: Value, ignoreRepeated: Bool) { self.value = value }
    func set(_ value: Value) { self.value = value }
}
struct TestFilter { let id: Int32 }
enum UIChatListEntryId: Hashable { case chat(EngineChatList.Item.Id, PeerId, Int32); case space }
enum UIChatListEntry {
    case chat(EngineChatList.Item, [String], String?, filter: TestFilter, generalStatus: String?, selectedForum: PeerId?, appearMode: String, hideContent: Bool, folders: String?, communityCategories: [PeerId: String], canPreviewChat: Bool, regramRevision: Int64)
    case space
    var stableId: UIChatListEntryId {
        if case let .chat(item, _, _, filter, _, _, _, _, _, _, _, _) = self { return .chat(item.id, item.renderedPeer.peerId, filter.id) }
        return .space
    }
}
final class TestCounters {
    static let shared = TestCounters()
    private let lock = NSLock()
    private var values: [String: Int] = [:]
    private var postboxDepth = 0
    func enterPostbox() { lock.lock(); postboxDepth += 1; lock.unlock() }
    func leavePostbox() { lock.lock(); postboxDepth -= 1; lock.unlock() }
    func increment(_ key: String) {
        lock.lock()
        values[key, default: 0] += 1
        if postboxDepth > 0 { values[key + ".postbox", default: 0] += 1 }
        lock.unlock()
    }
    func count(_ key: String) -> Int { lock.lock(); defer { lock.unlock() }; return values[key] ?? 0 }
}
