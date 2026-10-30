import Cocoa
import TGUIKit
import GeneralRows
import TelegramTheme

final class RegramEmptyRowItem: GeneralRowItem {
    let text: String
    let isLoading: Bool
    let buttonAction: SearchEmptyRowItem.Action?
    let minimumHeight: CGFloat
    var textHeight: CGFloat = 0

    init(_ size: NSSize, stableId: AnyHashable, height: CGFloat = 180, isLoading: Bool = false, text: String = "", action: SearchEmptyRowItem.Action? = nil) {
        self.text = text
        self.isLoading = isLoading
        self.buttonAction = action
        self.minimumHeight = height
        super.init(size, height: height, stableId: stableId, viewType: .singleItem)
    }

    override func viewClass() -> AnyClass { RegramEmptyRowView.self }
    override var accessibilityIncludesChildren: Bool { true }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        textHeight = regramNativeTextHeight(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13)]), width: blockWidth - 32)
        _height = max(minimumHeight, 74 + textHeight + (buttonAction == nil ? 0 : 44))
        return result
    }
}

private final class RegramEmptyRowView: RegramNativeRowView {
    private let symbol = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    private let button = NSButton(title: "", target: nil, action: nil)

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for view in [symbol, label, spinner, button] { addSubview(view) }
        symbol.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        symbol.contentTintColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: 13)
        label.alignment = .center
        spinner.style = .spinning
        spinner.isDisplayedWhenStopped = false
        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(activate)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var backdorColor: NSColor { .clear }
    override var firstResponder: NSResponder? { button.isHidden ? nil : button }
    override func hasFirstResponder() -> Bool { !button.isHidden }

    override func updateColors() {
        super.updateColors()
        label.textColor = theme.colors.grayText
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? RegramEmptyRowItem else { return }
        appearance = theme.appearance
        label.stringValue = item.text
        label.textColor = theme.colors.grayText
        symbol.isHidden = item.isLoading
        spinner.isHidden = !item.isLoading
        if item.isLoading { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        button.isHidden = item.buttonAction == nil
        button.title = item.buttonAction?.title ?? ""
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? RegramEmptyRowItem else { return }
        let width = max(1, containerView.bounds.width - 32)
        let textHeight = item.textHeight
        let total = 36 + 14 + textHeight + (button.isHidden ? 0 : 44)
        let top = max(12, floor((containerView.bounds.height - total) / 2))
        symbol.frame = NSRect(x: (containerView.bounds.width - 32) / 2, y: top, width: 32, height: 32)
        spinner.frame = symbol.frame
        label.frame = NSRect(x: 16, y: top + 46, width: width, height: textHeight)
        let buttonWidth = min(width, button.intrinsicContentSize.width)
        button.frame = NSRect(x: (containerView.bounds.width - buttonWidth) / 2, y: label.frame.maxY + 12, width: buttonWidth, height: 28)
    }

    @objc private func activate() { (item as? RegramEmptyRowItem)?.buttonAction?.click() }
}
