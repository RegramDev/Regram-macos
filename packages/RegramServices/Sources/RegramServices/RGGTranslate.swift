import Foundation
import SwiftSignalKit

public enum TranslateFetchError {
    case outdated
    case network
}

private let rgTranslateSessionConfiguration: URLSessionConfiguration = .ephemeral
private let rgTranslateSession: URLSession = URLSession(configuration: rgTranslateSessionConfiguration)

private let rgLegacyUserAgent: String = "Mozilla/4.0 (compatible;MSIE 6.0;Windows NT 5.1;SV1;.NET CLR 1.1.4322;.NET CLR 2.0.50727;.NET CLR 3.0.04506.30)"
let rgUserAgent: String = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Mobile/15E148 Safari/604.1"

private let rgTranslateQueryAllowedCharacters: CharacterSet = {
    var characterSet: CharacterSet = .alphanumerics
    characterSet.insert(charactersIn: "-._~")
    return characterSet
}()

let rgTranslateMaxChunkLength: Int = 1200


func rgTranslatePerform(_ request: URLRequest) -> Signal<Data, TranslateFetchError> {
    return Signal { subscriber in
        let completed: Atomic<Bool> = Atomic(value: false)
        let downloadTask: URLSessionDataTask = rgTranslateSession.dataTask(with: request, completionHandler: { data, response, _ in
            let _ = completed.swap(true)
            guard let response: HTTPURLResponse = response as? HTTPURLResponse, (200 ..< 300).contains(response.statusCode), let data: Data = data else {
                subscriber.putError(.network)
                return
            }
            subscriber.putNext(data)
            subscriber.putCompletion()
        })
        downloadTask.resume()

        return ActionDisposable {
            if !completed.with({ $0 }) {
                downloadTask.cancel()
            }
        }
    }
}

private func rgTranslateRequestData(url: URL, userAgent: String) -> Signal<Data, TranslateFetchError> {
    var request: URLRequest = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
    return rgTranslatePerform(request)
}

func rgTranslateEncode(_ text: String) -> String {
    return text.addingPercentEncoding(withAllowedCharacters: rgTranslateQueryAllowedCharacters) ?? ""
}


func rgTranslateInChunks(_ text: String, _ toLang: String, maxLength: Int = rgTranslateMaxChunkLength, chunkTimeout: Double = 20.0, _ translateChunk: @escaping (String, String) -> Signal<String, TranslateFetchError>) -> Signal<String, TranslateFetchError> {
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return .single(text)
    }

    let chunks = gtranslateSplitTextBySentences(text, maxChunkLength: maxLength)
    if chunks.count == 1 {
        return translateChunk(chunks[0], toLang)
    }

    let signals: [Signal<String, TranslateFetchError>] = chunks.map { chunk in
        if chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .single(chunk)
        }
        let leading = chunk.prefix(while: \.isWhitespace)
        let trailing = chunk.reversed().prefix(while: \.isWhitespace).reversed()
        return translateChunk(chunk.trimmingCharacters(in: .whitespacesAndNewlines), toLang) |> mapToSignal { value in
            let translated = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !translated.isEmpty else { return .fail(.network) }
            return .single(String(leading) + translated + String(trailing))
        }
    }

    return rgTranslateSequentially(signals, chunkTimeout: chunkTimeout)
    |> map { results in
        return results.joined()
    }
}

func rgTranslationSegmentTimeout(utf16Length: Int, maxChunkLength: Int, chunkTimeout: Double) -> Double {
    let effectiveChunkLength = max(1, maxChunkLength / 2)
    let estimatedChunks = max(1, Double(utf16Length / effectiveChunkLength) + 1)
    return (estimatedChunks + 1) * chunkTimeout
}


private func rgGoogleApiTranslateUrl(_ text: String, _ toLang: String) -> String {
    return "https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=\(getGTranslateLang(toLang))&dt=t&ie=UTF-8&oe=UTF-8&q=\(rgTranslateEncode(text))"
}

private func rgParseGoogleApiResponse(_ data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any], let blocks = json.first as? [Any] else {
        return nil
    }
    var result: String = ""
    for block in blocks {
        if let block = block as? [Any], let text = block.first as? String {
            result += text
        }
    }
    return result.isEmpty ? nil : result
}

private func rgGoogleApiTranslateChunk(_ text: String, _ toLang: String) -> Signal<String, TranslateFetchError> {
    guard let url: URL = URL(string: rgGoogleApiTranslateUrl(text, toLang)) else {
        return .fail(.network)
    }
    return rgTranslateRequestData(url: url, userAgent: rgUserAgent)
    |> mapToSignal { data -> Signal<String, TranslateFetchError> in
        guard let result: String = rgParseGoogleApiResponse(data) else {
            return .fail(.network)
        }
        return .single(result)
    }
}


private func rgGoogleDictTranslateUrl(_ text: String, _ toLang: String) -> String {
    return "https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl=auto&tl=\(getGTranslateLang(toLang))&q=\(rgTranslateEncode(text))"
}

private func rgParseGoogleDictResponse(_ data: Data) -> String? {
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any], let first = json.first else {
        return nil
    }
    let result: String?
    if let entry = first as? [Any] {
        result = entry.first as? String
    } else {
        result = first as? String
    }
    guard let result: String = result, !result.isEmpty else {
        return nil
    }
    return result
}

private func rgGoogleDictTranslateChunk(_ text: String, _ toLang: String) -> Signal<String, TranslateFetchError> {
    guard let url: URL = URL(string: rgGoogleDictTranslateUrl(text, toLang)) else {
        return .fail(.network)
    }
    return rgTranslateRequestData(url: url, userAgent: rgUserAgent)
    |> mapToSignal { data -> Signal<String, TranslateFetchError> in
        guard let result: String = rgParseGoogleDictResponse(data) else {
            return .fail(.network)
        }
        return .single(result)
    }
}



public func getGTranslateLang(_ userLang: String) -> String {
    var lang = userLang.replacingOccurrences(of: "_", with: "-").lowercased()
    let rawSuffix: String = "-raw"
    if lang.hasSuffix(rawSuffix) {
        lang = String(lang.dropLast(rawSuffix.count))
    }

    let components = lang.components(separatedBy: "-")
    if components.first == "zh" {
        if components.contains("hans") {
            return "zh-CN"
        }
        if components.contains("hant") || components.contains("tw") || components.contains("hk") || components.contains("mo") {
            return "zh-TW"
        }
        return "zh-CN"
    }

    switch lang {
    case "he":
        return "iw"
    default:
        break
    }

    lang = lang.components(separatedBy: "-")[0].components(separatedBy: "_")[0]

    return lang
}


public func googleTranslate(_ text: String, _ toLang: String) -> Signal<String, TranslateFetchError> {
    return rgTranslateInChunks(text, toLang, rgGoogleDictTranslateChunk)
    |> `catch` { _ in rgTranslateInChunks(text, toLang, rgGoogleApiTranslateChunk) }
}

public func gtranslateSplitTextBySentences(_ text: String, maxChunkLength: Int = 1500) -> [String] {
    let limit = max(1, maxChunkLength)
    guard text.utf16.count > limit else { return [text] }
    var chunks: [String] = []
    var start = text.startIndex
    while start < text.endIndex {
        var end = start
        var length = 0
        var paragraphBreak: String.Index?
        var sentenceBreak: String.Index?
        var wordBreak: String.Index?
        while end < text.endIndex {
            let character = text[end]
            let next = text.index(after: end)
            let width = text[end ..< next].utf16.count
            if end != start, length + width > limit { break }
            end = next
            length += width
            guard length >= limit / 2 else { continue }
            if character.isNewline {
                paragraphBreak = end
            } else if ".!?。！？".contains(character) {
                sentenceBreak = end
            } else if character.isWhitespace {
                wordBreak = end
            }
        }
        let boundary = end == text.endIndex ? end : paragraphBreak ?? sentenceBreak ?? wordBreak ?? end
        chunks.append(String(text[start ..< boundary]))
        start = boundary
    }
    return chunks
}

public func regramTranslateSequentially<Value, Failure>(_ signals: [Signal<Value, Failure>], chunkTimeout: Double, failure: Failure) -> Signal<[Value], Failure> {
    return Signal { subscriber in
        let disposable = MetaDisposable()
        let cancelled = Atomic(value: false)
        let queue = Queue(name: "regram.translate-chunks")
        var values: [Value] = []
        func next(_ index: Int) {
            guard !cancelled.with({ $0 }) else { return }
            guard index < signals.count else { subscriber.putNext(values); subscriber.putCompletion(); return }
            let current = MetaDisposable()
            disposable.set(current)
            var receivedValue = false
            current.set((signals[index] |> take(1) |> timeout(chunkTimeout, queue: queue, alternate: .fail(failure)) |> deliverOn(queue)).start(next: { value in
                receivedValue = true
                values.append(value)
                queue.justDispatch { next(index + 1) }
            }, error: { subscriber.putError($0) }, completed: {
                if !receivedValue { subscriber.putError(failure) }
            }))
        }
        queue.justDispatch { next(0) }
        return ActionDisposable { let _ = cancelled.swap(true); disposable.dispose() }
    }
}

func rgTranslateSequentially(_ signals: [Signal<String, TranslateFetchError>], chunkTimeout: Double = 20.0) -> Signal<[String], TranslateFetchError> {
    regramTranslateSequentially(signals, chunkTimeout: chunkTimeout, failure: .network)
}
