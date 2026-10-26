import Foundation
import TelegramCore
import Postbox
import TelegramContext
import SwiftSignalKit
import RegramCore

private struct LocalAppearance: Codable {
    let namePreset: Int32?
    let nameCollectible: PeerCollectibleColor?
    let profileColor: Int32?
    let replyFileId: Int64?
    let backgroundFileId: Int64?
    let emojiStatus: PeerEmojiStatus?
}

public func regramSaveLocalGiftAppearance(context: any AccountContextProtocol, nameColor: PeerColor, profileColor: PeerNameColor?, replyFileId: Int64?, backgroundFileId: Int64?, emojiStatus: PeerEmojiStatus?, expectedGift: Data? = nil, expectedGiftId: UUID? = nil) -> Bool {
    let state = RGLocalGiftsStore.shared.state(account: regramLocalGiftsAccount(context: context))
    guard state.enabled else { return false }
    var profileGiftId: UUID?, nameGiftId: UUID?
    var namePreset: Int32?, nameCollectible: PeerCollectibleColor?
    switch nameColor {
    case let .preset(color): namePreset = color.rawValue
    case let .collectible(color): nameCollectible = color
    }
    for purchase in state.purchases {
        guard case let .unique(gift) = regramLocalGift(context: context, purchase: purchase) else { continue }
        if nameCollectible?.collectibleId == gift.id { nameGiftId = purchase.id }
        if case let .starGift(id, _, _, _, _, _, _, _, _) = emojiStatus?.content, id == gift.id { profileGiftId = purchase.id }
    }
    if let color = nameCollectible, color.collectibleId < 0, nameGiftId == nil { return false }
    if case let .starGift(id, _, _, _, _, _, _, _, _) = emojiStatus?.content, id < 0, profileGiftId == nil { return false }
    let appearance = LocalAppearance(namePreset: namePreset, nameCollectible: nameCollectible, profileColor: profileColor?.rawValue,
        replyFileId: replyFileId, backgroundFileId: backgroundFileId, emojiStatus: emojiStatus)
    guard let data = try? JSONEncoder().encode(appearance) else { return false }
    if case .success = RGLocalGiftsStore.shared.setAppearance(account: regramLocalGiftsAccount(context: context), profileGiftId: profileGiftId, nameGiftId: nameGiftId, appearance: data, expectedGift: expectedGift, expectedGiftId: expectedGiftId) { return true }
    return false
}

public func regramLocalAppearanceState(context: any AccountContextProtocol) -> Signal<RGLocalGiftsState, NoError> {
    regramLocalGiftsState(context: context) |> mapToSignal { state -> Signal<RGLocalGiftsState, NoError> in
        guard state.enabled else { return .single(state) }
        let files: [TelegramMediaFile] = state.purchases.flatMap { purchase -> [TelegramMediaFile] in
            guard case let .unique(gift) = regramLocalGift(context: context, purchase: purchase) else { return [] }
            return gift.attributes.compactMap { attribute -> TelegramMediaFile? in
                switch attribute {
                case let .model(_, file, _, _), let .pattern(_, file, _): return file
                default: return nil
                }
            }
        }
        return Signal<RGLocalGiftsState, NoError> { subscriber in
            regramCacheLocalGiftInlineStickers(context: context, files: files).start(completed: {
                subscriber.putNext(state)
                subscriber.putCompletion()
            })
        }
    } |> deliverOnMainQueue
}

public func regramLocalAppearancePeer(context: any AccountContextProtocol, peer: EnginePeer, localState: RGLocalGiftsState? = nil) -> EnginePeer {
    guard peer.id == context.account.peerId, case let .user(user) = peer else { return peer }
    let state = localState ?? RGLocalGiftsStore.shared.state(account: regramLocalGiftsAccount(context: context))
    guard state.enabled, let data = state.appearance, let appearance = try? JSONDecoder().decode(LocalAppearance.self, from: data) else { return peer }
    var emojiStatus = appearance.emojiStatus
    var nameColor = appearance.nameCollectible.map(PeerColor.collectible) ?? appearance.namePreset.map(PeerNameColor.init(rawValue:)).map(PeerColor.preset)
    if let id = state.profileGiftId, let purchase = state.purchases.first(where: { $0.id == id }), case let .unique(gift) = regramLocalGift(context: context, purchase: purchase) {
        emojiStatus = regramLocalGiftEmojiStatus(gift)
    }
    if let id = state.nameGiftId, let purchase = state.purchases.first(where: { $0.id == id }), case let .unique(gift) = regramLocalGift(context: context, purchase: purchase), let color = gift.peerColor {
        nameColor = .collectible(color)
    }
    let needsLocalPattern = [appearance.replyFileId, appearance.backgroundFileId].contains { ($0 ?? 0) < 0 }
    let localMediaIds: Set<Int64> = needsLocalPattern ? Set(regramLocalUniqueGifts(context: context, localState: state).flatMap { gift in
        gift.attributes.compactMap { attribute -> Int64? in
            switch attribute {
            case let .model(_, file, _, _), let .pattern(_, file, _): return file.fileId.id
            default: return nil
            }
        }
    }) : []
    func availablePattern(_ id: Int64?) -> Int64? {
        guard let id else { return nil }
        return id >= 0 || localMediaIds.contains(id) ? id : nil
    }
    return .user(user.withUpdatedNameColor(nameColor ?? user.nameColor ?? .preset(.blue)).withUpdatedBackgroundEmojiId(availablePattern(appearance.replyFileId))
        .withUpdatedProfileColor(appearance.profileColor.map(PeerNameColor.init(rawValue:)))
        .withUpdatedProfileBackgroundEmojiId(availablePattern(appearance.backgroundFileId)).withUpdatedEmojiStatus(emojiStatus))
}

public func regramLocalGiftEmojiStatus(_ gift: StarGift.UniqueGift) -> PeerEmojiStatus? {
    var modelId: Int64?, patternId: Int64?
    for attribute in gift.attributes {
        switch attribute {
        case let .model(_, file, _, _): modelId = file.fileId.id
        case let .pattern(_, file, _): patternId = file.fileId.id
        default: break
        }
    }
    for attribute in gift.attributes {
        if case let .backdrop(_, _, inner, outer, pattern, text, _) = attribute, let modelId, let patternId {
            return PeerEmojiStatus(content: .starGift(id: gift.id, fileId: modelId, title: gift.title, slug: "", patternFileId: patternId,
                innerColor: inner, outerColor: outer, patternColor: pattern, textColor: text), expirationDate: nil)
        }
    }
    return nil
}

public func regramLocalUniqueGifts(context: any AccountContextProtocol, localState: RGLocalGiftsState? = nil) -> [StarGift.UniqueGift] {
    let state = localState ?? RGLocalGiftsStore.shared.state(account: regramLocalGiftsAccount(context: context))
    guard state.enabled else { return [] }
    return state.purchases.compactMap { purchase in
        if case let .unique(gift) = regramLocalGift(context: context, purchase: purchase) { return gift }
        return nil
    }
}

public func regramIsLocalGiftAppearance(nameColor: PeerColor, emojiStatus: PeerEmojiStatus?) -> Bool {
    if case let .collectible(color) = nameColor, color.collectibleId < 0 { return true }
    if case let .starGift(id, _, _, _, _, _, _, _, _) = emojiStatus?.content, id < 0 { return true }
    return false
}

private func regramCacheLocalGiftInlineStickers(context: any AccountContextProtocol, files: [TelegramMediaFile]) -> Signal<Never, NoError> {
    context.account.postbox.transaction { transaction in
        for file in files where file.fileId.id < 0 && file.fileId.namespace == Namespaces.Media.CloudFile && file.resource is LocalFileReferenceMediaResource {
            if let existing = transaction.getMedia(file.fileId) {
                if !existing.isEqual(to: file) { _ = transaction.updateMedia(file.fileId, update: file) }
            } else {
                transaction.storeMediaIfNotPresent(media: file)
            }
        }
    } |> ignoreValues
}

public func regramWearLocalGift(context: any AccountContextProtocol, gift: StarGift.UniqueGift, wear: Bool, expectedGift: Data? = nil, expectedGiftId: UUID? = nil) -> Bool {
    guard gift.id < 0, gift.owner?.peerId == context.peerId, let raw = context.myPeer else { return false }
    let peer = regramLocalAppearancePeer(context: context, peer: EnginePeer(raw))._asPeer()
    return regramSaveLocalGiftAppearance(context: context, nameColor: peer.nameColor ?? .preset(.blue), profileColor: peer.profileColor, replyFileId: peer.backgroundEmojiId, backgroundFileId: peer.profileBackgroundEmojiId, emojiStatus: wear ? regramLocalGiftEmojiStatus(gift) : nil, expectedGift: expectedGift, expectedGiftId: expectedGiftId)
}

public func regramUseLocalGiftNameColor(context: any AccountContextProtocol, gift: StarGift.UniqueGift, expectedGift: Data? = nil, expectedGiftId: UUID? = nil) -> Bool {
    guard gift.id < 0, gift.owner?.peerId == context.peerId, let color = gift.peerColor, let raw = context.myPeer else { return false }
    let peer = regramLocalAppearancePeer(context: context, peer: EnginePeer(raw))._asPeer()
    return regramSaveLocalGiftAppearance(context: context, nameColor: .collectible(color), profileColor: peer.profileColor, replyFileId: color.backgroundEmojiId, backgroundFileId: peer.profileBackgroundEmojiId, emojiStatus: peer.emojiStatus, expectedGift: expectedGift, expectedGiftId: expectedGiftId)
}
