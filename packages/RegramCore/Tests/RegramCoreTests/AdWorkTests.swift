import XCTest

@testable import RegramCore

@available(macOS 10.15, *)
final class AdWorkTests: XCTestCase {
    func testCancelledPausedWorkReleasesCapturedWindow() {
        final class Window {}
        let queue = DispatchQueue(label: "ad-cancelled-memory-test")
        let scheduler = RGAdWorkScheduler(queue: queue)
        let request = RGAdWorkRequest()
        weak var retained: Window?
        queue.sync {
            scheduler.updateConditions(RGAdWorkConditions(foreground: false))
            let window = Window()
            retained = window
            scheduler.enqueue(
                cancelled: { request.isCancelled },
                step: {
                    _ = window
                    return false
                }, onCancel: {})
        }
        XCTAssertNotNil(retained)
        request.cancel()
        queue.sync { scheduler.discardCancelled() }
        XCTAssertNil(retained)
    }

    func testPinnedPriorityAdvancesWithoutStarvingOlderPreviews() {
        let queue = DispatchQueue(label: "ad-priority-test")
        let scheduler = RGAdWorkScheduler(queue: queue)
        let done = expectation(description: "all priorities finish")
        done.expectedFulfillmentCount = 3
        var visits: [Int] = []
        queue.async {
            for priority in [0, 1, 2] {
                var count = 0
                scheduler.enqueue(
                    priority: priority, cancelled: { false },
                    step: {
                        visits.append(priority)
                        count += 1
                        if count == 8 {
                            done.fulfill()
                            return true
                        }
                        return false
                    }, onCancel: { XCTFail("unexpected cancellation") })
            }
        }
        wait(for: [done], timeout: 3)
        queue.sync {
            XCTAssertEqual(visits.first, 2)
            XCTAssertLessThanOrEqual(try! XCTUnwrap(visits.firstIndex(of: 0)), 3)
            XCTAssertEqual(visits.filter { $0 == 0 }.count, 8)
            XCTAssertEqual(visits.filter { $0 == 1 }.count, 8)
            XCTAssertEqual(visits.filter { $0 == 2 }.count, 8)
        }
    }

    func testSharedBudgetAndFairProgressAcrossLists() {
        let queue = DispatchQueue(label: "ad-work-test")
        let scheduler = RGAdWorkScheduler(queue: queue)
        let done = expectation(description: "both lists finish")
        done.expectedFulfillmentCount = 2
        var visits: [Int] = []
        var starts: [TimeInterval] = []
        queue.async {
            for id in [1, 2] {
                var count = 0
                scheduler.enqueue(
                    cancelled: { false },
                    step: {
                        starts.append(ProcessInfo.processInfo.systemUptime)
                        visits.append(id)
                        Thread.sleep(forTimeInterval: 0.02)
                        count += 1
                        if count == 2 {
                            done.fulfill()
                            return true
                        }
                        return false
                    }, onCancel: { XCTFail("unexpected cancellation") })
            }
        }
        wait(for: [done], timeout: 3)
        queue.sync {
            XCTAssertEqual(visits, [1, 2, 1, 2])
            for index in 1..<starts.count { XCTAssertGreaterThanOrEqual(starts[index] - starts[index - 1], 0.035) }
        }
    }

    func testBackgroundAndCriticalHeatPauseThenResumeWithoutDroppingWork() {
        let queue = DispatchQueue(label: "ad-pause-test")
        let scheduler = RGAdWorkScheduler(queue: queue)
        let done = expectation(description: "resumed")
        var count = 0
        queue.sync {
            scheduler.updateConditions(RGAdWorkConditions(foreground: false))
            scheduler.enqueue(
                cancelled: { false },
                step: {
                    count += 1
                    done.fulfill()
                    return true
                }, onCancel: { XCTFail() })
        }
        Thread.sleep(forTimeInterval: 0.04)
        queue.sync {
            XCTAssertEqual(count, 0)
            scheduler.updateConditions(RGAdWorkConditions(thermal: 3))
        }
        Thread.sleep(forTimeInterval: 0.04)
        queue.sync {
            XCTAssertEqual(count, 0)
            scheduler.updateConditions(RGAdWorkConditions(lowPower: true, thermal: 2))
        }
        wait(for: [done], timeout: 2)
        queue.sync { XCTAssertEqual(count, 1) }
    }

    func testCancelledWorkNeverRunsAndPowerModesOnlyChangeScheduling() {
        let queue = DispatchQueue(label: "ad-cancel-test")
        let request = RGAdWorkRequest()
        let scheduler = RGAdWorkScheduler(queue: queue)
        let cancelled = expectation(description: "cancelled")
        request.cancel()
        queue.async {
            scheduler.enqueue(
                cancelled: { request.isCancelled },
                step: {
                    XCTFail("obsolete inference ran")
                    return true
                }, onCancel: { cancelled.fulfill() })
        }
        wait(for: [cancelled], timeout: 2)
        XCTAssertEqual(RGAdWorkConditions().recoveryDelay(workDuration: 0.1), 0.1, accuracy: 0.001)
        XCTAssertEqual(RGAdWorkConditions(lowPower: true).recoveryDelay(workDuration: 0.1), 0.3, accuracy: 0.001)
        XCTAssertEqual(RGAdWorkConditions(thermal: 2).recoveryDelay(workDuration: 0.1), 0.7, accuracy: 0.001)
    }

    func testReplacingPausedWorkReleasesCancelledJobsBeforeForegrounding() {
        let queue = DispatchQueue(label: "ad-paused-cancel-test")
        let scheduler = RGAdWorkScheduler(queue: queue)
        let request = RGAdWorkRequest()
        var cancelled = 0
        var completed = 0
        let done = expectation(description: "only current work resumes")
        queue.sync {
            scheduler.updateConditions(RGAdWorkConditions(foreground: false))
            scheduler.enqueue(
                cancelled: { request.isCancelled },
                step: {
                    XCTFail()
                    return true
                }, onCancel: { cancelled += 1 })
            request.cancel()
            scheduler.enqueue(
                cancelled: { false },
                step: {
                    completed += 1
                    done.fulfill()
                    return true
                }, onCancel: { XCTFail() })
            XCTAssertEqual(cancelled, 1)
            XCTAssertEqual(completed, 0)
            scheduler.updateConditions(RGAdWorkConditions())
        }
        wait(for: [done], timeout: 2)
        queue.sync { XCTAssertEqual(completed, 1) }
    }

    func testFinalRuleAndReviewedKeepAvoidInferenceButMixedTextStillUsesModel() throws {
        let knowledge = RGAdPolicy.Knowledge()
        var calls = 0
        func classify(_ input: RGAdInput) -> RGAdSemanticResult {
            calls += 1
            return RGAdSemanticResult()
        }
        XCTAssertEqual(try knowledge.resolve(RGAdInput(text: "套餐说明\n\n#ad"), classify: classify).disposition, .hide)
        XCTAssertEqual(calls, 0)
        _ = try knowledge.resolve(RGAdInput(text: "正常讨论"), classify: classify)
        _ = try knowledge.resolve(RGAdInput(text: "正常内容\n\n#推广 套餐介绍\n\n正常结尾"), classify: classify)
        XCTAssertEqual(calls, 2)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RGAdSampleStore(accountDirectory: directory)
        let input = RGAdInput(text: "这是用户确认保留的示例\n#ad", peerId: 1)
        let sample = try store.draft(input: input, messageKey: "1", mediaKinds: [], mediaIdentity: "")
        try store.save(sample)
        let reviewed = RGAdPolicy.Knowledge(samples: try store.load())
        XCTAssertEqual(try reviewed.resolve(input, sourceGroup: sample.sourceGroup, classify: classify).disposition, .keep)
        XCTAssertEqual(calls, 2)
    }

    func testLeadingTopicsCannotStrandAnExplicitAdvertisingCard() throws {
        let input = RGAdInput(text: "#服务商 #网络\n#AnyTLS\n官网及优惠套餐介绍\n\n#AD 10-20", hasMedia: true)
        XCTAssertEqual(try RGAdPolicy.project(input).disposition, .hide)
    }

    func testExplicitAdvertisingMetadataScopesItsSectionButNotQuotedExamples() throws {
        let input = RGAdInput(text: "套餐介绍与办理说明\n\n🗒 标签: #广告\n📢 频道: @example\n\n收藏频道获取更新", hasMedia: true)
        XCTAssertEqual(try RGAdPolicy.project(input).disposition, .hide)
        let normal = "这段是教程中的标签示例。\n\n标签: #广告\n\n请勿删除正常说明。"
        let range = (normal as NSString).range(of: "标签: #广告")
        let quoted = RGAdInput(text: normal, entities: [RGAdEntity(range: RGAdRange(range.location, NSMaxRange(range)), kind: .quote)])
        XCTAssertEqual(try RGAdPolicy.project(quoted).disposition, .keep)
        XCTAssertEqual(try RGAdPolicy.project(RGAdInput(text: "使用说明\n标签: #短信 #广告 #拦截\n配置方法如下")).disposition, .keep)
    }

    func testUnavailableModelDoesNotReturnACompletedNormalVerdict() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let classifier = RGAdSemanticClassifier(resourceDirectory: directory)
        XCTAssertFalse(classifier.predict(RGAdInput(text: "这是一次需要语义识别的消息")).completed)
        XCTAssertFalse(classifier.prepareModel())
        XCTAssertFalse(classifier.predict(RGAdInput(text: "模型暂时不可用时应该允许后续重试")).completed)
    }

    func testDisclosedMonospaceProseNeedsSemanticWholeCardAndNeverOverridesActualCode() throws {
        let heading = "产品体验招募\n> 品牌 in #推广\n\n"
        let body = "提供旅行上网服务，欢迎体验我们的产品。\n多种手机兼容，提供售后支持，联系选购。"
        func input(_ prefix: String, _ text: String) -> RGAdInput {
            RGAdInput(
                text: prefix + text, entities: [RGAdEntity(range: RGAdRange(prefix.utf16.count, (prefix + text).utf16.count), kind: .code)])
        }
        func verdict(_ value: RGAdInput) throws -> RGAdProjection {
            try RGAdPolicy.project(
                value,
                semantic: RGAdSemanticResult(
                    predictions: [RGAdPrediction(range: RGAdRange(0, value.text.utf16.count), confidence: 0.999)], threshold: 0.99,
                    entireMessage: true))
        }
        let prose = input(heading, body)
        XCTAssertNotEqual(try RGAdPolicy.project(prose).disposition, .hide)
        XCTAssertEqual(try verdict(prose).disposition, .hide)
        let code = input(heading, "let example = { \"这是用于展示语法的中文代码示例，不能自动删除\" }")
        XCTAssertNotEqual(try verdict(code).disposition, .hide)
        XCTAssertNotEqual(try verdict(input("这是一段引用示例，用于排查过滤误判。\n\n", body)).disposition, .hide)
    }

    func testCommercialQuotePermissionRequiresACompleteStrongPredictionAndStillProtectsCode() throws {
        let prefix = "正常说明\n\n"
        let quote = "广告段落第一行\n广告段落第二行\n"
        let suffix = "\n正常结尾"
        let range = RGAdRange(prefix.utf16.count, prefix.utf16.count + quote.utf16.count)
        let input = RGAdInput(text: prefix + quote + suffix, entities: [RGAdEntity(range: range, kind: .quote)])
        let strong = [RGAdPrediction(range: range, confidence: 0.999)]
        XCTAssertEqual(try RGAdFilter.project(input, predictions: strong).disposition, .keep)
        XCTAssertEqual(try RGAdFilter.project(input, predictions: strong, promotionalQuoteRanges: [range]).text, prefix + suffix)
        XCTAssertEqual(
            try RGAdFilter.project(
                input, predictions: [RGAdPrediction(range: range, confidence: 0.98)], threshold: 0.97, promotionalQuoteRanges: [range]
            ).disposition, .keep)
        XCTAssertEqual(try RGAdFilter.project(input, promotionalQuoteRanges: [range]).disposition, .keep)
        let code = RGAdInput(text: input.text, entities: input.entities + [RGAdEntity(range: range, kind: .code)])
        XCTAssertEqual(try RGAdFilter.project(code, predictions: strong, promotionalQuoteRanges: [range]).disposition, .keep)
    }
}
