import XCTest
import TelegramCore
import Postbox
import WalletContext
import RegramCore
@testable import WalletUI

@available(macOS 10.15, *)
final class RegramLocalWalletDecorationsTests: XCTestCase {
    func testPinnedLocalDecorationsDiscardRemoteIdentitiesAndRespectNativeGeometry() throws {
        initializeAccountManagement()
        let file = TelegramMediaFile(fileId: .init(namespace: Namespaces.Media.CloudFile, id: -1), partialReference: nil,
            resource: LocalFileReferenceMediaResource(localFilePath: "/tmp/regram-wallet-test.tgs", randomId: -1), previewRepresentations: [],
            videoThumbnails: [], immediateThumbnailData: nil, mimeType: "application/x-tgsticker", size: nil,
            attributes: [.Animated], alternativeRepresentations: [])
        let gift = StarGift.UniqueGift(id: 123, giftId: 456, title: "Gift", number: 1, slug: "remote-gift", owner: .peerId(PeerId(1)),
            attributes: [.model(name: "Model", file: file, rarity: .rare, crafted: false), .pattern(name: "Pattern", file: file, rarity: .rare),
                         .backdrop(name: "Backdrop", id: 1, innerColor: 0x112233, outerColor: 0x334455, patternColor: 0x556677, textColor: 0xffffff, rarity: .rare)],
            availability: .init(issued: 1, total: 10), giftAddress: "remote-chain-address", resellAmounts: nil, resellForTonOnly: false,
            releasedBy: nil, valueAmount: nil, valueCurrency: nil, valueUsdAmount: nil, flags: [], themePeerId: nil, peerColor: nil,
            hostPeerId: nil, minOfferStars: nil, craftChancePermille: nil)
        var state = RGLocalGiftsState()
        state.enabled = true
        state.walletCardEnabled = true
        state.purchases = (0..<10).map { index in
            RGLocalGiftPurchase(id: UUID(), date: Int32(index), title: "Gift", price: 1, gift: Data([1]), savedToProfile: index != 0, pinnedToTop: index != 1)
        }
        let decorations = regramLocalWalletStickers(state: state, gift: { _ in .unique(gift) })
        XCTAssertEqual(decorations.count, 6)
        XCTAssertEqual(WalletContext.CardSticker.validated(decorations).count, 6)
        XCTAssertEqual(Set(decorations.map(\.gift.address)).count, 6)
        for (decoration, purchase) in zip(decorations, state.purchases.dropFirst(2)) {
            XCTAssertEqual(decoration.gift.address, "regram-local:" + purchase.id.uuidString)
            XCTAssertNil(decoration.gift.giftSlug)
            XCTAssertNil(decoration.gift.nft)
            let model = try XCTUnwrap(decoration.modelFile)
            XCTAssertTrue(try XCTUnwrap(PostboxDecoder(buffer: MemoryBuffer(data: model)).decodeRootObject() as? TelegramMediaFile).isEqual(to: file))
            XCTAssertNotNil(decoration.giftStyle?.patternFile)
        }
        state.walletCardEnabled = false
        XCTAssertTrue(regramLocalWalletStickers(state: state, gift: { _ in .unique(gift) }).isEmpty)
        state.walletCardEnabled = true
        state.enabled = false
        XCTAssertTrue(regramLocalWalletStickers(state: state, gift: { _ in .unique(gift) }).isEmpty)
    }

    func testLocalWalletVisibilityIsScopedToOwnerAndExplicitSwitchesAtZeroBalance() {
        var state = RGLocalGiftsState()
        state.enabled = true
        state.walletCardEnabled = true
        state.tonBalance = 0
        XCTAssertTrue(regramLocalWalletEnabled(accountId: 1, peerId: 1, state: state))
        XCTAssertFalse(regramLocalWalletEnabled(accountId: 1, peerId: 2, state: state))
        state.walletCardEnabled = false
        XCTAssertFalse(regramLocalWalletEnabled(accountId: 1, peerId: 1, state: state))
        state.walletCardEnabled = true
        state.enabled = false
        XCTAssertFalse(regramLocalWalletEnabled(accountId: 1, peerId: 1, state: state))
    }
}
