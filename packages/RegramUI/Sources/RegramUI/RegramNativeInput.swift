import Cocoa
import TGUIKit
import InputDataUI
import GeneralRows
import TelegramTheme
import Localization

final class RegramNativeInputItem: GeneralRowItem, InputDataRowDataValue {
    private(set) var text: String
    let mode: InputDataInputMode
    let data: InputDataRowData
    let label: String
    let placeholder: String
    let limit: Int32
    private let filter: (String) -> String
    private let updated: () -> Void
    var labelHeight: CGFloat = 0
    var fieldTop: CGFloat = 12
    var labelFrame = NSRect.zero
    var fieldFrame = NSRect.zero
    var fieldHeight: CGFloat { multiline ? 112 : 26 }
    var multiline: Bool { mode == .plain && (limit > 8192 || text.contains("\n")) }
    var value: InputDataValue { .string(text) }
    var canClear: Bool {
        if case let .action(_, action)? = data.rightItem, case .clearText = action { return true }
        return false
    }

    init(_ size: NSSize, stableId: AnyHashable, text: String, mode: InputDataInputMode, data: InputDataRowData, label: String, placeholder: String, error: InputDataValueError?, limit: Int32, filter: @escaping (String) -> String, updated: @escaping () -> Void) {
        self.text = text
        self.mode = mode
        self.data = data
        self.label = label
        self.placeholder = placeholder
        self.limit = limit
        self.filter = filter
        self.updated = updated
        super.init(size, stableId: stableId, viewType: data.viewType, error: error, customTheme: data.customTheme)
    }

    override var height: CGFloat { _height }
    override var accessibilityIncludesChildren: Bool { true }
    override var accessibilityLabel: String? { label.isEmpty ? placeholder : label }
    override func viewClass() -> AnyClass { RegramNativeInputView.self }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        let available = max(1, blockWidth - 32)
        let inline = !multiline && !label.isEmpty && available >= 360
        let labelWidth = inline ? min(168, floor(available * 0.35)) : available
        labelHeight = label.isEmpty ? 0 : regramNativeTextHeight(NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 13)]), width: labelWidth)
        if inline {
            let height = max(44, max(labelHeight, fieldHeight) + 16)
            fieldTop = floor((height - fieldHeight) / 2)
            labelFrame = NSRect(x: 16, y: floor((height - labelHeight) / 2), width: labelWidth, height: labelHeight)
            fieldFrame = NSRect(x: labelFrame.maxX + 16, y: fieldTop, width: available - labelWidth - 16, height: fieldHeight)
            _height = height
        } else {
            fieldTop = 10 + (labelHeight == 0 ? 0 : labelHeight + 6)
            labelFrame = NSRect(x: 16, y: 10, width: available, height: labelHeight)
            fieldFrame = NSRect(x: 16, y: fieldTop, width: available, height: fieldHeight)
            _height = fieldTop + fieldHeight + 10
        }
        if let error {
            _height += regramNativeTextHeight(NSAttributedString(string: error.description, attributes: [.font: NSFont.systemFont(ofSize: 11)]), width: available) + 4
        }
        return result
    }

    @discardableResult
    func edit(_ value: String) -> String {
        let next = String(filter(value).prefix(max(0, Int(limit))))
        guard next != text else { return next }
        text = next
        updated()
        return next
    }

    func preserveEditingValue(_ value: String) { text = value }
}

private final class RegramNativeInputView: RegramNativeRowView, NSTextFieldDelegate, NSTextViewDelegate {
    private let label = NSTextField(wrappingLabelWithString: "")
    private let field = NSTextField()
    private let secureField = NSSecureTextField()
    private let scroll = NSScrollView()
    private let editor = NSTextView()
    private let placeholder = NSTextField(wrappingLabelWithString: "")
    private let clear = NSButton()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for view in [label, field, secureField, scroll, clear, errorLabel] { addSubview(view) }
        for control in [field, secureField] {
            control.isEditable = true
            control.isSelectable = true
            control.font = .systemFont(ofSize: 13)
            control.isBezeled = true
            control.bezelStyle = .roundedBezel
            control.focusRingType = .default
            control.delegate = self
            control.cell?.usesSingleLineMode = true
            control.cell?.isScrollable = true
        }
        label.font = .systemFont(ofSize: 13)
        errorLabel.font = .systemFont(ofSize: 11)
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = editor
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.textContainerInset = NSSize(width: 6, height: 6)
        editor.font = .systemFont(ofSize: 13)
        editor.delegate = self
        editor.textContainer?.widthTracksTextView = true
        editor.autoresizingMask = [.width]
        placeholder.font = .systemFont(ofSize: 13)
        placeholder.textColor = .placeholderTextColor
        placeholder.setAccessibilityElement(false)
        editor.addSubview(placeholder)
        clear.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: strings().voiceOverEditingClearText)
        clear.isBordered = false
        clear.contentTintColor = .secondaryLabelColor
        clear.target = self
        clear.action = #selector(clearText)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var currentField: NSTextField { (item as? RegramNativeInputItem)?.mode == .secure ? secureField : field }
    private var marked: Bool {
        if (item as? RegramNativeInputItem)?.multiline == true { return editor.hasMarkedText() }
        return (currentField.currentEditor() as? NSTextView)?.hasMarkedText() == true
    }

    override var firstResponder: NSResponder? {
        guard let item = item as? RegramNativeInputItem else { return nil }
        return item.multiline ? editor : currentField.currentEditor() ?? currentField
    }
    override func hasFirstResponder() -> Bool { true }

    override func updateColors() {
        super.updateColors()
        label.textColor = theme.colors.text
        errorLabel.textColor = theme.colors.redUI
        for control in [field, secureField] {
            control.textColor = theme.colors.text
            if let editor = control.currentEditor() as? NSTextView {
                editor.textColor = theme.colors.text
                editor.insertionPointColor = theme.colors.text
            }
        }
        editor.textColor = theme.colors.text
        editor.insertionPointColor = theme.colors.text
        editor.backgroundColor = theme.colors.background
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        let previous = self.item as? RegramNativeInputItem
        let preserve = previous?.stableId == item.stableId && marked
        super.set(item: item, animated: animated)
        guard let item = item as? RegramNativeInputItem else { return }
        if preserve, let previous { item.preserveEditingValue(previous.text) }
        appearance = theme.appearance
        label.stringValue = item.label
        label.textColor = theme.colors.text
        label.isHidden = item.label.isEmpty
        field.isHidden = item.multiline || item.mode == .secure
        secureField.isHidden = item.multiline || item.mode != .secure
        scroll.isHidden = !item.multiline
        if field.isHidden { field.stringValue = "" }
        if secureField.isHidden { secureField.stringValue = "" }
        if scroll.isHidden { editor.string = "" }
        clear.isHidden = !item.canClear || item.text.isEmpty
        clear.setAccessibilityLabel(strings().voiceOverEditingClearText)
        errorLabel.stringValue = item.error?.description ?? ""
        errorLabel.textColor = theme.colors.redUI
        errorLabel.isHidden = item.error == nil
        let name = item.label.isEmpty ? item.placeholder : item.label
        for control in [field, secureField] {
            control.placeholderString = item.placeholder
            control.setAccessibilityLabel(name)
        }
        editor.setAccessibilityLabel(name)
        placeholder.stringValue = item.placeholder
        if !preserve {
            if item.multiline {
                if editor.string != item.text {
                    let selection = editor.selectedRange()
                    editor.string = item.text
                    editor.setSelectedRange(clamped(selection, length: (item.text as NSString).length))
                }
            } else if currentField.stringValue != item.text {
                let textEditor = currentField.currentEditor() as? NSTextView
                let selection = textEditor?.selectedRange()
                currentField.stringValue = item.text
                if let selection { textEditor?.setSelectedRange(clamped(selection, length: (item.text as NSString).length)) }
            }
        }
        placeholder.isHidden = !editor.string.isEmpty
        needsLayout = true
    }

    private func clamped(_ range: NSRange, length: Int) -> NSRange {
        let location = min(range.location, length)
        return NSRange(location: location, length: min(range.length, length - location))
    }

    override func layout() {
        super.layout()
        guard let item = item as? RegramNativeInputItem else { return }
        let width = max(1, containerView.bounds.width - 32)
        label.frame = item.labelFrame
        var frame = item.fieldFrame
        frame.size.width = max(1, frame.width - (clear.isHidden ? 0 : 26))
        field.frame = frame
        secureField.frame = frame
        scroll.frame = frame
        if item.multiline {
            editor.setFrameSize(NSSize(width: scroll.contentSize.width, height: max(scroll.contentSize.height, editor.frame.height)))
            editor.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
            placeholder.frame = NSRect(x: 10, y: 6, width: max(1, scroll.contentSize.width - 20), height: 36)
        }
        clear.frame = NSRect(x: frame.maxX + 6, y: frame.minY + 3, width: 20, height: 20)
        errorLabel.frame = NSRect(x: 16, y: frame.maxY + 4, width: width, height: max(0, containerView.bounds.height - frame.maxY - 4))
    }

    func controlTextDidChange(_ notification: Notification) { commitEditing() }
    func controlTextDidEndEditing(_ notification: Notification) { commitEditing() }
    func textDidChange(_ notification: Notification) { commitEditing() }
    func textDidEndEditing(_ notification: Notification) { commitEditing() }

    private func commitEditing() {
        guard let item = item as? RegramNativeInputItem, !marked else { return }
        let text = item.multiline ? editor.string : currentField.stringValue
        let result = item.edit(text)
        if result != text {
            if item.multiline {
                let selection = editor.selectedRange()
                editor.string = result
                editor.setSelectedRange(clamped(selection, length: (result as NSString).length))
            } else {
                let textEditor = currentField.currentEditor() as? NSTextView
                let selection = textEditor?.selectedRange()
                currentField.stringValue = result
                if let selection { textEditor?.setSelectedRange(clamped(selection, length: (result as NSString).length)) }
            }
        }
        placeholder.isHidden = !editor.string.isEmpty
        clear.isHidden = !item.canClear || result.isEmpty
        needsLayout = true
    }

    @objc private func clearText() {
        guard let item = item as? RegramNativeInputItem else { return }
        if item.multiline { editor.string = "" } else { currentField.stringValue = "" }
        item.edit("")
        clear.isHidden = true
        needsLayout = true
    }
}
