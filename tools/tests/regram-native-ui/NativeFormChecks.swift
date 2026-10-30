import Cocoa
import TGUIKit
import GeneralRows
import InputDataUI
import TelegramTheme
import SwiftSignalKit

extension NativeUIChecks {
    static func formAction(_ control: NSControl) {
        if let action = control.action { _ = NSApplication.shared.sendAction(action, to: control.target, from: control) }
    }

    static func formRow(_ data: InputDataGeneralData, id: String = "form.row", width: CGFloat = 600) -> GeneralContainableRowView {
        makeView(RegramNativeRowItem(NSSize(width: width, height: 50), stableId: id, data: data), width: width)
    }

    static func nativeFormActions() throws {
        var first = 0
        var latest = 0
        let row = formRow(.init(name: "Show labels", color: theme.colors.text, type: .switchable(false), viewType: .singleItem, action: { first += 1 }))
        let toggle = allSubviews(row).compactMap { $0 as? NSSwitch }.first!
        toggle.state = .on
        formAction(toggle)
        check(first == 1 && toggle.state == .off, "native toggle dispatches once and does not retain a rejected state")
        let replacement = RegramNativeRowItem(NSSize(width: 600, height: 50), stableId: "form.row", data: .init(name: "Show labels", color: theme.colors.text, type: .switchable(true), viewType: .singleItem, action: { latest += 1 }))
        row.set(item: replacement)
        toggle.state = .off
        formAction(toggle)
        check(first == 1 && latest == 1 && toggle.state == .on, "retained native switch uses the current model and callback")
        row.set(item: RegramNativeRowItem(NSSize(width: 600, height: 50), stableId: "form.row", data: .init(name: "Unavailable", color: theme.colors.text, type: .switchable(false), viewType: .singleItem, enabled: false, action: { latest += 1 })))
        formAction(toggle)
        check(latest == 1 && !toggle.isEnabled, "disabled native switch cannot change settings")
        check((row.accessibilityChildren() ?? []).contains { ($0 as? NSSwitch) === toggle }, "native switch is exposed to accessibility")

        var chosen: [Int] = []
        let choices = [
            ContextMenuItem("First", handler: { chosen.append(0) }),
            ContextMenuItem("Second", handler: { chosen.append(1) }, state: .on),
            ContextMenuItem("Unavailable", handler: { chosen.append(2) }, locked: true)
        ]
        let menuRow = formRow(.init(name: "Service", color: theme.colors.text, type: .contextSelector("Second", choices), viewType: .singleItem))
        let popup = allSubviews(menuRow).compactMap { $0 as? NSPopUpButton }.first!
        check(popup.titleOfSelectedItem == "Second" && chosen.isEmpty, "binding a native popup preserves selection without executing an option")
        check(popup.numberOfItems == 1, "popup defers option creation while scrolling")
        popup.menu?.delegate?.menuNeedsUpdate?(popup.menu!)
        let firstOption = popup.item(at: 0)!
        _ = NSApplication.shared.sendAction(firstOption.action!, to: firstOption.target, from: firstOption)
        let locked = popup.item(at: 2)!
        _ = NSApplication.shared.sendAction(locked.action!, to: locked.target, from: locked)
        check(chosen == [0] && !locked.isEnabled, "native popup executes the chosen handler and rejects unavailable choices")
        let newest = [ContextMenuItem("First", handler: { chosen.append(9) })]
        menuRow.set(item: RegramNativeRowItem(NSSize(width: 600, height: 50), stableId: "form.row", data: .init(name: "Service", color: theme.colors.text, type: .contextSelector("Unknown", newest), viewType: .singleItem)))
        popup.menu?.delegate?.menuNeedsUpdate?(popup.menu!)
        _ = NSApplication.shared.sendAction(firstOption.action!, to: firstOption.target, from: firstOption)
        check(popup.titleOfSelectedItem == "Unknown" && popup.numberOfItems == 2 && chosen == [0], "unknown popup values remain visible without silently choosing a service")
        let realOption = popup.item(at: 1)!
        _ = NSApplication.shared.sendAction(realOption.action!, to: realOption.target, from: realOption)
        check(chosen == [0, 9], "popup reuse invokes the latest handler even after inserting a placeholder")

        var applies = 0
        let actionRow = formRow(.init(name: "Apply", color: theme.colors.accent, type: .none, viewType: .singleItem, action: { applies += 1 }))
        let button = allSubviews(actionRow).compactMap { $0 as? NSButton }.first { !$0.isHidden && $0.title == "Apply" }!
        formAction(button)
        check(applies == 1 && button.bezelStyle == .rounded, "native action button applies once")
        var selected = 0
        let choiceRow = formRow(.init(name: "Include this category", color: theme.colors.text, type: .selectable(false), viewType: .singleItem, action: { selected += 1 }))
        let checkbox = allSubviews(choiceRow).compactMap { $0 as? NSButton }.first { !$0.isHidden && $0.title == "Include this category" }!
        formAction(checkbox)
        check(selected == 1 && checkbox.state == .off && checkbox.frame.minX < 24, "multi-selection uses a leading native checkbox and authoritative state")

        var amounts: [Int] = []
        let sliderRow = makeView(regramSliderRowItem(NSSize(width: 600, height: 88), stableId: "slider", title: "Quality", value: 50, range: 0...100, changed: { amounts.append($0) }), width: 600)
        let slider = allSubviews(sliderRow).compactMap { $0 as? NSSlider }.first!
        slider.doubleValue = 71.8
        formAction(slider)
        check(amounts == [72] && !slider.isContinuous, "native slider commits a rounded value without saving on every drag frame")
        sliderRow.set(item: regramSliderRowItem(NSSize(width: 600, height: 88), stableId: "slider", title: "Quality", value: 72, range: 0...100, changed: { amounts.append($0 * 2) }))
        slider.integerValue = 72
        formAction(slider)
        check(amounts == [72], "native slider ignores an unchanged setting")
        slider.integerValue = 80
        formAction(slider)
        check(amounts == [72, 160], "native slider reuse keeps the current callback")
    }

    static func nativeFormEditing() throws {
        let id = InputDataIdentifier("form.name")
        let secret = InputDataIdentifier("form.key")
        let note = InputDataIdentifier("form.prompt")
        var writes: [[InputDataIdentifier: InputDataValue]] = []
        let entries: [InputDataEntry] = [
            .sectionId(0, type: .normal),
            .input(sectionId: 1, index: 0, value: .string("Initial"), error: nil, identifier: id, mode: .plain, data: .init(viewType: .firstItem), placeholder: .init("Name"), inputPlaceholder: "Name", filter: { $0 }, limit: 24),
            .input(sectionId: 1, index: 1, value: .string("fixture-key"), error: nil, identifier: secret, mode: .secure, data: .init(viewType: .innerItem), placeholder: .init("API Key"), inputPlaceholder: "", filter: { $0 }, limit: 2048),
            .input(sectionId: 1, index: 2, value: .string("First line\nSecond line"), error: nil, identifier: note, mode: .plain, data: .init(viewType: .lastItem), placeholder: .init("Prompt"), inputPlaceholder: "", filter: { $0 }, limit: 16000)
        ]
        let controller = RegramFormController(dataSignal: .single(InputDataSignalValue(entries: entries)), title: "Native form", updateDatas: { writes.append($0); return .fail(.none) }, removeAfterDisappear: false, hasDone: false)
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 600, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let navigation = NavigationViewController(controller, window)
        navigation.loadViewIfNeeded(NSRect(x: 0, y: 0, width: 600, height: 600))
        window.contentView = navigation.view
        let end = Date().addingTimeInterval(3)
        while controller.fetchData()[id] == nil && Date() < end { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        defer { window.contentView = nil; window.close() }
        check(controller.fetchData()[id]?.stringValue == "Initial" && controller.fetchData()[secret]?.stringValue == "fixture-key", "native form retains field identifiers and initial values through InputDataController")
        guard let item = controller.tableView.item(stableId: InputDataEntryId.custom(id)) as? RegramNativeInputItem,
              let view = item.viewNecessary,
              let field = allSubviews(view).compactMap({ $0 as? NSTextField }).first(where: { $0.isEditable && !($0 is NSSecureTextField) && !$0.isHidden }) else { throw NSError(domain: "NativeForms", code: 1) }
        field.stringValue = "Changed"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        check(writes.last?[id]?.stringValue == "Changed" && controller.fetchData()[id]?.stringValue == "Changed", "native field edits reach production updateDatas and fetchData")
        field.stringValue = String(repeating: "界", count: 40)
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        check(field.stringValue.count == 24 && controller.fetchData()[id]?.stringValue?.count == 24, "native field limits preserve whole characters")
        window.makeFirstResponder(field)
        let secureView = controller.tableView.item(stableId: InputDataEntryId.custom(secret))?.viewNecessary
        check(controller.nextResponder() === secureView?.firstResponder, "Tab order advances from a native text field to the secure field")
        let child = ViewController()
        child.loadViewIfNeeded(NSRect(x: 0, y: 0, width: 600, height: 600))
        child.readyOnce()
        navigation.push(child, false)
        let pushEnd = Date().addingTimeInterval(3)
        while navigation.controller !== child && Date() < pushEnd { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        navigation.back(animated: false)
        let popEnd = Date().addingTimeInterval(3)
        while (navigation.controller !== controller || field.window !== window) && Date() < popEnd { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        check(navigation.controller === controller && controller.fetchData()[id]?.stringValue?.count == 24 && controller.fetchData()[secret]?.stringValue == "fixture-key", "native form values survive child navigation and return")
        window.makeFirstResponder(field)
        if let editor = field.currentEditor() as? NSTextView {
            editor.setSelectedRange(NSRange(location: 2, length: 0))
            let count = writes.count
            editor.setMarkedText("拼音", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
            let marked = editor.markedRange()
            field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
            let replacement = RegramNativeInputItem(NSSize(width: 600, height: 80), stableId: item.stableId, text: "stale model", mode: .plain, data: .init(viewType: .firstItem), label: "Name", placeholder: "Name", error: nil, limit: 24, filter: { $0 }, updated: {})
            view.set(item: replacement, animated: false)
            check(editor.hasMarkedText() && editor.markedRange() == marked && writes.count == count, "native IME composition survives rebinding without saving unfinished text")
            editor.unmarkText()
        } else {
            check(false, "native field creates a real AppKit field editor")
        }
        check(secureView.map { allSubviews($0).contains { $0 is NSSecureTextField && !$0.isHidden } } == true, "API credentials use NSSecureTextField")
        let multiView = controller.tableView.item(stableId: InputDataEntryId.custom(note))?.viewNecessary
        check(multiView.map { allSubviews($0).contains { $0 is NSScrollView && !$0.isHidden } } == true, "long prompts use an AppKit text editor with native scrolling")
        check(!window.isVisible && !window.isKeyWindow && !window.isMainWindow, "native form editing checks do not activate a user window")
    }

    static func nativeFormGeometry(width: CGFloat, palette: String, output: URL) throws {
        let menu = [
            ContextMenuItem("自动选择", state: .on),
            ContextMenuItem("自定义 API（OpenAI 格式）")
        ]
        let fixtures: [InputDataGeneralData] = [
            .init(name: "消息与聊天", color: theme.colors.text, type: .next, viewType: .firstItem, description: "消息操作、聊天列表与文件夹", action: {}),
            .init(name: "打开消息前确认", color: theme.colors.text, type: .switchable(true), viewType: .innerItem, description: "较长的说明会在窄窗口内自动换行，不挤压右侧的原生开关。", action: {}),
            .init(name: "语音识别服务", color: theme.colors.text, type: .contextSelector("自动选择", menu), viewType: .lastItem),
            .init(name: "Include message settings in this backup", color: theme.colors.text, type: .selectable(true), viewType: .singleItem, description: "Choose the categories you want to include.", action: {}),
            .init(name: "测试连接", color: theme.colors.accent, type: .loading, viewType: .singleItem, action: {}),
            .init(name: "删除本地数据…", color: theme.colors.redUI, type: .none, viewType: .singleItem, enabled: false, action: {})
        ]
        var views = fixtures.enumerated().map { formRow($0.element, id: "geometry.\($0.offset)", width: width) }
        views.append(makeView(RegramNativeInputItem(NSSize(width: width, height: 80), stableId: "geometry.field", text: "https://example.com/v1", mode: .plain, data: .init(viewType: .singleItem), label: "服务地址", placeholder: "https://", error: nil, limit: 2048, filter: { $0 }, updated: {}), width: width))
        views.append(makeView(regramSliderRowItem(NSSize(width: width, height: 88), stableId: "geometry.slider", title: "发送图片质量", value: 80, range: 0...100, changed: { _ in }), width: width))
        let height = views.reduce(20) { $0 + $1.frame.height + 12 }
        let root = View(frame: NSRect(x: 0, y: 0, width: width, height: height))
        root.backgroundColor = theme.colors.listBackground
        var y: CGFloat = 10
        for view in views {
            view.frame.origin.y = y
            root.addSubview(view)
            view.layout()
            y += view.frame.height + 12
            for control in view.containerView.subviews.compactMap({ $0 as? NSControl }) where !control.isHidden {
                check(control.frame.minX >= 0 && control.frame.maxX <= view.containerView.bounds.width + 1, "\(palette)/\(width) native control stays inside its content column")
                check(control.frame.minY >= 0 && control.frame.maxY <= view.containerView.bounds.height + 1, "\(palette)/\(width) native control remains vertically visible")
                if let label = control as? NSTextField, !label.isEditable, label.maximumNumberOfLines == 0, label.lineBreakMode == .byWordWrapping, !label.stringValue.isEmpty {
                    let needed = label.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: label.frame.width, height: 10000)).height
                    check(label.frame.height >= needed, "\(palette)/\(width) native label has enough space for every wrapped line: \(label.stringValue)")
                }
            }
            check(view.containerView.layer?.cornerRadius == min(14, view.containerView.bounds.height / 2), "\(palette)/\(width) settings groups use consistent rounded corners")
        }
        try layerComposite(root, path: output.appendingPathComponent("native-form-\(palette)-\(Int(width)).png"))
        let longText = String(repeating: "请检查服务配置，然后重试。", count: 30)
        let empty = makeView(RegramEmptyRowItem(NSSize(width: width, height: 180), stableId: "empty.long", text: longText), width: width)
        let emptyLabel = allSubviews(empty).compactMap { $0 as? NSTextField }.first!
        check(emptyLabel.frame.maxY < empty.containerView.bounds.height, "\(palette)/\(width) long empty-state guidance remains inside the row")
        let longSlider = makeView(regramSliderRowItem(NSSize(width: width, height: 88), stableId: "slider.long", title: "Maximum image quality when sending photos and media", value: 80, range: 0...100, changed: { _ in }), width: width)
        let sliderTitle = allSubviews(longSlider).compactMap { $0 as? NSTextField }.first!
        let required = sliderTitle.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: sliderTitle.frame.width, height: 10000)).height
        check(sliderTitle.frame.height >= required, "\(palette)/\(width) localized slider title wraps without clipping")
        let browser = RegramWebTranslationView(frame: NSRect(x: 0, y: 0, width: width, height: 600))
        browser.translate.title = "Translate webpage"
        browser.restore.title = "Restore the original text"
        browser.status.stringValue = "example.com"
        browser.notice.stringValue = "Visible webpage text is sent to the selected translation service. Review the service settings before translating."
        browser.layout()
        for control in [browser.translate, browser.restore, browser.status, browser.notice] {
            check(control.frame.maxX <= width - 15 && control.frame.minX >= 16, "\(palette)/\(width) web translation controls remain inside the window")
        }
        let noticeHeight = browser.notice.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: browser.notice.frame.width, height: 10000)).height
        check(browser.notice.frame.height >= noticeHeight && browser.webView.frame.minY > browser.notice.frame.maxY, "\(palette)/\(width) webpage starts below all wrapped guidance")
    }
}
