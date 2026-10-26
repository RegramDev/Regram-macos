import Foundation

public struct RegramNavigationConfiguration: Equatable {
    public enum Tab: String, CaseIterable {
        case contacts
        case calls
        case chats
        case settings

        public var canHide: Bool { self == .contacts || self == .calls }
    }

    public var order: [Tab]
    public var hidden: Set<Tab>

    public init(settings: RegramAccountSettings) {
        var seen = Set<Tab>()
        order = settings["sidebarOrder"].strings.compactMap(Tab.init(rawValue:)).filter { seen.insert($0).inserted }
        order.append(contentsOf: Tab.allCases.filter { seen.insert($0).inserted })
        hidden = Set(settings["sidebarHiddenTabs"].strings.compactMap(Tab.init(rawValue:)).filter(\.canHide))
    }

    public func visible(callsEnabled: Bool) -> [Tab] {
        order.filter { !hidden.contains($0) && ($0 != .calls || callsEnabled) }
    }

    public func apply(to settings: inout RegramAccountSettings) {
        settings["sidebarOrder"] = .strings(order.map(\.rawValue))
        settings["sidebarHiddenTabs"] = .strings(hidden.filter(\.canHide).map(\.rawValue).sorted())
    }
}
