import Foundation

public enum RegramBottomBarItemId: String, CaseIterable, Hashable {
    case contacts
    case calls
    case chats
    case settings
    case search

    public var isNavigationItem: Bool {
        switch self {
        case .contacts, .calls, .chats, .settings:
            return true
        case .search:
            return false
        }
    }
}

public enum RegramBottomBarWidthMode: String {
    case full
    case adaptive
}

public enum RegramBottomBarSlotMode: String {
    case visibleOnly
    case preserveHidden
}

public enum RegramBottomBarAlignment: String {
    case spaceBetween
    case leftCenter
    case center = "overallCenter"

    init?(storedValue: String) {
        switch storedValue {
        case "left":
            self = .spaceBetween
        case "center":
            self = .leftCenter
        default:
            self.init(rawValue: storedValue)
        }
    }
}

public enum RegramBottomBarSearchMode: String {
    case button
    case bar
    case hidden
}

public struct RegramBottomBarSettings: Equatable {
    public static let defaultBottomItems: [RegramBottomBarItemId] = [.contacts, .chats, .settings]
    public static let minimumVisibleNonSearchBottomItems = 2

    public var automaticWidth: Bool
    public var isBottomBarVisible: Bool
    public var bottomItems: [RegramBottomBarItemId]
    public var externalItem: RegramBottomBarItemId?
    public var hiddenItems: Set<RegramBottomBarItemId>
    public var topSearchVisible: Bool
    public var showLabels: Bool
    public var widthMode: RegramBottomBarWidthMode
    public var slotMode: RegramBottomBarSlotMode
    public var buttonWidthFillRatio: Int32
    public var alignment: RegramBottomBarAlignment
    public var searchMode: RegramBottomBarSearchMode

    public init(
        automaticWidth: Bool = true,
        isBottomBarVisible: Bool = true,
        bottomItems: [RegramBottomBarItemId] = RegramBottomBarSettings.defaultBottomItems,
        externalItem: RegramBottomBarItemId? = nil,
        hiddenItems: Set<RegramBottomBarItemId> = [.calls, .search],
        topSearchVisible: Bool = true,
        showLabels: Bool = false,
        widthMode: RegramBottomBarWidthMode = .full,
        slotMode: RegramBottomBarSlotMode = .visibleOnly,
        buttonWidthFillRatio: Int32 = 100,
        alignment: RegramBottomBarAlignment = .center,
        searchMode: RegramBottomBarSearchMode = .hidden
    ) {
        self.automaticWidth = automaticWidth
        self.isBottomBarVisible = isBottomBarVisible
        self.bottomItems = bottomItems
        self.externalItem = externalItem
        self.hiddenItems = hiddenItems
        self.topSearchVisible = topSearchVisible
        self.showLabels = showLabels
        self.widthMode = widthMode
        self.slotMode = slotMode
        self.buttonWidthFillRatio = buttonWidthFillRatio
        self.alignment = alignment
        self.searchMode = searchMode
        self.normalize()
    }

    public var visibleBottomItems: [RegramBottomBarItemId] {
        guard self.isBottomBarVisible else {
            return []
        }
        return self.activeBottomItems
    }

    public var visibleNavigationItems: [RegramBottomBarItemId] {
        guard self.isBottomBarVisible else { return [] }
        var result = self.visibleBottomItems.filter(\.isNavigationItem)
        if let externalItem = self.externalItem, externalItem.isNavigationItem, !self.hiddenItems.contains(externalItem) {
            result.append(externalItem)
        }
        return result
    }

    public func isVisible(_ item: RegramBottomBarItemId) -> Bool {
        if item == .search { return self.searchMode != .hidden && !self.hiddenItems.contains(.search) }
        if self.hiddenItems.contains(item) {
            return false
        }
        return self.bottomItems.contains(item) || self.externalItem == item
    }

    public var hiddenOrAvailableItems: [RegramBottomBarItemId] {
        let hiddenItems = RegramBottomBarItemId.allCases.filter { self.hiddenItems.contains($0) }
        let availableItems = RegramBottomBarItemId.allCases.filter { item in
            !self.hiddenItems.contains(item) && !self.isVisible(item)
        }
        return hiddenItems + availableItems
    }

    public func canHide(_ item: RegramBottomBarItemId) -> Bool {
        return item != .chats && item != .settings
    }

    public mutating func toggleHidden(_ item: RegramBottomBarItemId) {
        if item == .search { self.setSearchMode(self.isVisible(.search) ? .hidden : .button); return }
        if self.hiddenItems.contains(item) {
            self.hiddenItems.remove(item)
            if self.externalItem != item && !self.bottomItems.contains(item) {
                self.bottomItems.append(item)
            }
        } else {
            self.hide(item)
            return
        }
        self.normalize()
    }

    public mutating func hide(_ item: RegramBottomBarItemId) {
        guard self.canHide(item) else {
            return
        }
        if !self.hiddenItems.contains(item) {
            self.hiddenItems.insert(item)
        }
        if item == .search {
            self.searchMode = .hidden
        }
        self.bottomItems.removeAll(where: { $0 == item })
        if self.externalItem == item {
            self.externalItem = nil
        }
        self.normalize()
    }

    public mutating func show(_ item: RegramBottomBarItemId) {
        if item == .search { self.setSearchMode(.button); return }
        self.hiddenItems.remove(item)
        if self.externalItem != item && !self.bottomItems.contains(item) {
            self.bottomItems.append(item)
        }
        self.normalize()
    }

    public mutating func setVisible(_ item: RegramBottomBarItemId, visible: Bool) {
        if visible {
            self.show(item)
        } else {
            self.hide(item)
        }
    }

    public mutating func moveBottomItem(from sourceIndex: Int, to targetIndex: Int) {
        guard self.bottomItems.indices.contains(sourceIndex) else {
            return
        }
        let item = self.bottomItems.remove(at: sourceIndex)
        let index = max(0, min(targetIndex, self.bottomItems.count))
        self.bottomItems.insert(item, at: index)
        self.normalize()
    }

    public mutating func moveToExternal(_ item: RegramBottomBarItemId) {
        if item == .search {
            self.setSearchMode(.button)
            return
        }
        self.hiddenItems.remove(item)
        let replacementIndex = self.bottomItems.firstIndex(of: item) ?? self.bottomItems.count
        self.bottomItems.removeAll(where: { $0 == item })
        if let previous = self.externalItem, previous != item, previous.isNavigationItem, !self.hiddenItems.contains(previous) {
            let index = max(0, min(replacementIndex, self.bottomItems.count))
            self.bottomItems.insert(previous, at: index)
        }
        self.externalItem = item
        self.normalize()
    }

    public mutating func moveToBottom(_ item: RegramBottomBarItemId, at targetIndex: Int) {
        if item == .search { self.setSearchMode(.button); return }
        self.hiddenItems.remove(item)
        if self.externalItem == item {
            self.externalItem = nil
        }
        self.bottomItems.removeAll(where: { $0 == item })
        let index = max(0, min(targetIndex, self.bottomItems.count))
        self.bottomItems.insert(item, at: index)
        self.normalize()
    }

    public mutating func setSearchMode(_ mode: RegramBottomBarSearchMode) {
        self.searchMode = mode
        if mode == .hidden { self.hiddenItems.insert(.search) } else { self.hiddenItems.remove(.search) }
        self.normalize()
    }

    public mutating func reset() {
        self = RegramBottomBarSettings()
    }

    private mutating func normalize() {
        self.hiddenItems.subtract([.chats, .settings])
        self.alignment = .center
        let searchEnabled = !self.hiddenItems.contains(.search) && (self.bottomItems.contains(.search) || self.externalItem == .search || self.searchMode != .hidden)
        self.bottomItems.removeAll(where: { $0 == .search })
        if self.externalItem == .search { self.externalItem = nil }
        self.searchMode = searchEnabled ? .button : .hidden
        if searchEnabled { self.hiddenItems.remove(.search) } else { self.hiddenItems.insert(.search) }

        var seen = Set<RegramBottomBarItemId>()
        self.bottomItems = self.bottomItems.compactMap { item in
            guard !seen.contains(item), !self.hiddenItems.contains(item), self.externalItem != item else {
                return nil
            }
            seen.insert(item)
            return item
        }

        if let externalItem = self.externalItem {
            if self.hiddenItems.contains(externalItem) {
                self.externalItem = nil
            } else {
                seen.insert(externalItem)
            }
        }

        self.hiddenItems = self.hiddenItems.filter { RegramBottomBarItemId.allCases.contains($0) }
        for item in self.hiddenItems {
            seen.insert(item)
        }

        for item in RegramBottomBarItemId.allCases where !seen.contains(item) && item != .search {
            self.bottomItems.append(item)
            seen.insert(item)
        }
        self.buttonWidthFillRatio = max(0, min(100, self.buttonWidthFillRatio))
    }

    private var activeBottomItems: [RegramBottomBarItemId] {
        return self.bottomItems.filter { item in
            return !self.hiddenItems.contains(item) && self.externalItem != item
        }
    }
}

public extension RegramBottomBarSettings {
    static let storageKey = "bottomBarLayout"
    static let preferenceKeys: Set<String> = [storageKey, "native.showContactsTab", "native.showCallsTab", "sidebarOrder", "sidebarHiddenTabs", "hideTabBar", "showTabNames", "tabBarWidthPercent"]

    init(storedValues values: [String: String]) {
        self.init(
            automaticWidth: values["automaticWidth"] != "false",
            isBottomBarVisible: values["visible"] != "false",
            bottomItems: (values["items"] ?? "").split(separator: ",").compactMap { RegramBottomBarItemId(rawValue: String($0)) },
            externalItem: values["external"].flatMap(RegramBottomBarItemId.init(rawValue:)),
            hiddenItems: Set((values["hidden"] ?? "").split(separator: ",").compactMap { RegramBottomBarItemId(rawValue: String($0)) }),
            topSearchVisible: values["topSearch"] != "false",
            showLabels: values["labels"] == "true",
            widthMode: values["width"].flatMap(RegramBottomBarWidthMode.init(rawValue:)) ?? .full,
            slotMode: values["slots"].flatMap(RegramBottomBarSlotMode.init(rawValue:)) ?? .visibleOnly,
            buttonWidthFillRatio: values["fill"].flatMap(Int32.init) ?? 100,
            alignment: values["alignment"].flatMap(RegramBottomBarAlignment.init(rawValue:)) ?? .center,
            searchMode: values["search"].flatMap(RegramBottomBarSearchMode.init(rawValue:)) ?? .hidden
        )
    }

    var storedValues: [String: String] {
        var value = self
        value.normalize()
        return [
            "automaticWidth": String(value.automaticWidth), "visible": String(value.isBottomBarVisible), "items": value.bottomItems.map(\.rawValue).joined(separator: ","),
            "external": value.externalItem?.rawValue ?? "", "hidden": RegramBottomBarItemId.allCases.filter { value.hiddenItems.contains($0) }.map(\.rawValue).joined(separator: ","),
            "topSearch": String(value.topSearchVisible), "labels": String(value.showLabels),
            "width": value.widthMode.rawValue, "slots": value.slotMode.rawValue, "fill": String(value.buttonWidthFillRatio),
            "alignment": value.alignment.rawValue, "search": value.searchMode.rawValue
        ]
    }


}

public extension RegramBottomBarSettings {
    init(settings: RegramAccountSettings) {
        if case let .dictionary(values)? = settings.values[Self.storageKey] {
            self.init(storedValues: values)
        } else if settings.values["sidebarOrder"] != nil || settings.values["sidebarHiddenTabs"] != nil {
            let order = settings["sidebarOrder"].strings.compactMap(RegramBottomBarItemId.init(rawValue:))
            let hidden = Set(settings["sidebarHiddenTabs"].strings.compactMap(RegramBottomBarItemId.init(rawValue:)))
            self.init(bottomItems: order.isEmpty ? Self.defaultBottomItems : order, hiddenItems: hidden)
        } else if settings.values["hideTabBar"] != nil || settings.values["showTabNames"] != nil || settings.values["tabBarWidthPercent"] != nil {
            let width = settings["tabBarWidthPercent"].integer
            self.init(automaticWidth: width <= 0, isBottomBarVisible: !settings["hideTabBar"].bool, showLabels: settings["showTabNames"].bool, buttonWidthFillRatio: Int32(clamping: width > 0 ? width : 100))
        } else {
            self.init()
        }
        let showsContacts = settings.values["native.showContactsTab"]?.bool ?? !hiddenItems.contains(.contacts)
        self = RegramBottomBarSettings(automaticWidth: automaticWidth, hiddenItems: showsContacts ? [.calls, .search] : [.contacts, .calls, .search], showLabels: showLabels, buttonWidthFillRatio: automaticWidth ? 100 : max(50, min(100, buttonWidthFillRatio)))
    }

    func apply(to settings: inout RegramAccountSettings) {
        settings[Self.storageKey] = .dictionary(storedValues)
        settings["native.showContactsTab"] = .bool(isVisible(.contacts))
        settings["showTabNames"] = .bool(showLabels)
        settings["tabBarWidthPercent"] = .integer(automaticWidth ? 0 : Int64(buttonWidthFillRatio))
    }
}
