import Foundation
import SwiftSignalKit

public enum RGTranscriptionError: LocalizedError {
    case configuration(String)
    case download
    case invalidAudio
    case fileTooLarge
    case cancelled
    case timeout
    case http(Int, String)
    case network(String)
    case invalidResponse
    case noSpeech

    public var errorDescription: String? {
        switch self {
        case let .configuration(message), let .network(message):
            return message
        case .download:
            return "Unable to download the audio. Please try again."
        case .invalidAudio:
            return "Unable to prepare a valid audio file."
        case .fileTooLarge:
            return "The audio exceeds the 25 MB upload limit."
        case .cancelled:
            return "Transcription cancelled. Tap to try again."
        case .timeout:
            return "Transcription timed out. Please try again."
        case let .http(status, message):
            return "HTTP \(status): \(message)"
        case .invalidResponse:
            return "The API response does not contain a valid transcription."
        case .noSpeech:
            return "No speech was recognized."
        }
    }
}

public enum RGOpenAITranscriptionProvider {
    static let maximumFileSize: Int64 = 25_000_000

    static func multipart(configuration: RGSTTConfiguration, audioURL: URL, bodyURL: URL, boundary: String) throws {
        let size = try audioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 else { throw RGTranscriptionError.invalidAudio }
        guard Int64(size) <= self.maximumFileSize else { throw RGTranscriptionError.fileTooLarge }
        guard FileManager.default.createFile(atPath: bodyURL.path, contents: nil) else {
            throw RGTranscriptionError.invalidAudio
        }
        let output = try FileHandle(forWritingTo: bodyURL)
        defer { try? output.close() }
        func write(_ value: String) throws { try output.write(contentsOf: Data(value.utf8)) }
        func field(_ name: String, _ value: String) throws {
            try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        try field("model", configuration.model)
        try field("response_format", "json")
        if !configuration.language.isEmpty {
            try field(configuration.model == "gpt-transcribe" ? "languages[]" : "language", configuration.language)
        }
        if !configuration.prompt.isEmpty { try field("prompt", configuration.prompt) }
        try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n")
        let input = try FileHandle(forReadingFrom: audioURL)
        defer { try? input.close() }
        while let data = try input.read(upToCount: 64 * 1024), !data.isEmpty {
            try output.write(contentsOf: data)
        }
        try write("\r\n--\(boundary)--\r\n")
    }

    static func parse(data: Data, response: HTTPURLResponse, apiKey: String) throws -> String {
        guard (200 ..< 300).contains(response.statusCode) else {
            let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let message = (object?["error"] as? [String: Any])?["message"] as? String
            var description = message ?? HTTPURLResponse.localizedString(forStatusCode: response.statusCode)
            if !apiKey.isEmpty { description = description.replacingOccurrences(of: apiKey, with: "[REDACTED]") }
            throw RGTranscriptionError.http(response.statusCode, String(description.prefix(512)))
        }
        struct Response: Decodable { let text: String }
        guard let result = try? JSONDecoder().decode(Response.self, from: data) else {
            throw RGTranscriptionError.invalidResponse
        }
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw RGTranscriptionError.noSpeech }
        return text
    }

    public static func transcribe(configuration: RGSTTConfiguration, audioURL: URL) -> Signal<String, RGTranscriptionError> {
        return Signal { subscriber in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("rg-stt-upload-\(UUID().uuidString)", isDirectory: true)
            let taskDisposable = MetaDisposable()
            let cancelled = Atomic(value: false)
            Queue.concurrentDefaultQueue().async {
                do {
                    if cancelled.with({ $0 }) { return }
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let bodyURL = directory.appendingPathComponent("body")
                    let boundary = "RGSTT-\(UUID().uuidString)"
                    try self.multipart(configuration: configuration, audioURL: audioURL, bodyURL: bodyURL, boundary: boundary)
                    if cancelled.with({ $0 }) {
                        try? FileManager.default.removeItem(at: directory)
                        return
                    }
                    var request = URLRequest(url: configuration.url)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 120
                    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                    request.setValue("application/json", forHTTPHeaderField: "Accept")
                    if !configuration.apiKey.isEmpty {
                        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
                    }
                    let sessionConfiguration = URLSessionConfiguration.ephemeral
                    sessionConfiguration.timeoutIntervalForResource = 180
                    let session = URLSession(configuration: sessionConfiguration, delegate: RGSTTRedirectDelegate(), delegateQueue: nil)
                    let task = session.uploadTask(with: request, fromFile: bodyURL) { data, response, error in
                        defer {
                            session.finishTasksAndInvalidate()
                            try? FileManager.default.removeItem(at: directory)
                        }
                        guard !cancelled.with({ $0 }) else { return }
                        if let error = error as NSError? {
                            subscriber.putError(error.code == NSURLErrorTimedOut ? .timeout : .network(error.localizedDescription))
                            return
                        }
                        guard let data, let response = response as? HTTPURLResponse else {
                            subscriber.putError(.invalidResponse)
                            return
                        }
                        do {
                            subscriber.putNext(try self.parse(data: data, response: response, apiKey: configuration.apiKey))
                            subscriber.putCompletion()
                        } catch let error as RGTranscriptionError {
                            subscriber.putError(error)
                        } catch {
                            subscriber.putError(.invalidResponse)
                        }
                    }
                    taskDisposable.set(ActionDisposable { task.cancel(); session.invalidateAndCancel() })
                    task.resume()
                } catch {
                    try? FileManager.default.removeItem(at: directory)
                    if !cancelled.with({ $0 }) { subscriber.putError((error as? RGTranscriptionError) ?? .invalidAudio) }
                }
            }
            return ActionDisposable {
                _ = cancelled.swap(true)
                taskDisposable.dispose()
            }
        }
    }
}

private final class RGSTTRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
