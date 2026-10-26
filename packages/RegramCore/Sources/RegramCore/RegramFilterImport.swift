import Foundation

public struct RegramFilterImport: Equatable {
    public enum Failure: Error { case tooLarge, invalidRules, unreadableFile }
    public static let maximumBytes = 2 * 1024 * 1024
    public let data: Data
    public let rules: [RGMessageFilterRule]

    public init(data: Data) throws {
        guard data.count <= Self.maximumBytes else { throw Failure.tooLarge }
        guard let rules = try? JSONDecoder().decode([RGMessageFilterRule].self, from: data), !rules.isEmpty else { throw Failure.invalidRules }
        self.data = data
        self.rules = rules
    }

    public static func read(from url: URL) throws -> RegramFilterImport {
        guard url.isFileURL, let stream = InputStream(url: url) else { throw Failure.unreadableFile }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        while true {
            let remaining = Self.maximumBytes - data.count
            let count = stream.read(&buffer, maxLength: min(buffer.count, remaining + 1))
            guard count >= 0 else { throw Failure.unreadableFile }
            if count == 0 { break }
            guard count <= remaining else { throw Failure.tooLarge }
            data.append(contentsOf: buffer.prefix(count))
        }
        return try Self(data: data)
    }

    public struct Plan: Equatable {
        public enum Disposition: Equatable { case added, duplicate, conflictingIdentifier }
        public struct Entry: Equatable {
            public let rule: RGMessageFilterRule
            public let disposition: Disposition
        }
        public let entries: [Entry]
        public let addedCount: Int
        public let duplicateCount: Int
        public let conflictingIdentifierCount: Int
    }

    private struct Definition: Hashable {
        let pattern: String
        let isRegex: Bool
        let isException: Bool
        let peerIds: Set<Int64>

        init(_ rule: RGMessageFilterRule) {
            pattern = rule.pattern
            isRegex = rule.isRegex
            isException = rule.isException
            peerIds = Set(rule.peerIds)
        }
    }

    public func plan(existing: [RGMessageFilterRule]) -> Plan {
        var definitions = Set(existing.map(Definition.init))
        var identifiers = Set(existing.map(\.id))
        var entries: [Plan.Entry] = []
        var added = 0
        var duplicates = 0
        var conflicts = 0
        for rule in rules {
            let disposition: Plan.Disposition
            if !definitions.insert(Definition(rule)).inserted {
                disposition = .duplicate
                duplicates += 1
            } else {
                added += 1
                if !identifiers.insert(rule.id).inserted {
                    disposition = .conflictingIdentifier
                    conflicts += 1
                } else {
                    disposition = .added
                }
            }
            entries.append(Plan.Entry(rule: rule, disposition: disposition))
        }
        return Plan(entries: entries, addedCount: added, duplicateCount: duplicates, conflictingIdentifierCount: conflicts)
    }

    public func merging(into existing: [RGMessageFilterRule]) -> (rules: [RGMessageFilterRule], addedCount: Int) {
        let plan = self.plan(existing: existing)
        let additions = plan.entries.filter { $0.disposition != .duplicate }.map { entry in
            RGMessageFilterRule(pattern: entry.rule.pattern, isRegex: entry.rule.isRegex, peerIds: entry.rule.peerIds, isEnabled: entry.rule.isEnabled, isException: entry.rule.isException)
        }
        return (existing + additions, additions.count)
    }
}
