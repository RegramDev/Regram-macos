import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import InputDataUI
import AlertsUI
import RegramCore
import RegramSignals
import RegramServices

private struct RegramNetworkEditorState: Equatable {
    var policy: RegramNetworkPolicy
    var failure: String?
}

public func RegramNetworkPolicyController(context: any AccountContextProtocol, focusSetting: String? = nil) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let policy = RegramNetworkPolicy(settings: RegramPreferences.shared.settings(accountId: accountId))
    let initial = RegramNetworkEditorState(policy: policy, failure: RegramDNSDiagnostics.lastFailure(endpoint: policy.endpoint))
    let value = Atomic(value: initial)
    let promise = ValuePromise(initial, ignoreRepeated: true)
    let actions = DisposableSet()
    func update(_ transform: (inout RegramNetworkEditorState) -> Void) { promise.set(value.modify { state in var state = state; transform(&state); return state }) }
    actions.add((regramPreferenceChanges(accountId: accountId) |> map { _ in RegramNetworkPolicy(settings: RegramPreferences.shared.settings(accountId: accountId)) } |> distinctUntilChanged |> deliverOnMainQueue).start(next: { policy in update { $0.policy = policy; $0.failure = RegramDNSDiagnostics.lastFailure(endpoint: policy.endpoint) } }))
    let observer = NotificationCenter.default.addObserver(forName: RegramDNSDiagnostics.failureDidChange, object: nil, queue: .main) { _ in
        update { $0.failure = RegramDNSDiagnostics.lastFailure(endpoint: $0.policy.endpoint) }
    }
    actions.add(ActionDisposable { NotificationCenter.default.removeObserver(observer) })
    let signal = combineLatest(promise.get(), appearanceSignal) |> map { state, _ -> InputDataSignalValue in
        let policy = state.policy
        var page = RegramPageBuilder(page: "networkPolicy")
        page.section()
        page.row("enabled", title: regramString("NetworkPolicy.DNSMode"), type: .contextSelector(regramString(policy.dnsMode.titleKey), RegramNetworkPolicy.DNSMode.allCases.map { mode in ContextMenuItem(regramString(mode.titleKey), handler: { update { $0.policy.dnsMode = mode } }, state: mode == policy.dnsMode ? .on : .off) }))
        page.input("endpoint", value: policy.endpoint, title: regramString("NetworkPolicy.Endpoint"), placeholder: "https://dns.google/resolve")
        if policy.dnsMode == .custom, let failure = state.failure { page.text(regramString("NetworkPolicy.DoHFailure." + failure)) }
        if policy.dnsMode == .custom && !RegramNetworkPolicy.validEndpoint(policy.endpoint) { page.text(regramString("NetworkPolicy.InvalidURL")) }
        page.text(regramString("NetworkPolicy.DoHNotice"))
        page.section()
        page.row("ipVersion", title: regramString("NetworkPolicy.IP"), type: .contextSelector(regramString(policy.ipVersion.titleKey), RegramNetworkPolicy.IPVersion.sourceOrder.map { version in ContextMenuItem(regramString(version.titleKey), handler: { update { $0.policy.ipVersion = version } }, state: version == policy.ipVersion ? .on : .off) }))
        page.text(regramString("NetworkPolicy.IPNotice"))
        page.section()
        page.row("disableBackup", title: regramString("NetworkPolicy.DisableBackup"), type: .switchable(policy.disableBackupAddresses), action: { update { $0.policy.disableBackupAddresses.toggle() } })
        page.text(regramString("NetworkPolicy.BackupNotice"))
        page.section()
        page.row("test", title: regramString("DNSDiagnostics.Title"), type: .next, action: { context.bindings.rootNavigation().push(RegramDNSController(context: context, policy: policy)) })
        page.row("apply", title: regramString("NetworkPolicy.Apply"), enabled: policy.dnsMode != .custom || RegramNetworkPolicy.validEndpoint(policy.endpoint), action: {
            RegramPreferences.shared.update(accountId: accountId) { policy.apply(to: &$0) }
            showModalText(for: context.window, text: regramString("NetworkPolicy.Applied"))
        })
        return InputDataSignalValue(entries: page.entries)
    }
    let controller = InputDataController(dataSignal: signal, title: regramString("NetworkPolicy.Title"), updateDatas: { data in
        if let endpoint = data[InputDataIdentifier("networkPolicy.endpoint")]?.stringValue {
            update { $0.policy.endpoint = endpoint; $0.failure = RegramDNSDiagnostics.lastFailure(endpoint: endpoint) }
        }
        return .fail(.none)
    }, removeAfterDisappear: false, hasDone: false, identifier: "regram.networkPolicy")
    controller.onDeinit = { actions.dispose() }
    regramFocusSettings(controller, page: "networkPolicy", item: focusSetting)
    return controller
}
