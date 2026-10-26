import Foundation

public final class RegramRecentChats {
    public static let shared = RegramRecentChats()
    public static let didChange = Notification.Name("Regram.RecentChats.DidChange")
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public func peers(accountId: Int64) -> [Int64] {
        lock.lock()
        defer { lock.unlock() }
        return read(accountId)
    }

    public func add(peerId: Int64, accountId: Int64) {
        guard RegramPreferences.shared.settings(accountId: accountId)["recentChatsEnabled"].bool else { return }
        lock.lock()
        let current = read(accountId)
        let updated = Array(([peerId] + current.filter { $0 != peerId }).prefix(50))
        defaults.set(updated.map(String.init), forKey: key(accountId))
        lock.unlock()
        guard updated != current else { return }
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.didChange, object: accountId) }
    }

    public func clear(accountId: Int64) {
        lock.lock()
        defaults.removeObject(forKey: key(accountId))
        lock.unlock()
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.didChange, object: accountId) }
    }

    private func read(_ accountId: Int64) -> [Int64] { (defaults.stringArray(forKey: key(accountId)) ?? []).compactMap(Int64.init) }
    private func key(_ accountId: Int64) -> String { "Regram.RecentChats.v1.\(accountId)" }
}
