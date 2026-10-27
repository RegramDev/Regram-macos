enum FixtureProxyConnection: Equatable { case socks5, mtp, web }
struct FixtureProxyServer: Equatable { let connection: FixtureProxyConnection }
struct ProxySettings: Equatable {
    var enabled: Bool
    var activeServer: FixtureProxyServer?
    static let defaultSettings = ProxySettings(enabled: false, activeServer: nil)
}
enum SharedDataKeys { static let proxySettings = "proxySettings" }
struct FixtureSharedEntry {
    let proxy: ProxySettings
    func get<T>(_ type: T.Type) -> T? { proxy as? T }
}
struct FixtureSharedData { let entries: [String: FixtureSharedEntry] }
final class FixtureAccountManager {
    let proxy = ValuePromise(ProxySettings.defaultSettings, ignoreRepeated: true)
    func sharedData(keys: [String]) -> Signal<FixtureSharedData, NoError> {
        precondition(keys == [SharedDataKeys.proxySettings])
        return proxy.get() |> map { FixtureSharedData(entries: [SharedDataKeys.proxySettings: FixtureSharedEntry(proxy: $0)]) }
    }
}
struct FixtureSharedContext { let accountManager = FixtureAccountManager() }
enum FixtureConnectionStatus: Equatable { case online, connecting, updating, waitingForNetwork }
final class ControlledProbe {
    let datacenterId: Int
    var subscriber: Subscriber<RegramDatacenterProbeSample, NoError>?
    var cancelled = false
    var attemptedSamples = 0
    init(_ datacenterId: Int) { self.datacenterId = datacenterId }
    func signal() -> Signal<RegramDatacenterProbeSample, NoError> {
        Signal { subscriber in
            self.subscriber = subscriber
            return ActionDisposable { self.cancelled = true }
        }
    }
    func sample(_ index: Int, _ milliseconds: Double?, timedOut: Bool = false) {
        attemptedSamples += 1
        subscriber?.putNext(RegramDatacenterProbeSample(datacenterId: datacenterId, index: index, milliseconds: milliseconds, timedOut: timedOut))
    }
    func complete() { subscriber?.putCompletion() }
    func succeed(_ samples: [Double]) {
        precondition(samples.count == 3)
        sample(0, 7)
        for (index, value) in samples.enumerated() { sample(index + 1, value) }
        complete()
    }
}
final class FixtureNetwork {
    let datacenterId = 5
    let status = ValuePromise(FixtureConnectionStatus.online, ignoreRepeated: true)
    var connectionStatus: Signal<FixtureConnectionStatus, NoError> { status.get() }
    var probes: [ControlledProbe] = []
    func regramTestDatacenter(_ dc: Int) -> Signal<RegramDatacenterProbeSample, NoError> {
        precondition((1...5).contains(dc))
        let request = ControlledProbe(dc)
        probes.append(request)
        return request.signal()
    }
    var latest: [ControlledProbe] { Array(probes.suffix(5)) }
}
struct FixtureAccount { let network = FixtureNetwork() }
protocol AccountContextProtocol {
    var account: FixtureAccount { get }
    var sharedContext: FixtureSharedContext { get }
}
final class FixtureContext: AccountContextProtocol {
    let account = FixtureAccount()
    let sharedContext = FixtureSharedContext()
}
final class FixturePasteboard {
    static let general = FixturePasteboard()
    var value: String?
    var writes = 0
    func clearContents() { value = nil }
    @discardableResult func setString(_ value: String, forType: NSPasteboard.PasteboardType) -> Bool {
        precondition(forType == .string)
        self.value = value
        writes += 1
        return true
    }
}
let appearanceSignal: Signal<Int, NoError> = .single(0)
func regramString(_ key: String) -> String { key }
func regramFocusSettings(_ controller: InputDataController, page: String, item: String?) {}
func drain() { RunLoop.current.run(until: Date().addingTimeInterval(0.03)) }
func display(_ controller: InputDataController, _ key: String) -> String { controller.entry("datacenters." + key).type.identity }
func copy(_ controller: InputDataController) -> String {
    controller.entry("datacenters.copy").action!()
    return FixturePasteboard.general.value!
}
func report(_ values: [String]) -> String {
    precondition(values.count == 5)
    return values.enumerated().map { "DC\($0.offset + 1): \($0.element)" }.joined(separator: "\n")
}
func start(_ controller: InputDataController, _ context: FixtureContext) -> [ControlledProbe] {
    controller.entry("datacenters.start").action!()
    let requests = context.account.network.latest
    precondition(requests.map(\.datacenterId) == Array(1...5))
    precondition(requests.allSatisfy { $0.subscriber != nil && !$0.cancelled })
    precondition(display(controller, "start") == "loading")
    return requests
}
func queuedSuccess(_ probe: ControlledProbe) {
    let queued = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { probe.succeed([900, 900, 900]); queued.signal() }
    precondition(queued.wait(timeout: .now() + 3) == .success)
}

@main
struct DatacenterChecks {
    static func main() {
        checkIndependentResultsAndLiveCopy()
        checkCancelRetryAndQueuedCallbacks()
        checkProxyChanges()
        checkLeavingAndDeinit()
        print("Datacenter checks passed: five independent subscriptions, partial/failed results retained, reused copy reads latest Atomic, retry/cancel/proxy/leave reject stale callbacks; no network, account or system clipboard was used")
    }
    static func checkIndependentResultsAndLiveCopy() {
        for firstDatacenterFails in [false, true] {
            let context = FixtureContext()
            let controller = RegramDatacenterController(context: context)
            drain()
            precondition(!controller.entry("datacenters.copy").enabled)
            let requests = start(controller, context)
            requests[4].succeed([100, 110, 120])
            drain()
            let reusedCopy = controller.entry("datacenters.copy")
            let action = reusedCopy.action!
            precondition(reusedCopy.enabled)
            action()
            precondition(FixturePasteboard.general.value == report(["—", "—", "—", "—", "110 ms"]))
            requests[0].sample(0, nil, timedOut: true)
            if firstDatacenterFails {
                for index in 1...3 { requests[0].sample(index, nil, timedOut: index == 1) }
                requests[0].complete()
            }
            requests[1].succeed([20, 40, 60])
            drain()
            precondition(controller.entry("datacenters.copy") === reusedCopy)
            requests[2].succeed([10, 20, 30])
            drain()
            requests[3].succeed([70, 80, 90])
            drain()
            precondition(controller.entry("datacenters.copy") === reusedCopy)
            action()
            precondition(FixturePasteboard.general.value == report(["—", "40 ms", "20 ms", "80 ms", "110 ms"]))
            precondition(display(controller, "average.5") == "110 ms" && display(controller, "minimum.5") == "100 ms" && display(controller, "variation.5") == "8 ms")
            precondition(display(controller, "connection.1") == "Diagnostics.DC.Timeout")
            precondition(display(controller, "samples.1") == "0/3")
            if firstDatacenterFails {
                precondition(display(controller, "start") == "none")
                precondition(display(controller, "failures.1") == "3/3" && display(controller, "timeouts.1") == "1")
            } else {
                precondition(display(controller, "start") == "loading" && !requests[0].cancelled)
                precondition(display(controller, "failures.1") == "0/3")
                for index in 1...3 { requests[0].sample(index, 30) }
                requests[0].complete()
                drain()
                precondition(display(controller, "start") == "none")
                action()
                precondition(FixturePasteboard.general.value == report(["30 ms", "40 ms", "20 ms", "80 ms", "110 ms"]))
            }
        }
    }
    static func checkCancelRetryAndQueuedCallbacks() {
        let context = FixtureContext()
        let controller = RegramDatacenterController(context: context)
        drain()
        let first = start(controller, context)
        first[4].succeed([50, 50, 50])
        drain()
        let oldCopy = controller.entry("datacenters.copy").action!
        queuedSuccess(first[1])
        controller.entry("datacenters.start").action!()
        precondition(first.prefix(4).allSatisfy(\.cancelled))
        precondition(display(controller, "start") == "none")
        precondition(copy(controller) == report(["—", "—", "—", "—", "50 ms"]))
        let second = start(controller, context)
        precondition(context.account.network.probes.count == 10)
        precondition(!controller.entry("datacenters.copy").enabled)
        oldCopy()
        precondition(FixturePasteboard.general.value == report(["—", "—", "—", "—", "—"]))
        for request in first { request.succeed([800, 800, 800]) }
        drain()
        precondition(display(controller, "start") == "loading" && display(controller, "samples.2") == "0/3")
        second[4].succeed([70, 70, 70])
        drain()
        oldCopy()
        precondition(FixturePasteboard.general.value == report(["—", "—", "—", "—", "70 ms"]))
        for request in second.prefix(4) { request.succeed([Double(request.datacenterId * 10), Double(request.datacenterId * 10), Double(request.datacenterId * 10)]) }
        drain()
        precondition(copy(controller) == report(["10 ms", "20 ms", "30 ms", "40 ms", "70 ms"]))
        precondition(display(controller, "start") == "none")
    }
    static func checkProxyChanges() {
        let routes: [(FixtureProxyConnection?, String)] = [(.socks5, "Diagnostics.Route.SOCKS5"), (.mtp, "Diagnostics.Route.MTProto"), (.web, "Diagnostics.Route.Web"), (nil, "Diagnostics.Route.Direct")]
        let context = FixtureContext()
        let controller = RegramDatacenterController(context: context)
        drain()
        for (connection, route) in routes {
            let previous = start(controller, context)
            previous[4].succeed([100, 100, 100])
            drain()
            context.sharedContext.accountManager.proxy.set(ProxySettings(enabled: connection != nil, activeServer: connection.map { FixtureProxyServer(connection: $0) }))
            drain()
            precondition(previous.prefix(4).allSatisfy(\.cancelled))
            precondition(controller.entries.contains { $0.title == route })
            precondition(display(controller, "start") == "none")
            precondition(copy(controller) == report(["—", "—", "—", "—", "100 ms"]))
            let current = start(controller, context)
            current[1].succeed([21, 31, 41])
            for request in previous { request.succeed([999, 999, 999]) }
            drain()
            precondition(copy(controller) == report(["—", "31 ms", "—", "—", "—"]))
            precondition(display(controller, "start") == "loading")
            controller.entry("datacenters.start").action!()
            precondition(current.filter { $0.datacenterId != 2 }.allSatisfy(\.cancelled))
        }
    }
    static func checkLeavingAndDeinit() {
        for event in ["leave", "resign", "deinit"] {
            let context = FixtureContext()
            var controller: InputDataController? = RegramDatacenterController(context: context)
            drain()
            let requests = start(controller!, context)
            requests[4].succeed([40, 40, 40])
            drain()
            let oldCopy = controller!.entry("datacenters.copy").action!
            weak let weakController = controller
            if event == "leave" { controller!.afterDisappear() }
            else if event == "resign" { NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil) }
            else { controller = nil; precondition(weakController == nil) }
            precondition(requests.prefix(4).allSatisfy(\.cancelled))
            for request in requests { request.succeed([600, 600, 600]) }
            drain()
            oldCopy()
            precondition(FixturePasteboard.general.value == report(["—", "—", "—", "—", "40 ms"]))
            if let controller { precondition(display(controller, "start") == "none") }
        }
    }
}
