import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import InputDataUI
import AlertsUI
import RegramCore
import RegramSignals

private func regramPrivacyToolsController(context: any AccountContextProtocol, ghostMode: Bool, focusSetting: String?) -> InputDataController {
    let keys: [(String, String)] = ghostMode ? [
        ("ghostDontReadStories", "Ghost.DontReadStories"),
        ("ghostDontSendOnline", "Ghost.DontSendOnline"),
        ("ghostDontSendTyping", "Ghost.DontSendTyping")
    ] : [
        ("antiRevoke", "AntiFeatures.Revoke"),
        ("saveEditHistory", "AntiFeatures.EditHistory"),
        ("antiAutoDelete", "AntiFeatures.AutoDelete"),
        ("antiSelfDestruct", "AntiFeatures.SelfDestruct"),
        ("allowSavingProtectedContent", "AntiFeatures.SaveProtected"),
        ("allowDownloadingStories", "AntiFeatures.SaveProtectedStories"),
        ("disableAllAds", "AntiFeatures.DisableAds")
    ]
    let page = ghostMode ? "ghostMode" : "antiFeatures"
    let accountId = context.peerId.toInt64()
    let signal = combineLatest(regramPreferenceChanges(accountId: accountId), appearanceSignal) |> map { settings, _ -> InputDataSignalValue in
        var rows: [InputDataEntry] = [.sectionId(0, type: .normal)]
        let count = keys.count + (ghostMode ? 0 : 1)
        for (index, item) in keys.enumerated() {
            rows.append(.general(sectionId: 1, index: Int32(index), value: .none, error: nil, identifier: InputDataIdentifier(page + "." + item.0), data: .init(name: regramString(item.1), color: theme.colors.text, type: .switchable(settings[item.0].bool), viewType: index == 0 ? .firstItem : index + 1 == count ? .lastItem : .innerItem, action: {
                RegramPreferences.shared.update(accountId: accountId) { $0[item.0] = .bool(!$0[item.0].bool) }
            })))
        }
        if !ghostMode {
            rows.append(.general(sectionId: 1, index: Int32(keys.count), value: .none, error: nil, identifier: InputDataIdentifier("antiFeatures.revokedMarker"), data: .init(name: regramString("RevokedMarker.Title"), color: theme.colors.text, type: .next, viewType: .lastItem, action: { context.bindings.rootNavigation().push(RegramRevokedMarkerController(context: context)) })))
        }
        rows.append(.desc(sectionId: 1, index: Int32(count), text: .plain(regramString(ghostMode ? "Ghost.Notice" : "AntiFeatures.Notice")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        return InputDataSignalValue(entries: rows)
    }
    let controller = InputDataController(dataSignal: signal, title: regramString(ghostMode ? "Ghost.Header" : "AntiFeatures.Header"), removeAfterDisappear: false, hasDone: false, identifier: "regram.privacyTools")
    regramFocusSettings(controller, page: page, item: focusSetting)
    return controller
}

public func RegramAntiFeaturesController(context: any AccountContextProtocol, focusSetting: String? = nil) -> InputDataController {
    regramPrivacyToolsController(context: context, ghostMode: false, focusSetting: focusSetting)
}

public func RegramGhostModeController(context: any AccountContextProtocol, focusSetting: String? = nil) -> InputDataController {
    regramPrivacyToolsController(context: context, ghostMode: true, focusSetting: focusSetting)
}

public func RegramRevokedMarkerController(context: any AccountContextProtocol, focusSetting: String? = nil) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let initial = RegramRevokedMarker(settings: RegramPreferences.shared.settings(accountId: accountId))
    let state = Atomic(value: initial)
    let promise = ValuePromise(initial, ignoreRepeated: true)
    func update(_ transform: (inout RegramRevokedMarker) -> Void) { promise.set(state.modify { current in var value = current; transform(&value); return value }) }
    let signal = combineLatest(promise.get(), appearanceSignal) |> map { marker, _ -> InputDataSignalValue in
        var rows: [InputDataEntry] = [.sectionId(0, type: .normal)]
        let invalidColor = marker.style != .none && !marker.color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && RegramRevokedMarker.rgb(marker.color) == nil
        let choices = RegramRevokedMarker.Style.allCases.map { style in ContextMenuItem(regramString("RevokedMarker.Style." + style.rawValue), handler: { update { $0.style = style } }, state: marker.style == style ? .on : .off) }
        rows.append(.general(sectionId: 1, index: 0, value: .none, error: nil, identifier: InputDataIdentifier("revokedMarker.style"), data: .init(name: regramString("RevokedMarker.Style"), color: theme.colors.text, type: .contextSelector(regramString("RevokedMarker.Style." + marker.style.rawValue), choices), viewType: marker.style == .none ? .singleItem : .firstItem)))
        if marker.style == .text {
            rows.append(.input(sectionId: 1, index: 1, value: .string(marker.text), error: nil, identifier: InputDataIdentifier("revokedMarker.text"), mode: .plain, data: .init(viewType: .innerItem), placeholder: .init(regramString("RevokedMarker.Text")), inputPlaceholder: regramString("RevokedMarker.DefaultText"), filter: RegramRevokedMarker.normalizedText, limit: 384))
        }
        if marker.style != .none {
            rows.append(.input(sectionId: 1, index: 2, value: .string(marker.color), error: nil, identifier: InputDataIdentifier("revokedMarker.color"), mode: .plain, data: .init(viewType: .lastItem), placeholder: .init(regramString("RevokedMarker.Color")), inputPlaceholder: "#RRGGBB", filter: { $0.uppercased() }, limit: 32))
            if invalidColor { rows.append(.desc(sectionId: 1, index: 3, text: .plain(regramString("RevokedMarker.InvalidColor")), data: .init(color: theme.colors.redUI, viewType: .textBottomItem))) }
        }
        rows.append(.desc(sectionId: 1, index: 4, text: .plain(regramString("RevokedMarker.Notice")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        rows.append(.sectionId(1, type: .normal))
        rows.append(.desc(sectionId: 2, index: 5, text: .plain(regramString("RevokedMarker.Preview")), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        let preview = NSMutableAttributedString(string: "")
        if let label = marker.label(defaultText: regramString("RevokedMarker.DefaultText")) {
            let color = RegramRevokedMarker.rgb(marker.color).map { NSColor(calibratedRed: CGFloat(($0 >> 16) & 255) / 255, green: CGFloat(($0 >> 8) & 255) / 255, blue: CGFloat($0 & 255) / 255, alpha: 1) } ?? theme.colors.grayText
            preview.append(NSAttributedString(string: label + " ", attributes: [.foregroundColor: color]))
        }
        preview.append(NSAttributedString(string: "12:34", attributes: [.foregroundColor: theme.colors.grayText]))
        rows.append(.desc(sectionId: 2, index: 6, text: .attributed(preview), data: .init(color: theme.colors.grayText, viewType: .singleItem)))
        rows.append(.sectionId(2, type: .normal))
        rows.append(.general(sectionId: 3, index: 7, value: .none, error: nil, identifier: InputDataIdentifier("revokedMarker.apply"), data: .init(name: regramString("NetworkPolicy.Apply"), color: theme.colors.accent, type: .none, viewType: .singleItem, enabled: !invalidColor, action: {
            let marker = state.with { $0 }
            guard !context.isFrozen, marker.style == .none || marker.color.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || RegramRevokedMarker.rgb(marker.color) != nil else { return }
            RegramPreferences.shared.update(accountId: accountId) { marker.apply(to: &$0) }
            showModalText(for: context.window, text: regramString("RevokedMarker.Saved"))
        })))
        return InputDataSignalValue(entries: rows)
    }
    let controller = InputDataController(dataSignal: signal, title: regramString("RevokedMarker.Title"), updateDatas: { data in
        update { marker in
            if let text = data[InputDataIdentifier("revokedMarker.text")]?.stringValue { marker.text = RegramRevokedMarker.normalizedText(text) }
            if let color = data[InputDataIdentifier("revokedMarker.color")]?.stringValue { marker.color = color }
        }
        return .fail(.none)
    }, removeAfterDisappear: false, hasDone: false, identifier: "regram.privacyTools")
    regramFocusSettings(controller, page: "revokedMarker", item: focusSetting)
    return controller
}
