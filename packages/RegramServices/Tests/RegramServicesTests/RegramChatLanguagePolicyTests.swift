import XCTest
@testable import RegramServices

final class RegramChatLanguagePolicyTests: XCTestCase {
    func testChineseScriptsCompareAsOneLanguageWithoutLosingRequestTargets() {
        for source in ["zh", "zh-Hans", "zh-Hant", "zh-CN", "zh-TW", "zh_hk"] {
            XCTAssertFalse(RegramChatLanguagePolicy.canDisplay(source: source, target: "zh-CN", interfaceLanguage: "zh-Hans", active: false))
        }
        XCTAssertEqual(RegramChatLanguagePolicy.targetCode("zh-Hans-raw"), "zh-CN")
        XCTAssertEqual(RegramChatLanguagePolicy.targetCode("zh-Hant"), "zh-TW")
        XCTAssertEqual(RegramChatLanguagePolicy.targetCode("zh-TW"), "zh-TW")
        XCTAssertEqual(RegramChatLanguagePolicy.comparisonCode("nb-NO"), "no")
        XCTAssertEqual(RegramChatLanguagePolicy.comparisonCode("en-US"), "en")
    }

    func testForeignMonolingualChatAndActiveOriginalControlRemainAvailable() {
        XCTAssertTrue(RegramChatLanguagePolicy.canDisplay(source: "en", target: "zh-CN", interfaceLanguage: "zh-Hans", active: false))
        XCTAssertTrue(RegramChatLanguagePolicy.canDisplay(source: "zh-Hant", target: "en", interfaceLanguage: "zh-Hans", active: true))
        XCTAssertFalse(RegramChatLanguagePolicy.canDisplay(source: "zh-Hant", target: "en", interfaceLanguage: "zh-Hans", active: false))
        XCTAssertFalse(RegramChatLanguagePolicy.canDisplay(source: "", target: "en", interfaceLanguage: "zh-Hans", active: true))
        XCTAssertFalse(RegramChatLanguagePolicy.canDisplay(source: "en-US", target: "en-GB", interfaceLanguage: "zh-Hans", active: false))
    }

    func testIgnoredLanguagesNormalizeInterfaceAndRespectExplicitList() {
        XCTAssertEqual(RegramChatLanguagePolicy.ignoredLanguages(interfaceLanguage: "zh-Hans-raw", configured: [], systemLanguages: ["en-US", "ja-JP"]), ["zh", "en"])
        XCTAssertEqual(RegramChatLanguagePolicy.ignoredLanguages(interfaceLanguage: "zh-Hant", configured: [], systemLanguages: ["en-US", "ru-RU"]), ["zh", "en", "ru"])
        XCTAssertEqual(RegramChatLanguagePolicy.ignoredLanguages(interfaceLanguage: "zh-Hans", configured: ["de-DE", "zh-Hant"], systemLanguages: ["en-US"]), ["de", "zh"])
    }

    func testRecognitionWeightsIncomingTextRatherThanOutgoingOrMessageCount() {
        let english = RegramChatLanguagePolicy.Sample(text: "English message content", incoming: true)
        let chinese = RegramChatLanguagePolicy.Sample(text: String(repeating: "中文消息内容", count: 60), incoming: true)
        let outgoing = RegramChatLanguagePolicy.Sample(text: String(repeating: "French outgoing message", count: 100), incoming: false)
        let result = RegramChatLanguagePolicy.dominantLanguage(samples: [outgoing] + Array(repeating: english, count: 5) + [chinese], supported: ["en", "zh", "fr"]) { text in
            text.contains("中文") ? "zh-Hans" : text.contains("English") ? "en" : "fr"
        }
        XCTAssertEqual(result, "zh")
        let capped = RegramChatLanguagePolicy.dominantLanguage(samples: Array(repeating: english, count: 16) + [chinese], supported: ["en", "zh"]) { $0.contains("中文") ? "zh-Hans" : "en" }
        XCTAssertEqual(capped, "en")
    }

    func testRecognitionRemovesUtf16EntitiesIncludingOverlapsAndTrailingLinks() {
        let text = "📣群聊中的中文消息足够用于识别 https://example.com/@someone"
        let full = text as NSString
        let link = full.range(of: "https://example.com/@someone")
        let sample = RegramChatLanguagePolicy.Sample(text: text, incoming: true, excludedRanges: [link, full.range(of: "@someone"), NSRange(location: NSNotFound, length: 1)])
        let recognition = RegramChatLanguagePolicy.recognitionText(sample)
        XCTAssertEqual(recognition, "📣群聊中的中文消息足够用于识别 ")
        let result = RegramChatLanguagePolicy.dominantLanguage(samples: [sample], supported: ["zh"]) { value in
            XCTAssertEqual(value, recognition)
            return "zh-Hans"
        }
        XCTAssertEqual(result, "zh")
        let onlyCode = RegramChatLanguagePolicy.Sample(text: "console.log(message)", incoming: true, excludedRanges: [NSRange(location: 0, length: 20)])
        XCTAssertNil(RegramChatLanguagePolicy.dominantLanguage(samples: [onlyCode], supported: ["en"]) { _ in XCTFail("Code-only text must not reach recognition"); return "en" })
    }

    func testOnlyRecentTimestampedPredictionsCanBeReused() {
        XCTAssertFalse(RegramChatLanguagePolicy.isFresh(timestamp: nil, now: 10_000))
        XCTAssertTrue(RegramChatLanguagePolicy.isFresh(timestamp: 6_401, now: 10_000))
        XCTAssertFalse(RegramChatLanguagePolicy.isFresh(timestamp: 6_400, now: 10_000))
        XCTAssertFalse(RegramChatLanguagePolicy.isFresh(timestamp: 10_001, now: 10_000))
    }
}
