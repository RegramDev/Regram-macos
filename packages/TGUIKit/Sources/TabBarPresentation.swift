import Cocoa

public struct TabBarPresentation {
    public enum Width {
        case standard
        case compact
        case fraction(CGFloat)
    }
    public var showsLabels: Bool
    public var width: Width
    public var externalTabIndex: Int?
    public var accessoryImage: CGImage?
    public var accessoryTitle: String?
    public var accessoryAction: (() -> Void)?

    public init(showsLabels: Bool = false, width: Width = .standard, externalTabIndex: Int? = nil, accessoryImage: CGImage? = nil, accessoryTitle: String? = nil, accessoryAction: (() -> Void)? = nil) {
        self.showsLabels = showsLabels
        self.width = width
        self.externalTabIndex = externalTabIndex
        self.accessoryImage = accessoryImage
        self.accessoryTitle = accessoryTitle
        self.accessoryAction = accessoryAction
    }

    var height: CGFloat { showsLabels ? 64 : FloatingTabBarLayout.height }

    func frame(in size: NSSize, count: Int) -> NSRect {
        let available = min(500, max(0, size.width - FloatingTabBarLayout.sideInset * 2))
        let accessoryWidth: CGFloat = accessoryAction == nil ? 0 : height + 8
        let itemCount = max(1, count)
        let requested: CGFloat
        switch width {
        case .standard: requested = available
        case .fraction(let fraction): requested = available * min(1, max(0.5, fraction))
        case .compact:
            let divisor: CGFloat = itemCount == 1 ? 1.75 : itemCount == 2 ? 1.5 : itemCount == 3 ? 1.25 : 1
            requested = available / divisor - (accessoryWidth == 0 ? 56 : 0)
        }
        let minimum = min(available, CGFloat(itemCount) * 44 + 8 + accessoryWidth)
        let width = min(available, max(minimum, requested))
        return NSMakeRect(floorToScreenPixels((size.width - width) / 2), max(0, size.height - height - FloatingTabBarLayout.bottomGap), max(0, width - accessoryWidth), height)
    }
}
