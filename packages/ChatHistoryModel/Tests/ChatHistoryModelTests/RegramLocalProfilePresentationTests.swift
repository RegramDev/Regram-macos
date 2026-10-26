import XCTest
import Postbox
import TelegramCore
import RegramCore
@testable import ChatHistoryModel

final class RegramLocalProfilePresentationTests: XCTestCase {
    private let accountId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))
    private let otherId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(2))

    private func serverData() -> CachedUserData {
        let rating = TelegramStarRating(level: 4, currentLevelStars: 4_000, stars: 4_500, nextLevelStars: 5_000)
        return CachedUserData().withUpdatedFlags(.copyProtectionEnabled)
            .withUpdatedStarRating(rating)
            .withUpdatedPendingStarRating(TelegramStarPendingRating(rating: rating, timestamp: 10))
            .withUpdatedWalletCard(WalletCard(address: "unit-test-address", balance: 7_000_000_000, stickers: []))
    }

    func testDisabledAndOtherPeerPresentationRetainsServerObjects() {
        let original = serverData()
        var state = RGLocalGiftsState()
        XCTAssertTrue(regramLocalProfileCachedData(accountPeerId: accountId, peerId: accountId, cachedData: original, state: state) === original)
        state.enabled = true
        state.ratingEnabled = true
        state.ratingLevel = -7
        state.walletCardEnabled = true
        XCTAssertTrue(regramLocalProfileCachedData(accountPeerId: accountId, peerId: otherId, cachedData: original, state: state) === original)
        XCTAssertNil(regramLocalProfileCachedData(accountPeerId: accountId, peerId: otherId, cachedData: nil, state: state))
    }

    func testLocalRatingHandlesZeroAndNegativeLevelsWithoutMutatingServerData() throws {
        let original = serverData()
        var state = RGLocalGiftsState()
        state.ratingEnabled = true
        for level: Int32 in [-999, -3, 0, 1, 999] {
            state.ratingLevel = level
            let projected = try XCTUnwrap(regramLocalProfileCachedData(accountPeerId: accountId, peerId: accountId, cachedData: original, state: state) as? CachedUserData)
            XCTAssertEqual(projected.starRating?.level, level)
            XCTAssertEqual(projected.starRating?.stars, Int64(level) * 1_000)
            XCTAssertNil(projected.pendingStarRating)
            XCTAssertEqual(projected.flags, original.flags)
            XCTAssertEqual(projected.walletCard?.address, original.walletCard?.address)
        }
        XCTAssertEqual(original.starRating?.level, 4)
        XCTAssertNotNil(original.pendingStarRating)
    }

    func testLocalWalletCardShowsZeroWithoutProvidingAReceivingAddress() throws {
        let original = serverData()
        var state = RGLocalGiftsState()
        state.enabled = true
        state.walletCardEnabled = true
        state.tonBalance = 0
        let projected = try XCTUnwrap(regramLocalProfileCachedData(accountPeerId: accountId, peerId: accountId, cachedData: original, state: state) as? CachedUserData)
        XCTAssertEqual(projected.walletCard?.balance, 0)
        XCTAssertEqual(projected.walletCard?.address, "")
        XCTAssertEqual(projected.starRating, original.starRating)
        XCTAssertEqual(projected.pendingStarRating, original.pendingStarRating)
        XCTAssertEqual(original.walletCard?.address, "unit-test-address")
        XCTAssertEqual(original.walletCard?.balance, 7_000_000_000)
        state.enabled = false
        XCTAssertTrue(regramLocalProfileCachedData(accountPeerId: accountId, peerId: accountId, cachedData: original, state: state) === original)
    }
}
