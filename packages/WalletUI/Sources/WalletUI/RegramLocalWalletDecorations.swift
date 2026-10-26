import Foundation
import TelegramCore
import Postbox
import TelegramContext
import WalletContext
import ChatHistoryModel
import RegramCore

func regramLocalWalletEnabled(accountId: Int64, peerId: Int64, state: RGLocalGiftsState) -> Bool {
    accountId == peerId && state.enabled && state.walletCardEnabled
}

func regramLocalWalletEnabled(context: any AccountContextProtocol, peerId: PeerId) -> Bool {
    regramLocalWalletEnabled(accountId: context.peerId.toInt64(), peerId: peerId.toInt64(), state: RGLocalGiftsStore.shared.state(account: regramLocalGiftsAccount(context: context)))
}

func regramLocalWalletStickers(context: any AccountContextProtocol, state: RGLocalGiftsState) -> [WalletContext.CardSticker] {
    regramLocalWalletStickers(state: state, gift: { regramLocalGift(context: context, purchase: $0) })
}

func regramLocalWalletStickers(state: RGLocalGiftsState, gift: (RGLocalGiftPurchase) -> StarGift?) -> [WalletContext.CardSticker] {
    guard state.enabled && state.walletCardEnabled else { return [] }
    let gifts = state.purchases.filter { $0.savedToProfile && $0.pinnedToTop }.compactMap { purchase -> (RGLocalGiftPurchase, StarGift.UniqueGift)? in
        guard case let .unique(gift) = gift(purchase) else { return nil }
        return (purchase, gift)
    }.prefix(6)
    let positions: [(Double, Double, Double)] = [(0.16, 0.21, -0.18), (0.65, 0.19, 0.16), (0.86, 0.78, 0.18), (0.46, 0.79, -0.15), (0.89, 0.2, 0.12), (0.14, 0.78, -0.12)]
    return gifts.enumerated().compactMap { index, item in
        let (purchase, gift) = item
        var model: Data?
        var pattern: Data?
        for attribute in gift.attributes {
            switch attribute {
            case let .model(_, file, _, _): model = walletEncodedMediaFile(file)
            case let .pattern(_, file, _): pattern = walletEncodedMediaFile(file)
            default: break
            }
        }
        guard let model else { return nil }
        var style: WalletContext.CardGiftStyle?
        for case let .backdrop(_, _, inner, outer, color, _, _) in gift.attributes {
            style = .init(innerColor: inner, outerColor: outer, patternColor: color, patternFile: pattern)
        }
        let collectible = WalletContext.Collectible(address: "regram-local:" + purchase.id.uuidString, name: gift.title, subtitle: "", kind: .gift)
        let position = positions[index]
        return WalletContext.CardSticker(gift: collectible, x: position.0, y: position.1, angle: position.2, scale: 1, modelFile: model, geometryVersion: 2, giftStyle: style)
    }
}
