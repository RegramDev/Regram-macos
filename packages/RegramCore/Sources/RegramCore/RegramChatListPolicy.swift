import Foundation

public enum RegramChatListSwipeAction: String, CaseIterable {
    case both, folderSwitch = "switch", quickActions = "quick", none
    public var allowsFolderSwitch: Bool { self == .both || self == .folderSwitch }
    public var allowsQuickActions: Bool { self == .both || self == .quickActions }
}

public enum RegramChatListPolicy {
    public static func swipeAction(settings: RegramAccountSettings) -> RegramChatListSwipeAction {
        RegramChatListSwipeAction(rawValue: settings["features.chatListSwipeAction"].string) ?? .both
    }

    public static func startupFolderId(settings: RegramAccountSettings, accountId: Int64, defaults: UserDefaults = regramSharedDefaults()) -> Int32? {
        switch settings["features.chatListStartupFolderMode"].string {
        case "last":
            let values = defaults.dictionary(forKey: "lastAccountFolders") ?? [:]
            let value = values[String(accountId & 0x00ffffffffffffff)] as? NSNumber
            return value.flatMap { Int32(exactly: $0.int64Value) }
        case "specific":
            if case let .dictionary(values) = settings["features.startupFolders"] { return values[String(accountId)].flatMap(Int32.init) }
            return nil
        default: return nil
        }
    }

    public static func recordSelectedFolderId(_ folderId: Int32, accountId: Int64, defaults: UserDefaults = regramSharedDefaults()) {
        var values = defaults.dictionary(forKey: "lastAccountFolders") ?? [:]
        values[String(accountId & 0x00ffffffffffffff)] = NSNumber(value: folderId)
        defaults.set(values, forKey: "lastAccountFolders")
    }

    public static func clear(accountId: Int64, defaults: UserDefaults = regramSharedDefaults()) {
        var values = defaults.dictionary(forKey: "lastAccountFolders") ?? [:]
        values.removeValue(forKey: String(accountId & 0x00ffffffffffffff))
        defaults.set(values, forKey: "lastAccountFolders")
    }

    public static func folderTitle(text: String, icon: String, allChats: Bool, shortAllChats: String, longAllChats: String, settings: RegramAccountSettings) -> String {
        let title: String
        if allChats {
            switch settings["allChatsTitleLengthOverride"].string {
            case "long": title = longAllChats
            case "short": title = shortAllChats
            default: title = text
            }
        } else { title = text }
        switch settings["features.chatListFolderTabDisplayMode"].string {
        case "icon": return icon
        case "both": return icon + " " + title
        default: return title
        }
    }
}
