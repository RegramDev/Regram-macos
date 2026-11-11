import Foundation

func postboxLog(_ value: String) {}

func mdb_cmp_memn(_ lhs: UnsafeRawPointer, _ lhsLength: Int, _ rhs: UnsafeRawPointer, _ rhsLength: Int) -> Int {
    let result = memcmp(lhs, rhs, min(lhsLength, rhsLength))
    return result == 0 ? lhsLength - rhsLength : Int(result)
}

public struct MediaResourceId {}

public struct PeerId: Hashable {
    private let value: Int64

    init(_ value: Int64) { self.value = value }

    func toInt64() -> Int64 { value }
}

struct ValueBoxKey: Hashable {
    let value: String

    init(_ value: String) { self.value = value }
}

enum PinnedItemId: Equatable {
    case peer(PeerId)
}

final class Transaction {
    var preferences: [ValueBoxKey: PreferencesEntry] = [:]
    var inclusions: [PeerId: PeerChatListInclusion] = [:]

    func getPreferencesEntry(key: ValueBoxKey) -> PreferencesEntry? { preferences[key] }

    func updatePreferencesEntry(key: ValueBoxKey, _ update: (PreferencesEntry?) -> PreferencesEntry?) {
        preferences[key] = update(preferences[key])
    }

    func getPeerChatListInclusion(_ peerId: PeerId) -> PeerChatListInclusion { inclusions[peerId] ?? .notIncluded }
}

@main
struct ArchivePlacementTests {
    static func main() {
        let group = PeerId(9_234_567_890)
        let other = PeerId(47)
        let archive = PeerGroupId.group(1)
        let account = Transaction()
        let otherAccount = Transaction()
        var placement = RegramChatListPlacement.read(account)
        let beforeArchive = placement.revision
        let archiveRevision = placement.record(peerId: group, groupId: archive)
        placement.store(account)

        let reopened = Transaction()
        reopened.preferences = account.preferences.mapValues { PreferencesEntry(data: $0.data) }
        placement = RegramChatListPlacement.read(reopened)
        precondition(placement.shouldSend(peerId: group, groupId: archive, revision: archiveRevision))
        precondition(placement.protectedGroup(peerId: group, currentGroup: .root) == archive)
        precondition(RegramChatListPlacement.read(otherAccount).protectedGroup(peerId: group, currentGroup: .root) == nil)
        precondition(!placement.shouldSend(peerId: group, groupId: .root, revision: nil))
        precondition(rgFilterPinnedChatPlacements(transaction: reopened, placement: placement, groupId: .root, itemIds: [.peer(group), .peer(other)], since: beforeArchive) == [.peer(other)])

        let duringArchive = placement.revision
        precondition(placement.finish(peerId: group, groupId: archive, revision: archiveRevision))
        precondition(placement.protectedGroup(peerId: group, currentGroup: archive, since: duringArchive) == archive)
        precondition(placement.protectedGroup(peerId: group, currentGroup: .root, since: duringArchive) == .root)
        precondition(placement.protectedGroup(peerId: group, currentGroup: archive, since: placement.revision) == nil)
        precondition(placement.protectedGroup(peerId: group, currentGroup: archive) == nil)

        let unarchiveRevision = placement.record(peerId: group, groupId: .root)
        let newArchiveRevision = placement.record(peerId: group, groupId: archive)
        precondition(!placement.finish(peerId: group, groupId: .root, revision: unarchiveRevision))
        precondition(!placement.finish(peerId: group, groupId: archive, revision: archiveRevision))
        precondition(placement.shouldSend(peerId: group, groupId: archive, revision: newArchiveRevision))
        precondition(placement.finish(peerId: group, groupId: archive, revision: newArchiveRevision))
        precondition(placement.rememberHidden(peerId: group, groupId: archive))
        placement.store(reopened)
        precondition(rgRestoreChatListGroup(transaction: reopened, peerId: group) == archive)
        precondition(rgRestoreChatListGroup(transaction: reopened, peerId: other) == .root)

        let beforeUnarchive = placement.revision
        let manualUnarchive = placement.record(peerId: group, groupId: .root)
        precondition(placement.finish(peerId: group, groupId: .root, revision: manualUnarchive))
        precondition(placement.protectedGroup(peerId: group, currentGroup: .root, since: beforeUnarchive) == .root)
        precondition(placement.protectedGroup(peerId: group, currentGroup: .root, since: placement.revision) == nil)

        for operation in [
            SynchronizeGroupedPeersOperation(peerId: group, groupId: archive),
            SynchronizeGroupedPeersOperation(peerId: group, groupId: .root, revision: manualUnarchive),
        ] {
            let encoder = PostboxEncoder()
            operation.encode(encoder)
            let decoded = SynchronizeGroupedPeersOperation(decoder: PostboxDecoder(buffer: MemoryBuffer(data: encoder.makeData())))
            precondition(decoded.peerId == operation.peerId && decoded.groupId == operation.groupId && decoded.revision == operation.revision)
        }
        print("Archive placement: stale responses, manual moves, account isolation and Postbox persistence passed")
    }
}
