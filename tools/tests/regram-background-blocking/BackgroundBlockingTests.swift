import Cocoa
import XCTest
import SwiftSignalKit

__QUEUES__
__TRANSLATION_FACTORY__
__PREVIEW_FACTORY__
__PREVIEW_SCHEDULE__

typealias TelegramMediaFile = Int
typealias EmojiValues = [(String, Data?, TelegramMediaFile)]

extension String {
    var withoutColorizer: String { self }
}

__EMOJI_CONTEXT__

class DiceFixture {
    __DICE_QUEUE__
    private var dataContexts: [String: EmojiDataContext] = [:]
    private var dataEffectsContexts: [String: EmojiDataContext] = [:]

    private func ensureLoaded() {}

    __DICE_METHODS__

    func publish(data: [String: EmojiValues] = [:], effects dataEffects: [String: EmojiValues] = [:]) {
        queue.async {
            __DICE_UPDATES__
        }
    }

    func onQueue(_ body: @escaping () -> Void) { queue.async(body) }

    func subscriberCount(_ body: @escaping (Int) -> Void) {
        queue.async {
            body((Array(self.dataContexts.values) + Array(self.dataEffectsContexts.values)).reduce(0) { $0 + $1.subscribers.copyItems().count })
        }
    }
}

struct BadgeResult {
    let dockText: String?
    let total: Int32
}

private let theme = BadgeTheme()
private struct BadgeTheme {
    let colors = BadgeColors()
}
private struct BadgeColors {
    let redUI = NSColor.red
    let underSelectedColor = NSColor.white
}

extension Int {
    var prettyNumber: String { String(self) }
}

extension NSFont {
    static func bold(_ size: CGFloat) -> NSFont { .boldSystemFont(ofSize: size) }
}

extension NSAttributedString {
    static func initialize(string: String, color: NSColor, font: NSFont) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.foregroundColor: color, .font: font])
    }
}

private func forceUpdateStatusBarIconByDockTile(sharedContext: Int) {}

final class BadgeFixture {
    private let disposable = MetaDisposable()
    private let isSelected = false
    private let layoutChanged: (() -> Void)?
    private(set) var unreadCount: Int32 = 0
    private(set) var attributedString: NSAttributedString?

    init(_ signal: Signal<BadgeResult, NoError>, layoutChanged: @escaping () -> Void) {
        self.layoutChanged = layoutChanged
        let s = signal |> deliverOnMainQueue
        let getColor: (Bool) -> NSColor = { _ in .red }
        let fontSize: CGFloat = 12
        let dockTile = false
        let sharedContext = 0
        __BADGE_SYNC__
        __BADGE_SUBSCRIPTION__
    }

    deinit { disposable.dispose() }
}

final class ReadyChild {
    let ready = Promise<Bool>(true)
}

final class ReadyFixture {
    let chatList = ReadyChild()
    let settings = ReadyChild()
    let ready = Promise<Bool>()

    init() {
        __READY_PIPELINE__
    }
}

private final class TranslationFixture {
    let queue = makeChatTranslationQueue()
    let state = ValuePromise<Bool>(ignoreRepeated: true)
    private let disposable = MetaDisposable()

    init() {
        disposable.set(combineLatest(queue: __TRANSLATION_QUEUE__, Signal<Bool, NoError>.single(true), Signal<Bool, NoError>.single(false)).start(next: { [weak self] loaded, _ in
            self?.state.set(loaded)
        }))
    }

    deinit { disposable.dispose() }
}

typealias MessageId = Int
struct Message {
    let id: MessageId
    let text: String
    let stableVersion: Int = 0
}
enum TranslateFetchError { case network }
__TRANSLATION_SCHEDULER__

private struct FolderData: Equatable {
    let filter: Int
    let request: Int
}

private struct FolderState {
    let filterData: FolderData
}

private final class FolderFixture {
    let queue = Queue(name: "folderFixture", qos: .userInitiated)
    let selectionState = Atomic(value: FolderState(filterData: FolderData(filter: 1, request: 1)))
    let built = Atomic<[Int]>(value: [])
    private let source = ValuePipe<((Int, FolderData), Int)>()
    private let disposable = MetaDisposable()

    init() {
        let selectionState = self.selectionState
        let built = self.built
        disposable.set((source.signal() |> deliverOn(queue) |> __FOLDER_SELECTION_GATE__ |> mapToQueue { value -> Signal<Int, NoError> in
            _ = built.modify { $0 + [value.0.0] }
            return .single(value.0.0)
        }).start())
    }

    func select(_ data: FolderData) { _ = selectionState.swap(FolderState(filterData: data)) }
    func send(_ id: Int, data: FolderData) { source.putNext(((id, data), 0)) }
    deinit { disposable.dispose() }
}

private struct EngineChatList: Equatable {
    let items: [Int]
}

private struct PaginationResult {
    let list: EngineChatList
    let filterData: FolderData
}

private final class PaginationFixture {
    var filterValue = FolderData(filter: 1, request: 1)
    private let previousChatList = Atomic<EngineChatList?>(value: nil)
    private let displayedFilterData = Atomic<FolderData?>(value: nil)

    __PAGINATION_VIEW__

    func prepare(_ list: EngineChatList) {
        __BACKGROUND_PUBLISH__
    }

    func apply(_ result: PaginationResult) {
        __APPLY_METADATA__
    }

    func display(_ list: EngineChatList, data: FolderData) {
        prepare(list)
        apply(PaginationResult(list: list, filterData: data))
    }

    func current() -> EngineChatList? { paginationView() }
}

final class BackgroundBlockingTests: XCTestCase {
    private func block(_ enqueue: (@escaping () -> Void) -> Void) -> DispatchSemaphore {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        enqueue {
            entered.signal()
            _ = release.wait(timeout: .now() + 3)
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 1), .success)
        return release
    }

    func testSymbolSubscriptionDoesNotWaitForBusyCacheQueue() {
        let fixture = DiceFixture()
        let release = block(fixture.onQueue)
        let returned = DispatchSemaphore(value: 0)
        let subscriptions = Atomic<[Disposable]>(value: [])
        let completed = expectation(description: "subscriptions created")
        DispatchQueue.global().async {
            let values = [false, true].map { fixture.interactiveSymbolData(baseSymbol: "dice", synchronous: $0).start() }
            _ = subscriptions.swap(values)
            returned.signal()
            completed.fulfill()
        }
        XCTAssertEqual(returned.wait(timeout: .now() + 0.25), .success)
        release.signal()
        wait(for: [completed], timeout: 2)
        for subscription in subscriptions.with({ $0 }) { subscription.dispose() }
    }

    func testEffectSubscriptionDoesNotWaitForBusyCacheQueue() {
        let fixture = DiceFixture()
        let release = block(fixture.onQueue)
        let returned = DispatchSemaphore(value: 0)
        let holder = MetaDisposable()
        let completed = expectation(description: "effect subscribed")
        DispatchQueue.global().async {
            holder.set(fixture.animationEffect(for: "effect").start())
            returned.signal()
            completed.fulfill()
        }
        XCTAssertEqual(returned.wait(timeout: .now() + 0.25), .success)
        release.signal()
        wait(for: [completed], timeout: 2)
        holder.dispose()
    }

    func testUnrelatedResourcesDoNotDelayCachedDice() {
        let fixture = DiceFixture()
        fixture.publish(data: ["dice": [("cached", nil, 7)]])
        let prepared = expectation(description: "cached data")
        fixture.onQueue { prepared.fulfill() }
        wait(for: [prepared], timeout: 1)
        let release = block(resourcesQueue.async)
        let received = expectation(description: "cache independent of resource queue")
        let subscription = fixture.interactiveSymbolData(baseSymbol: "dice", synchronous: true).start(next: { values in
            XCTAssertEqual(values.map { $0.2 }, [7])
            received.fulfill()
        })
        wait(for: [received], timeout: 1)
        release.signal()
        subscription.dispose()
    }

    func testCancelledQueuedRegistrationDoesNotRetainSubscribers() {
        let fixture = DiceFixture()
        let release = block(fixture.onQueue)
        let received = Atomic<Int>(value: 0)
        let subscriptions = (0 ..< 100).map { _ in fixture.animationEffect(for: "effect").start(next: { _ in _ = received.modify { $0 + 1 } }) }
        for subscription in subscriptions { subscription.dispose() }
        release.signal()
        let checked = expectation(description: "cancelled registrations removed")
        fixture.subscriberCount { count in
            XCTAssertEqual(count, 0)
            XCTAssertEqual(received.with { $0 }, 0)
            checked.fulfill()
        }
        wait(for: [checked], timeout: 2)
    }

    func testTakeOneRemovesSubscriberAfterInitialValue() {
        let fixture = DiceFixture()
        let received = expectation(description: "initial value")
        let holder = MetaDisposable()
        holder.set((fixture.animationEffect(for: "effect") |> take(1)).start(next: { _ in received.fulfill() }))
        wait(for: [received], timeout: 1)
        let checked = expectation(description: "subscription cleaned")
        fixture.subscriberCount { count in
            XCTAssertEqual(count, 0)
            checked.fulfill()
        }
        wait(for: [checked], timeout: 1)
        holder.dispose()
    }

    func testDiceAndEffectsRemainIndependentAndUpdatesStayOrdered() {
        let fixture = DiceFixture()
        let dice = Atomic<[[Int]]>(value: [])
        let effects = Atomic<[[Int]]>(value: [])
        let diceSubscription = fixture.interactiveSymbolData(baseSymbol: "same", synchronous: false).start(next: { values in
            _ = dice.modify { $0 + [values.map { $0.2 }] }
        })
        let effectSubscription = fixture.animationEffect(for: "same").start(next: { values in
            _ = effects.modify { $0 + [values.map { $0.2 }] }
        })
        fixture.publish(data: ["same": [("one", nil, 1)]], effects: ["same": [("effect", nil, 9)]])
        fixture.publish(data: ["same": [("two", nil, 2)]])
        let checked = expectation(description: "ordered updates")
        fixture.onQueue {
            XCTAssertEqual(dice.with { $0 }, [[], [1], [2]])
            XCTAssertEqual(effects.with { $0 }, [[], [9]])
            checked.fulfill()
        }
        wait(for: [checked], timeout: 1)
        diceSubscription.dispose()
        effectSubscription.dispose()
    }

    func testDisposingOneObserverKeepsAnotherActive() {
        let fixture = DiceFixture()
        let first = Atomic<Int>(value: 0)
        let second = Atomic<Int>(value: 0)
        let firstSubscription = fixture.animationEffect(for: "effect").start(next: { _ in _ = first.modify { $0 + 1 } })
        let secondSubscription = fixture.animationEffect(for: "effect").start(next: { _ in _ = second.modify { $0 + 1 } })
        let initialized = expectation(description: "observers registered")
        fixture.onQueue { initialized.fulfill() }
        wait(for: [initialized], timeout: 1)
        firstSubscription.dispose()
        fixture.publish(effects: ["effect": [("effect", nil, 9)]])
        let checked = expectation(description: "other observer survives")
        fixture.subscriberCount { count in
            XCTAssertEqual(count, 1)
            XCTAssertEqual(first.with { $0 }, 1)
            XCTAssertEqual(second.with { $0 }, 2)
            checked.fulfill()
        }
        wait(for: [checked], timeout: 1)
        secondSubscription.dispose()
    }

    func testDisposalDoesNotWaitForInFlightDelivery() {
        let fixture = DiceFixture()
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let subscription = fixture.animationEffect(for: "effect").start(next: { _ in
            entered.signal()
            _ = release.wait(timeout: .now() + 3)
        })
        XCTAssertEqual(entered.wait(timeout: .now() + 1), .success)
        let returned = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            subscription.dispose()
            returned.signal()
        }
        XCTAssertEqual(returned.wait(timeout: .now() + 0.25), .success)
        release.signal()
        let checked = expectation(description: "in-flight observer cleaned")
        fixture.subscriberCount { count in
            XCTAssertEqual(count, 0)
            checked.fulfill()
        }
        wait(for: [checked], timeout: 1)
    }

    func testIndependentCachesDoNotBlockEachOther() {
        let first = DiceFixture()
        let second = DiceFixture()
        let release = block(first.onQueue)
        let received = expectation(description: "other account cache remains responsive")
        let subscription = second.animationEffect(for: "effect").start(next: { _ in received.fulfill() })
        wait(for: [received], timeout: 1)
        release.signal()
        subscription.dispose()
    }

    func testBadgeCreationDoesNotWaitForMainThread() {
        let returned = DispatchSemaphore(value: 0)
        let holder = Atomic<BadgeFixture?>(value: nil)
        let updated = expectation(description: "badge updates on main thread")
        DispatchQueue.global().async {
            let badge = BadgeFixture(.single(BadgeResult(dockText: nil, total: 12))) {
                XCTAssertTrue(Thread.isMainThread)
                updated.fulfill()
            }
            _ = holder.swap(badge)
            returned.signal()
        }
        XCTAssertEqual(returned.wait(timeout: .now() + 0.25), .success)
        wait(for: [updated], timeout: 2)
        XCTAssertEqual(holder.with { $0?.unreadCount }, 12)
        XCTAssertEqual(holder.with { $0?.attributedString?.string }, "12")
    }

    func testBadgeClearsAndRelayoutsWhenCountBecomesZero() {
        let pipe = ValuePipe<BadgeResult>()
        var updates = 0
        let fixture = BadgeFixture(pipe.signal()) { updates += 1 }
        pipe.putNext(BadgeResult(dockText: nil, total: 5))
        XCTAssertEqual(fixture.attributedString?.string, "5")
        pipe.putNext(BadgeResult(dockText: nil, total: 0))
        XCTAssertEqual(fixture.unreadCount, 0)
        XCTAssertNil(fixture.attributedString)
        XCTAssertEqual(updates, 2)
    }

    func testReadinessDoesNotWaitForResourcePreparation() {
        let release = block(prepareQueue.async)
        let fixture = ReadyFixture()
        let ready = expectation(description: "readiness is independent of prepare queue")
        let disposable = (fixture.ready.get() |> filter { $0 } |> take(1)).start(next: { _ in ready.fulfill() })
        wait(for: [ready], timeout: 0.25)
        release.signal()
        disposable.dispose()
    }

    func testChatAppearanceDoesNotWaitForPrepareQueue() {
        let release = block(prepareQueue.async)
        let fixture = TranslationFixture()
        let ready = expectation(description: "translation state unblocks chat appearance")
        let subscription = fixture.state.get().start(next: { _ in ready.fulfill() })
        wait(for: [ready], timeout: 0.25)
        release.signal()
        subscription.dispose()
        withExtendedLifetime(fixture) {}
    }

    func testMediaPreviewWorkDoesNotBlockNewChatAppearance() {
        let previewQueue = makeMediaPreviewQueue()
        let release = block(previewQueue.async)
        let fixture = TranslationFixture()
        let ready = expectation(description: "new chat opens while preview generation is busy")
        let subscription = fixture.state.get().start(next: { _ in ready.fulfill() })
        wait(for: [ready], timeout: 0.25)
        release.signal()
        subscription.dispose()
        withExtendedLifetime(fixture) {}
    }

    func testIndependentChatTranslationContextsDoNotBlockEachOther() {
        let first = TranslationFixture()
        let release = block(first.queue.async)
        let second = TranslationFixture()
        let ready = expectation(description: "another chat has an independent state queue")
        let subscription = second.state.get().start(next: { _ in ready.fulfill() })
        wait(for: [ready], timeout: 0.25)
        release.signal()
        subscription.dispose()
        withExtendedLifetime((first, second)) {}
    }

    func testMediaPreviewCompletionDoesNotWaitForPrepareQueue() {
        let release = block(prepareQueue.async)
        let ready = expectation(description: "prepared media applies on its own queue")
        schedulePreviewPreparedMedias({ ready.fulfill() }, queue: makeMediaPreviewQueue())
        wait(for: [ready], timeout: 0.25)
        release.signal()
    }

    func testTranslationSchedulerKeepsBatchLimitsOnPrivateQueue() {
        let queue = makeChatTranslationQueue()
        let batches = Atomic<[Int]>(value: [])
        let settled = expectation(description: "all messages translated")
        settled.expectedFulfillmentCount = 3
        let scheduler = RegramChatTranslationScheduler(queue: queue, request: { messages, _ in
            _ = batches.modify { $0 + [messages.count] }
            return .single(Set(messages.map(\.id)))
        }, changed: { event in
            if case .settled = event { settled.fulfill() }
        })
        queue.async { scheduler.update((0 ..< 45).map { Message(id: $0, text: "text") }, generation: 1) }
        wait(for: [settled], timeout: 1)
        XCTAssertEqual(batches.with { $0 }, [20, 20, 5])
        withExtendedLifetime(scheduler) {}
    }

    func testTranslationSchedulerResetCancelsOldGeneration() {
        let queue = makeChatTranslationQueue()
        let oldSubscriber = Atomic<Subscriber<Set<MessageId>, TranslateFetchError>?>(value: nil)
        let cancelled = expectation(description: "old request cancelled")
        let ready = expectation(description: "new generation settled")
        let scheduler = RegramChatTranslationScheduler(queue: queue, request: { messages, generation in
            if generation == 1 {
                return Signal { subscriber in
                    _ = oldSubscriber.swap(subscriber)
                    return ActionDisposable { cancelled.fulfill() }
                }
            }
            return .single(Set(messages.map(\.id)))
        }, changed: { event in
            if case let .settled(completed, _) = event {
                XCTAssertEqual(completed, [2])
                ready.fulfill()
            }
        })
        queue.async {
            scheduler.update([Message(id: 1, text: "old")], generation: 1)
            scheduler.update([Message(id: 2, text: "new")], generation: 2)
            oldSubscriber.with { $0 }?.putNext([1])
        }
        wait(for: [cancelled, ready], timeout: 1)
        withExtendedLifetime(scheduler) {}
    }

    func testOldFolderUpdatesDoNotBuildRowsAfterSelectionChanges() {
        let fixture = FolderFixture()
        let release = block(fixture.queue.async)
        for id in 0 ..< 100 { fixture.send(id, data: FolderData(filter: 1, request: 1)) }
        fixture.select(FolderData(filter: 2, request: 1))
        fixture.send(100, data: FolderData(filter: 2, request: 1))
        let checked = expectation(description: "stale folder work skipped")
        fixture.queue.async {
            XCTAssertEqual(fixture.built.with { $0 }, [100])
            checked.fulfill()
        }
        release.signal()
        wait(for: [checked], timeout: 1)
    }

    func testOldPagingRequestsDoNotBuildRows() {
        let fixture = FolderFixture()
        let release = block(fixture.queue.async)
        fixture.send(1, data: FolderData(filter: 1, request: 1))
        fixture.select(FolderData(filter: 1, request: 2))
        fixture.send(2, data: FolderData(filter: 1, request: 2))
        let checked = expectation(description: "only current pagination builds rows")
        fixture.queue.async {
            XCTAssertEqual(fixture.built.with { $0 }, [2])
            checked.fulfill()
        }
        release.signal()
        wait(for: [checked], timeout: 1)
    }

    func testCurrentFolderUpdatesKeepTheirOrderAfterDiscardingOldWork() {
        let fixture = FolderFixture()
        fixture.send(1, data: FolderData(filter: 1, request: 1))
        let first = expectation(description: "first transition applied")
        fixture.queue.async { first.fulfill() }
        wait(for: [first], timeout: 1)
        let release = block(fixture.queue.async)
        fixture.send(2, data: FolderData(filter: 1, request: 1))
        fixture.select(FolderData(filter: 2, request: 1))
        fixture.send(3, data: FolderData(filter: 2, request: 1))
        fixture.send(4, data: FolderData(filter: 2, request: 1))
        let checked = expectation(description: "current diffs remain sequential")
        fixture.queue.async {
            XCTAssertEqual(fixture.built.with { $0 }, [1, 3, 4])
            checked.fulfill()
        }
        release.signal()
        wait(for: [checked], timeout: 1)
    }

    func testFolderSelectionCannotUsePreviousFoldersPagination() {
        let fixture = PaginationFixture()
        fixture.display(EngineChatList(items: [100, 90]), data: fixture.filterValue)
        fixture.filterValue = FolderData(filter: 2, request: 1)
        XCTAssertNil(fixture.current())
    }

    func testPreparedListDoesNotBecomePaginationSourceBeforeDisplay() {
        let fixture = PaginationFixture()
        let selected = fixture.filterValue
        let visible = EngineChatList(items: [100, 90])
        fixture.display(visible, data: selected)
        fixture.prepare(EngineChatList(items: [80, 70]))
        XCTAssertEqual(fixture.current(), visible)
    }

    func testDisplayedListBecomesPaginationSourceAfterApply() {
        let fixture = PaginationFixture()
        fixture.display(EngineChatList(items: [100, 90]), data: fixture.filterValue)
        let next = FolderData(filter: 2, request: 1)
        fixture.filterValue = next
        let nextList = EngineChatList(items: [50, 40])
        fixture.prepare(nextList)
        XCTAssertNil(fixture.current())
        fixture.apply(PaginationResult(list: nextList, filterData: next))
        XCTAssertEqual(fixture.current(), nextList)
    }

    func testPendingPageRequestDoesNotReuseDisplayedCursor() {
        let fixture = PaginationFixture()
        fixture.display(EngineChatList(items: [100, 90]), data: fixture.filterValue)
        fixture.filterValue = FolderData(filter: 1, request: 2)
        XCTAssertNil(fixture.current())
        let nextList = EngineChatList(items: [90, 80])
        fixture.display(nextList, data: fixture.filterValue)
        XCTAssertEqual(fixture.current(), nextList)
    }

    func testBotsFolderCannotStartFromAllChatsCursor() {
        let fixture = PaginationFixture()
        fixture.display(EngineChatList(items: [500, 400, 300]), data: fixture.filterValue)
        let bots = FolderData(filter: 2, request: 1)
        fixture.filterValue = bots
        var requests: [Int] = []
        if let cursor = fixture.current()?.items.last { requests.append(cursor) }
        XCTAssertEqual(requests, [])
        fixture.display(EngineChatList(items: [90, 80, 70]), data: bots)
        if let cursor = fixture.current()?.items.last { requests.append(cursor) }
        XCTAssertEqual(requests, [70])
    }
}
