import XCTest
@testable import RegramCore

final class RegramChatListLayoutPreferencesTests: XCTestCase {
    func testCompactSnapshotsChangeGeometryWithoutChangingChosenBodyLineCount() {
        var settings = RegramAccountSettings()
        let normal = RegramChatListLayoutPreferences(settings: settings)
        settings["compactChatList"] = .bool(true)
        let compact = RegramChatListLayoutPreferences(settings: settings)
        XCTAssertFalse(normal.compact)
        XCTAssertEqual(normal.avatarSize, 50)
        XCTAssertEqual(compact.avatarSize, 34)
        XCTAssertEqual(normal.messageLines, 2)
        XCTAssertEqual(compact.messageLines, 2)
        XCTAssertLessThan(compact.rowHeight(titleHeight: 17, authorHeight: 0, bodyHeight: 34, tagsHeight: 0), normal.rowHeight(titleHeight: 17, authorHeight: 0, bodyHeight: 34, tagsHeight: 0))
        settings["chatListLines"] = .string("1")
        XCTAssertEqual(RegramChatListLayoutPreferences(settings: settings).messageLines, 1)
        XCTAssertEqual(compact.messageLines, 2)
    }

    func testCompactAuthorAndFolderLabelsKeepMeasuredContentInsideRow() {
        var settings = RegramAccountSettings()
        settings["compactChatList"] = .bool(true)
        let layout = RegramChatListLayoutPreferences(settings: settings)
        let regular = layout.rowHeight(titleHeight: 17, authorHeight: 0, bodyHeight: 34, tagsHeight: 0)
        let author = layout.rowHeight(titleHeight: 17, authorHeight: 17, bodyHeight: 34, tagsHeight: 0)
        let tags = layout.rowHeight(titleHeight: 17, authorHeight: 0, bodyHeight: 34, tagsHeight: 17)
        XCTAssertGreaterThan(author, regular)
        XCTAssertGreaterThan(tags, regular)
        XCTAssertGreaterThanOrEqual(author, 17 + 17 + 34 + layout.inset * 2)
        XCTAssertGreaterThanOrEqual(tags, 17 + 34 + 17 + layout.inset * 2)
    }

    func testHidingUnreadCountersChangesSegmentComparisonStateWithoutMutatingInput() {
        let unread = 27
        let visible = RegramFolderBadgePresentation(count: unread, hasUnmutedUnread: true, hidden: false)
        let hidden = RegramFolderBadgePresentation(count: unread, hasUnmutedUnread: true, hidden: true)
        XCTAssertNotEqual(visible, hidden)
        XCTAssertEqual(visible.count, 27)
        XCTAssertEqual(hidden.count, 0)
        XCTAssertFalse(hidden.hasUnmutedUnread)
        XCTAssertEqual(unread, 27)
    }
}
