import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import InputDataUI
import RegramCore
import RegramSignals

func regramStoriesSettingsEntries(context: any AccountContextProtocol, settings: RegramAccountSettings, sectionId: inout Int32, index: inout Int32) -> [InputDataEntry] {
    let accountId = context.peerId.toInt64()
    var page = RegramPageBuilder(page: "stories", sectionId: sectionId, index: index)
    page.section("AutoDownloadSettings.Stories")
    let rows = [("hideStories", "Settings.Stories.Hide"), ("warnOnStoriesOpen", "Settings.Stories.WarnBeforeView"), ("showRepostToStoryV2", "Share.RepostToStory")]
    for (key, title) in rows { page.row(key == "showRepostToStoryV2" ? "showRepostToStory" : key, title: regramString(title).replacingOccurrences(of: "\n", with: " "), type: .switchable(settings[key].bool), action: { RegramPreferences.shared.update(accountId: accountId) { $0[key] = .bool(!$0[key].bool) } }) }
    if settings["canUseStealthMode"].bool {
        page.row("storyStealthMode", title: regramString("Story.StealthMode.Title"), type: .switchable(settings["storyStealthMode"].bool), action: { RegramPreferences.shared.update(accountId: accountId) { $0["storyStealthMode"] = .bool(!$0["storyStealthMode"].bool) } })
        page.text(regramString("Story.StealthMode.ControlText"))
    }
    for (key, title) in [("features.hideTopStories", "features.HideTopStories"), ("features.disableChatAvatarStories", "features.DisableChatAvatarStories")] {
        page.row(String(key.dropFirst("features.".count)), title: regramString(title), type: .switchable(settings[key].bool), action: { RegramPreferences.shared.update(accountId: accountId) { $0[key] = .bool(!$0[key].bool) } })
    }
    sectionId = page.nextSectionId
    index = page.nextIndex
    return page.entries
}

public func RegramStoriesSettingsController(context: any AccountContextProtocol, focusSetting: String? = nil) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let signal = combineLatest(regramPreferenceChanges(accountId: accountId), appearanceSignal) |> map { settings, _ in
        var section: Int32 = 0
        var index: Int32 = 0
        return InputDataSignalValue(entries: regramStoriesSettingsEntries(context: context, settings: settings, sectionId: &section, index: &index))
    }
    let controller = RegramFormController(dataSignal: signal, title: regramString("AutoDownloadSettings.Stories"), removeAfterDisappear: false, hasDone: false, identifier: "regram.stories")
    regramFocusSettings(controller, page: "stories", item: focusSetting)
    return controller
}

func regramProfilesSettingsEntries(context: any AccountContextProtocol, settings: RegramAccountSettings, sectionId: inout Int32, index: inout Int32) -> [InputDataEntry] {
    let accountId = context.peerId.toInt64()
        var page = RegramPageBuilder(page: "profiles", sectionId: sectionId, index: index)
        page.section("Settings.Profiles.Header")
        let values: [(String, String, String?)] = [("showProfileId", "Settings.ShowProfileID", nil), ("showDC", "Settings.ShowDC", nil), ("showRegDate", "Settings.ShowRegDate", "Settings.ShowRegDate.Notice"), ("showCreationDate", "Settings.ShowCreationDate", "Settings.ShowCreationDate.Notice"), ("profileDefaultTabGroupsInCommon", "Settings.Profiles.DefaultTabGroupsInCommon", "Settings.Profiles.DefaultTabGroupsInCommon.Notice"), ("confirmCalls", "Settings.CallConfirmation", "Settings.CallConfirmation.Notice")]
        for (key, title, notice) in values {
            page.row(key, title: regramString(title), type: .switchable(settings[key].bool), description: notice.map(regramString), action: { RegramPreferences.shared.update(accountId: accountId) { $0[key] = .bool(!$0[key].bool) } })
        }
        page.row("groupProfileSettings", title: regramString("features.GroupProfileSettings"), type: .next, action: { context.bindings.rootNavigation().push(RegramGroupProfileSettingsController(context: context)) })
    sectionId = page.nextSectionId
    index = page.nextIndex
    return page.entries
}

public func RegramProfilesSettingsController(context: any AccountContextProtocol, focusSetting: String? = nil) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let signal = combineLatest(regramPreferenceChanges(accountId: accountId), appearanceSignal) |> map { settings, _ -> InputDataSignalValue in
        var section: Int32 = 0
        var index: Int32 = 0
        return InputDataSignalValue(entries: regramProfilesSettingsEntries(context: context, settings: settings, sectionId: &section, index: &index))
    }
    let controller = RegramFormController(dataSignal: signal, title: regramString("Settings.Profiles.Header"), removeAfterDisappear: false, hasDone: false, identifier: "regram.profiles")
    regramFocusSettings(controller, page: "profiles", item: focusSetting)
    return controller
}

public func RegramGroupProfileSettingsController(context: any AccountContextProtocol, focusSetting: String? = nil) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let signal = combineLatest(regramPreferenceChanges(accountId: accountId), appearanceSignal) |> map { settings, _ -> InputDataSignalValue in
        var page = RegramPageBuilder(page: "groupProfile")
        page.section()
        for item in RegramGroupProfileSettingItem.allCases {
            page.row(item.rawValue, title: regramString("features.GroupProfileSettings.Item." + item.rawValue), type: .switchable(item.isVisible(settings: settings)), action: { RegramPreferences.shared.update(accountId: accountId) { settings in let visible = !item.isVisible(settings: settings); item.setVisible(visible, settings: &settings) } })
        }
        page.text(regramString("features.GroupProfileSettings.Footer"))
        return InputDataSignalValue(entries: page.entries)
    }
    let controller = RegramFormController(dataSignal: signal, title: regramString("features.GroupProfileSettings"), removeAfterDisappear: false, hasDone: false, identifier: "regram.groupProfile")
    regramFocusSettings(controller, page: "groupProfile", item: focusSetting)
    return controller
}

func regramAppearanceSettingsEntries(context: any AccountContextProtocol, settings: RegramAccountSettings, sectionId: inout Int32, index: inout Int32) -> [InputDataEntry] {
    let accountId = context.peerId.toInt64()
        var page = RegramPageBuilder(page: "appearance", sectionId: sectionId, index: index)
        if settings["canUseNY"].bool {
            page.section("Settings.NY.Header")
            let styles = ["default", "snow", "lightning"].map { style in
                ContextMenuItem(regramString("Settings.NY.Style." + style), handler: { RegramPreferences.shared.update(accountId: accountId) { $0["nyStyle"] = .string(style) } }, state: settings["nyStyle"].string == style ? .on : .off)
            }
            page.row("nyStyle", title: regramString("Settings.NY.Style"), type: .contextSelector(regramString("Settings.NY.Style." + settings["nyStyle"].string), styles))
            page.text(regramString("Settings.NY.Notice"))
        }
        page.section("Settings.Section.Interface")
        page.row("folderTags", title: regramString("Settings.FolderTags"), type: .next, action: { RegramUIHooks.shared.openNativeSettings(context, "folderTags") })
        page.row("bottomBarLayout", title: regramString("Settings.Tabs.Customize"), type: .next, action: { context.bindings.rootNavigation().push(RegramNavigationController(context: context)) })
        page.row("appIcon", title: regramString("Appearance.ChangeIcon"), type: .next, action: { RegramUIHooks.shared.openNativeSettings(context, "appIcon") })
        page.row("hideTabBarPermissionWarnings", title: regramString("features.HideTabBarPermissionWarnings"), type: .switchable(settings["features.hideTabBarPermissionWarnings"].bool), action: { RegramPreferences.shared.update(accountId: accountId) { $0["features.hideTabBarPermissionWarnings"] = .bool(!$0["features.hideTabBarPermissionWarnings"].bool) } })
        page.text(regramString("features.HideTabBarPermissionWarnings.Notice"))
    sectionId = page.nextSectionId
    index = page.nextIndex
    return page.entries
}

public func RegramAppearanceSettingsController(context: any AccountContextProtocol, focusSetting: String? = nil) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let signal = combineLatest(regramPreferenceChanges(accountId: accountId), appearanceSignal) |> map { settings, _ -> InputDataSignalValue in
        var section: Int32 = 0
        var index: Int32 = 0
        return InputDataSignalValue(entries: regramAppearanceSettingsEntries(context: context, settings: settings, sectionId: &section, index: &index))
    }
    let controller = RegramFormController(dataSignal: signal, title: regramString("Settings.Section.Interface"), removeAfterDisappear: false, hasDone: false, identifier: "regram.appearance")
    regramFocusSettings(controller, page: "appearance", item: focusSetting)
    return controller
}

public func RegramAppearanceCategoryController(context: any AccountContextProtocol, focusSetting: String? = nil, page: String? = nil) -> InputDataController {
    let accountId = context.peerId.toInt64()
    let signal = combineLatest(regramPreferenceChanges(accountId: accountId), appearanceSignal) |> map { settings, _ -> InputDataSignalValue in
        var section: Int32 = 0
        var index: Int32 = 0
        var entries: [InputDataEntry] = []
        entries += regramAppearanceSettingsEntries(context: context, settings: settings, sectionId: &section, index: &index)
        entries += regramProfilesSettingsEntries(context: context, settings: settings, sectionId: &section, index: &index)
        return InputDataSignalValue(entries: entries)
    }
    let controller = RegramFormController(dataSignal: signal, title: regramString("category.appearance"), removeAfterDisappear: false, hasDone: false, identifier: "regram.appearance.category")
    regramFocusSettings(controller, page: page, item: focusSetting)
    return controller
}
