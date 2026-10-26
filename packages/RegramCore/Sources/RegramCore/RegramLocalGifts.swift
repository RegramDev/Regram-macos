import Foundation

public enum RGLocalGiftCurrency: String, Codable {
    case stars, ton

    public func amount(from text: String) -> Int64? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if self == .stars {
            guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }), let value = Int64(text), value <= RGLocalGiftsStore.maximumBalance else { return nil }
            return value
        }
        let parts = text.replacingOccurrences(of: ",", with: ".").split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), !parts[0].isEmpty,
              parts.allSatisfy({ $0.utf8.allSatisfy({ (48...57).contains($0) }) }),
              let whole = Int64(parts[0]), parts.count == 1 || parts[1].count <= 9 else { return nil }
        let fraction = parts.count == 2 ? String(parts[1]) : ""
        let (base, overflow) = whole.multipliedReportingOverflow(by: 1_000_000_000)
        guard !overflow, let nanos = Int64(fraction + String(repeating: "0", count: 9 - fraction.count)) else { return nil }
        let (value, addedOverflow) = base.addingReportingOverflow(nanos)
        return !addedOverflow && value <= RGLocalGiftsStore.maximumBalance ? value : nil
    }

    public func text(for amount: Int64) -> String {
        guard self == .ton else { return String(amount) }
        let fraction = String(String(amount % 1_000_000_000 + 1_000_000_000).dropFirst()).replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
        return String(amount / 1_000_000_000) + (fraction.isEmpty ? "" : "." + fraction)
    }
}

public struct RGLocalGiftPurchase: Codable, Equatable {
    public let id: UUID
    public let date: Int32
    public let title: String
    public let price: Int64
    public let gift: Data
    public let currency: RGLocalGiftCurrency
    public var savedToProfile: Bool
    public var pinnedToTop: Bool

    private enum CodingKeys: String, CodingKey { case id, date, title, price, gift, currency, savedToProfile, pinnedToTop }
    public init(id: UUID, date: Int32, title: String, price: Int64, gift: Data, currency: RGLocalGiftCurrency = .stars, savedToProfile: Bool = true, pinnedToTop: Bool = false) {
        self.id = id; self.date = date; self.title = title; self.price = price; self.gift = gift
        self.currency = currency; self.savedToProfile = savedToProfile; self.pinnedToTop = pinnedToTop
    }
    public init(from decoder: Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try value.decode(UUID.self, forKey: .id), date: try value.decode(Int32.self, forKey: .date),
            title: try value.decode(String.self, forKey: .title), price: try value.decode(Int64.self, forKey: .price), gift: try value.decode(Data.self, forKey: .gift),
            currency: try value.decodeIfPresent(RGLocalGiftCurrency.self, forKey: .currency) ?? .stars,
            savedToProfile: try value.decodeIfPresent(Bool.self, forKey: .savedToProfile) ?? true,
            pinnedToTop: try value.decodeIfPresent(Bool.self, forKey: .pinnedToTop) ?? false)
    }
}

public struct RGLocalGiftsState: Codable, Equatable {
    public var enabled = false
    public var balance: Int64 = 10000
    public var tonBalance: Int64 = 1_000_000_000_000
    public var purchases: [RGLocalGiftPurchase] = []
    public var profileGiftId: UUID?
    public var nameGiftId: UUID?
    public var appearance: Data?
    public var phoneEnabled = false
    public var phoneNumber = ""
    public var ratingEnabled = false
    public var ratingLevel: Int32 = 0
    public var walletCardEnabled = false
    public init() {}
    private enum CodingKeys: String, CodingKey { case enabled, balance, tonBalance, purchases, profileGiftId, nameGiftId, appearance, phoneEnabled, phoneNumber, ratingEnabled, ratingLevel, walletCardEnabled }
    public init(from decoder: Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try value.decode(Bool.self, forKey: .enabled)
        balance = try value.decode(Int64.self, forKey: .balance)
        purchases = try value.decode([RGLocalGiftPurchase].self, forKey: .purchases)
        tonBalance = try value.decodeIfPresent(Int64.self, forKey: .tonBalance) ?? 1_000_000_000_000
        profileGiftId = try value.decodeIfPresent(UUID.self, forKey: .profileGiftId)
        nameGiftId = try value.decodeIfPresent(UUID.self, forKey: .nameGiftId)
        appearance = try value.decodeIfPresent(Data.self, forKey: .appearance)
        phoneEnabled = try value.decodeIfPresent(Bool.self, forKey: .phoneEnabled) ?? false
        phoneNumber = try value.decodeIfPresent(String.self, forKey: .phoneNumber) ?? ""
        ratingEnabled = try value.decodeIfPresent(Bool.self, forKey: .ratingEnabled) ?? false
        ratingLevel = try value.decodeIfPresent(Int32.self, forKey: .ratingLevel) ?? 0
        walletCardEnabled = try value.decodeIfPresent(Bool.self, forKey: .walletCardEnabled) ?? false
    }
}

public enum RGLocalGiftsError: Error {
    case disabled, invalidAmount, insufficientStars, insufficientTon, limitReached, pinnedLimitReached, storage
}

public func regramLocalDisplayedPhone(accountId: Int64, peerId: Int64, testingEnvironment: Bool, phone: String?) -> String? {
    guard accountId == peerId else { return phone }
    let state = RGLocalGiftsStore.shared.state(account: RGLocalGiftsStore.accountKey(accountId: accountId, testingEnvironment: testingEnvironment))
    return state.phoneEnabled ? state.phoneNumber : phone
}

public final class RGLocalGiftsStore {
    public static let shared = RGLocalGiftsStore()
    public static let didChange = Notification.Name("Regram.LocalGifts.DidChange")
    public static let committedStateKey = "Regram.LocalGifts.CommittedState"
    public static let maximumBalance: Int64 = 9_000_000_000_000_000
    public static let maximumGifts = 500
    public static let maximumPinnedGifts = 12
    public static let maximumRatingLevel: Int32 = 999

    public static func accountKey(accountId: Int64, testingEnvironment: Bool) -> String {
        (testingEnvironment ? "test:" : "live:") + String(accountId)
    }
    private let defaults: UserDefaults
    private let notifications: NotificationCenter
    private let lock = NSLock()
    private var cached: [String: (data: Data, state: RGLocalGiftsState)] = [:]

    public init(defaults: UserDefaults = .standard, notifications: NotificationCenter = .default) {
        self.defaults = defaults
        self.notifications = notifications
    }

    private func key(_ account: String) -> String { "regram.localGifts.v1." + account }

    private func read(_ account: String) throws -> RGLocalGiftsState {
        guard let data = defaults.data(forKey: key(account)) else {
            cached.removeValue(forKey: account)
            return RGLocalGiftsState()
        }
        if let entry = cached[account], entry.data == data { return entry.state }
        guard data.count <= 16 * 1024 * 1024,
              let state = try? JSONDecoder().decode(RGLocalGiftsState.self, from: data),
              (0...Self.maximumBalance).contains(state.balance), (0...Self.maximumBalance).contains(state.tonBalance), state.purchases.count <= Self.maximumGifts,
              Set(state.purchases.map(\.id)).count == state.purchases.count,
              (state.appearance?.count ?? 0) <= 64 * 1024,
              (!state.phoneEnabled || Self.normalizedPhone(state.phoneNumber) == state.phoneNumber),
              (-Self.maximumRatingLevel...Self.maximumRatingLevel).contains(state.ratingLevel),
              state.purchases.filter(\.pinnedToTop).count <= Self.maximumPinnedGifts,
              state.purchases.allSatisfy({ !$0.pinnedToTop || $0.savedToProfile }),
              state.purchases.allSatisfy({ $0.price > 0 && $0.price <= Self.maximumBalance && !$0.gift.isEmpty && $0.gift.count <= 1024 * 1024 }) else {
            throw RGLocalGiftsError.storage
        }
        cached[account] = (data, state)
        return state
    }

    public func state(account: String) -> RGLocalGiftsState {
        lock.lock(); defer { lock.unlock() }
        return (try? read(account)) ?? RGLocalGiftsState()
    }

    @discardableResult private func update(account: String, _ change: (inout RGLocalGiftsState) throws -> Void) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
        lock.lock()
        let result: Result<RGLocalGiftsState, RGLocalGiftsError>
        do {
            var state = try read(account)
            try change(&state)
            let encoded = try JSONEncoder().encode(state)
            guard encoded.count <= 16 * 1024 * 1024 else { throw RGLocalGiftsError.limitReached }
            defaults.set(encoded, forKey: key(account))
            cached[account] = (encoded, state)
            result = .success(state)
        } catch let error as RGLocalGiftsError { result = .failure(error) }
        catch { result = .failure(.storage) }
        lock.unlock()
        if case let .success(state) = result {
            notifications.post(name: Self.didChange, object: account, userInfo: [Self.committedStateKey: state])
        }
        return result
    }

    public func setEnabled(account: String, enabled: Bool) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
        update(account: account) { $0.enabled = enabled }
    }

    public func setBalance(account: String, balance: Int64, currency: RGLocalGiftCurrency = .stars) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
        update(account: account) { state in
            guard (0...Self.maximumBalance).contains(balance) else { throw RGLocalGiftsError.invalidAmount }
            if currency == .stars { state.balance = balance } else { state.tonBalance = balance }
        }
    }

    public func purchase(account: String, title: String, price: Int64, gift: Data, currency: RGLocalGiftCurrency = .stars) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
        update(account: account) { state in
            guard state.enabled else { throw RGLocalGiftsError.disabled }
            guard price > 0 && price <= Self.maximumBalance && !gift.isEmpty && gift.count <= 1024 * 1024 else { throw RGLocalGiftsError.invalidAmount }
            guard state.purchases.count < Self.maximumGifts else { throw RGLocalGiftsError.limitReached }
            if currency == .stars {
                guard state.balance >= price else { throw RGLocalGiftsError.insufficientStars }
                state.balance -= price
            } else {
                guard state.tonBalance >= price else { throw RGLocalGiftsError.insufficientTon }
                state.tonBalance -= price
            }
            let purchase = RGLocalGiftPurchase(id: UUID(), date: Int32(clamping: Int64(Date().timeIntervalSince1970)), title: String(title.prefix(256)), price: price, gift: gift, currency: currency)
            state.purchases.insert(purchase, at: 0)
        }
    }

    public func upgrade(account: String, id: UUID, expectedGift: Data, title: String, gift: Data, stars: Int64) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
        update(account: account) { state in
            guard state.enabled else { throw RGLocalGiftsError.disabled }
            guard let index = state.purchases.firstIndex(where: { $0.id == id }), state.purchases[index].gift == expectedGift else { throw RGLocalGiftsError.storage }
            let original = state.purchases[index]
            guard original.currency == .stars, stars >= 0, stars <= Self.maximumBalance - original.price,
                  !gift.isEmpty, gift.count <= 1024 * 1024, gift != expectedGift else { throw RGLocalGiftsError.invalidAmount }
            guard state.balance >= stars else { throw RGLocalGiftsError.insufficientStars }
            state.balance -= stars
            state.purchases[index] = RGLocalGiftPurchase(id: original.id, date: original.date, title: String(title.prefix(256)),
                price: original.price + stars, gift: gift, currency: original.currency,
                savedToProfile: original.savedToProfile, pinnedToTop: original.pinnedToTop)
        }
    }

    public func remove(account: String, id: UUID, mediaIds: Set<Int64> = [], expectedGift: Data? = nil) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
        update(account: account) { state in
            if let expectedGift {
                guard state.enabled else { throw RGLocalGiftsError.disabled }
                guard state.purchases.contains(where: { $0.id == id && $0.gift == expectedGift }) else { throw RGLocalGiftsError.storage }
            }
            state.purchases.removeAll { $0.id == id }
            let removesProfile = state.profileGiftId == id
            let removesName = state.nameGiftId == id
            if removesProfile { state.profileGiftId = nil }
            if removesName { state.nameGiftId = nil }
            if removesProfile || removesName || !mediaIds.isEmpty, let data = state.appearance {
                if var fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    if removesProfile { fields.removeValue(forKey: "emojiStatus") }
                    if removesName { fields.removeValue(forKey: "nameCollectible") }
                    for key in ["replyFileId", "backgroundFileId"] {
                        if let value = fields[key] as? NSNumber, mediaIds.contains(value.int64Value) { fields.removeValue(forKey: key) }
                    }
                    state.appearance = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
                } else {
                    state.appearance = nil
                }
            }
        }
    }

    public func setAppearance(account: String, profileGiftId: UUID?, nameGiftId: UUID?, appearance: Data?, expectedGift: Data? = nil, expectedGiftId: UUID? = nil) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
        update(account: account) { state in
            guard state.enabled else { throw RGLocalGiftsError.disabled }
            if let expectedGift {
                guard let expectedGiftId, state.purchases.contains(where: { $0.id == expectedGiftId && $0.gift == expectedGift }) else { throw RGLocalGiftsError.storage }
            }
            let ids = Set(state.purchases.map(\.id))
            guard profileGiftId.map(ids.contains) ?? true, nameGiftId.map(ids.contains) ?? true else { throw RGLocalGiftsError.storage }
            guard (appearance?.count ?? 0) <= 64 * 1024 else { throw RGLocalGiftsError.storage }
            state.profileGiftId = profileGiftId; state.nameGiftId = nameGiftId; state.appearance = appearance
        }
    }

    public static func normalizedPhone(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
        let digits = value.hasPrefix("+") ? String(value.dropFirst()) : value
        guard (5...20).contains(digits.count), digits.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        return digits
    }

    public static func normalizedPhone(countryCode: String, number: String) -> String? {
        let code = countryCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = code.hasPrefix("+") ? String(code.dropFirst()) : code
        guard (1...3).contains(digits.count), digits.first != "0", digits.utf8.allSatisfy({ (48...57).contains($0) }),
              !number.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !number.contains("+") else { return nil }
        return normalizedPhone(digits + number)
    }

    public func setPhone(account: String, enabled: Bool, number: String) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
        update(account: account) { state in
            guard let phone = Self.normalizedPhone(number) ?? (enabled ? nil : "") else { throw RGLocalGiftsError.invalidAmount }
            state.phoneNumber = phone; state.phoneEnabled = enabled
        }
    }

    public func setVisibility(account: String, id: UUID, saved: Bool, expectedGift: Data? = nil) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
        update(account: account) { state in
            guard let index = state.purchases.firstIndex(where: { $0.id == id }) else { throw RGLocalGiftsError.storage }
            if let expectedGift {
                guard state.enabled else { throw RGLocalGiftsError.disabled }
                guard state.purchases[index].gift == expectedGift else { throw RGLocalGiftsError.storage }
            }
            state.purchases[index].savedToProfile = saved
            if !saved { state.purchases[index].pinnedToTop = false }
        }
    }

    public func setPinned(account: String, id: UUID, pinned: Bool, maximumCount: Int = RGLocalGiftsStore.maximumPinnedGifts, expectedGift: Data? = nil) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
        update(account: account) { state in
            guard state.enabled else { throw RGLocalGiftsError.disabled }
            guard let index = state.purchases.firstIndex(where: { $0.id == id }) else { throw RGLocalGiftsError.storage }
            if let expectedGift, state.purchases[index].gift != expectedGift { throw RGLocalGiftsError.storage }
            if pinned && !state.purchases[index].pinnedToTop {
                guard state.purchases.filter(\.pinnedToTop).count < min(Self.maximumPinnedGifts, max(0, maximumCount)) else { throw RGLocalGiftsError.pinnedLimitReached }
            }
            state.purchases[index].pinnedToTop = pinned
            if pinned { state.purchases[index].savedToProfile = true }
        }
    }

    public func setRating(account: String, enabled: Bool, level: Int32) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
        update(account: account) { state in
            guard (-Self.maximumRatingLevel...Self.maximumRatingLevel).contains(level) else { throw RGLocalGiftsError.invalidAmount }
            state.ratingEnabled = enabled; state.ratingLevel = level
        }
    }

    public func setWalletCardEnabled(account: String, enabled: Bool) -> Result<RGLocalGiftsState, RGLocalGiftsError> {
        update(account: account) { state in state.walletCardEnabled = enabled }
    }

    public func removeAccount(account: String) {
        lock.lock()
        defaults.removeObject(forKey: key(account))
        cached.removeValue(forKey: account)
        lock.unlock()
        notifications.post(name: Self.didChange, object: account, userInfo: [Self.committedStateKey: RGLocalGiftsState()])
    }
}
