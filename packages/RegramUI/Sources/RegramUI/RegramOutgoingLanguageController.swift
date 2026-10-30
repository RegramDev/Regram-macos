import Cocoa
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramContext
import TelegramTheme
import InputDataUI
import RegramCore
import RegramServices
import Localization

public func RegramOutgoingLanguageController(context: any AccountContextProtocol, peerId: PeerId, focusSetting: String? = nil) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let key = RegramOutgoingTranslationPolicy.key(accountId: accountId, peerId: peerId.toInt64())
    let settings = RegramPreferences.shared.settings(accountId: accountId)
    let query = Atomic(value: "")
    let queryPromise = ValuePromise("", ignoreRepeated: true)
    let selected: String?
    if case let .dictionary(values) = settings["outgoingLanguageTranslation"] { selected = values[key] } else { selected = nil }
    let popular = ["en", "ar", "zh", "fr", "de", "it", "ja", "ko", "pt-BR", "ru", "es", "uk"]
    let supported = ["af", "sq", "am", "ar", "hy", "az", "eu", "be", "bn", "bs", "bg", "ca", "ceb", "zh", "co", "hr", "cs", "da", "nl", "en", "eo", "et", "fi", "fr", "fy", "gl", "ka", "de", "el", "gu", "ht", "ha", "haw", "he", "hi", "hmn", "hu", "is", "ig", "id", "ga", "it", "ja", "jv", "kn", "kk", "km", "rw", "ko", "ku", "ky", "lo", "lv", "lt", "lb", "mk", "mg", "ms", "ml", "mt", "mi", "mr", "mn", "my", "ne", "no", "ny", "or", "ps", "fa", "pl", "pt", "pt-BR", "pa", "ro", "ru", "sm", "gd", "sr", "st", "sn", "sd", "si", "sk", "sl", "so", "es", "su", "sw", "sv", "tl", "tg", "ta", "tt", "te", "th", "tr", "tk", "uk", "ur", "ug", "uz", "vi", "cy", "xh", "yi", "yo", "zu"]
    var visited = Set<String>()
    let english = Locale(identifier: "en")
    let locale = Locale(identifier: appCurrentLanguage.primaryLanguage.languageCode)
    let languages = ((selected.flatMap { $0 == "off" ? nil : [$0] } ?? []) + popular + supported + ["zh-hans", "zh-hant"]).compactMap { code -> (String, String, String)? in
        guard visited.insert(code).inserted, let title = english.localizedString(forLanguageCode: code) else { return nil }
        var subtitle = Locale(identifier: code).localizedString(forLanguageCode: code) ?? title
        if code == "zh-hans" || code == "zh-hant" { subtitle += " " + code }
        return (code, (locale.localizedString(forLanguageCode: code) ?? title).capitalized, subtitle.capitalized)
    }
    func select(_ language: String) {
        RegramPreferences.shared.update(accountId: accountId) { settings in
            var values: [String: String] = [:]
            if case let .dictionary(current) = settings["outgoingLanguageTranslation"] { values = current }
            values[key] = language
            settings["outgoingLanguageTranslation"] = .dictionary(values)
        }
        context.bindings.rootNavigation().back()
    }
    let signal = combineLatest(queryPromise.get(), appearanceSignal) |> map { query, _ -> InputDataSignalValue in
        var rows: [InputDataEntry] = [.sectionId(0, type: .normal)]
        rows.append(regramSearchEntry(sectionId: 1, index: 0, value: query, identifier: InputDataIdentifier("outgoingTranslation.search"), update: { queryPromise.set($0) }))
        rows.append(.sectionId(1, type: .normal))
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let offTitle = regramString("ChatPreferences.Off")
        if value.isEmpty || offTitle.range(of: value, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil {
            rows.append(.general(sectionId: 2, index: 0, value: .none, error: nil, identifier: InputDataIdentifier("outgoingTranslation.off"), data: .init(name: offTitle, color: theme.colors.text, type: .selectable(selected == nil || selected == "off"), viewType: .singleItem, action: { select("off") })))
            rows.append(.sectionId(2, type: .normal))
        }
        let visible = languages.filter { value.isEmpty || [$0.0, $0.1, $0.2].contains { $0.range(of: value, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil } }
        for (index, language) in visible.enumerated() {
            rows.append(.general(sectionId: 3, index: Int32(index + 1), value: .none, error: nil, identifier: InputDataIdentifier("outgoingTranslation." + language.0), data: .init(name: language.1, color: theme.colors.text, type: .selectable(selected == language.0), viewType: visible.count == 1 ? .singleItem : index == 0 ? .firstItem : index + 1 == visible.count ? .lastItem : .innerItem, description: language.2, action: {
                let code = language.0 == "nb" ? "no" : language.0 == "pt-br" ? "pt" : language.0
                select(code)
            })))
        }
        if visible.isEmpty && !value.isEmpty && offTitle.range(of: value, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) == nil {
            rows.append(.custom(sectionId: 3, index: 1, value: .none, identifier: InputDataIdentifier("outgoingTranslation.empty"), equatable: InputDataEquatable(query), comparable: nil, item: { size, stableId in
                RegramEmptyRowItem(size, stableId: stableId, text: regramString("Settings.Search.NoResults"))
            }))
        }
        return InputDataSignalValue(entries: rows)
    }
    let controller = RegramFormController(dataSignal: signal, title: regramString("outgoingTranslation.changeLanguage"), removeAfterDisappear: false, hasDone: false, identifier: "regram.outgoingTranslation", selectionStyle: .single)
    let queryDisposable = queryPromise.get().start(next: { _ = query.swap($0) })
    controller.onDeinit = { queryDisposable.dispose() }
    regramRestoreSearchQuery(controller, identifier: InputDataIdentifier("outgoingTranslation.search"), query: { query.with { $0 } })
    regramFocusSettings(controller, page: "outgoingTranslation", item: focusSetting)
    return controller
}
