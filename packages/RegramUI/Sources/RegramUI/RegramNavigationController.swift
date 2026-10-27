import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import InputDataUI
import InAppSettings
import RegramCore
import RegramSignals

public enum RegramNativeNavigation {
    public static func visibility(context: any AccountContextProtocol) -> Signal<(contacts: Bool, calls: Bool), NoError> {
        combineLatest(baseAppSettings(accountManager: context.sharedContext.accountManager), regramPreferenceChanges(accountId: context.peerId.toInt64())) |> map { native, preferences in
            (preferences["native.showContactsTab"].bool, native.showCallsTab)
        }
    }

    public static func update(context: any AccountContextProtocol, contacts: Bool, calls: Bool) -> Signal<Void, NoError> {
        RegramPreferences.shared.update(accountId: context.peerId.toInt64()) { $0["native.showContactsTab"] = .bool(contacts); $0["native.showCallsTab"] = .bool(calls) }
        return updateBaseAppSettingsInteractively(accountManager: context.sharedContext.accountManager) { $0.withUpdatedShowCallsTab(calls) }
    }
}

private struct RegramNavigationState: Equatable {
    var configuration: RegramBottomBarSettings
}

public func RegramNavigationController(context: any AccountContextProtocol, focusSetting: String? = nil) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let actions = DisposableSet()
    let initial = RegramNavigationState(configuration: RegramBottomBarSettings(settings: RegramPreferences.shared.settings(accountId: accountId)))
    let value = Atomic(value: initial)
    let promise = ValuePromise(initial, ignoreRepeated: true)
    var pendingContacts: Bool?
    var pendingCalls: Bool?
    func update(_ transform: (inout RegramBottomBarSettings) -> Void) {
        var configuration = value.with { $0.configuration }
        transform(&configuration)
        pendingContacts = configuration.isVisible(.contacts)
        pendingCalls = configuration.isVisible(.calls)
        RegramPreferences.shared.update(accountId: accountId) { configuration.apply(to: &$0) }
        actions.add(RegramNativeNavigation.update(context: context, contacts: configuration.isVisible(.contacts), calls: configuration.isVisible(.calls)).start())
        _ = value.swap(RegramNavigationState(configuration: configuration))
        promise.set(RegramNavigationState(configuration: configuration))
    }
    actions.add((combineLatest(regramPreferenceChanges(accountId: accountId), baseAppSettings(accountManager: context.sharedContext.accountManager)) |> deliverOnMainQueue).start(next: { preferences, native in
        var configuration = RegramBottomBarSettings(settings: preferences)
        let contacts = pendingContacts ?? preferences["native.showContactsTab"].bool
        let calls = pendingCalls ?? native.showCallsTab
        if pendingContacts == preferences["native.showContactsTab"].bool { pendingContacts = nil }
        if pendingCalls == native.showCallsTab { pendingCalls = nil }
        configuration.setVisible(.contacts, visible: contacts)
        configuration.setVisible(.calls, visible: calls)
        let state = RegramNavigationState(configuration: configuration)
        _ = value.swap(state)
        promise.set(state)
    }))
    let signal = combineLatest(promise.get(), appearanceSignal) |> map { state, _ -> InputDataSignalValue in
        let configuration = state.configuration
        var page = RegramPageBuilder(page: "bottomBar")
        page.section("RG.BottomBarLayout.Visibility")
        for id in [RegramBottomBarItemId.contacts, .calls] {
            page.row(id.rawValue, title: regramString("RG.BottomBarLayout.Item." + id.rawValue), type: .switchable(configuration.isVisible(id)), action: {
                update { $0.toggleHidden(id) }
            })
        }
        page.section("RG.BottomBarLayout.Options")
        page.custom("width", equatable: InputDataEquatable(configuration.buttonWidthFillRatio)) { size, id in
            regramSliderRowItem(size, stableId: id, title: regramString("RG.BottomBarLayout.Width"), value: Int(configuration.buttonWidthFillRatio), range: 50...100, changed: { percent in
                update { $0.automaticWidth = false; $0.buttonWidthFillRatio = Int32(percent); $0.widthMode = percent >= 100 ? .full : .adaptive; $0.slotMode = .visibleOnly }
            })
        }
        return InputDataSignalValue(entries: page.entries)
    }
    let controller = InputDataController(dataSignal: signal, title: regramString("RG.BottomBarLayout"), removeAfterDisappear: false, hasDone: false, identifier: "regram.bottomBar")
    controller.onDeinit = { actions.dispose() }
    let focus = ["visibility", "bottomSearch", "searchMode"].contains(focusSetting ?? "") ? RegramBottomBarItemId.allCases.first(where: { initial.configuration.canHide($0) })?.rawValue : focusSetting
    regramFocusSettings(controller, page: "bottomBar", item: focus)
    return controller
}
