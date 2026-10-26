import Foundation

public enum RegramChatLanguagePolicy {
    public struct Sample {
        public let text: String
        public let incoming: Bool
        public let excludedRanges: [NSRange]
        public let languageHint: String?

        public init(text: String, incoming: Bool, excludedRanges: [NSRange] = [], languageHint: String? = nil) {
            self.text = text
            self.incoming = incoming
            self.excludedRanges = excludedRanges
            self.languageHint = languageHint
        }
    }

    public static func comparisonCode(_ code: String) -> String {
        let code = code.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init) ?? ""
        return code == "nb" ? "no" : code
    }

    public static func targetCode(_ code: String) -> String {
        let code = code.lowercased().replacingOccurrences(of: "_", with: "-")
        if code.hasPrefix("zh-hant") || code == "zh-tw" || code == "zh-hk" { return "zh-TW" }
        if code.hasPrefix("zh-hans") || code == "zh-cn" || code == "zh-sg" { return "zh-CN" }
        return comparisonCode(code)
    }

    public static func systemLanguages(_ preferred: [String]) -> [String] {
        var languages = preferred.prefix(2).map(comparisonCode)
        if languages.count == 2 && languages != ["en", "ru"] { languages = Array(languages.prefix(1)) }
        return languages
    }

    public static func ignoredLanguages(interfaceLanguage: String, configured: Set<String>, systemLanguages: [String]) -> Set<String> {
        if !configured.isEmpty { return Set(configured.map(comparisonCode)) }
        return Set([comparisonCode(interfaceLanguage)] + self.systemLanguages(systemLanguages)).subtracting([""])
    }

    public static func canDisplay(source: String, target: String, interfaceLanguage: String, active: Bool) -> Bool {
        let source = comparisonCode(source)
        let target = comparisonCode(target)
        guard !source.isEmpty && !target.isEmpty && source != target else { return false }
        return source != comparisonCode(interfaceLanguage) || active
    }

    public static func isFresh(timestamp: Int32?, now: Int32) -> Bool {
        guard let timestamp else { return false }
        let age = Int64(now) - Int64(timestamp)
        return age >= 0 && age < 60 * 60
    }

    public static func recognitionText(_ sample: Sample) -> String {
        let text = NSMutableString(string: String(sample.text.prefix(256)))
        let ranges = sample.excludedRanges.compactMap { range -> NSRange? in
            guard range.location >= 0, range.location < text.length, range.length > 0 else { return nil }
            return NSRange(location: range.location, length: min(range.length, text.length - range.location))
        }.sorted { $0.location < $1.location }
        var merged: [NSRange] = []
        for range in ranges {
            if let last = merged.last, NSMaxRange(last) >= range.location {
                merged[merged.count - 1] = NSUnionRange(last, range)
            } else { merged.append(range) }
        }
        for range in merged.reversed() { text.deleteCharacters(in: range) }
        return text as String
    }

    public static func dominantLanguage(samples: [Sample], supported: Set<String>, detect: (String) -> String?) -> String? {
        var weights: [String: Int] = [:]
        var order: [String] = []
        var recognized = 0
        for sample in samples where sample.incoming && sample.text.count >= 10 {
            let language: String?
            if let hint = sample.languageHint, !hint.isEmpty { language = comparisonCode(hint) }
            else {
                let text = recognitionText(sample)
                guard text.count >= 10 else { continue }
                language = detect(text).map(comparisonCode)
            }
            guard let language, supported.contains(language) else { continue }
            if weights[language] == nil { order.append(language) }
            weights[language, default: 0] += sample.text.count
            recognized += 1
            if recognized >= 16 { break }
        }
        return order.max { weights[$0, default: 0] < weights[$1, default: 0] }
    }
}
