extension InputDataIdentifier { var identifier: String { value } }
struct FixtureFocus { let focus: Bool }
enum FixtureScrollPosition { case center(id: AnyHashable, innerId: Int?, animated: Bool, focus: FixtureFocus, inset: CGFloat) }
struct FixtureTableItem { let stableId: AnyHashable }
final class FixtureTableView {
    func enumerateItems(_ body: (FixtureTableItem) -> Bool) {}
    func scroll(to: FixtureScrollPosition, inset: NSEdgeInsets, toVisible: Bool) {}
}
struct FixturePeerId: Hashable {
    let value: Int64
    var namespace: Int32 = 0
    func toInt64() -> Int64 { value }
}
struct FixtureMessageId: Hashable { let peerId: FixturePeerId; var namespace: Int32 = 0; let id: Int32 }
struct FixtureFilterTitle: Equatable { let text: String }
enum ChatListFilter: Equatable {
    case allChats, filter(Int32, FixtureFilterTitle, Int, Int)
    var id: Int32 { switch self { case .allChats: return 0; case let .filter(id, _, _, _): return id } }
}
struct FixturePeers { func updatedChatListFilters() -> Signal<[ChatListFilter], NoError> { .single([]) } }
struct FixtureEngine { let peers = FixturePeers() }
final class FixtureNavigation { var pushed: [InputDataController] = []; func push(_ controller: InputDataController) { pushed.append(controller) } }
struct FixtureBindings { let navigation = FixtureNavigation(); func rootNavigation() -> FixtureNavigation { navigation } }
protocol AccountContextProtocol { var peerId: FixturePeerId { get }; var bindings: FixtureBindings { get }; var engine: FixtureEngine { get } }
final class FixtureContext: AccountContextProtocol {
    let peerId: FixturePeerId
    let bindings = FixtureBindings()
    let engine = FixtureEngine()
    init(_ accountId: Int64 = 42) { peerId = FixturePeerId(value: accountId) }
}
typealias ViewController = InputDataController
func RegramChatPreferencesController(context: any AccountContextProtocol) -> InputDataController { preconditionFailure("Unrelated navigation must not open") }
func RegramContextMenuController(context: any AccountContextProtocol) -> InputDataController { preconditionFailure("Unrelated navigation must not open") }
func RegramInlineRulesController(context: any AccountContextProtocol) -> InputDataController { preconditionFailure("Unrelated navigation must not open") }
func RegramLinkPreviewSettingsController(context: any AccountContextProtocol) -> InputDataController { preconditionFailure("Unrelated navigation must not open") }
func regramSegmentedRowItem(_ size: NSSize, stableId: InputDataEntryId, labels: [String], selected: Int, changed: @escaping (Int) -> Void) -> PrecieSliderRowItem { PrecieSliderRowItem(size, stableId: stableId, current: 0, magnit: [], update: { _ in }, viewType: .singleItem) }
func regramConfigureSegmentedRows(_ controller: InputDataController) {}
struct FixtureStrings { let chatSendAsHeader = "Send As" }
func strings() -> FixtureStrings { FixtureStrings() }
let appearanceSignal: Signal<Int, NoError> = .single(0)
func regramString(_ key: String) -> String { regramLocalizedString(key, languageCode: "en") }
let suite = "RegramMessageBookmarkChecks." + UUID().uuidString
let testDefaults = UserDefaults(suiteName: suite)!
let testPreferences = RegramPreferences(defaults: testDefaults)
let testBookmarks = RGMessageBookmarks(defaults: testDefaults)
func regramPreferenceChanges(accountId: Int64) -> Signal<RegramAccountSettings, NoError> {
    Signal { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: RegramPreferences.didChange, object: nil, queue: nil) { notification in
            if notification.object as? Int64 == accountId { subscriber.putNext(testPreferences.settings(accountId: accountId)) }
        }
        subscriber.putNext(testPreferences.settings(accountId: accountId))
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    }
}
enum Namespaces { enum Message { static let Cloud: Int32 = 0 }; enum Peer { static let SecretChat: Int32 = 2 } }
struct Message {
    let id: FixtureMessageId
    var text = ""
    var containsSecretMedia = false
    var threadId: Int64? = 7
    func isCopyProtected(cachedData: Int?) -> Bool { false }
}
struct FixturePresentation { let cachedData: Int? = nil }
struct ChatInteraction { let interactionContext: FixtureContext; let presentation = FixturePresentation() }
struct FixtureLanguage { struct Primary { let languageCode = "en" }; let primaryLanguage = Primary() }
let appCurrentLanguage = FixtureLanguage()
final class RegramMessageSpeech {
    static let shared = RegramMessageSpeech()
    func isSpeaking(accountId: Int64, messageId: FixtureMessageId) -> Bool { false }
    func toggle(text: String, accountId: Int64, messageId: FixtureMessageId) { preconditionFailure("Speech must not start") }
}
enum FixtureMenuAction { case speak, bookmark }
extension ContextMenuItem { func regramAction(_ value: FixtureMenuAction) -> ContextMenuItem { self } }
enum MenuAnimation {
    struct Item { let value: NSImage? = nil }
    static let menu_show_info = Item()
    static let menu_bookmark = Item()
}
func drain() { RunLoop.current.run(until: Date().addingTimeInterval(0.03)) }
func bookmarkId(_ message: Message) -> RGBookmarkMessageId { RGBookmarkMessageId(peerId: message.id.peerId.toInt64(), namespace: message.id.namespace, id: message.id.id) }
func menu(_ message: Message, _ context: FixtureContext) -> [ContextMenuItem] { regramMessageMenu(message: message, messages: [message], interaction: ChatInteraction(interactionContext: context), canReply: false, canForward: false) }
func enabled(_ value: Bool, accountId: Int64 = 42) { testPreferences.update(accountId: accountId) { $0["messageBookmarksEnabled"] = .bool(value) }; drain() }
func saved(_ validation: InputDataValidation) -> Bool { if case .success = validation { return true }; return false }

@main
struct BookmarkChecks {
    static func main() {
        defer { testDefaults.removePersistentDomain(forName: suite) }
        checkToggleMenuAndEditorLifecycle()
        checkEligibilityAndAccountIsolation()
        print("Message bookmark checks passed: persistent native switch, current menu/editor guards, disabled add/edit, preserved tags and references, re-enable recovery, account isolation and eligibility; no shared preferences, account or windows were used")
    }
    static func checkToggleMenuAndEditorLifecycle() {
        let context = FixtureContext()
        let existing = Message(id: FixtureMessageId(peerId: FixturePeerId(value: 100), id: 1))
        let unbookmarked = Message(id: FixtureMessageId(peerId: FixturePeerId(value: 100), id: 2))
        testBookmarks.save(accountId: 42, messageId: bookmarkId(existing), threadId: 7, tags: ["Read", "Keep"], now: 55)
        let original = testBookmarks.bookmarks(accountId: 42)
        let settings = RegramMessagesSettingsController(context: context, focus: "messageBookmarksEnabled")
        drain()
        let toggle = settings.entry("parity_messageBookmarksEnabled")
        precondition(toggle.enabled && toggle.type.identity == "switch.true" && toggle.title == regramString("Bookmarks.Title"))
        let oldAdd = menu(unbookmarked, context).first { $0.title == menuTitle("menu.bookmark") }!
        let oldEdit = menu(existing, context).first { $0.title == menuTitle("menu.editBookmark") }!
        oldEdit.handler()
        let oldEditor = context.bindings.navigation.pushed.last!
        toggle.action!()
        drain()
        precondition(!testPreferences.settings(accountId: 42)["messageBookmarksEnabled"].bool)
        precondition(!RegramPreferences(defaults: testDefaults).settings(accountId: 42)["messageBookmarksEnabled"].bool)
        precondition(settings.entry("parity_messageBookmarksEnabled").type.identity == "switch.false")
        precondition(menu(existing, context).isEmpty && menu(unbookmarked, context).isEmpty)
        let pushes = context.bindings.navigation.pushed.count
        oldAdd.handler(); oldEdit.handler()
        precondition(context.bindings.navigation.pushed.count == pushes)
        precondition(!saved(oldEditor.validateData([InputDataIdentifier("regram_bookmark_tags"): .string("Rejected")])))
        precondition(testBookmarks.bookmarks(accountId: 42) == original)
        precondition(RGMessageBookmarks(defaults: testDefaults).bookmarks(accountId: 42) == original)
        precondition(RegramSettingsCatalog.results(query: "bookmark", language: "en").contains { $0.destination == "settings.messageActions/messageBookmarksEnabled" })
        settings.entry("parity_messageBookmarksEnabled").action!()
        drain()
        precondition(testPreferences.settings(accountId: 42)["messageBookmarksEnabled"].bool)
        precondition(settings.entry("parity_messageBookmarksEnabled").type.identity == "switch.true")
        precondition(testBookmarks.bookmarks(accountId: 42) == original)
        menu(existing, context).first { $0.title == menuTitle("menu.editBookmark") }!.handler()
        let currentEditor = context.bindings.navigation.pushed.last!
        precondition(currentEditor.entry("regram_bookmark_tags").type.identity == "Read, Keep")
        precondition(saved(currentEditor.validateData([InputDataIdentifier("regram_bookmark_tags"): .string("Updated, Later")])))
        let updated = testBookmarks.bookmark(accountId: 42, messageId: bookmarkId(existing))!
        precondition(updated.tags == ["Updated", "Later"] && updated.threadId == 7 && updated.addedAt == 55)
        oldAdd.handler()
        let addEditor = context.bindings.navigation.pushed.last!
        precondition(saved(addEditor.validateData([InputDataIdentifier("regram_bookmark_tags"): .string("New")])))
        precondition(testBookmarks.bookmark(accountId: 42, messageId: bookmarkId(unbookmarked))?.tags == ["New"])
    }
    static func checkEligibilityAndAccountIsolation() {
        let context = FixtureContext()
        let other = FixtureContext(43)
        let cloud = Message(id: FixtureMessageId(peerId: FixturePeerId(value: 200), id: 3))
        enabled(false)
        precondition(menu(cloud, context).isEmpty)
        precondition(menu(cloud, other).contains { $0.title == menuTitle("menu.bookmark") })
        enabled(true)
        let local = Message(id: FixtureMessageId(peerId: cloud.id.peerId, namespace: 1, id: 3))
        let secretPeer = Message(id: FixtureMessageId(peerId: FixturePeerId(value: 200, namespace: Namespaces.Peer.SecretChat), id: 3))
        var secretMedia = cloud
        secretMedia.containsSecretMedia = true
        precondition(menu(local, context).isEmpty && menu(secretPeer, context).isEmpty && menu(secretMedia, context).isEmpty)
        precondition(testBookmarks.bookmarks(accountId: 43).isEmpty)
    }
}
