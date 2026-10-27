import Cocoa
import Postbox
import TelegramCore
import TelegramContext
import TelegramTheme
import SwiftSignalKit
import TGUIKit
import InputDataUI
import RegramCore
import RegramSignals

public func RegramChatPreferencesController(context: any AccountContextProtocol, peerId: PeerId? = nil, focusSetting: String? = nil) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let selectedValue = Atomic(value: peerId)
    let selected = ValuePromise<PeerId?>(peerId, ignoreRepeated: true)
    let selection = MetaDisposable()

    func currentPeerId() -> PeerId? {
        guard !context.isFrozen, context.peerId.toInt64() == accountId else { return nil }
        return selectedValue.with { $0 }
    }
    func saveCurrent(transform: (inout RGChatPreferences) -> Void) {
        guard let peerId = currentPeerId() else { return }
        RegramPreferences.shared.update(accountId: accountId) { settings in
            var values = (try? JSONDecoder().decode([String: RGChatPreferences].self, from: Data(settings["chatPreferences"].string.utf8))) ?? [:]
            var value = settings.chatPreferences(accountId: accountId, peerId: peerId.toInt64())
            transform(&value)
            values.removeValue(forKey: String(peerId.toInt64()))
            values[RGChatPreferences.key(accountId: accountId, peerId: peerId.toInt64())] = value.isEmpty ? nil : value
            if let data = try? JSONEncoder().encode(values), let text = String(data: data, encoding: .utf8) { settings["chatPreferences"] = .string(text) }
        }
    }

    let signal = combineLatest(selected.get(), regramPreferenceChanges(accountId: accountId), appearanceSignal) |> mapToSignal { peerId, settings, _ in
        context.account.postbox.transaction { transaction in (peerId, peerId.flatMap(transaction.getPeer), settings) }
    } |> deliverOnMainQueue |> map { peerId, peer, settings -> InputDataSignalValue in
        var rows: [InputDataEntry] = [.sectionId(0, type: .normal)]
        rows.append(.general(sectionId: 1, index: 0, value: .none, error: nil, identifier: InputDataIdentifier("chatPreferences.selectChat"), data: .init(name: peer?.displayTitle ?? regramString("ChatPreferences.SelectChat"), color: theme.colors.text, type: .next, viewType: .singleItem, action: {
            guard !context.isFrozen, context.peerId.toInt64() == accountId else { return }
            selection.set((RegramUIHooks.shared.selectChat(context, currentPeerId()) |> deliverOnMainQueue).start(next: { peerId in
                guard !context.isFrozen, context.peerId.toInt64() == accountId else { return }
                _ = selectedValue.swap(peerId)
                selected.set(peerId)
            }))
        })))
        rows.append(.desc(sectionId: 1, index: 1, text: .plain(regramString("ChatPreferences.Notice")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        if let peerId {
            let preferences = settings.chatPreferences(accountId: accountId, peerId: peerId.toInt64())
            rows.append(.sectionId(1, type: .normal))
            let formats: [String?] = [nil, "none", "bold", "italic", "underline", "strikethrough", "spoiler"]
            let formatItems = formats.map { format in
                ContextMenuItem(regramString(format.map { "OutgoingFormatting." + $0 } ?? "ChatPreferences.Inherit"), handler: { saveCurrent { $0.formatting = format } }, state: preferences.formatting == format ? .on : .off)
            }
            rows.append(.general(sectionId: 2, index: 2, value: .none, error: nil, identifier: InputDataIdentifier("chatPreferences.formatting"), data: .init(name: regramString("OutgoingFormatting.Title"), color: theme.colors.text, type: .contextSelector(regramString(preferences.formatting.map { "OutgoingFormatting." + $0 } ?? "ChatPreferences.Inherit"), formatItems), viewType: .firstItem)))
            let pangu: [Bool?] = [nil, true, false]
            let panguItems = pangu.map { choice in
                ContextMenuItem(regramString(choice.map { $0 ? "ChatPreferences.On" : "ChatPreferences.Off" } ?? "ChatPreferences.Inherit"), handler: { saveCurrent { $0.panguSpacing = choice } }, state: preferences.panguSpacing == choice ? .on : .off)
            }
            rows.append(.general(sectionId: 2, index: 3, value: .none, error: nil, identifier: InputDataIdentifier("chatPreferences.panguSpacing"), data: .init(name: regramString("Pangu.Title"), color: theme.colors.text, type: .contextSelector(regramString(preferences.panguSpacing.map { $0 ? "ChatPreferences.On" : "ChatPreferences.Off" } ?? "ChatPreferences.Inherit"), panguItems), viewType: .innerItem)))
            rows.append(.general(sectionId: 2, index: 4, value: .none, error: nil, identifier: InputDataIdentifier("chatPreferences.reset"), data: .init(name: regramString("ChatPreferences.Reset"), color: theme.colors.accent, type: .none, viewType: .lastItem, action: { saveCurrent { $0 = RGChatPreferences() } })))
            rows.append(.sectionId(2, type: .normal))
            let revealed = RegramTemporaryReveal.shared.isRevealed(accountId: accountId, peerId: peerId.toInt64())
            rows.append(.general(sectionId: 3, index: 5, value: .none, error: nil, identifier: InputDataIdentifier("chatPreferences.reveal"), data: .init(name: regramString(revealed ? "ChatPreferences.Reveal.End" : "ChatPreferences.Reveal"), color: theme.colors.accent, type: .none, viewType: .singleItem, action: {
                guard let peerId = currentPeerId() else { return }
                let revealed = RegramTemporaryReveal.shared.isRevealed(accountId: accountId, peerId: peerId.toInt64())
                RegramTemporaryReveal.shared.setRevealed(!revealed, accountId: accountId, peerId: peerId.toInt64())
            })))
            rows.append(.desc(sectionId: 3, index: 6, text: .plain(regramString("ChatPreferences.Reveal.Notice")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        }
        return InputDataSignalValue(entries: rows)
    }
    let controller = InputDataController(dataSignal: signal, title: regramString("ChatPreferences.Title"), removeAfterDisappear: false, hasDone: false, identifier: "regram.chatPreferences")
    controller.onDeinit = { selection.dispose() }
    regramFocusSettings(controller, page: "chatPreferences", item: focusSetting)
    return controller
}
