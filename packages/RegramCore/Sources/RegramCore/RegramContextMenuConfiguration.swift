import Foundation

public struct RegramContextMenuConfiguration {
    public static let supportedItems: Set<RGContextMenuItemId> = [
        .favoriteSticker, .saveNotificationSound, .reply, .sendGift,
        .repeatForward, .repeatCopy, .sendScheduledNow, .editScheduledTime,
        .copy, .translate, .saveMedia, .messageReplies, .edit, .editHistory,
        .bookmark, .summarize, .messageScreenshot, .unvotePoll, .addTodoTask, .unpin, .pin, .stopPoll,
        .copyLink, .saveGif, .viewStickerPack, .saveToCloud, .forward,
        .forwardNoQuote, .report, .viewStats, .factCheck, .select, .selectFromUser, .delete, .json, .addFilter
    ]

    public let order: [RGContextMenuItemId]
    public let disabled: Set<RGContextMenuItemId>
    private let settings: RegramAccountSettings

    public init(settings: RegramAccountSettings) {
        self.settings = settings
        var seen = Set<RGContextMenuItemId>()
        order = (settings["contextMenuOrder"].strings.compactMap(RGContextMenuItemId.init(rawValue:)) + RGContextMenuItemId.allCases).filter { seen.insert($0).inserted }
        disabled = Set(settings["contextMenuDisabledItems"].strings.compactMap(RGContextMenuItemId.init(rawValue:)).filter(\.canBeCustomized))
    }

    public static func settingKey(_ id: RGContextMenuItemId) -> String? {
        switch id {
        case .repeatForward: return "contextShowRepeatForward"
        case .repeatCopy: return "contextShowRepeatCopy"
        case .forwardNoQuote: return "contextShowHideForwardName"
        case .saveToCloud: return "contextShowSaveToCloud"
        case .selectFromUser: return "contextShowSelectFromUser"
        case .restrict: return "contextShowRestrict"
        case .report: return "contextShowReport"
        case .reply: return "contextShowReply"
        case .pin: return "contextShowPin"
        case .saveMedia: return "contextShowSaveMedia"
        case .messageReplies: return "contextShowMessageReplies"
        case .json: return "contextShowJson"
        case .editHistory: return "contextShowEditHistory"
        default: return nil
        }
    }

    public func isEnabled(_ id: RGContextMenuItemId) -> Bool {
        if let key = Self.settingKey(id) { return settings[key].bool }
        return !disabled.contains(id)
    }

    public func orderedItems<T>(_ generated: [(RGContextMenuItemId, T)]) -> [T] {
        let groups = Dictionary(grouping: generated, by: { $0.0 })
        return order.filter(isEnabled).flatMap { groups[$0]?.map { $0.1 } ?? [] }
    }

    public func reorderingVisible(_ visible: [RGContextMenuItemId]) -> [RGContextMenuItemId] {
        let visibleSet = Set(visible)
        guard visibleSet.count == visible.count else { return order }
        var iterator = visible.makeIterator()
        return order.map { visibleSet.contains($0) ? iterator.next() ?? $0 : $0 }
    }
}
