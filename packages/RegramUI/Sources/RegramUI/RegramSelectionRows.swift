import Cocoa
import TGUIKit
import GeneralRows
import TelegramTheme

func regramSegmentedRowItem(_ size: NSSize, stableId: AnyHashable, labels: [String], selected: Int, changed: @escaping (Int) -> Void) -> GeneralRowItem {
    RegramSegmentedRowItem(size, stableId: stableId, labels: labels, selected: selected, changed: changed)
}

private final class RegramSegmentedRowItem: GeneralRowItem {
    let labels: [String]
    let selected: Int
    let changed: (Int) -> Void

    init(_ size: NSSize, stableId: AnyHashable, labels: [String], selected: Int, changed: @escaping (Int) -> Void) {
        self.labels = labels
        self.selected = labels.indices.contains(selected) ? selected : -1
        self.changed = changed
        super.init(size, height: 50, stableId: stableId, viewType: .singleItem)
    }

    override func viewClass() -> AnyClass { RegramSegmentedRowView.self }
    override var accessibilityRole: NSAccessibility.Role? { .radioGroup }
    override var accessibilityIncludesChildren: Bool { true }

    override var accessibilityLabel: String? {
        labels.indices.contains(selected) ? labels[selected] : labels.first
    }
}

private final class RegramSegmentAccessibilityElement: NSAccessibilityElement {
    weak var view: NSView?
    var frameInView = NSRect.zero
    var activate: (() -> Bool)?
    var reveal: (() -> Void)?

    override func accessibilityFrame() -> NSRect {
        guard let view else { return .zero }
        return NSAccessibility.screenRect(fromView: view, rect: frameInView)
    }

    override func accessibilityPerformPress() -> Bool { activate?() ?? false }

    override func setAccessibilityFocused(_ focused: Bool) {
        if focused { reveal?() }
        super.setAccessibilityFocused(focused)
    }
}

private final class RegramSegmentedRowView: RegramNativeRowView {
    private let segments = GlassSegmentView(frame: .zero)
    private let scroll = HorizontalScrollView(frame: .zero)
    private let document = View()
    private var tabs: [RegramSegmentAccessibilityElement] = []
    private var revealSelection = false

    private var glass: LiquidGlassView? { segments.subviews.compactMap { $0 as? LiquidGlassView }.first }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        glass?.hasShadow = false
        glass?.isEventLess = true
        glass?.userInteractionEnabled = false
        glass?.setAccessibilityHidden(true)
        addSubview(scroll)
        scroll.documentView = document
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        document.addSubview(segments)
        segments.didSelect = { [weak self] index in _ = self?.select(index) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var backdorColor: NSColor { .clear }
    override var firstResponder: NSResponder? { self }
    override var acceptsFirstResponder: Bool { (item as? RegramSegmentedRowItem)?.labels.isEmpty == false }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .radioGroup }
    override func accessibilityChildren() -> [Any]? { tabs }

    override func hasFirstResponder() -> Bool { acceptsFirstResponder }

    override func updateColors() {
        super.updateColors()
        glass?.updateLocalizationAndTheme(theme: theme)
        segments.updateLocalizationAndTheme(theme: theme)
        scroll.layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        let previous = self.item as? RegramSegmentedRowItem
        super.set(item: item, animated: animated)
        guard let item = item as? RegramSegmentedRowItem else { return }
        let sameBinding = previous?.stableId == item.stableId && previous?.labels == item.labels
        revealSelection = !sameBinding || previous?.selected != item.selected
        segments.set(titles: item.labels, selected: item.selected < 0 ? nil : item.selected, animated: animated)
        let previousTabs = sameBinding ? tabs : []
        tabs = []
        for (index, label) in item.labels.enumerated() {
            let tab = previousTabs.indices.contains(index) ? previousTabs[index] : RegramSegmentAccessibilityElement()
            tab.view = segments
            tab.setAccessibilityParent(self)
            tab.setAccessibilityElement(true)
            tab.setAccessibilityRole(.radioButton)
            tab.setAccessibilityLabel(label)
            tab.setAccessibilitySelected(index == item.selected)
            tab.setAccessibilityValue(NSNumber(value: index == item.selected))
            let identifier = item.stableId
            tab.activate = { [weak self] in
                guard let self, let current = self.item as? RegramSegmentedRowItem, current.stableId == identifier, current.labels.indices.contains(index), current.labels[index] == label else { return false }
                return self.select(index)
            }
            tab.reveal = { [weak self] in
                guard let self, let current = self.item as? RegramSegmentedRowItem, current.stableId == identifier, current.labels.indices.contains(index), current.labels[index] == label else { return }
                self.window?.makeFirstResponder(self)
                self.reveal(index)
            }
            tabs.append(tab)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let content = segments.contentSize
        let documentSize = NSSize(width: content.width + 8, height: containerView.bounds.height)
        let viewportWidth = min(containerView.bounds.width, documentSize.width)
        let resized = scroll.frame.width != viewportWidth || document.frame.size != documentSize
        scroll.frame = NSRect(x: floor((containerView.bounds.width - viewportWidth) / 2), y: 0, width: viewportWidth, height: containerView.bounds.height)
        document.setFrameSize(documentSize)
        segments.frame = NSRect(x: 4, y: floor((containerView.bounds.height - content.height) / 2), width: content.width, height: content.height)
        for (tab, frame) in zip(tabs, segments.itemFrames) { tab.frameInView = frame }
        if revealSelection || resized {
            if let item = item as? RegramSegmentedRowItem, item.selected >= 0 { reveal(item.selected) }
            else { scroll.clipView.updateBounds(to: .zero, cancel: true) }
            revealSelection = false
        }
    }

    private func reveal(_ index: Int) {
        guard segments.itemFrames.indices.contains(index) else { return }
        let frame = segments.convert(segments.itemFrames[index], to: document)
        let maximum = max(0, document.frame.width - scroll.clipView.bounds.width)
        let target = frame.width > scroll.clipView.bounds.width ? frame.minX - 4 : frame.midX - scroll.clipView.bounds.width / 2
        let offset = min(maximum, max(0, target))
        scroll.clipView.updateBounds(to: NSPoint(x: offset, y: 0), cancel: true)
        scroll.reflectScrolledClipView(scroll.clipView)
    }

    @discardableResult private func select(_ index: Int) -> Bool {
        guard let item = item as? RegramSegmentedRowItem, item.labels.indices.contains(index) else { return false }
        reveal(index)
        guard index != item.selected else { return true }
        segments.setSelection(position: CGFloat(index), animated: true)
        item.changed(index)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard let item = item as? RegramSegmentedRowItem, !item.labels.isEmpty else { super.keyDown(with: event); return }
        let index: Int
        switch event.keyCode {
        case 123: index = max(0, item.selected - 1)
        case 124: index = min(item.labels.count - 1, item.selected + 1)
        case 115: index = 0
        case 119: index = item.labels.count - 1
        case 36, 49: index = max(0, item.selected)
        default: super.keyDown(with: event); return
        }
        _ = select(index)
    }
}

func regramSliderRowItem(_ size: NSSize, stableId: AnyHashable, title: String, value: Int, range: ClosedRange<Int>, viewType: GeneralViewType = .singleItem, format: @escaping (Int) -> String = { "\($0)%" }, changed: @escaping (Int) -> Void) -> GeneralRowItem {
    RegramNativeSliderItem(size, stableId: stableId, title: title, value: value, range: range, viewType: viewType, format: format, changed: changed)
}

private final class RegramNativeSliderItem: GeneralRowItem {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let format: (Int) -> String
    let changed: (Int) -> Void
    var titleHeight: CGFloat = 22

    init(_ size: NSSize, stableId: AnyHashable, title: String, value: Int, range: ClosedRange<Int>, viewType: GeneralViewType, format: @escaping (Int) -> String, changed: @escaping (Int) -> Void) {
        self.title = title
        self.value = min(range.upperBound, max(range.lowerBound, value))
        self.range = range
        self.format = format
        self.changed = changed
        super.init(size, height: 88, stableId: stableId, viewType: viewType)
    }

    override func viewClass() -> AnyClass { RegramNativeSliderView.self }
    override var accessibilityIncludesChildren: Bool { true }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        titleHeight = max(22, regramNativeTextHeight(NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13)]), width: blockWidth - 108))
        _height = titleHeight + 66
        return result
    }
}

private final class RegramNativeSliderView: RegramNativeRowView {
    private let title = NSTextField(wrappingLabelWithString: "")
    private let value = NSTextField(labelWithString: "")
    private let lower = NSTextField(labelWithString: "")
    private let upper = NSTextField(labelWithString: "")
    private let slider = NSSlider()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for view in [title, value, lower, upper, slider] { addSubview(view) }
        title.font = .systemFont(ofSize: 13)
        value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        value.alignment = .right
        for label in [lower, upper] { label.font = .systemFont(ofSize: 11) }
        upper.alignment = .right
        slider.isContinuous = false
        slider.target = self
        slider.action = #selector(changed)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var firstResponder: NSResponder? { slider }
    override func hasFirstResponder() -> Bool { true }

    override func updateColors() {
        super.updateColors()
        title.textColor = theme.colors.text
        value.textColor = theme.colors.text
        lower.textColor = theme.colors.grayText
        upper.textColor = theme.colors.grayText
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? RegramNativeSliderItem else { return }
        appearance = theme.appearance
        title.stringValue = item.title
        title.textColor = theme.colors.text
        value.stringValue = item.format(item.value)
        value.textColor = theme.colors.text
        lower.stringValue = item.format(item.range.lowerBound)
        upper.stringValue = item.format(item.range.upperBound)
        lower.textColor = theme.colors.grayText
        upper.textColor = theme.colors.grayText
        slider.minValue = Double(item.range.lowerBound)
        slider.maxValue = Double(item.range.upperBound)
        slider.integerValue = item.value
        slider.isEnabled = item.range.lowerBound < item.range.upperBound
        slider.setAccessibilityLabel(item.title)
        slider.setAccessibilityValueDescription(item.format(item.value))
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? RegramNativeSliderItem else { return }
        let width = max(1, containerView.bounds.width - 32)
        title.frame = NSRect(x: 16, y: 10, width: max(1, width - 76), height: item.titleHeight)
        value.frame = NSRect(x: 16 + max(0, width - 72), y: 10, width: min(72, width), height: 20)
        slider.frame = NSRect(x: 14, y: title.frame.maxY + 2, width: width + 4, height: 22)
        lower.frame = NSRect(x: 16, y: slider.frame.maxY + 4, width: width / 2, height: 16)
        upper.frame = NSRect(x: 16 + width / 2, y: lower.frame.minY, width: width / 2, height: 16)
    }

    @objc private func changed() {
        guard let item = item as? RegramNativeSliderItem else { return }
        let next = min(item.range.upperBound, max(item.range.lowerBound, Int(slider.doubleValue.rounded())))
        slider.integerValue = next
        value.stringValue = item.format(next)
        slider.setAccessibilityValueDescription(item.format(next))
        if next != item.value { item.changed(next) }
    }
}
