import Foundation
import XCTest

final class RichDraftStoreTests: XCTestCase {
    private let key = ChatRichTextDraftKey(accountId: 1, peerId: 2, threadId: nil, isWelcome: false)

    func testEmptyDraftMutationCycleCannotReviveCapturedRevision() {
        let store = ChatRichTextDraftStore<Int>()
        let revision = store.captureRevision(for: key)
        XCTAssertFalse(store.set(nil, for: key))
        XCTAssertTrue(revision.isValid)
        XCTAssertTrue(store.set(1, for: key))
        XCTAssertTrue(store.set(nil, for: key))
        XCTAssertNil(store.value(for: key))
        XCTAssertFalse(revision.isValid)
    }

    func testAllObserversInvalidateOnlyForChangedKey() {
        let store = ChatRichTextDraftStore<Int>()
        let first = store.captureRevision(for: key)
        let second = store.captureRevision(for: key)
        let otherKey = ChatRichTextDraftKey(accountId: 9, peerId: 2, threadId: nil, isWelcome: false)
        let other = store.captureRevision(for: otherKey)
        store.set(1, for: key)
        XCTAssertFalse(first.isValid)
        XCTAssertFalse(second.isValid)
        XCTAssertTrue(other.isValid)
        XCTAssertNil(store.value(for: otherKey))
    }

    func testUnchangedValueKeepsObserversValid() {
        let store = ChatRichTextDraftStore<Int>()
        store.set(1, for: key)
        let revision = store.captureRevision(for: key)
        XCTAssertFalse(store.set(1, for: key))
        XCTAssertTrue(revision.isValid)
    }

    func testDraftStoreDoesNotRetainFinishedActionRevision() {
        let store = ChatRichTextDraftStore<Int>()
        var revision: ChatRichTextDraftRevision? = store.captureRevision(for: key)
        weak var observed = revision
        XCTAssertNotNil(observed)
        revision = nil
        XCTAssertNil(observed)
        let next = store.captureRevision(for: key)
        store.set(1, for: key)
        XCTAssertFalse(next.isValid)
    }

    func testMissingThreadAndZeroThreadAreDistinct() {
        let store = ChatRichTextDraftStore<Int>()
        let zeroThread = ChatRichTextDraftKey(accountId: 1, peerId: 2, threadId: 0, isWelcome: false)
        store.set(1, for: key)
        store.set(2, for: zeroThread)
        XCTAssertEqual(store.value(for: key), 1)
        XCTAssertEqual(store.value(for: zeroThread), 2)
    }

    func testAccountChatTopicAndCustomEditorsKeepSeparateDrafts() {
        let keys = [
            key,
            ChatRichTextDraftKey(accountId: 3, peerId: 2, threadId: nil, isWelcome: false),
            ChatRichTextDraftKey(accountId: 1, peerId: 4, threadId: nil, isWelcome: false),
            ChatRichTextDraftKey(accountId: 1, peerId: 2, threadId: 5, isWelcome: false),
            ChatRichTextDraftKey(accountId: 1, peerId: 2, threadId: nil, isWelcome: true, isCustomEditor: true),
            ChatRichTextDraftKey(accountId: 1, peerId: 2, threadId: nil, isWelcome: false, isCustomEditor: true)
        ]
        let store = ChatRichTextDraftStore<Int>()
        for (index, key) in keys.enumerated() {
            store.set(index, for: key)
        }
        for (index, key) in keys.enumerated() {
            XCTAssertEqual(store.value(for: key), index)
        }
        store.set(nil, for: key)
        XCTAssertNil(store.value(for: key))
        for (index, key) in keys.enumerated().dropFirst() {
            XCTAssertEqual(store.value(for: key), index)
        }
    }

    func testNewObservationAfterMutationDoesNotReviveOldObservation() {
        let store = ChatRichTextDraftStore<Int>()
        let old = store.captureRevision(for: key)
        store.set(1, for: key)
        let current = store.captureRevision(for: key)
        XCTAssertFalse(old.isValid)
        XCTAssertTrue(current.isValid)
        store.set(2, for: key)
        XCTAssertFalse(current.isValid)
    }

    func testConcurrentWritesInvalidateObservedRevision() {
        let store = ChatRichTextDraftStore<Int>()
        let revision = store.captureRevision(for: key)
        DispatchQueue.concurrentPerform(iterations: 64) { value in store.set(value, for: self.key) }
        XCTAssertFalse(revision.isValid)
        store.set(99, for: key)
        XCTAssertEqual(store.value(for: key), 99)
    }
}
