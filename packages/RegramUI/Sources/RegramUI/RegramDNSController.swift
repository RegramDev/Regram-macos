import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import InputDataUI
import RegramServices
import RegramCore

private struct RegramDNSFamilyResult: Equatable {
    let family: Int
    var addresses: [String] = []
    var milliseconds: Double?
}

private struct RegramDNSState: Equatable {
    var host: String
    var running = false
    var results: [RegramDNSFamilyResult] = []
}

public func RegramDNSController(context: any AccountContextProtocol, policy: RegramNetworkPolicy? = nil, focusSetting: String? = nil) -> InputDataController {
    let policy = policy ?? RegramNetworkPolicy(settings: RegramPreferences.shared.settings(accountId: context.peerId.toInt64()))
    let proxy = context.account.network.context.apiEnvironment.socksProxySettings
    let initial = RegramDNSState(host: proxy?.ip ?? "telegram.org")
    let route = proxy == nil ? "Diagnostics.Route.Direct" : proxy?.webProxy == true ? "Diagnostics.Route.Web" : proxy?.secret == nil ? "Diagnostics.Route.SOCKS5" : "Diagnostics.Route.MTProto"
    let value = Atomic(value: initial)
    let promise = ValuePromise(initial, ignoreRepeated: true)
    let request = MetaDisposable()
    var generation = UUID()
    func update(_ transform: (inout RegramDNSState) -> Void) { promise.set(value.modify { state in var state = state; transform(&state); return state }) }
    func cancel() { generation = UUID(); request.set(nil); update { $0.running = false } }
    func start() {
        cancel()
        let token = UUID()
        generation = token
        let host = value.with { $0.host.trimmingCharacters(in: .whitespacesAndNewlines) }
        update { $0.results = []; $0.running = true }
        let requests = DisposableSet()
        request.set(requests)
        for family in [4, 6] {
            func finish(_ result: RegramDNSFamilyResult) {
                guard generation == token else { return }
                update { state in state.results.removeAll { $0.family == family }; state.results.append(result); state.results.sort { $0.family < $1.family }; state.running = state.results.count < 2 }
            }
            requests.add((RegramDNSDiagnostics.resolve(domain: host, ipv6: family == 6, mode: policy.dnsMode, endpoint: policy.endpoint) |> deliverOnMainQueue).start(next: { result in
                finish(RegramDNSFamilyResult(family: family, addresses: result.addresses, milliseconds: result.elapsed * 1000))
            }, error: { _ in finish(RegramDNSFamilyResult(family: family)) }))
        }
    }
    let signal = combineLatest(promise.get(), appearanceSignal) |> map { state, _ -> InputDataSignalValue in
        var page = RegramPageBuilder(page: "dnsDiagnostics")
        page.section()
        page.text(regramString(policy.dnsMode.titleKey), header: true)
        if policy.dnsMode == .custom { page.text(policy.endpoint) }
        page.text(regramString(route))
        page.text(regramString("NetworkPolicy.IP") + ": " + regramString(policy.ipVersion.titleKey))
        if state.running { page.row("host", title: state.host, enabled: false) }
        else { page.input("host", value: state.host, title: regramString("DNSDiagnostics.Host"), limit: 253) }
        page.row("start", title: regramString(state.running ? "Common.Cancel" : "DNSDiagnostics.Start"), type: state.running ? .loading : .none, enabled: !state.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (policy.dnsMode != .custom || RegramNetworkPolicy.validEndpoint(policy.endpoint)), action: { if state.running { cancel() } else { start() } })
        page.text(regramString("DNSDiagnostics.Notice"))
        if !state.running && !state.results.isEmpty {
            page.section("DNSDiagnostics.PolicyAddresses")
            let addresses = RegramDNSDiagnostics.orderedAddresses(state.results.flatMap(\.addresses), policy: policy.ipVersion)
            if addresses.isEmpty { page.text(regramString("DNSDiagnostics.NoPolicyAddresses")) }
            for address in addresses { page.text(address) }
        }
        for result in state.results {
            page.section()
            page.text(result.family == 4 ? "IPv4 · A" : "IPv6 · AAAA", header: true)
            page.text(result.addresses.first ?? regramString("DNSDiagnostics.Failed"))
            if let milliseconds = result.milliseconds { page.text(String(format: "%.0f ms", milliseconds)) }
        }
        return InputDataSignalValue(entries: page.entries)
    }
    let controller = InputDataController(dataSignal: signal, title: regramString("DNSDiagnostics.Title"), updateDatas: { data in
        if let host = data[InputDataIdentifier("dnsDiagnostics.host")]?.stringValue { update { if !$0.running { $0.host = host } } }
        return .fail(.none)
    }, afterDisappear: cancel, removeAfterDisappear: false, hasDone: false, identifier: "regram.dnsDiagnostics")
    controller.onDeinit = { generation = UUID(); request.dispose() }
    regramFocusSettings(controller, page: "dnsDiagnostics", item: focusSetting)
    return controller
}
