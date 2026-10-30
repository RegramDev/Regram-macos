import Foundation

public struct RegramSettingsRoute: Equatable {
    public let page: String
    public let item: String?
    public var destination: String { page + (item.map { "/" + $0 } ?? "") }

    public static let pages: Set<String> = [
        "pro.home", "pro.messages", "pro.input", "pro.privacy", "pro.translation", "pro.media", "pro.appearance", "pro.notifications", "pro.network", "pro.tools",
        "settings.appearance", "settings.folders", "settings.chatList", "settings.profiles", "settings.stories", "settings.translation", "settings.messageActions", "settings.media", "settings.photos", "settings.stickers", "settings.recording", "settings.app",
        "settings.input", "settings.transfer", "settings.privacy",
        "inlineBots", "groupProfile", "startupFolder", "summary", "networkPolicy", "bottomBar", "llm", "stt", "updates", "linkPreview", "antiFeatures", "revokedMarker", "ghostMode", "backup", "diagnostics", "datacenters", "bookmarks", "chatPreferences", "messageFilter", "hiddenUsers", "antiRevokeChats", "revokedMessages", "localGifts", "contextMenu"
    ]
    public static func normalized(page: String, item: String? = nil) -> (page: String, item: String?)? {
        guard Self.pages.contains(page), item.map(Self.validItem) ?? true else { return nil }
        if item == "eraseAllData" { return nil }
        if ["disableDeleteChatSwipeOption", "mediaLoadingExperiment"].contains(item ?? "") { return nil }
        if ["appBages", "appBadges", "customAppBadge"].contains(item ?? "") { return nil }
        if ["inputToolbar", "textStyleMenu", "disableSwipeToRecordStory", "disableSnapDeletionEffect", "forceSystemSharing", "disableGalleryCameraPreview", "startTelescopeWithRearCam", "antiScreenshotNotification", "accountColorsSaturation", "videoPIPSwipeDirection", "features.videoPIPSwipeDirection", "disableScrollToNextChannel", "disableScrollToNextTopic", "appIcons"].contains(item ?? "") || (item?.hasPrefix("features.textStyleMenu.") ?? false) { return nil }
        if page == "bottomBar", ["hidden", "preview", "topSearch", "automaticWidth", "reset", "search", "bottomSearch", "searchMode"].contains(item ?? "") { return nil }
        if (page == "settings.appearance" && item == "liquidGlassTintPercent") || (page == "bottomBar" && item == "tint") { return ("bottomBar", nil) }
        if page == "settings.chatList", item == "disableChatSwipeOptions" { return (page, "chatListSwipeAction") }
        if page == "startupFolder" || (page == "settings.folders" && item == "rememberLastFolder") {
            return ("settings.folders", "startupFolder")
        }
        if page == "settings.messageActions", ["chatToolsEnabled", "chatSearchFieldAtBottom", "bottomUpChatSearchResults"].contains(item ?? "") { return nil }
        if ["disableCommunityChatGrouping", "openArchiveOnPull", "bottomUpGlobalSearchResults"].contains(item ?? "") { return nil }
        if page == "settings.messageActions", item == "autoInlineBotEnabled" { return ("inlineBots", "enabled") }
        if page == "settings.input", ["enablePanguOnEditing", "enablePanguOnReceiving"].contains(item ?? "") { return ("pro.input", item) }
        if page == "diagnostics", item == "datacenters" { return ("datacenters", "start") }
        if ["pro.privacy", "pro.tools"].contains(page), item == "localPremium" { return ("localGifts", item) }
        if ["pro.home", "pro.tools"].contains(page), item == "localGifts" { return ("localGifts", nil) }
        if page == "localGifts", ["catalog", "owned"].contains(item ?? "") { return (page, "balance") }
        let moves: [String: String] = [
            "pro.appearance:appIcon": "settings.appearance",
            "settings.privacy:hideTabBarPermissionWarnings": "settings.appearance", "settings.app:hideTabBarPermissionWarnings": "settings.appearance", "pro.notifications:hideTabBarPermissionWarnings": "settings.appearance",
            "pro.messages:mentionAsUserIdLink": "pro.input", "pro.messages:panguSpacing": "pro.input", "pro.messages:defaultOutgoingFormatting": "pro.input", "pro.messages:chatPreferences": "pro.input",
            "antiFeatures:revokedMarker": "revokedMarker",
            "pro.tools:diagnostics": "pro.network",
            "settings.messageActions:hideRecordingButton": "settings.input", "settings.messageActions:disableSendAsButton": "settings.input", "settings.messageActions:sendWithReturnKey": "settings.input",
            "settings.media:uploadSpeedBoost": "settings.transfer", "settings.media:downloadSpeedBoost": "settings.transfer", "settings.app:enableVoipTcp": "settings.transfer",
            "settings.media:disableGalleryCamera": "settings.recording",
            "settings.app:hideChannelBottomButton": "settings.messageActions", "settings.app:contentSettings": "settings.privacy", "settings.profiles:hidePhoneInSettings": "settings.privacy"
        ]
        return (item.flatMap { moves[page + ":" + $0] } ?? page, item)
    }
    private static func validItem(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 96 && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45,46,95].contains($0) }
    }

    public init?(page: String, item: String? = nil) {
        let normalizedPage: String
        if let category = RegramCategory(rawValue: page) {
            if let item { guard RegramSetting.byKey[item]?.category == category else { return nil } }
            normalizedPage = "pro." + category.rawValue
        } else { normalizedPage = page == "filters" ? "messageFilter" : page }
        guard let target = Self.normalized(page: normalizedPage, item: item),
              RegramSettingsScope.includesNotifications || target.page != "pro.notifications",
              RegramSettingsScope.includesUpdates || target.page != "updates" && !(target.page == "pro.tools" && target.item == "appUpdate") else { return nil }
        self.page = target.page
        self.item = target.item
    }

    public init?(url: URL, appSpecificScheme: String = "regram") {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.user == nil, components.password == nil, components.port == nil, components.fragment == nil else { return nil }
        let scheme = components.scheme?.lowercased() ?? "", host = components.host?.lowercased() ?? ""
        let aliases = ["rg", "regram"]
        let supported = scheme == "tg" || aliases.contains(scheme) || (scheme != "sg" && scheme == appSpecificScheme.lowercased())
        guard supported, (aliases.contains(host) && components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "settings") || (aliases.contains(scheme) && host == "settings" && components.path.isEmpty) else { return nil }
        let items = components.queryItems ?? []
        guard items.allSatisfy({ ["page", "item"].contains($0.name) && $0.value != nil }), Set(items.map(\.name)).count == items.count, let page = items.first(where: { $0.name == "page" })?.value else { return nil }
        self.init(page: page, item: items.first(where: { $0.name == "item" })?.value)
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = "tg"
        components.host = "rg"
        components.path = "/settings"
        components.queryItems = [URLQueryItem(name: "page", value: page)] + (item.map { [URLQueryItem(name: "item", value: $0)] } ?? [])
        return components.url!
    }
}
