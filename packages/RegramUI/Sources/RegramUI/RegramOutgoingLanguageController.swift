import Cocoa
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramContext
import TelegramTheme
import InputDataUI
import RegramCore
import RegramServices

public func RegramOutgoingLanguageController(context: any AccountContextProtocol, peerId: PeerId, focusSetting: String? = nil) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let key = RegramOutgoingTranslationPolicy.key(accountId: context.peerId.id._internalGetInt64Value(), peerId: peerId.id._internalGetInt64Value())
    let settings = RegramPreferences.shared.settings(accountId: accountId)
    let selected: String?
    if case let .dictionary(values) = settings["outgoingLanguageTranslation"] { selected = values[key] } else { selected = nil }
    let popular = ["en", "ar", "zh", "fr", "de", "it", "ja", "ko", "pt-BR", "ru", "es", "uk"]
    let supported = ["af", "sq", "am", "ar", "hy", "az", "eu", "be", "bn", "bs", "bg", "ca", "ceb", "zh", "co", "hr", "cs", "da", "nl", "en", "eo", "et", "fi", "fr", "fy", "gl", "ka", "de", "el", "gu", "ht", "ha", "haw", "he", "hi", "hmn", "hu", "is", "ig", "id", "ga", "it", "ja", "jv", "kn", "kk", "km", "rw", "ko", "ku", "ky", "lo", "lv", "lt", "lb", "mk", "mg", "ms", "ml", "mt", "mi", "mr", "mn", "my", "ne", "no", "ny", "or", "ps", "fa", "pl", "pt", "pt-BR", "pa", "ro", "ru", "sm", "gd", "sr", "st", "sn", "sd", "si", "sk", "sl", "so", "es", "su", "sw", "sv", "tl", "tg", "ta", "tt", "te", "th", "tr", "tk", "uk", "ur", "ug", "uz", "vi", "cy", "xh", "yi", "yo", "zu"]
    var visited = Set<String>()
    let english = Locale(identifier: "en")
    let languages = ((selected.map { [$0] } ?? []) + popular + supported + ["zh-hans", "zh-hant"]).compactMap { code -> (String, String, String)? in
        guard visited.insert(code).inserted, let title = english.localizedString(forLanguageCode: code) else { return nil }
        var subtitle = Locale(identifier: code).localizedString(forLanguageCode: code) ?? title
        if code == "zh-hans" || code == "zh-hant" { subtitle += " " + code }
        return (code, title.capitalized, subtitle.capitalized)
    }
    let signal = appearanceSignal |> map { _ -> InputDataSignalValue in
        var rows: [InputDataEntry] = [.sectionId(0, type: .normal)]
        for (index, language) in languages.enumerated() {
            rows.append(.general(sectionId: 1, index: Int32(index), value: .none, error: nil, identifier: InputDataIdentifier("outgoingTranslation." + language.0), data: .init(name: language.1, color: theme.colors.text, type: .selectable(selected == language.0), viewType: index == 0 ? .firstItem : index + 1 == languages.count ? .lastItem : .innerItem, description: language.2, action: {
                let code = language.0 == "nb" ? "no" : language.0 == "pt-br" ? "pt" : language.0
                RegramPreferences.shared.update(accountId: accountId) { settings in
                    var values: [String: String] = [:]
                    if case let .dictionary(current) = settings["outgoingLanguageTranslation"] { values = current }
                    values[key] = code
                    settings["outgoingLanguageTranslation"] = .dictionary(values)
                }
                context.bindings.rootNavigation().back()
            })))
        }
        return InputDataSignalValue(entries: rows)
    }
    let controller = InputDataController(dataSignal: signal, title: regramString("outgoingTranslation.changeLanguage"), removeAfterDisappear: false, hasDone: false, identifier: "regram.outgoingTranslation")
    regramFocusSettings(controller, page: "outgoingTranslation", item: focusSetting)
    return controller
}
