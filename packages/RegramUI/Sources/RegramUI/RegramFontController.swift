import Cocoa
import TGUIKit
import GeneralRows
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import InputDataUI
import AlertsUI
import RegramCore
import RegramSignals
import RegramServices

private struct RegramFontState: Equatable {
    var settings: RegramAccountSettings
    var imported: [RegramImportedFont]
    var script = 0
    var filter = ""
    var importing = false
    var downloading: String?
    var progress: Double = 0
    var revision: Int64 = 0
}

public func RegramFontController(context: any AccountContextProtocol, focusSetting: String? = nil) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let store = RegramFontStore.shared
    var initial = RegramFontState(settings: RegramPreferences.shared.settings(accountId: accountId), imported: store.imported)
    if focusSetting == "chinese" { initial.script = 1 }
    let value = Atomic(value: initial)
    let promise = ValuePromise(initial, ignoreRepeated: true)
    let actions = DisposableSet()
    let download = MetaDisposable()
    actions.add(download)
    func update(_ transform: (inout RegramFontState) -> Void) { promise.set(value.modify { state in var state = state; transform(&state); return state }) }
    func set(_ key: String, _ setting: RegramValue) { RegramPreferences.shared.update(accountId: accountId) { $0[key] = setting } }
    func runDownload(_ prefix: String?, apply: @escaping () -> Void) {
        guard let prefix, !store.isDownloaded(prefix: prefix) else { apply(); return }
        guard value.with({ $0.downloading == nil && !$0.importing }) else { return }
        update { $0.downloading = prefix; $0.progress = 0 }
        download.set((store.download(prefix: prefix) |> deliverOnMainQueue).start(next: { progress in update { $0.progress = progress } }, error: { _ in
            update { $0.downloading = nil }
            showModalText(for: context.window, text: regramString("Fonts.Download.Error"))
        }, completed: { apply(); update { $0.downloading = nil; $0.revision &+= 1 } }))
    }
    func selectImported(_ font: RegramImportedFont, chinese: Bool) {
        set(chinese ? "fontImportedChinese" : "fontImportedLatin", .string(font.id))
        store.retainSelections(settings: RegramPreferences.shared.settings(accountId: accountId), accountId: accountId)
    }
    func importFonts() {
        guard value.with({ !$0.importing && $0.downloading == nil }) else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        update { $0.importing = true }
        panel.beginSheetModal(for: context.window) { response in
            guard response == .OK, let url = panel.url else { update { $0.importing = false }; return }
            Queue.concurrentDefaultQueue().async {
                let result = Result { try store.importFonts(url: url, accountId: accountId) }
                Queue.mainQueue().async {
                    update { $0.importing = false; $0.imported = store.imported; $0.revision &+= 1 }
                    switch result {
                    case let .success(fonts):
                        let chinese = value.with { $0.script == 1 }
                        guard let font = fonts.first(where: { chinese ? $0.chinese : $0.latin }) ?? fonts.first else { return }
                        let useChinese = chinese && font.chinese || !font.latin && font.chinese
                        selectImported(font, chinese: useChinese)
                        update { $0.script = useChinese ? 1 : 0 }
                    case .failure: showModalText(for: context.window, text: regramString("Fonts.Import.Error"))
                    }
                }
            }
        }
    }
    let observer = NotificationCenter.default.addObserver(forName: RegramFontStore.didChange, object: store, queue: .main) { _ in update { $0.imported = store.imported; $0.revision &+= 1 } }
    actions.add(ActionDisposable { NotificationCenter.default.removeObserver(observer) })
    actions.add((regramPreferenceChanges(accountId: accountId) |> deliverOnMainQueue).start(next: { _ in update { $0.settings = RegramPreferences.shared.settings(accountId: accountId) } }))
    let signal = combineLatest(promise.get(), appearanceSignal) |> map { state, _ -> InputDataSignalValue in
        var page = RegramPageBuilder(page: "fonts")
        let busy = state.importing || state.downloading != nil
        let chinese = state.script == 1
        let selectedImported = state.settings[chinese ? "fontImportedChinese" : "fontImportedLatin"].string
        func font(_ settings: RegramAccountSettings, weight: NSFont.Weight = .regular, italic: Bool = false, size: CGFloat = 19) -> NSFont {
            var base = InterfaceFontProvider.withNativeFonts { NSFont.systemFont(ofSize: size, weight: weight) }
            if italic { base = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask) }
            return RegramFonts.font(base: base, settings: settings, area: .preview) ?? base
        }
        page.section("Fonts.Preview")
        let preview = NSMutableAttributedString(string: "Hello, Regram!   Aa · 字\n", attributes: [.font: font(state.settings, weight: .medium), .foregroundColor: theme.colors.text])
        preview.append(NSAttributedString(string: regramString("Fonts.Sample") + "\n", attributes: [.font: font(state.settings), .foregroundColor: theme.colors.grayText]))
        preview.append(NSAttributedString(string: "Bold 粗体   ", attributes: [.font: font(state.settings, weight: .bold), .foregroundColor: theme.colors.text]))
        preview.append(NSAttributedString(string: "Italic 斜体\n", attributes: [.font: font(state.settings, italic: true), .foregroundColor: theme.colors.text]))
        preview.append(NSAttributedString(string: "0123456789   →  ≠  <=", attributes: [.font: font(state.settings), .foregroundColor: theme.colors.grayText]))
        page.text("", attributed: preview)
        page.section("Fonts.Areas")
        for key in ["fontApplyToMessages", "fontApplyToInterface"] {
            page.row(key == "fontApplyToMessages" ? "messages" : "interface", title: regramString(key == "fontApplyToMessages" ? "Fonts.Messages" : "Fonts.Interface"), type: .switchable(state.settings[key].bool), action: { set(key, .bool(!state.settings[key].bool)) })
        }
        page.text(regramString(state.settings["fontApplyToMessages"].bool || state.settings["fontApplyToInterface"].bool ? "Fonts.Areas.Notice" : "Fonts.NoArea"))
        if let downloading = state.downloading {
            page.section("Fonts.Storage.Downloads")
            page.custom("downloadProgress", equatable: InputDataEquatable(state.progress)) { size, id in RegramProgressRowItem(size, stableId: id, title: downloading, progress: state.progress) }
            page.row("cancel", title: regramString("Fonts.Cancel"), type: .loading, action: { download.set(nil); update { $0.downloading = nil } })
        }
        page.section()
        page.custom("script", equatable: InputDataEquatable(state.script)) { size, id in RegramSegmentedRowItem(size, stableId: id, labels: [regramString("Fonts.Latin.Title"), regramString("Fonts.Chinese.Title")], selected: state.script, changed: { selected in update { $0.script = selected } }) }
        page.input("search", value: state.filter, title: regramString("Fonts.Search"), limit: 256)
        func matches(_ title: String) -> Bool { state.filter.isEmpty || title.localizedCaseInsensitiveContains(state.filter) }
        func groupViewType(_ position: Int, count: Int) -> GeneralViewType {
            position == 0 ? (count == 1 ? .singleItem : .firstItem) : (position + 1 == count ? .lastItem : .innerItem)
        }
        func option(_ key: String, title: String, selected: Bool, available: Bool, settings: RegramAccountSettings, viewType: GeneralViewType, menu: (() -> [ContextMenuItem])? = nil, action: @escaping () -> Void) {
            page.custom(key, equatable: InputDataEquatable(state)) { size, id in
                let sample = available ? (chinese ? regramString("Fonts.Chinese.Sample") : "The quick brown fox 0123") : regramString("Fonts.Preview.Download")
                let item = GeneralInteractedRowItem(size, stableId: id, name: title, description: sample, type: .selectable(selected), viewType: viewType, action: action, enabled: !busy, menuItems: menu)
                item.descLayout = TextViewLayout(NSAttributedString(string: sample, attributes: [.font: available ? font(settings, size: 17) : NSFont.normal(.text), .foregroundColor: theme.colors.grayText]), maximumNumberOfLines: 1)
                _ = item.makeSize(size.width, oldWidth: 0)
                return item
            }
        }
        page.section(chinese ? "Fonts.Chinese.Title" : "Fonts.Latin.Title")
        let families = (chinese ? RegramFonts.chineseFamilies : RegramFonts.latinFamilies).filter { matches(regramString($0.title)) }
        for (position, family) in families.enumerated() {
            var settings = state.settings
            settings[chinese ? "fontChineseFamily" : "fontFamily"] = .string(family.id)
            settings[chinese ? "fontImportedChinese" : "fontImportedLatin"] = .string("")
            option("family." + family.id, title: regramString(family.title), selected: selectedImported.isEmpty && state.settings[chinese ? "fontChineseFamily" : "fontFamily"].string == family.id, available: family.prefix.map { store.isDownloaded(prefix: $0) } ?? true, settings: settings, viewType: groupViewType(position, count: families.count), action: {
                runDownload(family.prefix) { RegramPreferences.shared.update(accountId: accountId) { $0[chinese ? "fontChineseFamily" : "fontFamily"] = .string(family.id); $0[chinese ? "fontImportedChinese" : "fontImportedLatin"] = .string("") } }
            })
        }
        if !chinese {
            for group in ["Anthropic", "Google"] {
                let options = RegramFontStore.downloadableFonts.filter { $0.group == group && matches($0.title) }
                if !options.isEmpty { page.section(); page.text(group, header: true) }
                for (position, family) in options.enumerated() {
                    var settings = state.settings
                    settings["fontImportedLatin"] = .string(family.selectionId)
                    option("additional." + family.id, title: family.title, selected: selectedImported == family.selectionId, available: store.isDownloaded(prefix: family.id), settings: settings, viewType: groupViewType(position, count: options.count), action: { runDownload(family.id) { set("fontImportedLatin", .string(family.selectionId)) } })
                }
            }
        }
        if !state.imported.isEmpty {
            page.section("Fonts.Imported")
            let importedFonts = state.imported.filter { (chinese ? $0.chinese : $0.latin) && matches($0.title) }
            for (position, imported) in importedFonts.enumerated() {
                var settings = state.settings
                settings[chinese ? "fontImportedChinese" : "fontImportedLatin"] = .string(imported.id)
                option("imported." + imported.id, title: imported.title, selected: selectedImported == imported.id, available: true, settings: settings, viewType: groupViewType(position, count: importedFonts.count), menu: {
                    [ContextMenuItem(regramString("Fonts.Rename"), handler: { context.bindings.rootNavigation().push(RegramFontRenameController(context: context, font: imported)) }), ContextMenuItem(regramString("Fonts.Delete"), handler: {
                        verifyAlert_button(for: context.window, information: regramString("Fonts.Delete.Notice"), successHandler: { _ in
                            do {
                                try store.remove(id: imported.id)
                                RegramPreferences.shared.update(accountId: accountId) { settings in
                                    if settings["fontImportedLatin"].string == imported.id { settings["fontImportedLatin"] = .string(""); settings["fontFamily"] = .string("system") }
                                    if settings["fontImportedChinese"].string == imported.id { settings["fontImportedChinese"] = .string(""); settings["fontChineseFamily"] = .string("system") }
                                }
                            } catch { showModalText(for: context.window, text: regramString("Fonts.Management.Error")) }
                        })
                    })]
                }, action: { selectImported(imported, chinese: chinese) })
            }
        }
        page.section()
        page.row("import", title: regramString("Fonts.Import"), type: state.importing ? .loading : .next, enabled: !busy, action: importFonts)
        page.text(regramString("Fonts.Import.Notice"))
        page.text(regramString("Fonts.Scripts.Notice"))
        page.section("Fonts.Storage")
        page.row("storage", title: regramString("Fonts.Storage.Downloads"), type: .context(ByteCountFormatter.string(fromByteCount: store.storageBytes(downloads: true), countStyle: .file)))
        page.row("importedStorage", title: regramString("Fonts.Imported"), type: .context(ByteCountFormatter.string(fromByteCount: store.storageBytes(downloads: false), countStyle: .file)))
        page.row("clearDownloads", title: regramString("Fonts.ClearDownloads"), enabled: !busy, action: {
            verifyAlert_button(for: context.window, information: regramString("Fonts.ClearDownloads.Notice"), successHandler: { _ in
                do {
                    try store.clearDownloads()
                    RegramPreferences.shared.update(accountId: accountId) { settings in
                        settings["fontFamily"] = .string("system"); settings["fontChineseFamily"] = .string("system")
                        if RegramFontStore.downloadableFonts.contains(where: { $0.selectionId == settings["fontImportedLatin"].string }) { settings["fontImportedLatin"] = .string("") }
                    }
                } catch { showModalText(for: context.window, text: regramString("Fonts.Management.Error")) }
            })
        })
        page.text(regramString("Fonts.Cloud.Notice"))
        page.section()
        page.row("reset", title: regramString("Fonts.Reset"), action: {
            download.set(nil)
            update { $0.downloading = nil }
            RegramPreferences.shared.update(accountId: accountId) { settings in
                settings["fontFamily"] = .string("system"); settings["fontChineseFamily"] = .string("system"); settings["fontImportedLatin"] = .string(""); settings["fontImportedChinese"] = .string(""); settings["fontApplyToMessages"] = .bool(true); settings["fontApplyToInterface"] = .bool(true)
            }
        })
        return InputDataSignalValue(entries: page.entries)
    }
    let controller = InputDataController(dataSignal: signal, title: regramString("Fonts.Title"), updateDatas: { data in
        if let filter = data[InputDataIdentifier("fonts.search")]?.stringValue { update { $0.filter = filter } }
        return .fail(.none)
    }, removeAfterDisappear: false, hasDone: false, identifier: "regram.fonts")
    controller.onDeinit = { actions.dispose() }
    regramFocusSettings(controller, page: "fonts", item: ["latin", "chinese"].contains(focusSetting ?? "") ? "script" : focusSetting)
    return controller
}

private func RegramFontRenameController(context: any AccountContextProtocol, font: RegramImportedFont) -> InputDataController {
    var page = RegramPageBuilder(page: "fontRename")
    page.section()
    page.input("title", value: font.title, title: regramString("Fonts.Rename"), limit: 80)
    page.text(regramString("Fonts.Rename.Notice"))
    return InputDataController(dataSignal: .single(InputDataSignalValue(entries: page.entries)), title: regramString("Fonts.Rename"), validateData: { data in
        guard let title = data[InputDataIdentifier("fontRename.title")]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else { return .fail(.fields([InputDataIdentifier("fontRename.title"): .shake])) }
        do { try RegramFontStore.shared.rename(id: font.id, title: title) }
        catch { return .fail(.fields([InputDataIdentifier("fontRename.title"): .shake])) }
        return .success(.navigationBack)
    }, hasDone: true)
}
