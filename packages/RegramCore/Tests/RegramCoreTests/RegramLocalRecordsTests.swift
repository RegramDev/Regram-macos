import XCTest
@testable import RegramCore

final class RegramLocalRecordsTests: XCTestCase {
    func testBulkBookmarkTagsAndRemovalPreserveOtherAccountsAndReferenceMetadata() throws {
        let suite = "RegramLocalRecordsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let bookmarks = RGMessageBookmarks(defaults: defaults)
        let first = RGBookmarkMessageId(peerId: 9_223_372_036_854_775_000, namespace: 0, id: 2)
        let second = RGBookmarkMessageId(peerId: 20, namespace: 0, id: 3)
        bookmarks.save(accountId: 1, messageId: first, threadId: 42, tags: ["News", "Ｒｅａｄ"], now: 10)
        bookmarks.save(accountId: 1, messageId: second, threadId: nil, tags: ["Keep"], now: 20)
        bookmarks.save(accountId: 2, messageId: first, threadId: 88, tags: ["Private"], now: 30)
        bookmarks.updateTags(accountId: 1, messageIds: [first], adding: ["Today", "today"], removing: ["read"])
        let value = try XCTUnwrap(bookmarks.bookmark(accountId: 1, messageId: first))
        XCTAssertEqual(value.tags, ["News", "Today"])
        XCTAssertEqual(value.addedAt, 10)
        XCTAssertEqual(value.threadId, 42)
        XCTAssertEqual(Set(bookmarks.tags(accountId: 1)), ["News", "Today", "Keep"])
        XCTAssertEqual(bookmarks.bookmark(accountId: 2, messageId: first)?.tags, ["Private"])
        bookmarks.remove(accountId: 1, messageIds: [first, second])
        XCTAssertTrue(bookmarks.bookmarks(accountId: 1).isEmpty)
        XCTAssertNotNil(bookmarks.bookmark(accountId: 2, messageId: first))
        let reopened = RGMessageBookmarks(defaults: defaults)
        XCTAssertEqual(reopened.bookmark(accountId: 2, messageId: first)?.threadId, 88)
    }

    func testAccountCleanupOnlyRemovesSelectedLocalRecords() throws {
        let suite = "RegramLocalRecordsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let remarks = RGGroupRemarks(defaults: defaults)
        let bookmarks = RGMessageBookmarks(defaults: defaults)
        let id = RGBookmarkMessageId(peerId: 5, namespace: 0, id: 6)
        for account in Int64(1)...2 {
            remarks.setName("项目 ＡＢＣ", accountId: account, peerId: 5)
            bookmarks.save(accountId: account, messageId: id, threadId: 7, tags: ["Tag"])
        }
        XCTAssertEqual(remarks.matchingPeerIds(accountId: 1, query: "项目 abc"), [5])
        let revision = remarks.revision(accountId: 1)
        remarks.clear(accountId: 1)
        bookmarks.clear(accountId: 1)
        XCTAssertNil(remarks.name(accountId: 1, peerId: 5))
        XCTAssertGreaterThan(remarks.revision(accountId: 1), revision)
        XCTAssertTrue(bookmarks.bookmarks(accountId: 1).isEmpty)
        XCTAssertEqual(remarks.name(accountId: 2, peerId: 5), "项目 ＡＢＣ")
        XCTAssertNotNil(bookmarks.bookmark(accountId: 2, messageId: id))
        XCTAssertNil(RGGroupRemarks(defaults: defaults).name(accountId: 1, peerId: 5))
    }
}
