import Foundation
import SwiftSignalKit
import RegramCore

enum FixtureMode { case sync, controlled, fail, empty }
enum FixtureRPC { case value, nilValue, fail, empty }
final class FixtureRequest {
    let provider: String
    let text: String
    let target: String
    let subscriber = Atomic<Subscriber<String, TranslateFetchError>?>(value: nil)
    let disposed = Atomic(value: false)
    var cancelled: Bool { disposed.with { $0 } }
    init(_ provider: String, _ text: String, _ target: String) { self.provider = provider; self.text = text; self.target = target }
    func signal() -> Signal<String, TranslateFetchError> {
        Signal { subscriber in
            _ = self.subscriber.swap(subscriber)
            _ = FixtureProviders.ledger.modify { $0 + [self] }
            let active = FixtureProviders.active.modify { $0 + 1 }
            _ = FixtureProviders.maximumActive.modify { max($0, active) }
            switch FixtureProviders.mode {
            case .sync: subscriber.putNext("Translated " + self.text); subscriber.putCompletion()
            case .fail: subscriber.putError(.network)
            case .empty: subscriber.putCompletion()
            case .controlled: break
            }
            return ActionDisposable { _ = self.disposed.swap(true); _ = FixtureProviders.active.modify { $0 - 1 } }
        }
    }
    func next(_ value: String) { subscriber.with { $0 }?.putNext(value) }
    func fail() { subscriber.with { $0 }?.putError(.network) }
    func complete() { subscriber.with { $0 }?.putCompletion() }
}
enum FixtureProviders {
    static let ledger = Atomic<[FixtureRequest]>(value: [])
    static let active = Atomic(value: 0)
    static let maximumActive = Atomic(value: 0)
    static var mode = FixtureMode.sync
    static var rpc = FixtureRPC.value
    static var entities: [NSRange] = []
    static var requests: [FixtureRequest] { ledger.with { $0 } }
    static func signal(_ provider: String, _ text: String, _ target: String) -> Signal<String, TranslateFetchError> { FixtureRequest(provider, text, target).signal() }
    static func reset() { precondition(active.with { $0 } == 0); _ = maximumActive.swap(0); _ = ledger.swap([]); mode = .sync; rpc = .value; entities = [] }
}
func googleTranslate(_ text: String, _ target: String) -> Signal<String, TranslateFetchError> { FixtureProviders.signal("google", text, target) }
func googleCNTranslate(_ text: String, _ target: String) -> Signal<String, TranslateFetchError> { FixtureProviders.signal("googleCN", text, target) }
func microsoftTranslate(_ text: String, _ target: String) -> Signal<String, TranslateFetchError> { FixtureProviders.signal("microsoft", text, target) }
func yandexTranslate(_ text: String, _ target: String) -> Signal<String, TranslateFetchError> { FixtureProviders.signal("yandex", text, target) }
func tranSmartTranslate(_ text: String, _ target: String) -> Signal<String, TranslateFetchError> { FixtureProviders.signal("transmart", text, target) }
func regramSystemTranslate(text: String, to: String) -> Signal<String, TranslateFetchError> { FixtureProviders.signal("system", text, to) }
func llmTranslate(_ text: String, _ target: String, context: [String], configuration: RGLLMTranslationConfiguration) -> Signal<String, TranslateFetchError> {
    precondition(configuration.apiKey == "memory-key" && context.isEmpty)
    return FixtureProviders.signal("llm", text, target)
}
enum FixtureCredentialPurpose { case translation }
final class RegramCredentials {
    static let shared = RegramCredentials()
    func read(accountId: Int64, purpose: FixtureCredentialPurpose) throws -> String { "memory-key" }
}
enum Translate {
    static func detectLanguage(for text: String) -> String? { nil }
}
enum TextRecognizing {
    struct Detected { let text: String }
    enum Result { typealias Detected = TextRecognizing.Detected; case progress(Double), finish(image: Int, text: [Detected], barcodes: [Int]) }
    enum TranslateResult {
        struct Value { let text: String; let detected: Detected }
        case progress(Result), success(translated: [Value], original: Result)
    }
}
struct FixturePeerId { var namespace: Int32 = 0; func toInt64() -> Int64 { 42 } }
struct FixtureMessageId { var namespace: Int32 = 0; var peerId = FixturePeerId() }
struct FixtureMessage {
    var id = FixtureMessageId()
    var containsSecretMedia = false
    var protected = false
    func isCopyProtected() -> Bool { protected }
}
enum Namespaces { enum Message { static let Cloud: Int32 = 0 }; enum Peer { static let SecretChat: Int32 = 2 } }
final class FixtureEntry {
    var isProtected = false
    var paidMedia = false
    var message: FixtureMessage? = FixtureMessage()
    var localAllowed = true
    func regramCanExport(accountId: Int64) -> Bool { localAllowed }
}
final class FixtureMessages {
    func translate(text: String, toLang: String) -> Signal<(String, [NSRange])?, TranslateFetchError> {
        FixtureProviders.signal("default", text, toLang) |> mapToSignal { value in
            switch FixtureProviders.rpc {
            case .value: return .single((value, FixtureProviders.entities))
            case .nilValue: return .single(nil)
            case .fail: return .fail(.network)
            case .empty: return .complete()
            }
        }
    }
}
struct FixtureEngine { let messages = FixtureMessages() }
struct FixtureBaseSettings { let doNotTranslate = Set<String>() }
struct FixtureSharedContext { let baseSettings = FixtureBaseSettings() }
final class FixtureContext {
    let peerId = FixturePeerId()
    let engine = FixtureEngine()
    let sharedContext = FixtureSharedContext()
    var allowed = true
    var permissionCalls = 0
    var emptyPermissionAt: Int?
}
final class FixtureItem {
    let context: FixtureContext
    let entry = FixtureEntry()
    init(_ context: FixtureContext) { self.context = context }
}
final class Window {}
struct FixtureView { var window: AnyObject? = Window() }
struct FixtureAppearance { let languageCode = "en" }
let appAppearance = FixtureAppearance()
struct FixtureStrings { let errorAnError = "An error occurred" }
func strings() -> FixtureStrings { FixtureStrings() }
var notices: [String] = []
func showModalText(for window: Window, text: String) { precondition(Thread.isMainThread); notices.append(text) }
func regramValidateGalleryExport(context: FixtureContext, entry: FixtureEntry, permitsProtectedOverride: Bool) -> Signal<Bool, NoError> {
    precondition(Thread.isMainThread && !permitsProtectedOverride)
    context.permissionCalls += 1
    if context.permissionCalls == context.emptyPermissionAt { return .complete() }
    return .single(context.allowed)
}
let suite = "RegramImageTranslationChecks." + UUID().uuidString
let fixtureDefaults = UserDefaults(suiteName: suite)!
let fixturePreferences = RegramPreferences(defaults: fixtureDefaults)
final class FixtureSelector {
    var state = "idle"
    var values: [TextRecognizing.TranslateResult.Value] = []
    func set(_ result: TextRecognizing.Result?, translate: TextRecognizing.TranslateResult?) {
        precondition(Thread.isMainThread)
        values = []
        switch translate {
        case nil: state = "idle"
        case .some(.progress): state = "progress"
        case let .some(.success(translated, _)): state = "success"; values = translated
        }
    }
}
final class RecognitionAudit {
    let item: FixtureItem
    let view = FixtureView()
    private var result: AnyObject?
    private var translation: AnyObject?
    private var sourceIsVisible = true
    private var translationGeneration = UUID()
    private var translationIdentity: String?
    private let translateDisposable = MetaDisposable()
    private var settingsObserver: NSObjectProtocol?
    let selectorView = FixtureSelector()
    init(_ lines: [String], context: FixtureContext = FixtureContext()) {
        item = FixtureItem(context)
        result = TextRecognizing.Result.finish(image: 1, text: lines.map { .init(text: $0) }, barcodes: []) as AnyObject
        let accountId = context.peerId.toInt64()
        __SETTINGS_OBSERVER__
    }
    deinit { translateDisposable.dispose(); if let settingsObserver { NotificationCenter.default.removeObserver(settingsObserver) } }
    func replaceSource(_ lines: [String], visible: Bool = true) {
        sourceIsVisible = visible
        applyResult(nil)
        if visible { applyResult(.finish(image: 2, text: lines.map { .init(text: $0) }, barcodes: [])) }
    }
    __GALLERY_METHODS__
}
func drain() { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
func waitFor(_ predicate: () -> Bool) {
    let deadline = Date().addingTimeInterval(4)
    while !predicate() && Date() < deadline { drain() }
    precondition(predicate(), "Timed out waiting for deterministic image translation")
}
func seed(_ provider: String = "default", mode: FixtureMode = .sync) {
    fixturePreferences.reset(accountId: 42)
    fixturePreferences.update(accountId: 42) { $0["translationBackend"] = .string(provider) }
    drain()
    FixtureProviders.reset()
    FixtureProviders.mode = mode
    notices = []
}
func checkProvidersAndStableMapping() {
    for provider in RegramChatTranslationPolicy.Provider.allCases {
        seed(provider.rawValue)
        let audit = RecognitionAudit(["First line", "Second line", "First line", "123"])
        audit.toggleTranslate(to: "de-DE")
        waitFor { audit.selectorView.state != "progress" }
        precondition(audit.selectorView.state == "success")
        precondition(FixtureProviders.requests.count == 2 && FixtureProviders.requests.allSatisfy { $0.provider == provider.rawValue && $0.target == "de" })
        precondition(audit.selectorView.values.map { $0.detected.text } == ["First line", "Second line", "First line"])
        precondition(audit.selectorView.values.map { $0.text } == ["Translated First line", "Translated Second line", "Translated First line"])
    }
    for ranges in [[], [NSRange(location: 0, length: 1)], [NSRange(location: 40, length: 200), NSRange(location: 0, length: 999), NSRange(location: 0, length: 20)]] {
        seed()
        FixtureProviders.entities = ranges
        let audit = RecognitionAudit(["First 😀", "Second"])
        audit.toggleTranslate(to: "nb-NO")
        waitFor { audit.selectorView.state != "progress" }
        precondition(audit.selectorView.values.count == 2 && FixtureProviders.requests.allSatisfy { $0.target == "no" })
    }
    for (input, expected) in [("zh-Hant", "zh-TW"), ("zh-Hant-raw", "zh-TW"), ("zh-Hans", "zh-CN"), ("zh-Hans-raw", "zh-CN"), ("zh_HK", "zh-TW"), ("nb-NO", "no"), ("nb", "no")] {
        seed()
        let audit = RecognitionAudit(["Language variant"])
        audit.toggleTranslate(to: input)
        waitFor { audit.selectorView.state != "progress" }
        precondition(audit.selectorView.state == "success" && FixtureProviders.requests.map { $0.target } == [expected])
    }
}
func checkBudgetsAndCommonScreenshot() {
    for provider in RegramChatTranslationPolicy.Provider.allCases {
        for lines in [Array(repeating: "word", count: 129), [String(repeating: "a", count: 1001)], (0..<25).map { "Unique \($0)" }, Array(repeating: String(repeating: "a", count: 1000), count: 13)] {
            seed(provider.rawValue)
            let audit = RecognitionAudit(lines)
            audit.toggleTranslate(to: "de")
            waitFor { audit.selectorView.state != "progress" }
            precondition(audit.selectorView.state == "idle" && FixtureProviders.requests.isEmpty && notices.count == 1 && !notices[0].isEmpty)
        }
        seed(provider.rawValue)
        let lines = (0..<20).map { "Screenshot row \($0): readable English text" } + Array(repeating: "Repeated heading", count: 8)
        let audit = RecognitionAudit(lines)
        audit.toggleTranslate(to: "de")
        waitFor { audit.selectorView.state != "progress" }
        precondition(audit.selectorView.values.count == 28 && FixtureProviders.requests.count == 21 && notices.isEmpty)
        precondition(FixtureProviders.maximumActive.with { $0 } == 1)
    }
    seed()
    for lines in [[], ["", "123", "😀"]] {
        let audit = RecognitionAudit(lines)
        precondition(!audit.canTranslate())
        audit.toggleTranslate(to: "de")
        precondition(audit.selectorView.state == "idle" && FixtureProviders.requests.isEmpty)
    }
}
func checkTerminalFailures() {
    for rpc in [FixtureRPC.nilValue, .fail, .empty] {
        seed()
        FixtureProviders.rpc = rpc
        let audit = RecognitionAudit(["First", "Second"])
        audit.toggleTranslate(to: "de")
        waitFor { audit.selectorView.state != "progress" }
        precondition(audit.selectorView.state == "idle" && audit.selectorView.values.isEmpty && notices.count == 1 && FixtureProviders.requests.count == 1)
    }
    for mode in [FixtureMode.fail, .empty] {
        seed("llm", mode: mode)
        let audit = RecognitionAudit(["First", "Second"])
        audit.toggleTranslate(to: "de")
        waitFor { audit.selectorView.state != "progress" }
        precondition(audit.selectorView.state == "idle" && notices.count == 1 && FixtureProviders.requests.count == 1)
    }
    seed()
    let emptyPermission = RecognitionAudit(["Only region"])
    emptyPermission.item.context.emptyPermissionAt = 2
    emptyPermission.toggleTranslate(to: "de")
    waitFor { emptyPermission.selectorView.state != "progress" }
    precondition(emptyPermission.selectorView.state == "idle" && notices.count == 1)
    seed(mode: .controlled)
    let blank = RecognitionAudit(["First", "Second"])
    blank.toggleTranslate(to: "de")
    waitFor { FixtureProviders.requests.count == 1 }
    FixtureProviders.requests[0].next(" \n ")
    waitFor { blank.selectorView.state != "progress" }
    precondition(blank.selectorView.state == "idle" && notices.count == 1 && FixtureProviders.requests.count == 1)
}
func checkSerialCancellationAndSourceChanges() {
    seed(mode: .controlled)
    let pending = RecognitionAudit(["Cancelled before main permission"])
    pending.toggleTranslate(to: "de")
    pending.toggleTranslate(to: "de")
    drain()
    precondition(FixtureProviders.requests.isEmpty && pending.selectorView.state == "idle")
    seed(mode: .controlled)
    let audit = RecognitionAudit(["First", "Second"])
    audit.toggleTranslate(to: "de")
    waitFor { FixtureProviders.requests.count == 1 }
    precondition(audit.selectorView.state == "progress" && audit.selectorView.values.isEmpty)
    let first = FixtureProviders.requests[0]
    first.next("Translated first"); first.complete()
    waitFor { FixtureProviders.requests.count == 2 }
    precondition(audit.selectorView.values.isEmpty)
    audit.toggleTranslate(to: "de")
    precondition(audit.selectorView.state == "idle" && FixtureProviders.requests[1].cancelled)
    FixtureProviders.requests[1].next("Late"); FixtureProviders.requests[1].complete(); drain()
    precondition(audit.selectorView.state == "idle" && notices.isEmpty)
    audit.toggleTranslate(to: "de")
    waitFor { FixtureProviders.requests.count == 3 }
    let old = FixtureProviders.requests[2]
    audit.replaceSource(["Latest"])
    audit.toggleTranslate(to: "de")
    waitFor { FixtureProviders.requests.count == 4 }
    old.next("Stale picture"); old.fail()
    let current = FixtureProviders.requests[3]
    current.next("Current picture"); current.complete()
    waitFor { audit.selectorView.state != "progress" }
    precondition(audit.selectorView.values.map { $0.detected.text } == ["Latest"] && audit.selectorView.values.map { $0.text } == ["Current picture"])
}
func checkPermissionsConfigurationAndLifetime() {
    for source in ["protected", "paid", "secret", "private", "local", "copyProtected", "freshDenied"] {
        seed()
        let audit = RecognitionAudit(["Private source"])
        switch source {
        case "protected": audit.item.entry.isProtected = true
        case "paid": audit.item.entry.paidMedia = true
        case "secret": audit.item.entry.message?.containsSecretMedia = true
        case "private": audit.item.entry.message?.id.peerId.namespace = Namespaces.Peer.SecretChat
        case "local": audit.item.entry.message?.id.namespace = 1
        case "copyProtected": audit.item.entry.message?.protected = true
        default: audit.item.context.allowed = false
        }
        audit.toggleTranslate(to: "de"); drain()
        precondition(FixtureProviders.requests.isEmpty && audit.selectorView.state == "idle")
    }
    for reason in ["hidden", "permission", "configuration"] {
        seed(mode: .controlled)
        let audit = RecognitionAudit(["First", "Second"])
        audit.toggleTranslate(to: "de")
        waitFor { FixtureProviders.requests.count == 1 }
        let old = FixtureProviders.requests[0]
        if reason == "hidden" { audit.replaceSource([], visible: false) }
        else if reason == "permission" { audit.item.context.allowed = false }
        else { fixturePreferences.update(accountId: 42) { $0["serviceConfigurationRevision"] = .integer($0["serviceConfigurationRevision"].integer + 1) }; drain() }
        old.next("Old configuration"); old.complete()
        waitFor { audit.selectorView.state != "progress" }
        precondition(audit.selectorView.state == "idle" && audit.selectorView.values.isEmpty && FixtureProviders.requests.count == 1 && notices.isEmpty)
    }
    seed(mode: .controlled)
    let finalPermission = RecognitionAudit(["Only region"])
    finalPermission.toggleTranslate(to: "de")
    waitFor { FixtureProviders.requests.count == 1 }
    finalPermission.item.context.allowed = false
    FixtureProviders.requests[0].next("Denied result")
    FixtureProviders.requests[0].complete()
    waitFor { finalPermission.selectorView.state != "progress" }
    precondition(finalPermission.selectorView.state == "idle" && finalPermission.selectorView.values.isEmpty && notices.isEmpty)
    seed(mode: .controlled)
    var audit: RecognitionAudit? = RecognitionAudit(["Lifetime"])
    weak let weakAudit = audit
    weak let weakItem = audit!.item
    audit!.toggleTranslate(to: "de")
    waitFor { FixtureProviders.requests.count == 1 }
    audit = nil
    precondition(weakAudit == nil && weakItem == nil && FixtureProviders.requests[0].cancelled)
}

@main
struct ImageTranslationChecks {
    static func main() {
        defer { fixtureDefaults.removePersistentDomain(forName: suite) }
        checkProvidersAndStableMapping()
        checkBudgetsAndCommonScreenshot()
        checkTerminalFailures()
        checkSerialCancellationAndSourceChanges()
        checkPermissionsConfigurationAndLifetime()
        print("Image translation logic checks passed: all providers, budgets with zero rejected requests, stable regions, target normalization, malformed entities ignored, sync/nil/error/empty, serial cancellation, source/configuration/hidden/lifetime; no network or user data.")
    }
}
