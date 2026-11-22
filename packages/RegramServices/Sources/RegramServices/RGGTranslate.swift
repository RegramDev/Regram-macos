import Foundation
import SwiftSignalKit

public enum TranslateFetchError {
    case outdated
    case network
}

private let rgTranslateSessionConfiguration: URLSessionConfiguration = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 20
    configuration.httpMaximumConnectionsPerHost = 8
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return configuration
}()
private let rgTranslateSession: URLSession = URLSession(configuration: rgTranslateSessionConfiguration)

private let rgLegacyUserAgent: String = "Mozilla/4.0 (compatible;MSIE 6.0;Windows NT 5.1;SV1;.NET CLR 1.1.4322;.NET CLR 2.0.50727;.NET CLR 3.0.04506.30)"
let rgUserAgent: String = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Mobile/15E148 Safari/604.1"

private let rgTranslateQueryAllowedCharacters: CharacterSet = {
    var characterSet: CharacterSet = .alphanumerics
    characterSet.insert(charactersIn: "-._~")
    return characterSet
}()

let rgTranslateMaxChunkLength: Int = 1200


private final class RGTranslateRequestLimiter {
    private let lock = NSLock()
    private let limit: Int
    private var running = 0
    private var nextToken: UInt64 = 0
    private var waiting: [(token: UInt64, start: () -> Void)] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire(_ start: @escaping () -> Void) -> UInt64? {
        lock.lock()
        if running < limit {
            running += 1
            lock.unlock()
            start()
            return nil
        }
        nextToken &+= 1
        let token = nextToken
        waiting.append((token, start))
        lock.unlock()
        return token
    }

    func cancel(_ token: UInt64) {
        lock.lock()
        waiting.removeAll { $0.token == token }
        lock.unlock()
    }

    func release() {
        lock.lock()
        if waiting.isEmpty {
            running -= 1
            lock.unlock()
        } else {
            let next = waiting.removeFirst()
            lock.unlock()
            next.start()
        }
    }
}

private let rgTranslateRequestLimiter = RGTranslateRequestLimiter(limit: 10)

func rgTranslatePerform(_ request: URLRequest) -> Signal<Data, TranslateFetchError> {
    return Signal { subscriber in
        let completed: Atomic<Bool> = Atomic(value: false)
        let started: Atomic<Bool> = Atomic(value: false)
        var request = request
        request.timeoutInterval = min(request.timeoutInterval, 20)
        let downloadTask: URLSessionDataTask = rgTranslateSession.dataTask(with: request, completionHandler: { data, response, _ in
            let _ = completed.swap(true)
            rgTranslateRequestLimiter.release()
            guard let response: HTTPURLResponse = response as? HTTPURLResponse, (200 ..< 300).contains(response.statusCode), let data: Data = data else {
                subscriber.putError(.network)
                return
            }
            subscriber.putNext(data)
            subscriber.putCompletion()
        })
        let token = rgTranslateRequestLimiter.acquire {
            let _ = started.swap(true)
            downloadTask.resume()
        }

        return ActionDisposable {
            if let token, !started.with({ $0 }) {
                rgTranslateRequestLimiter.cancel(token)
                if !started.with({ $0 }) { return }
            }
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

    return rgTranslateConcurrently(signals, chunkTimeout: chunkTimeout)
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

public let regramTranslationDefaultConcurrency = 6

public func regramTranslateConcurrently<Value, Failure>(_ signals: [Signal<Value, Failure>], limit: Int = regramTranslationDefaultConcurrency, chunkTimeout: Double, failure: Failure) -> Signal<[Value], Failure> {
    if signals.isEmpty { return .single([]) }
    return Signal { subscriber in
        let lock = NSLock()
        let timeoutQueue = Queue(name: "regram.translate-parallel")
        let disposables = DisposableSet()
        let limit = max(1, limit)
        var values: [Value?] = Array(repeating: nil, count: signals.count)
        var next = 0
        var active = 0
        var remaining = signals.count
        var finished = false
        var pumping = false
        var needsPump = false

        func fail(_ error: Failure) {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            lock.unlock()
            disposables.dispose()
            subscriber.putError(error)
        }

        func launch() -> Bool {
            lock.lock()
            guard !finished, active < limit, next < signals.count else { lock.unlock(); return false }
            let index = next
            next += 1
            active += 1
            lock.unlock()
            var received = false
            let disposable = MetaDisposable()
            disposables.add(disposable)
            disposable.set((signals[index] |> take(1) |> timeout(chunkTimeout, queue: timeoutQueue, alternate: .fail(failure))).start(next: { value in
                lock.lock()
                if !finished {
                    values[index] = value
                    received = true
                }
                lock.unlock()
            }, error: { error in
                fail(error)
            }, completed: {
                lock.lock()
                guard !finished else { lock.unlock(); return }
                guard received else {
                    lock.unlock()
                    fail(failure)
                    return
                }
                active -= 1
                remaining -= 1
                let done = remaining == 0
                if done { finished = true }
                let result = done ? values.compactMap { $0 } : []
                lock.unlock()
                if done {
                    subscriber.putNext(result)
                    subscriber.putCompletion()
                } else {
                    pump()
                }
            }))
            return true
        }

        func pump() {
            lock.lock()
            if pumping {
                needsPump = true
                lock.unlock()
                return
            }
            pumping = true
            lock.unlock()
            while true {
                lock.lock()
                needsPump = false
                lock.unlock()
                while launch() {}
                lock.lock()
                if !needsPump {
                    pumping = false
                    lock.unlock()
                    return
                }
                lock.unlock()
            }
        }

        pump()
        return ActionDisposable {
            lock.lock()
            finished = true
            lock.unlock()
            disposables.dispose()
        }
    }
}

func rgTranslateConcurrently(_ signals: [Signal<String, TranslateFetchError>], limit: Int = regramTranslationDefaultConcurrency, chunkTimeout: Double = 20.0) -> Signal<[String], TranslateFetchError> {
    regramTranslateConcurrently(signals, limit: limit, chunkTimeout: chunkTimeout, failure: .network)
}

public func regramTranslationConcurrency(backend: String) -> Int {
    switch backend {
    case "system": return 1
    case "llm": return 3
    default: return regramTranslationDefaultConcurrency
    }
}
