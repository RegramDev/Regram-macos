import Foundation
import Postbox
import TelegramCore
import RegramCore
import RegramServices

public func regramLLMTranslationContext(transaction: Transaction, message: Message, settings: RegramAccountSettings) -> [String] {
    guard message.id.namespace == Namespaces.Message.Cloud, regramSupportsSelectedTranslationProvider(message) else { return [] }
    return regramLLMTranslationContext(transaction: transaction, peerId: message.id.peerId, threadId: message.threadId, before: message.index, settings: settings)
}

public func regramLLMTranslationContext(transaction: Transaction, peerId: PeerId, threadId: Int64?, before: MessageIndex? = nil, settings: RegramAccountSettings) -> [String] {
    guard settings["translationBackend"].string == "llm", settings["translationLLMUseContext"].bool, peerId.namespace != Namespaces.Peer.SecretChat else { return [] }
    if let cached = transaction.getPeerCachedData(peerId: peerId) as? CachedUserData, cached.flags.contains(.copyProtectionEnabled) || cached.flags.contains(.myCopyProtectionEnabled) { return [] }
    let upper = before ?? MessageIndex.upperBound(peerId: peerId, namespace: Namespaces.Message.Cloud)
    let lower = MessageIndex.lowerBound(peerId: peerId, namespace: Namespaces.Message.Cloud)
    let earlier: [Message]
    if let threadId {
        earlier = transaction.getMessagesWithThreadId(peerId: peerId, namespace: Namespaces.Message.Cloud, threadId: threadId, from: upper, includeFrom: false, to: lower, limit: 20)
    } else {
        earlier = transaction.getMessages(peerId: peerId, namespace: Namespaces.Message.Cloud, from: upper, includeFrom: false, to: lower, limit: 20)
    }
    let filter = RegramFilterSnapshot(settings: settings)
    let candidates = earlier.sorted { $0.index < $1.index }.filter { message in
        regramSupportsSelectedTranslationProvider(message) && !message.media.contains { $0 is TelegramMediaAction } && !message.attributes.contains { $0 is RGRevokedMessageAttribute } && !filter.shouldHide(text: regramMessageText(message), peerId: message.id.peerId.toInt64(), authorId: message.author?.id.toInt64(), incoming: !message.flags.intersection(.IsIncomingMask).isEmpty)
    }.map { message in
        RegramLLMContextMessage(peerId: message.id.peerId.toInt64(), topicId: message.threadId, text: message.text, isSecret: message.containsSecretMedia, isCopyProtected: message.isCopyProtected(), isOneTime: message.attributes.contains { $0 is AutoclearTimeoutMessageAttribute || $0 is AutoremoveTimeoutMessageAttribute })
    }
    return RegramLLMContextPolicy.bounded(candidates, peerId: peerId.toInt64(), topicId: threadId)
}
