import Foundation

public enum RegramSettingsScope {
    public static let includesNotifications = false
    public static let includesUpdates = true
}

public struct RegramSettingsSearchQuery {
    private let tokens: [String]
    private let locale: Locale
    public init(_ query: String, language: String) {
        locale = Locale(identifier: language)
        tokens = query.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
    public var isEmpty: Bool { tokens.isEmpty }
    public func matches(_ text: String) -> Bool {
        guard !isEmpty else { return false }
        let text = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
        return tokens.allSatisfy { text.contains($0) }
    }
}

public struct RegramSettingsCatalogEntry {
    public let page: String
    public let key: String
    public let titleKey: String
    public let keywords: String
    public var category: RegramCategory { RegramSettingsCatalog.category(for: page) }
    public var sourceIdentifier: String { page + ":" + key }
    public var destination: String { page + (key.isEmpty ? "" : "/" + key) }
    public var stableId: Int32 {
        let hash = sourceIdentifier.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }
        return Int32((hash & 0x3fffffff) | 0x40000000)
    }
    public init(_ page: String, _ item: String, _ titleKey: String, keywords: String = "") {
        let target = RegramSettingsRoute.normalized(page: page, item: item)
        self.page = target?.page ?? page; self.key = target.map { $0.item ?? "" } ?? item; self.titleKey = titleKey; self.keywords = keywords
    }
    public init(key: String, category: RegramCategory, titleKey: String? = nil, destination: String? = nil) {
        page = destination ?? ("pro." + category.rawValue)
        self.key = key; self.titleKey = titleKey ?? ("setting." + key); keywords = ""
    }
    public func title(language: String) -> String { regramLocalizedString(titleKey, languageCode: language) }
    public var pageTitleKey: String {
        if page.hasPrefix("pro.") { return "Settings.ProCategory." + page.dropFirst(4) }
        if page.hasPrefix("settings.") { return "Settings.ProCategory." + category.rawValue }
        return ["inlineBots": "features.InlineBots.Title", "groupProfile": "features.GroupProfileSettings", "startupFolder": "features.ChatListStartupFolder", "networkPolicy": "NetworkPolicy.Title", "bottomBar": "RG.BottomBarLayout", "llm": "LLMTranslation.Title", "stt": "RG.STTSettings", "updates": "AppUpdate.Title", "linkPreview": "LinkPreview.Repair", "antiFeatures": "AntiFeatures.Header", "revokedMarker": "RevokedMarker.Title", "ghostMode": "Ghost.Header", "backup": "Backup.Title", "diagnostics": "Diagnostics.Title", "datacenters": "Diagnostics.DC.Title", "bookmarks": "Bookmarks.Title", "chatPreferences": "ChatPreferences.Title", "localGifts": "Showroom.Title"][page] ?? "Settings.Pro.Title"
    }
    public func alternate(language: String) -> [String] {
        let pageContext = ["llm": "LLM OpenAI Anthropic 大模型", "stt": "STT ASR OpenAI Whisper 自定义识别 自訂辨識"]
        let aliases = (RegramSettingsCatalog.aliases[key] ?? []) + [pageContext[page] ?? ""]
        return ["Regram Pro", title(language: language), title(language: "en"), regramLocalizedString(pageTitleKey, languageCode: language), regramLocalizedString(pageTitleKey, languageCode: "en"), keywords, key] + aliases.map { $0.contains(".") ? regramLocalizedString($0, languageCode: language) : $0 }
    }
    public func matches(_ query: RegramSettingsSearchQuery, language: String) -> Bool { query.matches(alternate(language: language).joined(separator: " ")) }
}

public enum RegramSettingsCatalog {
    public static func category(for page: String) -> RegramCategory {
        if page.hasPrefix("pro."), let value = RegramCategory(rawValue: String(page.dropFirst(4))) { return value }
        let value = page.hasPrefix("settings.") ? String(page.dropFirst(9)) : page
        if ["messageActions", "chatList", "folders", "bookmarks", "startupFolder"].contains(value) { return .messages }
        if ["input", "inlineBots"].contains(value) { return .input }
        if ["translation", "llm", "stt"].contains(value) { return .translation }
        if ["privacy", "stories", "app", "antiFeatures", "revokedMarker", "ghostMode", "hiddenUsers", "antiRevokeChats", "revokedMessages"].contains(value) { return .privacy }
        if ["media", "photos", "stickers", "recording", "linkPreview"].contains(value) { return .media }
        if ["appearance", "profiles", "groupProfile", "bottomBar"].contains(value) { return .appearance }
        if ["network", "transfer", "networkPolicy", "diagnostics", "datacenters"].contains(value) { return .network }
        return .tools
    }
    public static var entries: [RegramSettingsCatalogEntry] {
        sourceEntries.filter {
            (RegramSettingsScope.includesNotifications || $0.category != .notifications) && (RegramSettingsScope.includesUpdates || $0.page != "updates" && !($0.page == "pro.tools" && $0.key == "appUpdate"))
        }
    }
    public static func results(query: String, language: String) -> [RegramSettingsCatalogEntry] {
        let query = RegramSettingsSearchQuery(query, language: language)
        return query.isEmpty ? [] : entries.filter { $0.matches(query, language: language) }
    }
    public static let sourceEntries: [RegramSettingsCatalogEntry] = [
        .init("inlineBots", "enabled", "features.AutoInlineBot.Enabled", keywords: "inline bot 自动查询 机器人"),
        .init("settings.messageActions", "inlineBotRules", "features.InlineBots.Title", keywords: "bot Twitter Pixiv Music163 rules 机器人 規則 规则"),
        .init("settings.folders", "showFoldersInShareSheet", "features.ShowFoldersInShareSheet"),
        .init("settings.messageActions", "confirmUnpin", "features.ConfirmUnpin"),
        .init("settings.chatList", "hideSavedAndArchivedMessagesInList", "features.HideSavedAndArchivedMessagesInList"),
        .init("settings.chatList", "hidePrivateChatActivities", "features.HidePrivateChatActivities", keywords: "隐藏私聊活动状态 隱藏私聊活動狀態 incoming typing recording 对方 正在输入 錄音"),
        .init("settings.folders", "hideFolderUnreadCount", "features.HideFolderUnreadCount"),
        .init("settings.folders", "showArchiveInFolders", "features.ShowArchiveInFolders"),
        .init("settings.messageActions", "stayAtLatestMessageAfterRefresh", "features.StayAtLatestMessageAfterRefresh"),
        .init("pro.input", "enablePanguOnEditing", "features.PanguOnEditing"),
        .init("pro.input", "enablePanguOnReceiving", "features.PanguOnReceiving"),
        .init("settings.stories", "hideTopStories", "features.HideTopStories"),
        .init("settings.stories", "disableChatAvatarStories", "features.DisableChatAvatarStories"),
        .init("settings.chatList", "keepNewChatsVisibleAtTop", "features.KeepNewChatsVisibleAtTop"),
        .init("settings.chatList", "chatListSwipeAction", "features.ChatListSwipeAction"),
        .init("settings.chatList", "communityAvatarTapAction", "features.CommunityAvatarTapAction"),
        .init("settings.profiles", "groupProfileSettings", "features.GroupProfileSettings"),
        .init("settings.folders", "startupFolder", "features.ChatListStartupFolder", keywords: "remember last specific folder 记住上次分组 指定分组 記住上次分組 指定分組"),
        .init("groupProfile", "groupType", "features.GroupProfileSettings.Item.groupType"),
        .init("groupProfile", "inviteLinks", "features.GroupProfileSettings.Item.inviteLinks"),
        .init("groupProfile", "linkedChannel", "features.GroupProfileSettings.Item.linkedChannel"),
        .init("groupProfile", "reactions", "features.GroupProfileSettings.Item.reactions"),
        .init("groupProfile", "appearance", "features.GroupProfileSettings.Item.appearance"),
        .init("groupProfile", "history", "features.GroupProfileSettings.Item.history"),
        .init("groupProfile", "topics", "features.GroupProfileSettings.Item.topics"),
        .init("groupProfile", "location", "features.GroupProfileSettings.Item.location"),
        .init("groupProfile", "members", "features.GroupProfileSettings.Item.members"),
        .init("groupProfile", "permissions", "features.GroupProfileSettings.Item.permissions"),
        .init("groupProfile", "admins", "features.GroupProfileSettings.Item.admins"),
        .init("groupProfile", "memberRequests", "features.GroupProfileSettings.Item.memberRequests"),
        .init("groupProfile", "removedUsers", "features.GroupProfileSettings.Item.removedUsers"),
        .init("groupProfile", "recentActions", "features.GroupProfileSettings.Item.recentActions"),
        .init("groupProfile", "community", "features.GroupProfileSettings.Item.community"),
        .init("groupProfile", "deleteGroup", "features.GroupProfileSettings.Item.deleteGroup"),
        .init("groupProfile", "other", "features.GroupProfileSettings.Item.other"),
        .init("settings.appearance", "folderTags", "Settings.FolderTags", keywords: "folder tags 标签视图 標籤視圖"),
        .init("settings.appearance", "nyStyleSnow", "Settings.NY.Style.snow"),
        .init("settings.appearance", "nyStyleLightning", "Settings.NY.Style.lightning"),
        .init("settings.appearance", "nyStyle", "Settings.NY.Style"),
        .init("settings.appearance", "bottomBarLayout", "Settings.Tabs.Customize"),
        .init("settings.folders", "foldersAtBottom", "Settings.Folders.BottomTab"),
        .init("settings.folders", "allChatsHidden", "Settings.Folders.AllChatsHidden"),
        .init("settings.folders", "compactFolderNames", "Settings.Folders.CompactNames"),
        .init("settings.folders", "chooseFolderAfterJoining", "JoinFolder.Setting"),
        .init("settings.chatList", "compactChatList", "Settings.CompactChatList"),
        .init("settings.chatList", "chatListLines", "Settings.ChatList.Lines"),
        .init("settings.chatList", "hideChatListSeparators", "Settings.ChatList.HideSeparators"),
        .init("settings.chatList", "unlimitedPinnedChats", "Settings.UnlimitedPinnedChats"),
        .init("settings.profiles", "showProfileId", "Settings.ShowProfileID"),
        .init("settings.profiles", "showDC", "Settings.ShowDC"),
        .init("settings.profiles", "showRegDate", "Settings.ShowRegDate"),
        .init("settings.profiles", "showCreationDate", "Settings.ShowCreationDate"),
        .init("settings.profiles", "profileDefaultTabGroupsInCommon", "Settings.Profiles.DefaultTabGroupsInCommon"),
        .init("settings.profiles", "confirmCalls", "Settings.CallConfirmation"),
        .init("settings.stories", "hideStories", "Settings.Stories.Hide"),
        .init("settings.stories", "warnOnStoriesOpen", "Settings.Stories.WarnBeforeView"),
        .init("settings.stories", "showRepostToStory", "Catalog.RepostToStory"),
        .init("settings.stories", "storyStealthMode", "Catalog.StoryStealth"),
        .init("settings.translation", "translationBackend", "Settings.Translation.Backend"),
        .init("settings.translation", "llmTranslationSettings", "LLMTranslation.Title"),
        .init("settings.translation", "quickTranslateButton", "Settings.Translation.QuickTranslateButton"),
        .init("settings.translation", "languageSettings", "Catalog.ChatTranslation"),
        .init("settings.recording", "forceBuiltInMic", "Settings.forceBuiltInMic"),
        .init("settings.app", "enableVoipTcp", "Settings.Calls.ForceTCP"),
        .init("settings.photos", "outgoingPhotoQuality", "Catalog.PhotoQuality"),
        .init("settings.photos", "sendLargePhotos", "Settings.Photo.SendLarge"),
        .init("settings.photos", "clipboardOriginalImages", "Media.ClipboardOriginalImages"),
        .init("settings.stickers", "stickerSize", "Catalog.StickerSize"),
        .init("settings.stickers", "stickerTimestamp", "Settings.Stickers.Timestamp"),
        .init("settings.stickers", "recentStickerLimit", "Settings.Stickers.RecentLimit"),
        .init("settings.messageActions", "messageDoubleTapAction", "DoubleTap.Action", keywords: "double click double tap 双击 双擊 雙擊 按兩下 點兩下"),
        .init("settings.messageActions", "messageDoubleTapActionWithoutEditPermission", "setting.messageDoubleTapActionWithoutEditPermission", keywords: "double click double tap edit unavailable 双击 不可编辑 雙擊 無法編輯 按兩下 點兩下"),
        .init("settings.messageActions", "contextMenuOrder", "Settings.ContextMenu.Customize"),
        .init("settings.app", "hideChannelBottomButton", "Settings.showChannelBottomButton"),
        .init("settings.appearance", "wideChannelPosts", "Settings.wideChannelPosts"),
        .init("settings.messageActions", "secondsInMessages", "Settings.secondsInMessages"),
        .init("settings.messageActions", "showMessageId", "Settings.ShowMessageId"),
        .init("settings.messageActions", "messageBookmarksEnabled", "Bookmarks.Title", keywords: "message bookmarks bookmark tags labels enable toggle 书签 标签 开关 启用 書籤 標籤 開關 啟用"),
        .init("settings.messageActions", "automaticallyRevealSpoilers", "Settings.AutomaticallyRevealSpoilers", keywords: "spoiler 剧透 劇透 reveal"),
        .init("settings.messageActions", "showForwardedMessageDate", "Settings.ShowForwardedMessageDate"),
        .init("settings.messageActions", "hideRecordingButton", "Settings.RecordingButton"),
        .init("settings.messageActions", "disableSendAsButton", "Settings.SendAsButton"),
        .init("settings.media", "disableGalleryCamera", "Settings.GalleryCamera"),
        .init("settings.messageActions", "hideReactions", "Settings.HideReactions"),
        .init("settings.media", "uploadSpeedBoost", "Settings.UploadsBoost"),
        .init("settings.media", "downloadSpeedBoost", "Settings.DownloadsBoost"),
        .init("settings.media", "defaultVideoQuality", "Settings.DefaultVideoQuality"),
        .init("settings.media", "showMediaMetadata", "MediaMetadata.Setting"),
        .init("settings.messageActions", "sendWithReturnKey", "Settings.SendWithReturnKey"),
        .init("settings.stickers", "forceEmojiTab", "Settings.ForceEmojiTab"),
        .init("settings.stickers", "defaultEmojisFirst", "Settings.DefaultEmojisFirst"),
        .init("settings.profiles", "hidePhoneInSettings", "Settings.HidePhoneInSettingsUI"),
        .init("pro.privacy", "messageFilter", "MessageFilter.Title"),
        .init("pro.privacy", "hiddenUsers", "HiddenUsers.Title"),
        .init("pro.messages", "mentionAsUserIdLink", "Mention.UserIdLink"),
        .init("pro.privacy", "localPremium", "LocalPremium.Title"),
        .init("pro.home", "localGifts", "Showroom.Title"),
        .init("localGifts", "phone", "LocalPhone.Title"),
        .init("localGifts", "rating", "LocalRating.Title"),
        .init("localGifts", "enabled", "LocalGifts.Enabled"),
        .init("localGifts", "balance", "LocalGifts.Balance"),
        .init("localGifts", "tonBalance", "LocalGifts.TonBalance"),
        .init("localGifts", "walletCard", "LocalWallet.Enabled"),
        .init("pro.media", "disableLinkPreview", "LinkPreview.Disable"),
        .init("pro.input", "panguSpacing", "features.PanguOnSending", keywords: "pangu 盘古之白 盤古之白"),
        .init("pro.messages", "defaultOutgoingFormatting", "OutgoingFormatting.Title"),
        .init("pro.messages", "chatPreferences", "ChatPreferences.Title"),
        .init("pro.privacy", "antiFeatures", "AntiFeatures.Header"),
        .init("pro.privacy", "antiRevokeChats", "AntiRevoke.Chats.Title"),
        .init("pro.privacy", "revokedMessages", "Revoked.Title"),
        .init("pro.privacy", "ghostMode", "Ghost.Header"),
        .init("pro.notifications", "pinnedMessageNotifications", "Notifications.PinnedMessages.Title"),
        .init("pro.notifications", "mentionsAndRepliesNotifications", "Notifications.MentionsAndReplies.Title"),
        .init("pro.notifications", "filterNotifications", "Notifications.ContentFilter"),
        .init("settings.appearance", "hideTabBarPermissionWarnings", "features.HideTabBarPermissionWarnings", keywords: "notifications permissions exclamation warning badge 通知 权限 感叹号 角标 通知 權限 驚嘆號"),
        .init("settings.appearance", "appIcon", "Appearance.ChangeIcon"),
        .init("pro.tools", "backup", "Backup.Title"),
        .init("pro.tools", "diagnostics", "Diagnostics.Title"),
        .init("pro.tools", "eraseAllData", "EraseData.Title"),
        .init("pro.input", "inputSettings", "Settings.Category.input"),
        .init("pro.network", "transferSettings", "Settings.Category.transfer"),
        .init("pro.messages", "messageActionsSettings", "Settings.Category.messageActions"),
        .init("pro.messages", "chatListSettings", "Settings.Category.chatList"),
        .init("pro.messages", "folderSettings", "Settings.Category.folders"),
        .init("pro.translation", "translationSettings", "Settings.Category.translation"),
        .init("pro.translation", "transcriptionSettings", "Settings.Category.transcription"),
        .init("pro.media", "linkPreviewSettings", "LinkPreview.Repair"),
        .init("pro.media", "photoSettings", "Settings.Category.photos"),
        .init("pro.media", "stickerSettings", "Settings.Category.stickers"),
        .init("pro.media", "recordingSettings", "Settings.Category.recording"),
        .init("pro.media", "mediaSettings", "Settings.Category.media"),
        .init("pro.appearance", "appearanceSettings", "Settings.Category.appearance"),
        .init("pro.appearance", "profileSettings", "Settings.Category.profiles"),
        .init("pro.privacy", "storiesSettings", "Settings.Category.stories"),
        .init("pro.privacy", "privacySettings", "Settings.Category.privacy"),
        .init("pro.tools", "appUpdate", "AppUpdate.Title"),
        .init("antiFeatures", "antiRevoke", "AntiFeatures.Revoke"),
        .init("antiFeatures", "revokedMarker", "RevokedMarker.Title"),
        .init("revokedMarker", "style", "RevokedMarker.Style"),
        .init("revokedMarker", "text", "RevokedMarker.Text"),
        .init("revokedMarker", "color", "RevokedMarker.Color"),
        .init("revokedMarker", "apply", "NetworkPolicy.Apply"),
        .init("antiFeatures", "saveEditHistory", "AntiFeatures.EditHistory"),
        .init("antiFeatures", "antiAutoDelete", "AntiFeatures.AutoDelete"),
        .init("antiFeatures", "antiSelfDestruct", "AntiFeatures.SelfDestruct"),
        .init("antiFeatures", "allowSavingProtectedContent", "AntiFeatures.SaveProtected"),
        .init("antiFeatures", "allowDownloadingStories", "AntiFeatures.SaveProtectedStories"),
        .init("antiFeatures", "disableAllAds", "AntiFeatures.DisableAds"),
        .init("ghostMode", "ghostDontReadStories", "Ghost.DontReadStories"),
        .init("ghostMode", "ghostDontSendOnline", "Ghost.DontSendOnline"),
        .init("ghostMode", "ghostDontSendTyping", "Ghost.DontSendTyping"),
        .init("pro.network", "networkPolicy", "NetworkPolicy.Title", keywords: "DNS DoH IP IPv4 IPv6"),
        .init("networkPolicy", "enabled", "NetworkPolicy.DNSMode", keywords: "DoH DNS 系统 内置 Google Cloudflare IPv4 IPv6"),
        .init("networkPolicy", "endpoint", "NetworkPolicy.Endpoint"),
        .init("networkPolicy", "ipVersion", "NetworkPolicy.IP"),
        .init("networkPolicy", "disableBackup", "NetworkPolicy.DisableBackup"),
        .init("networkPolicy", "test", "DNSDiagnostics.Title"),
        .init("networkPolicy", "apply", "NetworkPolicy.Apply"),
        .init("llm", "format", "LLMTranslation.Format"),
        .init("llm", "baseURL", "LLMTranslation.BaseURL"),
        .init("llm", "apiKey", "LLMTranslation.APIKey"),
        .init("llm", "model", "LLMTranslation.Model"),
        .init("llm", "fetchModels", "LLMTranslation.FetchModels"),
        .init("llm", "testModel", "LLMTranslation.TestModel"),
        .init("llm", "prompt", "LLMTranslation.Prompt"),
        .init("llm", "useContext", "LLMTranslation.UseContext"),
        .init("llm", "temperature", "LLMTranslation.Temperature"),
        .init("stt", "provider", "Settings.Transcription.Backend"),
        .init("stt", "baseURL", "RG.STTBaseURL"),
        .init("stt", "endpoint", "RG.STTEndpoint"),
        .init("stt", "apiKey", "RG.STTAPIKey"),
        .init("stt", "model", "RG.STTModel"),
        .init("stt", "language", "RG.STTLanguage"),
        .init("stt", "prompt", "RG.STTPrompt"),
        .init("stt", "test", "RG.STTTest"),
        .init("updates", "check", "AppUpdate.Check"),
        .init("updates", "github", "AppUpdate.OpenGitHub"),
        .init("updates", "automaticCheck", "AppUpdate.AutomaticCheck"),
        .init("updates", "automaticDownload", "AppUpdate.AutomaticDownload"),
        .init("updates", "installOnQuit", "AppUpdate.InstallOnQuit"),
        .init("updates", "install", "AppUpdate.Install"),
        .init("bottomBar", "contacts", "RG.BottomBarLayout.Item.contacts", keywords: "bottom tabs contacts hide 底栏 联系人 隐藏 底欄 聯絡人 隱藏"),
        .init("bottomBar", "calls", "RG.BottomBarLayout.Item.calls", keywords: "show calls tab panel 显示呼叫面板 顯示呼叫面板"),
        .init("bottomBar", "labels", "RG.BottomBarLayout.ShowLabels", keywords: "bottom tabs text label 底栏 文字 标签 底欄 文字 標籤"),
        .init("bottomBar", "width", "RG.BottomBarLayout.Width", keywords: "bottom tabs width size 底栏 宽度 底欄 寬度"),
        .init("linkPreview", "xHost", "LinkPreview.XService"),
        .init("linkPreview", "instagramHost", "LinkPreview.InstagramService"),
        .init("linkPreview", "enabled", "LinkPreview.Repair"),
        .init("linkPreview", "reset", "Common.Reset"),
        .init("backup", "export", "Backup.Export"),
        .init("backup", "import", "Backup.Import"),
        .init("backup", "reset", "Backup.Reset"),
        .init("datacenters", "start", "Diagnostics.DC.Title", keywords: "DC1 DC2 DC3 DC4 DC5 ping 数据中心 平均 延迟"),
        .init("datacenters", "copy", "Diagnostics.CopyAverages"),
        .init("diagnostics", "transfer", "Diagnostics.Download"),
        .init("diagnostics", "filter", "Diagnostics.Filter"),
        .init("chatPreferences", "selectChat", "ChatPreferences.SelectChat"),
        .init("chatPreferences", "formatting", "OutgoingFormatting.Title"),
        .init("chatPreferences", "panguSpacing", "Pangu.Title"),
        .init("chatPreferences", "reset", "ChatPreferences.Reset"),
    ]

    static let aliases: [String: [String]] = [
        "sttSettings": ["RG.STTSettings", "speech transcription whisper openai model voice audio round video 语音 转写 识别 圆视频 模型 密钥 音频 語音 辨識"],
        "transcriptionSettings": ["Settings.Category.transcription", "Settings.Transcription.Backend", "speech voice telegram apple 语音 转写 识别"],
        "translationSettings": ["Settings.Category.translation", "translation google microsoft yandex transmart llm 翻译"],
        "llmSettings": ["LLMTranslation.Title", "LLMTranslation.Model", "openai anthropic prompt temperature context 大模型 提示词 温度 上下文"],
        "linkPreviewSettings": ["LinkPreview.Repair", "preview x twitter instagram reddit pixiv tiktok 链接 预览 修复 连结 連結"],
        "messageActionsSettings": ["Settings.Category.messageActions", "DoubleTap.Action", "Settings.ShowMessageId", "Settings.ShowForwardedMessageDate", "menu double tap id forwarded 消息 菜单 双击 时间 转发"],
        "chatListSettings": ["Settings.Category.chatList", "Settings.UnlimitedPinnedChats", "chat list pinned swipe 聊天 列表 无限 置顶 侧滑"],
        "folderSettings": ["Settings.Category.folders", "JoinFolder.Setting", "folders join 分组 加入"],
        "profileSettings": ["Settings.Category.profiles", "profile id registration phone 资料 注册 手机号"],
        "storiesSettings": ["Settings.Category.stories", "stories stealth 动态 快拍"],
        "appearanceSettings": ["Settings.Category.appearance", "appearance tabs bar saturation 外观 界面 底栏 颜色"],
        "mediaSettings": ["Settings.MediaLoading.Title", "MediaMetadata.Setting", "download speed video quality metadata 下载 速度 媒体 信息 播放 画质"],
        "photoSettings": ["Settings.Category.photos", "photo quality image 照片 画质 图片"],
        "stickerSettings": ["Settings.Category.stickers", "sticker emoji size recent 贴纸 表情 最近 大小"],
        "recordingSettings": ["Settings.Category.recording", "recording microphone round camera 录制 麦克风 圆视频"],
        "appUpdate": ["AppUpdate.Title", "update github certificate p12 ipa install 更新 证书 签名 安装"],

        "messageFilter": ["MessageFilter.Title", "MessageFilter.Regex", "MessageFilter.Test.Title", "filter regex whitelist 过滤 正则 白名单"],
        "hiddenUsers": ["HiddenUsers.Title", "hidden blocked 隐藏 屏蔽用户"],
        "mentionAsUserIdLink": ["Mention.UserIdLink", "mention nickname 昵称 提及 艾特"],
        "localPremium": ["LocalPremium.Title", "premium"],
        "disableLinkPreview": ["LinkPreview.Disable", "link preview 链接 预览"],
        "panguSpacing": ["Pangu.Title", "spacing 盘古 空格"],
        "defaultOutgoingFormatting": ["OutgoingFormatting.Title", "format bold italic 默认 格式 加粗 斜体"],
        "antiFeatures": ["AntiFeatures.Header", "AntiFeatures.Revoke", "AntiFeatures.AutoDelete", "AntiFeatures.SelfDestruct", "AntiFeatures.Screenshot", "AntiFeatures.SaveProtected", "AntiFeatures.SaveProtectedStories", "AntiFeatures.DisableAds", "privacy ads sponsored 隐私 广告 赞助 防撤回"],
        "antiRevokeChats": ["AntiRevoke.Chats.Title", "revoked chats 防撤回 会话"],
        "ghostMode": ["Ghost.Header", "Ghost.DontReadStories", "Ghost.DontSendOnline", "Ghost.DontSendTyping", "ghost online typing 幽灵 在线 输入状态 快拍"],
        "pinnedMessageNotifications": ["Notifications.PinnedMessages.Title", "pinned notification 置顶 通知"],
        "mentionsAndRepliesNotifications": ["Notifications.MentionsAndReplies.Title", "mention reply notification 提及 回复 通知"],
        "eraseAllData": ["EraseData.Title", "erase reset 清除数据"],
        "backup": ["Backup.Title", "Backup.Import", "Backup.Export", "backup restore 备份 備份 恢复 還原 配置"],
        "chatPreferences": ["ChatPreferences.Title", "chat settings per chat 会话 對話 格式"],
        "revokedMessages": ["Revoked.Title", "revoked history 撤回 历史 歷史"],
        "bookmarks": ["Bookmarks.Title", "bookmark tags labels 书签 标签 書籤 標籤"],
        "inputSettings": ["Settings.Category.input", "send input button 发送 输入 按钮"],
        "transferSettings": ["Settings.Category.transfer", "network download upload tcp 网络 传输 下载 上传"],
        "privacySettings": ["Settings.Category.privacy", "phone sensitive 隐私 手机 敏感"],
        "diagnostics": ["Diagnostics.Title", "diagnostics speed performance 速度 性能 诊断 診斷"],
        "filterNotifications": ["Notifications.ContentFilter", "notification filter 通知 过滤 過濾"],
    ]
}
