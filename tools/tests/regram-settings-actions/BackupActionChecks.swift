final class FixtureSavePanel {
    static var presentations = 0
    var nameFieldStringValue = ""
    var allowedFileTypes: [String]?
    let url: URL? = URL(string: "memory://backup/export/" + UUID().uuidString)
    func beginSheetModal(for window: NSObject, completionHandler: (FixturePanelResponse) -> Void) {
        Self.presentations += 1
        completionHandler(.OK)
    }
}
final class FixtureOpenPanel {
    static var presentations = 0
    static var selectedURL: URL?
    var allowedFileTypes: [String]?
    var allowsMultipleSelection = false
    var url: URL? { Self.selectedURL }
    func beginSheetModal(for window: NSObject, completionHandler: (FixturePanelResponse) -> Void) {
        Self.presentations += 1
        completionHandler(.OK)
    }
}
enum FixturePanelResponse { case OK, cancel }
enum FixtureFiles {
    static let lock = NSLock()
    static var data: [URL: Data] = [:]
    static var exports: [Data] = []
    static func store(_ data: Data) -> URL {
        let url = URL(string: "memory://backup/import/" + UUID().uuidString)!
        lock.lock(); defer { lock.unlock() }
        self.data[url] = data
        return url
    }
    static func read(_ url: URL) throws -> RegramSettingsBackup {
        precondition(url.scheme == "memory")
        lock.lock()
        let bytes = data[url]
        lock.unlock()
        guard let bytes else { throw CocoaError(.fileNoSuchFile) }
        return try RegramSettingsBackup.decode(bytes)
    }
}
extension Data {
    func fixtureWrite(to url: URL, options: Data.WritingOptions) throws {
        precondition(url.scheme == "memory")
        FixtureFiles.exports.append(self)
    }
}
struct FixtureTheme { struct Colors { let redUI = NSColor.red }; let colors = Colors() }
let theme = FixtureTheme()
var alerts: [String] = []
var notices: [String] = []
func verifyAlert(for window: NSObject, header: String, information: String, successHandler: (Bool) -> Void) {
    alerts.append(header)
    successHandler(true)
}
func showModalText(for window: NSObject, text: String, title: String) { notices.append(text) }
func showModalText(for window: NSObject, text: String, button: String, callback: @escaping (Bool) -> Void) { notices.append(text) }
final class RegramUIHooks {
    static let shared = RegramUIHooks()
    var restarts = 0
    func restartApplication() { restarts += 1 }
}
enum RegramNativeNavigation {
    struct Visibility { let contacts: Bool; let calls: Bool }
    static var updates: [Visibility] = []
    static func visibility(context: any AccountContextProtocol) -> Signal<Visibility, NoError> { .single(Visibility(contacts: false, calls: true)) }
    static func update(context: any AccountContextProtocol, contacts: Bool, calls: Bool) -> Signal<Never, NoError> {
        updates.append(Visibility(contacts: contacts, calls: calls))
        return Signal { subscriber in subscriber.putCompletion(); return EmptyDisposable }
    }
}
func waitUntil(_ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(3)
    while !condition() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    precondition(condition(), "Timed out waiting for the real backup controller's asynchronous action")
}
func selectedCategories(_ controller: InputDataController) -> Set<RegramBackupCategory> {
    Set(RegramBackupCategory.available.filter { category in
        if case let .switchable(selected) = controller.entry("backup.category." + category.rawValue).type { return selected }
        return false
    })
}
func selectCategories(_ selected: Set<RegramBackupCategory>, in controller: InputDataController) {
    for category in RegramBackupCategory.available where selected.contains(category) && !selectedCategories(controller).contains(category) {
        controller.entry("backup.category." + category.rawValue).action!()
    }
    for category in RegramBackupCategory.available where !selected.contains(category) && selectedCategories(controller).contains(category) {
        controller.entry("backup.category." + category.rawValue).action!()
    }
    precondition(selectedCategories(controller) == selected)
}
func seed() {
    testPreferences.reset(accountId: 42)
    testPreferences.update(accountId: 42) {
        $0["fontFamily"] = .string("inter")
        $0["showMessageId"] = .bool(true)
        $0["antiRevoke"] = .bool(true)
        $0["translationBackend"] = .string("google")
        $0["disableBackupAddresses"] = .bool(true)
        $0["native.enableVoipTcp"] = .bool(true)
    }
}

@main
struct BackupActionChecks {
    static let first = RegramSettingsBackup(values: ["fontFamily": .string("lora"), "showMessageId": .bool(false), "antiRevoke": .bool(false), "translationBackend": .string("yandex"), "disableBackupAddresses": .bool(false)])
    static let latest = RegramSettingsBackup(values: ["fontFamily": .string("poppins"), "showMessageId": .bool(true), "contextShowJson": .bool(true), "antiRevoke": .bool(true), "translationBackend": .string("microsoft"), "disableBackupAddresses": .bool(false)])
    static func main() throws {
        defer { testDefaults.removePersistentDomain(forName: suite) }
        try checkExportUsesCurrentCategories()
        checkResetUsesCurrentCategories()
        try checkRestoreUsesCurrentCategoriesAndCandidate()
        checkEmptySelectionAndCancelledPreviewAreNoops()
        precondition(RegramUIHooks.shared.restarts == 0)
        print("Backup action checks passed: reused export/reset/restore actions, current category selection, unrelated settings preserved, latest imported candidate, isolated real backup encoding/applying/reload, empty/canceled noops; no real file dialogs, files or accounts were used")
    }
    static func checkExportUsesCurrentCategories() throws {
        seed()
        let controller = RegramSettingsBackupController(context: EditorContext())
        let originalEntry = controller.entry("backup.export")
        let oldExport = originalEntry.action!
        for categories in [Set(RegramBackupCategory.available), Set([RegramBackupCategory.messages]), Set([RegramBackupCategory.privacy])] {
            selectCategories(categories, in: controller)
            precondition(controller.entry("backup.export") === originalEntry)
            let count = FixtureFiles.exports.count
            oldExport()
            waitUntil { FixtureFiles.exports.count == count + 1 }
            let backup = try RegramSettingsBackup.decode(FixtureFiles.exports.last!)
            precondition(!backup.values.isEmpty)
            precondition(Set(backup.values.keys.compactMap(RegramSettingsBackup.category(for:))) == categories)
        }
    }
    static func checkResetUsesCurrentCategories() {
        seed()
        let controller = RegramSettingsBackupController(context: EditorContext())
        let originalEntry = controller.entry("backup.reset")
        let oldReset = originalEntry.action!
        for category in [RegramBackupCategory.messages, .privacy, .media] {
            selectCategories([category], in: controller)
            precondition(controller.entry("backup.reset") === originalEntry)
            let before = testPreferences.settings(accountId: 42)
            oldReset()
            let actual = testPreferences.settings(accountId: 42)
            let expected = RegramSettingsBackup(values: [:]).applying(to: before, categories: [category], resetCategories: [category])
            precondition(actual == expected)
            precondition(actual["fontFamily"].string == "inter" && actual["translationBackend"].string == "google")
            if category == .messages { precondition(!actual["showMessageId"].bool && actual["antiRevoke"].bool && actual["disableBackupAddresses"].bool) }
            if category == .privacy { precondition(!actual["antiRevoke"].bool && actual["disableBackupAddresses"].bool) }
            if category == .media { precondition(!actual["disableBackupAddresses"].bool && !actual["native.enableVoipTcp"].bool && !actual["enableVoipTcp"].bool) }
            precondition(RegramPreferences(defaults: testDefaults).settings(accountId: 42) == actual)
        }
    }
    static func checkRestoreUsesCurrentCategoriesAndCandidate() throws {
        seed()
        let controller = RegramSettingsBackupController(context: EditorContext(), initialBackup: first)
        let originalEntry = controller.entry("backup.restore")
        let oldRestore = originalEntry.action!
        selectCategories([.messages], in: controller)
        precondition(controller.entry("backup.restore") === originalEntry)
        let before = testPreferences.settings(accountId: 42)
        oldRestore()
        precondition(testPreferences.settings(accountId: 42) == first.applying(to: before, categories: [.messages]))
        precondition(testPreferences.settings(accountId: 42)["fontFamily"].string == "inter")
        selectCategories([.privacy], in: controller)
        precondition(controller.entry("backup.restore") === originalEntry)
        let beforePrivacy = testPreferences.settings(accountId: 42)
        oldRestore()
        precondition(testPreferences.settings(accountId: 42) == first.applying(to: beforePrivacy, categories: [.privacy]))
        FixtureOpenPanel.selectedURL = FixtureFiles.store(try latest.encoded())
        controller.entry("backup.import").action!()
        waitUntil { controller.entry("backup.category.messages").title.hasSuffix("(2)") }
        let beforeLatest = testPreferences.settings(accountId: 42)
        oldRestore()
        precondition(testPreferences.settings(accountId: 42) == latest.applying(to: beforeLatest, categories: [.privacy]))
        precondition(testPreferences.settings(accountId: 42)["antiRevoke"].bool)
        selectCategories([.translation], in: controller)
        let beforeTranslation = testPreferences.settings(accountId: 42)
        oldRestore()
        precondition(testPreferences.settings(accountId: 42) == latest.applying(to: beforeTranslation, categories: [.translation]))
        precondition(testPreferences.settings(accountId: 42)["translationBackend"].string == "microsoft")
        precondition(RegramPreferences(defaults: testDefaults).settings(accountId: 42) == testPreferences.settings(accountId: 42))
    }
    static func checkEmptySelectionAndCancelledPreviewAreNoops() {
        seed()
        let controller = RegramSettingsBackupController(context: EditorContext(), initialBackup: first)
        let export = controller.entry("backup.export").action!
        let reset = controller.entry("backup.reset").action!
        let restore = controller.entry("backup.restore").action!
        selectCategories([], in: controller)
        let before = testPreferences.settings(accountId: 42)
        let revision = testPreferences.revision(accountId: 42)
        let panelCount = FixtureSavePanel.presentations
        let alertCount = alerts.count
        export(); reset(); restore()
        precondition(testPreferences.settings(accountId: 42) == before && testPreferences.revision(accountId: 42) == revision)
        precondition(FixtureSavePanel.presentations == panelCount && alerts.count == alertCount)
        selectCategories([.messages], in: controller)
        controller.entry("backup.cancelPreview").action!()
        restore()
        precondition(testPreferences.settings(accountId: 42) == before && alerts.count == alertCount)
        precondition(testPreferences.settings(accountId: 43).values.isEmpty)
    }
}
