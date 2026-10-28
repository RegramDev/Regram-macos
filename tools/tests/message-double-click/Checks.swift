import Foundation
import CoreGraphics

public enum RegramValue {
    case string(String)
    case integer(Int64)
    var string: String { if case let .string(value) = self { return value }; return "" }
    var integer: Int64 { if case let .integer(value) = self { return value }; return 0 }
}

public struct RegramAccountSettings {
    var values: [String: RegramValue] = [:]
    subscript(key: String) -> RegramValue {
        get { values[key] ?? .string(key == "messageDoubleTapAction" ? "sendReaction" : "sameAsUnified") }
        set { values[key] = newValue }
    }
}

__POLICY__

var actions: [String] = []
struct TestEvent {}
final class TestApplication { var currentEvent: TestEvent? = TestEvent() }
let NSApp = TestApplication()
extension Int64 { func toInt64() -> Int64 { self } }
struct TestContext { var peerId: Int64 = 1; var account: Int64 = 700; var isFrozen = false }
struct TestMessage { var editable = true; var replyable = true; var id: Int64 = 1; var forwardable = true; var media: [Int] = [] }
typealias Message = TestMessage
typealias ChatInteraction = TestInteraction
struct TestReply { let messageId: Int64; let quote: String?; let innerSubject: String? }
enum TestState { case normal, selecting }
struct TestSlowMode { var hasLocked = false }
struct TestPeer {
    var isDeleted = false
    var allowsSending = true
    func canSendMessage(_ threaded: Bool, media: Int?, threadData: Int) -> Bool { allowsSending }
}
final class TestPresentation {
    var state = TestState.normal
    var canReplyInRestrictedMode = true
    var peer: TestPeer? = TestPeer()
    var sendPaidMessageStars: Int?
    var slowMode: TestSlowMode?
    var slowModeMultipleLocked = false
    var currentSendAsPeerId: Int64?
    var threadInfo = 0
}
struct TestLocation { var threadId: Int64? }
struct TestMode { var isThreadMode = false; var isTopicMode = false }
final class TestInteraction {
    let presentation = TestPresentation()
    let peerId: Int64 = 1
    var interactionContext = TestContext()
    var chatLocation = TestLocation()
    var mode = TestMode()
    var getMessages: Int?
    var draft = "unsent draft"
    var copyPayload: [Int]? = [1, 2]
    func setupReplyMessage(_ message: TestMessage, _ reply: TestReply) { actions.append("reply") }
}
struct TestEntry { var messages = [TestMessage()] }
final class RegramPreferences {
    static let shared = RegramPreferences()
    var value = RegramAccountSettings()
    func settings(accountId: Int64) -> RegramAccountSettings { value }
}
final class ChatRowItem {
    var message: TestMessage? = TestMessage()
    let context = TestContext()
    let chatInteraction = TestInteraction()
    let entry = TestEntry()
    var canReact = true
    func reactAction() -> Bool { if canReact { actions.append("sendReaction") }; return canReact }
    func replyAction() -> Bool { actions.append("reply"); return true }
    func editAction() -> Bool { actions.append("edit"); return true }
}
func canEditMessage(_ message: TestMessage, chatInteraction: TestInteraction, context: TestContext) -> Bool { message.editable }
func canReplyMessage(_ message: TestMessage, peerId: Int64, chatLocation: TestLocation, mode: TestMode) -> Bool { message.replyable }
func canForwardMessage(_ message: TestMessage, chatInteraction: TestInteraction) -> Bool { message.forwardable }
func regramToggleQuickTranslation(_ item: ChatRowItem) { actions.append("translate") }
struct RecordedSend { let peerId: Int64; let threadId: Int64?; let sendAs: Int64?; let ids: [Int64] }
var sends: [RecordedSend] = []
struct TestSignal { let start: () -> Void; func startStandalone() { start() } }
enum Sender {
    static func forwardMessages(messageIds: [Int64], context: TestContext, peerId: Int64, replyId: TestReply?, threadId: Int64?, sendAsPeerId: Int64?) -> TestSignal {
        TestSignal { actions.append("repeatMessage"); sends.append(.init(peerId: peerId, threadId: threadId, sendAs: sendAsPeerId, ids: messageIds)) }
    }
}
func enqueueMessages(account: Int64, peerId: Int64, messages: [Int]) -> TestSignal {
    TestSignal { actions.append("repeatWithoutQuote"); sends.append(.init(peerId: peerId, threadId: nil, sendAs: nil, ids: messages.map(Int64.init))) }
}
func regramRepeatCopyMessages(_ messages: [Message], interaction: ChatInteraction) -> [Int]? { interaction.copyPayload }
struct TestForwardObject { func possibilityPerformTo(_ peer: TestPeer) -> Bool { peer.allowsSending } }
final class ChatForwardMenuAction {
    init(chatInteraction: TestInteraction, sources: [Message]) {}
    func forward(_ object: TestForwardObject, peerId: Int64, threadId: Int64?) { actions.append("preparedDraft") }
}
final class ChatHistoryUIHooks {
    static let shared = ChatHistoryUIHooks()
    func makeForwardMessagesObjectObserved(_ context: TestContext, _ messages: [Message], _ album: Bool, _ getMessages: Int?) -> TestForwardObject { TestForwardObject() }
}
__CAN_REPEAT__
__REPEAT_FORWARD__
__REPEAT_COPY__
__DEFERRED__
func menuRepeatForward(_ messages: [Message], interaction: ChatInteraction, action: ChatDeferredSendAction) {
    let forward = ChatForwardMenuAction(chatInteraction: interaction, sources: messages)
    let object = TestForwardObject()
    __MENU_FORWARD__
}
func menuRepeatCopy(_ messages: [Message], interaction: ChatInteraction, action: ChatDeferredSendAction) { __MENU_COPY__ }
class TestView: NSObject { var frame = NSRect.zero }
class TableRowView: TestView {
    var item: Any? = ChatRowItem()
    var contentHit = false
    var hit: TestView?
    var avatar: TestView?
    let rowView = TestView()
    let bubbleView = TestView()
    let replyView = TestView()
    func hitTest(_ point: NSPoint) -> TestView? { hit }
    func clickInContent(point: NSPoint) -> Bool { contentHit }
    func showContextMenu(_ event: TestEvent) { actions.append("showReactions") }
    func doubleClick(in location: NSPoint) {}
}
class ChatRowView: TableRowView {
    __ELIGIBILITY__
    override func doubleClick(in location: NSPoint) { __ROW_ACTION__ }
}
final class ServiceRowView: TableRowView {
    override func doubleClick(in location: NSPoint) { __SERVICE_ACTION__ }
}
__HANDLER__

func regramString(_ key: String) -> String { key }
struct TestStrings { let chatSendAsHeader = "Send as" }
func strings() -> TestStrings { TestStrings() }
__ROW_TYPE__
__ROWS__
__TITLE__
__VALUE_TITLE__

var checks = 0
var failures: [String] = []
func check(_ condition: Bool, _ name: String) {
    checks += 1
    if !condition { failures.append(name); print("FAIL: " + name) }
}
let point = NSPoint(x: 40, y: 40)
for service in [false, true] {
    for action in RGMessageDoubleClickAction.allCases {
        let row: TableRowView = service ? ServiceRowView() : ChatRowView()
        RegramPreferences.shared.value["messageDoubleTapAction"] = .string(action.rawValue)
        actions = []
        row.doubleClick(in: point)
        check(actions == (action == .disabled ? [] : [action.rawValue]), "dispatch \(action) service=\(service)")
        let item = row.item as! ChatRowItem
        item.message?.editable = false
        RegramPreferences.shared.value["messageDoubleTapAction"] = .string("edit")
        RegramPreferences.shared.value["messageDoubleTapActionWithoutEditPermission"] = .string(action.rawValue)
        actions = []
        row.doubleClick(in: point)
        let fallback = action == .edit ? RGMessageDoubleClickAction.sendReaction : action
        check(actions == (fallback == .disabled ? [] : [fallback.rawValue]), "fallback \(action) service=\(service)")
        RegramPreferences.shared.value = RegramAccountSettings()
    }
}
for blocked in ["text", "control", "avatar", "restricted", "unreplyable", "missing"] {
    let row = ChatRowView()
    let item = row.item as! ChatRowItem
    switch blocked {
    case "text": row.contentHit = true
    case "control": row.hit = TestView()
    case "avatar": row.avatar = TestView(); row.avatar!.frame = NSRect(x: 30, y: 30, width: 20, height: 20)
    case "restricted": item.chatInteraction.presentation.canReplyInRestrictedMode = false
    case "unreplyable": item.message?.replyable = false
    default: item.message = nil
    }
    actions = []
    row.doubleClick(in: point)
    check(actions.isEmpty, "preserve native exclusion: " + blocked)
}
let service = ServiceRowView()
(service.item as! ChatRowItem).chatInteraction.presentation.state = .selecting
actions = []
service.doubleClick(in: point)
check(actions.isEmpty, "service selection mode")
let row = ChatRowView()
let item = row.item as! ChatRowItem
item.canReact = false
for action in ["sendReaction", "showReactions"] {
    RegramPreferences.shared.value["messageDoubleTapAction"] = .string(action)
    actions = []
    row.doubleClick(in: point)
    check(actions.isEmpty, "reaction unavailable: " + action)
}
let pickers = regramParityRows("messageActions").compactMap { row -> String? in
    if case let .picker(key, _) = row { return key }; return nil
}
check(pickers.contains("messageDoubleTapAction"), "unified action picker exists")
check(pickers.contains("messageDoubleTapActionWithoutEditPermission"), "fallback action picker exists")
check(regramParityText("setting.messageDoubleTapActionWithoutEditPermission") == "setting.messageDoubleTapActionWithoutEditPermission", "fallback title uses macOS localization")
for action in RGMessageDoubleClickAction.allCases.map(\.rawValue) + ["sameAsUnified"] {
    check(regramParityValueTitle("messageDoubleTapAction", .string(action)) == "ios.DoubleTap.Action." + action, "localized action title: " + action)
}
for copying in [false, true] {
    let interaction = TestInteraction()
    interaction.chatLocation.threadId = 17
    interaction.presentation.currentSendAsPeerId = 88
    let messages = [Message(id: 1), Message(id: 2)]
    let action = ChatDeferredSendAction { true }
    actions = []; sends = []
    for _ in 0..<2 {
        if copying { menuRepeatCopy(messages, interaction: interaction, action: action) }
        else { menuRepeatForward(messages, interaction: interaction, action: action) }
    }
    check(sends.count == 1, "menu subscribes to send exactly once: copying=\(copying)")
    check(actions == [copying ? "repeatWithoutQuote" : "repeatMessage"], "menu sends without preparing composer: copying=\(copying)")
    check(interaction.draft == "unsent draft", "menu preserves draft: copying=\(copying)")
    check(sends.first?.peerId == interaction.peerId, "menu targets current chat: copying=\(copying)")
    check(sends.first?.ids == [1, 2], "menu sends selected messages: copying=\(copying)")
    if !copying {
        check(sends.first?.threadId == 17, "forward preserves topic")
        check(sends.first?.sendAs == 88, "forward preserves send-as identity")
    }
    actions = []; sends = []
    let stale = ChatDeferredSendAction { false }
    if copying { menuRepeatCopy(messages, interaction: interaction, action: stale) }
    else { menuRepeatForward(messages, interaction: interaction, action: stale) }
    check(sends.isEmpty && actions.isEmpty, "stale menu does not send: copying=\(copying)")
}
for reason in ["frozen", "deleted", "paid", "slow", "multiple", "selecting", "permission", "forwarding", "empty", "tooMany"] {
    let interaction = TestInteraction()
    var messages = [Message()]
    switch reason {
    case "frozen": interaction.interactionContext.isFrozen = true
    case "deleted": interaction.presentation.peer?.isDeleted = true
    case "paid": interaction.presentation.sendPaidMessageStars = 1
    case "slow": interaction.presentation.slowMode = TestSlowMode(hasLocked: true)
    case "multiple": interaction.presentation.slowModeMultipleLocked = true
    case "selecting": interaction.presentation.state = .selecting
    case "permission": interaction.presentation.peer?.allowsSending = false
    case "forwarding": messages[0].forwardable = false
    case "empty": messages = []
    default: messages = Array(repeating: Message(), count: 101)
    }
    actions = []; sends = []
    regramRepeatForward(messages, interaction: interaction)
    check(sends.isEmpty && actions.isEmpty, "direct repeat retains restriction: " + reason)
}
let report: [String: Any] = ["checks": checks, "failures": failures]
try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
print("\(checks) message double-click checks; \(failures.count) failures")
exit(failures.isEmpty ? 0 : 1)
