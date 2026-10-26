import Foundation

public final class RegramMessageMenuInventory {
    public static let shared = RegramMessageMenuInventory()
    public static let didChange = Notification.Name("Regram.MessageMenuInventory.DidChange")
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = regramSharedDefaults()) { self.defaults = defaults }

    public func available(accountId: Int64) -> Set<RGContextMenuItemId> {
        lock.lock()
        defer { lock.unlock() }
        let observed = defaults.stringArray(forKey: "rg_contextMenuObserved_\(accountId)") ?? []
        return RGContextMenuItemId.standardItems.union(observed.compactMap(RGContextMenuItemId.init(rawValue:))).filter(\.canBeCustomized)
    }

    public func record(_ items: Set<RGContextMenuItemId>, accountId: Int64) {
        lock.lock()
        let key = "rg_contextMenuObserved_\(accountId)"
        let current = Set(defaults.stringArray(forKey: key) ?? [])
        let updated = current.union(items.filter(\.canBeCustomized).map(\.rawValue))
        guard current != updated else { lock.unlock(); return }
        defaults.set(updated.sorted(), forKey: key)
        lock.unlock()
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.didChange, object: accountId) }
    }

    public func clear(accountId: Int64) {
        lock.lock()
        defaults.removeObject(forKey: "rg_contextMenuObserved_\(accountId)")
        lock.unlock()
    }
}
