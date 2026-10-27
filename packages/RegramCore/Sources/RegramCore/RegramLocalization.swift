import Foundation

public enum RegramLanguagePack {
    private static let tables: [String: [String: String]] = {
        var result: [String: [String: String]] = [:]
        for language in ["en", "zh-Hans", "zh-Hant"] {
            guard let folder = Bundle.module.path(forResource: language, ofType: "lproj"),
                  let values = NSDictionary(contentsOfFile: folder + "/Regram.strings") as? [String: String] else { continue }
            result[language] = values
        }
        return result
    }()

    private static func normalizedLanguageCode(_ languageCode: String) -> String {
        var code = languageCode.lowercased().replacingOccurrences(of: "_", with: "-")
        if code.hasSuffix("-raw") { code = String(code.dropLast(4)) }
        if code == "regram-zh-hans" || code == "zhcncc" { return "zh-hans" }
        return code
    }

    public static func language(_ languageCode: String) -> String {
        let code = normalizedLanguageCode(languageCode)
        if code.hasPrefix("zh") { return code.contains("hant") || code.contains("tw") || code.contains("hk") || code.contains("mo") ? "zh-Hant" : "zh-Hans" }
        return "en"
    }

    public static func strings(languageCode: String) -> [String: String] {
        tables[language(languageCode)] ?? tables["en"] ?? [:]
    }

    public static func nativeMacOSStrings(languageCode: String) -> [String: String] {
        let code = normalizedLanguageCode(languageCode)
        guard code.hasPrefix("zh") || code.hasPrefix("en") else { return [:] }
        let prefix = "native.macos."
        return Dictionary(uniqueKeysWithValues: strings(languageCode: languageCode).compactMap { key, value in
            key.hasPrefix(prefix) ? (String(key.dropFirst(prefix.count)), value) : nil
        })
    }
}

public func regramLocalizedString(_ key: String, languageCode: String) -> String {
    RegramLanguagePack.strings(languageCode: languageCode)[key] ?? RegramLanguagePack.strings(languageCode: "en")[key] ?? key
}
