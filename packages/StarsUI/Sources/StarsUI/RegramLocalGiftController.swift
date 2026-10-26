import Cocoa
import TGUIKit
import GeneralRows
import InputDataUI
import AlertsUI
import TelegramCore
import TelegramContext
import TelegramTheme
import SwiftSignalKit
import Localization
import RegramCore
import ChatHistoryModel

func regramGiftString(_ key: String) -> String {
    regramLocalizedString(key, languageCode: appCurrentLanguage.primaryLanguage.languageCode)
}

func regramGiftError(_ error: RGLocalGiftsError) -> String {
    let key: String
    switch error {
    case .disabled: key = "LocalGifts.Disabled"
    case .invalidAmount: key = "LocalGifts.InvalidAmount"
    case .insufficientStars: key = "LocalGifts.Insufficient"
    case .insufficientTon: key = "LocalGifts.InsufficientTon"
    case .limitReached: key = "LocalGifts.Limit"
    case .pinnedLimitReached: key = "LocalGifts.PinnedLimit"
    case .storage: key = "LocalGifts.StorageError"
    }
    return regramGiftString(key)
}

func regramPresentLocalGiftPurchase(context: any AccountContextProtocol, gift: StarGift, price: Int64, currency: RGLocalGiftCurrency = .stars, window: Window, completion: ((Bool) -> Void)? = nil) {
    switch regramBuyLocalGift(context: context, gift: gift, price: price, currency: currency) {
    case .success:
        alert(for: window, header: regramGiftString("LocalGifts.Success"), info: regramGiftString("LocalGifts.SuccessHint"), completion: { completion?(true) })
    case let .failure(error):
        alert(for: window, header: regramGiftString("LocalGifts.Title"), info: regramGiftError(error), completion: { completion?(false) })
    }
}

final class RegramLocalGiftDetails {
    let context: any AccountContextProtocol
    let purchaseId: UUID
    let initialGift: Data
    private let request = MetaDisposable()
    private var generation = 0
    private(set) var isActive = true

    func setActive(_ value: Bool) {
        isActive = value
        if !value {
            generation &+= 1
            request.set(nil)
        }
    }

    init?(context: any AccountContextProtocol, purchaseId: UUID?) {
        guard let purchaseId, let purchase = regramLocalGiftPurchase(context: context, id: purchaseId), regramLocalGift(context: context, purchase: purchase) != nil else { return nil }
        self.context = context
        self.purchaseId = purchaseId
        self.initialGift = purchase.gift
    }

    func current(state: RGLocalGiftsState? = nil) -> (purchase: RGLocalGiftPurchase, gift: StarGift)? {
        let state = state ?? RGLocalGiftsStore.shared.state(account: regramLocalGiftsAccount(context: context))
        guard state.enabled, let purchase = state.purchases.first(where: { $0.id == purchaseId }), purchase.gift == initialGift,
              let gift = regramLocalGift(context: context, purchase: purchase) else { return nil }
        return (purchase, gift)
    }

    func unavailable(window: Window) {
        guard isActive else { return }
        let key = current() != nil ? "LocalGifts.Notice" : regramLocalGiftsEnabled(context: context) ? "LocalGifts.StorageError" : "LocalGifts.Disabled"
        alert(for: window, info: regramGiftString(key))
    }

    func result(_ result: Result<RGLocalGiftsState, RGLocalGiftsError>, window: Window) {
        guard isActive else { return }
        if case let .failure(error) = result { alert(for: window, info: regramGiftError(error)) }
    }

    func toggleVisibility(window: Window) {
        guard isActive else { return }
        guard let current = current() else { unavailable(window: window); return }
        result(RGLocalGiftsStore.shared.setVisibility(account: regramLocalGiftsAccount(context: context), id: purchaseId, saved: !current.purchase.savedToProfile, expectedGift: initialGift), window: window)
    }

    func togglePin(window: Window, profileGifts: ProfileGiftsContext?) {
        guard isActive else { return }
        guard let current = current() else { unavailable(window: window); return }
        result(regramSetLocalGiftPinned(context: context, id: purchaseId, pinned: !current.purchase.pinnedToTop, profileGifts: profileGifts, expectedGift: initialGift), window: window)
    }

    func wear(_ wear: Bool, window: Window) -> Bool {
        guard isActive else { return false }
        guard let current = current(), case let .unique(gift) = current.gift else { unavailable(window: window); return false }
        if !wear {
            guard let raw = context.myPeer, case let .starGift(id, _, _, _, _, _, _, _, _)? = regramLocalAppearancePeer(context: context, peer: EnginePeer(raw)).emojiStatus?.content, id == gift.id else { return false }
        }
        guard regramWearLocalGift(context: context, gift: gift, wear: wear, expectedGift: initialGift, expectedGiftId: purchaseId) else { unavailable(window: window); return false }
        return true
    }

    func useNameColor(window: Window) {
        guard isActive else { return }
        guard let current = current(), case let .unique(gift) = current.gift else { unavailable(window: window); return }
        if !regramUseLocalGiftNameColor(context: context, gift: gift, expectedGift: initialGift, expectedGiftId: purchaseId) { unavailable(window: window) }
    }

    func remove(window: Window, completion: @escaping () -> Void) {
        guard isActive else { return }
        guard let current = current() else { unavailable(window: window); return }
        let token = generation
        verifyAlert(for: window, header: strings().giftDeleteTitle, information: regramGiftString("LocalGifts.RemoveHint"), ok: strings().modalDelete, successHandler: { [weak self] _ in
            guard let self, self.isActive, self.generation == token else { return }
            guard self.current()?.purchase == current.purchase else { self.unavailable(window: window); return }
            switch regramRemoveLocalGift(context: self.context, purchase: current.purchase, expectedGift: self.initialGift) {
            case .success: completion()
            case let .failure(error): alert(for: window, info: regramGiftError(error))
            }
        })
    }

    func upgrade(window: Window, completion: @escaping () -> Void) {
        guard isActive else { return }
        guard let current = current(), case let .generic(gift) = current.gift else { unavailable(window: window); return }
        generation &+= 1
        let token = generation
        request.set(showModalProgress(signal: context.engine.payments.starGiftUpgradePreview(giftId: gift.id) |> deliverOnMainQueue, for: window).start(next: { [weak self] preview in
            guard let self, self.isActive, self.generation == token else { return }
            guard self.current()?.purchase == current.purchase, let preview, let peer = self.context.myPeer else { self.unavailable(window: window); return }
            let controller = StarGift_Nft_Controller(context: self.context, gift: current.gift, source: .preview(EnginePeer(peer), preview), localUpgradePurchaseId: current.purchase.id, localUpgradeExpectedGift: current.purchase.gift)
            guard self.isActive, self.generation == token else { return }
            guard self.current()?.purchase == current.purchase else { self.unavailable(window: window); return }
            completion()
            showModal(with: controller, for: window)
        }))
    }

    deinit { request.dispose() }
}

func regramLocalGiftPurpose(gift: StarGift, purchase: RGLocalGiftPurchase) -> Star_TransactionPurpose {
    .starGift(gift: gift, convertStars: nil, text: nil, entities: nil, nameHidden: false, savedToProfile: purchase.savedToProfile, converted: false, fromProfile: true, upgraded: false, prepaidUpgradeHash: nil, transferStars: nil, canExportDate: nil, reference: nil, sender: nil, saverId: nil, canTransferDate: nil, canResaleDate: nil, dropOriginalDetailsStars: nil, canUpgrade: gift.generic?.upgradeStars != nil, number: nil, isRefunded: false, canCraftAt: nil, craftChancePermille: nil, upgradeStars: nil)
}

func regramUnavailableLocalGiftController(context: any AccountContextProtocol) -> InputDataModalController {
    let controller = InputDataController(dataSignal: .single(InputDataSignalValue(entries: [])), title: "", hasDone: false)
    let modal = InputDataModalController(controller)
    controller.didAppear = { [weak modal] _ in
        modal?.modal?.close()
        alert(for: context.window, info: regramGiftString(regramLocalGiftsEnabled(context: context) ? "LocalGifts.StorageError" : "LocalGifts.Disabled"))
    }
    return modal
}

func RegramLocalGiftController(context: any AccountContextProtocol, purchaseId: UUID?, profileGifts: ProfileGiftsContext? = nil) -> InputDataModalController {
    guard let details = RegramLocalGiftDetails(context: context, purchaseId: purchaseId), let current = details.current(), let me = context.myPeer else {
        return regramUnavailableLocalGiftController(context: context)
    }
    let owner = regramLocalAppearancePeer(context: context, peer: EnginePeer(me))
    let transaction = StarsContext.State.Transaction(flags: [.isLocal, .isGift], id: "", count: .init(amount: .init(value: current.purchase.price, nanos: 0), currency: current.purchase.currency == .ton ? .ton : .stars), date: current.purchase.date, peer: .peer(owner), title: nil, description: nil, photo: nil, transactionDate: nil, transactionUrl: nil, paidMessageId: nil, giveawayMessageId: nil, media: [], subscriptionPeriod: nil, starGift: current.gift, floodskipNumber: nil, starrefCommissionPermille: nil, starrefPeerId: nil, starrefAmount: nil, paidMessageCount: nil, premiumGiftMonths: nil, adsProceedsFromDate: nil, adsProceedsToDate: nil)
    let purpose = regramLocalGiftPurpose(gift: current.gift, purchase: current.purchase)
    if case let .unique(gift) = current.gift {
        return StarGift_Nft_Controller(context: context, gift: current.gift, source: .quickLook(owner, gift), transaction: transaction, purpose: purpose, giftsContext: profileGifts, localPurchaseId: current.purchase.id)
    }
    return Star_TransactionScreen(context: context, fromPeerId: context.peerId, peer: nil, transaction: transaction, purpose: purpose, profileContext: profileGifts, currency: transaction.count.currency, localPurchaseId: current.purchase.id)
}

public func regramPresentLocalGiftResale(context: any AccountContextProtocol, gift: StarGift.UniqueGift, window: Window, completion: ((StarGift?) -> Void)? = nil) {
    guard regramLocalGiftsEnabled(context: context), gift.id >= 0, let peer = context.myPeer else { alert(for: window, info: regramGiftString("LocalGifts.Disabled")); return }
    let amounts = gift.resellAmounts ?? []
    var currency: CurrencyAmount.Currency = gift.resellForTonOnly ? .ton : (amounts.contains { $0.currency == .stars } ? .stars : .ton)
    var refresh: ((ModalAlertData) -> Void)?
    func data() -> ModalAlertData {
        let price = amounts.first { $0.currency == currency }
        return ModalAlertData(title: strings().starNftGiftConfirmTitle, info: regramGiftString("LocalGifts.Notice"), description: nil, ok: strings().starNftGiftConfirmOk(price?.fullyFormatted ?? ""), options: [], mode: .confirm(text: strings().modalCancel, isThird: false), header: .init(id: "header", value: { size, stableId, _ in
            TransferUniqueGiftHeaderItem(size, stableId: stableId, gift: gift, toPeer: EnginePeer(peer), context: context, transferType: .buy(onlyTon: gift.resellForTonOnly), buyForSelected: currency, callback: { selected in currency = selected; refresh?(data()) })
        }), footer: .init(id: "footer", value: { size, stableId, _, _ in
            InputDataTableBasedItem(size, stableId: stableId, viewType: .singleItem, rows: getTransferAttributesRows(gift: gift), context: context)
        }))
    }
    showModalAlert(for: window, data: data(), completion: { _ in
        guard let price = amounts.first(where: { $0.currency == currency }), price.amount.nanos == 0, price.amount.value > 0 else { alert(for: window, info: regramGiftString("LocalGifts.InvalidAmount")); return }
        let result = regramBuyLocalGift(context: context, gift: .unique(gift), price: price.amount.value, currency: currency == .ton ? .ton : .stars)
        switch result {
        case let .success(local):
            let stored = local.purchases.first.flatMap { regramLocalGift(context: context, purchase: $0) }
            alert(for: window, header: regramGiftString("LocalGifts.Success"), info: regramGiftString("LocalGifts.SuccessHint"), completion: { completion?(stored) })
        case let .failure(error): alert(for: window, info: regramGiftError(error))
        }
    }, takeNewData: { refresh = $0 })
}
