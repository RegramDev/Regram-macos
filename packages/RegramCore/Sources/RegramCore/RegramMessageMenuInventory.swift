import Foundation

public final class RegramMessageMenuInventory {
    public static let shared = RegramMessageMenuInventory()
    public static let didChange = Notification.Name("Regram.MessageMenuInventory.DidChange")
    private static let observedKey = "rg_contextMenuObserved"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = regramSharedDefaults()) { self.defaults = defaults }

    public func available() -> Set<RGContextMenuItemId> {
        lock.lock()
        defer { lock.unlock() }
        return RGContextMenuItemId.standardItems.union(observedItems())
    }

    public func record(_ items: Set<RGContextMenuItemId>) {
        lock.lock()
        let current = observedItems()
        let updated = current.union(items.filter(\.canBeCustomized))
        guard current != updated else { lock.unlock(); return }
        defaults.set(updated.map(\.rawValue).sorted(), forKey: Self.observedKey)
        lock.unlock()
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.didChange, object: nil) }
    }

    private func observedItems() -> Set<RGContextMenuItemId> {
        if let stored = defaults.stringArray(forKey: Self.observedKey) {
            return Set(stored.compactMap(RGContextMenuItemId.init(rawValue:)).filter(\.canBeCustomized))
        }
        let legacy = defaults.dictionaryRepresentation().flatMap { key, value -> [String] in
            guard key.hasPrefix(Self.observedKey + "_") else { return [] }
            return value as? [String] ?? []
        }
        let items = Set(legacy.compactMap(RGContextMenuItemId.init(rawValue:)).filter(\.canBeCustomized))
        defaults.set(items.map(\.rawValue).sorted(), forKey: Self.observedKey)
        return items
    }
}
