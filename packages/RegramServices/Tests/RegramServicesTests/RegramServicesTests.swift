import RegramCore
import XCTest
@testable import RegramServices

final class RegramServicesTests: XCTestCase {
    func testDoHValidatesAddressFamilyAndIgnoresAliases() throws {
        let data = Data("{\"Status\":0,\"Answer\":[{\"type\":5,\"data\":\"example.test.\"},{\"type\":1,\"data\":\"192.0.2.1\"},{\"type\":1,\"data\":\"192.0.2.1\"},{\"type\":28,\"data\":\"2001:db8::1\"},{\"type\":1,\"data\":\"invalid\"}]}".utf8)
        XCTAssertEqual(try RegramDNSDiagnostics.parse(data, ipv6: false), ["192.0.2.1"])
        XCTAssertEqual(try RegramDNSDiagnostics.parse(data, ipv6: true), ["2001:db8::1"])
        XCTAssertThrowsError(try RegramDNSDiagnostics.parse(Data("{\"Status\":3}".utf8), ipv6: false))
    }

    func testProtectedOnlyTranslationCompletesWithoutNetwork() {
        let done = expectation(description: "protected translation")
        let text = " https://example.test/a?q=1 "
        let task = regramProtectedTranslation(text: text, to: "zh", accountId: 1, settings: RegramAccountSettings(), ranges: [], protectedIds: []).start(next: { result in
            XCTAssertEqual(result.text, text)
            done.fulfill()
        }, error: { _ in XCTFail("Protected text should not reach a provider") })
        defer { task.dispose() }
        wait(for: [done], timeout: 3)
    }

    func testSTTRejectsEmbeddedCredentialsAndMissingModel() {
        XCTAssertThrowsError(try RGSTTConfiguration(baseURL: "https://user:pass@example.test", endpoint: "", model: "model", language: "", prompt: "", apiKey: ""))
        XCTAssertThrowsError(try RGSTTConfiguration(baseURL: "https://example.test", endpoint: "", model: "", language: "", prompt: "", apiKey: ""))
        XCTAssertThrowsError(try RGSTTConfiguration(baseURL: "http://api.openai.com", endpoint: "", model: "model", language: "", prompt: "", apiKey: "test"))
    }

    func testLocalSTTEndpointAndLanguageValidation() throws {
        let config = try RGSTTConfiguration(baseURL: "http://127.0.0.1:8000/v1", endpoint: "/v1/audio/transcriptions", model: "local", language: "ZH", prompt: "", apiKey: "")
        XCTAssertEqual(config.url.absoluteString, "http://127.0.0.1:8000/v1/audio/transcriptions")
        XCTAssertEqual(config.language, "zh")
        XCTAssertThrowsError(try RGSTTConfiguration(baseURL: "https://example.test", endpoint: "", model: "model", language: "zh-CN", prompt: "", apiKey: ""))
    }

    func testLLMEndpointJoiningAndSeparateModelEndpoint() {
        let configuration = RGLLMTranslationConfiguration(format: .openai, baseURL: "https://example.test/v1/", endpoint: "/v1/chat/completions", apiKey: "", model: "local", prompt: "", temperature: 0.2)
        XCTAssertEqual(configuration.translationURL?.absoluteString, "https://example.test/v1/chat/completions")
        XCTAssertEqual(configuration.modelsURL?.absoluteString, "https://example.test/v1/models")
    }

    func testLLMServiceAddressesIncludeVersionOrFullRequestPath() {
        for base in ["http://127.0.0.1:1111", "http://127.0.0.1:1111/v1", "http://127.0.0.1:1111/v1/", "http://127.0.0.1:1111/v1/chat/completions"] {
            let configuration = RGLLMTranslationConfiguration(format: .openai, baseURL: base, endpoint: "", apiKey: "", model: "local", prompt: "", temperature: 0.2)
            XCTAssertEqual(configuration.translationURL?.absoluteString, "http://127.0.0.1:1111/v1/chat/completions")
            XCTAssertEqual(configuration.modelsURL?.absoluteString, "http://127.0.0.1:1111/v1/models")
        }
        let anthropic = RGLLMTranslationConfiguration(format: .anthropic, baseURL: "https://example.test/proxy/v1/messages", endpoint: "", apiKey: "", model: "local", prompt: "", temperature: 0.2)
        XCTAssertEqual(anthropic.translationURL?.absoluteString, "https://example.test/proxy/v1/messages")
        XCTAssertEqual(anthropic.modelsURL?.absoluteString, "https://example.test/proxy/v1/models")
    }

    func testLanguageNormalizationAndUnicodeChunking() {
        XCTAssertEqual(getGTranslateLang("zh-Hans"), "zh-CN")
        XCTAssertEqual(getGTranslateLang("zh-Hant"), "zh-TW")
        let text = String(repeating: "中文👨‍👩‍👧‍👦\n", count: 700)
        let chunks = gtranslateSplitTextBySentences(text, maxChunkLength: 1200)
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertGreaterThan(chunks.count, 1)
    }

    func testTranscriptionResponseAndCredentialRedaction() throws {
        let url = try XCTUnwrap(URL(string: "https://example.test/transcriptions"))
        let ok = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        XCTAssertEqual(try RGOpenAITranscriptionProvider.parse(data: Data("{\"text\":\"recognized\"}".utf8), response: ok, apiKey: "fixture-key"), "recognized")
        let failed = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 403, httpVersion: nil, headerFields: nil))
        XCTAssertThrowsError(try RGOpenAITranscriptionProvider.parse(data: Data("{\"error\":{\"message\":\"denied fixture-key\"}}".utf8), response: failed, apiKey: "fixture-key")) { error in
            XCTAssertFalse(error.localizedDescription.contains("fixture-key"))
        }
    }
}
