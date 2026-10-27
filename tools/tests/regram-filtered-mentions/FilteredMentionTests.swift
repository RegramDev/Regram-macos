import Foundation

@main enum FilteredMentionTests {
    static let peer = PeerId(namespace: Namespaces.Peer.CloudChannel, value: 100)
    static var checks = 0

    static func expect(_ value: @autoclosure () -> Bool, _ description: String) {
        checks += 1
        if !value() { fatalError(description) }
    }

    static func message(_ number: Int32, hidden: Bool = true, peerId: PeerId = peer, threadId: Int64? = nil, incoming: Bool = true, namespace: Int32 = Namespaces.Message.Cloud, tagged: Bool = true, consumed: Bool = false, pending: Bool = false, timestamp: Int32? = nil) -> Message {
        Message(id: MessageId(peerId: peerId, namespace: namespace, id: number), threadId: threadId, timestamp: timestamp ?? number, flags: incoming ? [.IsIncomingMask] : [], tags: tagged ? [.unseenPersonalMessage] : [], attributes: [ConsumablePersonalMentionMessageAttribute(consumed: consumed, pending: pending)], text: hidden ? "blocked" : "visible")
    }

    static func hidden(_ message: Message) -> Bool { message.text == "blocked" }
    static func seed(_ messages: [Message]) -> Account {
        let account = Account()
        account.postbox.storage.messages = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })
        return account
    }
    static func next(_ account: Account, threadId: Int64? = nil) -> [EarliestUnseenPersonalMentionMessageResult] {
        regramEarliestVisiblePersonalMention(account: account, peerId: peer, threadId: threadId, isHidden: hidden).values()
    }

    static func main() {
        let blocked = message(2), visible = message(3, hidden: false), later = message(4)
        let otherPeer = message(1, peerId: PeerId(namespace: Namespaces.Peer.CloudChannel, value: 200))
        let otherTopic = message(1, threadId: 20)
        let currentTopic = message(2, threadId: 10)
        let incoming = [message(1), blocked, visible, later, otherPeer, message(1, incoming: false), message(1, namespace: Namespaces.Message.Local), message(1, tagged: false), message(1, consumed: true), message(1, pending: true)]
        let ids = regramFilteredMentionIdsToRead(messages: incoming, peerId: peer, threadId: nil, readThrough: visible.index, isHidden: hidden)
        expect(ids == [message(1).id, blocked.id], "Reading past a hidden reply consumes its mention without consuming visible, future, outgoing, local or already-acknowledged messages")
        expect(regramFilteredMentionIdsToRead(messages: [blocked], peerId: peer, threadId: nil, readThrough: message(1).index, isHidden: hidden).isEmpty, "Scrolling above a hidden reply must not acknowledge it early")
        expect(regramFilteredMentionIdsToRead(messages: [currentTopic, otherTopic], peerId: peer, threadId: 10, readThrough: message(9).index, isHidden: hidden) == [currentTopic.id], "Topic reads must not consume mentions from a different topic")
        expect(regramFilteredMentionIdsToRead(messages: [blocked], peerId: peer, threadId: nil, readThrough: blocked.index, isHidden: { _ in false }).isEmpty, "Disabled filters, keep rules and temporary reveal must leave visible mentions for normal reading")
        let allHidden = (1...12).map { message(Int32($0)) }
        expect(regramFilteredMentionIdsToRead(messages: allHidden, peerId: peer, threadId: nil, readThrough: allHidden.last!.index, isHidden: hidden).count == 12, "An all-filtered loaded window can acknowledge its entire read prefix without item nodes")
        let timestampLater = message(1, timestamp: 100)
        expect(regramFilteredMentionIdsToRead(messages: [timestampLater], peerId: peer, threadId: nil, readThrough: message(9).index, isHidden: hidden).isEmpty, "Use the actual read index, not just the numeric message id")

        let mixed = seed([blocked, visible, later, otherPeer])
        expect(next(mixed) == [.result(visible.id)], "@ must skip a filtered reply and navigate to the next visible one")
        expect(mixed.viewTracker.acknowledged == [blocked.id], "Only hidden mentions before the next visible destination are acknowledged")
        expect(mixed.postbox.storage.messages[blocked.id]!.tags.contains(.unseenPersonalMessage), "Regression fixture must retain tags while server acknowledgement is pending")
        expect(next(mixed) == [.result(visible.id)], "A second tap while offline must not get stuck on the pending hidden reply")
        expect(mixed.bulkAcknowledgements == 0 && mixed.postbox.storage.summaryResets == 0, "Skipping filtered messages must not bulk-clear remaining visible mentions")

        let many = seed(allHidden + [message(13, hidden: false), message(14)])
        expect(next(many) == [.result(message(13).id)], "Navigation must pass more filtered replies than the four-entry lookup page")
        expect(many.viewTracker.acknowledged == Set(allHidden.map(\.id)), "Every skipped hidden reply is acknowledged individually")
        expect(!many.viewTracker.acknowledged.contains(message(14).id), "Do not consume a later hidden reply beyond the visible destination")

        let onlyHidden = seed(allHidden)
        expect(next(onlyHidden) == [.result(nil)], "All-filtered mentions finish navigation without an unreachable destination")
        expect(onlyHidden.viewTracker.acknowledged == Set(allHidden.map(\.id)), "All-filtered navigation schedules every individual acknowledgement")
        expect(onlyHidden.bulkAcknowledgements == 0 && onlyHidden.postbox.storage.summaryResets == 0 && onlyHidden.postbox.storage.holeRemovals == 0, "Exhausting an ignored-id query must not reset summaries or remove tag holes")

        let topic = seed([currentTopic, otherTopic, message(3, hidden: false, threadId: 10)])
        expect(next(topic, threadId: 10) == [.result(message(3, threadId: 10).id)], "@ navigation must stay inside the requested topic")
        expect(topic.viewTracker.acknowledged == [currentTopic.id], "Another topic's hidden mention must remain unread")

        let loading = seed([blocked])
        loading.viewTracker.isLoading = true
        expect(next(loading) == [.loading] && loading.viewTracker.acknowledged.isEmpty, "A loading lookup must not acknowledge an unverified message")
        let invalidated = seed([Message(id: blocked.id, threadId: nil, timestamp: 2, flags: [.IsIncomingMask], tags: [.unseenPersonalMessage], attributes: [ConsumablePersonalMentionMessageAttribute(consumed: false, pending: false), ChannelMessageStateVersionAttribute(pts: 5)], text: "blocked")])
        invalidated.viewTracker.invalidatedPts = 10
        expect(next(invalidated) == [.loading] && invalidated.viewTracker.acknowledged.isEmpty, "Preserve upstream channel-state validation before filtering")
        let hole = seed([blocked, visible])
        hole.viewTracker.fillHoleOnce = true
        expect(next(hole) == [.result(visible.id)], "Filling a history hole must preserve ignored ids")
        expect(hole.viewTracker.ignoredLookups.suffix(2).allSatisfy { $0 == [blocked.id] }, "A fill-hole retry must not start again from the filtered message")

        let ordinary = seed([visible])
        expect(next(ordinary) == [.result(visible.id)] && ordinary.viewTracker.acknowledged.isEmpty, "Visible mention navigation must keep its existing behavior")
        let staleSummary = seed([message(1, tagged: false)])
        expect(TelegramEngine(account: staleSummary).messages.earliestUnseenPersonalMentionMessage(peerId: peer, threadId: nil).values() == [.result(nil)], "An ordinary empty lookup still completes")
        expect(staleSummary.bulkAcknowledgements == 1 && staleSummary.postbox.storage.summaryResets == 1, "Keep the existing unfiltered stale-summary repair")
        print("Filtered mention checks passed: \(checks) assertions; read ranges, filtering, topics, pending/offline acknowledgements, multi-page navigation, loading/channel validation and hole retries")
    }
}
