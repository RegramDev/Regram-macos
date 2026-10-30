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
import RegramCore
import RegramSignals
import RegramServices

private struct RegramHomeState: Equatable {
    var query = ""
}

private func regramCategoryController(context: any AccountContextProtocol, category: RegramCategory, focus: String?, initialPage: String?) -> InputDataController {
    switch category {
    case .messages: return RegramMessagesSettingsController(context: context, initialTab: initialPage, focus: focus)
    case .input: return RegramInputSettingsController(context: context, focus: focus)
    case .translation: return RegramTranslationSettingsController(context: context, focusSetting: focus)
    case .appearance: return RegramAppearanceCategoryController(context: context, focusSetting: focus, page: initialPage)
    case .media: return RegramMediaSettingsController(context: context, initialTab: initialPage, focus: focus)
    case .privacy, .network, .tools, .notifications: return regramComposedSettingsController(context: context, category: category, focus: focus)
    }
}

public func RegramSettingsController(context: any AccountContextProtocol, page: String? = nil) -> InputDataController {
    let parts = page?.split(separator: "/", maxSplits: 1).map(String.init) ?? []
    let rawPage = parts.first ?? "home"
    let rawFocus = parts.count > 1 ? parts[1] : nil
    let normalized = RegramSettingsRoute.normalized(page: rawPage, item: rawFocus)
    let route = normalized?.page ?? rawPage
    let focus: String? = normalized == nil ? rawFocus : normalized!.item
    let disclosures = ["messagesPage": "pro.messages", "inputPage": "pro.input", "networkPage": "pro.network", "translationPage": "pro.translation", "privacyPage": "pro.privacy", "mediaPage": "pro.media", "appearancePage": "pro.appearance", "notificationsPage": "pro.notifications", "toolsPage": "pro.tools", "messageActionsSettings": "settings.messageActions", "chatListSettings": "settings.chatList", "folderSettings": "settings.folders", "translationSettings": "settings.translation", "transcriptionSettings": "stt", "photoSettings": "settings.photos", "stickerSettings": "settings.stickers", "recordingSettings": "settings.recording", "mediaSettings": "settings.media", "appearanceSettings": "settings.appearance", "profileSettings": "settings.profiles", "storiesSettings": "settings.stories", "appSettings": "settings.app", "inputSettings": "settings.input", "transferSettings": "settings.transfer", "privacySettings": "settings.privacy", "bookmarks": "bookmarks", "inlineBotRules": "inlineBots", "groupProfileSettings": "groupProfile", "networkPolicy": "networkPolicy", "llmTranslationSettings": "llm", "bottomBarLayout": "bottomBar", "contextMenuOrder": "contextMenu", "linkPreviewSettings": "linkPreview", "appUpdate": "updates", "antiFeatures": "antiFeatures", "ghostMode": "ghostMode", "messageFilter": "messageFilter", "hiddenUsers": "hiddenUsers", "antiRevokeChats": "antiRevokeChats", "backup": "backup", "chatPreferences": "chatPreferences", "revokedMessages": "revokedMessages", "diagnostics": "diagnostics", "localGifts": "localGifts"]
    if route.hasPrefix("pro.") || route.hasPrefix("settings."), let focus, let target = disclosures[focus] {
        return RegramSettingsController(context: context, page: target)
    }
    if let category = RegramCategory(rawValue: route.hasPrefix("pro.") ? String(route.dropFirst(4)) : route) {
        return regramCategoryController(context: context, category: category, focus: focus, initialPage: nil)
    }
    if route.hasPrefix("settings.") {
        let initialPage = String(route.dropFirst(9))
        return regramCategoryController(context: context, category: RegramSettingsCatalog.category(for: route), focus: focus, initialPage: initialPage)
    }
    switch route {
    case "llm": return RegramServiceController(context: context, purpose: .translation, focusSetting: focus)
    case "stt": return RegramServiceController(context: context, purpose: .transcription, focusSetting: focus)
    case "inlineBots", "inlineRules":
        let controller = RegramInlineRulesController(context: context)
        regramFocusSettings(controller, page: "inlineBots", item: focus)
        return controller
    case "contextMenu": return RegramContextMenuController(context: context)
    case "linkPreview":
        let controller = RegramLinkPreviewSettingsController(context: context)
        regramFocusSettings(controller, page: "linkPreview", item: focus)
        return controller
    case "groupProfile": return RegramGroupProfileSettingsController(context: context, focusSetting: focus)
    case "bottomBar", "navigation": return RegramNavigationController(context: context, focusSetting: focus)
    case "networkPolicy": return focus == "test" ? RegramDNSController(context: context) : RegramNetworkPolicyController(context: context, focusSetting: focus)
    case "dns": return RegramDNSController(context: context, focusSetting: focus)
    case "diagnostics", "transferStats": return focus == "datacenters" ? RegramDatacenterController(context: context, focusSetting: "start") : RegramDiagnosticsController(context: context, focusSetting: focus)
    case "datacenters": return RegramDatacenterController(context: context, focusSetting: focus)
    case "antiFeatures": return RegramAntiFeaturesController(context: context, focusSetting: focus)
    case "ghostMode": return RegramGhostModeController(context: context, focusSetting: focus)
    case "revokedMarker": return RegramRevokedMarkerController(context: context, focusSetting: focus)
    case "messageFilter", "filters": return RegramFilterController(context: context, focusSetting: focus)
    case "hiddenUsers": return RegramHiddenPeersController(context: context, focusSetting: focus)
    case "antiRevokeChats": return RegramAntiRevokeChatsController(context: context, focusSetting: focus)
    case "revokedMessages": return RegramRetainedMessagesController(context: context, focusSetting: focus)
    case "chatPreferences": return RegramChatPreferencesController(context: context, focusSetting: focus)
    case "bookmarks": return RegramBookmarksController(context: context)
    case "updates": return RegramUIHooks.shared.makeUpdateController() ?? regramSettingsHomeController(context: context)
    case "recent": return RegramRecentChatsController(context: context)
    case "backup": return RegramSettingsBackupController(context: context, focusSetting: focus)
    case "localGifts": return RegramShowroomController(context: context, focusSetting: focus)
    case "startupFolder": return RegramMessagesSettingsController(context: context, initialTab: "folders", focus: "startupFolder")
    case "transcriptionTasks": return RegramTranscriptionTasksController(context: context, focusSetting: focus)
    case "webTranslation": return RegramWebTranslationURLController(context: context)
    default: return regramSettingsHomeController(context: context)
    }
}

private func regramSettingsHomeController(context: any AccountContextProtocol) -> InputDataController {
    let currentQuery = Atomic(value: "")
    let promise = ValuePromise(RegramHomeState(), ignoreRepeated: true)
    let signal = combineLatest(promise.get(), appearanceSignal) |> map { state, _ -> InputDataSignalValue in
        InputDataSignalValue(entries: regramSettingsHomeEntries(query: state.query, language: appCurrentLanguage.primaryLanguage.languageCode, update: { query in
            _ = currentQuery.swap(query)
            promise.set(RegramHomeState(query: query))
        }, open: { destination in
            if destination == "settings.appearance/appIcon" {
                RegramUIHooks.shared.openNativeSettings(context, "appIcon")
            } else {
                context.bindings.rootNavigation().push(RegramSettingsController(context: context, page: destination))
            }
        }))
    }
    let controller = RegramFormController(dataSignal: signal, title: "Regram Pro", removeAfterDisappear: false, hasDone: false, identifier: "regram.pro.home")
    regramRestoreSearchQuery(controller, identifier: InputDataIdentifier("pro.home.search"), autofocusSearch: false, query: { currentQuery.with { $0 } })
    return controller
}

private func regramComposedSettingsController(context: any AccountContextProtocol, category: RegramCategory, focus: String?) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let signal = combineLatest(regramPreferenceChanges(accountId: accountId), appearanceSignal) |> map { settings, _ -> InputDataSignalValue in
        var page = RegramPageBuilder(page: "pro." + category.rawValue)
        func toggle(_ key: String) { RegramPreferences.shared.update(accountId: accountId) { $0[key] = .bool(!$0[key].bool) } }
        func push(_ destination: String) { context.bindings.rootNavigation().push(RegramSettingsController(context: context, page: destination)) }
        switch category {
        case .privacy:
            page.section("Settings.Section.PrivacyControls")
            for (key, title) in [("messageFilter", "MessageFilter.Title"), ("hiddenUsers", "HiddenUsers.Title"), ("antiFeatures", "AntiFeatures.Header"), ("antiRevokeChats", "AntiRevoke.Chats.Title"), ("revokedMessages", "Revoked.Title"), ("ghostMode", "Ghost.Header")] {
                page.row(key, title: regramString(title), type: .next, action: { push(key) })
            }
            page.section("Settings.Section.PrivacyDisplay")
            page.row("hidePhoneInSettings", title: regramString("Settings.HidePhoneInSettingsUI"), type: .switchable(settings["hidePhoneInSettings"].bool), action: { toggle("hidePhoneInSettings") })
            page.text(regramString("Settings.HidePhoneInSettingsUI.Notice"))
            var section = page.nextSectionId
            var index = page.nextIndex
            let stories = regramStoriesSettingsEntries(context: context, settings: settings, sectionId: &section, index: &index)
            return InputDataSignalValue(entries: page.entries + stories)
        case .network:
            page.section("Settings.Section.Connection")
            page.row("diagnostics", title: regramString("Diagnostics.Title"), type: .next, action: { push("diagnostics") })
            page.row("networkPolicy", title: regramString("NetworkPolicy.Title"), type: .next, action: { push("networkPolicy") })
            page.section("Diagnostics.Download")
            page.row("uploadSpeedBoost", title: regramString("Settings.UploadsBoost"), type: .switchable(settings["uploadSpeedBoost"].bool), action: { toggle("uploadSpeedBoost") })
            page.row("downloadSpeedBoost", title: regramString("Settings.DownloadsBoost"), type: .switchable(settings["downloadSpeedBoost"].string != "none"), action: { RegramPreferences.shared.update(accountId: accountId) { $0["downloadSpeedBoost"] = .string($0["downloadSpeedBoost"].string == "none" ? "medium" : "none") } })
            page.text(regramString("Settings.DownloadsBoost.Notice"))
            page.section()
            page.text(strings().recentCallsRecentCalls, header: true)
            page.row("enableVoipTcp", title: regramString("Settings.Calls.ForceTCP"), type: .switchable(settings["enableVoipTcp"].bool), action: { toggle("enableVoipTcp") })
            page.text(regramString("Common.KnowWhatYouDo"))
        case .tools:
            page.section("Settings.ProCategory.tools")
            page.row("appUpdate", title: regramString("AppUpdate.Title"), type: .next, action: { push("updates") })
            page.row("backup", title: regramString("Backup.Title"), type: .next, action: { push("backup") })

        case .notifications:
            break
        default: break
        }
        return InputDataSignalValue(entries: page.entries)
    }
    let controller = RegramFormController(dataSignal: signal, title: regramString("Settings.ProCategory." + category.rawValue), removeAfterDisappear: false, hasDone: false, identifier: "regram.pro." + category.rawValue)
    regramFocusSettings(controller, page: "pro." + category.rawValue, item: focus)
    return controller
}
