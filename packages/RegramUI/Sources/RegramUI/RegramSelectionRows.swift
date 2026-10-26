import Cocoa
import TGUIKit
import GeneralRows
import TelegramTheme
import InputDataUI

final class RegramSegmentedRowItem: GeneralRowItem {
    let labels: [String]
    let selected: Int
    let changed: (Int) -> Void
    init(_ size: NSSize, stableId: AnyHashable, labels: [String], selected: Int, changed: @escaping (Int) -> Void) {
        self.labels = labels
        self.selected = selected
        self.changed = changed
        super.init(size, height: 48, stableId: stableId, viewType: .singleItem)
    }
    override func viewClass() -> AnyClass { RegramSegmentedRowView.self }
}

private final class RegramSegmentedRowView: GeneralContainableRowView {
    private let control = NSSegmentedControl()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(control)
        control.target = self
        control.action = #selector(changed)
        control.segmentStyle = .rounded
        control.trackingMode = .selectOne
    }
    @objc private func changed() { (item as? RegramSegmentedRowItem)?.changed(control.selectedSegment) }
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? RegramSegmentedRowItem else { return }
        control.segmentCount = item.labels.count
        for (index, title) in item.labels.enumerated() { control.setLabel(title, forSegment: index) }
        control.selectedSegment = item.selected
        needsLayout = true
    }
    override func layout() {
        super.layout()
        control.frame = NSMakeRect(16, 9, max(0, containerView.bounds.width - 32), 30)
        for index in 0..<control.segmentCount { control.setWidth(max(0, control.bounds.width / CGFloat(max(1, control.segmentCount))), forSegment: index) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class RegramSliderRowItem: GeneralRowItem {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let changed: (Int) -> Void
    init(_ size: NSSize, stableId: AnyHashable, title: String, value: Int, range: ClosedRange<Int>, changed: @escaping (Int) -> Void) {
        self.title = title
        self.value = value
        self.range = range
        self.changed = changed
        super.init(size, height: 76, stableId: stableId, viewType: .singleItem)
    }
    override func viewClass() -> AnyClass { RegramSliderRowView.self }
}

private final class RegramSliderRowView: GeneralContainableRowView {
    private let title = NSTextField(labelWithString: "")
    private let value = NSTextField(labelWithString: "")
    private let control = NSSlider()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(title)
        addSubview(value)
        addSubview(control)
        value.alignment = .right
        control.target = self
        control.action = #selector(changed)
        control.isContinuous = true
    }
    @objc private func changed() { (item as? RegramSliderRowItem)?.changed(control.integerValue) }
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? RegramSliderRowItem else { return }
        title.stringValue = item.title
        title.textColor = theme.colors.text
        title.font = .normal(.title)
        title.lineBreakMode = .byTruncatingTail
        value.stringValue = "\(item.value)%"
        value.textColor = theme.colors.grayText
        value.font = .normal(.title)
        control.minValue = Double(item.range.lowerBound)
        control.maxValue = Double(item.range.upperBound)
        control.integerValue = item.value
        control.setAccessibilityLabel(item.title)
        needsLayout = true
    }
    override func layout() {
        super.layout()
        guard let item = item as? RegramSliderRowItem else { return }
        let insets = item.viewType.innerInset
        let width = max(0, containerView.bounds.width - insets.left - insets.right)
        let valueWidth = min(width, max(36, value.intrinsicContentSize.width))
        let top = max(0, insets.top - 1)
        title.frame = NSMakeRect(insets.left, top, max(0, width - valueWidth - 8), 22)
        value.frame = NSMakeRect(containerView.bounds.width - insets.right - valueWidth, top, valueWidth, 22)
        control.frame = NSMakeRect(insets.left, top + 27, width, 24)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class RegramProgressRowItem: GeneralRowItem {
    let title: String
    let progress: Double
    init(_ size: NSSize, stableId: AnyHashable, title: String, progress: Double) {
        self.title = title
        self.progress = min(1, max(0, progress))
        super.init(size, height: 68, stableId: stableId, viewType: .singleItem)
    }
    override func viewClass() -> AnyClass { RegramProgressRowView.self }
}

private final class RegramProgressRowView: GeneralContainableRowView {
    private let title = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(title)
        addSubview(progress)
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
    }
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? RegramProgressRowItem else { return }
        title.stringValue = item.title + "  \(Int(item.progress * 100))%"
        title.textColor = theme.colors.text
        title.font = .normal(.title)
        progress.doubleValue = item.progress
        progress.setAccessibilityLabel(item.title)
        needsLayout = true
    }
    override func layout() {
        super.layout()
        title.frame = NSMakeRect(16, 10, max(0, containerView.bounds.width - 32), 22)
        progress.frame = NSMakeRect(16, 40, max(0, containerView.bounds.width - 32), 8)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
