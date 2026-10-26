import Foundation

public struct RegramChatListLayoutPreferences: Equatable {
    public let compact: Bool
    public let messageLines: Int
    public let hideSeparators: Bool

    public init(settings: RegramAccountSettings) {
        compact = settings["compactChatList"].bool
        messageLines = settings["chatListLines"].string == "1" ? 1 : 2
        hideSeparators = settings["hideChatListSeparators"].bool
    }

    public var avatarSize: Double { compact ? 34 : 50 }
    public var inset: Double { compact ? 4 : 9 }

    public func rowHeight(titleHeight: Double, authorHeight: Double, bodyHeight: Double, tagsHeight: Double) -> Double {
        let textHeight = max(0, titleHeight) + 1 + (authorHeight > 0 ? authorHeight + 2 : 0) + max(0, bodyHeight) + (tagsHeight > 0 ? tagsHeight + 3 : 0)
        return max(compact ? 52 : 70, ceil(inset * 2 + textHeight))
    }
}

public struct RegramFolderBadgePresentation: Equatable {
    public let count: Int
    public let hasUnmutedUnread: Bool

    public init(count: Int, hasUnmutedUnread: Bool, hidden: Bool) {
        self.count = hidden ? 0 : max(0, count)
        self.hasUnmutedUnread = !hidden && count > 0 && hasUnmutedUnread
    }
}
