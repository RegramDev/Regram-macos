import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramContext
import TelegramTheme
import InputDataUI
import RegramCore

private struct RegramDatacenterState: Equatable {
    var results = Dictionary(uniqueKeysWithValues: (1...5).map { ($0, RegramDatacenterStatistics()) })
    var running = false
    var cancelled = false
    var route = "Diagnostics.Route.Direct"
    var connection = "Diagnostics.Connection.Waiting"
}

public func RegramDatacenterController(context: any AccountContextProtocol, focusSetting: String? = nil) -> InputDataController {
    let initial = RegramDatacenterState()
    let value = Atomic(value: initial)
    let promise = ValuePromise(initial, ignoreRepeated: true)
    let tests = MetaDisposable()
    let actions = DisposableSet()
    actions.add(tests)
    var generation = UUID()
    func update(_ transform: (inout RegramDatacenterState) -> Void) { promise.set(value.modify { state in var state = state; transform(&state); return state }) }
    func cancel() {
        generation = UUID()
        tests.set(nil)
        update { if $0.running { $0.cancelled = true }; $0.running = false }
    }
    func start() {
        cancel()
        update { $0.results = initial.results; $0.running = true; $0.cancelled = false }
        let id = UUID()
        generation = id
        let requests = DisposableSet()
        tests.set(requests)
        for dc in 1...5 {
            requests.add((context.account.network.regramTestDatacenter(dc) |> deliverOnMainQueue).start(next: { sample in
                guard generation == id else { return }
                update { state in
                    if sample.index == 0 {
                        state.results[dc]?.connectionMilliseconds = sample.milliseconds
                        state.results[dc]?.connectionFailed = sample.milliseconds == nil
                        state.results[dc]?.connectionTimedOut = sample.timedOut
                    } else if let milliseconds = sample.milliseconds { state.results[dc]?.samples.append(milliseconds) }
                    else { state.results[dc]?.failures += 1; if sample.timedOut { state.results[dc]?.timeouts += 1 } }
                }
            }, completed: {
                guard generation == id else { return }
                update { $0.results[dc]?.completed = true; if $0.results.values.allSatisfy(\.completed) { $0.running = false } }
            }))
        }
    }
    let proxies = context.sharedContext.accountManager.sharedData(keys: [SharedDataKeys.proxySettings]) |> map { $0.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? .defaultSettings } |> distinctUntilChanged |> deliverOnMainQueue
    actions.add(proxies.start(next: { proxy in
        cancel()
        var route = "Diagnostics.Route.Direct"
        if proxy.enabled, let server = proxy.activeServer {
            switch server.connection { case .socks5: route = "Diagnostics.Route.SOCKS5"; case .mtp: route = "Diagnostics.Route.MTProto"; case .web: route = "Diagnostics.Route.Web" }
        }
        update { $0.route = route }
    }))
    actions.add((context.account.network.connectionStatus |> deliverOnMainQueue).start(next: { status in
        update { state in
            switch status { case .online: state.connection = "Diagnostics.Connection.Online"; case .connecting: state.connection = "Diagnostics.Connection.Connecting"; case .updating: state.connection = "Diagnostics.Connection.Updating"; case .waitingForNetwork: state.connection = "Diagnostics.Connection.Waiting" }
        }
    }))
    let observer = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in cancel() }
    actions.add(ActionDisposable { NotificationCenter.default.removeObserver(observer) })
    let signal = combineLatest(promise.get(), appearanceSignal) |> map { state, _ -> InputDataSignalValue in
        func ms(_ value: Double?) -> String { value.map { String(format: "%.0f ms", $0) } ?? "—" }
        func title(_ dc: Int) -> String { "DC\(dc) · " + (dc == 5 ? "Singapore" : dc == 1 || dc == 3 ? "Miami" : "Amsterdam") }
        var page = RegramPageBuilder(page: "datacenters")
        page.section("Diagnostics.Connection.Title")
        page.text(regramString(state.route))
        page.row("currentDC", title: regramString("Diagnostics.Connection.CurrentDC"), type: .context(title(context.account.network.datacenterId)))
        page.text(regramString(state.connection))
        page.section()
        page.row("start", title: regramString(state.running ? "Diagnostics.DC.Cancel" : "Diagnostics.DC.Start"), type: state.running ? .loading : .none, action: { if state.running { cancel() } else { start() } })
        page.text(regramString("Diagnostics.DC.Notice"))
        for dc in 1...5 {
            guard let result = state.results[dc] else { continue }
            page.section()
            page.text(title(dc), header: true)
            page.row("average.\(dc)", title: regramString("Diagnostics.DC.Average"), type: state.running && !result.completed ? .loading : .context(ms(result.average)))
            page.row("minimum.\(dc)", title: regramString("Diagnostics.DC.Minimum"), type: .context(ms(result.minimum)))
            page.row("variation.\(dc)", title: regramString("Diagnostics.DC.Variation"), type: .context(ms(result.variation)))
            page.row("connection.\(dc)", title: regramString("Diagnostics.DC.Connection"), type: .context(result.connectionFailed ? regramString(result.connectionTimedOut ? "Diagnostics.DC.Timeout" : "Diagnostics.DC.Failed") : ms(result.connectionMilliseconds)))
            page.row("samples.\(dc)", title: regramString("Diagnostics.DC.Samples"), type: .context("\(result.samples.count)/3"))
            page.row("failures.\(dc)", title: regramString("Diagnostics.DC.Failures"), type: .context("\(result.failures)/3"))
            page.row("timeouts.\(dc)", title: regramString("Diagnostics.DC.Timeouts"), type: .context("\(result.timeouts)"))
        }
        page.section()
        if state.cancelled { page.text(regramString("Diagnostics.DC.Cancelled")) }
        page.row("copy", title: regramString("Diagnostics.CopyAverages"), enabled: !state.results.values.allSatisfy { $0.samples.isEmpty && !$0.completed }, action: {
            let results = value.with { $0.results }
            let report = (1...5).map { dc in "DC\(dc): " + ms(results[dc]?.average) }.joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
        })
        return InputDataSignalValue(entries: page.entries)
    }
    let controller = RegramFormController(dataSignal: signal, title: regramString("Diagnostics.DC.Title"), afterDisappear: cancel, removeAfterDisappear: false, hasDone: false, identifier: "regram.datacenters")
    controller.onDeinit = { cancel(); actions.dispose() }
    regramFocusSettings(controller, page: "datacenters", item: focusSetting)
    return controller
}
