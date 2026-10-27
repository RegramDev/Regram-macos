import Foundation
import Postbox
import SwiftSignalKit

enum Namespaces {
    enum Peer {
        static let CloudUser = PeerId.Namespace._internalFromInt32Value(0)
        static let CloudGroup = PeerId.Namespace._internalFromInt32Value(1)
        static let CloudChannel = PeerId.Namespace._internalFromInt32Value(2)
        static let SecretChat = PeerId.Namespace._internalFromInt32Value(3)
    }
    enum Message { static let Cloud: Int32 = 0 }
}

final class FixturePeer: Peer {
    let id: PeerId
    var indexName: PeerIndexNameRepresentation { .title(title: "Fixture", addressNames: []) }
    var associatedPeerId: PeerId? { nil }
    var notificationSettingsPeerId: PeerId? { nil }
    var associatedMediaIds: [MediaId]? { nil }
    var timeoutAttribute: UInt32? { nil }
    init(id: PeerId) { self.id = id }
    init(decoder: PostboxDecoder) { id = PeerId(decoder.decodeInt64ForKey("id", orElse: 0)) }
    func encode(_ encoder: PostboxEncoder) { encoder.encodeInt64(id.toInt64(), forKey: "id") }
    func isEqual(_ other: Peer) -> Bool { id == other.id }
}
extension Peer { var isForumOrMonoForum: Bool { false } }

final class Fixture {
    let path = NSTemporaryDirectory() + "regram-filtered-chat-list-postbox-" + UUID().uuidString
    var postbox: Postbox!
    init() {
        declareEncodable(FixturePeer.self, f: FixturePeer.init)
        let seed = SeedConfiguration(globalMessageIdsPeerIdNamespaces: [], initializeChatListWithHole: (nil, nil), messageHoles: [:], upgradedMessageHoles: [:], messageThreadHoles: { _, _ in nil }, existingMessageTags: [], messageTagsWithSummary: [], messageTagsWithThreadSummary: [], existingGlobalMessageTags: [], peerNamespacesRequiringMessageTextIndex: [], peerSummaryCounterTags: { _, _ in PeerSummaryCounterTags(rawValue: 1) }, peerSummaryIsThreadBased: { _, _ in (false, false) }, additionalChatListIndexNamespace: 0, messageNamespacesRequiringGroupStatsValidation: [], defaultMessageNamespaceReadStates: [:], chatMessagesNamespaces: [0], getGlobalNotificationSettings: { _ in nil }, defaultGlobalNotificationSettings: PostboxGlobalNotificationSettings(defaultIncludePeer: { _ in true }), mergeMessageAttributes: { _, _ in }, decodeMessageThreadInfo: { _ in nil }, decodeAutoremoveTimeout: { _ in nil }, decodeDisplayPeerAsRegularChat: { _ in false }, isPeerUpgradeMessage: { _ in false }, automaticThreadIndexInfo: { _, _ in nil }, customTagsFromAttributes: { _ in [] }, displaySavedMessagesAsTopicListPreferencesKey: ValueBoxKey(length: 4))
        let parameters = ValueBoxEncryptionParameters(forceEncryptionIfNoSet: false, key: ValueBoxEncryptionParameters.Key(data: Data(count: 32))!, salt: ValueBoxEncryptionParameters.Salt(data: Data(count: 16))!)
        let done = DispatchSemaphore(value: 0)
        let task = openPostbox(basePath: path, seedConfiguration: seed, encryptionParameters: parameters, timestampForAbsoluteTimeBasedOperations: 1, isMainProcess: true, isTemporary: true, isReadOnly: false, useCopy: false, useCaches: false, removeDatabaseOnError: true).start(next: { result in
            switch result {
            case let .postbox(value): self.postbox = value; done.signal()
            case .error: done.signal()
            case .upgrading: break
            }
        })
        precondition(done.wait(timeout: .now() + 10) == .success && postbox != nil)
        task.dispose()
    }
    func transaction<T>(_ body: @escaping (Transaction) -> T) -> T {
        let done = DispatchSemaphore(value: 0)
        var output: T?
        let task = postbox.transaction(body).start(next: { output = $0 }, completed: { done.signal() })
        precondition(done.wait(timeout: .now() + 10) == .success)
        task.dispose()
        return output!
    }
    func close() {
        postbox = nil
        try? FileManager.default.removeItem(atPath: path)
    }
}

@main
struct NativePostboxChecks {
    static func main() {
        let fixture = Fixture()
        defer { fixture.close() }
        let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(42))
        func id(_ value: Int32) -> MessageId { MessageId(peerId: peerId, namespace: 0, id: value) }
        func stored(_ value: Int32, text: String = "hidden", group: Int64? = nil) -> StoreMessage {
            StoreMessage(id: id(value), customStableId: nil, globallyUniqueId: nil, groupingKey: group, threadId: nil, timestamp: value * 10, flags: .Incoming, tags: [], globalTags: [], localTags: [], forwardInfo: nil, authorId: nil, text: text, attributes: [], media: [])
        }
        let snapshot = fixture.transaction { transaction -> RegramChatListUnreadSnapshot in
            transaction.updatePeersInternal([FixturePeer(id: peerId)], update: { _, updated in updated })
            _ = transaction.addMessages([stored(18, text: "visible"), stored(19), stored(20)], location: .Random)
            transaction.resetIncomingReadStates([peerId: [0: .idBased(maxIncomingReadId: 18, maxOutgoingReadId: 0, maxKnownId: 20, count: 2, markedUnread: false)]])
            return RegramChatListUnreadSnapshot(sourceTop: transaction.getMessage(id(20))!.index, sourceMessages: regramChatListSourceKeys([transaction.getMessage(id(20))!]), readState: transaction.getCombinedPeerReadState(peerId)!)
        }
        func canRead(_ transaction: Transaction, _ value: RegramChatListUnreadSnapshot = snapshot) -> Bool {
            regramChatListCanReadHiddenUnread(transaction: transaction, snapshot: value, isHidden: { $0.text == "hidden" })
        }
        var checks = 0
        func expect(_ value: Bool, _ name: String) { checks += 1; precondition(value, name) }
        expect(fixture.transaction { canRead($0) }, "real Postbox complete hidden unread")
        expect(fixture.transaction { transaction in transaction.addHole(peerId: peerId, threadId: nil, namespace: 0, space: .everywhere, range: 19...19); return !canRead(transaction) }, "real history hole prevents read")
        expect(fixture.transaction { transaction in transaction.removeHole(peerId: peerId, threadId: nil, namespace: 0, space: .everywhere, range: 19...19); return canRead(transaction) }, "real hole fill permits retry")
        expect(fixture.transaction { transaction in transaction.applyMarkUnread(peerId: peerId, namespace: 0, value: true, interactive: false); return !canRead(transaction) && transaction.getCombinedPeerReadState(peerId)!.markedUnread }, "manual unread between snapshot and commit")
        fixture.transaction { $0.applyMarkUnread(peerId: peerId, namespace: 0, value: false, interactive: false) }
        expect(fixture.transaction { transaction in guard canRead(transaction) else { return false }; _ = transaction.applyInteractiveReadMaxIndex(snapshot.sourceTop); return transaction.getCombinedPeerReadState(peerId)!.count == 0 }, "native local read updates real count")
        expect(fixture.transaction { !canRead($0) }, "duplicate expected read state rejects")
        fixture.transaction { transaction in transaction.resetIncomingReadStates([peerId: [0: snapshot.readState.states.first!.1]]) }
        expect(fixture.transaction { transaction in _ = transaction.addMessages([stored(19, text: "visible")], location: .Random); return !canRead(transaction) }, "actual unread edit becomes visible")
        fixture.transaction { transaction in _ = transaction.addMessages([stored(19)], location: .Random) }
        expect(fixture.transaction { transaction in _ = transaction.addMessages([stored(21, text: "visible")], location: .Random); return !canRead(transaction) }, "arrival before conditional transaction rejects old source")
        fixture.transaction { transaction in transaction.deleteMessages([id(21)], forEachMedia: nil); _ = transaction.addMessages([stored(19, group: 7), stored(20, group: 7)], location: .Random); transaction.resetIncomingReadStates([peerId: [0: .idBased(maxIncomingReadId: 18, maxOutgoingReadId: 0, maxKnownId: 20, count: 2, markedUnread: false)]]) }
        let album = fixture.transaction { transaction in RegramChatListUnreadSnapshot(sourceTop: transaction.getMessage(id(20))!.index, sourceMessages: regramChatListSourceKeys(transaction.getMessageGroup(id(20))!), readState: transaction.getCombinedPeerReadState(peerId)!) }
        expect(album.sourceMessages.count == 2 && fixture.transaction { canRead($0, album) }, "real ascending media group complete proof")
        expect(fixture.transaction { transaction in transaction.deleteMessages([id(19)], forEachMedia: nil); return !canRead(transaction, album) }, "real album deletion invalidates proof")
        fixture.transaction { transaction in _ = transaction.addMessages([stored(19)], location: .Random) }
        let historyKey = PostboxViewKey.historyView(.init(peerId: peerId, threadId: nil, clipHoles: false, trackHoles: false, anchor: .upperBound, appendMessagesFromTheSameGroup: false, namespaces: .just([0]), count: 50))
        let historyEvents = DispatchSemaphore(value: 0)
        let historyCount = Atomic(value: 0)
        let historyObserver = fixture.postbox.combinedView(keys: [historyKey]).start(next: { _ in
            _ = historyCount.modify { $0 + 1 }
            historyEvents.signal()
        })
        defer { historyObserver.dispose() }
        expect(historyEvents.wait(timeout: .now() + 5) == .success, "passive native history observer initializes")
        let holesEvents = DispatchSemaphore(value: 0)
        let trackedHoles = Atomic(value: 0)
        let holesObserver = fixture.postbox.messageHistoryHolesView().start(next: { value in
            _ = trackedHoles.swap(value.entries.count)
            holesEvents.signal()
        })
        defer { holesObserver.dispose() }
        precondition(holesEvents.wait(timeout: .now() + 5) == .success)
        fixture.transaction { transaction in transaction.addHole(peerId: peerId, threadId: nil, namespace: 0, space: .everywhere, range: 19...19) }
        expect(historyEvents.wait(timeout: .now() + 5) == .success, "passive native history observer emits for hole insertion")
        expect(trackedHoles.with { $0 } == 0, "passive proof observer does not register network-fetch holes")
        fixture.transaction { transaction in transaction.removeHole(peerId: peerId, threadId: nil, namespace: 0, space: .everywhere, range: 19...19) }
        expect(historyEvents.wait(timeout: .now() + 5) == .success && historyCount.with { $0 } >= 3, "passive native history observer emits for hole filling")
        fixture.transaction { transaction in _ = transaction.addMessages([stored(19, text: "changed")], location: .Random) }
        expect(historyEvents.wait(timeout: .now() + 5) == .success, "passive native history observer emits for same-source history edit")
        let associatedPeer = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(43))
        fixture.transaction { transaction in
            transaction.updatePeersInternal([FixturePeer(id: associatedPeer)], update: { _, updated in updated })
            transaction.resetIncomingReadStates([associatedPeer: [0: .idBased(maxIncomingReadId: 0, maxOutgoingReadId: 0, maxKnownId: 1, count: 1, markedUnread: false)]])
        }
        let associatedEvents = DispatchSemaphore(value: 0)
        let associatedObserver = fixture.postbox.combinedView(keys: [.combinedReadState(peerId: associatedPeer, handleThreads: false)]).start(next: { _ in associatedEvents.signal() })
        defer { associatedObserver.dispose() }
        precondition(associatedEvents.wait(timeout: .now() + 5) == .success)
        fixture.transaction { transaction in transaction.resetIncomingReadStates([associatedPeer: [0: .idBased(maxIncomingReadId: 1, maxOutgoingReadId: 0, maxKnownId: 1, count: 0, markedUnread: false)]]) }
        expect(associatedEvents.wait(timeout: .now() + 5) == .success, "native associated read-state observer emits independently of source")
        print("Passed \(checks) real Postbox filtered chat-list checks")
    }
}
