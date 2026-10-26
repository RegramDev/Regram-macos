import Foundation


public struct RGMessageFilterRule: Codable, Equatable {
    public var id: String
    public var pattern: String
    public var isRegex: Bool
    public var isEnabled: Bool
    public var isException: Bool
    public var peerIds: [Int64]

    public init(id: String = UUID().uuidString, pattern: String, isRegex: Bool = false, peerIds: [Int64] = [], isEnabled: Bool = true, isException: Bool = false) {
        self.id = id
        self.pattern = pattern
        self.isRegex = isRegex
        self.peerIds = peerIds
        self.isEnabled = isEnabled
        self.isException = isException
    }

    private enum CodingKeys: String, CodingKey { case id, pattern, isRegex, peerIds, isEnabled, isException }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try values.decode(String.self, forKey: .id)
        self.pattern = try values.decode(String.self, forKey: .pattern)
        self.isRegex = try values.decode(Bool.self, forKey: .isRegex)
        self.peerIds = try values.decode([Int64].self, forKey: .peerIds)
        self.isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.isException = try values.decodeIfPresent(Bool.self, forKey: .isException) ?? false
    }

    public func hasSameDefinition(as other: RGMessageFilterRule) -> Bool {
        return self.pattern == other.pattern && self.isRegex == other.isRegex
            && self.isException == other.isException && Set(self.peerIds) == Set(other.peerIds)
    }

    public var appliesToAllChats: Bool {
        return self.peerIds.isEmpty
    }

    public func appliesTo(peerId: Int64?) -> Bool {
        if self.peerIds.isEmpty {
            return true
        }
        guard let peerId = peerId else {
            return false
        }
        return self.peerIds.contains(peerId)
    }

    public var isValid: Bool {
        if self.pattern.isEmpty {
            return false
        }
        if self.isRegex {
            return RGMessageFilter.compiledRegex(for: self.pattern) != nil
        }
        return true
    }
}

public final class RGMessageFilter {
    public enum MatchResult: Equatable { case matched, notMatched, disabled, invalidRegex, timedOut }
    public static let regexTimeBudget: TimeInterval = 0.005
    private static let regexCacheLock = NSLock()
    private static var regexCache: [String: NSRegularExpression?] = [:]
    private static var regexCacheOrder: [String] = []

    public static func compiledRegex(for pattern: String) -> NSRegularExpression? {
        self.regexCacheLock.lock()
        defer { self.regexCacheLock.unlock() }
        if let cached = self.regexCache[pattern] {
            return cached
        }
        let compiled = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        if self.regexCacheOrder.count == 4096 {
            self.regexCache.removeValue(forKey: self.regexCacheOrder.removeFirst())
        }
        self.regexCacheOrder.append(pattern)
        self.regexCache[pattern] = compiled
        return compiled
    }

    public static func matches(rule: RGMessageFilterRule, text: String) -> Bool {
        return self.matchResult(rule: rule, text: text) == .matched
    }

    public static func matchResult(rule: RGMessageFilterRule, text: String) -> MatchResult {
        return self.matchResult(rule: rule, text: text, string: text as NSString, needsSwiftMatching: self.needsSwiftMatching(text))
    }

    private static func needsSwiftMatching(_ text: String) -> Bool {
        return text.unicodeScalars.contains { $0.value > 127 && $0.properties.isCased }
    }

    private static func matchResult(rule: RGMessageFilterRule, text: String, string: NSString, needsSwiftMatching: Bool) -> MatchResult {
        guard rule.isEnabled else { return .disabled }
        guard !rule.pattern.isEmpty, string.length != 0 else { return .notMatched }
        if rule.isRegex {
            guard let regex = self.compiledRegex(for: rule.pattern) else {
                return .invalidRegex
            }
            let deadline = ProcessInfo.processInfo.systemUptime + self.regexTimeBudget
            var result: MatchResult = .notMatched
            regex.enumerateMatches(in: text, options: .reportProgress, range: NSRange(location: 0, length: string.length)) { match, _, stop in
                if ProcessInfo.processInfo.systemUptime >= deadline {
                    result = .timedOut
                    stop.pointee = true
                } else if match != nil {
                    result = .matched
                    stop.pointee = true
                }
            }
            return result
        }
        if needsSwiftMatching || self.needsSwiftMatching(rule.pattern) {
            return text.range(of: rule.pattern, options: .caseInsensitive) != nil ? .matched : .notMatched
        }
        return string.range(of: rule.pattern, options: .caseInsensitive).location != NSNotFound ? .matched : .notMatched
    }

    public static func shouldHide(text: String, peerId: Int64?, rules: [RGMessageFilterRule]) -> Bool {
        if rules.isEmpty {
            return false
        }
        let string = text as NSString
        let needsSwiftMatching = self.needsSwiftMatching(text)
        for rule in rules where rule.isException && rule.isEnabled && rule.appliesTo(peerId: peerId) {
            let result = self.matchResult(rule: rule, text: text, string: string, needsSwiftMatching: needsSwiftMatching)
            if result == .matched || result == .timedOut { return false }
        }
        var timeoutCount = 0
        for rule in rules where !rule.isException && rule.isEnabled {
            if !rule.appliesTo(peerId: peerId) {
                continue
            }
            if rule.isRegex && timeoutCount >= 4 { continue }
            let result = self.matchResult(rule: rule, text: text, string: string, needsSwiftMatching: needsSwiftMatching)
            if result == .matched {
                return true
            }
            if result == .timedOut { timeoutCount += 1 }
        }
        return false
    }

    public static func encode(_ rules: [RGMessageFilterRule]) -> String {
        guard let data = try? JSONEncoder().encode(rules), let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    public static func decode(_ string: String) -> [RGMessageFilterRule] {
        guard let data = string.data(using: .utf8), let rules = try? JSONDecoder().decode([RGMessageFilterRule].self, from: data) else {
            return []
        }
        return rules
    }

    public static let exportFileName = "regram-message-filter.json"

    public static func isExportFileName(_ fileName: String) -> Bool {
        let lowercased = fileName.lowercased()
        return lowercased.hasPrefix("regram-message-filter") && lowercased.hasSuffix(".json")
    }

    public static func merging(_ imported: [RGMessageFilterRule], into existing: [RGMessageFilterRule]) -> (rules: [RGMessageFilterRule], addedCount: Int) {
        var merged = existing
        var addedCount = 0
        for rule in imported where !merged.contains(where: { $0.hasSameDefinition(as: rule) }) {
            merged.append(RGMessageFilterRule(pattern: rule.pattern, isRegex: rule.isRegex, peerIds: rule.peerIds, isEnabled: rule.isEnabled, isException: rule.isException))
            addedCount += 1
        }
        return (merged, addedCount)
    }
}
