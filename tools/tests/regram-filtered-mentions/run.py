#!/usr/bin/env python3
"""Exercise production filtered-mention selection/navigation with account-free Postbox adapters."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
tests = Path(__file__).with_name('FilteredMentionTests.swift')
lookup_path = ROOT / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/EarliestUnseenPersonalMentionMessage.swift'
engine_path = ROOT / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift'
lookup = lookup_path.read_text()
lookup = lookup[lookup.index('public enum EarliestUnseenPersonalMentionMessageResult'):lookup.index('func _internal_earliestUnseenPersonalReactionMessage')]
engine = engine_path.read_text()
engine = engine[engine.index('        public func earliestUnseenPersonalMentionMessage('):engine.index('        public func earliestUnseenPersonalReactionMessage(')]
policy = (ROOT / 'packages/ChatHistoryModel/Sources/ChatHistoryModel/RegramFilteredReading.swift').read_text()
for module in ['Postbox', 'SwiftSignalKit', 'TelegramCore']:
    policy = policy.replace('import ' + module + '\n', '')

adapters = r'''
import Foundation

public enum NoError: Error {}
public struct SignalTakeAction { let passthrough: Bool; let complete: Bool }
public struct Signal<Value, Failure: Error> {
    let values: () -> [Value]
    public static func single(_ value: Value) -> Self { Self(values: { [value] }) }
    @discardableResult func start() -> Int { _ = values(); return 0 }
}
infix operator |> : AdditionPrecedence
func |> <A, B>(value: A, transform: (A) -> B) -> B { transform(value) }
func mapToSignal<A, B, E>(_ transform: @escaping (A) -> Signal<B, E>) -> (Signal<A, E>) -> Signal<B, E> {
    { input in Signal(values: { input.values().flatMap { transform($0).values() } }) }
}
func distinctUntilChanged<A: Equatable, E>(_ input: Signal<A, E>) -> Signal<A, E> {
    Signal(values: {
        var result: [A] = []
        for value in input.values() where result.last != value { result.append(value) }
        return result
    })
}
func take<A, E>(until predicate: @escaping (A) -> SignalTakeAction) -> (Signal<A, E>) -> Signal<A, E> {
    { input in Signal(values: {
        var result: [A] = []
        for value in input.values() {
            let action = predicate(value)
            if action.passthrough { result.append(value) }
            if action.complete { return result }
        }
        return result
    }) }
}

public struct PeerId: Hashable { public let namespace: Int32; public let value: Int64 }
public struct MessageId: Hashable {
    public let peerId: PeerId; public let namespace: Int32; public let id: Int32
}
public struct MessageIndex: Comparable {
    public let id: MessageId; public let timestamp: Int32
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.timestamp == rhs.timestamp ? lhs.id.id < rhs.id.id : lhs.timestamp < rhs.timestamp
    }
}
public struct MessageFlags: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let IsIncomingMask = Self(rawValue: 1)
}
public struct MessageTags: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let unseenPersonalMessage = Self(rawValue: 1)
}
public struct ConsumablePersonalMentionMessageAttribute { let consumed: Bool; let pending: Bool }
public struct ChannelMessageStateVersionAttribute { let pts: Int32 }
public struct Message {
    public let id: MessageId; public let threadId: Int64?; public let timestamp: Int32
    public let flags: MessageFlags; public let tags: MessageTags; public var attributes: [Any]
    public let text: String
    public var index: MessageIndex { MessageIndex(id: id, timestamp: timestamp) }
}
public enum Namespaces {
    public enum Message { public static let Cloud: Int32 = 0; public static let Local: Int32 = 1 }
    public enum Peer { public static let CloudChannel: Int32 = 2; public static let CloudGroup: Int32 = 1 }
}
struct ChannelState { let invalidatedPts: Int32? }
enum AdditionalMessageHistoryViewDataEntry { case peerChatState(PeerId, Any?), unrelated }
enum AdditionalMessageHistoryViewData { case peerChatState(PeerId) }
enum ChatLocationInput { case peer(peerId: PeerId, threadId: Int64?) }
enum MessageHistoryAnchorIndex { case lowerBound }
enum HistoryViewInputTag { case tag(MessageTags) }
enum ViewUpdateType { case Generic, FillHole }
struct MessageHistoryEntry { let message: Message }
struct MessageHistoryView {
    let isLoading: Bool; let entries: [MessageHistoryEntry]; let additionalData: [AdditionalMessageHistoryViewDataEntry]
}

final class Transaction {
    var messages: [MessageId: Message] = [:]
    var summaryResets = 0, holeRemovals = 0, tagRepairs = 0
    func getMessage(_ id: MessageId) -> Message? { messages[id] }
    func getTopPeerMessageId(peerId: PeerId, namespace: Int32) -> MessageId? {
        messages.keys.filter { $0.peerId == peerId && $0.namespace == namespace }.max { $0.id < $1.id }
    }
    func replaceMessageTagSummary(peerId: PeerId, threadId: Int64?, tagMask: MessageTags, namespace: Int32, customTag: Int?, count: Int32, maxId: Int32) { summaryResets += 1 }
    func removeHole(peerId: PeerId, threadId: Int64?, namespace: Int32, space: HistoryViewInputTag, range: ClosedRange<Int32>) { holeRemovals += 1 }
    func getMessageIndicesWithTag(peerId: PeerId, threadId: Int64?, namespace: Int32, tag: MessageTags) -> [MessageIndex] {
        messages.values.filter { $0.id.peerId == peerId && $0.id.namespace == namespace && (threadId == nil || $0.threadId == threadId) && $0.tags.contains(tag) }.map(\.index)
    }
}
public final class Postbox {
    let storage = Transaction()
    func transaction<T>(_ action: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        Signal(values: { [action(self.storage)] })
    }
}
public final class Account {
    public let postbox = Postbox()
    public lazy var viewTracker = AccountViewTracker(account: self)
    var bulkAcknowledgements = 0
}
public final class AccountViewTracker {
    unowned let account: Account
    var acknowledged = Set<MessageId>()
    var ignoredLookups: [Set<MessageId>] = []
    var fillHoleOnce = false, isLoading = false
    var invalidatedPts: Int32?
    init(account: Account) { self.account = account }
    func aroundMessageHistoryViewForLocation(_ location: ChatLocationInput, ignoreMessageIds: Set<MessageId> = [], index: MessageHistoryAnchorIndex, anchorIndex: MessageHistoryAnchorIndex, count: Int, fixedCombinedReadStates: Int?, tag: HistoryViewInputTag?, additionalData: [AdditionalMessageHistoryViewData]) -> Signal<(MessageHistoryView, ViewUpdateType, Int?), NoError> {
        Signal(values: {
            self.ignoredLookups.append(ignoreMessageIds)
            let peerId: PeerId; let threadId: Int64?
            switch location { case let .peer(peer, thread): peerId = peer; threadId = thread }
            let messages = self.account.postbox.storage.messages.values.filter {
                $0.id.peerId == peerId && (threadId == nil || $0.threadId == threadId) && $0.tags.contains(.unseenPersonalMessage) && !ignoreMessageIds.contains($0.id)
            }.sorted { $0.index < $1.index }
            let view = MessageHistoryView(isLoading: self.isLoading, entries: messages.prefix(count).map { MessageHistoryEntry(message: $0) }, additionalData: [.peerChatState(peerId, ChannelState(invalidatedPts: self.invalidatedPts))])
            if self.fillHoleOnce && !ignoreMessageIds.isEmpty {
                self.fillHoleOnce = false
                return [(view, .FillHole, nil)]
            }
            return [(view, .Generic, nil)]
        })
    }
    public func updateMarkMentionsSeenForMessageIds(messageIds: Set<MessageId>) {
        for id in messageIds {
            guard var message = account.postbox.storage.messages[id] else { continue }
            acknowledged.insert(id)
            message.attributes = message.attributes.map { attribute in
                if let mention = attribute as? ConsumablePersonalMentionMessageAttribute {
                    return ConsumablePersonalMentionMessageAttribute(consumed: mention.consumed, pending: true)
                }
                return attribute
            }
            account.postbox.storage.messages[id] = message
        }
    }
}
func markUnseenPersonalMessage(transaction: Transaction, id: MessageId, addSynchronizeAction: Bool) { transaction.tagRepairs += 1 }
func clearPeerUnseenPersonalMessagesInteractively(account: Account, peerId: PeerId, threadId: Int64?) -> Signal<Never, NoError> {
    Signal(values: { account.bulkAcknowledgements += 1; return [] })
}
public final class TelegramEngine {
    public final class Messages {
        let account: Account
        init(account: Account) { self.account = account }
        ENGINE_METHOD
    }
    public let messages: Messages
    public init(account: Account) { self.messages = Messages(account: account) }
}
'''.replace('ENGINE_METHOD', engine)

with tempfile.TemporaryDirectory(prefix='regram-filtered-mentions-') as directory:
    work = Path(directory)
    source = work / 'ProductionFilteredMentions.swift'
    source.write_text(adapters + '\n' + lookup + '\n' + policy)
    binary = work / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-warnings-as-errors', str(source), str(tests), '-o', str(binary)], cwd=ROOT, check=True)
    subprocess.run([str(binary)], cwd=ROOT, check=True, timeout=30)
