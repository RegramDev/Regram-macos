import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramTheme
import TelegramContext
import Localization
import Translate
import ChatHistoryModel
import MessageUtils
import RegramCore
import RegramServices
import AlertsUI

private func quickTranslationString(_ key: String) -> String {
    regramLocalizedString(key, languageCode: appCurrentLanguage.primaryLanguage.languageCode)
}

private func quickTranslationKey(_ message: Message) -> RGBookmarkMessageId {
    RGBookmarkMessageId(peerId: message.id.peerId.toInt64(), namespace: message.id.namespace, id: message.id.id)
}

private func regramQuickTranslationCanProcess(_ item: ChatRowItem) -> Bool {
    guard let message = item.message, message.id.namespace == Namespaces.Message.Cloud,
          message.id.peerId.namespace != Namespaces.Peer.SecretChat, !message.text.isEmpty,
          message.adAttribute == nil, !message.containsSecretMedia, !message.isCopyProtected(cachedData: item.chatInteraction.presentation.cachedData),
          !message.attributes.contains(where: { $0 is RichTextMessageAttribute }),
          !message.media.contains(where: { $0 is TelegramMediaAction || $0 is TelegramMediaExpiredContent || $0 is TelegramMediaPaidContent }) else { return false }
    return true
}

func regramQuickTranslationIsAvailable(_ item: ChatRowItem) -> Bool {
    guard let message = item.message, item.isIncoming, regramQuickTranslationCanProcess(item) else { return false }
    let accountId = item.context.peerId.toInt64()
    let settings = RegramPreferences.shared.settings(accountId: accountId)
    if regramQuickTranslationLanguage(message, settings: settings) != nil || RegramQuickTranslationTasks.shared.task(accountId: accountId, messageId: quickTranslationKey(message)) != nil { return true }
    guard settings["quickTranslateButton"].bool, message.text.unicodeScalars.contains(where: CharacterSet.letters.contains) else { return false }
    guard let language = Translate.detectLanguage(for: String(message.text.prefix(512))) else { return true }
    let ignored = item.context.sharedContext.baseSettings.doNotTranslate.union([appAppearance.languageCode])
    let normalized = language.lowercased().split(separator: "-").first.map(String.init) ?? language
    return !ignored.contains { $0.lowercased().split(separator: "-").first.map(String.init) == normalized }
}

func regramToggleQuickTranslation(_ item: ChatRowItem) {
    guard let message = item.message else { return }
    let interaction = item.chatInteraction
    let context = item.context
    let accountId = context.peerId.toInt64()
    let settings = RegramPreferences.shared.settings(accountId: accountId)
    let key = quickTranslationKey(message)
    let tasks = RegramQuickTranslationTasks.shared
    if let pending = tasks.task(accountId: accountId, messageId: key) {
        tasks.finish(accountId: accountId, messageId: key, token: pending.token)
        interaction.regramQuickTranslationRequests.removeValue(forKey: message.id)?.dispose()
        return
    }
    if regramQuickTranslationLanguage(message, settings: settings) != nil {
        _ = context.account.postbox.transaction { transaction in
            transaction.updateMessage(message.id) { current in
                var attributes = current.attributes.filter { !($0 is RegramTranslationMessageAttribute) }
                attributes.append(RegramTranslationMessageAttribute(configuration: settings.translationIdentity, quickToLang: ""))
                return .update(quickTranslationStoreMessage(current, attributes: attributes))
            }
        }.startStandalone()
        return
    }
    guard regramQuickTranslationCanProcess(item) else { return }
    let target = appAppearance.languageCode
    guard let token = tasks.begin(accountId: accountId, messageId: key, language: target) else {
        showModalText(for: context.window, text: quickTranslationString("quickTranslate.busy"))
        return
    }
    let configuration = settings.translationIdentity
    let isCurrent = {
        tasks.task(accountId: accountId, messageId: key)?.token == token && RegramPreferences.shared.settings(accountId: accountId).translationIdentity == configuration
    }
    let entities = message.textEntitiesAttribute?.entities ?? []
    let external = settings["translationBackend"].string != "default"
    func externalRequest(_ configuration: RegramAccountSettings) -> Signal<(String, [MessageTextEntity]), TranslateFetchError> {
        let ranges = entities.enumerated().map { RGTranslationLinkPlan.ProtectedRange(range: NSRange(location: $0.element.range.lowerBound, length: $0.element.range.count), id: $0.offset) }
        let protected = Set(entities.enumerated().compactMap { index, entity -> Int? in
            switch entity.type {
            case .Code, .Pre, .TextUrl, .TextMention, .Mention, .CustomEmoji: return index
            default: return nil
            }
        })
        return context.account.postbox.transaction { transaction -> [String]? in
            guard let current = transaction.getMessage(message.id), current.stableVersion == message.stableVersion,
                  !current.containsSecretMedia, !current.isCopyProtected(cachedData: transaction.getPeerCachedData(peerId: current.id.peerId)),
                  !current.media.contains(where: { $0 is TelegramMediaPaidContent || $0 is TelegramMediaExpiredContent }) else { return nil }
            return regramLLMTranslationContext(transaction: transaction, message: current, settings: configuration)
        } |> castError(TranslateFetchError.self) |> mapToSignal { history -> Signal<(String, [MessageTextEntity]), TranslateFetchError> in
        guard let history, isCurrent() else { return .fail(.outdated) }
        return regramProtectedTranslation(text: message.text, to: target, accountId: accountId, settings: configuration, ranges: ranges, protectedIds: protected, context: history, permitsNetworkFallback: {
            context.account.postbox.transaction { transaction -> Bool in
                guard isCurrent(), let current = transaction.getMessage(message.id), current.stableVersion == message.stableVersion,
                      !current.containsSecretMedia, !current.isCopyProtected(cachedData: transaction.getPeerCachedData(peerId: current.id.peerId)),
                      !current.media.contains(where: { $0 is TelegramMediaPaidContent || $0 is TelegramMediaExpiredContent }) else { return false }
                return true
            }
        }) |> map { result in
            let restored = result.ranges.compactMap { range -> MessageTextEntity? in
                guard entities.indices.contains(range.id) else { return nil }
                return MessageTextEntity(range: range.range.location..<(range.range.location + range.range.length), type: entities[range.id].type)
            }
            return (result.text, restored)
        }
        }
    }
    let translated: Signal<(String, [MessageTextEntity]), TranslateFetchError>
    if external {
        translated = externalRequest(settings)
    } else {
        let native: Signal<(String, [MessageTextEntity])?, TranslationError> = context.engine.messages.translate(text: message.text, toLang: target, entities: entities, tone: .neutral) |> `catch` { error -> Signal<(String, [MessageTextEntity])?, TranslationError> in
            if case .tryAlternative = error { return .single(nil) }
            return .fail(error)
        }
        translated = native |> mapError { _ in TranslateFetchError.network } |> mapToSignal { result -> Signal<(String, [MessageTextEntity]), TranslateFetchError> in
            if let result, !result.0.isEmpty { return .single(result) }
            var fallback = settings
            fallback["translationBackend"] = .string("google")
            return externalRequest(fallback)
        }
    }
    let postbox = context.account.postbox
    let signal = translated |> mapToSignal { text, entities -> Signal<Void, TranslateFetchError> in
        guard isCurrent() else { return .fail(.outdated) }
        guard !text.isEmpty else { return .fail(.network) }
        return postbox.transaction { transaction -> Bool in
            var applied = false
            transaction.updateMessage(message.id) { current in
                guard current.stableVersion == message.stableVersion, isCurrent(), !current.isCopyProtected(cachedData: transaction.getPeerCachedData(peerId: current.id.peerId)) else { return .skip }
                var attributes = current.attributes.filter { !($0 is TranslationMessageAttribute || $0 is RegramTranslationMessageAttribute) }
                attributes.append(TranslationMessageAttribute(text: text, entities: entities, toLang: target))
                attributes.append(RegramTranslationMessageAttribute(configuration: configuration, quickToLang: target))
                applied = true
                return .update(quickTranslationStoreMessage(current, attributes: attributes))
            }
            return applied
        } |> castError(TranslateFetchError.self) |> mapToSignal { applied -> Signal<Void, TranslateFetchError> in
            applied ? .single(()) : .fail(.outdated)
        }
    } |> afterDisposed { tasks.finish(accountId: accountId, messageId: key, token: token) }
    let holder = MetaDisposable()
    interaction.regramQuickTranslationRequests[message.id] = holder
    holder.set((signal |> deliverOnMainQueue).start(error: { [weak context, weak interaction, weak holder] error in
        if let context { showModalText(for: context.window, text: quickTranslationString({ if case .outdated = error { return "quickTranslate.outdated" }; return "quickTranslate.failed" }())) }
        tasks.finish(accountId: accountId, messageId: key, token: token)
        if interaction?.regramQuickTranslationRequests[message.id] === holder { interaction?.regramQuickTranslationRequests.removeValue(forKey: message.id) }
    }, completed: { [weak interaction, weak holder] in
        tasks.finish(accountId: accountId, messageId: key, token: token)
        if interaction?.regramQuickTranslationRequests[message.id] === holder { interaction?.regramQuickTranslationRequests.removeValue(forKey: message.id) }
    }))
}

private func quickTranslationStoreMessage(_ message: Message, attributes: [MessageAttribute]) -> StoreMessage {
    StoreMessage(id: message.id, customStableId: nil, globallyUniqueId: message.globallyUniqueId, groupingKey: message.groupingKey, threadId: message.threadId, timestamp: message.timestamp, flags: StoreMessageFlags(message.flags), tags: message.tags, globalTags: message.globalTags, localTags: message.localTags, forwardInfo: message.forwardInfo.flatMap(StoreMessageForwardInfo.init), authorId: message.author?.id, text: message.text, attributes: attributes, media: message.media)
}

final class RegramQuickTranslationButton: ImageButton {
    private let progress = ProgressIndicator(frame: NSMakeRect(0, 0, 16, 16))

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        progress.isEventLess = true
        addSubview(progress)
        scaleOnClick = true
        set(cornerRadius: .half, for: .Normal)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ item: ChatRowItem) {
        guard let message = item.message else { return }
        let accountId = item.context.peerId.toInt64()
        let loading = RegramQuickTranslationTasks.shared.task(accountId: accountId, messageId: quickTranslationKey(message)) != nil
        let active = regramQuickTranslationLanguage(message, settings: RegramPreferences.shared.settings(accountId: accountId)) != nil
        backgroundColor = item.presentation.colors.grayBackground
        set(image: item.presentation.icons.chat_translate, for: .Normal)
        imageView.isHidden = loading
        progress.isHidden = !loading
        progress.progressColor = item.presentation.colors.accent
        setAccessibilityLabel(quickTranslationString(loading ? "quickTranslate.cancel" : active ? "quickTranslate.original" : "quickTranslate.action"))
        appTooltip = active && !loading ? nil : quickTranslationString(loading ? "quickTranslate.cancel" : "quickTranslate.action")
        removeAllHandlers()
        set(handler: { [weak item] _ in if let item { regramToggleQuickTranslation(item) } }, for: .Click)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        progress.center()
    }
}
