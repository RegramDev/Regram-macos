import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import InputDataUI
import AlertsUI
import RegramCore
import RegramSignals
import ChatHistoryModel
import PhoneNumberUtils

private struct RegramShowroomState: Equatable {
    var local: RGLocalGiftsState
    var phoneCode: String
    var phoneNumber: String
    var rating: String
    var stars: String
    var ton: String
}

public func RegramShowroomController(context: any AccountContextProtocol, focusSetting: String? = nil) -> InputDataController {
    let account = regramLocalGiftsAccount(context: context)
    let initial = RGLocalGiftsStore.shared.state(account: account)
    func phoneParts(_ number: String) -> (String, String) {
        let code = number.hasPrefix("888") ? "888" : (lookupCountryIdByNumber(number, configuration: PhoneNumberUtilsHooks.shared.currentCountriesConfiguration(context).with { $0 })?.1.code ?? "")
        return (code, String(number.dropFirst(code.count)))
    }
    let parts = phoneParts(initial.phoneNumber)
    let initialState = RegramShowroomState(local: initial, phoneCode: parts.0, phoneNumber: parts.1, rating: String(initial.ratingLevel), stars: String(initial.balance), ton: RGLocalGiftCurrency.ton.text(for: initial.tonBalance))
    let state = Atomic(value: initialState)
    let promise = ValuePromise(initialState, ignoreRepeated: true)
    let disposables = DisposableSet()
    func update(_ f: (inout RegramShowroomState) -> Void) {
        promise.set(state.modify { current in var current = current; f(&current); return current })
    }
    func result(_ value: Result<RGLocalGiftsState, RGLocalGiftsError>) {
        if case let .failure(error) = value { alert(for: context.window, info: regramLocalGiftError(error)) }
    }
    func savePhone(_ enabled: Bool) {
        let current = state.with { $0 }
        guard !enabled || RGLocalGiftsStore.normalizedPhone(countryCode: current.phoneCode, number: current.phoneNumber) != nil else { alert(for: context.window, info: regramString("LocalPhone.Invalid")); return }
        let number = enabled ? RGLocalGiftsStore.normalizedPhone(countryCode: current.phoneCode, number: current.phoneNumber)! : RGLocalGiftsStore.shared.state(account: account).phoneNumber
        result(RGLocalGiftsStore.shared.setPhone(account: account, enabled: enabled, number: number))
    }
    func saveRating(_ enabled: Bool) {
        let current = state.with { $0 }
        guard !enabled || Int32(current.rating.trimmingCharacters(in: .whitespacesAndNewlines)).map({ (-RGLocalGiftsStore.maximumRatingLevel...RGLocalGiftsStore.maximumRatingLevel).contains($0) }) == true else { alert(for: context.window, info: regramString("LocalRating.Invalid")); return }
        let level = enabled ? Int32(current.rating.trimmingCharacters(in: .whitespacesAndNewlines))! : RGLocalGiftsStore.shared.state(account: account).ratingLevel
        result(RGLocalGiftsStore.shared.setRating(account: account, enabled: enabled, level: level))
    }
    func saveBalance(_ currency: RGLocalGiftCurrency) {
        let current = state.with { $0 }
        guard let amount = currency.amount(from: currency == .stars ? current.stars : current.ton) else { alert(for: context.window, info: regramString("LocalGifts.InvalidAmount")); return }
        result(RGLocalGiftsStore.shared.setBalance(account: account, balance: amount, currency: currency))
    }
    disposables.add(regramLocalGiftsState(context: context).start(next: { local in
        update { current in
            if current.local.phoneNumber != local.phoneNumber { let parts = phoneParts(local.phoneNumber); current.phoneCode = parts.0; current.phoneNumber = parts.1 }
            if current.local.ratingLevel != local.ratingLevel { current.rating = String(local.ratingLevel) }
            if current.local.balance != local.balance { current.stars = String(local.balance) }
            if current.local.tonBalance != local.tonBalance { current.ton = RGLocalGiftCurrency.ton.text(for: local.tonBalance) }
            current.local = local
        }
    }))
    let signal = combineLatest(promise.get(), regramPreferenceChanges(accountId: context.peerId.toInt64()), appearanceSignal) |> map { state, settings, _ -> InputDataSignalValue in
        var page = RegramPageBuilder(page: "localGifts")
        page.section()
        page.row("localPremium", title: regramString("LocalPremium.Title"), type: .switchable(settings["localPremium"].bool), action: { RegramPreferences.shared.update(accountId: context.peerId.toInt64()) { $0["localPremium"] = .bool(!$0["localPremium"].bool) } })
        page.text(regramString("LocalPremium.Notice") + "\n" + regramString("Showroom.PremiumRefresh"))
        page.section("LocalPhone.Title")
        page.input("phone", value: state.phoneCode, title: "+ " + regramString("LocalPhone.CountryCode"), limit: 4)
        page.input("phoneNumber", value: state.phoneNumber, title: regramString("LocalPhone.Number"), limit: 40)
        page.row("phoneEnabled", title: regramString("LocalPhone.Enabled"), type: .switchable(state.local.phoneEnabled), action: { savePhone(!RGLocalGiftsStore.shared.state(account: account).phoneEnabled) })
        page.row("savePhone", title: regramString("LocalPhone.Save"), action: { savePhone(true) })
        page.text(regramString("LocalPhone.Hint"))
        page.section("LocalRating.Title")
        page.input("rating", value: state.rating, title: "", placeholder: regramString("LocalRating.Level"), limit: 6)
        page.row("ratingEnabled", title: regramString("LocalRating.Enabled"), type: .switchable(state.local.ratingEnabled), action: { saveRating(!RGLocalGiftsStore.shared.state(account: account).ratingEnabled) })
        page.row("saveRating", title: regramString("LocalRating.Save"), action: { saveRating(true) })
        page.text(regramString("LocalRating.Level") + "\n" + regramString("LocalRating.Hint"))
        page.section()
        page.row("enabled", title: regramString("LocalGifts.Enabled"), type: .switchable(state.local.enabled), action: { result(RGLocalGiftsStore.shared.setEnabled(account: account, enabled: !RGLocalGiftsStore.shared.state(account: account).enabled)) })
        page.text(regramString("LocalGifts.Notice"))
        if state.local.enabled {
            page.section("LocalGifts.Balance")
            page.input("balance", value: state.stars, title: "", placeholder: regramString("LocalGifts.Balance"), limit: 16)
            page.row("saveBalance", title: regramString("LocalGifts.SaveBalance"), action: { saveBalance(.stars) })
            page.row("currentBalance", title: regramString("LocalGifts.CurrentBalance"), type: .context(String(state.local.balance)))
            page.text(regramString("LocalGifts.BalanceHint") + "\n" + regramString("LocalGifts.NativeHint"))
            page.section("LocalGifts.TonBalance")
            page.input("tonBalance", value: state.ton, title: "", placeholder: regramString("LocalGifts.TonBalance"), limit: 26)
            page.row("saveTonBalance", title: regramString("LocalGifts.SaveTonBalance"), action: { saveBalance(.ton) })
            page.row("walletCard", title: regramString("LocalWallet.Enabled"), type: .switchable(state.local.walletCardEnabled), action: { result(RGLocalGiftsStore.shared.setWalletCardEnabled(account: account, enabled: !RGLocalGiftsStore.shared.state(account: account).walletCardEnabled)) })
            page.text(regramString("LocalGifts.TonHint") + "\n" + regramString("LocalWallet.Hint"))
        }
        return InputDataSignalValue(entries: page.entries)
    }
    let controller = RegramFormController(dataSignal: signal, title: regramString("Showroom.Title"), updateDatas: { values in
        update { current in
            if let value = values[InputDataIdentifier("localGifts.phone")]?.stringValue { current.phoneCode = value }
            if let value = values[InputDataIdentifier("localGifts.phoneNumber")]?.stringValue { current.phoneNumber = value }
            if let value = values[InputDataIdentifier("localGifts.rating")]?.stringValue { current.rating = value }
            if let value = values[InputDataIdentifier("localGifts.balance")]?.stringValue { current.stars = value }
            if let value = values[InputDataIdentifier("localGifts.tonBalance")]?.stringValue { current.ton = value }
        }
        return .fail(.none)
    }, removeAfterDisappear: false, hasDone: false, identifier: "regram.localGifts")
    controller.onDeinit = { disposables.dispose() }
    regramFocusSettings(controller, page: "localGifts", item: focusSetting)
    return controller
}


func regramLocalGiftError(_ error: RGLocalGiftsError) -> String {
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
    return regramString(key)
}
