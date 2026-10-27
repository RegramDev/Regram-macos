typealias InputDataEntry = EditorEntry
enum GeneralViewType { case firstItem, innerItem, lastItem, singleItem, textBottomItem, textTopItem }
enum FixtureSectionType { case normal }
enum FixtureInputMode { case plain, secure }
enum FixtureText { case plain(String); var value: String { switch self { case let .plain(value): return value } } }
struct FixtureInputData { init(viewType: GeneralViewType) {} }
struct FixturePlaceholder { let title: String; init(_ title: String) { self.title = title } }
struct FixtureGeneralTextData { init(color: NSColor, viewType: GeneralViewType) {} }
struct FixtureGeneralData {
    let name: String
    let type: GeneralInteractedType
    let enabled: Bool
    let action: (() -> Void)?
    init(name: String, color: NSColor, type: GeneralInteractedType, viewType: GeneralViewType, enabled: Bool = true, action: (() -> Void)? = nil) { self.name = name; self.type = type; self.enabled = enabled; self.action = action }
}
struct InputDataEquatable { init<T>(_ value: T) {} }
struct InputDataEntryId { let value: String }
final class PrecieSliderRowItem {
    init(_ size: NSSize, stableId: InputDataEntryId, current: CGFloat, magnit: [CGFloat], update: @escaping (CGFloat) -> Void, viewType: GeneralViewType) {}
}
extension EditorEntry {
    static func sectionId(_ section: Int32, type: FixtureSectionType) -> EditorEntry { EditorEntry("section.\(section)", index: Int(section), title: "section") }
    static func desc(sectionId: Int32, index: Int32, text: FixtureText, data: FixtureGeneralTextData) -> EditorEntry { EditorEntry("text.\(index)", index: Int(index), title: text.value) }
    static func input(sectionId: Int32, index: Int32, value: InputDataValue, error: String?, identifier: InputDataIdentifier, mode: FixtureInputMode, data: FixtureInputData, placeholder: FixturePlaceholder?, inputPlaceholder: String, filter: (String) -> String, limit: Int) -> EditorEntry { EditorEntry(identifier.value, index: Int(index), title: placeholder?.title ?? "", type: .contextSelector(value.stringValue ?? "", []), input: true) }
    static func general(sectionId: Int32, index: Int32, value: InputDataValue, error: String?, identifier: InputDataIdentifier, data: FixtureGeneralData) -> EditorEntry { EditorEntry(identifier.value, index: Int(index), title: data.name, type: data.type, enabled: data.enabled, action: data.action) }
    static func custom(sectionId: Int32, index: Int32, value: InputDataValue, identifier: InputDataIdentifier, equatable: InputDataEquatable?, comparable: String?, item: (NSSize, InputDataEntryId) -> PrecieSliderRowItem) -> EditorEntry { EditorEntry(identifier.value, index: Int(index), title: "slider") }
}
struct FixtureTheme { struct Colors { let listGrayText = NSColor.gray; let text = NSColor.textColor; let accent = NSColor.blue }; let colors = Colors() }
let theme = FixtureTheme()
var serviceNotices: [String] = []
var serviceAlerts: [String] = []
func showModalText(for window: NSObject, text: String, title: String) { serviceNotices.append(title + ":" + text) }
func alert(for window: NSObject, header: String = "", info: String) { serviceAlerts.append(header + ":" + info) }
enum RegramCredentialPurpose: String { case translation, transcription, summary }
struct RegramKeychainError: Error { let status: Int }
final class RegramCredentials {
    static let shared = RegramCredentials()
    var values: [String: String] = [:]
    var writeFailuresRemaining = 0
    var writeAttempts = 0
    func read(accountId: Int64, purpose: RegramCredentialPurpose) throws -> String { values["\(accountId).\(purpose.rawValue)"] ?? "" }
    func write(_ value: String, accountId: Int64, purpose: RegramCredentialPurpose) throws {
        writeAttempts += 1
        if writeFailuresRemaining > 0 {
            writeFailuresRemaining -= 1
            throw RegramKeychainError(status: -1)
        }
        values["\(accountId).\(purpose.rawValue)"] = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
final class ControlledRequest<T, E> {
    var subscriber: Subscriber<T, E>?
    var cancelled = false
    var attemptedEmissions = 0
    func signal() -> Signal<T, E> {
        Signal { subscriber in self.subscriber = subscriber; return ActionDisposable { self.cancelled = true } }
    }
    func next(_ value: T) { attemptedEmissions += 1; subscriber?.putNext(value) }
    func fail(_ error: E) { attemptedEmissions += 1; subscriber?.putError(error) }
    func complete() { subscriber?.putCompletion() }
}
enum ServiceRequests {
    static var tests: [(RGLLMTranslationConfiguration, ControlledRequest<Void, RGLLMRequestError>)] = []
    static var models: [(RGLLMTranslationConfiguration, ControlledRequest<[String], RGLLMRequestError>)] = []
    static var transcriptions: [(RGSTTConfiguration, ControlledRequest<String, RGTranscriptionError>)] = []
}
func llmTestModel(configuration: RGLLMTranslationConfiguration) -> Signal<Void, RGLLMRequestError> {
    let request = ControlledRequest<Void, RGLLMRequestError>()
    ServiceRequests.tests.append((configuration, request))
    return request.signal()
}
func llmFetchModels(configuration: RGLLMTranslationConfiguration) -> Signal<[String], RGLLMRequestError> {
    let request = ControlledRequest<[String], RGLLMRequestError>()
    ServiceRequests.models.append((configuration, request))
    return request.signal()
}
enum RGOpenAITranscriptionProvider {
    static func transcribe(configuration: RGSTTConfiguration, audioURL: URL) -> Signal<String, RGTranscriptionError> {
        precondition(audioURL.scheme == "memory")
        let request = ControlledRequest<String, RGTranscriptionError>()
        ServiceRequests.transcriptions.append((configuration, request))
        return request.signal()
    }
}
func fixtureTestAudioURL() -> URL? { URL(string: "memory://audio/RGSTTTest.m4a") }
func drain() { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
func seedService() {
    testPreferences.reset(accountId: 42)
    RegramCredentials.shared.values.removeAll()
    RegramCredentials.shared.writeFailuresRemaining = 0
    RegramCredentials.shared.writeAttempts = 0
    ServiceRequests.tests.removeAll(); ServiceRequests.models.removeAll(); ServiceRequests.transcriptions.removeAll()
    serviceNotices.removeAll(); serviceAlerts.removeAll()
    testPreferences.update(accountId: 42) {
        $0["translationLLMBaseURL"] = .string("https://first.example/v1")
        $0["translationLLMModel"] = .string("first-model")
        $0["sttBaseURL"] = .string("https://first.example/v1")
        $0["sttModel"] = .string("first-stt")
    }
}
func isIdle(_ controller: InputDataController, key: String) -> Bool { controller.entry(key).type.identity == "none" }
func hasModelPicker(_ controller: InputDataController) -> Bool { controller.entries.contains { $0.identifier == "llm.selectModel" } }

@main
struct ServiceEditorChecks {
    static func main() throws {
        defer { testDefaults.removePersistentDomain(forName: suite) }
        checkOldLLMActionsReadLatestDraft()
        checkModelListsBelongToConnection()
        checkEditingCancelsOldRequestsAndRejectsCallbacks()
        try checkSTTLatestDraftCancelAndLeave()
        checkLeavingAndDeinitCancelLLM()
        try checkCredentialRetryAdvancesIdentity()
        print("Service editor checks passed: reused actions read current LLM/STT drafts and memory credentials, edits cancel requests, stale success/errors stay invisible, base/key/format clear models, cancel/leave/deinit, credential retry identity; no Keychain, account or network was used")
    }
    static func checkOldLLMActionsReadLatestDraft() {
        seedService()
        let controller = RegramServiceController(context: EditorContext(), purpose: .translation)
        let originalTest = controller.entry("llm.testModel")
        let originalFetch = controller.entry("llm.fetchModels")
        controller.input("llm.baseURL", "https://latest.example/v1/chat/completions")
        controller.input("llm.model", "latest-model")
        controller.input("llm.apiKey", "latest-key")
        precondition(controller.entry("llm.testModel") === originalTest && controller.entry("llm.fetchModels") === originalFetch)
        originalTest.action!()
        let (configuration, request) = ServiceRequests.tests.last!
        precondition(configuration.baseURL == "https://latest.example/v1/chat/completions" && configuration.model == "latest-model" && configuration.apiKey == "latest-key")
        precondition(configuration.translationURL?.absoluteString == "https://latest.example/v1/chat/completions")
        request.next(()); request.complete()
        precondition(serviceNotices.count == 1)
        originalFetch.action!()
        let (fetched, models) = ServiceRequests.models.last!
        precondition(fetched.baseURL == configuration.baseURL && fetched.model == configuration.model && fetched.apiKey == configuration.apiKey)
        models.next(["latest-model", "another"]); models.complete()
        precondition(hasModelPicker(controller))
        precondition((try! RegramCredentials.shared.read(accountId: 42, purpose: .translation)) == "latest-key")
        precondition(testPreferences.settings(accountId: 42)["translationLLMModel"].string == "latest-model")
    }
    static func checkModelListsBelongToConnection() {
        seedService()
        let controller = RegramServiceController(context: EditorContext(), purpose: .translation)
        let fetch = controller.entry("llm.fetchModels").action!
        for field in ["baseURL", "apiKey", "format"] {
            fetch()
            let request = ServiceRequests.models.last!.1
            request.next(["provider-model"]); request.complete()
            precondition(hasModelPicker(controller))
            if field == "format" { controller.select("llm.format", "Anthropic") }
            else { controller.input("llm." + field, field == "apiKey" ? "replacement-key" : "https://replacement.example") }
            precondition(!hasModelPicker(controller))
        }
        fetch()
        precondition(ServiceRequests.models.last!.0.format == .anthropic)
    }
    static func checkEditingCancelsOldRequestsAndRejectsCallbacks() {
        for kind in ["test", "models"] {
            for failure in [false, true] {
                for field in ["model", "baseURL", "apiKey", "format"] {
                    seedService()
                    let controller = RegramServiceController(context: EditorContext(), purpose: .translation)
                    let action = controller.entry(kind == "test" ? "llm.testModel" : "llm.fetchModels").action!
                    action()
                    let oldTest = ServiceRequests.tests.last?.1
                    let oldModels = ServiceRequests.models.last?.1
                    if field == "format" { controller.select("llm.format", "Anthropic") }
                    else { controller.input("llm." + field, field == "baseURL" ? "https://changed.example" : "changed-" + field) }
                    precondition(oldTest?.cancelled ?? oldModels!.cancelled)
                    precondition(isIdle(controller, key: "llm.testModel") && isIdle(controller, key: "llm.fetchModels"))
                    action()
                    if kind == "test" {
                        if failure { oldTest!.fail(RGLLMRequestError("old-test-error")) } else { oldTest!.next(()); oldTest!.complete() }
                        precondition(controller.entry("llm.testModel").type.identity == "loading")
                        ServiceRequests.tests.last!.1.next(()); ServiceRequests.tests.last!.1.complete()
                        precondition(serviceNotices.count == 1 && serviceAlerts.isEmpty)
                    } else {
                        if failure { oldModels!.fail(RGLLMRequestError("old-model-error")) } else { oldModels!.next(["old-model"]); oldModels!.complete() }
                        precondition(controller.entry("llm.fetchModels").type.identity == "loading" && !hasModelPicker(controller))
                        ServiceRequests.models.last!.1.next(["current-model"]); ServiceRequests.models.last!.1.complete()
                        precondition(hasModelPicker(controller) && serviceNotices.isEmpty && serviceAlerts.isEmpty)
                    }
                }
            }
        }
    }
    static func checkSTTLatestDraftCancelAndLeave() throws {
        seedService()
        let controller = RegramServiceController(context: EditorContext(), purpose: .transcription)
        let oldTest = controller.entry("stt.test").action!
        controller.input("stt.baseURL", "http://127.0.0.1:8123/v1")
        controller.input("stt.endpoint", "/v1/audio/transcriptions")
        controller.input("stt.model", "latest-stt")
        controller.input("stt.apiKey", "stt-memory-key")
        oldTest()
        let (configuration, original) = ServiceRequests.transcriptions.last!
        precondition(configuration.url.absoluteString == "http://127.0.0.1:8123/v1/audio/transcriptions" && configuration.model == "latest-stt" && configuration.apiKey == "stt-memory-key")
        oldTest()
        precondition(original.cancelled && isIdle(controller, key: "stt.test"))
        original.next("old-after-cancel"); original.fail(.network("old-error"))
        precondition(serviceNotices.isEmpty && serviceAlerts.isEmpty)
        oldTest()
        let editing = ServiceRequests.transcriptions.last!.1
        controller.input("stt.apiKey", "changed-key")
        precondition(editing.cancelled && isIdle(controller, key: "stt.test"))
        editing.next("old-key-success")
        precondition(serviceNotices.isEmpty)
        oldTest()
        let leaving = ServiceRequests.transcriptions.last!.1
        controller.afterDisappear()
        precondition(leaving.cancelled)
        leaving.fail(.network("after-leave"))
        precondition(serviceNotices.isEmpty && serviceAlerts.isEmpty)
        let savedKey = try RegramCredentials.shared.read(accountId: 42, purpose: .transcription)
        precondition(savedKey == "changed-key")
    }
    static func checkLeavingAndDeinitCancelLLM() {
        for deinitialize in [false, true] {
            seedService()
            var controller: InputDataController? = RegramServiceController(context: EditorContext(), purpose: .translation)
            controller!.entry("llm.fetchModels").action!()
            let request = ServiceRequests.models.last!.1
            if deinitialize { controller = nil } else { controller!.afterDisappear() }
            precondition(request.cancelled)
            request.next(["late"]); request.fail(RGLLMRequestError("late-error")); drain()
            precondition(serviceNotices.isEmpty && serviceAlerts.isEmpty)
        }
    }
    static func checkCredentialRetryAdvancesIdentity() throws {
        for (purpose, actionKey) in [(RegramServicePurpose.translation, "llm.testModel"), (.translation, "llm.fetchModels"), (.transcription, "stt.test")] {
            seedService()
            let controller = RegramServiceController(context: EditorContext(), purpose: purpose)
            let action = controller.entry(actionKey).action!
            let prefix = purpose == .translation ? "llm" : "stt"
            let before = testPreferences.settings(accountId: 42).translationIdentity
            RegramCredentials.shared.writeFailuresRemaining = 2
            controller.input(prefix + ".apiKey", "retry-key")
            let failed = testPreferences.settings(accountId: 42)
            let unsaved = try RegramCredentials.shared.read(accountId: 42, purpose: purpose.credentialPurpose)
            precondition(failed.translationIdentity != before)
            precondition(unsaved.isEmpty)
            action()
            precondition(testPreferences.settings(accountId: 42).translationIdentity == failed.translationIdentity)
            precondition(ServiceRequests.tests.isEmpty && ServiceRequests.models.isEmpty && ServiceRequests.transcriptions.isEmpty)
            action()
            let saved = testPreferences.settings(accountId: 42)
            let persisted = try RegramCredentials.shared.read(accountId: 42, purpose: purpose.credentialPurpose)
            precondition(saved["serviceConfigurationRevision"].integer == failed["serviceConfigurationRevision"].integer &+ 1)
            precondition(saved.translationIdentity != failed.translationIdentity)
            precondition(persisted == "retry-key")
            precondition(RegramCredentials.shared.writeAttempts == 3)
            if actionKey == "llm.fetchModels" {
                precondition(ServiceRequests.models.count == 1 && ServiceRequests.models[0].0.apiKey == "retry-key")
                ServiceRequests.models[0].1.next([]); ServiceRequests.models[0].1.complete()
            } else if purpose == .translation {
                precondition(ServiceRequests.tests.count == 1 && ServiceRequests.tests[0].0.apiKey == "retry-key")
                ServiceRequests.tests[0].1.next(()); ServiceRequests.tests[0].1.complete()
            } else {
                precondition(ServiceRequests.transcriptions.count == 1 && ServiceRequests.transcriptions[0].0.apiKey == "retry-key")
                ServiceRequests.transcriptions[0].1.next("synthetic"); ServiceRequests.transcriptions[0].1.complete()
            }
            action()
            precondition(testPreferences.settings(accountId: 42).translationIdentity == saved.translationIdentity)
            precondition(RegramCredentials.shared.writeAttempts == 3)
            controller.afterDisappear()
        }
    }
}
