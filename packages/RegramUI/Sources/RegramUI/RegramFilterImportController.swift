import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import InputDataUI
import GeneralRows
import RegramCore
import RegramSignals

private struct FilterImportState: Equatable {
    let plan: RegramFilterImport.Plan
}

private final class FilterImportArguments {
    let apply: () -> Void

    init(apply: @escaping () -> Void) {
        self.apply = apply
    }
}

private func filterImportEntries(_ state: FilterImportState, arguments: FilterImportArguments) -> [InputDataEntry] {
    let plan = state.plan
    var page = RegramPageBuilder(page: "messageFilter.import")
    page.section()
    page.text(regramString("MessageFilter.ImportPreview.Notice"))
    page.row("added", title: regramString("MessageFilter.ImportPreview.Added"), type: .context(String(plan.addedCount)))
    page.row("duplicates", title: regramString("MessageFilter.ImportPreview.Duplicates"), type: .context(String(plan.duplicateCount)))
    if plan.conflictingIdentifierCount > 0 {
        page.row("conflicts", title: regramString("MessageFilter.ImportPreview.Conflicts"), type: .context(String(plan.conflictingIdentifierCount)))
        page.text(regramString("MessageFilter.ImportPreview.ConflictNotice"))
    }
    page.section()
    page.row("confirm", title: regramString("MessageFilter.Import"), enabled: plan.addedCount > 0, action: arguments.apply)
    if plan.addedCount == 0 { page.text(regramString("MessageFilter.AlreadyExists")) }
    var entries = page.entries
    var section = page.nextSectionId
    var index = page.nextIndex
    for (position, entry) in plan.entries.enumerated() {
        entries.append(.sectionId(section, type: .normal))
        section += 1
        let status: String
        switch entry.disposition {
        case .added: status = "MessageFilter.ImportPreview.NewRule"
        case .duplicate: status = "MessageFilter.AlreadyExists"
        case .conflictingIdentifier: status = "MessageFilter.ImportPreview.NewIdentifier"
        }
        var details = [String(position + 1) + " · " + regramString(status)]
        details.append(regramString(entry.rule.isEnabled ? "MessageFilter.ImportPreview.Enabled" : "MessageFilter.Rule.Disabled"))
        details.append(regramString(entry.rule.isException ? "MessageFilter.Rule.Keep" : "MessageFilter.Rule.Hide"))
        if entry.rule.isRegex { details.append(regramString("MessageFilter.Rule.Regex")) }
        if !entry.rule.isValid { details.append(regramString("MessageFilter.Rule.InvalidRegex")) }
        let scope = entry.rule.peerIds.isEmpty ? regramString("MessageFilter.Rule.AllChats") : regramString("MessageFilter.Rule.SelectedChats") + ": " + Set(entry.rule.peerIds).sorted().map(String.init).joined(separator: ", ")
        details.append(scope)
        entries.append(.desc(sectionId: section, index: index, text: .plain(details.joined(separator: " · ")), data: .init(color: theme.colors.listGrayText, detectBold: false, viewType: .textTopItem)))
        index += 1
        entries.append(.desc(sectionId: section, index: index, text: .plain(entry.rule.pattern), data: .init(color: theme.colors.text, detectBold: false, viewType: .textBottomItem, fontSize: 13)))
        index += 1
    }
    return entries
}

public func RegramFilterImportController(context: any AccountContextProtocol, data: Data) -> InputDataController? {
    guard let imported = try? RegramFilterImport(data: data) else { return nil }
    let accountId = context.peerId.toInt64()
    var getController: (() -> InputDataController?)?
    var applied = false
    let arguments = FilterImportArguments(apply: {
        guard !applied, !context.isFrozen else { return }
        applied = true
        var addedCount = 0
        RegramPreferences.shared.update(accountId: accountId) { settings in
            let result = imported.merging(into: settings.filterRules)
            settings.filterRules = result.rules
            addedCount = result.addedCount
        }
        getController?()?.navigationController?.back()
        let text = addedCount == 0 ? regramString("MessageFilter.AlreadyExists") : regramString("MessageFilter.Imported").replacingOccurrences(of: "%@", with: String(addedCount))
        showModalText(for: context.window, text: text)
    })
    let signal = combineLatest(regramPreferenceChanges(accountId: accountId), appearanceSignal) |> deliverOnPrepareQueue |> map { settings, _ in
        InputDataSignalValue(entries: filterImportEntries(FilterImportState(plan: imported.plan(existing: settings.filterRules)), arguments: arguments))
    }
    let controller = InputDataController(dataSignal: signal, title: regramString("MessageFilter.ImportPreview.Title"), removeAfterDisappear: false, hasDone: false, identifier: "regram.messageFilter.import")
    getController = { [weak controller] in controller }
    return controller
}
