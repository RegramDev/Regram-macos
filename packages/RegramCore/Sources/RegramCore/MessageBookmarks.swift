import Foundation

public struct RGBookmarkMessageId: Codable, Hashable {
    public let peerId: Int64
    public let namespace: Int32
    public let id: Int32
    public init(peerId: Int64, namespace: Int32, id: Int32) {
        self.peerId = peerId; self.namespace = namespace; self.id = id
    }
}

public struct RGMessageBookmark: Codable, Equatable, Identifiable {
    public var id: RGBookmarkMessageId { messageId }
    public let messageId: RGBookmarkMessageId
    public let threadId: Int64?
    public let addedAt: TimeInterval
    public var tags: [String]
    public init(messageId: RGBookmarkMessageId, threadId: Int64?, addedAt: TimeInterval, tags: [String]) {
        self.messageId = messageId; self.threadId = threadId; self.addedAt = addedAt; self.tags = tags
    }
}

public final class RGMessageBookmarks {
    public static let shared = RGMessageBookmarks()
    public static let didChange = Notification.Name("Regram.MessageBookmarks.DidChange")
    public static let maximumTags = 10
    public static let maximumTagLength = 32
    private static let preferenceKey = "Regram.MessageBookmarks.v1"
    private struct Record: Codable { var schema = 1; var accounts: [String: [RGMessageBookmark]] }
    private let defaults: UserDefaults
    private let notifications: NotificationCenter
    private let lock = NSLock()
    private var accounts: [String: [RGMessageBookmark]]

    public init(defaults: UserDefaults = .standard, notifications: NotificationCenter = .default) {
        self.defaults = defaults; self.notifications = notifications
        if let data = defaults.data(forKey: Self.preferenceKey), let record = try? JSONDecoder().decode(Record.self, from: data), record.schema == 1 {
            self.accounts = record.accounts
        } else { self.accounts = [:] }
    }

    public static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { value -> String? in
            let singleLine = value.unicodeScalars.map { scalar in scalar.properties.generalCategory == .control || CharacterSet.newlines.contains(scalar) ? " " : String(scalar) }.joined()
            let name = String(singleLine.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumTagLength)).trimmingCharacters(in: .whitespacesAndNewlines)
            let key = name.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            return !name.isEmpty && seen.insert(key).inserted ? name : nil
        }.prefix(maximumTags).map { $0 }
    }

    public func bookmarks(accountId: Int64) -> [RGMessageBookmark] {
        lock.lock(); defer { lock.unlock() }
        return (accounts[String(accountId)] ?? []).sorted { $0.addedAt > $1.addedAt }
    }

    public func bookmark(accountId: Int64, messageId: RGBookmarkMessageId) -> RGMessageBookmark? {
        lock.lock(); defer { lock.unlock() }
        return accounts[String(accountId)]?.first { $0.messageId == messageId }
    }

    public func save(accountId: Int64, messageId: RGBookmarkMessageId, threadId: Int64?, tags: [String], now: TimeInterval = Date().timeIntervalSince1970) {
        let tags = Self.normalizedTags(tags)
        update(accountId: accountId) { values in
            if let index = values.firstIndex(where: { $0.messageId == messageId }) { values[index].tags = tags }
            else { values.append(RGMessageBookmark(messageId: messageId, threadId: threadId, addedAt: now, tags: tags)) }
        }
    }

    public func remove(accountId: Int64, messageId: RGBookmarkMessageId) {
        update(accountId: accountId) { $0.removeAll { $0.messageId == messageId } }
    }

    public func remove(accountId: Int64, messageIds: Set<RGBookmarkMessageId>) {
        guard !messageIds.isEmpty else { return }
        update(accountId: accountId) { $0.removeAll { messageIds.contains($0.messageId) } }
    }

    public func clear(accountId: Int64) {
        update(accountId: accountId) { $0.removeAll() }
    }

    public func tags(accountId: Int64) -> [String] {
        let tags = bookmarks(accountId: accountId).flatMap(\.tags)
        var seen = Set<String>()
        return tags.filter { seen.insert($0.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public func updateTags(accountId: Int64, messageIds: Set<RGBookmarkMessageId>, adding: [String] = [], removing: [String] = []) {
        let removing = Set(Self.normalizedTags(removing).map { $0.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")) })
        update(accountId: accountId) { values in
            for index in values.indices where messageIds.contains(values[index].messageId) {
                let tags = values[index].tags.filter { !removing.contains($0.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))) }
                values[index].tags = Self.normalizedTags(tags + adding)
            }
        }
    }

    private func update(accountId: Int64, change: (inout [RGMessageBookmark]) -> Void) {
        lock.lock()
        var values = accounts[String(accountId)] ?? []
        let previous = values
        change(&values)
        guard values != previous else { lock.unlock(); return }
        var updated = accounts
        updated[String(accountId)] = values.isEmpty ? nil : values
        guard let data = try? JSONEncoder().encode(Record(accounts: updated)) else { lock.unlock(); return }
        defaults.set(data, forKey: Self.preferenceKey)
        accounts = updated
        lock.unlock()
        let notifications = self.notifications
        DispatchQueue.main.async { notifications.post(name: Self.didChange, object: accountId) }
    }
}
