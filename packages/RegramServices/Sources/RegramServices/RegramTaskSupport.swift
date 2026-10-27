import Foundation
import SwiftSignalKit

public struct RegramTaskToken: Hashable, Equatable {
    public let rawValue: UUID

    public init() {
        self.rawValue = UUID()
    }
}

public final class RegramTaskRegistry<Key: Hashable> {
    private struct Entry {
        let token: RegramTaskToken
        let revision: Int64
    }

    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    private var revisions: [Key: Int64] = [:]

    public init() {}

    public func begin(_ key: Key, revision: Int64 = 0) -> RegramTaskToken? {
        lock.lock()
        defer { lock.unlock() }
        guard entries[key] == nil else { return nil }
        let token = RegramTaskToken()
        entries[key] = Entry(token: token, revision: revision)
        return token
    }

    public func replace(_ key: Key, revision: Int64 = 0) -> RegramTaskToken {
        lock.lock()
        defer { lock.unlock() }
        let token = RegramTaskToken()
        entries[key] = Entry(token: token, revision: revision)
        return token
    }

    public func isCurrent(_ key: Key, token: RegramTaskToken, revision: Int64? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key], entry.token == token else { return false }
        return revision == nil || entry.revision == revision
    }

    @discardableResult
    public func finish(_ key: Key, token: RegramTaskToken) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard entries[key]?.token == token else { return false }
        entries.removeValue(forKey: key)
        revisions[key] = (revisions[key] ?? 0) &+ 1
        return true
    }

    @discardableResult
    public func cancel(_ key: Key) -> RegramTaskToken? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries.removeValue(forKey: key) else { return nil }
        revisions[key] = (revisions[key] ?? 0) &+ 1
        return entry.token
    }

    public func current(_ key: Key) -> (token: RegramTaskToken, revision: Int64)? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key] else { return nil }
        return (entry.token, entry.revision)
    }

    public func cancelAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}

public struct RegramLLMContextMessage: Equatable {
    public let peerId: Int64
    public let topicId: Int64?
    public let text: String
    public let isSecret: Bool
    public let isCopyProtected: Bool
    public let isOneTime: Bool

    public init(peerId: Int64, topicId: Int64? = nil, text: String, isSecret: Bool = false, isCopyProtected: Bool = false, isOneTime: Bool = false) {
        self.peerId = peerId
        self.topicId = topicId
        self.text = text
        self.isSecret = isSecret
        self.isCopyProtected = isCopyProtected
        self.isOneTime = isOneTime
    }
}

public enum RegramLLMContextPolicy {
    public static let maxMessages = 5
    public static let maxCharactersPerMessage = 800

    public static func bounded(_ messages: [RegramLLMContextMessage], peerId: Int64, topicId: Int64?) -> [String] {
        let eligible = messages.filter {
            $0.peerId == peerId && $0.topicId == topicId && !$0.isSecret && !$0.isCopyProtected && !$0.isOneTime && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return eligible.suffix(maxMessages).map { message in
            let text = String(message.text.prefix(maxCharactersPerMessage))
            return text
        }
    }
}
