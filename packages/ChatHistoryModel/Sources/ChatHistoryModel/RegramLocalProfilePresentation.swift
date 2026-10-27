import TelegramCore
import Postbox
import TelegramContext
import RegramCore
import RegramSignals
import SwiftSignalKit

public func regramLocalGiftsAccount(context: any AccountContextProtocol) -> String {
    RGLocalGiftsStore.accountKey(accountId: context.peerId.toInt64(), testingEnvironment: context.account.testingEnvironment)
}

public func regramLocalGiftsState(context: any AccountContextProtocol) -> Signal<RGLocalGiftsState, NoError> {
    regramLocalGiftsChanges(account: regramLocalGiftsAccount(context: context))
}

public func regramLocalProfileGiftCount(accountPeerId: PeerId, peerId: PeerId, remoteCount: Int32, state: RGLocalGiftsState) -> Int32 {
    guard peerId == accountPeerId, state.enabled else { return remoteCount }
    return Int32(clamping: Int64(max(0, remoteCount)) + Int64(state.purchases.count))
}

public func regramLocalProfileCachedData(accountPeerId: PeerId, peerId: PeerId, cachedData: CachedPeerData?, state: RGLocalGiftsState) -> CachedPeerData? {
    guard peerId == accountPeerId, state.ratingEnabled || (state.enabled && state.walletCardEnabled) else { return cachedData }
    var result = (cachedData as? CachedUserData) ?? CachedUserData()
    if state.ratingEnabled {
        let level = state.ratingLevel
        let points = Int64(level) * 1_000
        let rating = TelegramStarRating(level: level, currentLevelStars: points, stars: points, nextLevelStars: level < 0 ? 0 : points + 1_000)
        result = result.withUpdatedStarRating(rating).withUpdatedPendingStarRating(nil)
    }
    if state.enabled && state.walletCardEnabled {
        result = result.withUpdatedWalletCard(WalletCard(address: "", balance: state.tonBalance, stickers: []))
    }
    return result
}

public func regramLocalProfileCachedData(context: any AccountContextProtocol, peerId: PeerId, cachedData: CachedPeerData?, localState: RGLocalGiftsState? = nil) -> CachedPeerData? {
    regramLocalProfileCachedData(accountPeerId: context.peerId, peerId: peerId, cachedData: cachedData, state: localState ?? RGLocalGiftsStore.shared.state(account: regramLocalGiftsAccount(context: context)))
}
