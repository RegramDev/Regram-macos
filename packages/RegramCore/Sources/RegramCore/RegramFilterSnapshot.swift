import Foundation

public struct RegramFilterSnapshot {
    private let rules: [RGMessageFilterRule]
    private let hiddenAuthors: Set<Int64>
    private let ignoredChats: Set<Int64>

    public init(settings: RegramAccountSettings) {
        rules = settings.filterRules
        hiddenAuthors = Set(settings["blockedPeerIds"].strings.compactMap(Int64.init))
        ignoredChats = Set(settings["messageFilterDisabledPeerIds"].strings.compactMap(Int64.init))
    }

    public func shouldHide(text: String, peerId: Int64, authorId: Int64?, incoming: Bool) -> Bool {
        guard incoming else { return false }
        if let authorId, hiddenAuthors.contains(authorId) { return true }
        guard !ignoredChats.contains(peerId) else { return false }
        return RGMessageFilter.shouldHide(text: text, peerId: peerId, rules: rules)
    }
}

public final class RegramTemporaryReveal {
    public static let shared = RegramTemporaryReveal()
    private let lock = NSLock()
    private var deadlines: [String: TimeInterval] = [:]

    public func isRevealed(accountId: Int64, peerId: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return (deadlines[key(accountId, peerId)] ?? 0) > ProcessInfo.processInfo.systemUptime
    }

    public func setRevealed(_ enabled: Bool, accountId: Int64, peerId: Int64) {
        let key = key(accountId, peerId)
        let deadline = ProcessInfo.processInfo.systemUptime + 300
        lock.lock()
        deadlines[key] = enabled ? deadline : nil
        lock.unlock()
        NotificationCenter.default.post(name: RegramPreferences.didChange, object: accountId)
        guard enabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            guard self.deadlines[key] == deadline else { self.lock.unlock(); return }
            self.deadlines.removeValue(forKey: key)
            self.lock.unlock()
            NotificationCenter.default.post(name: RegramPreferences.didChange, object: accountId)
        }
    }

    private func key(_ accountId: Int64, _ peerId: Int64) -> String { "\(accountId):\(peerId)" }

    public func clear(accountId: Int64) {
        lock.lock()
        deadlines = deadlines.filter { !$0.key.hasPrefix("\(accountId):") }
        lock.unlock()
        NotificationCenter.default.post(name: RegramPreferences.didChange, object: accountId)
    }
}
