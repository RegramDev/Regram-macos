import XCTest
import Postbox
@testable import ChatHistoryModel

final class RegramChatTranslationStateTests: XCTestCase {
    func testFreshRecognitionSurvivesPostboxRoundTrip() throws {
        let state = ChatTranslationState(baseLang: "zh-CN", fromLang: "zh-TW", toLang: "en", isEnabled: true, paywall: false, tone: .formal, timestamp: 10_000)
        let entry = try XCTUnwrap(CodableEntry(state))
        let restored = try XCTUnwrap(entry.get(ChatTranslationState.self))

        XCTAssertEqual(restored, state)
        XCTAssertTrue(restored.hasCurrentRecognition(baseLang: "zh-CN", now: 10_001))
        XCTAssertFalse(restored.hasCurrentRecognition(baseLang: "zh-TW", now: 10_001))
        XCTAssertFalse(restored.hasCurrentRecognition(baseLang: "zh-CN", now: 13_600))
    }

    func testDecodesExistingCacheWithOrWithoutRecognitionVersion() throws {
        for version: Int32? in [nil, 1] {
            let encoder = PostboxEncoder()
            encoder.encodeString("zh-TW", forKey: "baseLang")
            encoder.encodeString("", forKey: "fromLang")
            encoder.encodeString("zh-CN", forKey: "toLang")
            encoder.encodeBool(false, forKey: "isEnabled")
            encoder.encodeString("casual", forKey: "tone")
            encoder.encodeInt32(10_000, forKey: "timestamp")
            if let version {
                encoder.encodeInt32(version, forKey: "recognitionVersion")
            }
            let restored = try AdaptedPostboxDecoder().decode(ChatTranslationState.self, from: encoder.makeData())

            XCTAssertEqual(restored.fromLang, "")
            XCTAssertEqual(restored.toLang, "zh-CN")
            XCTAssertEqual(restored.isEnabled, false)
            XCTAssertEqual(restored.tone, .casual)
            XCTAssertEqual(restored.hasCurrentRecognition(baseLang: "zh-TW", now: 10_001), version != nil)
        }
    }
}
