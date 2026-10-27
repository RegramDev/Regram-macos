import Foundation

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    checks += 1
    guard condition() else { fatalError("Failed: \(name)") }
}

let peer = PeerId(namespace: Namespaces.Peer.CloudUser, value: 42)
let otherPeer = PeerId(namespace: Namespaces.Peer.CloudUser, value: 43)
func message(_ id: Int32, text: String = "hidden", peerId: PeerId = peer, namespace: Int32 = Namespaces.Message.Cloud, timestamp: Int32? = nil) -> Message {
    Message(id: MessageId(peerId: peerId, namespace: namespace, id: id), timestamp: timestamp ?? id * 10, text: text)
}
func state(read: Int32 = 18, count: Int32 = 2, marked: Bool = false, known: Int32 = 20) -> CombinedPeerReadState {
    CombinedPeerReadState(states: [(Namespaces.Message.Cloud, .idBased(maxIncomingReadId: read, maxOutgoingReadId: 0, maxKnownId: known, count: count, markedUnread: marked))])
}
func fixture() -> (Account, RegramChatListUnreadSnapshot) {
    let account = Account()
    let transaction = account.postbox.storage
    transaction.peers[peer] = Peer(id: peer)
    for value in [message(18, text: "visible"), message(19), message(20)] { transaction.messages[value.id] = value }
    transaction.readStates[peer] = state()
    return (account, RegramChatListUnreadSnapshot(sourceTop: message(20).index, sourceMessages: regramChatListSourceKeys([message(20)]), readState: state()))
}
func proof(_ transaction: Transaction, _ snapshot: RegramChatListUnreadSnapshot) -> Bool {
    regramChatListCanReadHiddenUnread(transaction: transaction, snapshot: snapshot, isHidden: { $0.text == "hidden" && !$0.flags.intersection(.IsIncomingMask).isEmpty })
}
func rejected(_ name: String, _ mutate: (Transaction) -> Void) {
    let (account, snapshot) = fixture()
    mutate(account.postbox.storage)
    expect(!proof(account.postbox.storage, snapshot), name)
}

let (base, snapshot) = fixture()
expect(proof(base.postbox.storage, snapshot), "complete hidden incoming tail")
expect(snapshot.sourceTop == message(20).index, "read target remains hidden source top")
rejected("visible unread", { $0.messages[message(19).id]?.text = "visible" })
rejected("manually marked unread stale snapshot", { $0.readStates[peer] = state(marked: true) })
rejected("count changed", { $0.readStates[peer] = state(count: 3) })
rejected("source edit", { $0.messages[message(20).id]?.stableVersion += 1 })
rejected("source deletion", { $0.messages.removeValue(forKey: message(20).id) })
rejected("new visible arrival", { $0.messages[message(21).id] = message(21, text: "visible") })
rejected("new local outgoing", { transaction in var local = message(5, namespace: Namespaces.Message.Local, timestamp: 300); local.flags = []; transaction.messages[local.id] = local })
rejected("missing unread record", { $0.messages.removeValue(forKey: message(19).id) })
rejected("hole at unread boundary", { $0.holes[peer] = IndexSet(integer: 19) })
rejected("hole at top", { $0.holes[peer] = IndexSet(integer: 20) })
rejected("hole over whole suffix", { $0.holes[peer] = IndexSet(integersIn: 18..<22) })
rejected("associated peer visible unread", { transaction in transaction.cached[peer] = CachedPeerData(associatedHistoryMessageId: message(1, peerId: otherPeer).id); transaction.readStates[otherPeer] = state(read: 0, count: 1, known: 1) })
rejected("associated peer manually unread", { transaction in transaction.cached[peer] = CachedPeerData(associatedHistoryMessageId: message(1, peerId: otherPeer).id); transaction.readStates[otherPeer] = state(count: 0, marked: true) })
rejected("associated peer missing native read state", { $0.cached[peer] = CachedPeerData(associatedHistoryMessageId: message(1, peerId: otherPeer).id) })
rejected("other namespace unread", { transaction in transaction.readStates[peer] = CombinedPeerReadState(states: state().states + [(Namespaces.Message.Local, .idBased(maxIncomingReadId: 0, maxOutgoingReadId: 0, maxKnownId: 1, count: 1, markedUnread: false))]) })
rejected("other namespace manual unread", { transaction in transaction.readStates[peer] = CombinedPeerReadState(states: state().states + [(Namespaces.Message.Local, .idBased(maxIncomingReadId: 0, maxOutgoingReadId: 0, maxKnownId: 1, count: 0, markedUnread: true))]) })
rejected("forum aggregate is topic count", { $0.peers[peer]?.isForumOrMonoForum = true })
rejected("mono forum aggregate unknown", { $0.peers[peer]?.isForumOrMonoForum = true })
rejected("threaded bot aggregate unknown", { $0.peers[peer]?.isForumOrMonoForum = true })
rejected("duplicate recent ids", { $0.recentOverride = [message(20), message(19), message(19)] })
rejected("foreign recent peer", { $0.recentOverride = [message(20), message(19, peerId: otherPeer)] })
rejected("outgoing source", { $0.messages[message(20).id]?.flags = [] })

for value in [state(count: 0, marked: true), state(marked: true), state(read: 19), state(count: 51), state(known: 21)] {
    let (account, _) = fixture()
    account.postbox.storage.readStates[peer] = value
    expect(!proof(account.postbox.storage, RegramChatListUnreadSnapshot(sourceTop: snapshot.sourceTop, sourceMessages: snapshot.sourceMessages, readState: value)), "current invalid native read state")
}
base.postbox.storage.holes[peer] = IndexSet(integersIn: 1..<19)
expect(proof(base.postbox.storage, snapshot), "holes below unread boundary allowed")
base.postbox.storage.cached[peer] = CachedPeerData(associatedHistoryMessageId: message(1, peerId: otherPeer).id)
base.postbox.storage.readStates[otherPeer] = state(count: 0)
expect(proof(base.postbox.storage, snapshot), "known fully read associated peer allowed")
for otherState in [PeerReadState.idBased(maxIncomingReadId: 0, maxOutgoingReadId: 0, maxKnownId: 1, count: 1, markedUnread: false), .idBased(maxIncomingReadId: 0, maxOutgoingReadId: 0, maxKnownId: 1, count: 0, markedUnread: true)] {
    let (account, _) = fixture()
    let combined = CombinedPeerReadState(states: state().states + [(Namespaces.Message.Local, otherState)])
    account.postbox.storage.readStates[peer] = combined
    expect(!proof(account.postbox.storage, RegramChatListUnreadSnapshot(sourceTop: snapshot.sourceTop, sourceMessages: snapshot.sourceMessages, readState: combined)), "current matching read state with other namespace unread rejected")
}
let incomplete = fixture().0.postbox.storage
incomplete.recentOverride = [message(20)]
expect(!proof(incomplete, snapshot), "bounded latest snapshot incomplete")

let group = fixture().0.postbox.storage
group.messages[message(19).id]?.groupingKey = 9
group.messages[message(20).id]?.groupingKey = 9
let groupMessages = [group.messages[message(19).id]!, group.messages[message(20).id]!]
let groupSnapshot = RegramChatListUnreadSnapshot(sourceTop: message(20).index, sourceMessages: regramChatListSourceKeys(groupMessages), readState: state())
expect(regramChatListSourceKeys(groupMessages) == regramChatListSourceKeys(groupMessages.reversed()), "complete album key independent of order")
expect(regramChatListSourceTop(groupMessages)?.id == message(20).id && regramChatListSourceTop(groupMessages.reversed())?.id == message(20).id, "actual source top independent of album order")
expect(regramChatListPreviewUpperBound(groupMessages) == message(19).index && regramChatListPreviewUpperBound(groupMessages.reversed()) == message(19).index, "scan and remote offset start before complete album")
expect(proof(group, groupSnapshot), "all hidden complete media group")
expect(!proof(group, snapshot), "source album member added after request")
group.messages[message(19).id]?.text = "visible"
expect(!proof(group, groupSnapshot), "mixed media group retains unread")
group.messages.removeValue(forKey: message(19).id)
expect(!proof(group, groupSnapshot), "source album member deleted after request")

for namespace in [Namespaces.Peer.SecretChat, 99] {
    let id = PeerId(namespace: namespace, value: 42)
    let top = message(20, peerId: id)
    expect(!proof(base.postbox.storage, RegramChatListUnreadSnapshot(sourceTop: top.index, sourceMessages: regramChatListSourceKeys([top]), readState: state())), "unsupported peer namespace")
}
for namespace in [Namespaces.Message.Local, Namespaces.Message.ScheduledCloud] {
    let top = message(20, namespace: namespace)
    expect(!proof(base.postbox.storage, RegramChatListUnreadSnapshot(sourceTop: top.index, sourceMessages: regramChatListSourceKeys([top]), readState: state())), "unsupported source namespace")
}

let native = ChatListIndex(pinningIndex: nil, messageIndex: message(20).index)
let visible = message(10, text: "visible").index
expect(regramChatListDisplayIndex(native: native, sourceTop: native.messageIndex, replacement: visible, pagingFloor: nil).messageIndex == visible, "replacement reorders ordinary row")
let pinned = ChatListIndex(pinningIndex: 4, messageIndex: native.messageIndex)
expect(regramChatListDisplayIndex(native: pinned, sourceTop: native.messageIndex, replacement: visible, pagingFloor: nil) == pinned, "pinned position")
let draft = ChatListIndex(pinningIndex: nil, messageIndex: MessageIndex(id: native.messageIndex.id, timestamp: 300))
expect(regramChatListDisplayIndex(native: draft, sourceTop: native.messageIndex, replacement: visible, pagingFloor: nil) == draft, "newer draft or media draft position")
let floor = message(9, peerId: otherPeer, timestamp: 150).index
let clamped = regramChatListDisplayIndex(native: native, sourceTop: native.messageIndex, replacement: visible, pagingFloor: floor)
expect(clamped.messageIndex.timestamp == 150 && clamped.messageIndex.id == visible.id, "floor clamp preserves own peer and message id")
let tieFloor = message(11, peerId: otherPeer, timestamp: 150).index
expect(regramChatListDisplayIndex(native: native, sourceTop: native.messageIndex, replacement: visible, pagingFloor: tieFloor) == native, "equal timestamp unsafe id tie preserves native")
expect(regramChatListDisplayIndex(native: native, sourceTop: native.messageIndex, replacement: message(10, peerId: otherPeer).index, pagingFloor: nil) == native, "foreign replacement rejected")

func item(_ index: ChatListIndex, top: Message = message(20)) -> EngineChatList.Item {
    EngineChatList.Item(id: .chatList(peer), index: .chatList(index), messages: [EngineMessage(message: top)], readCounters: EnginePeerReadCounters(state: state()), isMuted: true, draft: "draft", threadData: "thread", renderedPeer: "peer", presence: "presence", hasUnseenMentions: true, hasUnseenReactions: true, hasUnseenPollVotes: true, forumTopicData: "topic", topForumTopicItems: ["topTopic"], hasFailed: true, isContact: true, autoremoveTimeout: 30, storyStats: "story", displayAsTopicList: true, isPremiumRequiredToMessage: true, mediaDraftContentType: .video)
}
let original = item(native)
let substituted = regramChatListItemWithDisplayIndex(original, ChatListIndex(pinningIndex: nil, messageIndex: visible))
expect(regramChatListItemWithDisplayIndex(substituted, native) == original, "all item fields survive clone")
expect(regramChatListPagingFloor(EngineChatList(items: [item(pinned), original], hasEarlier: true)) == native.messageIndex, "paging floor ignores pinned")
expect(regramChatListPagingFloor(EngineChatList(items: [original], hasEarlier: false)) == nil, "no earlier page has no floor")

var settings = RegramAccountSettings()
settings.filterRules = [RGMessageFilterRule(pattern: "hidden")]
let filter = RegramFilterSnapshot(settings: settings)
expect(regramChatListMessageIsHidden(message(20), filter: filter), "actual filter classification")
expect(!regramChatListMessageIsHidden(message(18, text: "visible"), filter: filter), "actual visible classification")
var outgoing = message(20); outgoing.flags = []
expect(!regramChatListMessageIsHidden(outgoing, filter: filter), "actual filter keeps outgoing")

let suite = "Regram.FilteredChatList.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName: suite)!
defer { defaults.removePersistentDomain(forName: suite) }
let preferences = RegramPreferences(defaults: defaults)
let reveal = RegramTemporaryReveal()
let testPreferences = preferences
let testReveal = reveal
let accountId: Int64 = 98123
func request(_ snapshot: RegramChatListUnreadSnapshot, revision: Int64? = nil) -> UnreadRequest {
    UnreadRequest(id: 1, source: UnreadSource(accountId: accountId, preferencesRevision: revision ?? preferences.revision(accountId: accountId)), snapshot: snapshot)
}
func submitFixture(_ account: Account, _ request: UnreadRequest, lease: Atomic<[Int: UnreadRequest]?>? = nil) -> Bool {
    submit(account: account, request: request, lease: lease ?? Atomic(value: [request.id: request]), filter: filter, preferences: preferences, reveal: reveal)
}
let (readAccount, readSnapshot) = fixture()
let readRequest = request(readSnapshot)
expect(submitFixture(readAccount, readRequest), "conditional bridge commits native read")
expect(readAccount.postbox.storage.applied == [readSnapshot.sourceTop], "native target source top, not visible index")
expect(!submitFixture(readAccount, readRequest), "second folder request rejected atomically")
let (retryAccount, retrySnapshot) = fixture()
retryAccount.postbox.storage.holes[peer] = IndexSet(integer: 19)
expect(!submitFixture(retryAccount, request(retrySnapshot)), "incomplete request rejected")
retryAccount.postbox.storage.holes[peer] = []
expect(submitFixture(retryAccount, request(retrySnapshot)), "same request retry after hole filling")
let (staleAccount, staleSnapshot) = fixture()
expect(!submitFixture(staleAccount, request(staleSnapshot), lease: Atomic(value: nil)), "disposed or replaced lifecycle lease")
let disposedLease = Atomic<[Int: UnreadRequest]?>(value: nil)
_ = disposedLease.modify { $0 == nil ? nil : [1: request(staleSnapshot)] }
expect(!submitFixture(staleAccount, request(staleSnapshot), lease: disposedLease), "in-progress update cannot revive disposed lease")
let oldRequest = request(staleSnapshot)
preferences.update(accountId: accountId) { $0["warnOnStoriesOpen"] = .bool(!$0["warnOnStoriesOpen"].bool) }
expect(!submitFixture(staleAccount, oldRequest), "old policy revision cannot commit")
reveal.setRevealed(true, accountId: accountId, peerId: peer.toInt64())
expect(!submitFixture(staleAccount, request(staleSnapshot)), "temporary reveal prevents commit")
reveal.setRevealed(false, accountId: accountId, peerId: peer.toInt64())

let entered = DispatchSemaphore(value: 0)
let release = DispatchSemaphore(value: 0)
let committed = DispatchSemaphore(value: 0)
let preferenceDone = DispatchSemaphore(value: 0)
let revealDone = DispatchSemaphore(value: 0)
let guardedRequest = request(staleSnapshot)
staleAccount.postbox.storage.beforeNativeApply = { entered.signal(); precondition(release.wait(timeout: .now() + 5) == .success) }
DispatchQueue.global().async { _ = submitFixture(staleAccount, guardedRequest); committed.signal() }
expect(entered.wait(timeout: .now() + 5) == .success, "commit holds current policy lease")
DispatchQueue.global().async { preferences.update(accountId: accountId) { $0["warnOnStoriesOpen"] = .bool(!$0["warnOnStoriesOpen"].bool) }; preferenceDone.signal() }
DispatchQueue.global().async { reveal.setRevealed(true, accountId: accountId, peerId: peer.toInt64()); revealDone.signal() }
expect(preferenceDone.wait(timeout: .now() + 0.02) == .timedOut, "preference mutation waits for native commit")
expect(revealDone.wait(timeout: .now() + 0.02) == .timedOut, "reveal mutation waits for native commit")
release.signal()
expect(committed.wait(timeout: .now() + 5) == .success, "native commit completes without lock cycle")
expect(preferenceDone.wait(timeout: .now() + 5) == .success, "preference writer resumes")
expect(revealDone.wait(timeout: .now() + 5) == .success, "reveal writer resumes")

let stress = DispatchGroup()
for operation in 0..<3 {
    stress.enter()
    DispatchQueue.global().async {
        for _ in 0..<500 {
            switch operation {
            case 0: preferences.update(accountId: accountId) { $0["warnOnStoriesOpen"] = .bool(!$0["warnOnStoriesOpen"].bool) }
            case 1: reveal.setRevealed(false, accountId: accountId, peerId: peer.toInt64())
            default:
                _ = preferences.withCurrentRevision(accountId: accountId, revision: preferences.revision(accountId: accountId)) {
                    _ = reveal.withUnrevealed(accountId: accountId, peerId: peer.toInt64()) { 1 }
                }
            }
        }
        stress.leave()
    }
}
expect(stress.wait(timeout: .now() + 10) == .success, "concurrent revision reveal native lock ordering")

preferences.update(accountId: accountId) { $0.filterRules = settings.filterRules }
func scheduledRequests(_ account: Account, ids: ClosedRange<Int>, readable: Set<Int>) -> [UnreadRequest] {
    ids.map { index in
        let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, value: Int64(1000 + index))
        account.postbox.storage.peers[peerId] = Peer(id: peerId)
        let messages = [message(18, text: "visible", peerId: peerId), message(19, peerId: peerId), message(20, peerId: peerId)]
        for value in messages { account.postbox.storage.messages[value.id] = value }
        account.postbox.storage.readStates[peerId] = state()
        account.postbox.storage.holes[peerId] = readable.contains(index) ? [] : IndexSet(integer: 19)
        return UnreadRequest(id: index, source: UnreadSource(accountId: accountId, preferencesRevision: preferences.revision(accountId: accountId)), snapshot: RegramChatListUnreadSnapshot(sourceTop: messages[2].index, sourceMessages: regramChatListSourceKeys([messages[2]]), readState: state()))
    }
}
func drainScheduling(_ fixture: SchedulingFixture) -> Int {
    var steps = 0
    var maximumInFlight = fixture.unreadDisposables.count
    while prepareQueue.runNext() {
        steps += 1
        precondition(steps < 200, "scheduler retried a failed key indefinitely")
        maximumInFlight = max(maximumInFlight, fixture.unreadDisposables.count)
    }
    return maximumInFlight
}
prepareQueue.reset()
let scheduledAccount = Account()
let scheduled = SchedulingFixture(account: scheduledAccount, accountId: accountId, preferences: preferences, reveal: reveal)
let candidates = scheduledRequests(scheduledAccount, ids: 1...17, readable: [17])
scheduled.update(candidates)
expect(drainScheduling(scheduled) <= 2, "production unread scheduler keeps two concurrent checks")
expect(prepareQueue.startCalls == 33 && scheduledAccount.postbox.storage.transactionRuns == 66, "all candidates finish with at most one initial observation recheck")
expect(scheduledAccount.postbox.storage.applied == [candidates[16].snapshot.sourceTop], "first sixteen false still reaches readable seventeenth")
expect(prepareQueue.continuationDispatches == 2, "production scheduler yields after sixteen starts")
expect(scheduled.pendingUnread.isEmpty && scheduled.unreadDisposables.isEmpty, "completed failures are not self-requeued")

prepareQueue.reset()
let manyAccount = Account()
let many = SchedulingFixture(account: manyAccount, accountId: accountId, preferences: preferences, reveal: reveal)
let manyCandidates = scheduledRequests(manyAccount, ids: 1...33, readable: [17, 33])
many.update(manyCandidates)
expect(drainScheduling(many) <= 2 && prepareQueue.startCalls == 64 && manyAccount.postbox.storage.transactionRuns == 128, "all candidates across batches have one attempt per evidence epoch")
expect(prepareQueue.continuationDispatches == 3, "each sixteen starts yields to prepare queue")
expect(manyAccount.postbox.storage.applied == [manyCandidates[16].snapshot.sourceTop, manyCandidates[32].snapshot.sourceTop], "later batches finish without an external update")

prepareQueue.reset()
let stoppedAccount = Account()
let stopped = SchedulingFixture(account: stoppedAccount, accountId: accountId, preferences: preferences, reveal: reveal)
stopped.update(scheduledRequests(stoppedAccount, ids: 1...33, readable: [17, 33]))
while prepareQueue.continuationDispatches == 0 { precondition(prepareQueue.runNext()) }
let startsBeforeDispose = prepareQueue.startCalls
stopped.dispose()
_ = drainScheduling(stopped)
expect(startsBeforeDispose == 16 && prepareQueue.startCalls == startsBeforeDispose, "dispose prevents deferred batch replenishment")
expect(stoppedAccount.postbox.storage.applied.isEmpty, "disposed continuation never reaches later readable candidates")

prepareQueue.reset()
let replacedAccount = Account()
let replaced = SchedulingFixture(account: replacedAccount, accountId: accountId, preferences: preferences, reveal: reveal)
replaced.update(scheduledRequests(replacedAccount, ids: 1...33, readable: [17, 33]))
while prepareQueue.continuationDispatches == 0 { precondition(prepareQueue.runNext()) }
let newerCandidates = scheduledRequests(replacedAccount, ids: 50...51, readable: [50, 51])
replaced.update(newerCandidates)
expect(drainScheduling(replaced) <= 2, "new update retains concurrency bound")
expect(prepareQueue.startCalls == 18, "new update replaces old pending candidates")
expect(Set(replacedAccount.postbox.storage.applied) == Set(newerCandidates.map { $0.snapshot.sourceTop }), "stale continuation cannot restore previous pending batch")
expect(replaced.pendingUnread.isEmpty && replaced.unreadDisposables.isEmpty, "replacement update completes without more source updates")
resetVisibilityCache()
let performanceAccount: Int64 = 998123
let performanceRevision: Int64 = 111
let emptyFilter = RegramFilterSnapshot(settings: RegramAccountSettings())
let textBeforeEmpty = TestCounters.shared.count("text")
let matchesBeforeEmpty = TestCounters.shared.count("matches")
var fastPathsVisible = true
for _ in 0..<200 {
    fastPathsVisible = !regramShouldHideMessage(message(20), accountId: performanceAccount, filter: emptyFilter, revision: performanceRevision) && !regramShouldHideMessage(outgoing, accountId: performanceAccount, filter: filter, revision: performanceRevision) && fastPathsVisible
}
expect(fastPathsVisible, "empty and outgoing remain visible")
expect(TestCounters.shared.count("text") == textBeforeEmpty && TestCounters.shared.count("matches") == matchesBeforeEmpty, "empty and outgoing skip text extraction and regex")
var whitelistSettings = settings
whitelistSettings["messageFilterDisabledPeerIds"] = .strings([String(peer.toInt64())])
let whitelistFilter = RegramFilterSnapshot(settings: whitelistSettings)
expect(!regramShouldHideMessage(message(20), accountId: performanceAccount, filter: whitelistFilter, revision: performanceRevision), "whitelisted chat visible")
expect(TestCounters.shared.count("text") == textBeforeEmpty && TestCounters.shared.count("matches") == matchesBeforeEmpty, "whitelist skips text extraction and regex")
whitelistSettings["blockedPeerIds"] = .strings([String(otherPeer.toInt64())])
var fromHiddenAuthor = message(21); fromHiddenAuthor.author = Peer(id: otherPeer)
expect(regramShouldHideMessage(fromHiddenAuthor, accountId: performanceAccount, filter: RegramFilterSnapshot(settings: whitelistSettings), revision: performanceRevision), "hidden author still precedes whitelist")
expect(TestCounters.shared.count("text") == textBeforeEmpty, "hidden author skips text expansion")
resetVisibilityCache()
let textBeforeRepeated = TestCounters.shared.count("text")
let matchesBeforeRepeated = TestCounters.shared.count("matches")
for _ in 0..<200 { _ = regramShouldHideMessage(message(20), accountId: performanceAccount, filter: filter, revision: performanceRevision) }
expect(TestCounters.shared.count("text") - textBeforeRepeated == 1 && TestCounters.shared.count("matches") - matchesBeforeRepeated == 1, "two hundred stable classifications share one text extraction and regex")
let changedText = message(20).withUpdatedText("visible")
expect(changedText.stableVersion == message(20).stableVersion && !regramShouldHideMessage(changedText, accountId: performanceAccount, filter: filter, revision: performanceRevision), "same-version updated text invalidates decision")
let richAttribute = RichTextMessageAttribute(InstantPage(["hidden"]))
let richMessage = message(25, text: "visible").withUpdatedAttributes([richAttribute])
expect(regramShouldHideMessage(richMessage, accountId: performanceAccount, filter: filter, revision: performanceRevision), "rich block participates in text filtering")
let richPrepared = RegramChatListPreparedVisibility(messages: [richMessage], accountId: performanceAccount, filter: filter, revision: performanceRevision)
let originalPayload = RegramMessageFilterPayload(richMessage)
richAttribute.fullInstantPage = InstantPage(["visible"])
expect(originalPayload != RegramMessageFilterPayload(richMessage), "mutable full-page replacement cannot alter captured blocks")
expect(!regramShouldHideMessage(richMessage, accountId: performanceAccount, filter: filter, revision: performanceRevision), "same-version full-page replacement invalidates decision")
expect(!richPrepared.isHidden(richMessage), "preclassified full-page replacement fails closed")
let replacedAttributes = richMessage.withUpdatedAttributes([RichTextMessageAttribute(InstantPage(["hidden"]))])
expect(regramShouldHideMessage(replacedAttributes, accountId: performanceAccount, filter: filter, revision: performanceRevision), "same-version replaced attributes invalidate decision")
let textPrepared = RegramChatListPreparedVisibility(messages: [message(20)], accountId: performanceAccount, filter: filter, revision: performanceRevision)
expect(!textPrepared.isHidden(changedText), "preclassified updated text fails closed")
expect(!textPrepared.isHidden(message(30)), "unclassified new message fails closed")
var onlyMediaChanged = message(20); onlyMediaChanged.media = ["unfiltered-media"]
expect(textPrepared.isHidden(onlyMediaChanged), "media outside raw text and rich blocks is outside filter text scope")
weak var weakPage: InstantPage?
do {
    let page = InstantPage([String(repeating: "hidden ", count: 10000)])
    weakPage = page
    let value = message(26, text: "visible").withUpdatedAttributes([RichTextMessageAttribute(page)])
    _ = regramShouldHideMessage(value, accountId: performanceAccount, filter: filter, revision: performanceRevision)
}
expect(weakPage == nil, "decision cache does not retain rich pages or block payloads")
resetVisibilityCache()
let largeText = message(27, text: String(repeating: "visible ", count: 10000))
_ = regramShouldHideMessage(largeText, accountId: performanceAccount, filter: filter, revision: performanceRevision)
let largeBefore = TestCounters.shared.count("matches")
_ = regramShouldHideMessage(largeText, accountId: performanceAccount, filter: filter, revision: performanceRevision)
expect(visibilityCacheStats().0 == 0 && TestCounters.shared.count("matches") == largeBefore + 1, "oversize plain text is not retained in decision cache")
resetVisibilityCache()
for id in 1...4096 { _ = regramShouldHideMessage(message(Int32(id)), accountId: performanceAccount, filter: filter, revision: performanceRevision) }
expect(visibilityCacheStats().0 == 4096, "decision cache reaches bounded item capacity")
let capacityBefore = TestCounters.shared.count("matches")
_ = regramShouldHideMessage(message(2000).withUpdatedText("visible"), accountId: performanceAccount, filter: filter, revision: performanceRevision)
_ = regramShouldHideMessage(message(2001), accountId: performanceAccount, filter: filter, revision: performanceRevision)
expect(TestCounters.shared.count("matches") == capacityBefore + 1 && visibilityCacheStats().0 == 4096, "capacity update preserves other hot entries")
_ = regramShouldHideMessage(message(5000), accountId: performanceAccount, filter: filter, revision: performanceRevision)
let evictionBefore = TestCounters.shared.count("matches")
_ = regramShouldHideMessage(message(2001), accountId: performanceAccount, filter: filter, revision: performanceRevision)
expect(TestCounters.shared.count("matches") == evictionBefore && visibilityCacheStats().0 == 4096, "capacity insertion evicts one entry without clearing hot cache")
resetVisibilityCache()
for id in 1...150 { _ = regramShouldHideMessage(message(Int32(id), text: String(repeating: "x", count: 32000)), accountId: performanceAccount, filter: filter, revision: performanceRevision) }
let budgetBefore = TestCounters.shared.count("matches")
_ = regramShouldHideMessage(message(149, text: String(repeating: "x", count: 32000)), accountId: performanceAccount, filter: filter, revision: performanceRevision)
expect(visibilityCacheStats().1 <= 4 * 1024 * 1024 && visibilityCacheStats().0 > 100, "cache cost budget evicts a bounded subset")
expect(TestCounters.shared.count("matches") == budgetBefore, "cost pressure preserves recent hot entries")
resetVisibilityCache()

prepareQueue.reset()
let quietAccount = Account()
let quiet = SchedulingFixture(account: quietAccount, accountId: accountId, preferences: preferences, reveal: reveal)
let quietRequest = scheduledRequests(quietAccount, ids: 61...61, readable: [])
quiet.update(quietRequest)
_ = drainScheduling(quiet)
let quietTransactions = quietAccount.postbox.storage.transactionRuns
let quietQueries = quietAccount.postbox.storage.historyQueries
let quietMatches = TestCounters.shared.count("matches")
for _ in 0..<200 { quiet.update(quietRequest); _ = drainScheduling(quiet) }
expect(quietTransactions == 4 && quietAccount.postbox.storage.transactionRuns == quietTransactions, "two hundred unrelated updates never requeue the same failed proof")
expect(quietAccount.postbox.storage.historyQueries == quietQueries && TestCounters.shared.count("matches") == quietMatches, "failed proof memo skips history and regex on unrelated updates")
quietAccount.postbox.storage.holes[quietRequest[0].snapshot.sourceTop.id.peerId] = []
quietAccount.postbox.publishViews(); _ = drainScheduling(quiet)
expect(quietAccount.postbox.storage.applied == quietRequest.map { $0.snapshot.sourceTop }, "hole change retries failed proof without source update")
quiet.dispose(); _ = drainScheduling(quiet)

for missingAssociation in [false, true] {
    prepareQueue.reset()
    let associatedAccount = Account()
    let associated = SchedulingFixture(account: associatedAccount, accountId: accountId, preferences: preferences, reveal: reveal)
    let requests = scheduledRequests(associatedAccount, ids: 62...62, readable: [62])
    let associatedMain = requests[0].snapshot.sourceTop.id.peerId
    associatedAccount.postbox.storage.cached[associatedMain] = CachedPeerData(associatedHistoryMessageId: message(1, peerId: otherPeer).id)
    if !missingAssociation { associatedAccount.postbox.storage.readStates[otherPeer] = state(count: 1) }
    associated.update(requests); _ = drainScheduling(associated)
    expect(associatedAccount.postbox.storage.applied.isEmpty, "associated unread or unknown evidence fails closed")
    associatedAccount.postbox.storage.readStates[otherPeer] = state(count: 0)
    associatedAccount.postbox.publishViews(); _ = drainScheduling(associated)
    expect(associatedAccount.postbox.storage.applied == requests.map { $0.snapshot.sourceTop }, "associated read-state becoming known zero retries")
    associated.dispose(); _ = drainScheduling(associated)
}
prepareQueue.reset()
let incompleteAccount = Account()
let missing = SchedulingFixture(account: incompleteAccount, accountId: accountId, preferences: preferences, reveal: reveal)
let missingRequests = scheduledRequests(incompleteAccount, ids: 63...63, readable: [63])
let absentId = message(19, peerId: missingRequests[0].snapshot.sourceTop.id.peerId).id
let absentMessage = incompleteAccount.postbox.storage.messages.removeValue(forKey: absentId)!
missing.update(missingRequests); _ = drainScheduling(missing)
expect(incompleteAccount.postbox.storage.applied.isEmpty, "incomplete history stays unread")
incompleteAccount.postbox.storage.messages[absentId] = absentMessage
incompleteAccount.postbox.publishViews(); _ = drainScheduling(missing)
expect(incompleteAccount.postbox.storage.applied == missingRequests.map { $0.snapshot.sourceTop }, "history insertion retries without source update")
missing.update([]); _ = drainScheduling(missing)
let inactiveTransactions = incompleteAccount.postbox.storage.transactionRuns
incompleteAccount.postbox.storage.holes[absentId.peerId] = IndexSet(integer: 19)
incompleteAccount.postbox.publishViews(); _ = drainScheduling(missing)
expect(incompleteAccount.postbox.storage.transactionRuns == inactiveTransactions, "leaving source disposes passive proof observation")
missing.dispose(); _ = drainScheduling(missing)

prepareQueue.reset()
let unsupportedAccount = Account()
let unsupported = SchedulingFixture(account: unsupportedAccount, accountId: accountId, preferences: preferences, reveal: reveal)
let unsupportedRequests = scheduledRequests(unsupportedAccount, ids: 64...64, readable: [64])
unsupportedAccount.postbox.storage.peers[unsupportedRequests[0].snapshot.sourceTop.id.peerId]?.isForumOrMonoForum = true
unsupported.update(unsupportedRequests); _ = drainScheduling(unsupported)
expect(unsupportedAccount.postbox.storage.historyQueries == 0 && unsupportedAccount.postbox.observationStarts == 0, "unsupported aggregate has no history proof or watcher")
unsupported.dispose(); _ = drainScheduling(unsupported)
prepareQueue.reset()
let queuedStaleAccount = Account()
let queuedStale = SchedulingFixture(account: queuedStaleAccount, accountId: accountId, preferences: preferences, reveal: reveal)
queuedStale.update(scheduledRequests(queuedStaleAccount, ids: 65...65, readable: [65]))
queuedStale.dispose(); _ = drainScheduling(queuedStale)
expect(queuedStaleAccount.postbox.storage.historyQueries == 0 && queuedStaleAccount.postbox.storage.applied.isEmpty, "disposed queued Postbox work rejects before proof history scan")

for changedPayload in 0..<3 {
    let (changedAccount, changedSnapshot) = fixture()
    let attribute = RichTextMessageAttribute(InstantPage(["hidden"]))
    if changedPayload != 0 { changedAccount.postbox.storage.messages[message(19).id] = message(19, text: "visible").withUpdatedAttributes([attribute]) }
    changedAccount.postbox.storage.beforeTransaction = { number in
        guard number == 2 else { return }
        switch changedPayload {
        case 0: changedAccount.postbox.storage.messages[message(19).id] = message(19).withUpdatedText("visible")
        case 1: changedAccount.postbox.storage.messages[message(19).id] = message(19, text: "visible").withUpdatedAttributes([RichTextMessageAttribute(InstantPage(["visible"]))])
        default: attribute.fullInstantPage = InstantPage(["visible"])
        }
    }
    expect(!submitFixture(changedAccount, request(changedSnapshot)) && changedAccount.postbox.storage.applied.isEmpty, "same-version payload mutation after preparation cannot commit")
}
prepareQueue.reset()
let manualAccount = Account()
let manual = SchedulingFixture(account: manualAccount, accountId: accountId, preferences: preferences, reveal: reveal)
let beforeManual = scheduledRequests(manualAccount, ids: 66...66, readable: [66])[0]
let manualReadState = state(marked: true)
manualAccount.postbox.storage.readStates[beforeManual.snapshot.sourceTop.id.peerId] = manualReadState
let manualRequest = UnreadRequest(id: beforeManual.id, source: beforeManual.source, snapshot: RegramChatListUnreadSnapshot(sourceTop: beforeManual.snapshot.sourceTop, sourceMessages: beforeManual.snapshot.sourceMessages, readState: manualReadState))
manual.update([manualRequest]); _ = drainScheduling(manual)
expect(manualAccount.postbox.storage.historyQueries == 0 && manualAccount.postbox.observationStarts == 0, "manual unread has no history proof or watcher")
manual.dispose(); _ = drainScheduling(manual)

func coordinatorEntry(_ top: Message, folder: Int32 = 1, peerObject: Peer? = nil, unread: CombinedPeerReadState? = nil) -> UIChatListEntry {
    let rendered = EngineRenderedPeer(peerId: top.id.peerId, peer: EnginePeer(peer: peerObject ?? Peer(id: top.id.peerId)))
    let value = EngineChatList.Item(id: .chatList(top.id.peerId), index: .chatList(ChatListIndex(pinningIndex: nil, messageIndex: top.index)), messages: [EngineMessage(message: top)], readCounters: unread.map { EnginePeerReadCounters(state: $0) }, isMuted: false, draft: nil, threadData: nil, renderedPeer: rendered, presence: nil, hasUnseenMentions: false, hasUnseenReactions: false, hasUnseenPollVotes: false, forumTopicData: nil, topForumTopicItems: [], hasFailed: false, isContact: false, autoremoveTimeout: nil, storyStats: nil, displayAsTopicList: false, isPremiumRequiredToMessage: false, mediaDraftContentType: nil)
    return .chat(value, [], nil, filter: TestFilter(id: folder), generalStatus: nil, selectedForum: nil, appearMode: "default", hideContent: false, folders: nil, communityCategories: [:], canPreviewChat: true, regramRevision: 1)
}
func drainCoordinator() {
    var steps = 0
    while prepareQueue.runNext() { steps += 1; precondition(steps < 2000, "coordinator failed to settle") }
}
prepareQueue.reset()
let previewAccount = Account()
let preview = RegramChatListPreviewCoordinator(account: previewAccount, accountId: accountId)
previewAccount.postbox.storage.peers[peer] = Peer(id: peer)
previewAccount.postbox.storage.messages[message(20).id] = message(20)
previewAccount.postbox.storage.messages[message(19).id] = message(19, text: "visible")
let folderA = coordinatorEntry(message(20), folder: 1)
_ = preview.update([folderA], filterRevision: 1, pagingFloor: nil); drainCoordinator()
let previewQueries = previewAccount.postbox.storage.historyQueries
let previewMatches = TestCounters.shared.count("matches")
var sharedPreviewStable = true
for index in 0..<200 {
    let entry = coordinatorEntry(message(20), folder: Int32(index % 2 + 1))
    let result = preview.update([entry], filterRevision: 1, pagingFloor: nil)
    sharedPreviewStable = result.previews[entry.stableId]?.first?.id == message(19).id && sharedPreviewStable
    drainCoordinator()
}
expect(sharedPreviewStable, "shared peer preview survives folder switches")
expect(previewQueries == 3 && previewAccount.postbox.storage.historyQueries == previewQueries, "two hundred folder switches reuse one three-namespace scan")
expect(TestCounters.shared.count("matches") == previewMatches, "two hundred folder switches run zero additional regex")
let sourceChanged = coordinatorEntry(message(20).withUpdatedText("visible"), folder: 2)
let changedSourceResult = preview.update([sourceChanged], filterRevision: 1, pagingFloor: nil)
expect(changedSourceResult.previews[sourceChanged.stableId] == nil, "same-version source text invalidates cached hidden-source preview")
drainCoordinator()
let sourceRich = RichTextMessageAttribute(InstantPage(["hidden"]))
let richSource = message(20, text: "visible").withUpdatedAttributes([sourceRich])
previewAccount.postbox.storage.messages[richSource.id] = richSource
let richSourceEntry = coordinatorEntry(richSource)
_ = preview.update([richSourceEntry], filterRevision: 1, pagingFloor: nil); drainCoordinator()
sourceRich.fullInstantPage = InstantPage(["visible"])
let richSourceResult = preview.update([richSourceEntry], filterRevision: 1, pagingFloor: nil)
expect(richSourceResult.previews[richSourceEntry.stableId] == nil, "cached source sees in-place rich full-page replacement on next update")
drainCoordinator()
let candidateAttribute = RichTextMessageAttribute(InstantPage(["visible"]))
let richCandidate = message(19, text: "visible").withUpdatedAttributes([candidateAttribute])
previewAccount.postbox.storage.messages[message(20).id] = message(20)
previewAccount.postbox.storage.messages[richCandidate.id] = richCandidate
_ = preview.update([folderA], filterRevision: 1, pagingFloor: nil); drainCoordinator()
_ = preview.update([], filterRevision: 1, pagingFloor: nil); drainCoordinator()
candidateAttribute.fullInstantPage = InstantPage(["hidden"])
let candidateResult = preview.update([folderA], filterRevision: 1, pagingFloor: nil)
expect(candidateResult.previews[folderA.stableId]?.isEmpty == true, "returning folder rejects in-place changed cached candidate payload")
drainCoordinator()
previewAccount.postbox.storage.messages[richCandidate.id] = richCandidate.withUpdatedAttributes([RichTextMessageAttribute(InstantPage(["visible"]))])
previewAccount.postbox.publishViews(); drainCoordinator()
preview.refreshExhaustedEmpty(); drainCoordinator()
let restoredResult = preview.update([folderA], filterRevision: 1, pagingFloor: nil)
expect(restoredResult.previews[folderA.stableId]?.first?.id == richCandidate.id, "same-version replaced candidate attributes become visible after native observation")
previewAccount.postbox.storage.messages[richCandidate.id] = richCandidate.withUpdatedText("hidden")
previewAccount.postbox.publishViews(); drainCoordinator()
let hiddenCandidateResult = preview.update([folderA], filterRevision: 1, pagingFloor: nil)
expect(hiddenCandidateResult.previews[folderA.stableId]?.isEmpty == true, "same-version changed candidate text cannot survive cached presentation")
preview.dispose(); drainCoordinator()
prepareQueue.reset()
let boundedAccount = Account()
let bounded = RegramChatListPreviewCoordinator(account: boundedAccount, accountId: accountId)
for index in 1...132 {
    let id = PeerId(namespace: Namespaces.Peer.CloudUser, value: Int64(3000 + index))
    let top = message(20, peerId: id)
    boundedAccount.postbox.storage.messages[top.id] = top
    let visible = message(19, text: "visible", peerId: id)
    boundedAccount.postbox.storage.messages[visible.id] = visible
    _ = bounded.update([coordinatorEntry(top)], filterRevision: 1, pagingFloor: nil); drainCoordinator()
}
expect(bounded.testInactiveCount == 128 && bounded.testCacheCount == 129, "cross-folder preview retains at most 128 non-current peers")
bounded.dispose(); drainCoordinator()
prepareQueue.reset()
let migratingAccount = Account()
let migrating = SchedulingFixture(account: migratingAccount, accountId: accountId, preferences: preferences, reveal: reveal)
let migratingOld = scheduledRequests(migratingAccount, ids: 67...67, readable: [67])[0]
let migratingNew = UnreadRequest(id: 167, source: migratingOld.source, snapshot: migratingOld.snapshot)
migrating.update([migratingOld])
migrating.update([migratingNew])
_ = drainScheduling(migrating)
expect(migratingAccount.postbox.storage.applied == [migratingNew.snapshot.sourceTop], "folder identity change resumes an unread request cancelled before phase one")
expect(migratingAccount.postbox.storage.historyQueries == 2 && migratingAccount.postbox.observationStarts == 0 && migrating.pendingUnread.isEmpty && migrating.unreadDisposables.isEmpty, "migrated unread request completes once without orphaned memo or watcher")
migrating.dispose(); _ = drainScheduling(migrating)
prepareQueue.reset()
let completedAccount = Account()
let completed = SchedulingFixture(account: completedAccount, accountId: accountId, preferences: preferences, reveal: reveal)
let completedOld = scheduledRequests(completedAccount, ids: 68...68, readable: [])[0]
completed.update([completedOld]); _ = drainScheduling(completed)
let completedRuns = completedAccount.postbox.storage.transactionRuns
let completedQueries = completedAccount.postbox.storage.historyQueries
let completedNew = UnreadRequest(id: 168, source: completedOld.source, snapshot: completedOld.snapshot)
completed.update([completedNew]); _ = drainScheduling(completed)
expect(completedAccount.postbox.storage.transactionRuns == completedRuns && completedAccount.postbox.storage.historyQueries == completedQueries, "folder identity change preserves completed failed-proof memo")
completedAccount.postbox.storage.holes[completedOld.snapshot.sourceTop.id.peerId] = []
completedAccount.postbox.publishViews(); _ = drainScheduling(completed)
expect(completedAccount.postbox.storage.applied == [completedNew.snapshot.sourceTop], "preserved evidence observer retries the new folder lease")
completed.dispose(); _ = drainScheduling(completed)
prepareQueue.reset()
let newSourceAccount = Account()
let newSource = SchedulingFixture(account: newSourceAccount, accountId: accountId, preferences: preferences, reveal: reveal)
let sourceOld = scheduledRequests(newSourceAccount, ids: 69...69, readable: [69])[0]
newSource.update([sourceOld])
var sourceNewTop = newSourceAccount.postbox.storage.messages[sourceOld.snapshot.sourceTop.id]!
sourceNewTop.stableVersion += 1
newSourceAccount.postbox.storage.messages[sourceNewTop.id] = sourceNewTop
let sourceNew = UnreadRequest(id: sourceOld.id, source: sourceOld.source, snapshot: RegramChatListUnreadSnapshot(sourceTop: sourceNewTop.index, sourceMessages: regramChatListSourceKeys([sourceNewTop]), readState: sourceOld.snapshot.readState))
newSource.update([sourceNew]); _ = drainScheduling(newSource)
expect(newSourceAccount.postbox.storage.applied == [sourceNew.snapshot.sourceTop] && newSource.pendingUnread.isEmpty && newSource.unreadDisposables.isEmpty, "source replacement cancels old in-flight work and completes current proof")
newSource.dispose(); _ = drainScheduling(newSource)
let disposedMigrateRuns = newSourceAccount.postbox.storage.transactionRuns
newSource.update([sourceNew]); _ = drainScheduling(newSource)
expect(newSourceAccount.postbox.storage.transactionRuns == disposedMigrateRuns, "disposed unread scheduler cannot revive cancelled attempts")

prepareQueue.reset()
testHoldRemote = true
let resumedRemoteAccount = Account()
resumedRemoteAccount.postbox.storage.messages[message(20).id] = message(20)
let resumedRemote = RegramChatListPreviewCoordinator(account: resumedRemoteAccount, accountId: accountId)
let remoteStartsBefore = testRemoteStarts
_ = resumedRemote.update([folderA], filterRevision: 1, pagingFloor: nil); drainCoordinator()
expect(testRemoteStarts == remoteStartsBefore + 1 && resumedRemote.testActiveRemoteCount == 1, "exhausted local preview starts one pending remote request")
_ = resumedRemote.update([], filterRevision: 1, pagingFloor: nil); drainCoordinator()
expect(resumedRemote.testActiveRemoteCount == 0 && resumedRemote.testInactiveCount == 1, "leaving peer cancels remote while retaining bounded preview state")
testHoldRemote = false
let folderB = coordinatorEntry(message(20), folder: 2)
_ = resumedRemote.update([folderB], filterRevision: 1, pagingFloor: nil); drainCoordinator()
expect(testRemoteStarts == remoteStartsBefore + 2 && resumedRemote.testActiveRemoteCount == 0, "returning folder restarts cancelled remote and completes empty result")
for _ in 0..<200 { _ = resumedRemote.update([folderB], filterRevision: 1, pagingFloor: nil); drainCoordinator() }
_ = resumedRemote.update([], filterRevision: 1, pagingFloor: nil); drainCoordinator()
_ = resumedRemote.update([folderA], filterRevision: 1, pagingFloor: nil); drainCoordinator()
expect(testRemoteStarts == remoteStartsBefore + 2, "completed empty remote does not restart on updates or folder return")
resumedRemote.dispose(); drainCoordinator()
prepareQueue.reset()
testHoldRemote = true
let changedRemoteAccount = Account()
changedRemoteAccount.postbox.storage.messages[message(20).id] = message(20)
let changedRemote = RegramChatListPreviewCoordinator(account: changedRemoteAccount, accountId: accountId)
let changedRemoteStarts = testRemoteStarts
_ = changedRemote.update([folderA], filterRevision: 1, pagingFloor: nil); drainCoordinator()
changedRemoteAccount.postbox.storage.messages[message(21).id] = message(21)
let newerRemoteEntry = coordinatorEntry(message(21))
_ = changedRemote.update([newerRemoteEntry], filterRevision: 1, pagingFloor: nil); drainCoordinator()
expect(testRemoteStarts == changedRemoteStarts + 2 && changedRemote.testActiveRemoteCount == 1, "source replacement cancels prior remote and starts current source once")
changedRemote.dispose(); drainCoordinator()
let disposedRemoteStarts = testRemoteStarts
_ = changedRemote.update([newerRemoteEntry], filterRevision: 1, pagingFloor: nil); drainCoordinator()
expect(changedRemote.testActiveRemoteCount == 0 && testRemoteStarts == disposedRemoteStarts, "disposed preview cannot restart cancelled remote")
testHoldRemote = false

func scanWindowFixture() -> (Account, RegramChatListPreviewCoordinator) {
    let account = Account()
    account.postbox.storage.messages[message(20).id] = message(20)
    account.postbox.storage.messages[message(19).id] = message(19, text: "visible")
    return (account, RegramChatListPreviewCoordinator(account: account, accountId: accountId))
}
for returnPhase in 0..<4 {
    prepareQueue.reset()
    let (account, coordinator) = scanWindowFixture()
    _ = coordinator.update([folderA], filterRevision: 1, pagingFloor: nil)
    _ = coordinator.update([], filterRevision: 1, pagingFloor: nil)
    switch returnPhase {
    case 0: _ = coordinator.update([folderB], filterRevision: 1, pagingFloor: nil)
    case 1:
        account.postbox.storage.beforeTransaction = { number in
            guard number == 1 else { return }
            account.postbox.storage.beforeTransaction = nil
            _ = coordinator.update([folderB], filterRevision: 1, pagingFloor: nil)
        }
    case 2:
        account.postbox.storage.afterTransaction = { number in
            guard number == 1 else { return }
            account.postbox.storage.afterTransaction = nil
            _ = coordinator.update([folderB], filterRevision: 1, pagingFloor: nil)
        }
    default:
        drainCoordinator()
        _ = coordinator.update([folderB], filterRevision: 1, pagingFloor: nil)
    }
    drainCoordinator()
    let result = coordinator.update([folderB], filterRevision: 1, pagingFloor: nil)
    expect(result.previews[folderB.stableId]?.first?.id == message(19).id && account.postbox.storage.historyQueries == 3, "local preview resumes at each return boundary around DB and prepare delivery")
    for _ in 0..<20 { _ = coordinator.update([folderB], filterRevision: 1, pagingFloor: nil); drainCoordinator() }
    expect(account.postbox.storage.historyQueries == 3 && coordinator.testPendingPreviewCount == 0 && coordinator.testInFlightPreviewCount == 0 && !coordinator.testPreviewRunning, "resumed local scan has no duplicate queue entries or later rescans")
    coordinator.dispose(); drainCoordinator()
}
for returnBeforePrepare in [true, false] {
    prepareQueue.reset()
    let (account, coordinator) = scanWindowFixture()
    account.postbox.storage.afterTransaction = { number in
        guard number == 1 else { return }
        account.postbox.storage.afterTransaction = nil
        _ = coordinator.update([], filterRevision: 1, pagingFloor: nil)
        if returnBeforePrepare { _ = coordinator.update([folderB], filterRevision: 1, pagingFloor: nil) }
    }
    _ = coordinator.update([folderA], filterRevision: 1, pagingFloor: nil); drainCoordinator()
    let result = coordinator.update([folderB], filterRevision: 1, pagingFloor: nil); drainCoordinator()
    expect(result.previews[folderB.stableId]?.first?.id == message(19).id && account.postbox.storage.historyQueries == 3, "leaving after DB fetch preserves valid preview across prepare and return ordering")
    coordinator.dispose(); drainCoordinator()
}
prepareQueue.reset()
let (inactiveScanAccount, inactiveScan) = scanWindowFixture()
_ = inactiveScan.update([folderA], filterRevision: 1, pagingFloor: nil)
_ = inactiveScan.update([], filterRevision: 1, pagingFloor: nil); drainCoordinator()
expect(inactiveScanAccount.postbox.storage.historyQueries == 0 && inactiveScan.testPendingPreviewCount == 0 && inactiveScan.testInFlightPreviewCount == 0 && !inactiveScan.testPreviewRunning, "lease-skipped request stays unqueued while peer remains inactive")
inactiveScan.dispose(); drainCoordinator()
for disposePhase in 0..<3 {
    prepareQueue.reset()
    let (account, coordinator) = scanWindowFixture()
    _ = coordinator.update([folderA], filterRevision: 1, pagingFloor: nil)
    _ = coordinator.update([], filterRevision: 1, pagingFloor: nil)
    switch disposePhase {
    case 0: coordinator.dispose()
    case 1:
        account.postbox.storage.afterTransaction = { number in
            guard number == 1 else { return }
            account.postbox.storage.afterTransaction = nil
            coordinator.dispose()
            _ = coordinator.update([folderB], filterRevision: 1, pagingFloor: nil)
        }
    default: drainCoordinator(); coordinator.dispose()
    }
    drainCoordinator()
    let transactionsAfterDispose = account.postbox.storage.transactionRuns
    _ = coordinator.update([folderB], filterRevision: 1, pagingFloor: nil); drainCoordinator()
    expect(account.postbox.storage.historyQueries == 0 && coordinator.testPendingPreviewCount == 0 && account.postbox.storage.transactionRuns == transactionsAfterDispose, "dispose at each DB/prepare boundary cannot replenish skipped local work")
}
for replacePhase in 0..<3 {
    prepareQueue.reset()
    let (account, coordinator) = scanWindowFixture()
    let newer = coordinatorEntry(message(21), folder: 2)
    let replaceSource = {
        account.postbox.storage.messages[message(20).id] = message(20, text: "visible")
        account.postbox.storage.messages[message(21).id] = message(21)
        _ = coordinator.update([newer], filterRevision: 1, pagingFloor: nil)
    }
    _ = coordinator.update([folderA], filterRevision: 1, pagingFloor: nil)
    _ = coordinator.update([], filterRevision: 1, pagingFloor: nil)
    switch replacePhase {
    case 0: replaceSource()
    case 1:
        account.postbox.storage.afterTransaction = { number in
            guard number == 1 else { return }
            account.postbox.storage.afterTransaction = nil
            replaceSource()
        }
    default: drainCoordinator(); replaceSource()
    }
    drainCoordinator()
    let result = coordinator.update([newer], filterRevision: 1, pagingFloor: nil)
    expect(result.previews[newer.stableId]?.first?.id == message(20).id && account.postbox.storage.historyQueries == 3 && coordinator.testPendingPreviewCount == 0, "source replacement at each DB/prepare boundary does not replenish the previous source")
    coordinator.dispose(); drainCoordinator()
}
prepareQueue.reset()
let (fetchedOldAccount, fetchedOld) = scanWindowFixture()
let fetchedNewEntry = coordinatorEntry(message(21))
fetchedOldAccount.postbox.storage.afterTransaction = { number in
    guard number == 1 else { return }
    fetchedOldAccount.postbox.storage.afterTransaction = nil
    fetchedOldAccount.postbox.storage.messages[message(20).id] = message(20, text: "visible")
    fetchedOldAccount.postbox.storage.messages[message(21).id] = message(21)
    _ = fetchedOld.update([fetchedNewEntry], filterRevision: 1, pagingFloor: nil)
}
_ = fetchedOld.update([folderA], filterRevision: 1, pagingFloor: nil); drainCoordinator()
let fetchedNewResult = fetchedOld.update([fetchedNewEntry], filterRevision: 1, pagingFloor: nil)
expect(fetchedNewResult.previews[fetchedNewEntry.stableId]?.first?.id == message(20).id && fetchedOldAccount.postbox.storage.historyQueries == 6, "fetched old-source result cannot override or requeue after a new-source scan")
fetchedOld.dispose(); drainCoordinator()
for resetAfterDB in [false, true] {
    prepareQueue.reset()
    let (account, coordinator) = scanWindowFixture()
    _ = coordinator.update([folderA], filterRevision: 1, pagingFloor: nil)
    _ = coordinator.update([], filterRevision: 1, pagingFloor: nil)
    if resetAfterDB {
        account.postbox.storage.afterTransaction = { number in
            guard number == 1 else { return }
            account.postbox.storage.afterTransaction = nil
            _ = coordinator.update([folderB], filterRevision: 2, pagingFloor: nil)
        }
    } else { _ = coordinator.update([folderB], filterRevision: 2, pagingFloor: nil) }
    drainCoordinator()
    let result = coordinator.update([folderB], filterRevision: 2, pagingFloor: nil)
    expect(result.previews[folderB.stableId]?.first?.id == message(19).id && account.postbox.storage.historyQueries == 3 && coordinator.testPendingPreviewCount == 0 && coordinator.testInFlightPreviewCount == 0, "generation reset owns its new scan without replenishing the old generation")
    coordinator.dispose(); drainCoordinator()
}
prepareQueue.reset()
let partialAccount = Account()
for id in 1...71 { let value = message(Int32(id), text: id == 1 ? "visible" : "hidden"); partialAccount.postbox.storage.messages[value.id] = value }
let partial = RegramChatListPreviewCoordinator(account: partialAccount, accountId: accountId)
let partialEntry = coordinatorEntry(message(71))
_ = partial.update([partialEntry], filterRevision: 1, pagingFloor: nil); drainCoordinator()
let partialResult = partial.update([partialEntry], filterRevision: 1, pagingFloor: nil)
expect(partialResult.previews[partialEntry.stableId]?.first?.id == message(1).id && partialAccount.postbox.storage.historyQueries == 5 && partial.testPendingPreviewCount == 0, "ordinary partial pages are already queued and never duplicated by recovery")
partial.dispose(); drainCoordinator()
prepareQueue.reset()
let (mixedAccount, mixed) = scanWindowFixture()
let mixedTop = message(20, peerId: otherPeer)
let mixedVisible = message(19, text: "visible", peerId: otherPeer)
mixedAccount.postbox.storage.messages[mixedTop.id] = mixedTop
mixedAccount.postbox.storage.messages[mixedVisible.id] = mixedVisible
let mixedEntry = coordinatorEntry(mixedTop)
_ = mixed.update([folderA, mixedEntry], filterRevision: 1, pagingFloor: nil)
_ = mixed.update([mixedEntry], filterRevision: 1, pagingFloor: nil)
mixedAccount.postbox.storage.afterTransaction = { number in
    guard number == 1 else { return }
    mixedAccount.postbox.storage.afterTransaction = nil
    _ = mixed.update([folderB, mixedEntry], filterRevision: 1, pagingFloor: nil)
}
drainCoordinator()
let mixedResult = mixed.update([folderB, mixedEntry], filterRevision: 1, pagingFloor: nil)
expect(mixedResult.previews[folderB.stableId]?.first?.id == message(19).id && mixedResult.previews[mixedEntry.stableId]?.first?.id == mixedVisible.id && mixedAccount.postbox.storage.historyQueries == 6, "mixed batch recovers only its lease-skipped peer while preserving completed peer")
mixed.dispose(); drainCoordinator()

expect(TestCounters.shared.count("text.postbox") == 0 && TestCounters.shared.count("matches.postbox") == 0, "preview and unread classification never expand text or match regex inside Postbox transactions")
let captureAccountId: Int64 = 77219
let initialCapture = preferences.captureFilter(accountId: captureAccountId)
expect(initialCapture.revision == 0 && initialCapture.filter.isEmpty, "initial capture returns the matching empty filter and zero revision")
preferences.update(accountId: captureAccountId) { $0.filterRules = [RGMessageFilterRule(pattern: "odd")] }
let firstCapture = preferences.captureFilter(accountId: captureAccountId)
expect(firstCapture.revision == 1 && firstCapture.filter.shouldHide(text: "odd", peerId: peer.toInt64(), authorId: nil, incoming: true), "capture pairs a changed rule with its incremented revision")
expect(preferences.filter(accountId: captureAccountId).shouldHide(text: "odd", peerId: peer.toInt64(), authorId: nil, incoming: true), "filter compatibility entry uses captured filter")
let captureMismatched = Atomic(value: false)
let captureWorkers = DispatchGroup()
for operation in 0..<4 {
    captureWorkers.enter()
    DispatchQueue.global().async {
        if operation == 0 {
            for revision in 2...502 {
                preferences.update(accountId: captureAccountId) { $0.filterRules = [RGMessageFilterRule(pattern: revision % 2 == 1 ? "odd" : "even")] }
            }
        } else {
            for _ in 0..<2000 {
                let captured = preferences.captureFilter(accountId: captureAccountId)
                let hidden = captured.filter.shouldHide(text: "odd", peerId: peer.toInt64(), authorId: nil, incoming: true)
                if hidden != (captured.revision % 2 == 1) { _ = captureMismatched.swap(true) }
                _ = regramShouldHideMessage(message(700, text: "odd"), accountId: captureAccountId)
            }
        }
        captureWorkers.leave()
    }
}
expect(captureWorkers.wait(timeout: .now() + 15) == .success && !captureMismatched.with { $0 }, "concurrent rule writes cannot split captured revision and filter")
expect(TestCounters.shared.count("captureStores") > 0 && TestCounters.shared.count("captureMismatch") == 0, "legacy entry never stores a decision under another rule revision")
let finalCapture = preferences.captureFilter(accountId: captureAccountId)
expect(finalCapture.revision == 502 && !finalCapture.filter.shouldHide(text: "odd", peerId: peer.toInt64(), authorId: nil, incoming: true), "final capture reflects all concurrent rule writes")
print("Measured stable decisions: 200 calls -> 1 text + 1 match; folder changes: 200 -> 3 initial queries + 0 further matches; failed proofs: 200 updates -> 0 extra queries/transactions/matches")
print("Passed \(checks) filtered chat-list parity checks")
