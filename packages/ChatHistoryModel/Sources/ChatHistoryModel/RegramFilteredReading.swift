import Postbox
import TelegramCore
import SwiftSignalKit

public func regramReadIndexIncludingFilteredTail(messages: [Message], visibleReadIndex: MessageIndex?, atLatest: Bool, isHidden: (Message) -> Bool) -> MessageIndex? {
    guard atLatest else { return visibleReadIndex }
    var result = visibleReadIndex
    for message in messages.reversed() {
        if let visibleReadIndex, message.index <= visibleReadIndex { break }
        guard isHidden(message) else { break }
        if !message.flags.intersection(.IsIncomingMask).isEmpty, result == nil || result! < message.index { result = message.index }
    }
    return result
}

public func regramFilteredMentionIdsToRead(messages: [Message], peerId: PeerId, threadId: Int64?, readThrough: MessageIndex, isHidden: (Message) -> Bool) -> Set<MessageId> {
    Set(messages.compactMap { message in
        guard message.id.peerId == peerId, message.id.namespace == Namespaces.Message.Cloud,
              threadId == nil || message.threadId == threadId, message.index <= readThrough,
              !message.flags.intersection(.IsIncomingMask).isEmpty, message.tags.contains(.unseenPersonalMessage),
              message.attributes.contains(where: { attribute in
                  guard let mention = attribute as? ConsumablePersonalMentionMessageAttribute else { return false }
                  return !mention.consumed && !mention.pending
              }), isHidden(message) else { return nil }
        return message.id
    })
}

public func regramEarliestVisiblePersonalMention(account: Account, peerId: PeerId, threadId: Int64?, isHidden: @escaping (Message) -> Bool) -> Signal<EarliestUnseenPersonalMentionMessageResult, NoError> {
    func next(ignoring ids: Set<MessageId>) -> Signal<EarliestUnseenPersonalMentionMessageResult, NoError> {
        TelegramEngine(account: account).messages.earliestUnseenPersonalMentionMessage(peerId: peerId, threadId: threadId, ignoreMessageIds: ids)
        |> mapToSignal { result in
            guard case let .result(id?) = result else { return .single(result) }
            return account.postbox.transaction { $0.getMessage(id) } |> mapToSignal { message in
                guard let message, message.id.peerId == peerId, message.id.namespace == Namespaces.Message.Cloud,
                      threadId == nil || message.threadId == threadId, !message.flags.intersection(.IsIncomingMask).isEmpty,
                      isHidden(message) else { return .single(result) }
                account.viewTracker.updateMarkMentionsSeenForMessageIds(messageIds: [id])
                return next(ignoring: ids.union([id]))
            }
        }
    }
    return next(ignoring: [])
}
