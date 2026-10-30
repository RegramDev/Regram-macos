import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramContext
import TelegramTheme
import Localization
import InputDataUI
import GeneralRows
import AlertsUI
import RegramCore
import RegramSignals

private struct FilterDraft: Equatable {
    var pattern = ""
    var regex = false
    var editing = false
}

public func RegramFilterController(context: any AccountContextProtocol, focusSetting: String? = nil) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let draft = Atomic(value: FilterDraft())
    let promise = ValuePromise(FilterDraft(), ignoreRepeated: true)
    let selection = MetaDisposable()
    let patternId = InputDataIdentifier("messageFilter.input")
    func currentRules() -> [RGMessageFilterRule] { RegramPreferences.shared.settings(accountId: accountId).filterRules }
    func update(_ transform: (inout FilterDraft) -> Void) { promise.set(draft.modify { current in var value = current; transform(&value); return value }) }
    func edit(_ id: String, transform: (inout RGMessageFilterRule) -> Void) {
        RegramPreferences.shared.update(accountId: accountId) { settings in
            var rules = settings.filterRules
            guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
            transform(&rules[index])
            settings.filterRules = rules
        }
    }
    func remove(_ id: String) { RegramPreferences.shared.update(accountId: accountId) { $0.filterRules.removeAll { $0.id == id } } }
    func add() {
        let value = draft.with { $0 }
        let rule = RGMessageFilterRule(pattern: value.pattern.trimmingCharacters(in: .whitespacesAndNewlines), isRegex: value.regex)
        guard rule.isValid else { return }
        RegramPreferences.shared.update(accountId: accountId) { settings in
            guard !settings.filterRules.contains(where: { $0.hasSameDefinition(as: rule) }) else { return }
            settings.filterRules.append(rule)
        }
        update { $0.pattern = "" }
    }
    let signal = combineLatest(promise.get(), regramPreferenceChanges(accountId: accountId), appearanceSignal) |> map { value, settings, _ -> InputDataSignalValue in
        let rule = RGMessageFilterRule(pattern: value.pattern.trimmingCharacters(in: .whitespacesAndNewlines), isRegex: value.regex)
        var rows: [InputDataEntry] = [
            .sectionId(0, type: .normal),
            .input(sectionId: 1, index: 0, value: .string(value.pattern), error: nil, identifier: patternId, mode: .plain, data: .init(viewType: .firstItem), placeholder: nil, inputPlaceholder: regramString(value.regex ? "MessageFilter.InputPlaceholderRegex" : "MessageFilter.InputPlaceholder"), filter: { $0 }, limit: 8192),
            .general(sectionId: 1, index: 1, value: .none, error: nil, identifier: InputDataIdentifier("messageFilter.regex"), data: .init(name: regramString("MessageFilter.Regex"), color: theme.colors.text, type: .switchable(value.regex), viewType: .innerItem, action: { update { $0.regex.toggle() } })),
            .general(sectionId: 1, index: 2, value: .none, error: nil, identifier: InputDataIdentifier("messageFilter.add"), data: .init(name: regramString("MessageFilter.Add"), color: theme.colors.accent, type: .none, viewType: .lastItem, enabled: rule.isValid && !settings.filterRules.contains(where: { $0.hasSameDefinition(as: rule) }), action: add)),
            .desc(sectionId: 1, index: 3, text: .plain(regramString("MessageFilter.SubTitle") + "\n\n" + regramString("MessageFilter.Regex.Notice")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)),
            .sectionId(1, type: .normal)
        ]
        let tools = {
            [
                ContextMenuItem(regramString("MessageFilter.Export"), handler: { if !currentRules().isEmpty { regramExportRules(context: context) } }),
                ContextMenuItem(regramString("MessageFilter.Import"), handler: { regramImportRules(context: context) }),
                ContextMenuItem(regramString("MessageFilter.Test.Title"), handler: { context.bindings.rootNavigation().push(RegramMessageFilterTestController(context: context, rules: currentRules())) })
            ]
        }
        rows.append(.desc(sectionId: 2, index: 4, text: .plain(regramString("MessageFilter.Keywords.Title")), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem, rightItem: .init(isLoading: false, text: .initialize(string: "⋯", color: theme.colors.accent, font: .medium(.title)), contextMenu: tools))))
        let rules = Array(settings.filterRules.reversed())
        for (index, rule) in rules.enumerated() {
            var details: [String] = []
            if !rule.isEnabled { details.append(regramString("MessageFilter.Rule.Disabled")) }
            if rule.isException { details.append(regramString("MessageFilter.Rule.Keep")) }
            if rule.isRegex { details.append(regramString("MessageFilter.Rule.Regex")) }
            details.append(regramString(rule.peerIds.isEmpty ? "MessageFilter.Rule.AllChats" : "MessageFilter.Rule.SelectedChats") + (rule.peerIds.isEmpty ? "" : " (\(rule.peerIds.count))"))
            if rule.isRegex && !rule.isValid { details.append(regramString("MessageFilter.Rule.InvalidRegex")) }
            let menu = {
                [
                    ContextMenuItem(regramString(rule.isEnabled ? "MessageFilter.Rule.Disable" : "MessageFilter.Rule.Enable"), handler: { edit(rule.id) { $0.isEnabled.toggle() } }),
                    ContextMenuItem(regramString(rule.isException ? "MessageFilter.Rule.Hide" : "MessageFilter.Rule.Keep"), handler: { edit(rule.id) { $0.isException.toggle() } }),
                    ContextMenuItem(regramString("MessageFilter.Rule.LimitToChats"), handler: {
                        guard let rule = currentRules().first(where: { $0.id == rule.id }) else { return }
                        selection.set((RegramUIHooks.shared.selectChats(context, rule.peerIds.map(PeerId.init)) |> deliverOnMainQueue).start(next: { ids in edit(rule.id) { $0.peerIds = ids.map { $0.toInt64() } } }))
                    }),
                    ContextMenuItem(regramString(rule.isRegex ? "MessageFilter.Rule.MakePlain" : "MessageFilter.Rule.MakeRegex"), handler: { edit(rule.id) { $0.isRegex.toggle() } }),
                    ContextMenuItem(regramString("MessageFilter.Rule.Delete"), handler: { remove(rule.id) })
                ]
            }
            rows.append(.general(sectionId: 2, index: Int32(index + 5), value: .none, error: nil, identifier: InputDataIdentifier("filter_rule_" + rule.id), data: .init(name: rule.pattern, color: rule.isEnabled ? theme.colors.text : theme.colors.grayText, type: value.editing ? .context(regramString("MessageFilter.Rule.Delete")) : .next, viewType: rules.count == 1 ? .singleItem : index == 0 ? .firstItem : index + 1 == rules.count ? .lastItem : .innerItem, description: details.joined(separator: " · "), action: {
                if draft.with({ $0.editing }) { remove(rule.id) }
                else if let rule = currentRules().first(where: { $0.id == rule.id }) { context.bindings.rootNavigation().push(RegramRuleController(context: context, rule: rule)) }
            }, menuItems: menu)))
        }
        rows.append(.desc(sectionId: 2, index: Int32(rules.count + 5), text: .plain(regramString("MessageFilter.Rules.Notice")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        return InputDataSignalValue(entries: rows)
    }
    let controller = RegramFormController(dataSignal: signal, title: regramString("MessageFilter.Title"), validateData: { _ in
        update { $0.editing.toggle() }
        return .fail(.none)
    }, updateDatas: { data in
        if let text = data[patternId]?.stringValue { update { $0.pattern = text } }
        return .fail(.none)
    }, updateDoneValue: { _ in
        let editing = draft.with { $0.editing }
        return { $0(.enabled(editing ? strings().navigationDone : strings().navigationEdit)) }
    }, removeAfterDisappear: false, hasDone: true, identifier: "regram.messageFilter", returnKeyInvocation: { id, _ in
        if id == patternId { add(); return .nothing }
        return .default
    }, doneString: { strings().navigationEdit })
    controller.onDeinit = { selection.dispose() }
    regramFocusSettings(controller, page: "messageFilter", item: focusSetting)
    return controller
}

public func RegramRuleController(context: any AccountContextProtocol, rule: RGMessageFilterRule) -> InputDataController {
    let identifier = InputDataIdentifier("filter_pattern")
    let rows: [InputDataEntry] = [
        .sectionId(0, type: .normal),
        .input(sectionId: 1, index: 0, value: .string(rule.pattern), error: nil, identifier: identifier, mode: .plain, data: .init(viewType: .singleItem), placeholder: nil, inputPlaceholder: regramString(rule.isRegex ? "MessageFilter.InputPlaceholderRegex" : "MessageFilter.InputPlaceholder"), filter: { $0 }, limit: 8192),
        .desc(sectionId: 1, index: 1, text: .plain(regramString(rule.isRegex ? "MessageFilter.Rule.EditMessageRegex" : "MessageFilter.Rule.EditMessage")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem))
    ]
    return RegramFormController(dataSignal: .single(InputDataSignalValue(entries: rows)), title: regramString("MessageFilter.Rule.EditTitle"), validateData: { data in
        var result = rule
        result.pattern = (data[identifier]?.stringValue ?? rule.pattern).trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.isValid else { return .fail(.fields([identifier: .shake])) }
        RegramPreferences.shared.update(accountId: context.peerId.toInt64()) { settings in
            var rules = settings.filterRules
            guard !rules.contains(where: { $0.id != rule.id && $0.hasSameDefinition(as: result) }), let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
            rules[index].pattern = result.pattern
            settings.filterRules = rules
        }
        return .success(.navigationBack)
    }, identifier: "regram.messageFilter.rule")
}

private struct FilterTestState: Equatable {
    var text = ""
    var results: [RGMessageFilter.MatchResult] = []
    var running = false
    var generation = UUID()
}

public func RegramMessageFilterTestController(context: any AccountContextProtocol, rules: [RGMessageFilterRule]) -> InputDataController {
    let state = Atomic(value: FilterTestState())
    let promise = ValuePromise(FilterTestState(), ignoreRepeated: true)
    func update(_ transform: (inout FilterTestState) -> Void) { promise.set(state.modify { current in var value = current; transform(&value); return value }) }
    func cancel() { update { $0.generation = UUID(); $0.running = false } }
    let signal = combineLatest(promise.get(), appearanceSignal) |> map { value, _ -> InputDataSignalValue in
        var rows: [InputDataEntry] = [
            .sectionId(0, type: .normal),
            .input(sectionId: 1, index: 0, value: .string(value.text), error: nil, identifier: InputDataIdentifier("filter_testText"), mode: .plain, data: .init(viewType: .firstItem), placeholder: nil, inputPlaceholder: "", filter: { $0 }, limit: 64000),
            .general(sectionId: 1, index: 1, value: .none, error: nil, identifier: InputDataIdentifier("filter_runTest"), data: .init(name: regramString(value.running ? "Common.Cancel" : "MessageFilter.Test.Run"), color: theme.colors.accent, type: value.running ? .loading : .none, viewType: .lastItem, enabled: value.running || !value.text.isEmpty, action: {
                let current = state.with { $0 }
                if current.running { cancel(); return }
                guard !context.isFrozen, !current.text.isEmpty else { return }
                let text = current.text
                let generation = UUID()
                update { $0.running = true; $0.generation = generation }
                DispatchQueue.global(qos: .userInitiated).async {
                    var results: [RGMessageFilter.MatchResult] = []
                    for rule in rules {
                        guard state.with({ $0.generation == generation }) else { return }
                        results.append(RGMessageFilter.matchResult(rule: rule, text: text))
                    }
                    DispatchQueue.main.async {
                        guard state.with({ $0.generation == generation }) else { return }
                        update { if $0.text == text { $0.results = results }; $0.running = false }
                    }
                }
            })),
            .desc(sectionId: 1, index: 2, text: .plain(regramString("MessageFilter.Test.Notice")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem))
        ]
        let results = rules.enumerated().filter { value.results.indices.contains($0.offset) }
        if !results.isEmpty { rows.append(.sectionId(1, type: .normal)) }
        for (position, entry) in results.enumerated() {
            let (index, rule) = entry
            let result = value.results[index]
            let key: String
            switch result {
            case .matched: key = "MessageFilter.Test.Matched"
            case .notMatched: key = "MessageFilter.Test.NotMatched"
            case .disabled: key = "MessageFilter.Rule.Disabled"
            case .invalidRegex: key = "MessageFilter.Rule.InvalidRegex"
            case .timedOut: key = "MessageFilter.Test.TimedOut"
            }
            let viewType: GeneralViewType = results.count == 1 ? .singleItem : position == 0 ? .firstItem : position + 1 == results.count ? .lastItem : .innerItem
            rows.append(.general(sectionId: 2, index: Int32(index + 3), value: .none, error: nil, identifier: InputDataIdentifier("filter_result_" + rule.id), data: .init(name: rule.pattern, color: theme.colors.text, type: .context(regramString(key)), viewType: viewType, description: regramString(rule.isException ? "MessageFilter.Rule.Keep" : "MessageFilter.Rule.Hide"))))
        }
        return InputDataSignalValue(entries: rows)
    }
    let controller = RegramFormController(dataSignal: signal, title: regramString("MessageFilter.Test.Title"), updateDatas: { data in
        if let text = data[InputDataIdentifier("filter_testText")]?.stringValue { update { if $0.text != text { $0.text = text; $0.results = []; $0.generation = UUID(); $0.running = false } } }
        return .fail(.none)
    }, hasDone: false, identifier: "regram.messageFilter")
    controller.willDisappear = { _ in cancel() }
    controller.onDeinit = cancel
    return controller
}

private func regramImportRules(context: any AccountContextProtocol) {
    let panel = NSOpenPanel()
    panel.allowedFileTypes = ["json", "txt"]
    panel.allowsMultipleSelection = false
    panel.beginSheetModal(for: context.window) { response in
        guard response == .OK, let url = panel.url else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let imported = try? RegramFilterImport.read(from: url)
            DispatchQueue.main.async {
                guard !context.isFrozen else { return }
                if let imported, let controller = RegramFilterImportController(context: context, data: imported.data) {
                    context.bindings.rootNavigation().push(controller)
                } else { alert(for: context.window, info: regramString("MessageFilter.ImportFailed")) }
            }
        }
    }
}

private func regramExportRules(context: any AccountContextProtocol) {
    guard !RegramPreferences.shared.settings(accountId: context.peerId.toInt64()).filterRules.isEmpty else { return }
    let panel = NSSavePanel()
    panel.nameFieldStringValue = RGMessageFilter.exportFileName
    panel.beginSheetModal(for: context.window) { response in
        guard response == .OK, let url = panel.url else { return }
        do { try JSONEncoder().encode(RegramPreferences.shared.settings(accountId: context.peerId.toInt64()).filterRules).write(to: url, options: .atomic) }
        catch { alert(for: context.window, info: regramString("fileError")) }
    }
}
