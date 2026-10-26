import Foundation
import RegramCore
import SwiftSignalKit

public func regramLLMConfiguration(accountId: Int64, purpose: RegramCredentialPurpose, settings: RegramAccountSettings) throws -> RGLLMTranslationConfiguration {
    let prefix = purpose == .summary ? "summaryLLM" : "translationLLM"
    return RGLLMTranslationConfiguration(
        format: RGLLMAPIFormat(rawValue: settings[prefix + "APIFormat"].string) ?? .openai,
        baseURL: settings[prefix + "BaseURL"].string,
        endpoint: settings[prefix + "Endpoint"].string,
        apiKey: try RegramCredentials.shared.read(accountId: accountId, purpose: purpose),
        model: settings[prefix + "Model"].string,
        prompt: settings[prefix + "Prompt"].string,
        temperature: Double(settings[prefix + "TemperatureTenths"].integer) / 10.0
    )
}

public func regramExternalTranslate(text: String, to: String, accountId: Int64, settings: RegramAccountSettings, context: [String] = [], permitsNetworkFallback: @escaping () -> Signal<Bool, NoError> = { .single(true) }, telegramTranslate: ((String, String) -> Signal<String, TranslateFetchError>)? = nil) -> Signal<String, TranslateFetchError> {
    guard let provider = RegramChatTranslationPolicy.provider(settings: settings) else { return .fail(.network) }
    return permitsNetworkFallback() |> take(1) |> castError(TranslateFetchError.self) |> mapToSignal { allowed in
        guard allowed else { return .fail(.outdated) }
        switch provider {
        case .telegram: return telegramTranslate?(text, to) ?? .fail(.network)
        case .system: return regramSystemTranslate(text: text, to: to)
        case .google: return googleTranslate(text, to)
        case .googleCN: return googleCNTranslate(text, to)
        case .microsoft: return microsoftTranslate(text, to)
        case .yandex: return yandexTranslate(text, to)
        case .transmart: return tranSmartTranslate(text, to)
        case .llm:
            guard let configuration = try? regramLLMConfiguration(accountId: accountId, purpose: .translation, settings: settings) else { return .fail(.network) }
            return llmTranslate(text, to, context: settings["translationLLMUseContext"].bool ? Array(context.suffix(RegramLLMContextPolicy.maxMessages)).map { String($0.prefix(RegramLLMContextPolicy.maxCharactersPerMessage)) } : [], configuration: configuration)
        }
    }
}

public func regramSTTConfiguration(accountId: Int64, settings: RegramAccountSettings) throws -> RGSTTConfiguration {
    try RGSTTConfiguration(baseURL: settings["sttBaseURL"].string,
                          endpoint: settings["sttEndpoint"].string,
                          model: settings["sttModel"].string,
                          language: settings["sttLanguage"].string,
                          prompt: settings["sttPrompt"].string,
                          apiKey: RegramCredentials.shared.read(accountId: accountId, purpose: .transcription))
}
