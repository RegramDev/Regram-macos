import Foundation
import RegramCore
import SwiftSignalKit

public func regramLLMConfiguration(settings: RegramAccountSettings) throws -> RGLLMTranslationConfiguration {
    let prefix = "translationLLM"
    return RGLLMTranslationConfiguration(
        format: RGLLMAPIFormat(rawValue: settings[prefix + "APIFormat"].string) ?? .openai,
        baseURL: settings[prefix + "BaseURL"].string,
        endpoint: "",
        apiKey: try RegramCredentials.shared.read(purpose: .translation),
        model: settings[prefix + "Model"].string,
        prompt: settings[prefix + "Prompt"].string,
        temperature: Double(settings[prefix + "TemperatureTenths"].integer) / 10.0
    )
}

public enum RegramTranslationFallback {
    public static var translate: (String, String) -> Signal<String, TranslateFetchError> = { text, to in googleTranslate(text, to) }
}

public func regramExternalTranslate(text: String, to: String, accountId _: Int64, settings: RegramAccountSettings, context: [String] = [], permitsNetworkFallback: @escaping () -> Signal<Bool, NoError> = { .single(true) }, telegramTranslate: ((String, String) -> Signal<String, TranslateFetchError>)? = nil) -> Signal<String, TranslateFetchError> {
    guard let provider = RegramChatTranslationPolicy.provider(settings: settings) else { return .fail(.network) }
    func authorized(_ request: @escaping () -> Signal<String, TranslateFetchError>) -> Signal<String, TranslateFetchError> {
        deferred {
            permitsNetworkFallback() |> take(1) |> castError(TranslateFetchError.self) |> mapToSignal { allowed in
                allowed ? request() : .fail(.outdated)
            }
        }
    }
    if provider == .telegram {
        guard let telegramTranslate else { return authorized { RegramTranslationFallback.translate(text, to) } }
        return rgTranslateInChunks(text, to, maxLength: 1024) { chunk, target in
            authorized { telegramTranslate(chunk, target) }
        }
        |> `catch` { error -> Signal<String, TranslateFetchError> in
            if case .outdated = error { return .fail(error) }
            return authorized { RegramTranslationFallback.translate(text, to) }
        }
    }
    return authorized {
        switch provider {
        case .telegram: return .fail(.network)
        case .system: return regramSystemTranslate(text: text, to: to)
        case .google: return googleTranslate(text, to)
        case .yandex: return yandexTranslate(text, to)
        case .transmart: return tranSmartTranslate(text, to)
        case .llm:
            guard let configuration = try? regramLLMConfiguration(settings: settings) else { return .fail(.network) }
            return llmTranslate(text, to, context: settings["translationLLMUseContext"].bool ? Array(context.suffix(RegramLLMContextPolicy.maxMessages)).map { String($0.prefix(RegramLLMContextPolicy.maxCharactersPerMessage)) } : [], configuration: configuration)
        }
    }
}

public func regramSTTConfiguration(settings: RegramAccountSettings) throws -> RGSTTConfiguration {
    try RGSTTConfiguration(baseURL: settings["sttBaseURL"].string,
                          endpoint: settings["sttEndpoint"].string,
                          model: settings["sttModel"].string,
                          language: settings["sttLanguage"].string,
                          prompt: settings["sttPrompt"].string,
                          apiKey: RegramCredentials.shared.read(purpose: .transcription))
}
