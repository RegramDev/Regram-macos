import XCTest
import Postbox
import TelegramCore
import SwiftSignalKit
import RegramCore
import RegramServices
import MessageUtils
@testable import ChatHistoryModel

final class RegramChatTranslationSchedulerTests: XCTestCase {
    private func message(_ id: Int32, version: UInt32 = 1, text: String = "Public translation fixture", attributes: [MessageAttribute] = [], peerId: PeerId? = nil) -> Message {
        let peer = peerId ?? PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(11))
        return Message(stableId: UInt32(id), stableVersion: version, id: MessageId(peerId: peer, namespace: Namespaces.Message.Cloud, id: id), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: id, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: nil, text: text, attributes: attributes, media: [], peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    func testSameVisibleMessagesRetryAfterTransientProviderFailure() {
        let queue = Queue(name: "translation.retry")
        let complete = expectation(description: "same IDs recover")
        let source = message(1)
        var attempts = 0
        let scheduler = RegramChatTranslationScheduler(queue: queue, retryDelays: [0.01, 0.02], request: { messages, _ in
            attempts += 1
            if attempts == 1 { return .fail(.network) }
            return .single(Set(messages.map(\.id)))
        }, changed: { event in
            if case let .settled(ids, _) = event, ids == [source.id] { complete.fulfill() }
        })
        queue.sync {
            scheduler.update([source], generation: 1)
            for _ in 0..<20 { scheduler.update([source], generation: 1) }
        }
        wait(for: [complete], timeout: 2)
        queue.sync {
            XCTAssertEqual(attempts, 2)
            scheduler.reset(generation: 2)
        }
    }

    func testVisibleBatchesStaySerialAndMakeProgressDuringRefreshes() {
        let queue = Queue(name: "translation.serial")
        let complete = expectation(description: "all messages translated")
        let messages = (1...45).map { message(Int32($0)) }
        var requests: [[MessageId]] = []
        var active = 0
        var maximumActive = 0
        var translated = Set<MessageId>()
        let scheduler = RegramChatTranslationScheduler(queue: queue, request: { messages, _ in
            Signal { subscriber in
                requests.append(messages.map(\.id))
                active += 1
                maximumActive = max(maximumActive, active)
                queue.after(0.01) {
                    active -= 1
                    subscriber.putNext(Set(messages.map(\.id)))
                    subscriber.putCompletion()
                }
                return EmptyDisposable
            }
        }, changed: { event in
            if case let .settled(ids, _) = event {
                translated.formUnion(ids)
                if translated.count == messages.count { complete.fulfill() }
            }
        })
        queue.sync {
            scheduler.update(messages, generation: 1)
            for _ in 0..<20 { scheduler.update(messages, generation: 1) }
        }
        wait(for: [complete], timeout: 2)
        queue.sync {
            XCTAssertEqual(maximumActive, 1)
            XCTAssertEqual(requests.map(\.count), [20, 20, 5])
            XCTAssertEqual(requests.flatMap { $0 }.count, Set(requests.flatMap { $0 }).count)
            scheduler.reset(generation: 2)
        }
    }

    func testPartialSuccessRetriesOnlyMessagesWithoutCommittedTranslations() {
        let queue = Queue(name: "translation.partial")
        let complete = expectation(description: "partial batch recovered")
        let first = message(1)
        let second = message(2)
        var requests: [[MessageId]] = []
        var translated = Set<MessageId>()
        let scheduler = RegramChatTranslationScheduler(queue: queue, retryDelays: [0.01], request: { messages, _ in
            requests.append(messages.map(\.id))
            return .single(requests.count == 1 ? [second.id] : Set(messages.map(\.id)))
        }, changed: { event in
            if case let .settled(ids, _) = event {
                translated.formUnion(ids)
                if translated.count == 2 { complete.fulfill() }
            }
        })
        queue.sync { scheduler.update([first, second], generation: 1) }
        wait(for: [complete], timeout: 2)
        queue.sync {
            XCTAssertEqual(requests, [[second.id, first.id], [first.id]])
            scheduler.reset(generation: 2)
        }
    }

    func testRepeatedFailuresAreBoundedUntilExplicitGenerationReset() {
        let queue = Queue(name: "translation.bounded")
        let exhausted = expectation(description: "retry budget exhausted")
        let recovered = expectation(description: "explicit retry succeeds")
        let source = message(1)
        var attempts = 0
        var failures = 0
        let scheduler = RegramChatTranslationScheduler(queue: queue, retryDelays: [0.01, 0.02], request: { messages, generation in
            attempts += 1
            return generation == 1 ? .fail(.network) : .single(Set(messages.map(\.id)))
        }, changed: { event in
            if case let .settled(ids, failed) = event {
                if !failed.isEmpty { failures += 1; exhausted.fulfill() }
                if ids == [source.id] { recovered.fulfill() }
            }
        })
        queue.sync { scheduler.update([source], generation: 1) }
        wait(for: [exhausted], timeout: 2)
        queue.sync {
            for _ in 0..<100 { scheduler.update([source], generation: 1) }
            XCTAssertEqual(attempts, 3)
            XCTAssertEqual(failures, 1)
            scheduler.reset(generation: 2)
            scheduler.update([source], generation: 2)
        }
        wait(for: [recovered], timeout: 2)
        queue.sync {
            XCTAssertEqual(attempts, 4)
            scheduler.reset(generation: 3)
        }
    }

    func testGenerationResetCancelsOldProviderAndIgnoresItsLateResult() {
        let queue = Queue(name: "translation.generation")
        let recovered = expectation(description: "new generation succeeds")
        let old = message(1)
        let new = message(2)
        var lateResult: (() -> Void)?
        var disposed = 0
        var translated: [MessageId] = []
        let scheduler = RegramChatTranslationScheduler(queue: queue, request: { messages, generation in
            if generation == 1 {
                return Signal { subscriber in
                    lateResult = { subscriber.putNext(Set(messages.map(\.id))); subscriber.putCompletion() }
                    return ActionDisposable { disposed += 1 }
                }
            }
            return .single(Set(messages.map(\.id)))
        }, changed: { event in
            if case let .settled(ids, _) = event {
                translated.append(contentsOf: ids)
                if ids == [new.id] { recovered.fulfill() }
            }
        })
        queue.sync {
            scheduler.update([old], generation: 1)
            scheduler.reset(generation: 2)
            scheduler.update([new], generation: 2)
            lateResult?()
        }
        wait(for: [recovered], timeout: 2)
        queue.sync {
            XCTAssertEqual(disposed, 1)
            XCTAssertEqual(translated, [new.id])
            scheduler.reset(generation: 3)
        }
    }

    func testOversizedFirstMessageDoesNotStarveNormalMessages() {
        let queue = Queue(name: "translation.budget")
        let complete = expectation(description: "normal message is not starved")
        let ordinary = message(1)
        let large = message(2, text: String(repeating: "x", count: 25_001))
        var requests: [[MessageId]] = []
        let scheduler = RegramChatTranslationScheduler(queue: queue, retryDelays: [], request: { messages, _ in
            requests.append(messages.map(\.id))
            return .single(Set(messages.filter { $0.id == ordinary.id }.map(\.id)))
        }, changed: { event in
            if case let .settled(ids, _) = event, ids == [ordinary.id] { complete.fulfill() }
        })
        queue.sync { scheduler.update([ordinary, large], generation: 1) }
        wait(for: [complete], timeout: 2)
        queue.sync {
            XCTAssertEqual(requests, [[large.id], [ordinary.id]])
            scheduler.reset(generation: 2)
        }
    }

    func testProtectedMessageBatchContinuesAfterEmptyProviderCompletionAndSettlesVisibleMessages() throws {
        let fixture = try RegramTranslationPostboxFixture()
        defer { fixture.close() }
        let queue = Queue(name: "translation.pipeline")
        let providerQueue = Queue(name: "translation.pipeline.provider")
        let complete = expectation(description: "all committed translations settle")
        let failed = expectation(description: "empty provider response exhausts retries")
        let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(11))
        let source = (1...21).map { id in
            message(Int32(id), text: "@fixture https://example.invalid/fixture Public translation fixture \(id)", attributes: [TextEntitiesMessageAttribute(entities: [.init(range: 0..<8, type: .Mention)])], peerId: peerId)
        }
        fixture.seed(source)
        let settings = RegramAccountSettings(values: ["translationBackend": .string("default")])
        let target = "zh-CN"
        let failedId = source[19].id
        var requests: [[MessageId]] = []
        var translated = Set<MessageId>()
        var loading = Set<MessageId>()
        let providerRequests = Atomic(value: [MessageId]())
        let scheduler = RegramChatTranslationScheduler(queue: queue, retryDelays: [0.01, 0.02], request: { messages, _ in
            requests.append(messages.map(\.id))
            return fixture.postbox.transaction { transaction in
                messages.compactMap { transaction.getMessage($0.id) }
            } |> castError(TranslateFetchError.self) |> mapToSignal { originals in
                regramTranslateMessageBatch(messages: originals, to: target, isCurrent: { true }, translate: { message, part in
                    let ranges = part.entities.enumerated().map { index, entity in
                        RGTranslationLinkPlan.ProtectedRange(range: NSRange(location: entity.range.lowerBound, length: entity.range.count), id: index)
                    }
                    return regramProtectedTranslation(text: part.text, to: target, accountId: 0, settings: settings, ranges: ranges, protectedIds: Set(ranges.map(\.id)), telegramTranslate: { text, _ in
                        _ = providerRequests.modify { $0 + [message.id] }
                        if message.id == failedId { return .complete() }
                        return Signal { subscriber in
                            providerQueue.after(0.002) {
                                subscriber.putNext("译:" + text)
                                subscriber.putCompletion()
                            }
                            return EmptyDisposable
                        }
                    }) |> map { result in
                        TranslationMessageAttribute.Additional(text: result.text, entities: result.ranges.compactMap { range in
                            guard range.id >= 0, range.id < part.entities.count else { return nil }
                            return MessageTextEntity(range: range.range.location..<NSMaxRange(range.range), type: part.entities[range.id].type)
                        })
                    }
                }, commit: { message, attribute in
                    fixture.postbox.transaction { transaction in
                        regramCommitMessageTranslation(transaction: transaction, original: message, attribute: attribute, context: [], settings: settings, configurationIdentity: settings.translationIdentity, tone: .neutral, isCurrent: { true })
                    }
                })
            } |> mapToSignal { _ in
                fixture.postbox.transaction { transaction in
                    Set(messages.compactMap { transaction.getMessage($0.id) }.filter {
                        $0.hasTranslationAttribute(toLang: target) && regramTranslationMatches($0, settings: settings)
                    }.map(\.id))
                } |> castError(TranslateFetchError.self)
            }
        }, changed: { event in
            switch event {
            case let .loading(ids):
                loading.formUnion(ids)
            case let .settled(ids, failures):
                loading.subtract(ids)
                loading.subtract(failures)
                translated.formUnion(ids)
                if !ids.isEmpty, translated.count == source.count - 1 { complete.fulfill() }
                if !failures.isEmpty {
                    XCTAssertEqual(failures, [failedId])
                    failed.fulfill()
                }
            }
        })
        queue.sync {
            scheduler.update(source, generation: 1)
            for _ in 0..<20 { scheduler.update(source, generation: 1) }
        }
        wait(for: [complete, failed], timeout: 5)
        queue.sync {
            XCTAssertEqual(requests.first?.count, 20)
            XCTAssertTrue(loading.isEmpty)
            XCTAssertEqual(translated, Set(source.map(\.id)).subtracting([failedId]))
            XCTAssertEqual(providerRequests.with { $0.filter { $0 == failedId }.count }, 3)
            scheduler.reset(generation: 2)
        }
        let stored = try XCTUnwrap(fixture.transaction { transaction in source.compactMap { transaction.getMessage($0.id) } })
        for message in stored {
            if message.id == failedId {
                XCTAssertNil(message.translationAttribute(toLang: target))
                XCTAssertFalse(regramTranslationMatches(message, settings: settings))
            } else {
                let attribute = try XCTUnwrap(message.translationAttribute(toLang: target))
                XCTAssertTrue(attribute.text.hasPrefix("@fixture https://example.invalid/fixture 译:"))
                XCTAssertEqual(attribute.entities, [.init(range: 0..<8, type: .Mention)])
                XCTAssertTrue(regramTranslationMatches(message, settings: settings))
            }
        }
    }
}
