import Foundation
import SwiftSignalKit

private let fixtureRoot = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("synthetic-upload")

private func verify(_ value: @autoclosure () -> Bool, _ label: String) {
    guard value() else {
        FileHandle.standardError.write(Data((label + "\n").utf8))
        exit(1)
    }
}

private func waitFor(_ label: String, _ condition: () -> Bool) {
    let end = Date().addingTimeInterval(5)
    while !condition() && Date() < end { Thread.sleep(forTimeInterval: 0.005) }
    verify(condition(), label)
}

private final class MemoryProtocol: URLProtocol, @unchecked Sendable {
    struct Record {
        let request: URLRequest
        let body: Data
    }

    struct State {
        var active: [String: MemoryProtocol] = [:]
        var records: [String: Record] = [:]
        var cancelled: Set<String> = []
        var unexpectedHosts = 0
    }

    static let state = Atomic(value: State())
    private var key: String { request.url!.host! + request.url!.path }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard request.url?.host?.hasSuffix(".example.test") == true else {
            _ = Self.state.modify { value in var value = value; value.unexpectedHosts += 1; return value }
            client?.urlProtocol(self, didFailWithError: NSError(domain: "FixtureUnexpectedHost", code: 1))
            return
        }
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable && body.count < 1024 * 1024 {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        _ = Self.state.modify { value in
            var value = value
            value.active[self.key] = self
            value.records[self.key] = Record(request: self.request, body: body)
            return value
        }
    }

    override func stopLoading() {
        _ = Self.state.modify { value in
            var value = value
            if value.active[self.key] === self {
                value.active.removeValue(forKey: self.key)
                value.cancelled.insert(self.key)
            }
            return value
        }
    }

    static func active(_ host: String, _ path: String) -> Bool {
        state.with { $0.active[host + path] != nil }
    }

    static func record(_ host: String, _ path: String) -> Record {
        state.with { $0.records[host + path]! }
    }

    static func respond(_ host: String, _ path: String, status: Int = 200, json: [String: Any]) throws {
        var target: MemoryProtocol?
        _ = state.modify { value in var value = value; target = value.active.removeValue(forKey: host + path); return value }
        verify(target != nil, "No matching active request to respond to")
        let destination = target!
        let response = HTTPURLResponse(url: destination.request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        destination.client?.urlProtocol(destination, didReceive: response, cacheStoragePolicy: .notAllowed)
        destination.client?.urlProtocol(destination, didLoad: try JSONSerialization.data(withJSONObject: json))
        destination.client?.urlProtocolDidFinishLoading(destination)
    }
}

private func fixtureSessionConfiguration() -> URLSessionConfiguration {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MemoryProtocol.self]
    return configuration
}

@main
struct ServiceCombinationChecks {
    static func main() throws {
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtureRoot) }
        let audio = fixtureRoot.appendingPathComponent("synthetic.m4a")
        try Data([0, 1, 2, 3]).write(to: audio)
        let results = Atomic(value: [Int: String]())
        let errors = Atomic(value: [String]())
        var requests: [Disposable] = []
        defer { requests.forEach { $0.dispose() } }
        for index in 0..<4 {
            let format: RGLLMAPIFormat = index.isMultiple(of: 2) ? .openai : .anthropic
            let configuration = RGLLMTranslationConfiguration(format: format, baseURL: "https://translate\(index).example.test/v1", endpoint: "", apiKey: "translation-key-\(index)", model: "translation-model-\(index)", prompt: "Translate @text to @toLang", temperature: Double(index) / 10)
            requests.append(llmTranslate("synthetic-\(index)", "zh-Hant", fromLang: "en", context: ["context-\(index)"], configuration: configuration).start(next: { result in
                _ = results.modify { value in var value = value; value[index] = result; return value }
            }, error: { _ in _ = errors.modify { $0 + ["translation-\(index)"] } }))
        }
        waitFor("Three translation requests failed to start") { MemoryProtocol.state.with { $0.active.count == 3 } }
        verify(!MemoryProtocol.state.with { $0.records.keys.contains { $0.hasPrefix("translate3.") } }, "Queued translation exceeded the concurrency limit")

        let speechResults = Atomic(value: [Int: String]())
        var speech: [Disposable] = []
        for index in 0..<2 {
            let configuration = try RGSTTConfiguration(baseURL: "https://speech\(index).example.test/v1", endpoint: "", model: "speech-model-\(index)", language: index == 0 ? "en" : "zh", prompt: "speech-prompt-\(index)", apiKey: "speech-key-\(index)")
            speech.append(RGOpenAITranscriptionProvider.transcribe(configuration: configuration, audioURL: audio).start(next: { result in
                _ = speechResults.modify { value in var value = value; value[index] = result; return value }
            }, error: { _ in _ = errors.modify { $0 + ["speech-\(index)"] } }))
        }
        defer { speech.forEach { $0.dispose() } }
        waitFor("Speech was blocked behind unrelated translation slots") { (0..<2).allSatisfy { MemoryProtocol.active("speech\($0).example.test", "/v1/audio/transcriptions") } }
        for index in 0..<3 {
            let path = index.isMultiple(of: 2) ? "/v1/chat/completions" : "/v1/messages"
            let record = MemoryProtocol.record("translate\(index).example.test", path)
            let body = try JSONSerialization.jsonObject(with: record.body) as! [String: Any]
            verify(body["model"] as? String == "translation-model-\(index)", "Concurrent translation models interfered")
            if index.isMultiple(of: 2) {
                verify(record.request.value(forHTTPHeaderField: "Authorization") == "Bearer translation-key-\(index)", "Concurrent OpenAI translation credentials interfered")
                verify(record.request.value(forHTTPHeaderField: "x-api-key") == nil, "Anthropic credentials leaked into OpenAI")
            } else {
                verify(record.request.value(forHTTPHeaderField: "x-api-key") == "translation-key-\(index)", "Concurrent Anthropic credentials interfered")
                verify(record.request.value(forHTTPHeaderField: "Authorization") == nil, "OpenAI credentials leaked into Anthropic")
            }
            let serialized = String(data: record.body, encoding: .utf8)!
            verify(serialized.contains("context-\(index)") && serialized.contains("synthetic-\(index)"), "Concurrent prompt/context values interfered")
        }
        for index in 0..<2 {
            let record = MemoryProtocol.record("speech\(index).example.test", "/v1/audio/transcriptions")
            verify(record.request.value(forHTTPHeaderField: "Authorization") == "Bearer speech-key-\(index)", "Translation credentials replaced speech credentials")
            verify(record.request.value(forHTTPHeaderField: "x-api-key") == nil, "Speech retained an Anthropic header")
        }
        let bodies = try FileManager.default.contentsOfDirectory(at: fixtureRoot, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("rg-stt-upload-") }.map { try String(contentsOf: $0.appendingPathComponent("body"), encoding: .utf8) }
        verify(bodies.count == 2 && bodies.contains { $0.contains("speech-model-0") && $0.contains("speech-prompt-0") } && bodies.contains { $0.contains("speech-model-1") && $0.contains("speech-prompt-1") }, "Concurrent speech multipart payloads interfered")

        speech[1].dispose()
        waitFor("Speech cancellation was not delivered") { MemoryProtocol.state.with { $0.cancelled.contains("speech1.example.test/v1/audio/transcriptions") } }
        verify(MemoryProtocol.active("speech0.example.test", "/v1/audio/transcriptions"), "Cancelling one speech request cancelled another")
        requests[0].dispose()
        waitFor("A cancelled translation did not release its slot") { MemoryProtocol.active("translate3.example.test", "/v1/messages") }
        verify(MemoryProtocol.active("speech0.example.test", "/v1/audio/transcriptions"), "Translation cancellation cancelled speech")
        try MemoryProtocol.respond("speech0.example.test", "/v1/audio/transcriptions", json: ["text": "recognized fixture"])
        waitFor("Speech could not complete while translations remained pending") { speechResults.with { $0[0] == "recognized fixture" } }
        verify(speechResults.with { $0[1] == nil }, "Cancelled speech delivered a result")

        let modelResults = Atomic(value: [String]())
        let modelConfiguration = RGLLMTranslationConfiguration(format: .anthropic, baseURL: "https://models.example.test/v1", endpoint: "", apiKey: "models-key", model: "models-fixture", prompt: "", temperature: 0)
        let models = llmFetchModels(configuration: modelConfiguration).start(next: { _ = modelResults.swap($0) }, error: { _ in _ = errors.modify { $0 + ["models"] } })
        defer { models.dispose() }
        waitFor("Independent model listing failed to start") { MemoryProtocol.active("models.example.test", "/v1/models") }
        verify(MemoryProtocol.record("models.example.test", "/v1/models").request.value(forHTTPHeaderField: "x-api-key") == "models-key", "Model listing used a different request's credential")
        try MemoryProtocol.respond("models.example.test", "/v1/models", json: ["data": [["id": "model-b"], ["id": "model-a"], ["id": "model-a"]]])
        waitFor("Model listing failed during active translations") { modelResults.with { $0 == ["model-a", "model-b"] } }

        let failureMessages = Atomic(value: [String]())
        let failingConfiguration = RGLLMTranslationConfiguration(format: .openai, baseURL: "https://failure.example.test", endpoint: "", apiKey: "failure-key", model: "failure-model", prompt: "", temperature: 0)
        let failure = llmTestModel(configuration: failingConfiguration).start(error: { message in _ = failureMessages.modify { $0 + [message.message] } })
        defer { failure.dispose() }
        waitFor("Independent failure request failed to start") { MemoryProtocol.active("failure.example.test", "/v1/chat/completions") }
        try MemoryProtocol.respond("failure.example.test", "/v1/chat/completions", status: 401, json: ["error": ["message": "invalid failure-key"]])
        waitFor("Failure was not returned to its own caller") { !failureMessages.with { $0 }.isEmpty }
        verify(failureMessages.with { $0.allSatisfy { !$0.contains("failure-key") } }, "An API error exposed its request credential")
        verify((1..<4).allSatisfy { MemoryProtocol.active("translate\($0).example.test", $0.isMultiple(of: 2) ? "/v1/chat/completions" : "/v1/messages") }, "One service error cancelled unrelated translation work")

        for index in 1..<4 {
            let json: [String: Any] = index.isMultiple(of: 2) ? ["choices": [["message": ["content": "translated-\(index)"]]]] : ["content": [["type": "text", "text": "translated-\(index)"]]]
            try MemoryProtocol.respond("translate\(index).example.test", index.isMultiple(of: 2) ? "/v1/chat/completions" : "/v1/messages", json: json)
        }
        waitFor("Concurrent translation results did not reach the correct callers") { results.with { $0 == [1: "translated-1", 2: "translated-2", 3: "translated-3"] } }
        verify(errors.with { $0 }.isEmpty, "An unrelated service failed")
        waitFor("Speech upload temporary files survived completion/cancellation") {
            (try? FileManager.default.contentsOfDirectory(at: fixtureRoot, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("rg-stt-upload-") }.isEmpty) == true
        }
        verify(MemoryProtocol.state.with { $0.active.isEmpty && $0.unexpectedHosts == 0 }, "The fixture retained active or unexpected network work")
        rgLLMSession.invalidateAndCancel()
        let report: [String: Any] = ["capturedSyntheticRequests": MemoryProtocol.state.with { $0.records.count }, "simultaneousLLMAndSpeech": true, "credentialsModelsAndPromptsIsolated": true, "cancellationAndFailureIsolated": true, "modelListIndependent": true, "uploadTemporaryFilesReleased": true, "realNetworkRequests": 0, "chatMessagesSent": 0, "realAccountAccess": false]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("report.json"))
        print(String(data: data, encoding: .utf8)!)
    }
}
