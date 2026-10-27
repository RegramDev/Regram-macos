import Cocoa
import Postbox
import TelegramCore
import ChatHistoryModel

func regramMessageView(messageId: MessageId, interaction: ChatInteraction) -> ChatRowView? {
    func find(_ view: NSView) -> ChatRowView? {
        if let row = view as? ChatRowView, let item = row.item as? ChatRowItem,
           item.chatInteraction === interaction, item.entry.messages.contains(where: { $0.id == messageId }) { return row }
        for child in view.subviews {
            if let found = find(child) { return found }
        }
        return nil
    }
    guard Thread.isMainThread, let contentView = interaction.interactionContext.window.contentView else { return nil }
    return find(contentView)
}

func regramLoadedMessages(message: Message, interaction: ChatInteraction) -> [Message] {
    guard let table = regramMessageView(messageId: message.id, interaction: interaction)?.item?.table else { return [] }
    var result: [Message] = []
    var ids = Set<MessageId>()
    table.enumerateItems { item in
        if let item = item as? ChatRowItem, item.chatInteraction === interaction {
            for message in item.entry.messages where ids.insert(message.id).inserted { result.append(message) }
        }
        return true
    }
    return result.sorted { $0.index < $1.index }
}

func regramSelectMessagesFromSender(_ message: Message, interaction: ChatInteraction) -> [MessageId] {
    guard !interaction.disableSelectAbility, !interaction.isLogInteraction, let authorId = message.author?.id else { return [] }
    let threadId = interaction.chatLocation.threadId
    return Array(regramLoadedMessages(message: message, interaction: interaction).reversed().filter {
        $0.author?.id == authorId && $0.id.peerId == interaction.peerId && $0.id.namespace == Namespaces.Message.Cloud
            && (threadId == nil || $0.threadId == threadId) && !$0.media.contains(where: { $0 is TelegramMediaAction })
    }.prefix(100).map(\.id))
}

