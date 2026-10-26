import Foundation
import TelegramCore
import Postbox
import TelegramContext
import SwiftSignalKit
import RegramCore
import Localization

public func regramLocalGiftsEnabled(context: any AccountContextProtocol) -> Bool {
    RGLocalGiftsStore.shared.state(account: regramLocalGiftsAccount(context: context)).enabled
}

public func regramLocalGiftBalance(context: any AccountContextProtocol, ton: Bool = false) -> Int64? {
    let state = RGLocalGiftsStore.shared.state(account: regramLocalGiftsAccount(context: context))
    return state.enabled ? (ton ? state.tonBalance : state.balance) : nil
}

public func regramGiftStarsBalance(context: any AccountContextProtocol, source: Signal<StarsContext.State?, NoError>) -> Signal<StarsAmount, NoError> {
    combineLatest(source, regramLocalGiftsState(context: context)) |> map { remote, local in
        local.enabled ? StarsAmount(value: local.balance, nanos: 0) : (remote?.balance ?? .zero)
    } |> deliverOnMainQueue
}

public func regramGiftTonBalance(context: any AccountContextProtocol, source: Signal<StarsContext.State?, NoError>) -> Signal<StarsAmount, NoError> {
    combineLatest(source, regramLocalGiftsState(context: context)) |> map { remote, local in
        local.enabled ? StarsAmount(value: local.tonBalance, nanos: 0) : (remote?.balance ?? .zero)
    } |> deliverOnMainQueue
}

private let fallbackId: Int64 = -84631001

public func regramLocalFallbackGift() -> StarGift.Gift? {
    guard let path = Bundle.module.path(forResource: "RegramLocalGift", ofType: "tgs") else { return nil }
    let file = TelegramMediaFile(
        fileId: .init(namespace: 0, id: fallbackId), partialReference: nil,
        resource: LocalFileReferenceMediaResource(localFilePath: path, randomId: fallbackId),
        previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil,
        mimeType: "application/x-tgsticker", size: nil,
        attributes: [.FileName(fileName: "local_gift.tgs"), .Animated], alternativeRepresentations: []
    )
    return StarGift.Gift(id: fallbackId, title: nil, file: file, price: 100, convertStars: 0,
        availability: nil, soldOut: nil, flags: [], upgradeStars: nil, releasedBy: nil,
        perUserLimit: nil, lockedUntilDate: nil, auctionSlug: nil, auctionGiftsPerRound: nil,
        auctionStartDate: nil, upgradeVariantsCount: nil, background: nil)
}

public func regramLocalGiftTitle(_ gift: StarGift.Gift, language: String) -> String {
    gift.title ?? regramLocalizedString("LocalGifts.Gift", languageCode: language)
}

private func localAssets(context: any AccountContextProtocol) -> URL? {
    RGLocalGiftAssets.directory(account: regramLocalGiftsAccount(context: context))
}

private func localArtwork(_ file: TelegramMediaFile, path: String, id: Int64) -> TelegramMediaFile {
    TelegramMediaFile(fileId: .init(namespace: Namespaces.Media.CloudFile, id: id), partialReference: nil,
        resource: LocalFileReferenceMediaResource(localFilePath: path, randomId: id),
        previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: file.immediateThumbnailData,
        mimeType: file.mimeType, size: file.size, attributes: file.attributes, alternativeRepresentations: [])
}

private func localCopy(_ gift: StarGift.Gift, file: TelegramMediaFile) -> StarGift.Gift {
    StarGift.Gift(id: gift.id, title: gift.title, file: file, price: gift.price, convertStars: 0,
        availability: gift.availability, soldOut: nil, flags: gift.flags.subtracting([.isAuction, .requiresPremium]),
        upgradeStars: gift.upgradeStars, releasedBy: nil, perUserLimit: nil, lockedUntilDate: nil,
        auctionSlug: nil, auctionGiftsPerRound: nil, auctionStartDate: nil, upgradeVariantsCount: nil, background: gift.background)
}

public func regramCachedLocalGift(context: any AccountContextProtocol, gift: StarGift.Gift) -> StarGift.Gift? {
    let path: String?
    if let resource = gift.file.resource as? LocalFileReferenceMediaResource {
        path = FileManager.default.fileExists(atPath: resource.localFilePath) ? resource.localFilePath : nil
    } else {
        path = context.engine.resources.completedResourcePath(id: EngineMediaResource(gift.file.resource).id)
    }
    guard let path else { return nil }
    return localCopy(gift, file: localArtwork(gift.file, path: path, id: gift.id))
}

public func regramBuyLocalGift(context: any AccountContextProtocol, gift: StarGift.Gift) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
    regramBuyLocalGift(context: context, gift: .generic(gift), price: gift.price)
}

private func localUniqueCopy(_ gift: StarGift.UniqueGift, id: Int64, attributes: [StarGift.UniqueGift.Attribute], owner: EnginePeer.Id) -> StarGift.UniqueGift {
    var modelId: Int64?, patternId: Int64?, color: PeerCollectibleColor?
    for attribute in attributes {
        switch attribute {
        case let .model(_, file, _, _): modelId = file.fileId.id
        case let .pattern(_, file, _): patternId = file.fileId.id
        default: break
        }
    }
    for attribute in attributes {
        if case let .backdrop(_, _, inner, outer, pattern, text, _) = attribute, let modelId, let patternId {
            color = PeerCollectibleColor(collectibleId: id, giftEmojiFileId: modelId, backgroundEmojiId: patternId,
                accentColor: UInt32(bitPattern: text), colors: [UInt32(bitPattern: inner), UInt32(bitPattern: outer)],
                darkAccentColor: UInt32(bitPattern: pattern), darkColors: nil)
        }
    }
    return StarGift.UniqueGift(id: id, giftId: gift.giftId, title: gift.title, number: gift.number,
        slug: "", owner: .peerId(owner), attributes: attributes, availability: gift.availability,
        giftAddress: nil, resellAmounts: nil, resellForTonOnly: false, releasedBy: nil,
        valueAmount: nil, valueCurrency: nil, valueUsdAmount: nil, flags: [], themePeerId: nil,
        peerColor: color, hostPeerId: nil, minOfferStars: nil, craftChancePermille: nil)
}

private func localPattern(context: any AccountContextProtocol) -> TelegramMediaFile? {
    guard let directory = localAssets(context: context), let data = Data(base64Encoded: "H4sIAAAAAAAC/6tWKlOyUjLVM9czUdJRSitSsjI20FHKLFCyAlL5BRBuuZKVoQGQzoDSeblAPT75yYk5Cqm5BSWVCgWJJSWpRXlAE1JSUsBaE4uLU0uKlayiY3WUchIrU4vA7FoAhanBR28AAAA=") else { return nil }
    guard let url = RGLocalGiftAssets.asset(directory: directory, name: "empty-pattern.asset") else { return nil }
    do {
        try RGLocalGiftAssets.prepare(directory: directory)
        if !FileManager.default.fileExists(atPath: url.path) { try data.write(to: url, options: .atomic) }
    } catch { return nil }
    return TelegramMediaFile(fileId: .init(namespace: Namespaces.Media.CloudFile, id: -84631002), partialReference: nil,
        resource: LocalFileReferenceMediaResource(localFilePath: url.path, randomId: -84631002),
        previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "application/x-tgsticker",
        size: Int64(data.count), attributes: [.FileName(fileName: "local_pattern.tgs"), .Animated], alternativeRepresentations: [])
}

private func completeLocalAttributes(context: any AccountContextProtocol, attributes: [StarGift.UniqueGift.Attribute]) -> [StarGift.UniqueGift.Attribute] {
    if !attributes.contains(where: { if case .pattern = $0 { return true }; return false }), let pattern = localPattern(context: context) {
        return attributes + [.pattern(name: "", file: pattern, rarity: .rare)]
    }
    return attributes
}

public func regramBuyLocalGift(context: any AccountContextProtocol, gift: StarGift, price: Int64, currency: RGLocalGiftCurrency = .stars) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
    regramStoreLocalGift(context: context, gift: gift, price: price, currency: currency, upgrading: nil)
}

public func regramLocalGiftUpgradePrice(gift: StarGift.Gift, preview: StarGiftUpgradePreview, at timestamp: Int32) -> Int64? {
    let current = (preview.prices + preview.nextPrices).filter { $0.date <= timestamp }.max { $0.date < $1.date }
    return current?.stars ?? gift.upgradeStars
}

public func regramUpgradeLocalGift(context: any AccountContextProtocol, id: UUID, preview: StarGiftUpgradePreview, price: Int64, expectedGift: Data? = nil) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
    guard regramLocalGiftsEnabled(context: context) else { return .failure(.disabled) }
    guard let purchase = regramLocalGiftPurchase(context: context, id: id), case let .generic(gift) = regramLocalGift(context: context, purchase: purchase) else { return .failure(.storage) }
    if let expectedGift, purchase.gift != expectedGift { return .failure(.storage) }
    func cached(_ file: TelegramMediaFile) -> Bool {
        if let local = file.resource as? LocalFileReferenceMediaResource { return FileManager.default.fileExists(atPath: local.localFilePath) }
        return context.engine.resources.completedResourcePath(id: EngineMediaResource(file.resource).id) != nil
    }
    let models = preview.attributes.filter { if case let .model(_, file, _, _) = $0 { return cached(file) }; return false }
    let patterns = preview.attributes.filter { if case let .pattern(_, file, _) = $0 { return cached(file) }; return false }
    let backdrops = preview.attributes.filter { if case .backdrop = $0 { return true }; return false }
    guard let model = models.randomElement(), let backdrop = backdrops.randomElement() else { return .failure(.storage) }
    var attributes = [model, backdrop]
    if let pattern = patterns.randomElement() { attributes.append(pattern) }
    let total = max(1, gift.availability?.total ?? 1)
    let unique = StarGift.UniqueGift(id: -1, giftId: gift.id, title: gift.title ?? regramLocalGiftTitle(gift, language: appCurrentLanguage.primaryLanguage.languageCode),
        number: Int32.random(in: 1...total), slug: "", owner: .peerId(context.account.peerId), attributes: attributes,
        availability: .init(issued: total, total: total), giftAddress: nil, resellAmounts: nil, resellForTonOnly: false,
        releasedBy: nil, valueAmount: nil, valueCurrency: nil, valueUsdAmount: nil, flags: [], themePeerId: nil,
        peerColor: nil, hostPeerId: nil, minOfferStars: nil, craftChancePermille: nil)
    return regramStoreLocalGift(context: context, gift: .unique(unique), price: price, currency: .stars, upgrading: purchase)
}

private func regramStoreLocalGift(context: any AccountContextProtocol, gift: StarGift, price: Int64, currency: RGLocalGiftCurrency, upgrading: RGLocalGiftPurchase?) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
    guard regramLocalGiftsEnabled(context: context) else { return .failure(.disabled) }
    guard price > 0 || (upgrading != nil && price == 0) else { return .failure(.invalidAmount) }
    guard let directory = localAssets(context: context) else { return .failure(.storage) }
    var snapshots: [URL] = []
    var committed = false
    defer { if !committed { for path in snapshots { try? FileManager.default.removeItem(at: path) } } }
    do {
        try RGLocalGiftAssets.prepare(directory: directory)
        func snapshot(_ file: TelegramMediaFile) throws -> TelegramMediaFile {
            let path: String?
            if let resource = file.resource as? LocalFileReferenceMediaResource {
                path = resource.localFilePath
            } else {
                path = context.engine.resources.completedResourcePath(id: EngineMediaResource(file.resource).id)
            }
            guard let path else { throw RGLocalGiftsError.storage }
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            guard let size = attributes[.size] as? NSNumber, size.int64Value > 0, size.int64Value <= 8 * 1024 * 1024 else { throw RGLocalGiftsError.storage }
            guard let destination = RGLocalGiftAssets.asset(directory: directory, name: UUID().uuidString + ".asset") else { throw RGLocalGiftsError.storage }
            do {
                let data = try Data(contentsOf: URL(fileURLWithPath: path))
                guard !data.isEmpty, data.count <= 8 * 1024 * 1024 else { throw RGLocalGiftsError.storage }
                try data.write(to: destination, options: .atomic)
            } catch {
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
            snapshots.append(destination)
            return localArtwork(file, path: destination.path, id: Int64.random(in: Int64.min ... -1))
        }
        let stored: StarGift
        let title: String
        let language = appCurrentLanguage.primaryLanguage.languageCode
        switch gift {
        case let .generic(generic):
            let source = regramCachedLocalGift(context: context, gift: generic)?.file
            guard let source else { return .failure(.storage) }
            stored = .generic(localCopy(generic, file: try snapshot(source)))
            title = regramLocalGiftTitle(generic, language: language)
        case let .unique(unique):
            var attributes: [StarGift.UniqueGift.Attribute] = []
            var hasModel = false
            for attribute in unique.attributes {
                switch attribute {
                case let .model(name, file, rarity, crafted):
                    attributes.append(.model(name: name, file: try snapshot(file), rarity: rarity, crafted: crafted))
                    hasModel = true
                case let .pattern(name, file, rarity):
                    if let file = try? snapshot(file) { attributes.append(.pattern(name: name, file: file, rarity: rarity)) }
                case .backdrop:
                    attributes.append(attribute)
                case .originalInfo:
                    break
                }
            }
            guard hasModel else { return .failure(.storage) }
            stored = .unique(localUniqueCopy(unique, id: Int64.random(in: Int64.min ... -1), attributes: completeLocalAttributes(context: context, attributes: attributes), owner: context.account.peerId))
            title = unique.title + " #\(unique.number)"
        }
        let data = try JSONEncoder().encode(stored)
        let result: Result<RGLocalGiftsState, RGLocalGiftsError>
        if let upgrading {
            result = RGLocalGiftsStore.shared.upgrade(account: regramLocalGiftsAccount(context: context), id: upgrading.id, expectedGift: upgrading.gift, title: title, gift: data, stars: price)
        } else {
            result = RGLocalGiftsStore.shared.purchase(account: regramLocalGiftsAccount(context: context), title: title, price: price, gift: data, currency: currency)
        }
        if case .success = result { committed = true }
        return result
    } catch { return .failure(.storage) }
}

public func regramLocalGift(context: any AccountContextProtocol, purchase: RGLocalGiftPurchase) -> StarGift? {
    guard let gift = try? JSONDecoder().decode(StarGift.self, from: purchase.gift) else { return nil }
    func rebound(_ file: TelegramMediaFile) -> TelegramMediaFile? {
        guard let directory = localAssets(context: context), let resource = file.resource as? LocalFileReferenceMediaResource else { return nil }
        guard let asset = RGLocalGiftAssets.asset(directory: directory, name: URL(fileURLWithPath: resource.localFilePath).lastPathComponent) else { return nil }
        let path = asset.path
        if FileManager.default.fileExists(atPath: path) {
            let id = resource.randomId > 0 ? -resource.randomId : (resource.randomId == 0 ? -84631003 : resource.randomId)
            return localArtwork(file, path: path, id: id)
        }
        return nil
    }
    switch gift {
    case let .generic(generic):
        guard let file = rebound(generic.file) ?? regramLocalFallbackGift()?.file else { return nil }
        return .generic(localCopy(generic, file: file))
    case let .unique(unique):
        var attributes: [StarGift.UniqueGift.Attribute] = []
        var hasModel = false
        for attribute in unique.attributes {
            switch attribute {
            case let .model(name, file, rarity, crafted):
                if let file = rebound(file) { attributes.append(.model(name: name, file: file, rarity: rarity, crafted: crafted)); hasModel = true }
            case let .pattern(name, file, rarity):
                if let file = rebound(file) { attributes.append(.pattern(name: name, file: file, rarity: rarity)) }
            case .backdrop: attributes.append(attribute)
            case .originalInfo: break
            }
        }
        guard hasModel else { return nil }
        return .unique(localUniqueCopy(unique, id: unique.id, attributes: completeLocalAttributes(context: context, attributes: attributes), owner: context.account.peerId))
    }
}

public func regramRemoveLocalGift(context: any AccountContextProtocol, purchase: RGLocalGiftPurchase, expectedGift: Data? = nil) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
    var mediaIds = Set<Int64>()
    if case let .unique(gift) = regramLocalGift(context: context, purchase: purchase) {
        for attribute in gift.attributes {
            switch attribute {
            case let .model(_, file, _, _), let .pattern(_, file, _):
                if let resource = file.resource as? LocalFileReferenceMediaResource, URL(fileURLWithPath: resource.localFilePath).lastPathComponent != "empty-pattern.asset" {
                    mediaIds.insert(file.fileId.id)
                }
            default: break
            }
        }
    }
    let result = RGLocalGiftsStore.shared.remove(account: regramLocalGiftsAccount(context: context), id: purchase.id, mediaIds: mediaIds, expectedGift: expectedGift)
    if case .success = result, let gift = try? JSONDecoder().decode(StarGift.self, from: purchase.gift), let directory = localAssets(context: context) {
        let files: [TelegramMediaFile]
        switch gift {
        case let .generic(generic): files = [generic.file]
        case let .unique(unique): files = unique.attributes.compactMap { attribute in
            switch attribute {
            case let .model(_, file, _, _), let .pattern(_, file, _): return file
            default: return nil
            }
        }
        }
        for file in files {
            guard let resource = file.resource as? LocalFileReferenceMediaResource else { continue }
            guard let path = RGLocalGiftAssets.asset(directory: directory, name: URL(fileURLWithPath: resource.localFilePath).lastPathComponent), path.lastPathComponent != "empty-pattern.asset" else { continue }
            try? FileManager.default.removeItem(at: path)
        }
    }
    return result
}

public func regramLocalGiftPurchaseId(gift: ProfileGiftsContext.State.StarGift) -> UUID? {
    guard gift.reference == nil, let text = gift.text, text.hasPrefix("Regram.LocalGift:") else { return nil }
    return UUID(uuidString: String(text.dropFirst("Regram.LocalGift:".count)))
}

public func regramLocalGiftProfileState(context: any AccountContextProtocol, peerId: EnginePeer.Id, profileGifts: ProfileGiftsContext, canSelect: Bool) -> Signal<ProfileGiftsContext.State, NoError> {
    guard peerId == context.account.peerId, profileGifts.collectionId == nil, !canSelect else { return profileGifts.state }
    return combineLatest(profileGifts.state, regramLocalGiftsState(context: context)) |> map { remote, local in
        guard local.enabled else { return remote }
        var state = remote
        let gifts: [ProfileGiftsContext.State.StarGift] = local.purchases.compactMap { purchase in
            guard let gift = regramLocalGift(context: context, purchase: purchase) else { return nil }
            return regramLocalProfileGift(gift: gift, purchase: purchase)
        }
        let filtered = gifts.filter { item in
            guard state.filter.contains(item.savedToProfile ? .displayed : .hidden) else { return false }
            switch item.gift {
            case let .generic(gift):
                if state.filter.contains(.peerColor), !gift.flags.contains(.peerColorAvailable) { return false }
                if gift.availability == nil { return state.filter.contains(.unlimited) }
                return state.filter.contains(.limitedNonUpgradable)
            case let .unique(gift):
                if state.filter.contains(.peerColor), gift.peerColor == nil { return false }
                return state.filter.contains(.unique)
            }
        }
        let prices = Dictionary(uniqueKeysWithValues: local.purchases.filter { $0.currency == .stars }.map { ($0.id, $0.price) })
        func price(_ item: ProfileGiftsContext.State.StarGift) -> Int64? {
            if let id = regramLocalGiftPurchaseId(gift: item) { return prices[id] }
            switch item.gift {
            case let .generic(gift): return gift.price
            case let .unique(gift): return gift.resellAmounts?.first(where: { $0.currency == .stars })?.amount.value
            }
        }
        func merged(_ serverItems: [ProfileGiftsContext.State.StarGift], _ additions: [ProfileGiftsContext.State.StarGift]) -> [ProfileGiftsContext.State.StarGift] {
            var result = serverItems
            let sorted = additions.sorted { lhs, rhs in
                if lhs.pinnedToTop != rhs.pinnedToTop { return lhs.pinnedToTop }
                if remote.sorting == .value, let a = price(lhs), let b = price(rhs), a != b { return a > b }
                return lhs.date > rhs.date
            }
            for item in sorted {
                let index = result.firstIndex { other in
                    if item.pinnedToTop { return !other.pinnedToTop }
                    guard !other.pinnedToTop else { return false }
                    if remote.sorting == .value, let a = price(item), let b = price(other) { return a > b }
                    if remote.sorting == .value { return false }
                    return item.date > other.date
                } ?? result.endIndex
                result.insert(item, at: index)
            }
            return result
        }
        state.gifts = merged(remote.gifts, gifts)
        state.filteredGifts = merged(remote.filteredGifts, filtered)
        state.count = Int32(clamping: Int64(remote.count ?? Int32(clamping: remote.gifts.count)) + Int64(gifts.count))
        return state
    } |> deliverOnMainQueue
}

public func regramLocalProfileGift(gift: StarGift, purchase: RGLocalGiftPurchase) -> ProfileGiftsContext.State.StarGift {
    let canUpgrade: Bool
    if case let .generic(gift) = gift { canUpgrade = gift.upgradeStars != nil } else { canUpgrade = false }
    return ProfileGiftsContext.State.StarGift(gift: gift, reference: nil, fromPeer: nil,
        date: purchase.date, text: "Regram.LocalGift:" + purchase.id.uuidString, entities: nil,
        nameHidden: false, savedToProfile: purchase.savedToProfile, pinnedToTop: purchase.pinnedToTop, convertStars: nil,
        canUpgrade: canUpgrade, canExportDate: nil, upgradeStars: nil, transferStars: nil,
        canTransferDate: nil, canResaleDate: nil, collectionIds: nil, prepaidUpgradeHash: nil,
        upgradeSeparate: false, dropOriginalDetailsStars: nil, number: nil, isRefunded: false, canCraftAt: nil)
}

public func regramLocalGiftPurchase(context: any AccountContextProtocol, id: UUID) -> RGLocalGiftPurchase? {
    let state = RGLocalGiftsStore.shared.state(account: regramLocalGiftsAccount(context: context))
    return state.enabled ? state.purchases.first(where: { $0.id == id }) : nil
}

public func regramSetLocalGiftVisibility(context: any AccountContextProtocol, id: UUID, saved: Bool) {
    _ = RGLocalGiftsStore.shared.setVisibility(account: regramLocalGiftsAccount(context: context), id: id, saved: saved)
}

public func regramDeleteLocalGift(context: any AccountContextProtocol, id: UUID) {
    guard let purchase = regramLocalGiftPurchase(context: context, id: id) else { return }
    _ = regramRemoveLocalGift(context: context, purchase: purchase)
}

public func regramSetLocalGiftPinned(context: any AccountContextProtocol, id: UUID, pinned: Bool, profileGifts: ProfileGiftsContext? = nil, expectedGift: Data? = nil) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
    guard let purchase = regramLocalGiftPurchase(context: context, id: id), case .unique = regramLocalGift(context: context, purchase: purchase) else { return .failure(.storage) }
    let configuredLimit = context.appConfiguration.data?["stargifts_pinned_to_top_limit"] as? Double
    let limit: Int
    if let configuredLimit, configuredLimit.isFinite, configuredLimit >= 0 {
        limit = Int(min(Double(RGLocalGiftsStore.maximumPinnedGifts), configuredLimit))
    } else {
        limit = 6
    }
    let serverPins = profileGifts?.currentState?.gifts.filter { $0.pinnedToTop }.count ?? 0
    return RGLocalGiftsStore.shared.setPinned(account: regramLocalGiftsAccount(context: context), id: id, pinned: pinned, maximumCount: max(0, limit - serverPins), expectedGift: expectedGift)
}


public func regramIsLocalGift(_ gift: StarGift) -> Bool {
    switch gift {
    case let .generic(gift): return gift.id < 0 || gift.file.fileId.id < 0
    case let .unique(gift): return gift.id < 0 || gift.attributes.contains { attribute in
        switch attribute {
        case let .model(_, file, _, _), let .pattern(_, file, _): return file.fileId.id < 0
        default: return false
        }
    }
    }
}

public func regramLocalGiftPurchaseId(context: any AccountContextProtocol, gift: StarGift) -> UUID? {
    guard regramIsLocalGift(gift) else { return nil }
    let state = RGLocalGiftsStore.shared.state(account: regramLocalGiftsAccount(context: context))
    return state.purchases.first { purchase in
        guard let candidate = regramLocalGift(context: context, purchase: purchase) else { return false }
        switch (gift, candidate) {
        case let (.unique(first), .unique(second)): return first.id == second.id
        case let (.generic(first), .generic(second)): return first.file.fileId == second.file.fileId
        default: return false
        }
    }?.id
}
