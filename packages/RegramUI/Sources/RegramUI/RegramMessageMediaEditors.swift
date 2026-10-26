import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import InputDataUI
import GeneralRows
import RegramCore
import RegramSignals

public func RegramLinkPreviewSettingsController(context: any AccountContextProtocol) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let signal = combineLatest(regramPreferenceChanges(accountId: accountId), appearanceSignal) |> map { settings, _ -> InputDataSignalValue in
        var rows: [InputDataEntry] = [.sectionId(0, type: .normal)]
        rows.append(.general(sectionId: 1, index: 0, value: .none, error: nil, identifier: InputDataIdentifier("linkPreview.enabled"), data: .init(name: regramString("ios.LinkPreview.Repair"), color: theme.colors.text, type: .switchable(settings["fixLinkPreviews"].bool), viewType: .singleItem, action: { RegramPreferences.shared.update(accountId: accountId) { $0["fixLinkPreviews"] = .bool(!settings["fixLinkPreviews"].bool) } })))
        rows.append(.desc(sectionId: 1, index: 1, text: .plain(regramString("ios.LinkPreview.Repair.Notice")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        rows.append(.sectionId(1, type: .normal))
        rows.append(.desc(sectionId: 2, index: 2, text: .plain(regramString("ios.LinkPreview.Services")), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        for (index, value) in [("linkPreviewXHost", "xHost", "LinkPreview.XService"), ("linkPreviewInstagramHost", "instagramHost", "LinkPreview.InstagramService")].enumerated() {
            rows.append(.input(sectionId: 2, index: Int32(index + 3), value: .string(settings[value.0].string), error: nil, identifier: InputDataIdentifier("linkPreview." + value.1), mode: .plain, data: .init(viewType: index == 0 ? .firstItem : .innerItem), placeholder: nil, inputPlaceholder: regramString("ios." + value.2), filter: { $0 }, limit: 253))
        }
        rows.append(.general(sectionId: 2, index: 5, value: .none, error: nil, identifier: InputDataIdentifier("linkPreview.reset"), data: .init(name: regramString("ios.Common.Reset"), color: theme.colors.accent, type: .none, viewType: .lastItem, action: {
            RegramPreferences.shared.update(accountId: accountId) { settings in settings["linkPreviewXHost"] = .string(RGLinkPreviewRules.defaultXHost); settings["linkPreviewInstagramHost"] = .string(RGLinkPreviewRules.defaultInstagramHost) }
        })))
        rows.append(.desc(sectionId: 2, index: 6, text: .plain(regramString("ios.LinkPreview.InvalidHost")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        return InputDataSignalValue(entries: rows)
    }
    return InputDataController(dataSignal: signal, title: regramString("ios.LinkPreview.Repair"), updateDatas: { data in
        RegramPreferences.shared.update(accountId: accountId) { settings in
            for (key, item) in [("linkPreviewXHost", "xHost"), ("linkPreviewInstagramHost", "instagramHost")] {
                if let value = data[InputDataIdentifier("linkPreview." + item)]?.stringValue, RGLinkPreviewRules.isValidHost(value) { settings[key] = .string(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
            }
        }
        return .fail(.none)
    }, removeAfterDisappear: false, hasDone: false, identifier: "regram.linkPreview")
}
