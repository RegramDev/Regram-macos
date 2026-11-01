import Foundation
import XCTest
import SwiftSignalKit

enum LAPolicy: Equatable {
    case deviceOwnerAuthenticationWithBiometrics
}

final class LAContext {
    static let created = Atomic(value: [LAContext]())
    var localizedReason = ""
    var localizedFallbackTitle: String?
    var touchIDAuthenticationAllowableReuseDuration: TimeInterval = 10
    var policy: LAPolicy?
    var evaluatedReason: String?
    let invalidated = Atomic(value: false)
    private let reply = Atomic<((Bool, Error?) -> Void)?>(value: nil)

    init() {
        _ = Self.created.modify { $0 + [self] }
    }

    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping (Bool, Error?) -> Void) {
        self.policy = policy
        self.evaluatedReason = localizedReason
        _ = self.reply.swap(reply)
    }

    func complete(success: Bool) {
        reply.swap(nil)?(success, nil)
    }

    func invalidate() {
        _ = invalidated.swap(true)
    }
}

struct TestStrings {
    let walletBiometricsConfirmAccess = "Confirm wallet access"
}

func strings() -> TestStrings {
    return TestStrings()
}

final class TestSession {
    let invalidated = Atomic(value: false)

    func invalidate() {
        _ = invalidated.swap(true)
    }
}

struct KeychainCall {
    let namespace: String
    let lifetime: Int
    let context: LAContext
    let onMainThread: Bool
    let contextInvalidated: Bool
}

struct KeychainState {
    var calls: [KeychainCall] = []
    var fail = false
    let result = TestSession()
}

let keychain = Atomic(value: KeychainState())

func authenticateWalletBiometrics(namespace: String, lifetime: Int, context: LAContext) throws -> TestSession {
    let state = keychain.modify { current in
        var current = current
        current.calls.append(KeychainCall(namespace: namespace, lifetime: lifetime, context: context, onMainThread: Thread.isMainThread, contextInvalidated: context.invalidated.with { $0 }))
        return current
    }
    if state.fail {
        throw NSError(domain: "WalletBiometricFixture", code: 1)
    }
    return state.result
}

final class WalletBiometricTests: XCTestCase {
    override func setUp() {
        super.setUp()
        _ = LAContext.created.swap([])
        _ = keychain.swap(KeychainState())
    }

    func testDisabledBiometricsDoesNotCreateAnAuthenticationContext() {
        XCTAssertNil(makeAuthentication(biometrics: false, namespace: "regram-wallet", lifetime: 30, session: Atomic(value: nil)))
        XCTAssertTrue(LAContext.created.with { $0.isEmpty })
        XCTAssertTrue(keychain.with { $0.calls.isEmpty })
    }

    func testExplicitConfirmationPrecedesCredentialAccessAndDisablesReuse() throws {
        let old = TestSession()
        let session = Atomic<TestSession?>(value: old)
        let done = expectation(description: "cancelled")
        let authenticate = try XCTUnwrap(makeAuthentication(biometrics: true, namespace: "regram-wallet", lifetime: 30, session: session))
        authenticate { result in
            guard case .cancelled = result else { return XCTFail("expected cancellation") }
            done.fulfill()
        }
        let context = try XCTUnwrap(LAContext.created.with { $0.first })
        XCTAssertEqual(context.policy, .deviceOwnerAuthenticationWithBiometrics)
        XCTAssertEqual(context.localizedReason, strings().walletBiometricsConfirmAccess)
        XCTAssertEqual(context.evaluatedReason, context.localizedReason)
        XCTAssertEqual(context.localizedFallbackTitle, "")
        XCTAssertEqual(context.touchIDAuthenticationAllowableReuseDuration, 0)
        XCTAssertTrue(keychain.with { $0.calls.isEmpty })
        XCTAssertTrue(session.with { $0 === old })
        XCTAssertFalse(old.invalidated.with { $0 })
        context.complete(success: false)
        wait(for: [done], timeout: 2)
    }

    private func complete(success: Bool, keychainFails: Bool = false, backgroundReply: Bool = false, file: StaticString = #filePath, line: UInt = #line) throws {
        _ = keychain.modify { state in
            var state = state
            state.fail = keychainFails
            return state
        }
        let old = TestSession()
        let session = Atomic<TestSession?>(value: old)
        let done = expectation(description: "completion on main thread")
        let authenticate = try XCTUnwrap(makeAuthentication(biometrics: true, namespace: "regram-wallet", lifetime: 30, session: session))
        var completions = 0
        authenticate { result in
            XCTAssertTrue(Thread.isMainThread, file: file, line: line)
            completions += 1
            if success && !keychainFails {
                guard case .authorized = result else { return XCTFail("expected authorization", file: file, line: line) }
            } else {
                guard case .cancelled = result else { return XCTFail("expected cancellation", file: file, line: line) }
            }
            done.fulfill()
        }
        let context = try XCTUnwrap(LAContext.created.with { $0.first })
        if backgroundReply {
            DispatchQueue.global().async { context.complete(success: success) }
        } else {
            context.complete(success: success)
        }
        wait(for: [done], timeout: 2)
        XCTAssertEqual(completions, 1, file: file, line: line)
        XCTAssertTrue(context.invalidated.with { $0 }, file: file, line: line)
        let state = keychain.with { $0 }
        XCTAssertEqual(state.calls.count, success ? 1 : 0, file: file, line: line)
        if let call = state.calls.first {
            XCTAssertEqual(call.namespace, "regram-wallet", file: file, line: line)
            XCTAssertEqual(call.lifetime, 30, file: file, line: line)
            XCTAssertTrue(call.context === context, file: file, line: line)
            XCTAssertFalse(call.onMainThread, file: file, line: line)
            XCTAssertFalse(call.contextInvalidated, file: file, line: line)
        }
        if success && !keychainFails {
            XCTAssertTrue(session.with { $0 === state.result }, file: file, line: line)
            XCTAssertTrue(old.invalidated.with { $0 }, file: file, line: line)
            XCTAssertFalse(state.result.invalidated.with { $0 }, file: file, line: line)
        } else {
            XCTAssertTrue(session.with { $0 === old }, file: file, line: line)
            XCTAssertFalse(old.invalidated.with { $0 }, file: file, line: line)
        }
    }

    func testSuccessfulConfirmationReplacesThePreviousSession() throws {
        try complete(success: true)
    }

    func testRejectedConfirmationKeepsThePreviousSession() throws {
        try complete(success: false)
    }

    func testCredentialFailureKeepsThePreviousSession() throws {
        try complete(success: true, keychainFails: true)
    }

    func testBackgroundConfirmationStillCompletesOnMainThread() throws {
        try complete(success: true, backgroundReply: true)
    }
}
