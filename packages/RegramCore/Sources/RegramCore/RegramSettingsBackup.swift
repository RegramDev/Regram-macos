import Foundation

public enum RegramBackupCategory: String, Codable, CaseIterable {
    case appearance, messages, privacy, translation, media, notifications
    public var titleKey: String { "Backup.Category." + rawValue }
    public static var available: [RegramBackupCategory] { allCases.filter { $0 != .notifications || RegramSettingsScope.includesNotifications } }
}

public struct RegramSettingsBackup: Codable, Equatable {
    public enum Failure: Error { case tooLarge, unsupportedVersion, invalidValue(String) }
    public static let filename = "regram-settings.json"
    public static let maximumBytes = 2 * 1024 * 1024
    public let version: Int
    public let createdAt: Date
    public let values: [String: RegramValue]

    public init(values: [String: RegramValue], createdAt: Date = Date()) {
        version = 1
        self.createdAt = createdAt
        var normalized = values.filter { Self.category(for: $0.key) != nil }
        if case let .dictionary(stored)? = normalized[RegramBottomBarSettings.storageKey] {
            let layout = RegramBottomBarSettings(storedValues: stored)
            normalized[RegramBottomBarSettings.storageKey] = .dictionary(layout.storedValues)
            normalized["hideTabBar"] = .bool(!layout.isBottomBarVisible)
            normalized["showTabNames"] = .bool(layout.showLabels)
            normalized["tabBarWidthPercent"] = .integer(layout.automaticWidth ? 0 : Int64(max(50, min(100, layout.buttonWidthFillRatio))))
            normalized["native.showContactsTab"] = .bool(layout.isVisible(.contacts))
            normalized["native.showCallsTab"] = normalized["native.showCallsTab"] ?? .bool(layout.isVisible(.calls))
        }
        self.values = normalized
    }

    public init(settings: RegramAccountSettings, categories: Set<RegramBackupCategory> = Set(RegramBackupCategory.available), date: Date = Date()) {
        var values: [String: RegramValue] = [:]
        for category in categories where RegramBackupCategory.available.contains(category) {
            for key in Self.categoryKeys[category] ?? [] where RegramSetting.byKey[key] != nil { values[key] = settings[key] }
        }
        if categories.contains(.appearance) { values[RegramBottomBarSettings.storageKey] = .dictionary(RegramBottomBarSettings(settings: settings).storedValues) }
        self.init(values: values, createdAt: date)
    }

    public static let categoryKeys: [RegramBackupCategory: [String]] = [
        .appearance: ["features.hideTabBarPermissionWarnings", "bottomBarLayout", "showTabNames", "fontFamily", "fontChineseFamily", "fontImportedLatin", "fontImportedChinese", "fontApplyToMessages", "fontApplyToInterface", "rememberLastFolder", "hideReactions", "disableChatSwipeOptions", "hideTabBar", "hideChatListSeparators", "compactChatList", "chatListLines", "compactFolderNames", "allChatsTitleLengthOverride", "allChatsHidden", "wideChannelPosts", "secondsInMessages", "hideChannelBottomButton", "tabBarWidthPercent", "hideStories", "showRepostToStoryV2", "nyStyle", "stickerSize", "stickerTimestamp", "recentStickerLimit", "native.showContactsTab", "native.showCallsTab", "native.foldersAtBottom", "unlimitedPinnedChats", "recentChatsEnabled", "chooseFolderAfterJoining", "features.chatListFolderTabDisplayMode", "features.chatListSwipeAction", "features.communityAvatarTapAction", "features.groupProfileSettingItems", "features.hideFolderUnreadCount", "features.hideTopStories", "features.keepNewChatsVisibleAtTop", "features.showArchiveInFolders", "features.showFoldersInShareSheet", "features.chatListStartupFolderMode", "features.startupFolders", "features.stayAtLatestMessageAfterRefresh"],
        .messages: ["messageBookmarksEnabled", "messageSummaryEnabled", "contextShowSelectFromUser", "contextShowSaveToCloud", "contextShowRestrict", "contextShowHideForwardName", "contextShowReport", "contextShowReply", "contextShowPin", "contextShowSaveMedia", "contextShowMessageReplies", "contextShowJson", "contextShowRepeatForward", "contextShowRepeatCopy", "contextShowEditHistory", "contextMenuOrder", "contextMenuDisabledItems", "mentionAsUserIdLink", "disableLinkPreview", "fixLinkPreviews", "linkPreviewXHost", "linkPreviewInstagramHost", "defaultEmojisFirst", "messageDoubleTapActionOutgoing", "messageDoubleTapAction", "messageDoubleTapActionWithoutEditPermission", "showMessageId", "automaticallyRevealSpoilers", "showForwardedMessageDate", "forceEmojiTab", "panguSpacing", "defaultOutgoingFormatting", "sendWithReturnKey", "hideRecordingButton", "disableSendAsButton", "chatPreferences", "features.autoInlineBotEnabled", "features.tapMessageRowToOpenContextMenu", "features.confirmUnpin", "features.enablePanguOnEditing", "features.enablePanguOnReceiving"],
        .privacy: ["hidePhoneInSettings", "profileDefaultTabGroupsInCommon", "showDC", "showCreationDate", "showRegDate", "showProfileId", "confirmCalls", "messageFilterRules", "blockedPeerIds", "messageFilterDisabledPeerIds", "antiRevokePeerIds", "disableAllAds", "antiRevoke", "antiRevokeSkipBots", "revokedMarkerStyle", "revokedMarkerText", "revokedMarkerColor", "saveEditHistory", "antiAutoDelete", "antiSelfDestruct", "allowSavingProtectedContent", "allowDownloadingStories", "ghostDontReadStories", "ghostDontSendOnline", "ghostDontSendTyping", "storyStealthMode", "warnOnStoriesOpen", "features.hideSavedAndArchivedMessagesInList", "features.hidePrivateChatActivities", "features.disableChatAvatarStories"],
        .translation: ["sttBaseURL", "sttEndpoint", "sttModel", "sttLanguage", "sttPrompt", "summaryLLMAPIFormat", "summaryLLMBaseURL", "summaryLLMEndpoint", "summaryLLMModel", "summaryLLMPrompt", "summaryLLMTemperatureTenths", "translationLLMAPIFormat", "translationLLMBaseURL", "translationLLMEndpoint", "translationLLMModel", "translationLLMPrompt", "translationLLMUseContext", "translationLLMTemperatureTenths", "quickTranslateButton", "translationBackend", "transcriptionBackend", "outgoingLanguageTranslation"],
        .media: ["clipboardOriginalImages", "forceBuiltInMic", "uploadSpeedBoost", "downloadSpeedBoost", "showMediaMetadata", "defaultVideoQuality", "customDoHEnabled", "customDoHEndpoint", "ipVersionPolicy", "disableBackupAddresses", "localDNSForProxyHost", "sendLargePhotos", "outgoingPhotoQuality", "disableGalleryCamera", "native.enableVoipTcp"],
        .notifications: ["pinnedMessageNotifications", "mentionsAndRepliesNotifications", "pinnedMessageNotificationsExceptions", "mentionsAndRepliesNotificationsExceptions", "filterNotifications"]
    ]

    private static let categoriesByKey = Dictionary(RegramBackupCategory.allCases.flatMap { category in (categoryKeys[category] ?? []).map { ($0, category) } }, uniquingKeysWith: { first, _ in first })
    public static func category(for key: String) -> RegramBackupCategory? { categoriesByKey[key] }

    public func selectedValues(categories: Set<RegramBackupCategory>) -> [String: RegramValue] {
        values.filter { Self.category(for: $0.key).map { categories.contains($0) && RegramBackupCategory.available.contains($0) } == true }
    }

    public static func read(from url: URL) throws -> RegramSettingsBackup {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= maximumBytes else { throw Failure.tooLarge }
        return try decode(Data(contentsOf: url, options: .mappedIfSafe))
    }

    public static func decode(_ data: Data) throws -> RegramSettingsBackup {
        guard data.count <= maximumBytes else { throw Failure.tooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(Self.self, from: data)
        guard result.version == 1 else { throw Failure.unsupportedVersion }
        for (key, value) in result.values where category(for: key) != nil {
            guard isValid(value, key: key) else { throw Failure.invalidValue(key) }
        }
        return RegramSettingsBackup(values: result.values, createdAt: result.createdAt)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw Failure.tooLarge }
        return data
    }

    public var skippedKeys: [String] { values.keys.filter { key in Self.category(for: key).map { !RegramBackupCategory.available.contains($0) } ?? true }.sorted() }

    public func applying(to settings: RegramAccountSettings, categories: Set<RegramBackupCategory> = Set(RegramBackupCategory.available), resetCategories: Set<RegramBackupCategory> = []) -> RegramAccountSettings {
        var result = settings
        let reset = resetCategories.intersection(Set(RegramBackupCategory.available))
        for key in reset.flatMap({ Self.categoryKeys[$0] ?? [] }) { result.values.removeValue(forKey: key) }
        if reset.contains(.media) { result.values.removeValue(forKey: "enableVoipTcp") }
        var selected = selectedValues(categories: categories)
        if selected[RegramBottomBarSettings.storageKey] == nil, ["showTabNames", "hideTabBar", "tabBarWidthPercent", "native.showContactsTab", "native.showCallsTab"].contains(where: { selected[$0] != nil }) {
            var layout = RegramBottomBarSettings(settings: result)
            if case let .bool(value)? = selected["showTabNames"] { layout.showLabels = value }
            if case let .bool(value)? = selected["hideTabBar"] { layout.isBottomBarVisible = !value }
            if case let .integer(value)? = selected["tabBarWidthPercent"] { layout.automaticWidth = value == 0; layout.buttonWidthFillRatio = Int32(clamping: max(50, min(100, value))) }
            if case let .bool(value)? = selected["native.showContactsTab"] { layout.setVisible(.contacts, visible: value) }
            if case let .bool(value)? = selected["native.showCallsTab"] { layout.setVisible(.calls, visible: value) }
            selected[RegramBottomBarSettings.storageKey] = .dictionary(layout.storedValues)
        }
        selected = Self(values: selected).values
        if selected["features.chatListStartupFolderMode"] == nil, case let .bool(value)? = selected["rememberLastFolder"] { selected["features.chatListStartupFolderMode"] = .string(value ? "last" : "telegram") }
        for (key, value) in selected where Self.isValid(value, key: key) {
            if key == "translationBackend", value == .string("gtranslate") { result.values[key] = .string("google") }
            else if key == "downloadSpeedBoost", value == .string("maximum") { result.values[key] = .string("medium") }
            else if key == "chatListLines", !["1", "2"].contains(value.string) { result.values[key] = .string("2") }
            else { result.values[key] = value }
            if key == "native.enableVoipTcp" { result.values["enableVoipTcp"] = value }
        }
        return result
    }

    private static func validFontSelection(_ id: String) -> Bool {
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2, parts[0].count == 64, parts[0].allSatisfy({ $0.isHexDigit }) else { return false }
        if parts.count == 2 { guard let index = Int(parts[1]), index > 0, String(index) == parts[1] else { return false } }
        return true
    }

    private static func isValid(_ value: RegramValue, key: String) -> Bool {
        switch key {
        case "features.chatListStartupFolderMode":
            if case let .string(v) = value { return ["telegram", "last", "specific"].contains(v) }; return false
        case "features.chatListSwipeAction":
            if case let .string(v) = value { return RegramChatListSwipeAction(rawValue: v) != nil }; return false
        case "features.chatListFolderTabDisplayMode":
            if case let .string(v) = value { return ["text", "icon", "both"].contains(v) }; return false
        case "features.communityAvatarTapAction":
            if case let .string(v) = value { return ["chat", "community", "arrow"].contains(v) }; return false
        case "features.groupProfileSettingItems":
            if case let .string(v) = value {
                return v.isEmpty || (v.utf8.count <= 2048 && v.split(separator: ",", omittingEmptySubsequences: false).allSatisfy { RegramGroupProfileSettingItem(rawValue: String($0)) != nil })
            }; return false
        case "features.startupFolders":
            if case let .dictionary(v) = value {
                return v.count <= 10000 && v.allSatisfy { entry in
                    Int64(entry.key) != nil && Int32(entry.value).map { $0 >= -1 } == true
                }
            }; return false
        case "revokedMarkerStyle": if case let .string(v) = value { return RegramRevokedMarker.Style(rawValue: v) != nil }; return false
        case "revokedMarkerText": if case let .string(v) = value { return v.utf8.count <= 384 && v == RegramRevokedMarker.normalizedText(v) }; return false
        case "revokedMarkerColor": if case let .string(v) = value { return v.isEmpty || RegramRevokedMarker.rgb(v) != nil }; return false
        case "outgoingPhotoQuality":
            if case let .integer(v) = value { return (0...100).contains(v) }; return false
        case "ipVersionPolicy": if case let .integer(v) = value { return [0, 1, 2, 4, 6].contains(v) }; return false
        case "customDoHEndpoint": if case let .string(v) = value { return v.isEmpty || RegramNetworkPolicy.validEndpoint(v) }; return false
        case "summaryLLMTemperatureTenths", "translationLLMTemperatureTenths": if case let .integer(v) = value { return (0...10).contains(v) }; return false
        case "sttPrompt": if case let .string(v) = value { return v.utf8.count <= 16000 }; return false
        case "sttBaseURL", "sttEndpoint", "sttModel": if case let .string(v) = value { return v.utf8.count <= 2048 }; return false
        case "linkPreviewXHost", "linkPreviewInstagramHost": if case let .string(v) = value { return RGLinkPreviewRules.isValidHost(v) }; return false
        case "summaryLLMPrompt", "translationLLMPrompt": if case let .string(v) = value { return v.utf8.count <= 16000 }; return false
        case "summaryLLMAPIFormat", "translationLLMAPIFormat": if case let .string(v) = value { return v == "openai" || v == "anthropic" }; return false
        case "summaryLLMBaseURL", "summaryLLMEndpoint", "summaryLLMModel", "translationLLMBaseURL", "translationLLMEndpoint", "translationLLMModel": if case let .string(v) = value { return v.utf8.count <= 2048 }; return false
        case "stickerSize": if case let .integer(v) = value { return (0...200).contains(v) }; return false
        case "recentStickerLimit": if case let .integer(v) = value { return (1...1000).contains(v) }; return false
        case "bottomBarLayout":
            if case let .dictionary(v) = value { return v.count <= 13 && v.allSatisfy { $0.key.count < 32 && $0.value.count < 128 } }; return false
        case "tabBarWidthPercent": if case let .integer(v) = value { return v == 0 || (50...100).contains(v) }; return false
        case "contextMenuOrder", "contextMenuDisabledItems", "blockedPeerIds", "messageFilterDisabledPeerIds", "antiRevokePeerIds":
            if case let .strings(v) = value { return v.count <= 10000 && v.allSatisfy { $0.utf8.count <= 128 } }; return false
        case "outgoingLanguageTranslation", "pinnedMessageNotificationsExceptions", "mentionsAndRepliesNotificationsExceptions":
            if case let .dictionary(v) = value { return v.count <= 10000 && v.allSatisfy { $0.key.utf8.count <= 128 && $0.value.utf8.count <= 128 } }; return false
        case "messageFilterRules":
            if case let .string(v) = value { return (try? JSONDecoder().decode([RGMessageFilterRule].self, from: Data(v.utf8))) != nil }; return false
        case "chatPreferences":
            if case let .string(v) = value { return (try? JSONDecoder().decode([String: RGChatPreferences].self, from: Data(v.utf8))) != nil }; return false
        case "fontImportedLatin", "fontImportedChinese":
            if case let .string(v) = value { return v.isEmpty || validFontSelection(v) }; return false
        case "sttLanguage", "fontFamily", "fontChineseFamily", "downloadSpeedBoost", "defaultVideoQuality", "defaultOutgoingFormatting", "chatListLines", "allChatsTitleLengthOverride", "messageDoubleTapActionOutgoing", "messageDoubleTapAction", "messageDoubleTapActionWithoutEditPermission","translationBackend", "transcriptionBackend", "nyStyle", "pinnedMessageNotifications", "mentionsAndRepliesNotifications":
            if case let .string(v) = value { return v.utf8.count <= 256 }; return false
        default: if case .bool = value { return true }; return false
        }
    }
}
