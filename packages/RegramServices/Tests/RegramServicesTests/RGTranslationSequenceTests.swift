import Foundation
import SwiftSignalKit
import XCTest
@testable import RegramServices

final class RGTranslationSequenceTests: XCTestCase {
    private func asynchronous(_ value: String, after interval: Double = 0.01, cancelled: (() -> Void)? = nil) -> Signal<String, TranslateFetchError> {
        Signal { subscriber in
            let disposed = Atomic(value: false)
            DispatchQueue.global().asyncAfter(deadline: .now() + interval) {
                guard !disposed.with({ $0 }) else { return }
                subscriber.putNext(value)
                subscriber.putCompletion()
            }
            return ActionDisposable {
                let _ = disposed.swap(true)
                cancelled?()
            }
        }
    }

    func testProtectedPrefixDoesNotCancelAsynchronousText() {
        let done = expectation(description: "translated body")
        let task = rgTranslateSequentially([.single("@name "), asynchronous("翻译正文")]).start(next: {
            XCTAssertEqual($0, ["@name ", "翻译正文"])
            done.fulfill()
        }, error: { _ in XCTFail("Protected prefix must preserve the active text request") })
        defer { task.dispose() }
        wait(for: [done], timeout: 1)
    }

    func testProtectedLinkBetweenAsynchronousPartsPreservesOrdering() {
        let done = expectation(description: "both translated parts")
        let task = rgTranslateSequentially([asynchronous("阅读 "), .single("https://example.test"), asynchronous(" 现在")]).start(next: {
            XCTAssertEqual($0, ["阅读 ", "https://example.test", " 现在"])
            done.fulfill()
        }, error: { _ in XCTFail("Link must not cancel the following translation") })
        defer { task.dispose() }
        wait(for: [done], timeout: 1)
    }

    func testBlankChunkDoesNotBlockFollowingLongText() {
        let done = expectation(description: "all text chunks")
        let text = String(repeating: "a", count: 9) + "\n\n" + String(repeating: "b", count: 9)
        let task = rgTranslateInChunks(text, "zh", maxLength: 8, { text, _ in self.asynchronous(text.uppercased()) }).start(next: {
            XCTAssertEqual($0, text.uppercased())
            done.fulfill()
        }, error: { _ in XCTFail("Blank chunk must not block the next chunk") })
        defer { task.dispose() }
        wait(for: [done], timeout: 1)
    }

    func testChunksMeasureUTF16AndKeepEmojiAndWhitespace() {
        let emoji = "👨‍👩‍👧‍👦"
        let text = String(repeating: emoji + " 繁體中文\r\n", count: 170)
        let chunks = gtranslateSplitTextBySentences(text, maxChunkLength: 1024)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.utf16.count <= 1024 })
        XCTAssertEqual(chunks.joined(), text)
        XCTAssertTrue(chunks.dropLast().allSatisfy { $0.hasSuffix("\r\n") })
    }

    func testTimeoutRemainsActiveAfterSynchronousPrefix() {
        let done = expectation(description: "text timeout")
        let task = rgTranslateSequentially([.single("@name"), .never()], chunkTimeout: 0.02).start(next: { _ in
            XCTFail("An unfinished text request must not succeed")
        }, error: { error in
            guard case .network = error else { return XCTFail("Unexpected timeout error") }
            done.fulfill()
        })
        defer { task.dispose() }
        wait(for: [done], timeout: 1)
    }

    func testEmptyChunkCompletionFailsInsteadOfLoadingForever() {
        let done = expectation(description: "empty chunk failure")
        let task = rgTranslateSequentially([.single("@name"), .complete()]).start(next: { _ in
            XCTFail("Missing translation must not succeed")
        }, error: { error in
            guard case .network = error else { return XCTFail("Unexpected empty chunk error") }
            done.fulfill()
        })
        defer { task.dispose() }
        wait(for: [done], timeout: 1)
    }

    func testFailureDoesNotStartLaterChunks() {
        let done = expectation(description: "chunk failure")
        let started = Atomic(value: false)
        let later = Signal<String, TranslateFetchError> { subscriber in
            let _ = started.swap(true)
            subscriber.putNext("must not run")
            subscriber.putCompletion()
            return EmptyDisposable
        }
        let task = rgTranslateSequentially([.single("@name"), .fail(.network), later]).start(error: { _ in done.fulfill() })
        defer { task.dispose() }
        wait(for: [done], timeout: 1)
        XCTAssertFalse(started.with({ $0 }))
    }

    func testDisposalCancelsActiveChunkAndDoesNotStartLaterChunks() {
        let started = expectation(description: "body started")
        let cancelled = expectation(description: "body cancelled")
        let laterStarted = Atomic(value: false)
        let body = Signal<String, TranslateFetchError> { _ in
            started.fulfill()
            return ActionDisposable { cancelled.fulfill() }
        }
        let later = Signal<String, TranslateFetchError> { _ in
            let _ = laterStarted.swap(true)
            return EmptyDisposable
        }
        let task = rgTranslateSequentially([.single("@name"), body, later]).start(next: { _ in XCTFail("Cancelled sequence must not succeed") })
        wait(for: [started], timeout: 1)
        task.dispose()
        wait(for: [cancelled], timeout: 1)
        XCTAssertFalse(laterStarted.with({ $0 }))
    }

    func testSynchronousChunksCompleteInOrderWithoutRecursion() {
        let done = expectation(description: "synchronous chunks")
        let expected = (0..<512).map(String.init)
        let task = rgTranslateSequentially(expected.map { .single($0) }).start(next: {
            XCTAssertEqual($0, expected)
            done.fulfill()
        }, error: { _ in XCTFail("Synchronous values must complete") })
        defer { task.dispose() }
        wait(for: [done], timeout: 1)
    }

    func testConcurrentTranslationKeepsOrderAndBoundsParallelism() {
        let queue = Queue()
        let lock = NSLock()
        var running = 0
        var peak = 0
        let signals: [Signal<String, TranslateFetchError>] = (0 ..< 12).map { index in
            Signal { subscriber in
                lock.lock()
                running += 1
                peak = max(peak, running)
                lock.unlock()
                queue.after(Double(12 - index) * 0.003) {
                    lock.lock()
                    running -= 1
                    lock.unlock()
                    subscriber.putNext("译\(index)")
                    subscriber.putCompletion()
                }
                return EmptyDisposable
            }
        }
        let done = expectation(description: "parallel")
        let task = rgTranslateConcurrently(signals, limit: 4).start(next: { values in
            XCTAssertEqual(values, (0 ..< 12).map { "译\($0)" })
            done.fulfill()
        }, error: { _ in XCTFail("Parallel translation must succeed") })
        wait(for: [done], timeout: 2)
        task.dispose()
        XCTAssertEqual(peak, 4)
    }

    func testConcurrentTranslationFailureCancelsRemainingWork() {
        var cancelled = 0
        let lock = NSLock()
        let pending: Signal<String, TranslateFetchError> = Signal { _ in
            ActionDisposable {
                lock.lock()
                cancelled += 1
                lock.unlock()
            }
        }
        let done = expectation(description: "failure")
        let task = rgTranslateConcurrently([pending, .fail(.network), pending], limit: 3).start(next: { _ in
            XCTFail("A failed segment must not produce a result")
        }, error: { _ in done.fulfill() })
        wait(for: [done], timeout: 1)
        task.dispose()
        XCTAssertEqual(cancelled, 1)
    }
}
