import XCTest

@testable import RegramCore

@available(macOS 10.15, *)
final class AdPersistenceTests: XCTestCase {
    private func account() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func cache(_ root: URL, namespace: String = "model-v1", salt: String = "account-a", now: @escaping () -> Double = { 1000 })
        -> RGAdSemanticCache
    {
        let value = RGAdSemanticCache(accountDirectory: root, namespace: namespace, salt: salt, now: now)
        value.load()
        return value
    }
    private func cacheFile(_ root: URL) -> URL { root.appendingPathComponent("regram-ad-cache-v1/verdicts.json") }

    func testCompletedResultsSurviveRestartWithoutPersistingMessageContents() throws {
        let root = try account()
        let value = cache(root)
        let input = RGAdInput(
            text: "正常👋\n广告", peerId: 9876543210,
            buttons: [[RGAdButton(id: "0:0", title: "广告入口", target: "https://example.org/private")]])
        let result = RGAdSemanticResult(
            predictions: [RGAdPrediction(range: RGAdRange(5, 7), confidence: 0.999)], buttonIds: ["0:0"], threshold: 0.99)
        value.insert(result, for: value.key(for: input), input: input)
        value.takeWriter()?()
        let reopened = cache(root)
        XCTAssertEqual(reopened.result(for: reopened.key(for: input), input: input), result)
        let envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: cacheFile(root))) as! [String: Any]
        let payload = String(decoding: Data(base64Encoded: envelope["payload"] as! String)!, as: UTF8.self)
        for forbidden in [input.text, "private", "peerId", "9876543210", "account-a"] { XCTAssertFalse(payload.contains(forbidden)) }
        let changed = RGAdInput(text: input.text + "这是修改后的正常内容", peerId: input.peerId, buttons: input.buttons)
        XCTAssertNil(reopened.result(for: reopened.key(for: changed), input: changed))
        let linkChanged = RGAdInput(
            text: input.text, peerId: input.peerId,
            buttons: [[RGAdButton(id: "0:0", title: "广告入口", target: "https://example.org/other")]])
        XCTAssertNil(reopened.result(for: reopened.key(for: linkChanged), input: linkChanged))
    }

    func testNamespaceAccountAndExpiryInvalidateResults() throws {
        let root = try account()
        let input = RGAdInput(text: "正常消息", peerId: 9)
        let value = cache(root)
        value.insert(RGAdSemanticResult(), for: value.key(for: input), input: input)
        value.takeWriter()?()
        for other in [
            cache(root, namespace: "model-v2"), cache(root, salt: "account-b"), cache(root, now: { 1000 + 7 * 86400 + 1 }),
            cache(root, now: { 1 }),
        ] {
            XCTAssertNil(other.result(for: other.key(for: input), input: input))
        }
        XCTAssertNotNil(cache(root).result(for: value.key(for: input), input: input))
    }

    func testIncompleteAndMalformedPredictionsNeverBecomePersistedNormalOrAd() throws {
        let value = cache(try account())
        let input = RGAdInput(text: "正文👋")
        let key = value.key(for: input)
        for result in [
            RGAdSemanticResult(completed: false), RGAdSemanticResult(entireMessage: true),
            RGAdSemanticResult(buttonIds: ["missing"]),
            RGAdSemanticResult(predictions: [RGAdPrediction(range: RGAdRange(2, 3), confidence: 1)]),
            RGAdSemanticResult(predictions: [RGAdPrediction(range: RGAdRange(0, 4), confidence: .infinity)]),
        ] {
            value.insert(result, for: key, input: input)
            XCTAssertNil(value.result(for: key, input: input))
        }
        XCTAssertEqual(value.count, 0)
        XCTAssertNil(value.takeWriter())
    }

    func testCorruptCacheFallsBackToMissWithoutTouchingOtherAccountData() throws {
        let root = try account()
        let value = cache(root)
        let input = RGAdInput(text: "这是一条完整的普通消息")
        value.insert(RGAdSemanticResult(), for: value.key(for: input), input: input)
        value.takeWriter()?()
        let file = cacheFile(root)
        var envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        envelope["checksum"] = "broken"
        try JSONSerialization.data(withJSONObject: envelope).write(to: file, options: .atomic)
        XCTAssertEqual(cache(root).count, 0)
        try Data("not json".utf8).write(to: file, options: .atomic)
        XCTAssertEqual(cache(root).count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testCacheIsBoundedAndQueuedWriterCannotRecreateDeletedAccount() throws {
        let root = try account()
        let value = cache(root)
        for index in 0..<1300 {
            let input = RGAdInput(text: "消息 \(index)")
            value.insert(RGAdSemanticResult(), for: value.key(for: input), input: input)
        }
        XCTAssertEqual(value.count, 1024)
        XCTAssertLessThanOrEqual(value.estimatedMemoryCost, 512 * 1024)
        let writer = try XCTUnwrap(value.takeWriter())
        try FileManager.default.removeItem(at: root)
        writer()
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testBundleIdentityChangesWithManifestAndRequiresModelResources() throws {
        let root = try account()
        func manifest(_ threshold: Double) throws {
            try JSONSerialization.data(withJSONObject: [
                "version": 1, "modelSHA256": String(repeating: "a", count: 64), "vocabularySHA256": String(repeating: "b", count: 64),
                "threshold": threshold,
            ]).write(to: root.appendingPathComponent("RGAdModel.json"), options: .atomic)
        }
        try manifest(0.99)
        XCTAssertNil(RGAdSemanticCache.bundledNamespace(resourceDirectory: root))
        try Data().write(to: root.appendingPathComponent("RGAdVocabulary.txt"))
        try Data().write(to: root.appendingPathComponent("ReSieve.mlmodel"))
        let first = try XCTUnwrap(RGAdSemanticCache.bundledNamespace(resourceDirectory: root))
        try manifest(0.98)
        XCTAssertNotEqual(first, RGAdSemanticCache.bundledNamespace(resourceDirectory: root))
    }

    private func pending(_ store: RGAdSampleStore, key: String) throws -> RGAdSample {
        let input = RGAdInput(text: "商业套餐 \(key)\n#ad", peerId: 9)
        try store.recordDetection(input: input, messageKey: key, mediaKinds: [], mediaIdentity: "", projection: RGAdPolicy.project(input))
        return try store.draft(input: input, messageKey: key, mediaKinds: [], mediaIdentity: "")
    }
    private func atomicReview(_ sample: RGAdSample, store: RGAdSampleStore) throws {
        var sample = sample
        sample.reviewedAt = Date().timeIntervalSince1970
        sample.spans = []
        try JSONEncoder().encode(sample).write(to: store.directory.appendingPathComponent(sample.id + ".json"), options: .atomic)
    }

    func testReviewedStartupSkipsPendingBodiesButLibraryStillReportsTheirCorruption() throws {
        let root = try account()
        let store = RGAdSampleStore(accountDirectory: root)
        let ad = try pending(store, key: "pending")
        let review = try pending(store, key: "reviewed")
        try store.save(review)
        _ = try store.load(reviewedOnly: true)
        try Data("broken".utf8).write(to: store.directory.appendingPathComponent(ad.id + ".json"))
        let reopened = RGAdSampleStore(accountDirectory: root)
        XCTAssertEqual(try reopened.load(reviewedOnly: true).map(\.id), [review.id])
        XCTAssertThrowsError(try reopened.load())
    }

    func testAtomicExternalReviewInvalidatesIndexIncludingAnAlreadyLiveWriter() throws {
        let root = try account()
        let store = RGAdSampleStore(accountDirectory: root)
        let ad = try pending(store, key: "initial")
        XCTAssertTrue(try store.load(reviewedOnly: true).isEmpty)
        try atomicReview(ad, store: store)
        _ = try pending(store, key: "after-external-review")
        let reopened = RGAdSampleStore(accountDirectory: root)
        XCTAssertEqual(try reopened.load(reviewedOnly: true).map(\.id), [ad.id])
        try reopened.remove(ad)
        XCTAssertTrue(try RGAdSampleStore(accountDirectory: root).load(reviewedOnly: true).isEmpty)
    }

    func testDamagedIndexRebuildsFromOriginalReviewsAndNeverRewritesThem() throws {
        let root = try account()
        let store = RGAdSampleStore(accountDirectory: root)
        let ad = try pending(store, key: "review")
        try store.save(ad)
        let original = store.directory.appendingPathComponent(ad.id + ".json")
        let bytes = try Data(contentsOf: original)
        let index = store.directory.appendingPathComponent("index/reviewed-v1.json")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: index)) as! [String: Any]
        object["ids"] = [String]()
        try JSONSerialization.data(withJSONObject: object).write(to: index, options: .atomic)
        let reopened = RGAdSampleStore(accountDirectory: root)
        XCTAssertEqual(try reopened.load(reviewedOnly: true).map(\.id), [ad.id])
        XCTAssertEqual(try Data(contentsOf: original), bytes)
        try FileManager.default.removeItem(at: index)
        XCTAssertEqual(try reopened.load(reviewedOnly: true).map(\.id), [ad.id])
    }

    func testRemovalDoesNotDependOnOtherPendingRecordsBeingReadable() throws {
        let root = try account()
        let store = RGAdSampleStore(accountDirectory: root)
        let damaged = try pending(store, key: "damaged")
        let removable = try pending(store, key: "removable")
        let damagedFile = store.directory.appendingPathComponent(damaged.id + ".json")
        try Data("broken".utf8).write(to: damagedFile, options: .atomic)
        let reopened = RGAdSampleStore(accountDirectory: root)
        XCTAssertNoThrow(try reopened.remove(removable))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent(removable.id + ".json").path))
        XCTAssertEqual(try Data(contentsOf: damagedFile), Data("broken".utf8))
        XCTAssertThrowsError(try reopened.load())
    }
}
