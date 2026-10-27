import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import InputDataUI
import GeneralRows
import AlertsUI
import RegramCore
import RegramSignals

private struct RegramBackupState: Equatable {
    var categories = Set(RegramBackupCategory.available)
    var candidate: RegramSettingsBackup?
    var importing = false
}

public func RegramSettingsBackupController(context: any AccountContextProtocol, focusSetting: String? = nil, initialBackup: RegramSettingsBackup? = nil) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let initial = RegramBackupState(candidate: initialBackup)
    let stateValue = Atomic(value: initial)
    let promise = ValuePromise(initial)
    let actions = DisposableSet()
    func update(_ transform: (inout RegramBackupState) -> Void) { promise.set(stateValue.modify { value in var value = value; transform(&value); return value }) }
    func presentError() { showModalText(for: context.window, text: regramString("Backup.Error.Notice"), title: regramString("Backup.Error")) }
    func export(_ categories: Set<RegramBackupCategory>) {
        actions.add((RegramNativeNavigation.visibility(context: context) |> take(1) |> deliverOnMainQueue).start(next: { native in
            var snapshot = RegramPreferences.shared.settings(accountId: accountId)
            snapshot["native.showContactsTab"] = .bool(native.contacts)
            snapshot["native.showCallsTab"] = .bool(native.calls)
            var layout = RegramBottomBarSettings(settings: snapshot)
            layout.setVisible(.contacts, visible: native.contacts)
            layout.apply(to: &snapshot)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = RegramSettingsBackup.filename
            panel.allowedFileTypes = ["json"]
            panel.beginSheetModal(for: context.window) { result in
                guard result == .OK, let url = panel.url else { return }
                do { try RegramSettingsBackup(settings: snapshot, categories: categories).encoded().write(to: url, options: .atomic) }
                catch { presentError() }
            }
        }))
    }
    func importFile() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["json", "data"]
        panel.allowsMultipleSelection = false
        update { $0.importing = true }
        panel.beginSheetModal(for: context.window) { result in
            guard result == .OK, let url = panel.url else { update { $0.importing = false }; return }
            DispatchQueue.global(qos: .userInitiated).async {
                let loaded = Result { try RegramSettingsBackup.read(from: url) }
                DispatchQueue.main.async {
                    update { $0.importing = false }
                    switch loaded {
                    case let .success(backup): update { $0.candidate = backup }
                    case .failure: presentError()
                    }
                }
            }
        }
    }
    func restore(_ backup: RegramSettingsBackup?, categories: Set<RegramBackupCategory>) {
        verifyAlert(for: context.window, header: regramString(backup == nil ? "Backup.Reset" : "Backup.Restore"), information: regramString(backup == nil ? "Backup.Reset.Notice" : "Backup.Restore.Notice"), successHandler: { _ in
            let source = backup ?? RegramSettingsBackup(values: [:])
            RegramPreferences.shared.update(accountId: accountId) { $0 = source.applying(to: $0, categories: categories, resetCategories: backup == nil ? categories : []) }
            let selected = source.selectedValues(categories: categories)
            func completed() { showModalText(for: context.window, text: regramString("Backup.Done"), button: regramString("Common.RestartNow"), callback: { _ in RegramUIHooks.shared.restartApplication() }) }
            if backup == nil && categories.contains(.appearance) || ["bottomBarLayout", "native.showContactsTab", "native.showCallsTab", "hideTabBar", "showTabNames", "tabBarWidthPercent"].contains(where: { selected[$0] != nil }) {
                let settings = RegramPreferences.shared.settings(accountId: accountId)
                let layout = RegramBottomBarSettings(settings: settings)
                actions.add((RegramNativeNavigation.update(context: context, contacts: layout.isVisible(.contacts), calls: settings["native.showCallsTab"].bool) |> deliverOnMainQueue).start(completed: completed))
            } else { completed() }
        })
    }
    let signal = combineLatest(promise.get(), appearanceSignal) |> map { state, _ -> InputDataSignalValue in
        var page = RegramPageBuilder(page: "backup")
        page.section()
        page.row("export", title: regramString("Backup.Export"), enabled: !state.categories.isEmpty, action: {
            let categories = stateValue.with { $0.categories }
            guard !categories.isEmpty else { return }
            export(categories)
        })
        page.row("import", title: regramString("Backup.Import"), enabled: !state.importing, action: importFile)
        if state.importing { page.row("importing", title: regramString("loading"), type: .loading) }
        page.text(regramString("Backup.Notice"))
        page.section("Backup.Categories")
        for category in RegramBackupCategory.available {
            let count = state.candidate.map { backup in " (\(backup.values.keys.filter { RegramSettingsBackup.category(for: $0) == category }.count))" } ?? ""
            page.row("category." + category.rawValue, title: regramString(category.titleKey) + count, type: .switchable(state.categories.contains(category)), action: { update { if $0.categories.contains(category) { $0.categories.remove(category) } else { $0.categories.insert(category) } } })
        }
        if let backup = state.candidate {
            page.section("Backup.Preview")
            let date = DateFormatter.localizedString(from: backup.createdAt, dateStyle: .medium, timeStyle: .none)
            page.text(date)
            page.text("\(backup.selectedValues(categories: state.categories).count) " + regramString("Backup.Items"))
            page.row("restore", title: regramString("Backup.Restore"), enabled: !state.categories.isEmpty, action: {
                let current = stateValue.with { $0 }
                guard let backup = current.candidate, !current.categories.isEmpty else { return }
                restore(backup, categories: current.categories)
            })
            page.row("cancelPreview", title: regramString("Backup.CancelPreview"), action: { update { $0.candidate = nil } })
            page.text(regramString("Backup.Fonts.Notice"))
        }
        page.section()
        page.row("reset", title: regramString("Backup.Reset"), enabled: !state.categories.isEmpty, color: theme.colors.redUI, action: {
            let categories = stateValue.with { $0.categories }
            guard !categories.isEmpty else { return }
            restore(nil, categories: categories)
        })
        page.text(regramString("Backup.Reset.Notice"))
        return InputDataSignalValue(entries: page.entries)
    }
    let controller = InputDataController(dataSignal: signal, title: regramString("Backup.Title"), removeAfterDisappear: false, hasDone: false, identifier: "regram.backup")
    controller.onDeinit = { actions.dispose() }
    regramFocusSettings(controller, page: "backup", item: focusSetting)
    return controller
}
