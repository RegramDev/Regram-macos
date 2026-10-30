import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import InputDataUI
import GeneralRows
import InAppSettings
import Localization
import RegramCore
import RegramSignals

public enum RegramNativeNavigation {
    public static func visibility(context: any AccountContextProtocol) -> Signal<(contacts: Bool, calls: Bool), NoError> {
        combineLatest(baseAppSettings(accountManager: context.sharedContext.accountManager), regramPreferenceChanges(accountId: context.peerId.toInt64())) |> map { native, preferences in
            (RegramBottomBarSettings(settings: preferences).isVisible(.contacts), native.showCallsTab)
        }
    }

    public static func update(context: any AccountContextProtocol, contacts: Bool, calls: Bool) -> Signal<Void, NoError> {
        RegramPreferences.shared.update(accountId: context.peerId.toInt64()) { settings in
            var configuration = RegramBottomBarSettings(settings: settings)
            configuration.setVisible(.contacts, visible: contacts)
            configuration.apply(to: &settings)
        }
        return updateBaseAppSettingsInteractively(accountManager: context.sharedContext.accountManager) { $0.withUpdatedShowCallsTab(calls) }
    }
}

public func RegramNavigationController(context: any AccountContextProtocol, focusSetting: String? = nil) -> InputDataController {
    let accountId = context.peerId.toInt64()
    func update(_ transform: (inout RegramBottomBarSettings) -> Void) {
        RegramPreferences.shared.update(accountId: accountId) { settings in
            var configuration = RegramBottomBarSettings(settings: settings)
            transform(&configuration)
            configuration.apply(to: &settings)
        }
    }
    let bottomBar = regramPreferenceChanges(accountId: accountId, keys: RegramBottomBarSettings.preferenceKeys) |> map { RegramBottomBarSettings(settings: $0) } |> distinctUntilChanged
    let calls = baseAppSettings(accountManager: context.sharedContext.accountManager) |> map { $0.showCallsTab } |> distinctUntilChanged
    let signal = combineLatest(bottomBar, calls, appearanceSignal) |> map { configuration, showCalls, _ -> InputDataSignalValue in
        var page = RegramPageBuilder(page: "bottomBar")
        page.section("RG.BottomBarLayout.Visibility")
        page.row("contacts", title: regramString("RG.BottomBarLayout.Item.contacts"), type: .switchable(configuration.isVisible(.contacts)), action: {
            update { $0.toggleHidden(.contacts) }
        })
        page.row("calls", title: strings().generalSettingsShowCallsTab, type: .switchable(showCalls), action: {
            _ = updateBaseAppSettingsInteractively(accountManager: context.sharedContext.accountManager) { $0.withUpdatedShowCallsTab(!$0.showCallsTab) }.startStandalone()
        })
        page.section("RG.BottomBarLayout.Options")
        page.row("labels", title: regramString("RG.BottomBarLayout.ShowLabels"), type: .switchable(configuration.showLabels), action: {
            update { $0.showLabels.toggle() }
        })
        page.section()
        page.custom("width", equatable: InputDataEquatable(configuration.buttonWidthFillRatio)) { size, id in
            regramSliderRowItem(size, stableId: id, title: regramString("RG.BottomBarLayout.Width"), value: Int(configuration.buttonWidthFillRatio), range: 50...100, changed: { percent in
                update { $0.automaticWidth = false; $0.buttonWidthFillRatio = Int32(percent) }
            })
        }
        return InputDataSignalValue(entries: page.entries, animated: false)
    }
    let controller = RegramFormController(dataSignal: signal, title: regramString("RG.BottomBarLayout"), removeAfterDisappear: false, hasDone: false, identifier: "regram.bottomBar")
    let focus = focusSetting == "visibility" ? "contacts" : focusSetting
    regramFocusSettings(controller, page: "bottomBar", item: focus)
    return controller
}
