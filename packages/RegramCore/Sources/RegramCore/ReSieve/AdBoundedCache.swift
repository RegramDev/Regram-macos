import Foundation

public struct RGAdBoundedCache<Key: Hashable, Value> {
    private struct Entry {
        let value: Value
        let cost: Int
    }
    private let countLimit: Int
    private let costLimit: Int
    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []
    public private(set) var totalCost = 0
    public var count: Int { entries.count }
    public var orderedEntries: [(Key, Value)] { order.compactMap { key in entries[key].map { (key, $0.value) } } }
    public init(countLimit: Int, costLimit: Int) {
        self.countLimit = max(0, countLimit)
        self.costLimit = max(0, costLimit)
    }
    public subscript(key: Key) -> Value? { entries[key]?.value }
    public mutating func insert(_ value: Value, for key: Key, cost: Int) {
        if let previous = entries.removeValue(forKey: key) {
            totalCost -= previous.cost
            order.removeAll { $0 == key }
        }
        guard countLimit > 0, cost >= 0, cost <= costLimit else { return }
        while !order.isEmpty && (entries.count >= countLimit || cost > costLimit - totalCost) {
            if let old = entries.removeValue(forKey: order.removeFirst()) { totalCost -= old.cost }
        }
        entries[key] = Entry(value: value, cost: cost)
        order.append(key)
        totalCost += cost
    }
    public mutating func removeAll() {
        entries.removeAll()
        order.removeAll()
        totalCost = 0
    }
}

extension RGAdInput {
    public var estimatedMemoryCost: Int {
        256 + text.utf8.count * 2 + (previewTarget?.utf8.count ?? 0) * 2
            + entities.reduce(0) { $0 + 96 + ($1.value?.utf8.count ?? 0) * 2 }
            + buttons.flatMap { $0 }.reduce(0) { $0 + 128 + ($1.title.utf8.count + ($1.target?.utf8.count ?? 0)) * 2 }
    }
}
