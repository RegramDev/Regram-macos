import RegramCore
import SwiftSignalKit
import XCTest
@testable import RegramServices

final class RegramChatTranslationPolicyTests: XCTestCase {
    func testEverySelectedProviderKeepsItsIdentityForBothSubscriptionStates() {
        for provider in RegramChatTranslationPolicy.Provider.allCases {
            var settings = RegramAccountSettings()
            settings["translationBackend"] = .string(provider.rawValue)
            for premium in [true, false] {
                XCTAssertTrue(RegramChatTranslationPolicy.usesTextRequests(settings: settings, hasTelegramPremium: premium))
                XCTAssertEqual(RegramChatTranslationPolicy.provider(settings: settings), provider)
                XCTAssertEqual(RegramChatTranslationPolicy.textRequestSettings(settings).translationIdentity, settings.translationIdentity)
            }
        }
    }

    func testTelegramSelectionInvokesOnlyTheExplicitTextAdapter() {
        let done = expectation(description: "Telegram text provider")
        var requests: [(String, String)] = []
        let task = regramExternalTranslate(text: "hello", to: "zh-TW", accountId: 1, settings: RegramAccountSettings(), telegramTranslate: { text, target in
            requests.append((text, target))
            return .single("你好")
        }).start(next: { result in
            XCTAssertEqual(result, "你好")
            done.fulfill()
        }, error: { _ in XCTFail("Explicit Telegram text adapter should succeed") })
        defer { task.dispose() }
        wait(for: [done], timeout: 1)
        XCTAssertEqual(requests.map(\.0), ["hello"])
        XCTAssertEqual(requests.map(\.1), ["zh-TW"])
    }

    func testTelegramSelectionWithoutTextAdapterFailsWithoutFallback() {
        let done = expectation(description: "missing Telegram adapter")
        let task = regramExternalTranslate(text: "hello", to: "zh", accountId: 1, settings: RegramAccountSettings()).start(next: { _ in
            XCTFail("Missing adapter must not invoke a replacement provider")
        }, error: { error in
            guard case .network = error else { return XCTFail("Unexpected error") }
            done.fulfill()
        })
        defer { task.dispose() }
        wait(for: [done], timeout: 1)
    }

    func testTelegramProviderErrorIsReturnedWithoutRetryingAnotherEngine() {
        let done = expectation(description: "provider failure")
        var requests = 0
        let task = regramExternalTranslate(text: "hello", to: "zh", accountId: 1, settings: RegramAccountSettings(), telegramTranslate: { _, _ in
            requests += 1
            return .fail(.network)
        }).start(next: { _ in XCTFail("Failed provider must not return another engine's result") }, error: { error in
            guard case .network = error else { return XCTFail("Unexpected error") }
            done.fulfill()
        })
        defer { task.dispose() }
        wait(for: [done], timeout: 1)
        XCTAssertEqual(requests, 1)
    }

    func testAuthorizationBlocksTheProviderBeforeSendingText() {
        let done = expectation(description: "protected request")
        var invoked = false
        let task = regramExternalTranslate(text: "private text", to: "zh", accountId: 1, settings: RegramAccountSettings(), permitsNetworkFallback: { .single(false) }, telegramTranslate: { _, _ in
            invoked = true
            return .single("must not run")
        }).start(next: { _ in XCTFail("Unauthorized text must not leave the device") }, error: { error in
            guard case .outdated = error else { return XCTFail("Unexpected error") }
            done.fulfill()
        })
        defer { task.dispose() }
        wait(for: [done], timeout: 1)
        XCTAssertFalse(invoked)
    }

    func testDisposingTheRequestCancelsTheSelectedAdapter() {
        var cancelled = false
        let task = regramExternalTranslate(text: "hello", to: "zh", accountId: 1, settings: RegramAccountSettings(), telegramTranslate: { _, _ in
            Signal { _ in ActionDisposable { cancelled = true } }
        }).start()
        XCTAssertFalse(cancelled)
        task.dispose()
        XCTAssertTrue(cancelled)
    }

    func testProtectedTranslationKeepsLinksWhileUsingTheSelectedAdapter() {
        let done = expectation(description: "protected selected provider")
        var requests: [String] = []
        let task = regramProtectedTranslation(text: "Read https://example.test/a?q=1 now", to: "zh", accountId: 1, settings: RegramAccountSettings(), ranges: [], protectedIds: [], telegramTranslate: { text, _ in
            requests.append(text)
            return .single(text.replacingOccurrences(of: "Read", with: "阅读").replacingOccurrences(of: "now", with: "现在"))
        }).start(next: { result in
            XCTAssertEqual(result.text, "阅读 https://example.test/a?q=1 现在")
            done.fulfill()
        }, error: { _ in XCTFail("Protected translation should use the selected adapter") })
        defer { task.dispose() }
        wait(for: [done], timeout: 1)
        XCTAssertFalse(requests.isEmpty)
        XCTAssertTrue(requests.allSatisfy { !$0.contains("https://example.test") })
    }

    func testUnknownStoredProviderFailsInsteadOfSelectingTelegram() {
        let done = expectation(description: "unknown provider")
        let settings = RegramAccountSettings(values: ["translationBackend": .string("unknown")])
        XCTAssertNil(RegramChatTranslationPolicy.provider(settings: settings))
        var invoked = false
        let task = regramExternalTranslate(text: "hello", to: "zh", accountId: 1, settings: settings, telegramTranslate: { _, _ in
            invoked = true
            return .single("must not run")
        }).start(next: { _ in XCTFail("Unknown provider must not fall back") }, error: { error in
            guard case .network = error else { return XCTFail("Unexpected error") }
            done.fulfill()
        })
        defer { task.dispose() }
        wait(for: [done], timeout: 1)
        XCTAssertFalse(invoked)
    }
}
