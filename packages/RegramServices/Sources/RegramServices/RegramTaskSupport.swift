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

public struct RegramSummaryMessage: Equatable {
    public let identifier: String
    public let timestamp: Int64
    public let text: String
    public let isSecret: Bool
    public let isCopyProtected: Bool
    public let isOneTime: Bool
    public let hasAttachment: Bool

    public init(identifier: String, timestamp: Int64, text: String, isSecret: Bool = false, isCopyProtected: Bool = false, isOneTime: Bool = false, hasAttachment: Bool = false) {
        self.identifier = identifier
        self.timestamp = timestamp
        self.text = text
        self.isSecret = isSecret
        self.isCopyProtected = isCopyProtected
        self.isOneTime = isOneTime
        self.hasAttachment = hasAttachment
    }
}

public struct RegramSummarySelection: Equatable {
    public let messages: [RegramSummaryMessage]
    public let text: String
    public let byteCount: Int

    public init(messages: [RegramSummaryMessage], text: String, byteCount: Int) {
        self.messages = messages
        self.text = text
        self.byteCount = byteCount
    }
}

public enum RegramSummarySelectionError: LocalizedError, Equatable {
    case disabled
    case empty
    case secretContent
    case protectedContent
    case unsupportedAttachment
    case tooManyMessages
    case tooManyBytes
    case invalidRange

    public var errorDescription: String? {
        switch self {
        case .disabled: return "Message summaries are disabled."
        case .empty: return "There are no text messages to summarize."
        case .secretContent: return "Secret messages cannot be sent to a summary service."
        case .protectedContent: return "Protected messages cannot be sent to a summary service."
        case .unsupportedAttachment: return "Messages with one-time media or unsupported attachments cannot be summarized."
        case .tooManyMessages: return "Choose a smaller message range."
        case .tooManyBytes: return "Choose a smaller message range."
        case .invalidRange: return "Choose a valid time range."
        }
    }
}

public enum RegramSummaryPolicy {
    public static let selectionLimit = 100
    public static let rangeLimit = 5000
    public static let maximumBytes = 64000

    public static func prepare(_ messages: [RegramSummaryMessage], permitsTimeRange: Bool = false, enabled: Bool = true) -> Result<RegramSummarySelection, RegramSummarySelectionError> {
        guard enabled else { return .failure(.disabled) }
        let limit = permitsTimeRange ? rangeLimit : selectionLimit
        guard !messages.isEmpty else { return .failure(.empty) }
        guard messages.count <= limit else { return .failure(.tooManyMessages) }
        guard !messages.contains(where: { $0.isSecret }) else { return .failure(.secretContent) }
        guard !messages.contains(where: { $0.isCopyProtected }) else { return .failure(.protectedContent) }
        guard !messages.contains(where: { $0.isOneTime || $0.hasAttachment }) else { return .failure(.unsupportedAttachment) }
        let textMessages = messages.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.sorted { $0.timestamp == $1.timestamp ? $0.identifier < $1.identifier : $0.timestamp < $1.timestamp }
        guard !textMessages.isEmpty else { return .failure(.empty) }
        let text = textMessages.map(\.text).joined(separator: "\n\n---\n\n")
        let byteCount = text.utf8.count
        guard byteCount <= maximumBytes else { return .failure(.tooManyBytes) }
        return .success(RegramSummarySelection(messages: textMessages, text: text, byteCount: byteCount))
    }

    public static func prepareRange(_ messages: [RegramSummaryMessage], from: Int64, to: Int64, enabled: Bool = true) -> Result<RegramSummarySelection, RegramSummarySelectionError> {
        guard from > 0, from < to else { return .failure(.invalidRange) }
        return prepare(messages.filter { $0.timestamp >= from && $0.timestamp <= to }, permitsTimeRange: true, enabled: enabled)
    }
}
