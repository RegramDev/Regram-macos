import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import TelegramContext
import TelegramTheme
import Localization
import InputDataUI
import GeneralRows
import RegramCore
import RegramSignals

private enum RegramParityRow {
    case header(String)
    case notice(String)
    case toggle(String, String, inverted: Bool)
    case picker(String, String)
    case slider(String)
    case action(String, String)
}

private extension RegramParityRow {
    var controlKey: String? {
        switch self {
        case let .toggle(key, _, _), let .picker(key, _), let .slider(key), let .action(key, _): return key
        default: return nil
        }
    }
}

private struct RegramMessageMediaState: Equatable {
    var settings: RegramAccountSettings
    var tab: String
    var folders: [ChatListFilter] = []
}

private final class RegramMessageMediaArguments {
    let context: any AccountContextProtocol
    let set: (String, RegramValue) -> Void
    let tab: (String) -> Void
    let open: (String) -> Void
    init(context: any AccountContextProtocol, set: @escaping (String, RegramValue) -> Void, tab: @escaping (String) -> Void, open: @escaping (String) -> Void) {
        self.context = context
        self.set = set
        self.tab = tab
        self.open = open
    }
}

private func regramParityText(_ key: String) -> String {
    if ["Media.ClipboardOriginalImages", "Media.ClipboardOriginalImages.Notice", "Bookmarks.Title"].contains(key) { return regramString(key) }
    let text = regramString("ios." + key)
    let argument: String
    switch key {
    case "Settings.Folders.AllChatsHidden": argument = regramString("ios.Native.AllChats")
    case "Settings.SendAsButton": argument = strings().chatSendAsHeader
    default: argument = "Telegram Premium"
    }
    return text.replacingOccurrences(of: "%1$@", with: argument).replacingOccurrences(of: "%@", with: argument)
}

private func regramParityRows(_ page: String) -> [RegramParityRow] {
    switch page {
    case "messageActions": return [
        .header("Settings.ContextMenu"),
        .action("contextMenuOrder", "Settings.ContextMenu.Customize"),
        .notice("Settings.ContextMenu.Notice"),
        .header("Settings.Category.messageActions"),
        .toggle("messageBookmarksEnabled", "Bookmarks.Title", inverted: false),
        .toggle("hideChannelBottomButton", "Settings.showChannelBottomButton", inverted: true),
        .toggle("secondsInMessages", "Settings.secondsInMessages", inverted: false),
        .toggle("showMessageId", "Settings.ShowMessageId", inverted: false),
        .toggle("automaticallyRevealSpoilers", "Settings.AutomaticallyRevealSpoilers", inverted: false),
        .notice("Settings.AutomaticallyRevealSpoilers.Notice"),
        .toggle("showForwardedMessageDate", "Settings.ShowForwardedMessageDate", inverted: false),
        .toggle("hideReactions", "Settings.HideReactions", inverted: false),
        .toggle("features.confirmUnpin", "features.ConfirmUnpin", inverted: false),
        .toggle("features.stayAtLatestMessageAfterRefresh", "features.StayAtLatestMessageAfterRefresh", inverted: false),
        .action("inlineBotRules", "features.InlineBots.Title")
    ]
    case "chatList": return [
        .header("Settings.ChatList.Header"),
        .toggle("compactChatList", "Settings.CompactChatList", inverted: false),
        .picker("chatListLines", "Settings.ChatList.Lines"),
        .toggle("hideChatListSeparators", "Settings.ChatList.HideSeparators", inverted: false),
        .toggle("unlimitedPinnedChats", "Settings.UnlimitedPinnedChats", inverted: false),
        .notice("Settings.UnlimitedPinnedChats.Notice"),
        .toggle("features.hideSavedAndArchivedMessagesInList", "features.HideSavedAndArchivedMessagesInList", inverted: false),
        .toggle("features.hidePrivateChatActivities", "features.HidePrivateChatActivities", inverted: false),
        .notice("features.HidePrivateChatActivities.Notice"),
        .toggle("features.keepNewChatsVisibleAtTop", "features.KeepNewChatsVisibleAtTop", inverted: false),
        .picker("features.chatListSwipeAction", "features.ChatListSwipeAction"),
        .picker("features.communityAvatarTapAction", "features.CommunityAvatarTapAction")
    ]
    case "folders": return [
        .header("Settings.ChatFolders"),
        .toggle("native.foldersAtBottom", "Settings.Folders.BottomTab", inverted: false),
        .toggle("allChatsHidden", "Settings.Folders.AllChatsHidden", inverted: false),
        .toggle("compactFolderNames", "Settings.Folders.CompactNames", inverted: false),
        .picker("features.chatListStartupFolderMode", "features.ChatListStartupFolder"),
        .notice("Settings.Folders.RememberLast.Notice"),
        .toggle("chooseFolderAfterJoining", "JoinFolder.Setting", inverted: false),
        .notice("JoinFolder.Setting.Notice"),
        .toggle("features.showFoldersInShareSheet", "features.ShowFoldersInShareSheet", inverted: false),
        .toggle("features.hideFolderUnreadCount", "features.HideFolderUnreadCount", inverted: false),
        .toggle("features.showArchiveInFolders", "features.ShowArchiveInFolders", inverted: false)
    ]
    case "input": return [
        .header("Settings.Section.Sending"),
        .toggle("hideRecordingButton", "Settings.RecordingButton", inverted: true),
        .toggle("disableSendAsButton", "Settings.SendAsButton", inverted: true),
        .toggle("sendWithReturnKey", "Settings.SendWithReturnKey", inverted: false)
    ]
    case "media": return [
        .header("Settings.Section.Playback"),
        .picker("defaultVideoQuality", "Settings.DefaultVideoQuality"),
        .toggle("showMediaMetadata", "MediaMetadata.Setting", inverted: false),
        .notice("MediaMetadata.Setting.Notice")
    ]
    case "photos": return [
        .header("Native.Quality"),
        .slider("outgoingPhotoQuality"),
        .notice("Settings.Photo.Quality.Notice"),
        .header("Settings.Section.Sending"),
        .toggle("sendLargePhotos", "Settings.Photo.SendLarge", inverted: false),
        .notice("Settings.Photo.SendLarge.Notice"),
        .toggle("clipboardOriginalImages", "Media.ClipboardOriginalImages", inverted: false),
        .notice("Media.ClipboardOriginalImages.Notice")
    ]
    case "stickers": return [
        .header("Settings.Stickers.Size"),
        .slider("stickerSize"),
        .header("Native.Stickers"),
        .toggle("stickerTimestamp", "Settings.Stickers.Timestamp", inverted: false),
        .picker("recentStickerLimit", "Settings.Stickers.RecentLimit"),
        .toggle("forceEmojiTab", "Settings.ForceEmojiTab", inverted: false),
        .toggle("defaultEmojisFirst", "Settings.DefaultEmojisFirst", inverted: false),
        .notice("Settings.DefaultEmojisFirst.Notice")
    ]
    case "recording": return [
        .header("Native.VoiceMessages"),
        .toggle("forceBuiltInMic", "Settings.forceBuiltInMic", inverted: false),
        .notice("Settings.forceBuiltInMic.Notice"),
        .toggle("disableGalleryCamera", "Settings.GalleryCamera", inverted: true)
    ]
    default: return []
    }
}

private func regramParitySupplement(_ page: String) -> [RegramParityRow] {
    switch page {
    case "input": return [
        .header("Settings.Section.Composer"),
        .toggle("mentionAsUserIdLink", "Mention.UserIdLink", inverted: false),
        .notice("Mention.UserIdLink.Notice"),
        .picker("defaultOutgoingFormatting", "OutgoingFormatting.Title"),
        .notice("OutgoingFormatting.Notice"),
        .action("chatPreferences", "ChatPreferences.Title")
    ]
    case "pangu": return [
        .header("Pangu.Title"),
        .toggle("features.enablePanguOnReceiving", "features.PanguOnReceiving", inverted: false),
        .toggle("panguSpacing", "features.PanguOnSending", inverted: false),
        .toggle("features.enablePanguOnEditing", "features.PanguOnEditing", inverted: false),
        .notice("features.PanguInfo")
    ]
    case "media": return [
        .header("Settings.Section.Links"),
        .toggle("disableLinkPreview", "LinkPreview.Disable", inverted: false),
        .notice("LinkPreview.Disable.Notice"),
        .action("linkPreviewSettings", "LinkPreview.Repair")
    ]
    default: return []
    }
}

private func regramParityValueTitle(_ key: String, _ value: RegramValue) -> String {
    if key == "recentStickerLimit" { return String(value.integer) }
    let prefix: String
    switch key {
    case "messageDoubleTapAction", "messageDoubleTapActionWithoutEditPermission": prefix = "DoubleTap.Action."
    case "defaultOutgoingFormatting": prefix = "OutgoingFormatting."
    case "defaultVideoQuality": prefix = "Settings.DefaultVideoQuality."
    case "chatListLines": prefix = "Settings.ChatList.Lines."
    case "features.chatListSwipeAction": prefix = "features.ChatListSwipeAction."
    case "features.chatListFolderTabDisplayMode": prefix = "features.ChatListFolderTabDisplayMode."
    case "features.communityAvatarTapAction": prefix = "features.CommunityAvatarTapAction."
    case "allChatsTitleLengthOverride": prefix = "Settings.Folders.AllChatsTitle."
    default: prefix = key + "."
    }
    return regramParityText(prefix + value.string)
}

private func regramMessageMediaEntries(_ state: RegramMessageMediaState, category: String, arguments: RegramMessageMediaArguments) -> [InputDataEntry] {
    let tabs = category == "messages" ? ["messageActions", "chatList", "folders"] : category == "media" ? ["media", "photos", "stickers", "recording"] : []
    var rows: [InputDataEntry] = [.sectionId(0, type: .normal)]
    var section: Int32 = 1
    var index: Int32 = 0
    if !tabs.isEmpty {
        rows.append(.custom(sectionId: section, index: index, value: .none, identifier: InputDataIdentifier("parity_tabs"), equatable: InputDataEquatable(state.tab), comparable: nil, item: { size, stableId in
            regramSegmentedRowItem(size, stableId: stableId, labels: tabs.map { regramParityText("Settings.CategoryTab." + $0) }, selected: tabs.firstIndex(of: state.tab) ?? 0, changed: { index in
                arguments.tab(tabs[index])
            })
        }))
        index += 1
    }
    let values: [RegramParityRow]
    if category == "input" { values = regramParitySupplement("input") + regramParityRows("input") + regramParitySupplement("pangu") }
    else if category == "messages", state.tab == "messageActions" { values = regramParitySupplement("messages") + regramParityRows(state.tab) }
    else if category == "media", state.tab == "media" { values = regramParitySupplement("media") + regramParityRows(state.tab) }
    else { values = regramParityRows(state.tab) }
    for (offset, value) in values.enumerated() {
        let identifier = InputDataIdentifier("parity_" + (value.controlKey ?? category + "_" + state.tab + "_" + String(offset)))
        let hasPrevious = offset > 0 && values[offset - 1].controlKey != nil
        let hasNext = offset + 1 < values.count && values[offset + 1].controlKey != nil
        let viewType: GeneralViewType = hasPrevious ? (hasNext ? .innerItem : .lastItem) : (hasNext ? .firstItem : .singleItem)
        func general(_ title: String, _ type: GeneralInteractedType, enabled: Bool = true, action: @escaping () -> Void = {}) {
            rows.append(.general(sectionId: section, index: index, value: .none, error: nil, identifier: identifier, data: .init(name: title, color: theme.colors.text, type: type, viewType: viewType, enabled: enabled, action: action)))
        }
        switch value {
        case let .header(key):
            if index > 0 { rows.append(.sectionId(section, type: .normal)); section += 1 }
            rows.append(.desc(sectionId: section, index: index, text: .plain(regramParityText(key)), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        case let .notice(key):
            rows.append(.desc(sectionId: section, index: index, text: .plain(regramParityText(key)), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        case let .toggle(key, title, inverted):
            let current = state.settings[key].bool
            general(regramParityText(title), .switchable(inverted ? !current : current), action: { arguments.set(key, .bool(!current)) })
        case let .picker(key, title):
            if key == "features.chatListStartupFolderMode" {
                var items = ["telegram", "last"].map { mode in ContextMenuItem(regramParityText("features.ChatListStartupFolder." + mode), handler: { arguments.set(key, .string(mode)) }) }
                for filter in state.folders {
                    let name: String
                    switch filter { case .allChats: name = regramParityText("Native.AllChats"); case let .filter(_, title, _, _): name = title.text }
                    items.append(ContextMenuItem(name, handler: {
                        var dictionary: [String: String] = [:]
                        if case let .dictionary(values) = state.settings["features.startupFolders"] { dictionary = values }
                        dictionary[String(arguments.context.peerId.toInt64())] = String(filter.id == 0 ? -1 : filter.id)
                        arguments.set("features.startupFolders", .dictionary(dictionary))
                        arguments.set(key, .string("specific"))
                    }))
                }
                general(regramParityText(title), .contextSelector(regramParityText("features.ChatListStartupFolder." + state.settings[key].string), items))
            } else {
                let current = state.settings[key]
                let options = RegramSetting.byKey[key]?.choices ?? []
                let items = options.map { value in ContextMenuItem(regramParityValueTitle(key, value), handler: { arguments.set(key, value) }, state: current == value ? .on : .off) }
                general(regramParityText(title), .contextSelector(regramParityValueTitle(key, current), items))
            }
        case let .slider(key):
            let value = min(100, max(0, state.settings[key].integer))
            rows.append(.custom(sectionId: section, index: index, value: .none, identifier: identifier, equatable: InputDataEquatable(value), comparable: nil, item: { size, stableId in
                PrecieSliderRowItem(size, stableId: stableId, current: CGFloat(value) / 100, markers: ["0%", "100%"], showValue: "\(value)%", update: { progress in arguments.set(key, .integer(Int64((progress * 100).rounded()))) }, viewType: .singleItem)
            }))
        case let .action(id, title):
            general(regramParityText(title), .next, action: { arguments.open(id) })
        }
        index += 1
    }
    return rows
}

private func regramMessageMediaController(context: any AccountContextProtocol, category: String, initialTab: String?, focus: String?) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let tabs = category == "messages" ? ["messageActions", "chatList", "folders"] : category == "media" ? ["media", "photos", "stickers", "recording"] : ["input"]
    let focus = focus.map { value -> String in
        if value == "startupFolder" { return "features.chatListStartupFolderMode" }
        if RegramSetting.byKey[value] == nil, RegramSetting.byKey["features." + value] != nil { return "features." + value }
        return value
    }
    let focusTab = focus.flatMap { target in tabs.first(where: { tab in regramParityRows(tab).contains(where: { $0.controlKey == target }) }) }
    let selected = initialTab.flatMap { tabs.contains($0) ? $0 : nil } ?? focusTab ?? tabs[0]
    let initial = RegramMessageMediaState(settings: RegramPreferences.shared.settings(accountId: accountId), tab: selected)
    let state = Atomic(value: initial)
    let promise = ValuePromise(initial, ignoreRepeated: true)
    let disposables = DisposableSet()
    func update(_ transform: (inout RegramMessageMediaState) -> Void) { promise.set(state.modify { value in var value = value; transform(&value); return value }) }
    let arguments = RegramMessageMediaArguments(context: context, set: { key, value in
        RegramPreferences.shared.update(accountId: accountId) { $0[key] = value }
    }, tab: { tab in update { $0.tab = tab } }, open: { id in
        let controller: ViewController?
        switch id {
        case "chatPreferences": controller = RegramChatPreferencesController(context: context)
        case "contextMenuOrder": controller = RegramContextMenuController(context: context)
        case "inlineBotRules": controller = RegramInlineRulesController(context: context)
        case "linkPreviewSettings": controller = RegramLinkPreviewSettingsController(context: context)
        default: controller = nil
        }
        if let controller { context.bindings.rootNavigation().push(controller) }
    })
    let signal = combineLatest(promise.get(), appearanceSignal) |> map { state, _ in InputDataSignalValue(entries: regramMessageMediaEntries(state, category: category, arguments: arguments)) }
    var didFocus = false
    let controller = InputDataController(dataSignal: signal, title: regramParityText("Settings.ProCategory." + category), removeAfterDisappear: false, hasDone: false, identifier: "regram.pro." + category, afterTransaction: { controller in
        guard !didFocus, let focus else { return }
        controller.tableView.enumerateItems { item in
            if let id = (item.stableId.base as? InputDataEntryId)?.identifier, id.identifier == "parity_" + focus {
                didFocus = true
                controller.tableView.scroll(to: .center(id: item.stableId, innerId: nil, animated: true, focus: .init(focus: true), inset: 0), inset: NSEdgeInsets(), toVisible: true)
                return false
            }
            return true
        }
    })
    if category != "input" { regramConfigureSegmentedRows(controller) }
    disposables.add(regramPreferenceChanges(accountId: accountId).start(next: { settings in update { $0.settings = settings } }))
    disposables.add((context.engine.peers.updatedChatListFilters() |> deliverOnMainQueue).start(next: { folders in update { $0.folders = folders } }))
    controller.onDeinit = { disposables.dispose() }
    return controller
}

public func RegramMessagesSettingsController(context: any AccountContextProtocol, initialTab: String? = nil, focus: String? = nil) -> InputDataController {
    regramMessageMediaController(context: context, category: "messages", initialTab: initialTab, focus: focus)
}

public func RegramInputSettingsController(context: any AccountContextProtocol, focus: String? = nil) -> InputDataController {
    regramMessageMediaController(context: context, category: "input", initialTab: nil, focus: focus)
}

public func RegramMediaSettingsController(context: any AccountContextProtocol, initialTab: String? = nil, focus: String? = nil) -> InputDataController {
    regramMessageMediaController(context: context, category: "media", initialTab: initialTab, focus: focus)
}
