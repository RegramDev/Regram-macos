import Foundation
import RegramCore
import SwiftSignalKit
import XCTest
@testable import RegramServices

final class RegramWorkflowTests: XCTestCase {
    private func key(_ accountId: Int64 = 1, _ id: Int32 = 1) -> RegramTranscriptionTaskKey {
        RegramTranscriptionTaskKey(accountId: accountId, messageId: RGBookmarkMessageId(peerId: 2, namespace: 0, id: id))
    }

    func testSpeechTaskSharesWorkAndObserverDisposalDoesNotCancelOtherObserver() {
        let tasks = RegramTranscriptionTasks()
        var starts = 0
        var disposals = 0
        var complete: (() -> Void)?
        let operation: (@escaping () -> Bool) -> Signal<Void, RGTranscriptionError> = { isCurrent in
            Signal { subscriber in
                starts += 1
                complete = { XCTAssertTrue(isCurrent()); subscriber.putNext(()); subscriber.putCompletion() }
                return ActionDisposable { disposals += 1 }
            }
        }
        let first = tasks.perform(key: key(), revision: 1, operation: operation).start()
        var completed = false
        let second = tasks.perform(key: key(), revision: 1, operation: operation).start(completed: { completed = true })
        XCTAssertEqual(starts, 1)
        first.dispose()
        XCTAssertEqual(disposals, 0)
        complete?()
        XCTAssertTrue(completed)
        XCTAssertEqual(tasks.snapshot(key())?.state, .completed)
        XCTAssertEqual(disposals, 1)
        second.dispose()
    }

    func testSpeechCancellationVersionReplacementAndAccountIsolation() {
        let tasks = RegramTranscriptionTasks()
        var currentChecks: [() -> Bool] = []
        let operation: (@escaping () -> Bool) -> Signal<Void, RGTranscriptionError> = { isCurrent in
            currentChecks.append(isCurrent)
            return .never()
        }
        let first = tasks.perform(key: key(), revision: 1, operation: operation).start()
        let replacement = tasks.perform(key: key(), revision: 2, operation: operation).start()
        let other = tasks.perform(key: key(9), revision: 1, operation: operation).start()
        XCTAssertFalse(currentChecks[0]())
        XCTAssertTrue(currentChecks[1]())
        XCTAssertTrue(currentChecks[2]())
        tasks.cancelAccount(1)
        XCTAssertNil(tasks.snapshot(key()))
        XCTAssertFalse(currentChecks[1]())
        XCTAssertEqual(tasks.snapshot(key(9))?.state, .running)
        tasks.cancel(key(9))
        XCTAssertEqual(tasks.snapshot(key(9))?.state, .cancelled)
        XCTAssertFalse(currentChecks[2]())
        first.dispose(); replacement.dispose(); other.dispose()
    }

    func testSleepInvalidatesOldOwnershipAndWakeCreatesFreshAttempt() {
        let tasks = RegramTranscriptionTasks()
        var checks: [() -> Bool] = []
        let subscription = tasks.perform(key: key(), revision: 7) { isCurrent in checks.append(isCurrent); return .never() }.start()
        tasks.suspend()
        XCTAssertEqual(tasks.snapshot(key())?.state, .interrupted)
        XCTAssertFalse(checks[0]())
        tasks.resume()
        XCTAssertEqual(checks.count, 2)
        XCTAssertFalse(checks[0]())
        XCTAssertTrue(checks[1]())
        XCTAssertEqual(tasks.snapshot(key())?.state, .running)
        tasks.cancelAccount(1)
        tasks.resume()
        XCTAssertEqual(checks.count, 2)
        subscription.dispose()
    }

    func testContextStaysWithinChatTopicPrivacyAndCharacterLimits() {
        let long = String(repeating: "👨‍👩‍👧‍👦", count: 900)
        var messages = (0..<8).map { RegramLLMContextMessage(peerId: 1, topicId: 3, text: String($0)) }
        messages += [RegramLLMContextMessage(peerId: 2, topicId: 3, text: "other chat"), RegramLLMContextMessage(peerId: 1, topicId: 4, text: "other topic"), RegramLLMContextMessage(peerId: 1, topicId: 3, text: "protected", isCopyProtected: true), RegramLLMContextMessage(peerId: 1, topicId: 3, text: "secret", isSecret: true), RegramLLMContextMessage(peerId: 1, topicId: 3, text: "one time", isOneTime: true), RegramLLMContextMessage(peerId: 1, topicId: 3, text: long)]
        let result = RegramLLMContextPolicy.bounded(messages, peerId: 1, topicId: 3)
        XCTAssertEqual(Array(result.dropLast()), ["4", "5", "6", "7"])
        XCTAssertEqual(result.last?.count, 800)
    }

    func testOutgoingLanguageRequiresAnExactAccountAndChatKey() {
        var settings = RegramAccountSettings()
        settings["outgoingLanguageTranslation"] = .dictionary(["1:2": "ja", "1:3": "off", "default": "en"])
        XCTAssertEqual(RegramOutgoingTranslationPolicy.language(settings: settings, accountId: 1, peerId: 2), "ja")
        XCTAssertNil(RegramOutgoingTranslationPolicy.language(settings: settings, accountId: 9, peerId: 2))
        XCTAssertNil(RegramOutgoingTranslationPolicy.language(settings: settings, accountId: 1, peerId: 4))
        XCTAssertNil(RegramOutgoingTranslationPolicy.language(settings: settings, accountId: 1, peerId: 3))
        XCTAssertNil(RegramOutgoingTranslationPolicy.language(settings: RegramAccountSettings(), accountId: 1, peerId: 2))
    }

    func testLLMURLsRejectCredentialsInBaseAndAbsoluteEndpoint() {
        for (base, endpoint) in [("https://secret@example.test", ""), ("https://example.test", "https://secret@example.test/v1/messages")] {
            let configuration = RGLLMTranslationConfiguration(format: .openai, baseURL: base, endpoint: endpoint, apiKey: "fixture", model: "model", prompt: "", temperature: 0.2)
            XCTAssertNil(configuration.translationURL)
        }
    }

    func testWebTranslationJavascriptEscapesTextAndRejectsInvalidIndex() {
        let payload = "\"; window.location='https://example.test'; //\n</script>"
        let script = RegramWebTranslationScript.apply(index: 0, translation: payload)
        XCTAssertTrue(script?.contains("\\\"") == true)
        XCTAssertTrue(script?.contains("\\n") == true)
        XCTAssertNil(RegramWebTranslationScript.apply(index: -1, translation: payload))
        XCTAssertTrue(RegramWebTranslationScript.collect.contains("form,textarea,input"))
        XCTAssertTrue(RegramWebTranslationScript.collect.contains("[contenteditable]"))
    }
}
