import Foundation

public struct RGTranslationLinkPlan {
    public struct ProtectedRange {
        public let range: NSRange
        public let id: Int
        public init(range: NSRange, id: Int) { self.range = range; self.id = id }
    }
    public struct Segment {
        public let text: String
        public let id: Int?
        public let entityIds: [Int]
    }
    public let segments: [Segment]

    public init(text: String, ranges: [ProtectedRange], protectedIds: Set<Int>? = nil) {
        let string = text as NSString
        func isBoundary(_ offset: Int) -> Bool {
            guard offset > 0 && offset < string.length else { return true }
            return !(0xd800...0xdbff).contains(string.character(at: offset - 1)) || !(0xdc00...0xdfff).contains(string.character(at: offset))
        }
        let valid = ranges.filter { $0.range.location >= 0 && $0.range.length > 0 && $0.range.location <= string.length && $0.range.length <= string.length - $0.range.location && isBoundary($0.range.location) && isBoundary(NSMaxRange($0.range)) }
        let protectedIds = protectedIds ?? Set(valid.map(\.id))
        let boundaries = Set([0, string.length] + valid.flatMap { [$0.range.location, NSMaxRange($0.range)] }).sorted()
        var segments: [Segment] = []
        for (start, end) in zip(boundaries, boundaries.dropFirst()) where end > start {
            let ids = valid.filter { $0.range.location <= start && NSMaxRange($0.range) >= end }.map(\.id)
            segments.append(Segment(text: string.substring(with: NSRange(location: start, length: end - start)), id: ids.first(where: { protectedIds.contains($0) }), entityIds: ids))
        }
        self.segments = segments
    }

    public func restore(translations: [String]) -> (text: String, ranges: [ProtectedRange]) {
        precondition(translations.count == segments.count)
        var text = ""
        var ranges: [Int: NSRange] = [:]
        for (index, segment) in segments.enumerated() {
            let value: String
            if segment.id != nil || segment.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { value = segment.text }
            else {
                let leading = String(segment.text.prefix { $0.isWhitespace })
                let trailing = String(segment.text.reversed().prefix { $0.isWhitespace }.reversed())
                value = leading + translations[index].trimmingCharacters(in: .whitespacesAndNewlines) + trailing
            }
            let start = text.utf16.count
            for id in segment.entityIds {
                if let previous = ranges[id] { ranges[id] = NSRange(location: previous.location, length: start + value.utf16.count - previous.location) }
                else { ranges[id] = NSRange(location: start, length: value.utf16.count) }
            }
            text += value
        }
        return (text, ranges.filter { $0.value.length > 0 }.map { ProtectedRange(range: $0.value, id: $0.key) }.sorted { $0.range.location == $1.range.location ? $0.id < $1.id : $0.range.location < $1.range.location })
    }

    public static func literalLinkRanges(in text: String) -> [NSRange] {
        guard let detector = self.detector else { return [] }
        return detector.matches(in: text, range: NSRange(location: 0, length: text.utf16.count)).map { $0.range }
    }
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
}
