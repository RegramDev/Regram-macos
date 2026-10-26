import Foundation

public enum RGFilterBenchmark {
    public static let messageCount = 100
    public struct Result {
        public let totalMilliseconds: Double
        public var averageMilliseconds: Double { totalMilliseconds / Double(RGFilterBenchmark.messageCount) }
    }
    public static func measure(
        rules: [RGMessageFilterRule],
        shouldContinue: () -> Bool = { true },
        now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        match: (String, [RGMessageFilterRule]) -> Bool = { RGMessageFilter.shouldHide(text: $0, peerId: nil, rules: $1) }
    ) -> Result? {
        let rules = rules.map { rule -> RGMessageFilterRule in
            var rule = rule; rule.peerIds = []; return rule
        }
        let base = String(repeating: "这是一段性能测试消息 Hello Regram 😀 1234567。", count: 15)
        let messages = (0..<messageCount).map { base + " #\($0)" }
        let start = now()
        for message in messages {
            guard shouldContinue() else { return nil }
            _ = match(message, rules)
        }
        return Result(totalMilliseconds: max(0, now() - start) * 1000)
    }
}

public final class RGFilterBenchmarkSession {
    private let lock = NSLock()
    private var active: UUID?
    public init() {}
    public func begin() -> UUID {
        lock.lock(); defer { lock.unlock() }
        let token = UUID(); active = token; return token
    }
    public func isActive(_ token: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return active == token
    }
    public func finish(_ token: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard active == token else { return false }
        active = nil; return true
    }
    public func cancel() {
        lock.lock(); defer { lock.unlock() }
        active = nil
    }
}
