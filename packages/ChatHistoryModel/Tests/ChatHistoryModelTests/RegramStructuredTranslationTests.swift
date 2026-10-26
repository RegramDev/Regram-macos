import XCTest
import Postbox
import TelegramCore
import RegramCore
import SwiftSignalKit
@testable import ChatHistoryModel

final class RegramStructuredTranslationTests: XCTestCase {
    private let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(11))

    private func message(id: Int32 = 1, text: String = "", peer: PeerId? = nil, media: [Media] = [], attributes: [MessageAttribute] = [], flags: MessageFlags = [.Incoming]) -> Message {
        Message(stableId: UInt32(id), stableVersion: 2, id: MessageId(peerId: peer ?? peerId, namespace: Namespaces.Message.Cloud, id: id), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: id, flags: flags, tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: nil, text: text, attributes: attributes, media: media, peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    private func page(_ blocks: [InstantPageBlock], media: [EngineMedia.Id: EngineMedia] = [:]) -> InstantPage {
        InstantPage(blocks: blocks, media: media, isComplete: true, rtl: false, url: "https://source.invalid/original", views: 7)
    }

    func testRichTranslationRetainsStructureMediaTargetsCodeAndNativeSerialization() throws {
        initializeAccountManagement()
        let imageId = MediaId(namespace: Namespaces.Media.CloudImage, id: 77)
        let image = TelegramMediaImage(imageId: imageId, representations: [], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        let button = InstantPageButton(text: .bold(.plain("Open")), action: .url("https://action.invalid/path?q=1"), color: .primary, isLink: true)
        let fixed = RichText.fixed(.plain("let value = 42"))
        let formula = RichText.formula(latex: "x^2 + y^2")
        let original = page([
            .paragraph(.concat([.plain("same"), .bold(.plain("same")), .url(text: .italic(.plain("Read")), url: "https://destination.invalid/?secret=1", webpageId: imageId), fixed, formula, .textCustomEmoji(fileId: 88, alt: "🙂"), .textMention(text: .plain("@account"))])),
            .list(items: [.text(.plain("List"), "4", true)], ordered: true),
            .table(title: .plain("Table"), rows: [InstantPageTableRow(cells: [InstantPageTableCell(text: .underline(.plain("Cell")), header: true, alignment: .right, verticalAlignment: .bottom, colspan: 2, rowspan: 3)])], bordered: true, striped: true, compact: true),
            .image(id: imageId, caption: InstantPageCaption(text: .plain("Caption"), credit: .plain("Credit")), url: "https://image.invalid/original", webpageId: imageId, spoiler: true),
            .buttonRow(alignment: .right, buttons: [button]),
            .preformatted(text: .plain("do not translate()"), language: "swift"),
            .details(title: .plain("Details"), blocks: [.paragraph(.plain("Inside"))], expanded: false)
        ], media: [imageId: EngineMedia(image)])
        let originalBlocks = original.blocks
        let source = message(attributes: [RichTextMessageAttribute(instantPage: original, fullInstantPage: nil)])
        let plan = try RegramMessageTranslationPlan(message: source)
        XCTAssertEqual(plan.texts.map(\.text), ["same", "same", "Read", "List", "Table", "Cell", "Caption", "Credit", "Open", "Details", "Inside"])
        let values = plan.texts.indices.map { TranslationMessageAttribute.Additional(text: "译\($0)", entities: []) }
        let attribute = try plan.attribute(translations: values, toLang: "zh-TW")
        let result = try XCTUnwrap(attribute.instantPage)
        XCTAssertEqual(attribute.text, "")
        XCTAssertEqual(result.media[imageId]?._asMedia().isEqual(to: image), true)
        XCTAssertEqual(result.url, original.url)
        XCTAssertEqual(result.views, 7)
        XCTAssertTrue(result.isComplete)
        guard case let .paragraph(.concat(texts)) = result.blocks[0],
              case let .bold(.plain(second)) = texts[1],
              case let .url(label, url, webpageId) = texts[2] else { return XCTFail("Rich structure lost") }
        XCTAssertEqual(texts[0], .plain("译0"))
        XCTAssertEqual(second, "译1")
        XCTAssertEqual(label, .italic(.plain("译2")))
        XCTAssertEqual(url, "https://destination.invalid/?secret=1")
        XCTAssertEqual(webpageId, imageId)
        XCTAssertEqual(texts[3], fixed)
        XCTAssertEqual(texts[4], formula)
        XCTAssertEqual(texts[5], .textCustomEmoji(fileId: 88, alt: "🙂"))
        XCTAssertEqual(texts[6], .textMention(text: .plain("@account")))
        guard case let .table(_, rows, bordered, striped, compact) = result.blocks[2] else { return XCTFail("Table lost") }
        XCTAssertEqual(rows[0].cells[0].text, .underline(.plain("译5")))
        XCTAssertEqual(rows[0].cells[0].colspan, 2)
        XCTAssertEqual(rows[0].cells[0].rowspan, 3)
        XCTAssertEqual(rows[0].cells[0].alignment, .right)
        XCTAssertTrue(bordered && striped && compact)
        guard case let .buttonRow(alignment, buttons) = result.blocks[4] else { return XCTFail("Button lost") }
        XCTAssertEqual(alignment, .right)
        XCTAssertEqual(buttons[0].text, .bold(.plain("译8")))
        XCTAssertEqual(buttons[0].action, button.action)
        XCTAssertEqual(buttons[0].color, button.color)
        XCTAssertTrue(buttons[0].isLink)
        XCTAssertEqual(result.blocks[5], original.blocks[5])
        XCTAssertEqual(original.blocks, originalBlocks)
        let encoder = PostboxEncoder()
        attribute.encode(encoder)
        let restored = TranslationMessageAttribute(decoder: PostboxDecoder(buffer: MemoryBuffer(data: encoder.makeData())))
        XCTAssertEqual(restored, attribute)
    }

    func testPollTranslationBuildsNativeOptionsAndSolutionWithoutChangingVotes() throws {
        let questionEntities = [MessageTextEntity(range: 1..<3, type: .Bold)]
        let options = [TelegramMediaPollOption(text: "First", entities: [], opaqueIdentifier: Data([1]), date: 10, addedBy: peerId), TelegramMediaPollOption(text: "Second", entities: [], opaqueIdentifier: Data([2]), date: nil, addedBy: nil)]
        let results = TelegramMediaPollResults(voters: nil, totalVoters: 8, recentVoters: [peerId], solution: .init(text: "Explanation", entities: []), hasUnseenVotes: true, canViewStats: true)
        let poll = TelegramMediaPoll(pollId: MediaId(namespace: Namespaces.Media.CloudPoll, id: 8), publicity: .anonymous, kind: .quiz(multipleAnswers: false), text: "A😀B", textEntities: questionEntities, options: options, correctAnswers: [Data([2])], results: results, isClosed: false, deadlineTimeout: 60, deadlineDate: 90, pollHash: 4)
        let plan = try RegramMessageTranslationPlan(message: message(media: [poll]))
        XCTAssertEqual(plan.texts.map(\.text), ["A😀B", "First", "Second", "Explanation"])
        XCTAssertEqual(plan.texts[0].entities, questionEntities)
        let translated = [TranslationMessageAttribute.Additional(text: "译😀文", entities: questionEntities), .init(text: "一", entities: []), .init(text: "二", entities: []), .init(text: "说明", entities: [])]
        let attribute = try plan.attribute(translations: translated, toLang: "zh-CN")
        XCTAssertEqual(attribute.text, "译😀文")
        XCTAssertEqual(attribute.entities, questionEntities)
        XCTAssertEqual(attribute.additional.map(\.text), ["一", "二"])
        XCTAssertEqual(attribute.pollSolution?.text, "说明")
        XCTAssertNil(attribute.instantPage)
        XCTAssertEqual(poll.options.map(\.opaqueIdentifier), [Data([1]), Data([2])])
        XCTAssertEqual(poll.results.totalVoters, 8)
        XCTAssertEqual(poll.correctAnswers, [Data([2])])
        XCTAssertThrowsError(try plan.attribute(translations: Array(translated.dropLast()), toLang: "zh-CN"))
        XCTAssertThrowsError(try plan.attribute(translations: plan.texts.map { _ in .init(text: "", entities: []) }, toLang: "zh-CN"))
    }

    func testSelectedProviderSafetyRejectsSensitiveMessagesAndFreshCachedProtection() {
        let safe = message(text: "normal")
        XCTAssertTrue(regramSupportsSelectedTranslationProvider(safe))
        XCTAssertTrue(regramSupportsSelectedTranslationProvider(message()))
        let secret = PeerId(namespace: Namespaces.Peer.SecretChat, id: ._internalFromInt64Value(1))
        XCTAssertFalse(regramSupportsSelectedTranslationProvider(message(text: "secret", peer: secret)))
        XCTAssertFalse(regramSupportsSelectedTranslationProvider(message(text: "private", flags: [.Incoming, .CopyProtected])))
        XCTAssertFalse(regramSupportsSelectedTranslationProvider(message(media: [TelegramMediaPaidContent(amount: 1, extendedMedia: [])])))
        XCTAssertFalse(regramSupportsSelectedTranslationProvider(message(media: [TelegramMediaExpiredContent(data: .image)])))
        XCTAssertFalse(regramSupportsSelectedTranslationProvider(message(attributes: [AutoremoveTimeoutMessageAttribute(timeout: 60, countdownBeginTime: nil)])))
        XCTAssertFalse(regramSupportsSelectedTranslationProvider(message(attributes: [AutoclearTimeoutMessageAttribute(timeout: viewOnceTimeout, countdownBeginTime: nil)])))
        XCTAssertFalse(regramSupportsSelectedTranslationProvider(message(attributes: [RGRevokedMessageAttribute(date: 1, wasSecretMedia: false)])))
        XCTAssertFalse(regramSupportsSelectedTranslationProvider(safe, cachedData: CachedUserData().withUpdatedFlags(.copyProtectionEnabled)))
        XCTAssertFalse(regramSupportsSelectedTranslationProvider(safe, cachedData: CachedUserData().withUpdatedFlags(.myCopyProtectionEnabled)))
    }

    func testEveryBackendNeedsVersionedProviderAndToneStamp() {
        var settings = RegramAccountSettings()
        let original = message(text: "source", attributes: [TranslationMessageAttribute(text: "old native", entities: [], toLang: "zh")])
        for backend in ["default", "google", "llm", "system"] {
            settings["translationBackend"] = .string(backend)
            XCTAssertFalse(regramTranslationMatches(original, settings: settings))
            let legacy = original.withUpdatedAttributes(original.attributes + [RegramTranslationMessageAttribute(configuration: settings.translationIdentity)])
            XCTAssertFalse(regramTranslationMatches(legacy, settings: settings))
            let stamped = original.withUpdatedAttributes(original.attributes + [RegramTranslationMessageAttribute(configuration: regramTranslationCacheIdentity(settings.translationIdentity, tone: .formal))])
            XCTAssertTrue(regramTranslationMatches(stamped, settings: settings, tone: .formal))
            XCTAssertFalse(regramTranslationMatches(stamped, settings: settings, tone: .neutral))
            settings["translationBackend"] = .string("yandex")
            XCTAssertFalse(regramTranslationMatches(stamped, settings: settings, tone: .formal))
        }
    }

    func testRichPlanPrefersLoadedFullPageAndRejectsUnsafeShapeBounds() throws {
        let partial = page([.paragraph(.plain("partial"))])
        let full = page([.paragraph(.plain("full"))])
        let loaded = message(attributes: [RichTextMessageAttribute(instantPage: partial, fullInstantPage: full)])
        XCTAssertEqual(try RegramMessageTranslationPlan(message: loaded).texts.map(\.text), ["full"])
        var nested = RichText.plain("deep")
        for _ in 0..<66 { nested = .bold(nested) }
        XCTAssertThrowsError(try RegramMessageTranslationPlan(message: message(attributes: [RichTextMessageAttribute(instantPage: page([.paragraph(nested)]), fullInstantPage: nil)])))
        let oversized = page([.paragraph(.plain(String(repeating: "a", count: 25_001)))])
        XCTAssertThrowsError(try RegramMessageTranslationPlan(message: message(attributes: [RichTextMessageAttribute(instantPage: oversized, fullInstantPage: nil)])))
    }

    func testTranslationContentSeparatesEmptyMediaFromPlainRichAndPollText() {
        XCTAssertFalse(regramHasSelectedTranslationContent(message()))
        XCTAssertFalse(regramHasSelectedTranslationContent(message(text: " \n\t")))
        XCTAssertTrue(regramSupportsSelectedTranslationProvider(message()))
        XCTAssertTrue(regramHasSelectedTranslationContent(message(text: "caption")))
        XCTAssertTrue(regramHasSelectedTranslationContent(message(text: String(repeating: "a", count: 25_000))))
        XCTAssertFalse(regramHasSelectedTranslationContent(message(text: String(repeating: "😀", count: 12_501))))
        XCTAssertTrue(regramHasSelectedTranslationContent(message(attributes: [RichTextMessageAttribute(instantPage: page([.paragraph(.bold(.plain("rich")))]), fullInstantPage: nil)])))
        XCTAssertFalse(regramHasSelectedTranslationContent(message(attributes: [RichTextMessageAttribute(instantPage: page([.preformatted(text: .plain("code"), language: "swift")]), fullInstantPage: nil)])))
        let poll = TelegramMediaPoll(pollId: MediaId(namespace: Namespaces.Media.CloudPoll, id: 8), publicity: .anonymous, kind: .poll(multipleAnswers: false), text: "Question", textEntities: [], options: [], correctAnswers: nil, results: .init(voters: nil, totalVoters: nil, recentVoters: [], solution: nil, hasUnseenVotes: nil, canViewStats: false), isClosed: false, deadlineTimeout: nil, deadlineDate: nil, pollHash: 1)
        XCTAssertTrue(regramHasSelectedTranslationContent(message(media: [poll])))
    }

    func testMixedBatchCommitsSuccessfulMessagesAndLeavesFailuresUncached() throws {
        let fixture = try RegramTranslationPostboxFixture()
        defer { fixture.close() }
        let oversized = RichTextMessageAttribute(instantPage: page([.paragraph(.plain(String(repeating: "x", count: 25_001)))]), fullInstantPage: nil)
        let rich = RichTextMessageAttribute(instantPage: page([.paragraph(.plain("rich"))]), fullInstantPage: nil)
        let poll = TelegramMediaPoll(pollId: MediaId(namespace: Namespaces.Media.CloudPoll, id: 8), publicity: .anonymous, kind: .poll(multipleAnswers: false), text: "Question", textEntities: [], options: [TelegramMediaPollOption(text: "Answer", entities: [], opaqueIdentifier: Data([1]), date: nil, addedBy: nil)], correctAnswers: nil, results: .init(voters: nil, totalVoters: 1, recentVoters: [], solution: nil, hasUnseenVotes: nil, canViewStats: false), isClosed: false, deadlineTimeout: nil, deadlineDate: nil, pollHash: 1)
        let messages = [message(id: 1, text: "first"), message(id: 2, text: "failed provider"), message(id: 3, attributes: [oversized]), message(id: 4), message(id: 5, text: "stale"), message(id: 6, text: "empty response"), message(id: 7, text: "completed response"), message(id: 8, attributes: [rich]), message(id: 9, media: [poll])]
        fixture.seed(messages)
        let originals = try XCTUnwrap(fixture.transaction { transaction in messages.compactMap { transaction.getMessage($0.id) } })
        fixture.transaction { transaction in
            transaction.updateMessage(messages[4].id) { .update(RegramTranslationPostboxFixture.store($0, text: "edited")) }
        }
        let settings = RegramAccountSettings()
        var requested: [Int32] = []
        var committed: [Int32] = []
        let done = expectation(description: "mixed batch")
        let task = regramTranslateMessageBatch(messages: originals, to: "zh-TW", isCurrent: { true }, translate: { message, part in
            requested.append(message.id.id)
            if message.id.id == 2 {
                XCTAssertEqual(committed, [1])
                return .fail(.network)
            }
            if message.id.id == 6 { return .single(.init(text: "", entities: [])) }
            if message.id.id == 7 { return .complete() }
            return .single(.init(text: "译:" + part.text, entities: []))
        }, commit: { original, attribute in
            fixture.postbox.transaction { transaction in
                let applied = regramCommitMessageTranslation(transaction: transaction, original: original, attribute: attribute, context: [], settings: settings, configurationIdentity: settings.translationIdentity, tone: .formal, isCurrent: { true })
                if applied { committed.append(original.id.id) }
                return applied
            }
        }).start(error: { _ in XCTFail("A local failure must not abort the batch"); done.fulfill() }, completed: { done.fulfill() })
        defer { task.dispose() }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(requested, [1, 2, 5, 6, 7, 8, 9, 9])
        XCTAssertEqual(committed, [1, 8, 9])
        let stored = try XCTUnwrap(fixture.transaction { transaction in messages.compactMap { transaction.getMessage($0.id) } })
        for value in stored {
            let attribute = value.attributes.compactMap { $0 as? TranslationMessageAttribute }.first
            if [1, 8, 9].contains(value.id.id) {
                XCTAssertEqual(attribute?.toLang, "zh-TW")
                XCTAssertTrue(regramTranslationMatches(value, settings: settings, tone: .formal))
                XCTAssertFalse(regramTranslationMatches(value, settings: settings, tone: .neutral))
            } else {
                XCTAssertNil(attribute)
                XCTAssertFalse(regramTranslationMatches(value, settings: settings, tone: .formal))
            }
        }
        XCTAssertEqual(stored[0].text, "first")
        XCTAssertEqual(stored[4].text, "edited")
        XCTAssertEqual(stored[7].attributes.compactMap { $0 as? TranslationMessageAttribute }.first?.instantPage?.blocks, [.paragraph(.plain("译:rich"))])
        XCTAssertEqual(stored[8].attributes.compactMap { $0 as? TranslationMessageAttribute }.first?.additional.map(\.text), ["译:Answer"])
        XCTAssertEqual(stored[8].media.compactMap { $0 as? TelegramMediaPoll }.first?.results.totalVoters, 1)
    }

    func testGlobalInvalidationKeepsPriorCommitButRejectsInFlightAndLaterMessages() throws {
        let fixture = try RegramTranslationPostboxFixture()
        defer { fixture.close() }
        let messages = [message(id: 1, text: "first"), message(id: 2, text: "in flight"), message(id: 3, text: "later")]
        fixture.seed(messages)
        let originals = try XCTUnwrap(fixture.transaction { transaction in messages.compactMap { transaction.getMessage($0.id) } })
        let current = Atomic(value: true)
        let settings = RegramAccountSettings()
        var requested: [Int32] = []
        let done = expectation(description: "global invalidation")
        let task = regramTranslateMessageBatch(messages: originals, to: "zh-CN", isCurrent: { current.with { $0 } }, translate: { message, part in
            requested.append(message.id.id)
            if message.id.id == 2 { _ = current.swap(false) }
            return .single(.init(text: "译:" + part.text, entities: []))
        }, commit: { original, attribute in
            fixture.postbox.transaction { transaction in
                regramCommitMessageTranslation(transaction: transaction, original: original, attribute: attribute, context: [], settings: settings, configurationIdentity: settings.translationIdentity, tone: .neutral, isCurrent: { current.with { $0 } })
            }
        }).start(error: { error in
            guard case .outdated = error else { return XCTFail("Expected outdated generation") }
            done.fulfill()
        }, completed: { XCTFail("Global invalidation must stop the batch"); done.fulfill() })
        defer { task.dispose() }
        wait(for: [done], timeout: 10)
        XCTAssertEqual(requested, [1, 2])
        let stored = try XCTUnwrap(fixture.transaction { transaction in messages.compactMap { transaction.getMessage($0.id) } })
        XCTAssertTrue(regramTranslationMatches(stored[0], settings: settings))
        XCTAssertFalse(regramTranslationMatches(stored[1], settings: settings))
        XCTAssertFalse(regramTranslationMatches(stored[2], settings: settings))
    }

    func testFreshCommitRejectsConfigurationProtectionAndContextChanges() throws {
        let fixture = try RegramTranslationPostboxFixture()
        defer { fixture.close() }
        let source = message(text: "source")
        fixture.seed([source])
        let original = try XCTUnwrap(fixture.transaction { $0.getMessage(source.id) } ?? nil)
        let settings = RegramAccountSettings()
        let attribute = TranslationMessageAttribute(text: "译文", entities: [], toLang: "zh-CN")
        var changed = settings
        changed["translationBackend"] = .string("yandex")
        for (currentSettings, context) in [(changed, [String]()), (settings, ["changed context"])] {
            XCTAssertEqual(fixture.transaction { transaction in
                regramCommitMessageTranslation(transaction: transaction, original: original, attribute: attribute, context: context, settings: currentSettings, configurationIdentity: settings.translationIdentity, tone: .neutral, isCurrent: { true })
            }, false)
        }
        fixture.transaction { transaction in
            transaction.updatePeerCachedData(peerIds: [source.id.peerId]) { _, _ in CachedUserData().withUpdatedFlags(.copyProtectionEnabled) }
        }
        XCTAssertEqual(fixture.transaction { transaction in
            regramCommitMessageTranslation(transaction: transaction, original: original, attribute: attribute, context: [], settings: settings, configurationIdentity: settings.translationIdentity, tone: .neutral, isCurrent: { true })
        }, false)
        let stored = try XCTUnwrap(fixture.transaction { $0.getMessage(source.id) } ?? nil)
        XCTAssertFalse(stored.attributes.contains { $0 is TranslationMessageAttribute || $0 is RegramTranslationMessageAttribute })
    }

    func testDisposingBatchCancelsRequestAndIgnoresLateResponses() {
        var response: (() -> Void)?
        var cancelled = false
        var committed = false
        var requested: [Int32] = []
        let task = regramTranslateMessageBatch(messages: [message(id: 1, text: "first"), message(id: 2, text: "later")], to: "zh", isCurrent: { true }, translate: { message, _ in
            requested.append(message.id.id)
            return Signal { subscriber in
                response = {
                    subscriber.putNext(.init(text: "late", entities: []))
                    subscriber.putCompletion()
                }
                return ActionDisposable { cancelled = true }
            }
        }, commit: { _, _ in
            committed = true
            return .single(true)
        }).start()
        XCTAssertEqual(requested, [1])
        XCTAssertFalse(cancelled)
        task.dispose()
        XCTAssertTrue(cancelled)
        response?()
        XCTAssertFalse(committed)
        XCTAssertEqual(requested, [1])
    }
}

final class RegramTranslationPostboxFixture {
    private static let installLogger: Void = {
        let logger = Logger(rootPath: NSTemporaryDirectory(), basePath: NSTemporaryDirectory())
        logger.logToFile = false
        logger.logToConsole = false
        Logger.setSharedLogger(logger)
    }()

    let basePath: String
    private(set) var postbox: Postbox!

    init() throws {
        _ = Self.installLogger
        initializeAccountManagement()
        basePath = NSTemporaryDirectory() + "regram-translation-fixture-" + UUID().uuidString
        let ready = DispatchSemaphore(value: 0)
        var opened: Postbox?
        let parameters = ValueBoxEncryptionParameters(forceEncryptionIfNoSet: false, key: ValueBoxEncryptionParameters.Key(data: Data(count: 32))!, salt: ValueBoxEncryptionParameters.Salt(data: Data(count: 16))!)
        let task = openPostbox(basePath: basePath, seedConfiguration: telegramPostboxSeedConfiguration, encryptionParameters: parameters, timestampForAbsoluteTimeBasedOperations: 1, isMainProcess: true, isTemporary: true, isReadOnly: false, useCopy: false, useCaches: false, removeDatabaseOnError: true).start(next: { result in
            switch result {
            case let .postbox(value): opened = value; ready.signal()
            case .error: ready.signal()
            case .upgrading: break
            }
        })
        XCTAssertEqual(ready.wait(timeout: .now() + 10), .success)
        task.dispose()
        postbox = try XCTUnwrap(opened)
    }

    static func store(_ message: Message, text: String? = nil) -> StoreMessage {
        StoreMessage(id: message.id, customStableId: nil, globallyUniqueId: message.globallyUniqueId, groupingKey: message.groupingKey, threadId: message.threadId, timestamp: message.timestamp, flags: StoreMessageFlags(message.flags), tags: message.tags, globalTags: message.globalTags, localTags: message.localTags, forwardInfo: message.forwardInfo.flatMap(StoreMessageForwardInfo.init), authorId: message.author?.id, text: text ?? message.text, attributes: message.attributes, media: message.media)
    }

    func seed(_ messages: [Message]) {
        transaction { transaction in
            let peers = Set(messages.map { $0.id.peerId }).map { id in
                TelegramUser(id: id, accessHash: nil, firstName: "Fixture", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
            }
            updatePeersCustom(transaction: transaction, peers: peers, update: { _, peer in peer })
            _ = transaction.addMessages(messages.map { Self.store($0) }, location: .Random)
        }
    }

    @discardableResult
    func transaction<T>(_ body: @escaping (Transaction) -> T, file: StaticString = #file, line: UInt = #line) -> T? {
        let done = DispatchSemaphore(value: 0)
        var result: T?
        let task = postbox.transaction(body).start(next: { result = $0 }, completed: { done.signal() })
        XCTAssertEqual(done.wait(timeout: .now() + 10), .success, file: file, line: line)
        task.dispose()
        return result
    }

    func close() {
        let ready = DispatchSemaphore(value: 0)
        let task = postbox.mediaBox.storageBox.totalSize().start(next: { _ in ready.signal() })
        _ = ready.wait(timeout: .now() + 10)
        task.dispose()
        transaction { _ in }
        postbox = nil
        try? FileManager.default.removeItem(atPath: basePath)
    }
}
