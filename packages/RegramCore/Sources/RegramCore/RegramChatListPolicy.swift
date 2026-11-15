import Foundation

public enum RegramChatListSwipeAction: String, CaseIterable {
    case both, folderSwitch = "switch", quickActions = "quick", none
    public var allowsFolderSwitch: Bool { self == .both || self == .folderSwitch }
    public var allowsQuickActions: Bool { self == .both || self == .quickActions }
}

public enum RegramChatListPolicy {
    public enum StartupFolder: Equatable {
        case allChats
        case named(String)

        public var storedValue: RegramValue {
            switch self {
            case .allChats: return .dictionary(["allChats": "true"])
            case let .named(title): return .dictionary(["title": title])
            }
        }
    }

    public static func swipeAction(settings: RegramAccountSettings) -> RegramChatListSwipeAction {
        RegramChatListSwipeAction(rawValue: settings["features.chatListSwipeAction"].string) ?? .both
    }

    public static func startupFolder(settings: RegramAccountSettings) -> StartupFolder? {
        guard case let .dictionary(values) = settings["features.startupFolders"] else { return nil }
        if values["allChats"] == "true" { return .allChats }
        return values["title"].map(StartupFolder.named)
    }

    static func keepLegacyStartupFolder(settings: inout RegramAccountSettings, accountId: Int64) {
        guard startupFolder(settings: settings) == nil,
              case let .dictionary(values)? = settings.values["features.startupFolders"] else { return }
        let accountKey = String(accountId)
        if let id = values[accountKey].flatMap(Int32.init) {
            settings["features.startupFolders"] = id <= 0 ? StartupFolder.allChats.storedValue : .dictionary([accountKey: String(id)])
        } else {
            settings.values.removeValue(forKey: "features.startupFolders")
        }
    }

    public static func migrateLegacyStartupFolder(settings: inout RegramAccountSettings, accountId: Int64, folders: [(id: Int32, title: String)]) {
        guard startupFolder(settings: settings) == nil,
              case let .dictionary(values) = settings["features.startupFolders"],
              let id = values[String(accountId)].flatMap(Int32.init),
              let folder = folders.first(where: { $0.id == id }) else { return }
        settings["features.startupFolders"] = StartupFolder.named(folder.title).storedValue
    }

    public static func startupFolderId(settings: RegramAccountSettings, accountId: Int64, folders: [(id: Int32, title: String)] = [], defaults: UserDefaults = regramSharedDefaults()) -> Int32? {
        switch settings["features.chatListStartupFolderMode"].string {
        case "last":
            let values = defaults.dictionary(forKey: "lastAccountFolders") ?? [:]
            let value = values[String(accountId & 0x00ffffffffffffff)] as? NSNumber
            return value.flatMap { Int32(exactly: $0.int64Value) }
        case "specific":
            switch startupFolder(settings: settings) {
            case .allChats: return -1
            case let .named(title): return folders.first(where: { $0.title == title })?.id
            case nil: break
            }
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
        return text
    }
}
