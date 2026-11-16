import XCTest

@testable import RegramCore

@available(macOS 10.15, *)
final class SemanticTests: XCTestCase {
    private func tokenizer(length: Int = 128) throws -> RGAdTokenizer {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/RegramCore/ReSieve/ReSieveModel")
        return try RGAdTokenizer(
            vocabulary: String(contentsOf: directory.appendingPathComponent("RGAdVocabulary.txt"), encoding: .utf8), sequenceLength: length)
    }
    func testTokenizerMatchesPinnedBERTReference() throws {
        let cases: [(String, [Int32])] = [
            ("影视信息索引 🔍站内搜索工具", [2512, 6228, 928, 2622, 5164, 2471, 4991, 1079, 3017, 5164, 2339, 1072]),
            ("０ 充 值，免\u{200b}费 体 验 → @example_user", [121, 1041, 966, 117, 1048, 6589, 860, 7741, 370, 4500, 2787]),
            ("Café naïve HELLO! https://example.org/a?x=1", [8377, 11469, 8857, 8701, 106, 7216, 2970]),
            ("新用户注册送3️⃣8️⃣U", [3173, 4500, 2787, 3800, 1085, 6843, 8218, 8207]),
            ("繁體中文資料與資訊", [5246, 7768, 704, 3152, 6536, 3160, 5645, 6536, 6244]),
            ("\u{20000}测试👨‍👩‍👧‍👦。", [100, 3844, 6407, 511]),
            ("订单123456789 已完成。", [6370, 1296, 3144, 2099, 2347, 2130, 2768, 511]),
        ]
        let tokenizer = try tokenizer()
        for (text, expected) in cases { XCTAssertEqual(tokenizer.tokens(text), expected, text) }
    }
    func testWindowsCoverEveryTokenAndRejectOversizedInput() throws {
        let tokenizer = try tokenizer(length: 32)
        let text = String(repeating: "电影", count: 160)
        let tokens = try XCTUnwrap(tokenizer.tokens(text))
        let windows = try XCTUnwrap(tokenizer.windows(text))
        var covered = Set<Int>()
        for (i, window) in windows.enumerated() {
            XCTAssertEqual(window.count, 32)
            XCTAssertEqual(window.first, 101)
            let content = Array(window.dropFirst().prefix { $0 != 102 })
            let start = min(i * 14, tokens.count - 30)
            XCTAssertEqual(content, Array(tokens[start..<start + 30]))
            covered.formUnion(start..<start + 30)
        }
        XCTAssertEqual(covered, Set(tokens.indices))
        XCTAssertNil(tokenizer.tokens(String(repeating: "电", count: 1025)))
        XCTAssertThrowsError(try self.tokenizer(length: 16))
    }
    func testSentenceProjectionKeepsOriginalNormalTextAndAtomicLinks() throws {
        let text = "今天发布了新的开源项目👨‍👩‍👧‍👦。领取优惠请联系推广人员！文档入口：https://example.org/a?x=1。"
        let segments = RGAdFilter.semanticRanges(text)
        let result = try RGAdFilter.project(RGAdInput(text: text), predictions: [RGAdPrediction(range: segments[1], confidence: 0.999)])
        XCTAssertEqual(result.text, "今天发布了新的开源项目👨‍👩‍👧‍👦。文档入口：https://example.org/a?x=1。")
        let link = RGAdEntity(range: RGAdRange(segments[0].lower, segments[1].upper), kind: .link, value: "https://example.org")
        XCTAssertEqual(
            try RGAdFilter.project(
                RGAdInput(text: text, entities: [link]), predictions: [RGAdPrediction(range: segments[1], confidence: 0.999)]
            ).disposition, .keep)
    }
    func testMediaRequiresWholeMessageDecisionAndSurvivingContentVetoesHide() throws {
        let text = "推广内容及联系入口"
        let prediction = RGAdPrediction(range: RGAdRange(0, text.utf16.count), confidence: 0.999)
        let input = RGAdInput(text: text, hasMedia: true)
        XCTAssertEqual(try RGAdFilter.project(input, predictions: [prediction]).disposition, .trim)
        XCTAssertEqual(try RGAdFilter.project(input, predictions: [prediction], entireMessageIsAd: true).disposition, .hide)
        let mixed = RGAdInput(text: text + "\n正常正文必须保留", hasMedia: true)
        let first = RGAdFilter.semanticRanges(mixed.text)[0]
        XCTAssertEqual(
            try RGAdFilter.project(mixed, predictions: [RGAdPrediction(range: first, confidence: 0.999)], entireMessageIsAd: true)
                .disposition, .trim)
        let quoted = RGAdInput(text: text, entities: [RGAdEntity(range: prediction.range, kind: .quote)], hasMedia: true)
        XCTAssertEqual(try RGAdFilter.project(quoted, predictions: [prediction]).disposition, .keep)
        XCTAssertEqual(try RGAdFilter.project(quoted, predictions: [prediction], entireMessageIsAd: true).disposition, .hide)
        let code = RGAdInput(text: text, entities: [RGAdEntity(range: prediction.range, kind: .code)], hasMedia: true)
        XCTAssertEqual(try RGAdFilter.project(code, predictions: [prediction], entireMessageIsAd: true).disposition, .keep)
    }
    func testMissingModelDoesNotInventPredictions() throws {
        let classifier = RGAdSemanticClassifier(resourceDirectory: URL(fileURLWithPath: "/nonexistent-regram-test-model"))
        XCTAssertThrowsError(try classifier.probability("本机检测测试文本"))
        XCTAssertTrue(classifier.predict(RGAdInput(text: "普通内容")).predictions.isEmpty)
    }
    func testBundledCoreMLRecognizesChinesePromotion() throws {
        let classifier = RGAdSemanticClassifier.shared
        let ad = RGAdInput(text: "首充享双倍礼金，在线客服协助开户。")
        let result = classifier.predict(ad)
        XCTAssertTrue(result.completed)
        XCTAssertEqual(try RGAdPolicy.project(ad, semantic: result).disposition, .hide)
    }
    func testOverlappingBareDestinationEntitiesPreserveNormalSharing() throws {
        let classifier = RGAdSemanticClassifier.shared
        XCTAssertTrue(classifier.prepareModel())
        let text = "这是一份正常的开源项目说明。\nhttps://example.org/project\n使用方法和代码仓库都在文档中。"
        let range = (text as NSString).range(of: "https://example.org/project")
        let link = RGAdEntity(range: RGAdRange(range.location, NSMaxRange(range)), kind: .link, value: "https://example.org/project")
        for entities in [[link], [link, link]] {
            let input = RGAdInput(text: text, entities: entities)
            XCTAssertEqual(try RGAdPolicy.project(input, semantic: classifier.predict(input)).text, text)
        }
    }
    func testLinkedDividerOnlyFollowsTheRemovedSponsor() throws {
        let text = "普通正文\n======\n推广段落\n"
        let divider = RGAdRange(5, 11)
        let ad = RGAdRange(12, 17)
        func input(_ target: String) -> RGAdInput {
            RGAdInput(
                text: text,
                entities: [
                    RGAdEntity(range: divider, kind: .link, value: target),
                    RGAdEntity(range: RGAdRange(12, 16), kind: .link, value: "https://example.org/sponsor"),
                ])
        }
        let prediction = RGAdPrediction(range: ad, confidence: 0.999)
        XCTAssertEqual(try RGAdFilter.project(input("https://example.org/sponsor"), predictions: [prediction]).text, "普通正文\n")
        XCTAssertEqual(try RGAdFilter.project(input("https://example.org/contents"), predictions: [prediction]).text, "普通正文\n======\n")
    }
}
