import Foundation
import Postbox
import TelegramCore
import ChatHistoryModel
import RegramCore

struct RegramChatListPeerKey: Hashable {
    let accountId: Int64
    let peerId: PeerId
    let threadId: Int64?
}

struct RegramChatListSourceMessageKey: Equatable {
    let id: MessageId
    let version: UInt32
}

func regramChatListSourceKeys(_ messages: [Message]) -> [RegramChatListSourceMessageKey] {
    messages.sorted { $0.id < $1.id }.map { RegramChatListSourceMessageKey(id: $0.id, version: $0.stableVersion) }
}

func regramChatListSourceTop(_ messages: [Message]) -> Message? {
    messages.max { $0.index < $1.index }
}

func regramChatListPreviewUpperBound(_ messages: [Message]) -> MessageIndex? {
    messages.map(\.index).min()
}

func regramChatListMessageIsHidden(_ message: Message, filter: RegramFilterSnapshot) -> Bool {
    guard !filter.isEmpty, !message.flags.intersection(.IsIncomingMask).isEmpty else { return false }
    return filter.shouldHide(peerId: message.id.peerId.toInt64(), authorId: message.author?.id.toInt64(), incoming: true, text: { regramMessageText(message) })
}

struct RegramChatListUnreadSnapshot: Equatable {
    let sourceTop: MessageIndex
    let sourceMessages: [RegramChatListSourceMessageKey]
    let readState: CombinedPeerReadState
}

struct RegramChatListPreparedVisibility {
    private struct Value {
        let version: UInt32
        let payload: RegramMessageFilterPayload
    }
    private var hidden: [MessageId: Value] = [:]

    init(messages: [Message], accountId: Int64, filter: RegramFilterSnapshot, revision: Int64) {
        guard !filter.isEmpty else { return }
        for message in messages where !message.flags.intersection(.IsIncomingMask).isEmpty {
            let payload = RegramMessageFilterPayload(message)
            if payload.shouldHide(accountId: accountId, filter: filter, revision: revision) {
                hidden[message.id] = Value(version: message.stableVersion, payload: payload)
            }
        }
    }

    func isHidden(_ message: Message) -> Bool {
        guard let value = hidden[message.id] else { return false }
        return value.version == message.stableVersion && value.payload == RegramMessageFilterPayload(message)
    }
}

func regramChatListUnreadMessages(transaction: Transaction, snapshot: RegramChatListUnreadSnapshot) -> [Message]? {
    let peerId = snapshot.sourceTop.id.peerId
    guard peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.CloudGroup || peerId.namespace == Namespaces.Peer.CloudChannel,
          snapshot.sourceTop.id.namespace == Namespaces.Message.Cloud,
          let peer = transaction.getPeer(peerId), !peer.isForumOrMonoForum,
          let readState = transaction.getCombinedPeerReadState(peerId), readState == snapshot.readState,
          readState.count > 0, readState.count <= 50, !readState.markedUnread,
          readState.states.allSatisfy({ $0.0 == Namespaces.Message.Cloud || $0.1.count == 0 && !$0.1.markedUnread }),
          let cloudState = readState.states.first(where: { $0.0 == Namespaces.Message.Cloud })?.1,
          case .idBased = cloudState,
          transaction.getTopPeerMessageIndex(peerId: peerId) == snapshot.sourceTop,
          let sourceMessage = transaction.getMessage(snapshot.sourceTop.id),
          regramChatListSourceKeys(transaction.getMessageGroup(sourceMessage.id) ?? [sourceMessage]) == snapshot.sourceMessages else { return nil }
    if let channel = peer as? TelegramChannel, channel.participationStatus != .member { return nil }
    let recent = transaction.getMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, from: .upperBound(peerId: peerId, namespace: Namespaces.Message.Cloud), includeFrom: true, to: .lowerBound(peerId: peerId, namespace: Namespaces.Message.Cloud), limit: 50)
    let source = transaction.getMessageGroup(snapshot.sourceTop.id) ?? []
    var seen = Set<MessageId>()
    return (source + recent).filter { seen.insert($0.id).inserted }
}

func regramChatListCanReadHiddenUnread(transaction: Transaction, snapshot: RegramChatListUnreadSnapshot, isHidden: (Message) -> Bool) -> Bool {
    let peerId = snapshot.sourceTop.id.peerId
    guard peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.CloudGroup || peerId.namespace == Namespaces.Peer.CloudChannel,
          snapshot.sourceTop.id.namespace == Namespaces.Message.Cloud,
          let peer = transaction.getPeer(peerId), !peer.isForumOrMonoForum,
          let actualReadState = transaction.getCombinedPeerReadState(peerId), actualReadState == snapshot.readState,
          actualReadState.count > 0, !actualReadState.markedUnread,
          actualReadState.states.allSatisfy({ $0.0 == Namespaces.Message.Cloud || $0.1.count == 0 && !$0.1.markedUnread }),
          let cloudState = actualReadState.states.first(where: { $0.0 == Namespaces.Message.Cloud })?.1,
          case let .idBased(maxIncomingReadId, _, maxKnownId, unreadCount, markedUnread) = cloudState,
          !markedUnread, unreadCount > 0, unreadCount <= 50, unreadCount == actualReadState.count,
          maxIncomingReadId >= 0, maxIncomingReadId < snapshot.sourceTop.id.id,
          maxKnownId <= snapshot.sourceTop.id.id, snapshot.sourceTop.id.id < Int32.max,
          transaction.getTopPeerMessageIndex(peerId: peerId) == snapshot.sourceTop,
          transaction.getTopPeerMessageIndex(peerId: peerId, namespace: Namespaces.Message.Cloud) == snapshot.sourceTop,
          let source = transaction.getMessage(snapshot.sourceTop.id), source.index == snapshot.sourceTop,
          !source.flags.intersection(.IsIncomingMask).isEmpty else { return false }

    let sourceMessages = transaction.getMessageGroup(source.id) ?? [source]
    guard regramChatListSourceKeys(sourceMessages) == snapshot.sourceMessages,
          sourceMessages.allSatisfy({ $0.id.peerId == peerId && $0.id.namespace == Namespaces.Message.Cloud && isHidden($0) }) else { return false }

    if let associatedId = transaction.getPeerCachedData(peerId: peerId)?.associatedHistoryMessageId?.peerId,
       associatedId != peerId {
        guard let associatedReadState = transaction.getCombinedPeerReadState(associatedId),
              associatedReadState.count == 0, !associatedReadState.markedUnread else { return false }
    }

    let unreadRange = Int(maxIncomingReadId + 1)..<(Int(snapshot.sourceTop.id.id) + 1)
    guard transaction.getHoles(peerId: peerId, namespace: Namespaces.Message.Cloud).intersection(IndexSet(integersIn: unreadRange)).isEmpty else { return false }

    let recentMessages = transaction.getMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, from: .upperBound(peerId: peerId, namespace: Namespaces.Message.Cloud), includeFrom: true, to: .lowerBound(peerId: peerId, namespace: Namespaces.Message.Cloud), limit: 50)
    guard Set(recentMessages.map(\.id)).count == recentMessages.count,
          recentMessages.allSatisfy({ $0.id.peerId == peerId && $0.id.namespace == Namespaces.Message.Cloud }) else { return false }
    let unreadMessages = recentMessages.filter { !$0.flags.intersection(.IsIncomingMask).isEmpty && !actualReadState.isIncomingMessageIndexRead($0.index) }
    return unreadMessages.count == Int(unreadCount) && unreadMessages.allSatisfy { $0.id.id <= snapshot.sourceTop.id.id && isHidden($0) }
}

func regramChatListPagingFloor(_ list: EngineChatList) -> MessageIndex? {
    guard list.hasEarlier else { return nil }
    for item in list.items {
        if case .chatList = item.id, case let .chatList(index) = item.index, index.pinningIndex == nil { return index.messageIndex }
    }
    return nil
}

func regramChatListDisplayIndex(native: ChatListIndex, sourceTop: MessageIndex, replacement: MessageIndex, pagingFloor: MessageIndex?) -> ChatListIndex {
    guard native.pinningIndex == nil, native.messageIndex == sourceTop, replacement.id.peerId == sourceTop.id.peerId, replacement < sourceTop else { return native }
    var displayIndex = replacement
    if let pagingFloor, displayIndex < pagingFloor {
        displayIndex = MessageIndex(id: replacement.id, timestamp: pagingFloor.timestamp)
        if displayIndex < pagingFloor { return native }
    }
    guard displayIndex <= sourceTop else { return native }
    return ChatListIndex(pinningIndex: nil, messageIndex: displayIndex)
}

func regramChatListItemWithDisplayIndex(_ item: EngineChatList.Item, _ index: ChatListIndex) -> EngineChatList.Item {
    EngineChatList.Item(
        id: item.id,
        index: .chatList(index),
        messages: item.messages,
        readCounters: item.readCounters,
        isMuted: item.isMuted,
        draft: item.draft,
        threadData: item.threadData,
        renderedPeer: item.renderedPeer,
        presence: item.presence,
        hasUnseenMentions: item.hasUnseenMentions,
        hasUnseenReactions: item.hasUnseenReactions,
        hasUnseenPollVotes: item.hasUnseenPollVotes,
        forumTopicData: item.forumTopicData,
        topForumTopicItems: item.topForumTopicItems,
        hasFailed: item.hasFailed,
        isContact: item.isContact,
        autoremoveTimeout: item.autoremoveTimeout,
        storyStats: item.storyStats,
        displayAsTopicList: item.displayAsTopicList,
        isPremiumRequiredToMessage: item.isPremiumRequiredToMessage,
        mediaDraftContentType: item.mediaDraftContentType
    )
}
