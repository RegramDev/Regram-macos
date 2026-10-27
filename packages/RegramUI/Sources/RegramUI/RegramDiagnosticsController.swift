import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import InputDataUI
import RegramCore
import RegramSignals

private struct RegramDiagnosticsState: Equatable {
    var revision: Int64 = 0
    var testing = false
    var timing: Double?
}

public func RegramDiagnosticsController(context: any AccountContextProtocol, focusSetting: String? = nil) -> InputDataController {
    let value = Atomic(value: RegramDiagnosticsState())
    let promise = ValuePromise(RegramDiagnosticsState(), ignoreRepeated: true)
    let benchmark = RGFilterBenchmarkSession()
    func update(_ transform: (inout RegramDiagnosticsState) -> Void) { promise.set(value.modify { state in var state = state; transform(&state); return state }) }
    let timer = SwiftSignalKit.Timer(timeout: 1, repeat: true, completion: { update { $0.revision &+= 1 } }, queue: .mainQueue())
    timer.start()
    func cancel() { benchmark.cancel(); update { $0.testing = false } }
    let observer = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in cancel() }
    let signal = combineLatest(promise.get(), regramPreferenceChanges(accountId: context.peerId.toInt64()), appearanceSignal) |> map { state, settings, _ -> InputDataSignalValue in
        let snapshot = RegramTransferStatistics.shared.snapshot()
        var page = RegramPageBuilder(page: "diagnostics")
        page.section()
        page.row("datacenters", title: regramString("Diagnostics.DC.Title"), type: .next, action: { context.bindings.rootNavigation().push(RegramDatacenterController(context: context)) })
        page.section("Diagnostics.Download")
        page.row("speed", title: regramString("Diagnostics.Speed"), type: .context(ByteCountFormatter.string(fromByteCount: snapshot.roundedBytesPerSecond, countStyle: .file) + "/s"))
        page.row("received", title: regramString("Diagnostics.Received"), type: .context(ByteCountFormatter.string(fromByteCount: snapshot.receivedBytes, countStyle: .file)))
        page.text(regramString(settings["downloadSpeedBoost"].string == "medium" ? "Diagnostics.Boost.On" : "Diagnostics.Boost.Off"))
        page.text(regramString("Diagnostics.Download.Notice"))
        page.section("Diagnostics.Filter")
        page.row("filter", title: regramString(state.testing ? "Common.Cancel" : "Diagnostics.Filter.Run"), type: state.testing ? .loading : .none, action: {
            if state.testing { cancel(); return }
            let token = benchmark.begin()
            let rules = RegramPreferences.shared.settings(accountId: context.peerId.toInt64()).filterRules
            update { $0.testing = true }
            Queue.concurrentDefaultQueue().async {
                let result = RGFilterBenchmark.measure(rules: rules, shouldContinue: { benchmark.isActive(token) })
                Queue.mainQueue().async {
                    guard benchmark.finish(token) else { return }
                    update { $0.timing = result?.averageMilliseconds; $0.testing = false }
                }
            }
        })
        page.row("average", title: regramString("Diagnostics.Filter.Average"), type: .context(state.timing.map { String(format: "%.2f ms", $0) } ?? "—"))
        page.text("\(settings.filterRules.count) " + regramString("Diagnostics.Rules"))
        page.text(regramString("Diagnostics.Filter.Notice"))
        return InputDataSignalValue(entries: page.entries)
    }
    let controller = InputDataController(dataSignal: signal, title: regramString("Diagnostics.Title"), afterDisappear: cancel, removeAfterDisappear: false, hasDone: false, identifier: "regram.diagnostics")
    controller.onDeinit = { cancel(); timer.invalidate(); NotificationCenter.default.removeObserver(observer) }
    regramFocusSettings(controller, page: "diagnostics", item: focusSetting == "transfer" ? "speed" : focusSetting)
    return controller
}
