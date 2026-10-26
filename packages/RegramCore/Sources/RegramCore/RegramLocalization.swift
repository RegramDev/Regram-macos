import Foundation

public func regramLocalizedString(_ key: String, languageCode: String) -> String {
    let code = languageCode.lowercased()
    let language: String
    if code.hasPrefix("zh") { language = code.contains("hant") || code.contains("tw") || code.contains("hk") ? "zh-Hant" : "zh-Hans" }
    else { language = "en" }
    let bundle = Bundle.module.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? Bundle.module
    return bundle.localizedString(forKey: key, value: nil, table: "Regram")
}
