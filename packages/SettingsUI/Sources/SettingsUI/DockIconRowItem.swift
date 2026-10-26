import Cocoa
import TGUIKit
import GeneralRows
import Localization
import TelegramTheme
import ColorPalette
import FoundationUtils
import RegramCore
import RegramServices

public struct DockIconData {
    public let icon: String
    public let title: String
    public let selected: Bool
    public let frame: NSRect
}

public final class DockIconRowItem: GeneralRowItem {
    public let icons: [DockIconData]
    public let callback: (String) -> Void

    public init(_ initialSize: NSSize, stableId: AnyHashable, viewType: GeneralViewType, dockIcons: [String] = RegramBranding.icons, selected: String, action: @escaping (String) -> Void, insets: NSEdgeInsets = NSEdgeInsetsMake(0, 20, 0, 20)) {
        self.callback = action
        let language = appCurrentLanguage.primaryLanguage.languageCode
        var icons: [DockIconData] = []
        var frame = CGRect(origin: CGPoint(x: 20, y: 20), size: Self.iconSize)
        for (index, icon) in dockIcons.filter({ RegramBranding.icons.contains($0) }).enumerated() {
            icons.append(DockIconData(icon: icon, title: regramLocalizedString(RegramBranding.titleKey(icon), languageCode: language), selected: selected == icon, frame: frame))
            frame.origin.x += Self.iconSize.width
            if (index + 1) % Int(Self.rowCount) == 0 {
                frame.origin.y += Self.iconSize.height
                frame.origin.x = 20
            }
        }
        self.icons = icons
        super.init(initialSize, stableId: stableId, viewType: viewType, inset: insets)
    }

    public override func viewClass() -> AnyClass { DockIconRowView.self }
    public override var accessibilityLabel: String? { strings().appearanceSettingsDockIcon }
    public var containerSize: NSSize { NSSize(width: Self.rowCount * Self.iconSize.width + 40, height: ceil(CGFloat(icons.count) / Self.rowCount) * Self.iconSize.height + 30) }
    public static var iconSize: NSSize { NSSize(width: 60, height: 70) }
    public static var rowCount: CGFloat { 4 }
    public override var height: CGFloat { containerSize.height + 40 }
}

private final class DockIconView: Control {
    private let content = SimpleLayer()
    private let selected = SimpleLayer()
    private let selectionOutline = SimpleLayer()
    private var item: DockIconData?
    private weak var rowItem: DockIconRowItem?

    override func accessibilityLabel() -> String? { item?.title ?? strings().appearanceSettingsDockIcon }
    override func isAccessibilitySelected() -> Bool { item?.selected ?? false }

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        content.frame = NSRect(x: 0, y: 0, width: 60, height: 60)
        layer?.addSublayer(content)
        layer?.addSublayer(selectionOutline)
        layer?.addSublayer(selected)
        selectionOutline.frame = content.frame.insetBy(dx: 2, dy: 2)
        selectionOutline.cornerRadius = 14
        selectionOutline.borderWidth = 2
        selectionOutline.opacity = 0
        selected.frame = NSRect(x: 0, y: 0, width: 6, height: 6)
        selected.cornerRadius = 3
        selected.opacity = 0
        setAccessibilityRole(.radioButton)
        set(handler: { [weak self] _ in
            guard let self, let rowItem = self.rowItem, let item = self.item, !item.selected else { return }
            rowItem.callback(item.icon)
        }, for: .Click)
        layer?.masksToBounds = false
    }

    public override func layout() {
        super.layout()
        selected.frame.origin = NSPoint(x: (frame.width - selected.frame.width) / 2, y: content.frame.maxY)
    }

    public override func stateDidUpdate(_ state: ControlState) {
        scaleOnClick = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        super.stateDidUpdate(state)
    }

    public func set(item: DockIconData, rowItem: DockIconRowItem, animated: Bool) {
        let sameIcon = self.item?.icon == item.icon
        self.item = item
        self.rowItem = rowItem
        toolTip = item.title
        content.contents = RegramBranding.renderedIcon(item.icon, dark: theme.colors.isDark, pixelSize: 120)
        selected.backgroundColor = theme.colors.accent.cgColor
        selectionOutline.borderColor = theme.colors.accent.cgColor
        let opacity: Float = item.selected ? 1 : 0
        let previousOpacity = selected.presentation()?.opacity ?? selected.opacity
        let selectionChanged = selected.opacity != opacity
        selected.opacity = opacity
        selectionOutline.opacity = opacity
        if animated && sameIcon && selectionChanged {
            selected.animateAlpha(from: CGFloat(previousOpacity), to: CGFloat(opacity), duration: 0.18)
            selectionOutline.animateAlpha(from: CGFloat(previousOpacity), to: CGFloat(opacity), duration: 0.18)
            if item.selected && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                selectionOutline.animateScale(from: 0.94, to: 1, duration: 0.2, timingFunction: .easeOut)
            } else { selectionOutline.removeAnimation(forKey: "transform.scale") }
        } else {
            selected.removeAllAnimations()
            selectionOutline.removeAllAnimations()
        }
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class DockIconContainer: NSVisualEffectView {
    override var isFlipped: Bool { true }
}

public final class DockIconRowView: GeneralContainableRowView {
    private let backgroundView = BackgroundView(frame: .zero)
    private let visualEffect = DockIconContainer()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(backgroundView)
        addSubview(visualEffect)
        visualEffect.wantsLayer = true
        visualEffect.state = .active
        visualEffect.blendingMode = .withinWindow
        visualEffect.autoresizingMask = []
        visualEffect.material = .light
        visualEffect.layer?.cornerRadius = 10
        visualEffect.layer?.borderWidth = 1
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func layout() {
        super.layout()
        guard let item = item as? DockIconRowItem else { return }
        backgroundView.frame = containerView.bounds
        visualEffect.frame = containerView.focus(item.containerSize)
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? DockIconRowItem else { return }
        while visualEffect.subviews.count > item.icons.count { visualEffect.subviews.last?.removeFromSuperview() }
        while visualEffect.subviews.count < item.icons.count { visualEffect.addSubview(DockIconView(frame: DockIconRowItem.iconSize.bounds)) }
        for (index, icon) in item.icons.enumerated() {
            let view = visualEffect.subviews[index] as! DockIconView
            view.set(item: icon, rowItem: item, animated: animated)
            view.frame = icon.frame
        }
        backgroundView.backgroundMode = theme.backgroundMode
        visualEffect.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        needsLayout = true
    }
}
