import Foundation

public final class RegramQuickTranslationTasks {
    public static let shared = RegramQuickTranslationTasks()
    public static let didChange = Notification.Name("Regram.QuickTranslation.DidChange")
    public struct Task {
        public let token: UUID
        public let language: String
    }
    private let lock = NSLock()
    private var tasks: [Int64: [RGBookmarkMessageId: Task]] = [:]
    private var revisions: [Int64: Int64] = [:]

    public init() {}

    public func begin(accountId: Int64, messageId: RGBookmarkMessageId, language: String) -> UUID? {
        lock.lock()
        guard tasks[accountId, default: [:]].count < 3, tasks[accountId]?[messageId] == nil else { lock.unlock(); return nil }
        let token = UUID()
        tasks[accountId, default: [:]][messageId] = Task(token: token, language: language)
        revisions[accountId, default: 0] &+= 1
        lock.unlock()
        publish(accountId)
        return token
    }

    public func task(accountId: Int64, messageId: RGBookmarkMessageId) -> Task? {
        lock.lock(); defer { lock.unlock() }
        return tasks[accountId]?[messageId]
    }

    public func revision(accountId: Int64) -> Int64 {
        lock.lock(); defer { lock.unlock() }
        return revisions[accountId] ?? 0
    }

    @discardableResult public func finish(accountId: Int64, messageId: RGBookmarkMessageId, token: UUID) -> Bool {
        lock.lock()
        guard tasks[accountId]?[messageId]?.token == token else { lock.unlock(); return false }
        tasks[accountId]?.removeValue(forKey: messageId)
        if tasks[accountId]?.isEmpty == true { tasks.removeValue(forKey: accountId) }
        revisions[accountId, default: 0] &+= 1
        lock.unlock()
        publish(accountId)
        return true
    }

    private func publish(_ accountId: Int64) {
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.didChange, object: accountId) }
    }

    public func clear(accountId: Int64) {
        lock.lock()
        tasks.removeValue(forKey: accountId)
        revisions[accountId, default: 0] &+= 1
        lock.unlock()
        publish(accountId)
    }
}
