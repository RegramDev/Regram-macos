import Foundation

struct RegramSearchMessageOrder: Comparable, Hashable {
    let timestamp: Int32
    let peerId: Int64
    let namespace: Int32
    let messageId: Int32

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        if lhs.peerId != rhs.peerId { return lhs.peerId < rhs.peerId }
        if lhs.namespace != rhs.namespace { return lhs.namespace < rhs.namespace }
        return lhs.messageId < rhs.messageId
    }
}

struct RegramGroupSearchStatus {
    let peerId: Int64
    var loaded = false
    var hasMore = true
    var loading = false
    var failed = false
    var oldest: RegramSearchMessageOrder?
}

enum RegramMessageSearchPolicy {
    static let concurrency = 3
    static let pageSize: Int32 = 30
    static let displayPageSize = 50

    static func nextGroups(_ statuses: [RegramGroupSearchStatus], orders: [RegramSearchMessageOrder], visibleLimit: Int, selectedGroup: Int64?) -> [Int64] {
        let capacity = max(0, concurrency - statuses.filter(\.loading).count)
        let sorted = orders.sorted(by: >)
        let limit = max(1, visibleLimit)
        let cutoff = sorted.count >= limit ? sorted[limit - 1] : nil
        return statuses.filter { group in
            guard selectedGroup == nil || group.peerId == selectedGroup else { return false }
            guard !group.loading, !group.failed, group.hasMore else { return false }
            guard group.loaded, let cutoff else { return true }
            return group.oldest.map { $0 >= cutoff } ?? true
        }.sorted { lhs, rhs in
            if lhs.loaded != rhs.loaded { return !lhs.loaded }
            if lhs.oldest != rhs.oldest {
                let maximum = RegramSearchMessageOrder(timestamp: .max, peerId: .max, namespace: .max, messageId: .max)
                return (lhs.oldest ?? maximum) > (rhs.oldest ?? maximum)
            }
            return lhs.peerId < rhs.peerId
        }.prefix(capacity).map(\.peerId)
    }

    static func preview(_ text: String, spoilers: [Range<Int>], reveal: Bool) -> String {
        let preview = NSMutableString(string: String(text.prefix(600)))
        if !reveal {
            for range in spoilers.sorted(by: { $0.lowerBound > $1.lowerBound }) {
                let lower = max(0, range.lowerBound)
                let upper = min(preview.length, range.upperBound)
                if lower < upper {
                    preview.replaceCharacters(in: NSRange(location: lower, length: upper - lower), with: String(repeating: "▪", count: upper - lower))
                }
            }
        }
        return preview as String
    }
}
