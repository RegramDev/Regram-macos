import Cocoa
import Postbox
import TelegramCore
import TelegramUtils
import MessageUtils
import RegramCore
import TGUIKit

func regramHandleMessageDoubleClick(_ item: ChatRowItem, view: TableRowView, location: NSPoint) -> Bool {
    guard let message = item.message else { return false }
    let interaction = item.chatInteraction
    let settings = RegramPreferences.shared.settings(accountId: item.context.peerId.toInt64())
    let action = RGMessageDoubleClickAction.resolved(settings: settings, canEdit: canEditMessage(message, chatInteraction: interaction, context: item.context))
    switch action {
    case .disabled:
        return true
    case .sendReaction:
        _ = item.reactAction()
    case .showReactions:
        if item.canReact, let event = NSApp.currentEvent { view.showContextMenu(event) }
    case .reply:
        _ = item.replyAction()
    case .edit:
        _ = item.editAction()
    case .translate:
        regramToggleQuickTranslation(item)
    case .repeatMessage, .repeatWithoutQuote:
        let messages = item.entry.messages
        if action == .repeatMessage { regramRepeatForward(messages, interaction: interaction) }
        else { regramRepeatCopy(messages, interaction: interaction) }
    }
    return true
}
