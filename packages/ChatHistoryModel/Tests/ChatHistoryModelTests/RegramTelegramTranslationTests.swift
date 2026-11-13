import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore
import XCTest
@testable import ChatHistoryModel

final class RegramTelegramTranslationTests: XCTestCase {
    func testLengthErrorRetriesInOrderAndAdjustsUTF16EntityOffsets() {
        let first = String(repeating: "文", count: 1015) + "。\n"
        let link = "https://example.test"
        let second = "👨‍👩‍👧‍👦 " + link + String(repeating: "字", count: 76)
        let source = first + second
        let sourceLink = (source as NSString).range(of: link)
        let entity = MessageTextEntity(range: sourceLink.location..<NSMaxRange(sourceLink), type: .Url)
        let messageId = MessageId(peerId: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(42)), namespace: Namespaces.Message.Cloud, id: 1)
        let done = expectation(description: "complete translation")
        var requests: [String] = []
        let task = regramTranslateTelegramText(text: source, entities: [entity], messageId: messageId) { text, entities, id in
            requests.append(text)
            if requests.count == 1 {
                XCTAssertEqual(id, messageId)
                return .fail(.textTooLong)
            }
            XCTAssertNil(id)
            XCTAssertLessThanOrEqual(text.utf16.count, 1024)
            let prefix = "  🌏"
            let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let offset = prefix.utf16.count - text.prefix(while: \.isWhitespace).utf16.count
            let shifted = entities.map { MessageTextEntity(range: ($0.range.lowerBound + offset)..<($0.range.upperBound + offset), type: $0.type) }
            return .single((prefix + body + "  ", shifted))
        }.start(next: { result in
            XCTAssertEqual(requests.dropFirst().joined(), source)
            XCTAssertGreaterThan(requests.count, 2)
            XCTAssertEqual(result?.0, requests.dropFirst().map { "🌏" + $0 }.joined())
            let translatedLink = result.map { ($0.0 as NSString).range(of: link) }
            XCTAssertEqual(result?.1.first?.range.lowerBound, translatedLink?.location)
            XCTAssertEqual(result?.1.first?.range.count, sourceLink.length)
            done.fulfill()
        }, error: { _ in XCTFail("Length failure should retry smaller text blocks") })
        defer { task.dispose() }
        wait(for: [done], timeout: 2)
    }

    func testNonLengthErrorDoesNotResendText() {
        let done = expectation(description: "rate limit remains a rate limit")
        var requests = 0
        let task = regramTranslateTelegramText(text: String(repeating: "字", count: 2100), entities: [], messageId: nil) { _, _, _ in
            requests += 1
            return .fail(.limitExceeded)
        }.start(next: { _ in XCTFail("Rate-limited request must fail") }, error: { error in
            guard case .limitExceeded = error else { return XCTFail("Wrong error") }
            XCTAssertEqual(requests, 1)
            done.fulfill()
        })
        defer { task.dispose() }
        wait(for: [done], timeout: 2)
    }

    func testRestrictedMessageKeepsTheNativeMessageRequest() {
        let done = expectation(description: "restricted message surfaces the length limit")
        let messageId = MessageId(peerId: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(42)), namespace: Namespaces.Message.Cloud, id: 1)
        var requests = 0
        let task = regramTranslateTelegramText(text: String(repeating: "字", count: 2100), entities: [], messageId: messageId, permitsTextRetry: false) { _, _, id in
            XCTAssertEqual(id, messageId)
            requests += 1
            return .fail(.textTooLong)
        }.start(next: { _ in XCTFail("Restricted text must not be resent in blocks") }, error: { error in
            guard case .textTooLong = error else { return XCTFail("Wrong error") }
            XCTAssertEqual(requests, 1)
            done.fulfill()
        })
        defer { task.dispose() }
        wait(for: [done], timeout: 2)
    }
}
