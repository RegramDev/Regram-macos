import Foundation

public struct RGGroupRemarkChange {
    public let accountId: Int64
    public let peerId: Int64
}

public final class RGGroupRemarks {
    public static let shared = RGGroupRemarks()
    public static let didChange = Notification.Name("Regram.GroupRemarks.DidChange")
    public static let maximumLength = 128
    private static let preferenceKey = "Regram.GroupRemarks.v1"

    private let defaults: UserDefaults
    private let notifications: NotificationCenter
    private let lock = NSLock()
    private var accounts: [String: [String: String]]
    private var revisions: [Int64: Int64] = [:]

    public init(defaults: UserDefaults = .standard, notifications: NotificationCenter = .default) {
        self.defaults = defaults
        self.notifications = notifications
        self.accounts = defaults.dictionary(forKey: Self.preferenceKey) as? [String: [String: String]] ?? [:]
    }

    public static func normalized(_ text: String) -> String? {
        let singleLine = text.unicodeScalars.map { scalar -> String in
            scalar.properties.generalCategory == .control || CharacterSet.newlines.contains(scalar) ? " " : String(scalar)
        }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(singleLine.prefix(maximumLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public func revision(accountId: Int64) -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return revisions[accountId] ?? 0
    }

    public func name(accountId: Int64, peerId: Int64) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return accounts[String(accountId)]?[String(peerId)]
    }

    public func setName(_ text: String, accountId: Int64, peerId: Int64) {
        let value = Self.normalized(text)
        lock.lock()
        var names = accounts[String(accountId)] ?? [:]
        guard names[String(peerId)] != value else { lock.unlock(); return }
        names[String(peerId)] = value
        accounts[String(accountId)] = names.isEmpty ? nil : names
        defaults.set(accounts, forKey: Self.preferenceKey)
        revisions[accountId] = (revisions[accountId] ?? 0) &+ 1
        lock.unlock()
        let change = RGGroupRemarkChange(accountId: accountId, peerId: peerId)
        let notifications = self.notifications
        DispatchQueue.main.async { notifications.post(name: Self.didChange, object: change) }
    }

    public func matchingPeerIds(accountId: Int64, query: String) -> [Int64] {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !words.isEmpty else { return [] }
        lock.lock()
        let names = accounts[String(accountId)] ?? [:]
        lock.unlock()
        return names.compactMap { key, name in
            words.allSatisfy { name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil } ? Int64(key) : nil
        }.sorted()
    }

    public func clear(accountId: Int64) {
        lock.lock()
        guard accounts.removeValue(forKey: String(accountId)) != nil else { lock.unlock(); return }
        defaults.set(accounts, forKey: Self.preferenceKey)
        revisions[accountId] = (revisions[accountId] ?? 0) &+ 1
        lock.unlock()
        let notifications = self.notifications
        DispatchQueue.main.async { notifications.post(name: Self.didChange, object: RGGroupRemarkChange(accountId: accountId, peerId: 0)) }
    }
}
