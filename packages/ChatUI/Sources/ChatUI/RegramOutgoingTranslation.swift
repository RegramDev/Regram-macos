import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramTheme
import TelegramContext
import Localization
import InputDataUI
import InputView
import RegramCore
import RegramServices
import ChatHistoryModel

private struct OutgoingTranslationState: Equatable {
    var busy = false
    var translated: ChatTextInputState?
    var error = ""
}

private func outgoingTranslationString(_ key: String) -> String { regramLocalizedString(key, languageCode: appCurrentLanguage.primaryLanguage.languageCode) }

private func outgoingTranslationInput(text: String, entities: [MessageTextEntity], original: ChatTextInputState) -> ChatTextInputState {
    let attributes = chatTextAttributes(from: TextEntitiesMessageAttribute(entities: entities)).map { attribute -> ChatTextInputAttribute in
        if case let .animated(range, _, fileId, _, _) = attribute {
            for original in original.attributes {
                if case let .animated(_, id, originalFileId, file, info) = original, fileId == originalFileId {
                    return .animated(range, id, fileId, file, info)
                }
            }
        }
        return attribute
    }
    let length = text.utf16.count
    return ChatTextInputState(inputText: text, selectionRange: length..<length, attributes: attributes)
}

private func outgoingTranslationContext(account: Account, peerId: PeerId, threadId: Int64?, settings: RegramAccountSettings) -> Signal<[String], NoError> {
    return account.postbox.transaction { transaction in
        regramLLMTranslationContext(transaction: transaction, peerId: peerId, threadId: threadId, settings: settings)
    }
}

func regramTranslateOutgoingInput(context: any AccountContextProtocol, peerId: PeerId, threadId: Int64?, input: ChatTextInputState, target: String, settings: RegramAccountSettings) -> Signal<ChatTextInputState, TranslateFetchError> {
    let entities = input.messageTextEntities()
    func external(_ configuration: RegramAccountSettings) -> Signal<ChatTextInputState, TranslateFetchError> {
        let ranges = entities.enumerated().map { RGTranslationLinkPlan.ProtectedRange(range: NSRange(location: $0.element.range.lowerBound, length: $0.element.range.count), id: $0.offset) }
        let protectedIds = Set(entities.enumerated().compactMap { index, entity -> Int? in
            switch entity.type {
            case .Code, .Pre, .TextUrl, .TextMention, .Mention, .CustomEmoji, .BotCommand, .Email, .PhoneNumber, .Hashtag, .BankCard: return index
            default: return nil
            }
        })
        return outgoingTranslationContext(account: context.account, peerId: peerId, threadId: threadId, settings: configuration) |> castError(TranslateFetchError.self) |> mapToSignal { history in
            regramProtectedTranslation(text: input.inputText, to: target, accountId: context.peerId.toInt64(), settings: configuration, ranges: ranges, protectedIds: protectedIds, context: history) |> map { result in
                let converted = result.ranges.compactMap { range -> MessageTextEntity? in
                    guard entities.indices.contains(range.id) else { return nil }
                    return MessageTextEntity(range: range.range.location..<(range.range.location + range.range.length), type: entities[range.id].type)
                }
                return outgoingTranslationInput(text: result.text, entities: converted, original: input)
            }
        }
    }
    if settings["translationBackend"].string != "default" { return external(settings) }
    let native = context.engine.messages.translate(text: input.inputText, toLang: target, entities: entities, tone: .neutral) |> `catch` { error -> Signal<(String, [MessageTextEntity])?, TranslationError> in
        if case .tryAlternative = error { return .single(nil) }
        return .fail(error)
    }
    return native |> mapError { _ in TranslateFetchError.network } |> mapToSignal { result in
        if let result, !result.0.isEmpty { return .single(outgoingTranslationInput(text: result.0, entities: result.1, original: input)) }
        var fallback = settings
        fallback["translationBackend"] = .string("google")
        return external(fallback)
    }
}

public func regramPresentOutgoingTranslation(context: any AccountContextProtocol, interaction: ChatInteraction, input suppliedInput: ChatTextInputState? = nil, applyToDraft: Bool = false, completion: @escaping (ChatTextInputState) -> Void) -> Bool {
    let presentation = interaction.presentation
    let accountId = context.peerId.toInt64()
    let settings = RegramPreferences.shared.settings(accountId: accountId)
    let input = suppliedInput ?? presentation.effectiveInput
    guard suppliedInput != nil || presentation.abilityToSend, presentation.interfaceState.editState == nil, interaction.richTextDraft == nil,
          interaction.peerId.namespace != Namespaces.Peer.SecretChat, !input.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          let target = RegramOutgoingTranslationPolicy.language(settings: settings, accountId: accountId, peerId: interaction.peerId.toInt64()) else { return false }
    let action = interaction.captureDeferredSendAction()
    let state = Atomic(value: OutgoingTranslationState())
    let promise = ValuePromise(OutgoingTranslationState(), ignoreRepeated: true)
    let request = MetaDisposable()
    var generation = UUID()
    var close: (() -> Void)?
    func update(_ transform: (inout OutgoingTranslationState) -> Void) { promise.set(state.modify { value in var value = value; transform(&value); return value }) }
    func cancel() { generation = UUID(); request.set(nil); update { $0.busy = false } }
    func isCurrent() -> Bool {
        let current = RegramPreferences.shared.settings(accountId: accountId)
        return action.isAvailable && current.translationIdentity == settings.translationIdentity && RegramOutgoingTranslationPolicy.language(settings: current, accountId: accountId, peerId: interaction.peerId.toInt64()) == target
    }
    func translate() {
        guard !state.with({ $0.busy }) else { cancel(); return }
        guard isCurrent() else { update { $0.error = outgoingTranslationString("outgoingTranslation.outdated") }; return }
        let token = UUID()
        generation = token
        update { $0.busy = true; $0.error = ""; $0.translated = nil }
        request.set((regramTranslateOutgoingInput(context: context, peerId: interaction.peerId, threadId: interaction.chatLocation.threadId, input: input, target: target, settings: settings) |> timeout(180, queue: .mainQueue(), alternate: .fail(.network)) |> deliverOnMainQueue).start(next: { translated in
            guard generation == token else { return }
            guard isCurrent(), !translated.inputText.isEmpty else { update { $0.busy = false; $0.error = outgoingTranslationString("outgoingTranslation.outdated") }; return }
            update { $0.busy = false; $0.translated = translated }
        }, error: { _ in
            guard generation == token else { return }
            update { $0.busy = false; $0.error = outgoingTranslationString("outgoingTranslation.failed") }
        }))
    }
    func accept() {
        guard let translated = state.with({ $0.translated }), isCurrent(), action.takeIfCurrent() else { update { $0.error = outgoingTranslationString("outgoingTranslation.outdated") }; return }
        close?()
        completion(translated)
    }
    let language = Locale(identifier: appCurrentLanguage.primaryLanguage.languageCode).localizedString(forIdentifier: target) ?? target
    let signal = combineLatest(promise.get(), appearanceSignal) |> map { value, _ -> InputDataSignalValue in
        var rows: [InputDataEntry] = [
            .sectionId(0, type: .normal),
            .desc(sectionId: 1, index: 0, text: .plain(outgoingTranslationString("outgoingTranslation.target") + ": " + language), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)),
            .desc(sectionId: 1, index: 1, text: .plain(input.inputText), data: .init(color: theme.colors.grayText, viewType: .textBottomItem))
        ]
        if let translated = value.translated {
            rows.append(.sectionId(1, type: .normal))
            rows.append(.desc(sectionId: 2, index: 2, text: .plain(translated.inputText), data: .init(color: theme.colors.text, viewType: .textTopItem)))
        }
        if !value.error.isEmpty { rows.append(.desc(sectionId: 2, index: 3, text: .plain(value.error), data: .init(color: theme.colors.redUI, viewType: .textBottomItem))) }
        rows.append(.general(sectionId: 2, index: 4, value: .none, error: nil, identifier: InputDataIdentifier("outgoing_translation_retry"), data: .init(name: outgoingTranslationString(value.busy ? "cancel" : "outgoingTranslation.retry"), color: theme.colors.accent, type: value.busy ? .loading : .none, viewType: .singleItem, action: translate)))
        return InputDataSignalValue(entries: rows)
    }
    let controller = InputDataController(dataSignal: signal, title: outgoingTranslationString("outgoingTranslation.preview"), validateData: { _ in accept(); return .fail(.none) }, afterDisappear: cancel, hasDone: false)
    let interactions = ModalInteractions(acceptTitle: applyToDraft ? strings().translateApply : outgoingTranslationString("outgoingTranslation.send"), accept: accept, singleButton: true)
    let buttonState = (promise.get() |> deliverOnMainQueue).start(next: { value in
        interactions.updateDone { $0.userInteractionEnabled = !value.busy && value.translated != nil }
    })
    let modal = InputDataModalController(controller, modalInteractions: interactions, size: NSMakeSize(430, 400))
    close = { [weak modal] in modal?.modal?.close() }
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { cancel(); close?() })
    controller.onDeinit = { request.dispose(); buttonState.dispose() }
    showModal(with: modal, for: context.window)
    DispatchQueue.main.async(execute: translate)
    return true
}
