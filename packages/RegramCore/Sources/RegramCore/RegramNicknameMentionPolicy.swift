import Foundation

public enum RegramNicknameMentionPolicy {
    public static let lookupDelay = 0.65
    public static let lookupTimeout = 4.0
    public static let maximumResolvedUsernames = 16

    public struct Candidate: Equatable {
        public let range: Range<Int>
        public let username: String
    }

    public struct Replacement {
        public let range: Range<Int>
        public let text: String
        public init(range: Range<Int>, text: String) { self.range = range; self.text = text }
    }

    public static func candidates(text: String, mentionRanges: [Range<Int>], excludedRanges: [Range<Int>], selection: Range<Int>) -> [Candidate] {
        let string = text as NSString
        guard selection.isEmpty, selection.lowerBound >= 0, selection.upperBound <= string.length else { return [] }
        var seen = Set<Int>()
        return mentionRanges.compactMap { range in
            guard range.count > 1, range.lowerBound >= 0, range.upperBound <= string.length,
                  !excludedRanges.contains(where: { $0.overlaps(range) }),
                  !range.contains(selection.lowerBound) || selection.lowerBound == range.lowerBound,
                  seen.insert(range.lowerBound).inserted else { return nil }
            let token = string.substring(with: NSRange(location: range.lowerBound, length: range.count))
            guard token.hasPrefix("@") else { return nil }
            return Candidate(range: range, username: String(token.dropFirst()).lowercased())
        }
    }

    public static func remap(_ range: Range<Int>, replacements: [Replacement]) -> Range<Int> {
        func offset(_ value: Int, end: Bool) -> Int {
            var delta = 0
            for replacement in replacements.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
                if value >= replacement.range.upperBound { delta += replacement.text.utf16.count - replacement.range.count }
                else if value > replacement.range.lowerBound { return replacement.range.lowerBound + delta + (end ? replacement.text.utf16.count : 0) }
                else { break }
            }
            return value + delta
        }
        return offset(range.lowerBound, end: false)..<offset(range.upperBound, end: true)
    }
}
