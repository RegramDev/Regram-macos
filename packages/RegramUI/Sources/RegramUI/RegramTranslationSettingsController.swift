import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import Localization
import InputDataUI
import GeneralRows
import AlertsUI
import RegramCore
import RegramSignals

public func RegramTranslationSettingsController(context: any AccountContextProtocol, focusSetting: String? = nil) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let signal = combineLatest(regramPreferenceChanges(accountId: accountId), appearanceSignal) |> map { settings, _ -> InputDataSignalValue in
        let backend = settings["translationBackend"].string
        let options = ["default", "google", "googleCN", "microsoft", "yandex", "transmart", "llm", "system"].map { option in
            ContextMenuItem(regramString("Settings.Translation.Backend." + option), handler: {
                if option == "system" {
                    guard #available(macOS 15.0, *) else { alert(for: context.window, info: regramString("translation.systemUnavailable")); return }
                }
                RegramPreferences.shared.update(accountId: accountId) { $0["translationBackend"] = .string(option) }
            }, state: backend == option ? .on : .off)
        }
        var rows: [InputDataEntry] = [
            .sectionId(0, type: .normal),
            .desc(sectionId: 1, index: 0, text: .plain(strings().languageTranslateMessagesHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)),
            .general(sectionId: 1, index: 1, value: .none, error: nil, identifier: InputDataIdentifier("settings.translation.translationBackend"), data: .init(name: regramString("Settings.Translation.Backend"), color: theme.colors.text, type: .contextSelector(regramString("Settings.Translation.Backend." + backend), options), viewType: .firstItem))
        ]
        rows.append(.general(sectionId: 1, index: 3, value: .none, error: nil, identifier: InputDataIdentifier("settings.translation.llmTranslationSettings"), data: .init(name: regramString("LLMTranslation.Title"), color: theme.colors.text, type: .next, viewType: .innerItem, action: { context.bindings.rootNavigation().push(RegramServiceController(context: context, purpose: .translation)) })))
        rows.append(.general(sectionId: 1, index: 4, value: .none, error: nil, identifier: InputDataIdentifier("settings.translation.quickTranslateButton"), data: .init(name: regramString("Settings.Translation.QuickTranslateButton"), color: theme.colors.text, type: .switchable(settings["quickTranslateButton"].bool), viewType: .innerItem, action: { RegramPreferences.shared.update(accountId: accountId) { $0["quickTranslateButton"] = .bool(!$0["quickTranslateButton"].bool) } })))
        rows.append(.general(sectionId: 1, index: 5, value: .none, error: nil, identifier: InputDataIdentifier("settings.translation.languageSettings"), data: .init(name: strings().languageTranslateMessagesChannel, color: theme.colors.text, type: .next, viewType: .lastItem, action: { RegramUIHooks.shared.openNativeSettings(context, "translation") })))
        rows.append(.desc(sectionId: 1, index: 6, text: .markdown(regramString("Common.NoTelegramPremiumNeeded").replacingOccurrences(of: "%@", with: "Telegram Premium"), linkHandler: { _ in }), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        rows.append(.sectionId(2, type: .normal))
        rows.append(.desc(sectionId: 3, index: 7, text: .plain(regramString("Settings.Section.Speech")), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        rows.append(.general(sectionId: 3, index: 8, value: .none, error: nil, identifier: InputDataIdentifier("pro.translation.transcriptionSettings"), data: .init(name: regramString("RG.STTSettings"), color: theme.colors.text, type: .next, viewType: .singleItem, action: {
            context.bindings.rootNavigation().push(RegramServiceController(context: context, purpose: .transcription))
        })))
        rows.append(.desc(sectionId: 3, index: 9, text: .plain(regramString("Settings.Editor.transcriptionSettings.Description")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        return InputDataSignalValue(entries: rows)
    }
    let controller = RegramFormController(dataSignal: signal, title: regramString("Settings.ProCategory.translation"), removeAfterDisappear: false, hasDone: false, identifier: "regram.translation")
    regramFocusSettings(controller, page: "settings.translation", item: focusSetting)
    return controller
}
