import Foundation
import SwiftSignalKit


private func rgFormBody(_ fields: [(String, String)]) -> Data {
    return Data(fields.map { "\(rgTranslateEncode($0.0))=\(rgTranslateEncode($0.1))" }.joined(separator: "&").utf8)
}

private func rgRandomHex() -> String {
    return UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
}

private func rgBaseLanguageCode(_ language: String) -> String {
    let code = getGTranslateLang(language)
    switch code {
    case "zh-CN", "zh-TW":
        return "zh"
    case "iw":
        return "he"
    default:
        return code
    }
}



private func rgYandexTranslateChunk(_ text: String, _ toLang: String, fromLang: String?) -> Signal<String, TranslateFetchError> {
    guard let url = URL(string: "https://translate.yandex.net/api/v1/tr.json/translate?srv=android&uuid=\(rgRandomHex())&id=\(rgRandomHex())-9-0") else {
        return .fail(.network)
    }
    let target = rgBaseLanguageCode(toLang)
    let source = fromLang.flatMap { $0.isEmpty || $0 == "auto" ? nil : rgBaseLanguageCode($0) }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = rgFormBody([("text", text), ("lang", source.map { "\($0)-\(target)" } ?? target)])
    request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
    request.setValue("Mozilla/5.0 (Linux; Android 10; SM-G9600) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/70.0.3538.0 Mobile Safari/537.36", forHTTPHeaderField: "User-Agent")
    return rgTranslatePerform(request)
    |> mapToSignal { data -> Signal<String, TranslateFetchError> in
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let code = object["code"] as? Int, code == 200, let texts = object["text"] as? [String], !texts.isEmpty else {
            return .fail(.network)
        }
        return .single(texts.joined())
    }
}

public func yandexTranslate(_ text: String, _ toLang: String, fromLang: String? = nil) -> Signal<String, TranslateFetchError> {
    return rgTranslateInChunks(text, toLang, { chunk, lang in
        return rgYandexTranslateChunk(chunk, lang, fromLang: fromLang)
    })
}


private let rgTranSmartLanguages: Set<String> = ["ar", "fr", "fil", "lo", "ja", "it", "hi", "id", "vi", "de", "km", "ms", "th", "tr", "zh", "ru", "ko", "pt", "es", "en"]

private func rgTranSmartLanguage(_ language: String) -> String {
    let code = rgBaseLanguageCode(language)
    return code == "tl" ? "fil" : code
}

private func rgTranSmartHeader(_ function: String) -> [String: Any] {
    return [
        "fn": function,
        "client_key": "browser-chrome-120.0.0-Mac OS-\(UUID().uuidString)-\(Int(Date().timeIntervalSince1970 * 1000.0))",
        "session": "",
        "user": ""
    ]
}

private func rgTranSmartRequest(_ body: [String: Any]) -> Signal<[String: Any], TranslateFetchError> {
    guard let url = URL(string: "https://transmart.qq.com/api/imt"), let data = try? JSONSerialization.data(withJSONObject: body) else {
        return .fail(.network)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = data
    request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
    request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
    return rgTranslatePerform(request)
    |> mapToSignal { data -> Signal<[String: Any], TranslateFetchError> in
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .fail(.network)
        }
        return .single(object)
    }
}

private func rgTranSmartSourceLanguage(_ text: String, fromLang: String?) -> Signal<String, TranslateFetchError> {
    if let fromLang, !fromLang.isEmpty, fromLang != "auto" {
        return .single(rgTranSmartLanguage(fromLang))
    }
    return rgTranSmartRequest(["header": rgTranSmartHeader("text_analysis"), "text": text])
    |> mapToSignal { object -> Signal<String, TranslateFetchError> in
        guard let language = object["language"] as? String, !language.isEmpty else {
            return .fail(.network)
        }
        return .single(rgTranSmartLanguage(language))
    }
}

private func rgTranSmartTranslateChunk(_ text: String, _ toLang: String, fromLang: String?) -> Signal<String, TranslateFetchError> {
    let target = rgTranSmartLanguage(toLang)
    guard rgTranSmartLanguages.contains(target) else {
        return .fail(.network)
    }
    return rgTranSmartSourceLanguage(text, fromLang: fromLang)
    |> mapToSignal { source -> Signal<String, TranslateFetchError> in
        if source == target {
            return .single(text)
        }
        guard rgTranSmartLanguages.contains(source) else {
            return .fail(.network)
        }
        let body: [String: Any] = [
            "header": rgTranSmartHeader("auto_translation"),
            "type": "plain",
            "model_category": "normal",
            "text_domain": "",
            "source": [
                "lang": source,
                "text_list": text.components(separatedBy: "\n")
            ],
            "target": [
                "lang": target
            ]
        ]
        return rgTranSmartRequest(body)
        |> mapToSignal { object -> Signal<String, TranslateFetchError> in
            guard let translations = object["auto_translation"] as? [String], !translations.isEmpty else {
                return .fail(.network)
            }
            return .single(translations.joined(separator: "\n"))
        }
    }
}

public func tranSmartTranslate(_ text: String, _ toLang: String, fromLang: String? = nil) -> Signal<String, TranslateFetchError> {
    return rgTranslateInChunks(text, toLang, { chunk, lang in
        return rgTranSmartTranslateChunk(chunk, lang, fromLang: fromLang)
    })
}
