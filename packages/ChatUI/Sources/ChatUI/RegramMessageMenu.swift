import Cocoa
import Postbox
import TelegramCore
import TelegramContext
import TelegramTheme
import SwiftSignalKit
import TGUIKit
import InputDataUI
import InputView
import Localization
import AlertsUI
import LocalAnimations
import RegramCore
import RegramServices
import ChatHistoryModel
import MessageUtils

private func menuTitle(_ id: String) -> String {
    regramLocalizedString(id, languageCode: appCurrentLanguage.primaryLanguage.languageCode)
}

func regramMessageMenu(message: Message, messages: [Message], interaction: ChatInteraction, canReply: Bool, canForward: Bool, filterImportData: Data? = nil) -> [ContextMenuItem] {
    let context = interaction.interactionContext
    let accountId = context.peerId.toInt64()
    let settings = RegramPreferences.shared.settings(accountId: accountId)
    let protected = message.containsSecretMedia || message.isCopyProtected(cachedData: interaction.presentation.cachedData)
    var result: [ContextMenuItem] = []
    if !message.text.isEmpty, !message.containsSecretMedia {
        let speech = RegramMessageSpeech.shared
        let title = speech.isSpeaking(accountId: accountId, messageId: message.id) ? "ios.Native.StopSpeaking" : "ios.Native.Speak"
        result.append(ContextMenuItem(menuTitle(title), handler: {
            speech.toggle(text: message.text, accountId: accountId, messageId: message.id)
        }, itemImage: MenuAnimation.menu_show_info.value).regramAction(.speak))
    }
    if settings["messageBookmarksEnabled"].bool, message.id.namespace == Namespaces.Message.Cloud, message.id.peerId.namespace != Namespaces.Peer.SecretChat, !message.containsSecretMedia {
        let bookmarkId = RGBookmarkMessageId(peerId: message.id.peerId.toInt64(), namespace: message.id.namespace, id: message.id.id)
        let bookmark = RGMessageBookmarks.shared.bookmark(accountId: accountId, messageId: bookmarkId)
        result.append(ContextMenuItem(menuTitle(bookmark == nil ? "menu.bookmark" : "menu.editBookmark"), handler: {
            guard RegramPreferences.shared.settings(accountId: accountId)["messageBookmarksEnabled"].bool else { return }
            let id = InputDataIdentifier("regram_bookmark_tags")
            let rows: [InputDataEntry] = [
                .sectionId(0, type: .normal),
                .input(sectionId: 1, index: 0, value: .string(bookmark?.tags.joined(separator: ", ") ?? ""), error: nil, identifier: id, mode: .plain, data: .init(viewType: .singleItem), placeholder: nil, inputPlaceholder: menuTitle("tags"), filter: { $0 }, limit: 1024)
            ]
            let controller = InputDataController(dataSignal: .single(InputDataSignalValue(entries: rows)), title: menuTitle("bookmarks"), validateData: { data in
                guard RegramPreferences.shared.settings(accountId: accountId)["messageBookmarksEnabled"].bool else { return .fail(.none) }
                RGMessageBookmarks.shared.save(accountId: accountId, messageId: bookmarkId, threadId: message.threadId, tags: (data[id]?.stringValue ?? "").components(separatedBy: ","))
                return .success(.navigationBack)
            })
            context.bindings.rootNavigation().push(controller)
        }, itemImage: MenuAnimation.menu_bookmark.value).regramAction(.bookmark))
    }
    if message.rgEditHistory != nil {
        result.append(ContextMenuItem(menuTitle("menu.editHistory"), handler: {
            if let controller = FeatureNavigationHooks.shared.makeRegramMessageController(context, message) { context.bindings.rootNavigation().push(controller) }
        }, itemImage: MenuAnimation.menu_edited.value).regramAction(.editHistory))
    }
    let filters = ContextMenu()
    if !message.text.isEmpty {
        filters.addItem(ContextMenuItem(menuTitle("menu.addFilter"), handler: {
            let rule = RGMessageFilterRule(pattern: message.text, peerIds: [message.id.peerId.toInt64()])
            RegramPreferences.shared.update(accountId: accountId) { value in
                var rules = value.filterRules
                if !rules.contains(where: { $0.hasSameDefinition(as: rule) }) { rules.append(rule) }
                value.filterRules = rules
            }
            if let controller = FeatureNavigationHooks.shared.makeRegramController(context, "filters") { context.bindings.rootNavigation().push(controller) }
        }, itemImage: MenuAnimation.menu_plus.value))
    }
    if let author = message.author, author.id != context.peerId {
        filters.addItem(ContextMenuItem(menuTitle("menu.hideSender"), handler: {
            RegramPreferences.shared.update(accountId: accountId) { value in
                var ids = value["blockedPeerIds"].strings
                let id = String(author.id.toInt64())
                if !ids.contains(id) { ids.append(id) }
                value["blockedPeerIds"] = .strings(ids)
            }
        }, itemImage: MenuAnimation.menu_hide.value))
    }
    if let filterImportData, let makeController = FeatureNavigationHooks.shared.makeRegramFilterImportController {
        filters.addItem(ContextMenuItem(menuTitle("MessageFilter.ImportFromBackup"), handler: {
            let allowed = context.account.postbox.transaction { transaction -> Bool in
                guard let current = transaction.getMessage(message.id), current.stableVersion == message.stableVersion else { return false }
                return regramCanSaveMessage(current, accountId: accountId, cachedData: transaction.getPeerCachedData(peerId: current.id.peerId))
            }
            interaction.regramServiceDisposable.set((allowed |> deliverOnMainQueue).start(next: { [weak interaction = interaction] allowed in
                guard let interaction, allowed, !context.isFrozen, interaction.peerId == message.id.peerId,
                      let controller = makeController(context, filterImportData) else { return }
                context.bindings.rootNavigation().push(controller)
            }))
        }, itemImage: MenuAnimation.menu_plus.value))
    }
    if !filters.items.isEmpty { filters.addItem(ContextSeparatorItem()) }
    let revealed = RegramTemporaryReveal.shared.isRevealed(accountId: accountId, peerId: message.id.peerId.toInt64())
    filters.addItem(ContextMenuItem(menuTitle(revealed ? "menu.restoreFilters" : "menu.revealFilters"), handler: {
        RegramTemporaryReveal.shared.setRevealed(!revealed, accountId: accountId, peerId: message.id.peerId.toInt64())
    }, itemImage: MenuAnimation.menu_eye.value))
    filters.addItem(ContextMenuItem(menuTitle("menu.chatSettings"), handler: {
        if let controller = FeatureNavigationHooks.shared.makeRegramController(context, "chat/\(message.id.peerId.toInt64())") { context.bindings.rootNavigation().push(controller) }
    }, itemImage: MenuAnimation.menu_show_info.value))
    let filterItem = ContextMenuItem(menuTitle("menu.addFilter"), itemImage: MenuAnimation.menu_hide.value).regramAction(.addFilter)
    filterItem.submenu = filters
    result.append(filterItem)
    result.append(ContextMenuItem(menuTitle("menu.json"), handler: {
        let details: [String: Any] = ["id": message.id.id, "namespace": message.id.namespace,
                                      "peerId": String(message.id.peerId.toInt64()), "timestamp": message.timestamp,
                                      "text": protected ? "" : message.text, "threadId": message.threadId.map(String.init) ?? "",
                                      "authorId": message.author.map { String($0.id.toInt64()) } ?? "",
                                      "mediaTypes": message.media.map { String(describing: type(of: $0)) }]
        if let data = try? JSONSerialization.data(withJSONObject: details, options: [.prettyPrinted, .sortedKeys]), let text = String(data: data, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }, itemImage: MenuAnimation.menu_copy.value).regramAction(.json))
    if canForward, !protected, message.id.namespace == Namespaces.Message.Cloud, messages.allSatisfy({ canForwardMessage($0, chatInteraction: interaction) }) {
        let forward = ChatForwardMenuAction(chatInteraction: interaction, sources: messages)
        let object = ChatHistoryUIHooks.shared.makeForwardMessagesObjectObserved(context, messages, false, interaction.getMessages)
        if canReply, regramCanRepeatHere(messages, interaction: interaction), let peer = interaction.presentation.peer, object.possibilityPerformTo(peer) {
            let action = interaction.captureDeferredSendAction()
            result.append(ContextMenuItem(menuTitle("menu.repeatForward"), handler: {
                guard action.takeIfCurrent() else { return }
                regramRepeatForward(messages, interaction: interaction)
            }, itemImage: MenuAnimation.menu_plus.value).regramAction(.repeatForward))
        }
        if let makeModal = ChatUIHooks.shared.makeForwardMessagesWithoutQuoteShareModal {
            let action = interaction.captureDeferredSendAction()
            result.append(ContextMenuItem(menuTitle("menu.forwardNoQuote"), handler: {
                guard action.takeIfCurrent() else { return }
                showModal(with: makeModal(context, messages, interaction.getMessages), for: context.window)
            }, itemImage: MenuAnimation.menu_forward.value).regramAction(.forwardNoQuote))
        }
        if message.id.peerId != context.peerId {
            result.append(ContextMenuItem(menuTitle("menu.saveToCloud"), handler: {
                forward.forward(object, peerId: context.peerId, threadId: nil)
            }, itemImage: MenuAnimation.menu_bookmark.value).regramAction(.saveToCloud))
        }
    }
    if canReply, !protected, regramCanRepeatHere(messages, interaction: interaction), regramRepeatCopyMessages(messages, interaction: interaction) != nil {
        let action = interaction.captureDeferredSendAction()
        result.append(ContextMenuItem(menuTitle("menu.repeatCopy"), handler: {
            guard action.takeIfCurrent() else { return }
            regramRepeatCopy(messages, interaction: interaction)
        }, itemImage: MenuAnimation.menu_plus.value).regramAction(.repeatCopy))
    }
    let senderMessages = regramSelectMessagesFromSender(message, interaction: interaction)
    if !senderMessages.isEmpty {
        result.append(ContextMenuItem(String(format: menuTitle("menu.selectFromSenderLoaded"), senderMessages.count), handler: {
            let ids = Set(regramSelectMessagesFromSender(message, interaction: interaction))
            guard !ids.isEmpty else { return }
            interaction.update { $0.withSelectionState().withUpdatedSelectedMessages(ids) }
        }, itemImage: MenuAnimation.menu_select_messages.value).regramAction(.selectFromUser))
    }
    if settings["showMediaMetadata"].bool, message.media.contains(where: { $0 is TelegramMediaImage || $0 is TelegramMediaFile }) {
        result.append(ContextMenuItem(menuTitle("mediaDetails.title"), handler: {
            context.bindings.rootNavigation().push(RegramMediaDetailsController(context: context, message: message))
        }, itemImage: MenuAnimation.menu_show_info.value))
    }
    if let file = message.media.compactMap({ $0 as? TelegramMediaFile }).first, file.isVoice || file.isInstantVideo {
        result.append(ContextMenuItem(menuTitle("transcription.tasks"), handler: {
            if let controller = FeatureNavigationHooks.shared.makeRegramController(context, "transcriptionTasks") { context.bindings.rootNavigation().push(controller) }
        }, itemImage: MenuAnimation.menu_show_info.value))
    }
    if !protected, message.id.peerId.namespace != Namespaces.Peer.SecretChat, let url = regramMessageWebURL(message) {
        result.append(ContextMenuItem(menuTitle("webTranslation.action"), handler: {
            if let controller = FeatureNavigationHooks.shared.makeRegramWebTranslationController(context, url) { context.bindings.rootNavigation().push(controller) }
        }, itemImage: MenuAnimation.menu_translate.value))
    }
    return result
}
