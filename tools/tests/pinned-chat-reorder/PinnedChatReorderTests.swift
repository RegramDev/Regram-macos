import Foundation
import XCTest
import SwiftSignalKit

private enum EngineChatList {
    enum Group: Equatable {
        case root
        case archive

        func _asGroup() -> Group { self }
    }
}

private enum TogglePeerChatPinnedLocation: Equatable {
    case group(EngineChatList.Group)
    case filter(Int32)
}

private struct ChatLocation {
    let pinnedItemId: Int
}

private final class ChatListRowItem {
    let chatLocation: ChatLocation?

    init(_ id: Int?) {
        chatLocation = id.map { ChatLocation(pinnedItemId: $0) }
    }
}

private final class TableView {
    var items: [AnyObject]

    init(_ ids: [Int?]) { items = ids.map(ChatListRowItem.init) }

    func optionalItem(at index: Int) -> AnyObject? {
        items.indices.contains(index) ? items[index] : nil
    }
}

private final class Peers {
    var ids: [Int]
    var reads: [TogglePeerChatPinnedLocation] = []
    var writes: [TogglePeerChatPinnedLocation] = []

    init(_ ids: [Int]) { self.ids = ids }

    func getPinnedItemIds(location: TogglePeerChatPinnedLocation) -> Signal<[Int], NoError> {
        reads.append(location)
        return .single(ids)
    }

    func reorderPinnedItemIds(location: TogglePeerChatPinnedLocation, itemIds: [Int]) -> Signal<Bool, NoError> {
        writes.append(location)
        ids = itemIds
        return .single(true)
    }
}

private final class ReorderFixture {
    private struct Engine { let peers: Peers }
    private struct Context { let engine: Engine }
    private struct View { let tableView: TableView }
    private struct Mode { let groupId: EngineChatList.Group }
    private enum Filter {
        case allChats
        case filter(Int32, Int, Int, Int)
    }
    private struct FilterValue { let filter: Filter }

    private let context: Context
    private let genericView: View
    private let mode: Mode
    private let filterValue: FilterValue
    private let first = Atomic(value: false)
    private let reorderDisposable = MetaDisposable()

    var peers: Peers { context.engine.peers }

    init(ids: [Int], visibleAfterMove: [Int?], filterId: Int32? = nil, archive: Bool = false) {
        context = Context(engine: Engine(peers: Peers(ids)))
        genericView = View(tableView: TableView(visibleAfterMove))
        mode = Mode(groupId: archive ? .archive : .root)
        filterValue = FilterValue(filter: filterId.map { .filter($0, 0, 0, 0) } ?? .allChats)
    }

    deinit { reorderDisposable.dispose() }

    func resortPinned(_ from: Int, _ to: Int) {
        let context = self.context
__REORDER_BODY__
    }
}

final class PinnedChatReorderTests: XCTestCase {
    func testMovingDownRetainsPinnedChatsOutsideVisibleRows() {
        let fixture = ReorderFixture(ids: [1, 90, 2, 91, 3, 4], visibleAfterMove: [2, 3, 1], filterId: 12)
        fixture.resortPinned(0, 2)
        XCTAssertEqual(fixture.peers.ids, [90, 2, 91, 3, 1, 4])
        XCTAssertEqual(fixture.peers.reads, [.filter(12)])
        XCTAssertEqual(fixture.peers.writes, [.filter(12)])
    }

    func testMovingUpRetainsHiddenAndUnloadedPinnedChats() {
        let fixture = ReorderFixture(ids: [90, 1, 2, 91, 3, 4], visibleAfterMove: [3, 1, 2], filterId: 12)
        fixture.resortPinned(2, 0)
        XCTAssertEqual(fixture.peers.ids, [90, 3, 1, 2, 91, 4])
    }

    func testMissingReferenceAppendsToCompletePinnedList() {
        let fixture = ReorderFixture(ids: [1, 90, 2, 91], visibleAfterMove: [2, nil, 1])
        fixture.resortPinned(0, 2)
        XCTAssertEqual(fixture.peers.ids, [90, 2, 91, 1])
        XCTAssertEqual(fixture.peers.writes, [.group(.root)])
    }

    func testMissingReferencePrependsToCompletePinnedList() {
        let fixture = ReorderFixture(ids: [90, 1, 2, 91], visibleAfterMove: [2, nil, 1], archive: true)
        fixture.resortPinned(2, 0)
        XCTAssertEqual(fixture.peers.ids, [2, 90, 1, 91])
        XCTAssertEqual(fixture.peers.writes, [.group(.archive)])
    }

    func testUnpinnedMovedItemCannotOverwritePinnedOrder() {
        let fixture = ReorderFixture(ids: [1, 2, 90], visibleAfterMove: [1, 3])
        fixture.resortPinned(0, 1)
        XCTAssertEqual(fixture.peers.ids, [1, 2, 90])
        XCTAssertTrue(fixture.peers.writes.isEmpty)
    }

    func testStationaryMissingAndNonChatRowsDoNotRequestOrWrite() {
        for (from, to, rows) in [(0, 0, [1, 2]), (0, 4, [1, 2]), (0, 1, [1, nil])] {
            let fixture = ReorderFixture(ids: [1, 2], visibleAfterMove: rows)
            fixture.resortPinned(from, to)
            XCTAssertTrue(fixture.peers.reads.isEmpty)
            XCTAssertTrue(fixture.peers.writes.isEmpty)
        }
    }
}
