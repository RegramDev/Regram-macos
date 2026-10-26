import Foundation

public enum RegramGroupProfileSettingItem: String, CaseIterable {
    case groupType, inviteLinks, linkedChannel, reactions, appearance, history, topics, location
    case members, permissions, admins, memberRequests, removedUsers, recentActions, community, deleteGroup, other

    public func isVisible(settings: RegramAccountSettings) -> Bool {
        settings["features.groupProfileSettingItems"].string.split(separator: ",").contains { $0 == rawValue }
    }

    public func setVisible(_ visible: Bool, settings: inout RegramAccountSettings) {
        var items = Set(settings["features.groupProfileSettingItems"].string.split(separator: ",").map(String.init))
        if visible { items.insert(rawValue) } else { items.remove(rawValue) }
        settings["features.groupProfileSettingItems"] = .string(items.sorted().joined(separator: ","))
    }
}

public enum RegramProfileBadge: String {
    case developer
    public static func badge(userId: Int64) -> Self? {
        switch userId {
        case 6860249: return .developer
        default: return nil
        }
    }
}

public extension RegramAccountSettings {
    var isStoryStealthModeEnabled: Bool { self["canUseStealthMode"].bool && self["storyStealthMode"].bool }
    var seasonalEffect: String? {
        guard self["canUseNY"].bool, ["snow", "lightning"].contains(self["nyStyle"].string) else { return nil }
        return self["nyStyle"].string
    }
}
