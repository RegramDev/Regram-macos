import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import AudioPlayerUI
import AudioPlayerCore
import ChatHistoryModel

extension InstantVideoPIP: @retroactive InlineAudioPlayerInstantVideoPIP {

}

func installAudioPlayerUIHooks() {
    AudioPlayerHooks.install(AudioPlayerHooks(shouldIncludeMessage: { message, accountId in
        !regramShouldHideMessage(message, accountId: accountId)
    }, messageVisibilityChanges: { accountId in regramMessageFilterChanges(accountId: accountId) }))
    AudioPlayerUIHooks.install(AudioPlayerUIHooks(makeInstantVideoPip: { controller in
        return InstantVideoPIP(controller, context: controller.context.concrete, window: controller.context.concrete.window)
    }, updateInstantVideoPip: { instantVideoPip, tableView, controller in
        (instantVideoPip as? InstantVideoPIP)?.updateTableView(tableView, context: controller.context.concrete, controller: controller)
    }, hideInstantVideoPip: { instantVideoPip in
        (instantVideoPip as? InstantVideoPIP)?.hide()
    }, addGlobalAudioToVisible: { tableView, controller in
        tableView.enumerateViews(with: { (view) in
            var contentView: NSView? = (view as? ChatRowView)?.contentView.subviews.last ?? (view as? PeerMediaMusicRowView)
            if let view = ((view as? ChatMessageView)?.webpageContent as? WPMediaContentView)?.contentNode {
                contentView = view
            }

            if let view = view as? ChatGroupedView {
                for content in view.contents {
                    controller.add(listener: content)
                }
            } else if let view = contentView as? ChatAudioContentView {
                controller.add(listener: view)
            } else if let view = contentView as? ChatVideoMessageContentView {
                controller.add(listener: view)
            } else if let view = contentView as? WPMediaContentView {
                if let contentNode = view.contentNode as? ChatAudioContentView {
                    controller.add(listener: contentNode)
                }
            } else if let view = view as? PeerMediaMusicRowView {
                controller.add(listener: view)
            } else if let view = view as? PeerMediaVoiceRowView {
                controller.add(listener: view)
            } else if let view = view as? StorageUsageMediaItemView {
                controller.add(listener: view)
            } else if let view = view as? ChatRichTextRowView {
                for content in view.audioContentViews() {
                    controller.add(listener: content)
                }
            }
            return true
        })
    }, gotoMessage: { context, message in
        let context = context.concrete
        if let controller = context.bindings.rootNavigation().controller as? ChatController, controller.chatInteraction.peerId == message.id.peerId {
            controller.chatInteraction.focusMessageId(nil, .init(messageId: message.id, string: nil), .center(id: 0, innerId: nil, animated: true, focus: .init(focus: false), inset: 0))
        } else {
            navigateToChat(navigation: context.bindings.rootNavigation(), context: context, chatLocation: .peer(message.id.peerId), focusTarget: .init(messageId: message.id))
        }
    }, showChatPlayerList: { audioPlayer, controller, context, message, window in
        showModal(with: PlayerListController(audioPlayer: audioPlayer, context: controller.context.concrete, currentContext: context.concrete, source: .chat(message.id.peerId, MessageIndex(message), controller.messages)), for: window)
    }, showProfilePlayerList: { audioPlayer, controller, context, reference, window in
        showModal(with: PlayerListController(audioPlayer: audioPlayer, context: controller.context.concrete, currentContext: context.concrete, source: .profile(controller.peer, reference.media, controller.currentState, controller.profileMusicContext)), for: window)
    }, endInlinePlayer: { context, animated in
        context?.concrete.sharedContext.endInlinePlayer(animated: animated)
    }, getAudioPlayer: { context in
        return (context as! AccountContext).sharedContext.getAudioPlayer()
    }, focusSearch: { context, text in
        context.bindings.mainViewController.focusSearch(animated: true, text: text)
    }))
}
