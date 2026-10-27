import Foundation
import XCTest
import Postbox
import TelegramCore
import ChatHistoryModel
import RegramCore

final class RegramFilteredReadingTests: XCTestCase {
    private let peerId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(10))

    private func message(_ id: Int32, text: String = "hidden", threadId: Int64? = nil, version: UInt32 = 0, incoming: Bool = true, tagged: Bool = true, pending: Bool = false, consumed: Bool = false) -> Message {
        Message(stableId: UInt32(id), stableVersion: version, id: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: id), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: threadId, timestamp: id, flags: incoming ? [.Incoming] : [], tags: tagged ? [.unseenPersonalMessage] : [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: nil, text: text, attributes: [ConsumablePersonalMentionMessageAttribute(consumed: consumed, pending: pending)], media: [], peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    func testFilteredTailAdvancesOnlyAtTheLatestEdge() {
        let visible = message(1, text: "visible")
        let hidden = [message(2), message(3)]
        let predicate: (Message) -> Bool = { $0.text == "hidden" }
        XCTAssertEqual(regramReadIndexIncludingFilteredTail(messages: [visible] + hidden, visibleReadIndex: visible.index, atLatest: false, isHidden: predicate), visible.index)
        XCTAssertEqual(regramReadIndexIncludingFilteredTail(messages: [visible] + hidden, visibleReadIndex: visible.index, atLatest: true, isHidden: predicate), hidden.last?.index)
        XCTAssertEqual(regramReadIndexIncludingFilteredTail(messages: hidden, visibleReadIndex: nil, atLatest: true, isHidden: predicate), hidden.last?.index)
        XCTAssertNil(regramReadIndexIncludingFilteredTail(messages: hidden, visibleReadIndex: nil, atLatest: false, isHidden: predicate))
        XCTAssertEqual(regramReadIndexIncludingFilteredTail(messages: [visible, message(2), message(3, text: "visible")], visibleReadIndex: visible.index, atLatest: true, isHidden: predicate), visible.index)
    }

    func testFilteredMentionsRespectReadPositionTopicAndConsumptionState() {
        let visible = message(3, text: "visible", threadId: 10)
        let entries = [message(1, threadId: 10), message(2, threadId: 20), visible, message(4, threadId: 10), message(1, threadId: 10, incoming: false), message(1, threadId: 10, tagged: false), message(1, threadId: 10, pending: true), message(1, threadId: 10, consumed: true)]
        let ids = regramFilteredMentionIdsToRead(messages: entries, peerId: peerId, threadId: 10, readThrough: visible.index, isHidden: { $0.text == "hidden" })
        XCTAssertEqual(ids, [message(1).id])
        XCTAssertTrue(regramFilteredMentionIdsToRead(messages: entries, peerId: peerId, threadId: 10, readThrough: visible.index, isHidden: { _ in false }).isEmpty)
        XCTAssertTrue(regramFilteredMentionIdsToRead(messages: [message(4, threadId: 10)], peerId: peerId, threadId: 10, readThrough: visible.index, isHidden: { _ in true }).isEmpty)
    }

    func testFilterCacheInvalidatesForMessageEditsAndRuleChanges() {
        let accountId = Int64.min + 283369
        defer { RegramPreferences.shared.removeAccount(accountId) }
        RegramPreferences.shared.update(accountId: accountId) { $0["messageFilterRules"] = .string(RGMessageFilter.encode([RGMessageFilterRule(pattern: "hidden")])) }
        XCTAssertTrue(regramShouldHideMessage(message(1), accountId: accountId))
        XCTAssertFalse(regramShouldHideMessage(message(1, text: "edited", version: 1), accountId: accountId))
        RegramPreferences.shared.update(accountId: accountId) { $0["messageFilterRules"] = .string("[]") }
        XCTAssertFalse(regramShouldHideMessage(message(1), accountId: accountId))
    }
}
