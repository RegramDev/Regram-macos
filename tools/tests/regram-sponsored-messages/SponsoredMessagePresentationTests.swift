import Foundation
import XCTest
import SwiftSignalKit

private typealias Message = Int
private typealias PeerId = Int
private extension Int { func toInt64() -> Int64 { Int64(self) } }
private struct Setting { let bool: Bool }
private struct Settings {
    let hidden: Bool
    subscript(_ key: String) -> Setting { Setting(bool: key == "disableAllAds" && hidden) }
}
private final class RegramPreferences {
    static let shared = RegramPreferences()
    var hidden = false
    func settings(accountId: Int64) -> Settings { Settings(hidden: hidden && accountId == 1) }
}
private struct Context { let peerId = 1 }
private struct Interaction { let interactionContext = Context() }
private enum InitialAction { case ad(Int) }
private struct InterfaceState {
    var historyCount: Int? = 2
    var adMessage: Message? = 10
    var initialAction: InitialAction? = .ad(1)
}
private struct Peer { let id: Int }
private struct RenderedPeer { let peerId: Int }
private struct FoundPeer { let peer: Peer }
private final class AdPeer {}
private enum Entry {
    case localPeer(RenderedPeer, Int, Int?, Int, Bool, Bool, Int?)
    case globalPeer(FoundPeer, Int, Int, AdPeer?)
    case savedMessages(Peer)
    case message(Message, String, Int?, Int?, Int)
    case other
}
private func regramShouldHideMessage(_ message: Message, accountId: Int64) -> Bool { message == 99 }

private func botAd(hidden: Bool, count: Int?) -> Message? {
    RegramPreferences.shared.hidden = hidden
    let chatInteraction = Interaction()
    let interfaceState = InterfaceState(historyCount: count)
    __HIDE_HEADER__
    __BOT_HEADER__
    return botAd
}

private func proxyPromo(hidden: Bool) -> Bool {
    RegramPreferences.shared.hidden = hidden
    let chatInteraction = Interaction()
    let interfaceState = InterfaceState()
    __HIDE_HEADER__
    if __PROMO_CONDITION__ { return kind == 1 }
    return false
}

private func visibleSearchEntries(_ entries: [Entry], hidden: Bool) -> [Entry] {
    let hidesSponsoredMessages = hidden
    let context = Context()
    let value = (entries, false)
    __SEARCH_PROJECTION__
    return visible
}

private func channelAds(_ adMessage: Message?, _ dynamicAdMessages: [Message], hidden: Bool) -> (Message?, [Message]) {
    let regramSettings = Settings(hidden: hidden)
    __CHANNEL_GATE__
    return (adMessage, dynamicAdMessages)
}

private struct AdditionalItem { let item: AdditionalPeer }
private struct AdditionalPeer { let renderedPeer: RenderedPeer }
private struct List { let additionalItems: [AdditionalItem] }
private struct Update { let list: List }
private struct HiddenItems { let promo: Set<Int> }

private func proxyRows(hidden: Bool, dismissed: Set<Int>) -> [AdditionalItem] {
    RegramPreferences.shared.hidden = hidden
    let context = Context()
    let update = Update(list: List(additionalItems: [1, 2].map { AdditionalItem(item: AdditionalPeer(renderedPeer: RenderedPeer(peerId: $0))) }))
    let hiddenItems = HiddenItems(promo: dismissed)
    __PROXY_LIST_GATE__
    return items
}

private final class VideoView {
    var message: Message? = 1
    func set(adMessage: Message?, arguments: NSObject?, animated: Bool) { message = adMessage }
}

private final class VideoController {
    let context = Context()
    let genericView = VideoView()
    let nextAdDisposable = MetaDisposable()
    var adContext: NSObject? = NSObject()
    var controlsUpdates = 0
    func updateControlVisibility() { controlsUpdates += 1 }
    func pendingAd() -> () -> Void {
        let context = self.context
        let messages = [1, 2]
        let index = 0
        let arguments = NSObject()
        return { [weak self] in
            __DELAYED_VIDEO_AD__
        }
    }
    func updateAdsEnabled(_ value: Bool) {
        let action: (Bool) -> Void = { [weak self] enabled in
            __VIDEO_CLEAR__
        }
        action(value)
    }
}

final class SponsoredMessagePresentationTests: XCTestCase {
    func testBotHeaderRespectsTheSwitchAndExistingHistoryThreshold() {
        XCTAssertNil(botAd(hidden: true, count: 10))
        XCTAssertEqual(botAd(hidden: false, count: 2), 10)
        XCTAssertNil(botAd(hidden: false, count: 1))
        XCTAssertNil(botAd(hidden: false, count: nil))
    }

    func testProxyHeaderRespectsTheSwitch() {
        XCTAssertFalse(proxyPromo(hidden: true))
        XCTAssertTrue(proxyPromo(hidden: false))
    }

    func testSearchHidesSponsoredPeerWithoutRemovingItsOrganicResult() {
        let peer = FoundPeer(peer: Peer(id: 1))
        let entries: [Entry] = [.globalPeer(peer, 0, 0, AdPeer()), .globalPeer(peer, 0, 1, nil)]
        let visible = visibleSearchEntries(entries, hidden: true)
        XCTAssertEqual(visible.count, 1)
        guard case let .globalPeer(_, _, _, adPeer)? = visible.first else { return XCTFail("Expected organic peer") }
        XCTAssertNil(adPeer)
        guard case let .globalPeer(_, _, _, enabledAd)? = visibleSearchEntries(entries, hidden: false).first else { return XCTFail("Expected sponsored peer") }
        XCTAssertNotNil(enabledAd)
    }

    func testSearchPreservesOrdinaryDeduplicationAndMessageFilters() {
        let peer = Peer(id: 1)
        let entries: [Entry] = [.savedMessages(peer), .globalPeer(FoundPeer(peer: peer), 0, 0, nil), .message(99, "", nil, nil, 0), .message(2, "", nil, nil, 1)]
        XCTAssertEqual(visibleSearchEntries(entries, hidden: true).count, 2)
        XCTAssertEqual(visibleSearchEntries(entries, hidden: false).count, 2)
    }

    func testChannelFixedAndDynamicAdsRemainFiltered() {
        let hidden = channelAds(1, [2, 3], hidden: true)
        XCTAssertNil(hidden.0)
        XCTAssertTrue(hidden.1.isEmpty)
        let enabled = channelAds(1, [2, 3], hidden: false)
        XCTAssertEqual(enabled.0, 1)
        XCTAssertEqual(enabled.1, [2, 3])
    }

    func testProxyListRemainsFilteredWithoutLosingDismissedItems() {
        XCTAssertTrue(proxyRows(hidden: true, dismissed: []).isEmpty)
        XCTAssertEqual(proxyRows(hidden: false, dismissed: [1]).map { $0.item.renderedPeer.peerId }, [2])
    }

    func testDelayedVideoAdChecksTheLatestPreferenceBeforeShowing() {
        let controller = VideoController()
        let pending = controller.pendingAd()
        RegramPreferences.shared.hidden = true
        pending()
        XCTAssertEqual(controller.genericView.message, 1)
        RegramPreferences.shared.hidden = false
        pending()
        XCTAssertEqual(controller.genericView.message, 2)
    }

    func testVideoHideImmediatelyClearsOverlayContextAndPendingTimer() {
        let controller = VideoController()
        var cancelled = false
        controller.nextAdDisposable.set(ActionDisposable { cancelled = true })
        controller.updateAdsEnabled(true)
        XCTAssertNotNil(controller.adContext)
        XCTAssertEqual(controller.genericView.message, 1)
        controller.updateAdsEnabled(false)
        XCTAssertTrue(cancelled)
        XCTAssertNil(controller.adContext)
        XCTAssertNil(controller.genericView.message)
        XCTAssertEqual(controller.controlsUpdates, 1)
    }
}
