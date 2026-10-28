import Foundation
import Postbox
import TelegramCore
import TelegramContext
import ChatHistoryModel
import MessageUtils
import SwiftSignalKit
import TelegramUtils
import ChatModeTypes

func regramRepeatCopyMessages(_ messages: [Message], interaction: ChatInteraction) -> [EnqueueMessage]? {
    guard !messages.isEmpty, messages.count <= 100 else { return nil }
    let groupingKey: Int64? = messages.count > 1 && messages.allSatisfy({ $0.groupingKey == messages.first?.groupingKey && $0.groupingKey != nil }) ? Int64.random(in: Int64.min...Int64.max) : nil
    var result: [EnqueueMessage] = []
    for message in messages {
        guard message.id.namespace == Namespaces.Message.Cloud, !message.containsSecretMedia,
              !message.isCopyProtected(cachedData: interaction.presentation.cachedData),
              !message.attributes.contains(where: { $0 is RichTextMessageAttribute }) else { return nil }
        var media: Media?
        for value in message.media {
            if value is TelegramMediaWebpage { continue }
            guard media == nil, value is TelegramMediaImage || value is TelegramMediaFile || value is TelegramMediaMap || value is TelegramMediaContact else { return nil }
            media = value
        }
        guard media != nil || !message.text.isEmpty else { return nil }
        var attributes = message.attributes.filter { $0 is TextEntitiesMessageAttribute || $0 is MediaSpoilerMessageAttribute || $0 is InvertMediaMessageAttribute }
        if let sendAs = interaction.presentation.currentSendAsPeerId { attributes.append(SendAsMessageAttribute(peerId: sendAs)) }
        var inlineStickers: [MediaId: Media] = [:]
        for (id, value) in message.associatedMedia where value is TelegramMediaFile { inlineStickers[id] = value }
        let reference = media.map { AnyMediaReference.message(message: MessageReference(message), media: $0) }
        result.append(.message(text: message.text, attributes: attributes, inlineStickers: inlineStickers, mediaReference: reference, threadId: interaction.chatLocation.threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: groupingKey, correlationId: nil, bubbleUpEmojiOrStickersets: []))
    }
    return result
}

func regramCanRepeatHere(_ messages: [Message], interaction: ChatInteraction) -> Bool {
    let state = interaction.presentation
    guard state.sendPaidMessageStars == nil, state.slowMode?.hasLocked != true, !state.slowModeMultipleLocked,
          state.state == .normal, !interaction.interactionContext.isFrozen, let peer = state.peer, !peer.isDeleted else { return false }
    return messages.allSatisfy { message in
        peer.canSendMessage(interaction.mode.isThreadMode || interaction.mode.isTopicMode, media: message.media.first, threadData: state.threadInfo)
    }
}

func regramRepeatCopy(_ messages: [Message], interaction: ChatInteraction) {
    guard regramCanRepeatHere(messages, interaction: interaction), let copies = regramRepeatCopyMessages(messages, interaction: interaction) else { return }
    _ = enqueueMessages(account: interaction.interactionContext.account, peerId: interaction.peerId, messages: copies).startStandalone()
}

func regramRepeatForward(_ messages: [Message], interaction: ChatInteraction) {
    guard !messages.isEmpty, messages.count <= 100, regramCanRepeatHere(messages, interaction: interaction),
          messages.allSatisfy({ canForwardMessage($0, chatInteraction: interaction) }) else { return }
    _ = Sender.forwardMessages(messageIds: messages.map { $0.id }, context: interaction.interactionContext, peerId: interaction.peerId, replyId: nil, threadId: interaction.chatLocation.threadId, sendAsPeerId: interaction.presentation.currentSendAsPeerId).startStandalone()
}
