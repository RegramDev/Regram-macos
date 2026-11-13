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
        let code = code.lowercased().replacingOccurrences(of: "_", with: "-")
        let components = code.split(separator: "-")
        let language = components.first.map(String.init) ?? ""
        if code == "zhcncc" || code == "zhcncc-raw" || components.starts(with: ["regram", "zh", "hans"]) { return "zh-CN" }
        if language == "zh" {
            if components.contains("hans") { return "zh-CN" }
            if components.contains("hant") || components.contains("tw") || components.contains("hk") || components.contains("mo") { return "zh-TW" }
            if components.contains("cn") || components.contains("sg") { return "zh-CN" }
        }
        if language == "nb" { return "no" }
        if language == "iw" { return "he" }
        return language
    }

    public static func targetCode(_ code: String) -> String {
        let code = comparisonCode(code)
        return code == "zh" ? "zh-CN" : code
    }

    public static func interfaceCode(primary: String, base: String) -> String {
        let primary = comparisonCode(primary)
        return isChinese(primary) ? targetCode(primary) : targetCode(base)
    }

    private static func isChinese(_ code: String) -> Bool {
        code == "zh" || code == "zh-CN" || code == "zh-TW"
    }

    public static func isIgnored(source: String, languages: Set<String>) -> Bool {
        languages.contains(comparisonCode(source))
    }

    public static func canTranslateMessage(source: String?, interfaceLanguage: String, configured: Set<String>) -> Bool {
        guard let language = source else { return true }
        let interfaceLanguage = targetCode(interfaceLanguage)
        let source = comparisonCode(language)
        if !configured.isEmpty, isIgnored(source: source, languages: Set(configured.map(targetCode))) { return false }
        return source != interfaceLanguage && !(source == "zh" && isChinese(interfaceLanguage))
    }

    public static func systemLanguages(_ preferred: [String]) -> [String] {
        var languages = preferred.prefix(2).map(comparisonCode)
        if languages.count == 2 && languages != ["en", "ru"] { languages = Array(languages.prefix(1)) }
        return languages
    }

    public static func ignoredLanguages(interfaceLanguage: String, configured: Set<String>, systemLanguages: [String]) -> Set<String> {
        if !configured.isEmpty { return Set(configured.map(targetCode)) }
        let interfaceLanguage = targetCode(interfaceLanguage)
        let preferred = self.systemLanguages(systemLanguages).filter { !(isChinese(interfaceLanguage) && isChinese($0)) }
        return Set([interfaceLanguage] + preferred).subtracting([""])
    }

    public static func canDisplay(source: String, target: String, interfaceLanguage: String, active: Bool) -> Bool {
        let source = comparisonCode(source)
        let target = targetCode(target)
        let interfaceLanguage = targetCode(interfaceLanguage)
        guard !source.isEmpty, !target.isEmpty, source != target, !(source == "zh" && isChinese(target)) else { return false }
        return active || (source != interfaceLanguage && !(source == "zh" && isChinese(interfaceLanguage)))
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
            let hint = sample.languageHint.map(comparisonCode)
            let language: String?
            if let hint, !hint.isEmpty, hint != "zh" {
                language = hint
            } else {
                let text = recognitionText(sample)
                guard text.count >= 10 else { continue }
                let detected = detect(text).map(comparisonCode)
                language = hint == "zh" && detected.map(isChinese) != true ? nil : detected
            }
            guard let language, supported.contains(language) || (isChinese(language) && supported.contains("zh")) else { continue }
            if weights[language] == nil { order.append(language) }
            weights[language, default: 0] += sample.text.count
            recognized += 1
            if recognized >= 16 { break }
        }
        return order.max { weights[$0, default: 0] < weights[$1, default: 0] }
    }
}
