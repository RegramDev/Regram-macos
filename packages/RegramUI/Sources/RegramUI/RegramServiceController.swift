import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import Postbox
import InputDataUI
import GeneralRows
import AlertsUI
import RegramCore
import RegramServices

private struct ServiceDraft: Equatable {
    var fields: [String: String]
    var format: String
    var temperatureTenths: Int64
    var useContext: Bool
    var summaryEnabled: Bool
    var transcriptionBackend: String
    var models: [String] = []
    var request: String?
}

private func regramServiceErrorDescription(_ error: Error) -> String {
    if let error = error as? RGSTTConfigurationError { return regramString(error.localizationKey) }
    if let error = error as? RegramKeychainError { return regramString("RG.STT.Error.Keychain") + " (\(error.status))" }
    if let error = error as? RGTranscriptionError {
        let key: String
        switch error {
        case .download: key = "Download"
        case .invalidAudio: key = "InvalidAudio"
        case .fileTooLarge: key = "FileTooLarge"
        case .cancelled: key = "Cancelled"
        case .timeout: key = "Timeout"
        case .invalidResponse: key = "InvalidResponse"
        case .noSpeech: key = "NoSpeech"
        case .configuration, .http, .network: return error.localizedDescription
        }
        return regramString("RG.STT.Error." + key)
    }
    return error.localizedDescription
}

public func RegramServiceController(context: any AccountContextProtocol, purpose: RegramCredentialPurpose, focusSetting: String? = nil) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let settings = RegramPreferences.shared.settings(accountId: accountId)
    let page = purpose == .summary ? "summary" : purpose == .translation ? "llm" : "stt"
    func fieldIdentifier(_ field: String) -> InputDataIdentifier {
        let names = ["BaseURL": "baseURL", "APIKey": "apiKey", "Endpoint": "endpoint", "Model": "model", "Language": "language", "Prompt": "prompt"]
        return InputDataIdentifier(page + "." + (names[field] ?? field))
    }
    let prefix = purpose == .summary ? "summaryLLM" : purpose == .translation ? "translationLLM" : "stt"
    let suffixes = purpose == .transcription ? ["BaseURL", "Endpoint", "Model", "Language", "Prompt"] : ["BaseURL", "Endpoint", "Model", "Prompt"]
    var fields = Dictionary(uniqueKeysWithValues: suffixes.map { ($0, settings[prefix + $0].string) })
    fields["APIKey"] = (try? RegramCredentials.shared.read(accountId: accountId, purpose: purpose)) ?? ""
    let initial = ServiceDraft(fields: fields, format: settings[prefix + "APIFormat"].string, temperatureTenths: settings[prefix + "TemperatureTenths"].integer, useContext: settings["translationLLMUseContext"].bool, summaryEnabled: settings["messageSummaryEnabled"].bool, transcriptionBackend: settings["transcriptionBackend"].string)
    let state = Atomic(value: initial)
    let promise = ValuePromise(initial, ignoreRepeated: true)
    let request = MetaDisposable()
    var requestGeneration = UUID()
    var credentialSaveFailed = false

    func update(_ transform: (inout ServiceDraft) -> Void, persist: Bool = false) {
        let before = state.with { $0 }
        let next = state.modify { current in var value = current; transform(&value); return value }
        if persist {
            if before.fields["APIKey"] != next.fields["APIKey"] {
                do {
                    try RegramCredentials.shared.write(next.fields["APIKey"] ?? "", accountId: accountId, purpose: purpose)
                    credentialSaveFailed = false
                } catch {
                    if !credentialSaveFailed { alert(for: context.window, header: regramString(purpose == .transcription ? "RG.STTSaveFailed" : "LLMTranslation.Title"), info: purpose == .transcription ? regramServiceErrorDescription(error) : regramString("LLMTranslation.KeySaveFailed")) }
                    credentialSaveFailed = true
                }
            }
            RegramPreferences.shared.update(accountId: accountId) { value in
                var configurationChanged = false
                for key in suffixes where before.fields[key] != next.fields[key] {
                    value[prefix + key] = .string(next.fields[key] ?? "")
                    configurationChanged = true
                }
                if purpose != .transcription {
                    if before.format != next.format { value[prefix + "APIFormat"] = .string(next.format); configurationChanged = true }
                    if before.temperatureTenths != next.temperatureTenths { value[prefix + "TemperatureTenths"] = .integer(next.temperatureTenths); configurationChanged = true }
                }
                if purpose == .translation, before.useContext != next.useContext { value["translationLLMUseContext"] = .bool(next.useContext); configurationChanged = true }
                if purpose == .summary, before.summaryEnabled != next.summaryEnabled { value["messageSummaryEnabled"] = .bool(next.summaryEnabled) }
                if purpose == .transcription, before.transcriptionBackend != next.transcriptionBackend { value["transcriptionBackend"] = .string(next.transcriptionBackend); configurationChanged = true }
                if configurationChanged || before.fields["APIKey"] != next.fields["APIKey"] { value["serviceConfigurationRevision"] = .integer(value["serviceConfigurationRevision"].integer &+ 1) }
            }
        }
        promise.set(next)
    }

    func configuration(_ draft: ServiceDraft) -> RGLLMTranslationConfiguration {
        RGLLMTranslationConfiguration(format: RGLLMAPIFormat(rawValue: draft.format) ?? .openai, baseURL: draft.fields["BaseURL"] ?? "", endpoint: draft.fields["Endpoint"] ?? "", apiKey: draft.fields["APIKey"] ?? "", model: draft.fields["Model"] ?? "", prompt: draft.fields["Prompt"] ?? "", temperature: Double(draft.temperatureTenths) / 10.0)
    }

    func cancel() {
        requestGeneration = UUID()
        request.set(nil)
        update { $0.request = nil }
    }

    func saveCredential(_ draft: ServiceDraft) -> Bool {
        guard credentialSaveFailed else { return true }
        do {
            try RegramCredentials.shared.write(draft.fields["APIKey"] ?? "", accountId: accountId, purpose: purpose)
            credentialSaveFailed = false
            return true
        } catch {
            alert(for: context.window, header: regramString(purpose == .transcription ? "RG.STTSaveFailed" : "LLMTranslation.Title"), info: purpose == .transcription ? regramServiceErrorDescription(error) : regramString("LLMTranslation.KeySaveFailed"))
            return false
        }
    }

    func test(_ draft: ServiceDraft) {
        guard draft.request == nil, saveCredential(draft) else { return }
        let generation = UUID()
        requestGeneration = generation
        update { $0.request = "test" }
        let signal: Signal<(String, Bool), NoError>
        if purpose == .transcription {
            do {
                let configuration = try RGSTTConfiguration(baseURL: draft.fields["BaseURL"] ?? "", endpoint: draft.fields["Endpoint"] ?? "", model: draft.fields["Model"] ?? "", language: draft.fields["Language"] ?? "", prompt: draft.fields["Prompt"] ?? "", apiKey: draft.fields["APIKey"] ?? "")
                guard let url = Bundle.module.url(forResource: "RGSTTTest", withExtension: "m4a") else { throw RGTranscriptionError.invalidAudio }
                signal = RGOpenAITranscriptionProvider.transcribe(configuration: configuration, audioURL: url) |> map { ($0, true) } |> `catch` { error in .single((regramServiceErrorDescription(error), false)) }
            } catch {
                update { $0.request = nil }
                alert(for: context.window, header: regramString("RG.STTTestFailed"), info: regramServiceErrorDescription(error))
                return
            }
        } else {
            signal = llmTestModel(configuration: configuration(draft)) |> map { (regramString("LLMTranslation.TestSucceeded"), true) } |> `catch` { error in .single((error.message, false)) }
        }
        request.set((signal |> deliverOnMainQueue).start(next: { message, succeeded in
            guard requestGeneration == generation else { return }
            update { $0.request = nil }
            showModalText(for: context.window, text: message, title: regramString(purpose == .transcription ? (succeeded ? "RG.STTTestSucceeded" : "RG.STTTestFailed") : purpose == .summary ? "Summary.Title" : "LLMTranslation.Title"))
        }, completed: { if requestGeneration == generation { update { $0.request = nil } } }))
    }

    func fetchModels(_ draft: ServiceDraft) {
        guard draft.request == nil, saveCredential(draft) else { return }
        let generation = UUID()
        requestGeneration = generation
        update { $0.request = "models" }
        request.set((llmFetchModels(configuration: configuration(draft)) |> deliverOnMainQueue).start(next: { models in
            guard requestGeneration == generation else { return }
            update { $0.request = nil; $0.models = models }
        }, error: { error in
            guard requestGeneration == generation else { return }
            update { $0.request = nil }
            alert(for: context.window, info: error.message)
        }))
    }

    let signal = combineLatest(promise.get(), appearanceSignal) |> map { draft, _ -> InputDataSignalValue in
        var rows: [InputDataEntry] = [.sectionId(0, type: .normal)]
        var section: Int32 = 1
        var index: Int32 = 0
        func notice(_ key: String) {
            rows.append(.desc(sectionId: section, index: index, text: .plain(regramString(key)), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
            index += 1
        }
        func nextSection() { rows.append(.sectionId(section, type: .normal)); section += 1 }
        func header(_ key: String) {
            rows.append(.desc(sectionId: section, index: index, text: .plain(regramString(key)), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
            index += 1
        }
        func input(_ key: String, title: String?, placeholder: String = "", viewType: GeneralViewType) {
            rows.append(.input(sectionId: section, index: index, value: .string(draft.fields[key] ?? ""), error: nil, identifier: fieldIdentifier(key), mode: key == "APIKey" ? .secure : .plain, data: .init(viewType: viewType), placeholder: title.map { .init(regramString($0)) }, inputPlaceholder: placeholder, filter: { $0 }, limit: key == "Prompt" ? 16000 : 2048))
            index += 1
        }
        func row(_ key: String, title: String, type: GeneralInteractedType, viewType: GeneralViewType, enabled: Bool = true, action: (() -> Void)? = nil) {
            let color: NSColor
            switch type {
            case .none, .loading: color = action == nil ? theme.colors.text : theme.colors.accent
            default: color = theme.colors.text
            }
            rows.append(.general(sectionId: section, index: index, value: .none, error: nil, identifier: InputDataIdentifier(page + "." + (["service_enabled": "enabled", "service_provider": "provider", "service_test": purpose == .transcription ? "test" : "testModel", "service_models": "fetchModels", "service_model_picker": "selectModel", "service_format": "format", "service_context": "useContext", "service_temperature_label": "temperatureLabel"][key] ?? key)), data: .init(name: regramString(title), color: color, type: type, viewType: viewType, enabled: enabled, action: action)))
            index += 1
        }

        if purpose == .summary {
            row("service_enabled", title: "Summary.Enabled", type: .switchable(draft.summaryEnabled), viewType: .singleItem, action: { update({ $0.summaryEnabled.toggle() }, persist: true) })
            notice("Summary.EnabledNotice")
            nextSection()
        }

        if purpose == .transcription {
            header("RG.STTSettings")
            let backends = ["default", "apple", "openAICompatible"].map { backend in
                ContextMenuItem(regramString("Settings.Transcription.Backend." + backend), handler: { update({ $0.transcriptionBackend = backend }, persist: true) }, state: draft.transcriptionBackend == backend ? .on : .off)
            }
            row("service_provider", title: "Settings.Transcription.Backend", type: .contextSelector(regramString("Settings.Transcription.Backend." + draft.transcriptionBackend), backends), viewType: .firstItem)
            input("BaseURL", title: "RG.STTBaseURL", placeholder: RGSTTConfiguration.defaultBaseURL, viewType: .innerItem)
            input("Endpoint", title: "RG.STTEndpoint", placeholder: RGSTTConfiguration.defaultEndpoint, viewType: .innerItem)
            input("APIKey", title: "RG.STTAPIKey", placeholder: regramString("RG.STTAPIKey.Placeholder"), viewType: .innerItem)
            input("Model", title: "RG.STTModel", placeholder: "gpt-4o-mini-transcribe", viewType: .innerItem)
            input("Language", title: "RG.STTLanguage", placeholder: regramString("RG.STTLanguage.Placeholder"), viewType: .lastItem)
            notice("RG.STTSettings.Footer")
            nextSection()
            header("RG.STTPrompt")
            input("Prompt", title: nil, placeholder: regramString("RG.STTPrompt.Placeholder"), viewType: .singleItem)
            notice("RG.STTPrompt.Footer")
            nextSection()
            row("service_test", title: draft.request == nil ? "RG.STTTest" : "RG.STT.Cancel", type: draft.request == nil ? .none : .loading, viewType: .singleItem, action: { if draft.request == nil { test(draft) } else { cancel() } })
            notice("RG.STTTest.Footer")
        } else {
            let format = RGLLMAPIFormat(rawValue: draft.format) ?? .openai
            let formats = RGLLMAPIFormat.allCases.map { value in
                ContextMenuItem(value == .openai ? "OpenAI" : "Anthropic", handler: {
                    cancel()
                    update({ $0.format = value.rawValue; $0.models = [] }, persist: true)
                }, state: format == value ? .on : .off)
            }
            row("service_format", title: "LLMTranslation.Format", type: .contextSelector(format == .openai ? "OpenAI" : "Anthropic", formats), viewType: .firstItem)
            input("BaseURL", title: "LLMTranslation.BaseURL", placeholder: format.defaultBaseURL, viewType: .innerItem)
            input("Endpoint", title: "LLMTranslation.Endpoint", placeholder: format.defaultTranslationEndpoint, viewType: .innerItem)
            input("APIKey", title: "LLMTranslation.APIKey", viewType: .lastItem)
            notice(purpose == .summary ? "Summary.ConnectionNotice" : "LLMTranslation.ConnectionNotice")
            nextSection()

            input("Model", title: "LLMTranslation.Model", viewType: .firstItem)
            if !draft.models.isEmpty {
                var choices = draft.models
                let current = draft.fields["Model"] ?? ""
                if !choices.contains(current) { choices.insert(current, at: 0) }
                let models = choices.map { model in ContextMenuItem(model.isEmpty ? regramString("LLMTranslation.SelectModel") : model, handler: { update({ $0.fields["Model"] = model }, persist: true) }, state: current == model ? .on : .off) }
                row("service_model_picker", title: "LLMTranslation.SelectModel", type: .contextSelector(draft.fields["Model"].flatMap { $0.isEmpty ? nil : $0 } ?? regramString("LLMTranslation.SelectModel"), models), viewType: .innerItem)
            }
            row("service_models", title: "LLMTranslation.FetchModels", type: draft.request == "models" ? .loading : .none, viewType: .innerItem, enabled: draft.request == nil, action: { fetchModels(draft) })
            row("service_test", title: "LLMTranslation.TestModel", type: draft.request == "test" ? .loading : .none, viewType: .lastItem, enabled: draft.request == nil && !(draft.fields["Model"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, action: { test(draft) })
            nextSection()

            header("LLMTranslation.Prompt")
            input("Prompt", title: nil, viewType: .firstItem)
            if purpose == .translation {
                row("service_context", title: "LLMTranslation.UseContext", type: .switchable(draft.useContext), viewType: .innerItem, action: { update({ $0.useContext.toggle() }, persist: true) })
            }
            row("service_temperature_label", title: "LLMTranslation.Temperature", type: .context(String(format: "%.1f", Double(draft.temperatureTenths) / 10.0)), viewType: .innerItem)
            rows.append(.custom(sectionId: section, index: index, value: .none, identifier: InputDataIdentifier(page + ".temperature"), equatable: InputDataEquatable(draft.temperatureTenths), comparable: nil, item: { size, stableId in
                PrecieSliderRowItem(size, stableId: stableId, current: CGFloat(draft.temperatureTenths) / 10.0, magnit: (0...10).map { CGFloat($0) / 10.0 }, update: { value in update({ $0.temperatureTenths = Int64((value * 10).rounded()) }, persist: true) }, viewType: .lastItem)
            }))
            index += 1
            notice(purpose == .summary ? "Summary.PromptNotice" : "LLMTranslation.PromptNotice")
        }
        return InputDataSignalValue(entries: rows)
    }

    let title = purpose == .summary ? "Summary.Title" : purpose == .translation ? "LLMTranslation.Title" : "Settings.Category.transcription"
    let controller = InputDataController(dataSignal: signal, title: regramString(title), updateDatas: { data in
        update({ draft in
            for key in suffixes + ["APIKey"] {
                if let value = data[fieldIdentifier(key)]?.stringValue { draft.fields[key] = value }
            }
        }, persist: true)
        return .fail(.none)
    }, removeAfterDisappear: false, hasDone: false, identifier: "regram." + page)
    controller.afterDisappear = { cancel() }
    controller.onDeinit = { request.dispose() }
    regramFocusSettings(controller, page: page, item: focusSetting)
    return controller
}
