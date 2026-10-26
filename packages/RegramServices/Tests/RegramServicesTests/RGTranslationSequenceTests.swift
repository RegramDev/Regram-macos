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
            XCTAssertTrue($0.contains("AAAAAAAA"))
            XCTAssertTrue($0.contains("BBBBBBBB"))
            XCTAssertTrue($0.contains("\n\n"))
            done.fulfill()
        }, error: { _ in XCTFail("Blank chunk must not block the next chunk") })
        defer { task.dispose() }
        wait(for: [done], timeout: 1)
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
}
