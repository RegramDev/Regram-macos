import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import Localization
import TelegramContext
import TelegramTheme
import InputDataUI
import AlertsUI
import RegramCore
import RegramServices

private struct SummaryState: Equatable {
    var busy = false
    var result = ""
    var error = ""
}

private func summaryMessage(_ message: Message) -> RegramSummaryMessage {
    RegramSummaryMessage(identifier: "\(message.id.peerId.toInt64()):\(message.id.namespace):\(message.id.id)", timestamp: Int64(message.timestamp), text: message.text,
                         isSecret: message.id.peerId.namespace == Namespaces.Peer.SecretChat,
                         isCopyProtected: message.isCopyProtected(),
                         isOneTime: message.containsSecretMedia || message.attributes.contains { $0 is AutoclearTimeoutMessageAttribute },
                         hasAttachment: message.media.contains { !($0 is TelegramMediaWebpage) } || message.attributes.contains { $0 is RichTextMessageAttribute })
}

private func summaryError(_ error: RegramSummarySelectionError) -> String {
    switch error {
    case .disabled: return regramString("summary.disabled")
    case .empty: return regramString("summary.empty")
    case .secretContent, .protectedContent, .unsupportedAttachment: return regramString("summary.unsupported")
    case .tooManyMessages, .tooManyBytes: return regramString("summary.tooLarge")
    case .invalidRange: return regramString("summary.invalidRange")
    }
}

private func summaryConfigurationIdentity(_ settings: RegramAccountSettings) -> [RegramValue] {
    ["messageSummaryEnabled", "serviceConfigurationRevision", "summaryLLMAPIFormat", "summaryLLMBaseURL", "summaryLLMEndpoint", "summaryLLMModel", "summaryLLMPrompt", "summaryLLMTemperatureTenths"].map { settings[$0] }
}

public func RegramMessageSummaryController(context: any AccountContextProtocol, messages: [Message], permitsTimeRange: Bool = false) -> InputDataController? {
    let accountId = context.peerId.toInt64()
    guard let first = messages.first, messages.allSatisfy({ $0.id.peerId == first.id.peerId && $0.threadId == first.threadId }) else {
        alert(for: context.window, info: regramString("summary.sameChat"))
        return nil
    }
    let selection: RegramSummarySelection
    switch RegramSummaryPolicy.prepare(messages.map(summaryMessage), permitsTimeRange: permitsTimeRange, enabled: RegramPreferences.shared.settings(accountId: accountId)["messageSummaryEnabled"].bool) {
    case let .success(value): selection = value
    case let .failure(error): alert(for: context.window, info: summaryError(error)); return nil
    }
    let state = Atomic(value: SummaryState())
    let promise = ValuePromise(SummaryState(), ignoreRepeated: true)
    let request = MetaDisposable()
    var generation = UUID()
    func update(_ transform: (inout SummaryState) -> Void) { promise.set(state.modify { value in var value = value; transform(&value); return value }) }
    func cancel() {
        generation = UUID()
        request.set(nil)
        update { $0.busy = false }
    }
    func start() {
        guard !state.with({ $0.busy }) else { cancel(); return }
        let settings = RegramPreferences.shared.settings(accountId: accountId)
        guard settings["messageSummaryEnabled"].bool else { update { $0.error = regramString("summary.disabled") }; return }
        let configuration: RGLLMTranslationConfiguration
        do { configuration = try regramLLMConfiguration(accountId: accountId, purpose: .summary, settings: settings) }
        catch { update { $0.error = error.localizedDescription }; return }
        guard !configuration.model.isEmpty else { context.bindings.rootNavigation().push(RegramServiceController(context: context, purpose: .summary)); return }
        let id = UUID()
        generation = id
        let identity = summaryConfigurationIdentity(settings)
        update { $0.busy = true; $0.error = "" }
        func currentMessages() -> Signal<Bool, RGLLMRequestError> {
            context.account.postbox.transaction { transaction -> Bool in
            messages.allSatisfy { original in
                guard let message = transaction.getMessage(original.id), message.stableVersion == original.stableVersion else { return false }
                if let cached = transaction.getPeerCachedData(peerId: message.id.peerId) as? CachedUserData, cached.flags.contains(.copyProtectionEnabled) || cached.flags.contains(.myCopyProtectionEnabled) { return false }
                return summaryMessage(message) == summaryMessage(original)
            }
            } |> castError(RGLLMRequestError.self)
        }
        let current = currentMessages()
        request.set((current |> mapToSignal { valid -> Signal<String, RGLLMRequestError> in
            guard valid, generation == id, summaryConfigurationIdentity(RegramPreferences.shared.settings(accountId: accountId)) == identity else { return .fail(RGLLMRequestError(regramString("summary.outdated"))) }
            return llmSummarize(selection.text, language: appCurrentLanguage.primaryLanguage.languageCode, configuration: configuration) |> mapToSignal { result in
                currentMessages() |> mapToSignal { valid in valid ? .single(result) : .fail(RGLLMRequestError(regramString("summary.outdated"))) }
            }
        } |> deliverOnMainQueue).start(next: { result in
            guard generation == id else { return }
            guard summaryConfigurationIdentity(RegramPreferences.shared.settings(accountId: accountId)) == identity else {
                update { $0.busy = false; $0.error = regramString("summary.outdated") }
                return
            }
            update { $0.busy = false; $0.result = result }
        }, error: { error in
            guard generation == id else { return }
            update { $0.busy = false; $0.error = error.message }
        }))
    }
    let signal = combineLatest(promise.get(), appearanceSignal) |> map { value, _ -> InputDataSignalValue in
        var rows: [InputDataEntry] = [
            .sectionId(0, type: .normal),
            .desc(sectionId: 1, index: 0, text: .plain(regramString("summary.preview") + " · \(selection.messages.count) · \(selection.byteCount) " + regramString("summary.bytes")), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)),
            .desc(sectionId: 1, index: 1, text: .plain(selection.text), data: .init(color: theme.colors.text, viewType: .textBottomItem)),
            .desc(sectionId: 1, index: 2, text: .plain(regramString("summary.uploadNotice")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)),
            .sectionId(1, type: .normal),
            .general(sectionId: 2, index: 3, value: .none, error: nil, identifier: InputDataIdentifier("summary_start"), data: .init(name: regramString(value.busy ? "cancel" : value.error.isEmpty ? "summary.start" : "summary.retry"), color: theme.colors.accent, type: value.busy ? .loading : .none, viewType: .firstItem, action: start)),
            .general(sectionId: 2, index: 4, value: .none, error: nil, identifier: InputDataIdentifier("summary_configure"), data: .init(name: regramString("service.summary"), color: theme.colors.text, type: .next, viewType: .lastItem, enabled: !value.busy, action: { context.bindings.rootNavigation().push(RegramServiceController(context: context, purpose: .summary)) }))
        ]
        if !value.error.isEmpty { rows.append(.desc(sectionId: 2, index: 5, text: .plain(value.error), data: .init(color: theme.colors.redUI, viewType: .textBottomItem))) }
        if !value.result.isEmpty {
            rows.append(.sectionId(2, type: .normal))
            rows.append(.desc(sectionId: 3, index: 6, text: .plain(value.result), data: .init(color: theme.colors.text, viewType: .textTopItem)))
            rows.append(.general(sectionId: 3, index: 7, value: .none, error: nil, identifier: InputDataIdentifier("summary_copy"), data: .init(name: regramString("menu.copy"), color: theme.colors.accent, type: .none, viewType: .singleItem, action: { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(value.result, forType: .string) })))
        }
        return InputDataSignalValue(entries: rows)
    }
    let controller = InputDataController(dataSignal: signal, title: regramString("section.summary"), afterDisappear: cancel, removeAfterDisappear: false, hasDone: false, identifier: "regram.summary")
    controller.onDeinit = { request.dispose() }
    return controller
}

private struct SummaryRangeState: Equatable {
    var preset = "hour"
    var from = ""
    var to = ""
    var busy = false
    var count = 0
    var skipped = 0
    var error = ""
}

public func RegramMessageSummaryRangeController(context: any AccountContextProtocol, peerId: PeerId, threadId: Int64?, selectedMessages: [Message] = []) -> InputDataController? {
    let accountId = context.peerId.toInt64()
    guard peerId.namespace != Namespaces.Peer.SecretChat, RegramPreferences.shared.settings(accountId: accountId)["messageSummaryEnabled"].bool else { return nil }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm"
    formatter.isLenient = false
    let initial = SummaryRangeState(from: formatter.string(from: Date().addingTimeInterval(-3600)), to: formatter.string(from: Date()))
    let state = Atomic(value: initial)
    let promise = ValuePromise(initial, ignoreRepeated: true)
    let request = MetaDisposable()
    var generation = UUID()
    var loadedMessages: [Message] = []
    func update(_ transform: (inout SummaryRangeState) -> Void) { promise.set(state.modify { value in var value = value; transform(&value); return value }) }
    func cancel() { generation = UUID(); request.set(nil); update { $0.busy = false } }
    func load() {
        guard !state.with({ $0.busy }) else { cancel(); return }
        let value = state.with { $0 }
        let now = Date()
        let from: Date?
        let to: Date?
        switch value.preset {
        case "today": from = Calendar.current.startOfDay(for: now); to = now
        case "day": from = now.addingTimeInterval(-86400); to = now
        case "custom": from = formatter.date(from: value.from); to = formatter.date(from: value.to)
        default: from = now.addingTimeInterval(-3600); to = now
        }
        guard let from, let to, from < to, from.timeIntervalSince1970 > 0, to <= now, to.timeIntervalSince1970 <= Double(Int32.max) else { update { $0.error = regramString("summary.invalidRange") }; return }
        loadedMessages = []
        update { $0.busy = true; $0.count = 0; $0.skipped = 0; $0.error = "" }
        let token = UUID()
        generation = token
        let lower = Int32(from.timeIntervalSince1970), upper = Int32(to.timeIntervalSince1970)
        let location = SearchMessagesLocation.peer(peerId: peerId, fromId: nil, tags: nil, reactions: nil, threadId: threadId, minDate: lower, maxDate: upper)
        var seen = Set<MessageId>()
        var accumulated: [Message] = []
        var skipped = 0
        var bytes = 0
        var pages = 0
        func page(_ cursor: SearchMessagesState?) {
            guard generation == token else { return }
            request.set((context.engine.messages.searchMessages(location: location, query: "", state: cursor, limit: 100) |> take(1) |> map(Optional.init) |> timeout(25, queue: .mainQueue(), alternate: .single(nil)) |> deliverOnMainQueue).start(next: { response in
                guard generation == token else { return }
                guard RegramPreferences.shared.settings(accountId: accountId)["messageSummaryEnabled"].bool else { cancel(); update { $0.error = regramString("summary.disabled") }; return }
                guard let (result, next) = response else { update { $0.busy = false; $0.error = regramString("summary.rangeFailed") }; return }
                pages += 1
                for message in result.messages where message.id.peerId == peerId && message.threadId == threadId && message.timestamp >= lower && message.timestamp <= upper && seen.insert(message.id).inserted {
                    let candidate = summaryMessage(message)
                    guard !candidate.isSecret, !candidate.isCopyProtected, !candidate.isOneTime, !candidate.hasAttachment, !candidate.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { skipped += 1; continue }
                    bytes += candidate.text.utf8.count + (accumulated.isEmpty ? 0 : 7)
                    accumulated.append(message)
                }
                guard bytes <= RegramSummaryPolicy.maximumBytes, accumulated.count <= RegramSummaryPolicy.rangeLimit, pages <= 100 else {
                    update { $0.busy = false; $0.error = regramString("summary.tooLarge") }
                    return
                }
                if result.completed {
                    loadedMessages = accumulated.sorted { $0.index < $1.index }
                    update { $0.busy = false; $0.count = loadedMessages.count; $0.skipped = skipped; if loadedMessages.isEmpty { $0.error = regramString("summary.empty") } }
                } else if cursor == next {
                    update { $0.busy = false; $0.error = regramString("summary.rangeFailed") }
                } else {
                    DispatchQueue.main.async { page(next) }
                }
            }))
        }
        page(nil)
    }
    func open(_ messages: [Message], range: Bool) {
        if let controller = RegramMessageSummaryController(context: context, messages: messages, permitsTimeRange: range) { context.bindings.rootNavigation().push(controller) }
    }
    let signal = combineLatest(promise.get(), appearanceSignal) |> map { value, _ -> InputDataSignalValue in
        let presets = ["hour", "today", "day", "custom"].map { preset in
            ContextMenuItem(regramString("summary.range." + preset), handler: {
                cancel(); loadedMessages = []
                update { $0.preset = preset; $0.count = 0; $0.skipped = 0; $0.error = "" }
            }, state: value.preset == preset ? .on : .off)
        }
        var rows: [InputDataEntry] = [
            .sectionId(0, type: .normal),
            .desc(sectionId: 1, index: 0, text: .plain(regramString("summary.rangeNotice")), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)),
            .general(sectionId: 1, index: 1, value: .none, error: nil, identifier: InputDataIdentifier("summary_range_preset"), data: .init(name: regramString("summary.range"), color: theme.colors.text, type: .contextSelector(regramString("summary.range." + value.preset), presets), viewType: value.preset == "custom" ? .firstItem : .singleItem, enabled: !value.busy))
        ]
        if value.preset == "custom" {
            rows.append(.input(sectionId: 1, index: 2, value: .string(value.from), error: nil, identifier: InputDataIdentifier("summary_range_from"), mode: .plain, data: .init(viewType: .innerItem), placeholder: nil, inputPlaceholder: regramString("summary.from"), filter: { $0 }, limit: 16))
            rows.append(.input(sectionId: 1, index: 3, value: .string(value.to), error: nil, identifier: InputDataIdentifier("summary_range_to"), mode: .plain, data: .init(viewType: .lastItem), placeholder: nil, inputPlaceholder: regramString("summary.to"), filter: { $0 }, limit: 16))
            rows.append(.desc(sectionId: 1, index: 4, text: .plain(regramString("summary.dateFormat")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        }
        rows.append(.sectionId(1, type: .normal))
        rows.append(.general(sectionId: 2, index: 5, value: .none, error: nil, identifier: InputDataIdentifier("summary_range_load"), data: .init(name: regramString(value.busy ? "cancel" : "summary.loadRange"), color: theme.colors.accent, type: value.busy ? .loading : .none, viewType: .singleItem, action: load)))
        if !value.error.isEmpty { rows.append(.desc(sectionId: 2, index: 6, text: .plain(value.error), data: .init(color: theme.colors.redUI, viewType: .textBottomItem))) }
        if value.count > 0 {
            rows.append(.desc(sectionId: 2, index: 7, text: .plain(regramString("summary.selected") + " \(value.count) · " + regramString("summary.skipped") + " \(value.skipped)"), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
            rows.append(.general(sectionId: 2, index: 8, value: .none, error: nil, identifier: InputDataIdentifier("summary_range_review"), data: .init(name: regramString("summary.reviewRange"), color: theme.colors.text, type: .next, viewType: .singleItem, action: { open(loadedMessages, range: true) })))
        }
        if !selectedMessages.isEmpty {
            rows.append(.sectionId(2, type: .normal))
            rows.append(.general(sectionId: 3, index: 9, value: .none, error: nil, identifier: InputDataIdentifier("summary_range_selected"), data: .init(name: regramString("summary.onlySelected"), color: theme.colors.text, type: .next, viewType: .singleItem, action: { open(selectedMessages, range: false) })))
        }
        return InputDataSignalValue(entries: rows)
    }
    let controller = InputDataController(dataSignal: signal, title: regramString("summary.rangeAction"), updateDatas: { data in
        let current = state.with { $0 }
        let from = data[InputDataIdentifier("summary_range_from")]?.stringValue ?? current.from
        let to = data[InputDataIdentifier("summary_range_to")]?.stringValue ?? current.to
        guard from != current.from || to != current.to else { return .fail(.none) }
        cancel()
        loadedMessages = []
        update { value in
            value.from = from
            value.to = to
            value.count = 0
            value.skipped = 0
            value.error = ""
        }
        return .fail(.none)
    }, afterDisappear: cancel, removeAfterDisappear: false, hasDone: false, identifier: "regram.summary")
    controller.onDeinit = { request.dispose() }
    return controller
}
