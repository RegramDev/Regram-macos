import Cocoa
import TGUIKit
import SwiftSignalKit
import InputDataUI
import GeneralRows
import TelegramTheme

class RegramNativeRowView: GeneralContainableRowView {
    override func isAccessibilityElement() -> Bool { false }
    override func accessibilityChildren() -> [Any]? { NSAccessibility.unignoredChildren(from: containerView.subviews) }
    override var borderColor: NSColor { super.borderColor.withAlphaComponent(0.45) }
    override var additionBorderInset: CGFloat { (item as? RegramNativeRowItem)?.data.icon == nil ? 0 : 36 }

    override func updateColors() {
        super.updateColors()
        appearance = theme.appearance
    }

    override func layout() {
        super.layout()
        guard let item = item as? GeneralRowItem else { return }
        containerView.layer?.mask = nil
        let radius = min(14, containerView.bounds.height / 2)
        containerView.cornerRadius = radius
        containerView.layer?.cornerRadius = radius
        containerView.layer?.maskedCorners = containerView.morphCorners
        containerView.layer?.masksToBounds = true
        borderView.isHidden = !item.hasBorder
    }
}

func regramNativeTextHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
    ceil(text.boundingRect(with: NSSize(width: max(1, width - 4), height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 2
}

final class RegramNativeRowItem: GeneralRowItem {
    private let sourceTheme: TelegramPresentationTheme
    let data: InputDataGeneralData
    let fallbackAction: () -> Void
    var titleFrame = NSRect.zero
    var detailFrame = NSRect.zero
    var accessoryFrame = NSRect.zero
    var iconFrame = NSRect.zero
    let titleText: NSAttributedString
    let detailText: NSAttributedString
    let selectionStyle: RegramSelectionStyle
    let maximumDetailLines: Int

    var hasAction: Bool { data.action != nil || data.switchAction != nil }
    var isStandaloneAction: Bool {
        switch data.type {
        case .none, .loading: return hasAction
        default: return false
        }
    }
    var menuChoices: [ContextMenuItem] {
        if case let .contextSelector(_, choices) = data.type { return choices }
        return []
    }
    var contextText: String {
        switch data.type {
        case let .context(value), let .contextColored(value, _), let .nextContext(value), let .imageContext(_, value), let .contextSelector(value, _), let .button(value), let .badge(value, _): return value
        case let .twoLinesContext(first, second): return first + "\n" + second
        default: return ""
        }
    }
    var isNavigation: Bool {
        switch data.type {
        case .next, .nextContext, .nextImage: return true
        default: return false
        }
    }
    var isSelection: Bool {
        switch data.type {
        case .selectable, .selectableLeft: return true
        default: return false
        }
    }

    init(_ size: NSSize, stableId: AnyHashable, data: InputDataGeneralData, error: InputDataValueError? = nil, detail: NSAttributedString? = nil, maximumDetailLines: Int = 0, selectionStyle: RegramSelectionStyle = .multiple, sourceTheme: TelegramPresentationTheme = theme, fallbackAction: @escaping () -> Void = {}) {
        self.sourceTheme = sourceTheme
        self.data = data
        self.fallbackAction = fallbackAction
        self.maximumDetailLines = maximumDetailLines
        self.selectionStyle = selectionStyle
        self.titleText = data.nameAttributed ?? NSAttributedString(string: data.name, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .regular), .foregroundColor: data.color])
        self.detailText = detail ?? NSAttributedString(string: data.description ?? "", attributes: [.font: NSFont.systemFont(ofSize: 11.5, weight: .regular), .foregroundColor: data.descTextColor ?? sourceTheme.colors.grayText])
        super.init(size, stableId: stableId, type: data.type, viewType: data.viewType, enabled: data.enabled, error: error, customTheme: data.theme)
    }

    override func viewClass() -> AnyClass { RegramNativeSettingsRowView.self }
    override var accessibilityIncludesChildren: Bool { true }
    override var accessibilityLabel: String? { data.name }
    override var hasBorder: Bool { !data.disableBorder && super.hasBorder }

    func themedColor(_ color: NSColor) -> NSColor {
        for (original, current) in [(sourceTheme.colors.text, theme.colors.text), (sourceTheme.colors.accent, theme.colors.accent), (sourceTheme.colors.grayText, theme.colors.grayText), (sourceTheme.colors.listGrayText, theme.colors.listGrayText), (sourceTheme.colors.redUI, theme.colors.redUI), (sourceTheme.colors.greenUI, theme.colors.greenUI)] where color == original { return current }
        return color
    }

    func themedText(_ text: NSAttributedString) -> NSAttributedString {
        guard sourceTheme !== theme, text.length > 0 else { return text }
        let result = NSMutableAttributedString(attributedString: text)
        text.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let color = value as? NSColor { result.addAttribute(.foregroundColor, value: themedColor(color), range: range) }
        }
        return result
    }

    override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        .single(data.menuItems?() ?? [])
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        let contentWidth = max(1, blockWidth - 32)
        let iconWidth: CGFloat = data.icon == nil ? 0 : 36
        let available = max(1, contentWidth - iconWidth)
        let textWidth = ceil(NSAttributedString(string: contextText, attributes: [.font: NSFont.systemFont(ofSize: 13)]).size().width)
        var accessoryWidth: CGFloat = 0
        var accessoryHeight: CGFloat = 26
        switch data.type {
        case .switchable: accessoryWidth = 38
        case .selectable, .selectableLeft: accessoryWidth = 20
        case .contextSelector: accessoryWidth = min(240, max(100, textWidth + 34))
        case .next, .nextImage: accessoryWidth = 16
        case .nextContext: accessoryWidth = min(220, textWidth + 24)
        case .context, .contextColored, .twoLinesContext, .imageContext, .badge, .button:
            accessoryWidth = min(240, textWidth + (hasAction ? 28 : 0))
        case .loading: accessoryWidth = isStandaloneAction ? 0 : 18
        case .none: accessoryWidth = 0
        default: accessoryWidth = 22
        }
        if case .twoLinesContext = data.type { accessoryHeight = 40 }
        let stacked = accessoryWidth > 80 && available - accessoryWidth - 16 < 140
        accessoryWidth = min(accessoryWidth, available)
        let titleWidth = max(1, available - (stacked || accessoryWidth == 0 ? 0 : accessoryWidth + 16))
        let titleHeight = max(19, regramNativeTextHeight(titleText, width: titleWidth))
        let detailHeight = detailText.length == 0 ? 0 : min(maximumDetailLines == 0 ? .greatestFiniteMagnitude : CGFloat(maximumDetailLines) * 17 + 2, regramNativeTextHeight(detailText, width: titleWidth))
        let textHeight = titleHeight + (detailHeight == 0 ? 0 : 3 + detailHeight)
        let height = max(44, textHeight + 16 + (stacked ? accessoryHeight + 10 : 0))
        _height = height
        let top = floor((height - textHeight - (stacked ? accessoryHeight + 10 : 0)) / 2)
        titleFrame = NSRect(x: 16 + iconWidth, y: top, width: titleWidth, height: titleHeight)
        detailFrame = NSRect(x: titleFrame.minX, y: titleFrame.maxY + 3, width: titleWidth, height: detailHeight)
        if isSelection { detailFrame.origin.x += 22 }
        accessoryFrame = NSRect(x: blockWidth - 16 - accessoryWidth, y: stacked ? top + textHeight + 10 : floor((height - accessoryHeight) / 2), width: accessoryWidth, height: accessoryHeight)
        iconFrame = NSRect(x: 16, y: floor((height - 24) / 2), width: 24, height: 24)
        if isStandaloneAction {
            let buttonWidth = min(contentWidth - (data.type == .loading ? 28 : 0), ceil(titleText.size().width) + 30)
            accessoryFrame = NSRect(x: 16 + (data.type == .loading ? 28 : 0), y: 9, width: max(32, buttonWidth), height: 28)
            _height = max(46, detailHeight == 0 ? 46 : 52 + detailHeight)
            detailFrame = NSRect(x: 16, y: 42, width: contentWidth, height: detailHeight)
        }
        return result
    }
}

private final class RegramNativeSettingsRowView: RegramNativeRowView, NSMenuDelegate {
    private enum Accessory: Hashable { case value, icon, toggle, check, popup, button, navigation, chevron, spinner }
    private let title = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private var accessories: [Accessory: NSView] = [:]
    private var menuGeneration = 0

    private func accessory<T: NSView>(_ kind: Accessory, make: () -> T) -> T {
        if let view = accessories[kind] as? T { return view }
        let view = make()
        accessories[kind] = view
        addSubview(view)
        return view
    }

    private var value: NSTextField {
        accessory(.value) {
            let view = NSTextField(wrappingLabelWithString: "")
            view.font = .systemFont(ofSize: 13)
            view.alignment = .right
            return view
        }
    }
    private var icon: NSImageView { accessory(.icon) { NSImageView() } }
    private var toggle: NSSwitch { accessory(.toggle) { NSSwitch() } }
    private var check: NSButton { accessory(.check) { NSButton(checkboxWithTitle: "", target: nil, action: nil) } }
    private var popup: NSPopUpButton {
        accessory(.popup) {
            let view = NSPopUpButton(frame: .zero, pullsDown: false)
            view.bezelStyle = .rounded
            view.font = .systemFont(ofSize: 13)
            return view
        }
    }
    private var button: NSButton {
        accessory(.button) {
            let view = NSButton(title: "", target: nil, action: nil)
            view.bezelStyle = .rounded
            return view
        }
    }
    private var navigation: NSButton {
        accessory(.navigation) {
            let view = NSButton(title: "", target: nil, action: nil)
            view.isBordered = false
            view.setButtonType(.momentaryPushIn)
            return view
        }
    }
    private var chevron: NSImageView {
        accessory(.chevron) {
            let view = NSImageView()
            view.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
            view.contentTintColor = .secondaryLabelColor
            return view
        }
    }
    private var spinner: NSProgressIndicator {
        accessory(.spinner) {
            let view = NSProgressIndicator()
            view.style = .spinning
            view.controlSize = .small
            view.isDisplayedWhenStopped = false
            return view
        }
    }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for label in [title, detail] {
            label.maximumNumberOfLines = 0
            label.lineBreakMode = .byWordWrapping
            addSubview(label)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var firstResponder: NSResponder? {
        [Accessory.toggle, .check, .popup, .button, .navigation].compactMap { accessories[$0] as? NSControl }.first { !$0.isHidden && $0.isEnabled }
    }
    override func hasFirstResponder() -> Bool { firstResponder != nil }

    override func updateColors() {
        super.updateColors()
        guard let item = item as? RegramNativeRowItem else { return }
        title.attributedStringValue = item.themedText(item.titleText)
        detail.attributedStringValue = item.themedText(item.detailText)
        if item.data.nameAttributed == nil || !item.enabled { title.textColor = item.enabled ? item.themedColor(item.data.color) : theme.colors.grayText }
        if let value = accessories[.value] as? NSTextField {
            if case let .contextColored(_, color) = item.data.type { value.textColor = item.themedColor(color) }
            else { value.textColor = theme.colors.grayText }
        }
        if let button = accessories[.button] as? NSButton { button.contentTintColor = item.themedColor(item.data.color) == theme.colors.redUI ? theme.colors.redUI : nil }
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? RegramNativeRowItem else { return }
        menuGeneration += 1
        for view in accessories.values { view.isHidden = true }
        (accessories[.spinner] as? NSProgressIndicator)?.stopAnimation(nil)
        appearance = theme.appearance
        title.attributedStringValue = item.titleText
        detail.attributedStringValue = item.detailText
        detail.maximumNumberOfLines = item.maximumDetailLines
        detail.lineBreakMode = item.maximumDetailLines == 0 ? .byWordWrapping : .byTruncatingTail
        detail.isHidden = item.detailText.length == 0
        title.isHidden = item.isStandaloneAction || item.isSelection
        if let image = item.data.icon {
            icon.image = NSImage(cgImage: image, size: NSSize(width: 24, height: 24))
            icon.imageScaling = .scaleProportionallyDown
            icon.isHidden = false
        }
        if item.data.nameAttributed == nil || !item.enabled { title.textColor = item.enabled ? item.data.color : theme.colors.grayText }
        switch item.data.type {
        case let .switchable(state):
            toggle.isHidden = false
            toggle.state = state ? .on : .off
        case let .selectable(state), let .selectableLeft(state):
            check.isHidden = false
            check.setButtonType(item.selectionStyle == .single ? .radio : .switch)
            check.title = item.data.name
            check.font = .systemFont(ofSize: 13)
            check.alignment = .left
            check.cell?.wraps = true
            check.cell?.lineBreakMode = .byWordWrapping
            check.state = state ? .on : .off
        case let .contextSelector(current, choices):
            popup.isHidden = false
            let menu = NSMenu()
            menu.autoenablesItems = false
            let selectedTitle = choices.first(where: { $0.state == .on })?.title ?? current
            let placeholder = NSMenuItem(title: selectedTitle, action: nil, keyEquivalent: "")
            placeholder.isEnabled = item.enabled && choices.contains { $0.title == selectedTitle && $0.isEnabled && !$0.locked && !$0.isSeparatorItem }
            menu.addItem(placeholder)
            popup.menu = menu
            popup.selectItem(at: 0)
            menu.delegate = self
            popup.toolTip = current
        case .next, .nextContext, .nextImage:
            navigation.isHidden = false
            chevron.isHidden = false
            if !item.contextText.isEmpty { value.isHidden = false }
        case .loading:
            spinner.isHidden = false
            spinner.startAnimation(nil)
            if item.hasAction { button.isHidden = false; button.title = item.data.name }
        case .none:
            if item.hasAction { button.isHidden = false; button.title = item.data.name }
        default:
            if item.hasAction {
                button.isHidden = false
                button.title = item.contextText.isEmpty ? item.data.name : item.contextText
            } else {
                value.isHidden = false
            }
        }
        for (kind, view) in accessories where !view.isHidden {
            guard let control = view as? NSControl else { continue }
            control.isEnabled = item.enabled
            if kind == .toggle || kind == .check || kind == .button || kind == .navigation {
                control.target = self
                control.action = #selector(activate)
            }
            control.setAccessibilityLabel(item.data.name)
            control.setAccessibilityHelp(item.data.description)
            control.toolTip = item.data.description
        }
        if let popup = accessories[.popup] as? NSPopUpButton, !popup.isHidden {
            popup.isEnabled = item.enabled && item.menuChoices.contains { $0.isEnabled && !$0.locked && !$0.isSeparatorItem }
            popup.toolTip = item.contextText
        }
        if let button = accessories[.button] as? NSButton, !button.isHidden {
            button.contentTintColor = item.data.color == theme.colors.redUI ? theme.colors.redUI : nil
        }
        if let value = accessories[.value] as? NSTextField, !value.isHidden {
            value.stringValue = item.contextText
            value.textColor = theme.colors.grayText
            if case let .contextColored(_, color) = item.data.type { value.textColor = color }
            value.toolTip = item.contextText
            value.maximumNumberOfLines = 1
            value.lineBreakMode = .byTruncatingMiddle
            if case .twoLinesContext = item.data.type { value.maximumNumberOfLines = 2; value.lineBreakMode = .byTruncatingTail }
            value.isSelectable = !item.isNavigation && !item.hasAction
            value.setAccessibilityLabel(item.contextText)
        }
        title.setAccessibilityElement(firstResponder == nil)
        detail.setAccessibilityElement(firstResponder == nil)
        updateColors()
        needsLayout = true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let popup = accessories[.popup] as? NSPopUpButton, popup.menu === menu, !popup.isHidden,
              let item = item as? RegramNativeRowItem, case let .contextSelector(current, choices) = item.data.type else { return }
        menu.removeAllItems()
        for (index, choice) in choices.enumerated() {
            if choice.isSeparatorItem { menu.addItem(.separator()); continue }
            let option = NSMenuItem(title: choice.title, action: #selector(selectOption(_:)), keyEquivalent: "")
            option.target = self
            option.tag = index
            option.representedObject = menuGeneration
            option.isEnabled = item.enabled && choice.isEnabled && !choice.locked
            option.state = choice.state
            option.image = choice.image
            menu.addItem(option)
        }
        if let index = choices.firstIndex(where: { $0.state == .on }) ?? choices.firstIndex(where: { $0.title == current }) {
            popup.selectItem(at: index)
        } else {
            let placeholder = NSMenuItem(title: current, action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            menu.insertItem(placeholder, at: 0)
            popup.selectItem(at: 0)
        }
    }

    override func layout() {
        super.layout()
        guard let item = item as? RegramNativeRowItem else { return }
        title.frame = item.titleFrame
        detail.frame = item.detailFrame
        accessories[.icon]?.frame = item.iconFrame
        for kind in [Accessory.toggle, .check, .popup, .button, .value] { accessories[kind]?.frame = item.accessoryFrame }
        if item.isSelection { accessories[.check]?.frame = NSRect(x: item.titleFrame.minX, y: item.titleFrame.minY - 2, width: containerView.bounds.width - item.titleFrame.minX - 16, height: item.titleFrame.height + 4) }
        accessories[.toggle]?.frame = NSRect(x: item.accessoryFrame.minX, y: floor((containerView.bounds.height - 22) / 2), width: 38, height: 22)
        if item.isNavigation, let value = accessories[.value] { value.frame.size.width = max(0, value.frame.width - 20) }
        accessories[.navigation]?.frame = containerView.bounds
        accessories[.chevron]?.frame = NSRect(x: containerView.bounds.width - 28, y: floor((containerView.bounds.height - 12) / 2), width: 8, height: 12)
        accessories[.spinner]?.frame = item.isStandaloneAction ? NSRect(x: 16, y: 15, width: 16, height: 16) : NSRect(x: item.accessoryFrame.minX, y: floor((containerView.bounds.height - 16) / 2), width: 16, height: 16)
    }

    @objc private func activate() {
        guard let item = item as? RegramNativeRowItem, item.enabled else { return }
        if case .switchable = item.data.type { (item.data.switchAction ?? item.data.action ?? item.fallbackAction)() }
        else { (item.data.action ?? item.fallbackAction)() }
        if let current = self.item as? RegramNativeRowItem {
            switch current.data.type {
            case let .switchable(state): (accessories[.toggle] as? NSSwitch)?.state = state ? .on : .off
            case let .selectable(state), let .selectableLeft(state): (accessories[.check] as? NSButton)?.state = state ? .on : .off
            default: break
            }
        }
    }

    @objc private func selectOption(_ sender: NSMenuItem) {
        guard sender.isEnabled, sender.representedObject as? Int == menuGeneration,
              sender.menu === (accessories[.popup] as? NSPopUpButton)?.menu,
              let item = item as? RegramNativeRowItem, item.enabled, item.menuChoices.indices.contains(sender.tag) else { return }
        let option = item.menuChoices[sender.tag]
        guard option.isEnabled && !option.locked && !option.isSeparatorItem else { return }
        option.handler?()
    }
}
