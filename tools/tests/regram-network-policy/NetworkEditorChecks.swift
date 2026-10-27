import Cocoa
import SwiftSignalKit
import RegramCore

struct InputDataIdentifier: Hashable {
    let value: String
    init(_ value: String) { self.value = value }
}
enum InputDataValue {
    case string(String)
    var stringValue: String? { if case let .string(value) = self { return value }; return nil }
}
enum InputDataValidation { case fail(Failure); enum Failure { case none } }
enum MenuState { case on, off }
final class ContextMenuItem {
    let title: String
    let handler: () -> Void
    init(_ title: String, handler: @escaping () -> Void, state: MenuState) { self.title = title; self.handler = handler }
}
enum GeneralInteractedType {
    case none, next, loading, switchable(Bool), contextSelector(String, [ContextMenuItem])
    var identity: String {
        switch self {
        case .none: return "none"
        case .next: return "next"
        case .loading: return "loading"
        case let .switchable(value): return "switch.\(value)"
        case let .contextSelector(title, _): return title
        }
    }
}
final class EditorEntry {
    let identifier: String
    let index: Int
    let title: String
    let type: GeneralInteractedType
    let enabled: Bool
    let input: Bool
    let action: (() -> Void)?
    init(_ identifier: String, index: Int, title: String, type: GeneralInteractedType = .none, enabled: Bool = true, input: Bool = false, action: (() -> Void)? = nil) {
        self.identifier = identifier; self.index = index; self.title = title; self.type = type; self.enabled = enabled; self.input = input; self.action = action
    }
    func sameDisplay(as other: EditorEntry) -> Bool {
        identifier == other.identifier && index == other.index && title == other.title && type.identity == other.type.identity && enabled == other.enabled && input == other.input
    }
}
struct InputDataSignalValue { let entries: [EditorEntry] }
struct RegramPageBuilder {
    let page: String
    var entries: [EditorEntry] = []
    init(page: String) { self.page = page }
    mutating func section(_ title: String? = nil) { text(title ?? "section") }
    mutating func text(_ value: String, header: Bool = false) { entries.append(EditorEntry(page + ".text.\(entries.count)", index: entries.count, title: value)) }
    mutating func input(_ key: String, value: String, title: String, placeholder: String? = nil, limit: Int32 = 2048) { entries.append(EditorEntry(page + "." + key, index: entries.count, title: title, type: .contextSelector(value, []), input: true)) }
    mutating func row(_ key: String, title: String, type: GeneralInteractedType = .none, enabled: Bool = true, action: (() -> Void)? = nil) { entries.append(EditorEntry(page + "." + key, index: entries.count, title: title, type: type, enabled: enabled, action: action)) }
}
final class InputDataController {
    let updateDatas: ([InputDataIdentifier: InputDataValue]) -> InputDataValidation
    let afterDisappear: () -> Void
    var onDeinit: (() -> Void)?
    var entries: [EditorEntry] = []
    private var subscription: Disposable?
    init(dataSignal: Signal<InputDataSignalValue, NoError>, title: String, updateDatas: @escaping ([InputDataIdentifier: InputDataValue]) -> InputDataValidation, afterDisappear: @escaping () -> Void = {}, removeAfterDisappear: Bool, hasDone: Bool, identifier: String) {
        self.updateDatas = updateDatas; self.afterDisappear = afterDisappear
        subscription = dataSignal.start(next: { [weak self] value in
            guard let self else { return }
            self.entries = value.entries.map { new in self.entries.first(where: { $0.sameDisplay(as: new) }) ?? new }
        })
    }
    deinit { subscription?.dispose(); onDeinit?() }
    func entry(_ key: String) -> EditorEntry { entries.first { $0.identifier == key }! }
    func select(_ key: String, _ title: String) {
        if case let .contextSelector(_, items) = entry(key).type { items.first { $0.title == title }!.handler() }
        else { preconditionFailure("Missing selector") }
    }
    func input(_ key: String, _ value: String) { _ = updateDatas([InputDataIdentifier(key): .string(value)]) }
}
struct EditorPeerId { func toInt64() -> Int64 { 42 } }
final class EditorNavigation { var pushed: [InputDataController] = []; func push(_ controller: InputDataController) { pushed.append(controller) } }
final class EditorBindings { let navigation = EditorNavigation(); func rootNavigation() -> EditorNavigation { navigation } }
struct EditorProxy { let ip: String; let webProxy: Bool; let secret: Data? }
struct EditorEnvironment { var socksProxySettings: EditorProxy? }
struct EditorNetworkContext { var apiEnvironment = EditorEnvironment() }
struct EditorNetwork { var context = EditorNetworkContext() }
struct EditorAccount { var network = EditorNetwork() }
protocol AccountContextProtocol { var peerId: EditorPeerId { get }; var bindings: EditorBindings { get }; var window: NSObject { get }; var account: EditorAccount { get } }
final class EditorContext: AccountContextProtocol { let peerId = EditorPeerId(); let bindings = EditorBindings(); let window = NSObject(); let account = EditorAccount() }
let appearanceSignal: Signal<Int, NoError> = .single(0)
func regramString(_ key: String) -> String { key }
func regramFocusSettings(_ controller: InputDataController, page: String, item: String?) {}
var confirmations = 0
func showModalText(for window: NSObject, text: String) { confirmations += 1 }
let suite = "RegramNetworkEditorChecks." + UUID().uuidString
let testDefaults = UserDefaults(suiteName: suite)!
let testPreferences = RegramPreferences(defaults: testDefaults)
func regramPreferenceChanges(accountId: Int64) -> Signal<RegramAccountSettings, NoError> {
    Signal { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: RegramPreferences.didChange, object: nil, queue: nil) { notification in
            if notification.object as? Int64 == accountId { subscriber.putNext(testPreferences.settings(accountId: accountId)) }
        }
        subscriber.putNext(testPreferences.settings(accountId: accountId))
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    }
}
struct RegramDNSResult { let addresses: [String]; let elapsed: TimeInterval }
enum RegramDNSError: Error { case failed }
final class DiagnosticRequest {
    let host: String
    let mode: RegramNetworkPolicy.DNSMode
    let endpoint: String
    var cancelled = false
    init(host: String, mode: RegramNetworkPolicy.DNSMode, endpoint: String) { self.host = host; self.mode = mode; self.endpoint = endpoint }
}
enum RegramDNSDiagnostics {
    static let failureDidChange = Notification.Name("Regram.NetworkEditorTests.Failure")
    static var requests: [DiagnosticRequest] = []
    static func lastFailure(endpoint: String) -> String? { nil }
    static func orderedAddresses(_ addresses: [String], policy: RegramNetworkPolicy.IPVersion) -> [String] { addresses }
    static func resolve(domain: String, ipv6: Bool, mode: RegramNetworkPolicy.DNSMode, endpoint: String) -> Signal<RegramDNSResult, RegramDNSError> {
        Signal { _ in
            let request = DiagnosticRequest(host: domain, mode: mode, endpoint: endpoint)
            requests.append(request)
            return ActionDisposable { request.cancelled = true }
        }
    }
}
final class MTApiEnvironment: NSObject, NSCopying {
    var rgDoHEndpoint: String?
    var rgUseSystemDNS = false
    var rgIPVersionPreference = 0
    var rgDisableBackupAddressDiscovery = false
    func copy(with zone: NSZone? = nil) -> Any {
        let value = MTApiEnvironment()
        value.rgDoHEndpoint = rgDoHEndpoint; value.rgUseSystemDNS = rgUseSystemDNS; value.rgIPVersionPreference = rgIPVersionPreference; value.rgDisableBackupAddressDiscovery = rgDisableBackupAddressDiscovery
        return value
    }
}
final class MTContext {
    var environment = MTApiEnvironment()
    var changes = 0
    func updateApiEnvironment(_ update: (MTApiEnvironment?) -> MTApiEnvironment?) { environment = update(environment)!; changes += 1 }
}
func waitUntil(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(3)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    precondition(condition(), "Timed out waiting for editor persistence and native policy notification")
}

@main
struct NetworkEditorChecks {
    static func main() {
        defer { testDefaults.removePersistentDomain(forName: suite) }
        for mode in RegramNetworkPolicy.DNSMode.allCases {
            for version in RegramNetworkPolicy.IPVersion.allCases {
                checkSave(mode: mode, version: version)
            }
        }
        checkLatestEndpointAndInvalidSave()
        checkLiveDiagnosticsRouteAndCancel()
        print("Network editor checks passed: reused actions, 15 DNS/IP combinations, isolated persistence/reload, all native binding fields, invalid URL rejection, full-width custom-only endpoint, live diagnostics and cancel")
    }
    static func checkSave(mode: RegramNetworkPolicy.DNSMode, version: RegramNetworkPolicy.IPVersion) {
        testPreferences.reset(accountId: 42)
        testPreferences.update(accountId: 42) { $0["showMessageId"] = .bool(true) }
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        let native = MTContext()
        let binding = RegramNetworkPolicyBinding(context: native, accountId: 42)
        withExtendedLifetime(binding) {
            let controller = RegramNetworkPolicyController(context: EditorContext())
            let oldSave = controller.entry("networkPolicy.apply").action!
            controller.select("networkPolicy.enabled", mode.titleKey)
            controller.select("networkPolicy.ipVersion", version.titleKey)
            controller.entry("networkPolicy.disableBackup").action!()
            if mode == .custom {
                controller.input("networkPolicy.endpoint", " https://resolver.example:8443/dns-query ")
                precondition(controller.entry("networkPolicy.endpoint").title.isEmpty)
                precondition(controller.entries.contains { $0.title == "NetworkPolicy.Endpoint" })
            } else {
                precondition(!controller.entries.contains { $0.identifier == "networkPolicy.endpoint" })
            }
            oldSave()
            let saved = RegramNetworkPolicy(settings: testPreferences.settings(accountId: 42))
            precondition(saved.dnsMode == mode && saved.ipVersion == version && saved.disableBackupAddresses)
            precondition(testPreferences.settings(accountId: 42)["showMessageId"].bool)
            let reloaded = RegramNetworkPolicy(settings: RegramPreferences(defaults: testDefaults).settings(accountId: 42))
            precondition(reloaded == saved)
            waitUntil { native.environment.rgIPVersionPreference == Int(version.rawValue) && native.environment.rgDisableBackupAddressDiscovery && native.environment.rgUseSystemDNS == (mode == .system) && native.environment.rgDoHEndpoint == saved.effectiveEndpoint }
            precondition(native.changes >= 2)
            precondition(!testPreferences.settings(accountId: 43)["disableBackupAddresses"].bool)
        }
    }
    static func checkLatestEndpointAndInvalidSave() {
        testPreferences.reset(accountId: 42)
        let controller = RegramNetworkPolicyController(context: EditorContext())
        controller.select("networkPolicy.enabled", RegramNetworkPolicy.DNSMode.custom.titleKey)
        controller.input("networkPolicy.endpoint", "https://old-resolver.example/resolve")
        let oldSave = controller.entry("networkPolicy.apply").action!
        controller.input("networkPolicy.endpoint", "https://latest-resolver.example/resolve")
        oldSave()
        precondition(RegramNetworkPolicy(settings: testPreferences.settings(accountId: 42)).endpoint == "https://latest-resolver.example/resolve")
        let count = confirmations
        controller.input("networkPolicy.endpoint", "http://invalid-resolver.example")
        oldSave()
        precondition(confirmations == count)
        precondition(RegramNetworkPolicy(settings: testPreferences.settings(accountId: 42)).endpoint == "https://latest-resolver.example/resolve")
    }
    static func checkLiveDiagnosticsRouteAndCancel() {
        testPreferences.reset(accountId: 42)
        let context = EditorContext()
        let controller = RegramNetworkPolicyController(context: context)
        let oldTest = controller.entry("networkPolicy.test").action!
        controller.select("networkPolicy.enabled", RegramNetworkPolicy.DNSMode.custom.titleKey)
        controller.input("networkPolicy.endpoint", "https://latest-resolver.example/resolve")
        oldTest()
        let diagnostics = context.bindings.navigation.pushed.last!
        precondition(diagnostics.entries.contains { $0.title == "https://latest-resolver.example/resolve" })
        let oldStart = diagnostics.entry("dnsDiagnostics.start").action!
        diagnostics.input("dnsDiagnostics.host", " proxy.example ")
        RegramDNSDiagnostics.requests.removeAll()
        oldStart()
        precondition(RegramDNSDiagnostics.requests.count == 2)
        precondition(RegramDNSDiagnostics.requests.allSatisfy { $0.host == "proxy.example" && $0.mode == .custom && $0.endpoint == "https://latest-resolver.example/resolve" })
        oldStart()
        precondition(RegramDNSDiagnostics.requests.count == 2 && RegramDNSDiagnostics.requests.allSatisfy(\.cancelled))
    }
}
