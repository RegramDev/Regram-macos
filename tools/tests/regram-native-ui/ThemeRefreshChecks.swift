import Cocoa
import TGUIKit
import GeneralRows
import InputDataUI
import TelegramTheme
import SwiftSignalKit
import ColorPalette
import ThemeSettings

extension NativeUIChecks {
    static func nativeThemeRefresh() throws {
        func foreground(_ field: NSTextField?) -> NSColor? {
            guard let field, field.attributedStringValue.length > 0 else { return nil }
            return field.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        }
        telegramUpdateTheme(generateTheme(palette: dayClassicPalette, cloudTheme: nil, bubbled: false, fontSize: 13, wallpaper: ThemeWallpaper(), liquidGlass: false), animated: false)
        defer { setDefaultTheme() }
        let title = formRow(.init(name: "Theme title", color: theme.colors.text, type: .switchable(true), viewType: .singleItem, description: "Theme detail", action: {}))
        let attributed = NSAttributedString(string: "Custom color", attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.systemPurple])
        let custom = formRow(.init(name: "Custom color", color: theme.colors.text, type: .none, viewType: .singleItem, nameAttributed: attributed))
        let value = formRow(.init(name: "Value", color: theme.colors.text, type: .contextColored("Warning", theme.colors.redUI), viewType: .singleItem))
        let input = makeView(RegramNativeInputItem(NSSize(width: 600, height: 50), stableId: "theme.input", text: "Preserve input", mode: .plain, data: .init(viewType: .singleItem), label: "Input", placeholder: "", error: nil, limit: 100, filter: { $0 }, updated: {}), width: 600)
        let slider = makeView(regramSliderRowItem(NSSize(width: 600, height: 80), stableId: "theme.slider", title: "Quality", value: 50, range: 0...100, changed: { _ in }), width: 600)
        let empty = makeView(RegramEmptyRowItem(NSSize(width: 600, height: 180), stableId: "theme.empty", text: "Empty text"), width: 600)
        let rows = [title, custom, value, input, slider, empty]
        for index in 0..<12 {
            let palette = index.isMultiple(of: 2) ? darkPalette : dayClassicPalette
            telegramUpdateTheme(generateTheme(palette: palette, cloudTheme: nil, bubbled: false, fontSize: 13, wallpaper: ThemeWallpaper(), liquidGlass: false), animated: false)
            for row in rows {
                let item = row.item
                row.updateColors()
                check(row.item === item, "theme refresh does not rebind native rows")
                check(row.effectiveAppearance.name == theme.appearance.name, "native accessories immediately follow application appearance")
            }
            let labels = allSubviews(title).compactMap { $0 as? NSTextField }
            check(labels.first { $0.stringValue == "Theme title" }?.textColor == theme.colors.text, "existing native title adopts new semantic text color")
            check(foreground(labels.first { $0.stringValue == "Theme detail" }) == theme.colors.grayText, "existing native description adopts new semantic color")
            check(allSubviews(custom).compactMap { $0 as? NSTextField }.first { $0.stringValue == "Custom color" }?.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .systemPurple, "theme refresh preserves explicit custom attributed colors")
            check(allSubviews(value).compactMap { $0 as? NSTextField }.first { $0.stringValue == "Warning" }?.textColor == theme.colors.redUI, "existing semantic value adopts new warning color")
            let field = allSubviews(input).compactMap { $0 as? NSTextField }.first { $0.isEditable && !$0.isHidden }!
            check(field.stringValue == "Preserve input" && field.textColor == theme.colors.text, "theme refresh preserves native input and updates editor color")
            check(allSubviews(slider).compactMap { $0 as? NSTextField }.first { $0.stringValue == "Quality" }?.textColor == theme.colors.text, "slider title immediately follows theme")
            check(allSubviews(empty).compactMap { $0 as? NSTextField }.first { $0.stringValue == "Empty text" }?.textColor == theme.colors.grayText, "empty state immediately follows theme")
        }

        var actions = 0
        let id = InputDataIdentifier("theme.live")
        let initial = InputDataSignalValue(entries: [.general(sectionId: 1, index: 0, value: .none, error: nil, identifier: id, data: .init(name: "Live title", color: theme.colors.text, type: .switchable(false), viewType: .singleItem, description: "Live detail", action: { actions += 1 }))])
        let source = Promise(initial)
        let controller = RegramFormController(dataSignal: source.get(), title: "Theme refresh", hasDone: false)
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 600, height: 500), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let navigation = NavigationViewController(controller, window)
        navigation.loadViewIfNeeded(window.contentLayoutRect)
        window.contentView = navigation.view
        defer { window.contentView = nil; window.close() }
        func settle(_ condition: () -> Bool) {
            let end = Date().addingTimeInterval(3)
            while !condition() && Date() < end { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.005)) }
        }
        let stableId = InputDataEntryId.custom(id)
        settle { controller.tableView.item(stableId: stableId) != nil }
        let item = controller.tableView.item(stableId: stableId)!
        let row = item.viewNecessary!
        let field = allSubviews(row).compactMap { $0 as? NSTextField }.first { $0.stringValue == "Live title" }!
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        controller.preparationQueue!.async { entered.signal(); _ = release.wait(timeout: .now() + 8) }
        check(entered.wait(timeout: .now() + 1) == .success, "isolated form preparation can be held for theme-race test")
        telegramUpdateTheme(generateTheme(palette: darkPalette, cloudTheme: nil, bubbled: false, fontSize: 13, wallpaper: ThemeWallpaper(), liquidGlass: false), animated: false)
        settle { field.textColor == theme.colors.text }
        check(controller.tableView.item(stableId: stableId) === item && field.textColor == theme.colors.text, "visible form recolors before its queued table transaction completes")
        check(actions == 0, "theme notifications do not execute setting actions")
        release.signal()
        settle { controller.tableView.item(stableId: stableId) !== item }
        let rebound = controller.tableView.item(stableId: stableId)!.viewNecessary!
        check(allSubviews(rebound).compactMap { $0 as? NSTextField }.first { $0.stringValue == "Live title" }?.textColor == theme.colors.text, "static form entries retain their original semantic color role after rebinding")
        let reboundDetail = allSubviews(rebound).compactMap { $0 as? NSTextField }.first { $0.stringValue == "Live detail" }!
        let secondEntered = DispatchSemaphore(value: 0)
        let secondRelease = DispatchSemaphore(value: 0)
        controller.preparationQueue!.async { secondEntered.signal(); _ = secondRelease.wait(timeout: .now() + 8) }
        check(secondEntered.wait(timeout: .now() + 1) == .success, "form preparation is held after static row rebinding")
        telegramUpdateTheme(generateTheme(palette: dayClassicPalette, cloudTheme: nil, bubbled: false, fontSize: 13, wallpaper: ThemeWallpaper(), liquidGlass: false), animated: false)
        settle { foreground(reboundDetail) == theme.colors.grayText }
        check(foreground(reboundDetail) == theme.colors.grayText, "rebound static description recolors before queued table replacement")
        secondRelease.signal()
        settle { controller.tableView.item(stableId: stableId)?.view !== rebound }
        for index in 0..<4 {
            telegramUpdateTheme(generateTheme(palette: index.isMultiple(of: 2) ? dayClassicPalette : darkPalette, cloudTheme: nil, bubbled: false, fontSize: 13, wallpaper: ThemeWallpaper(), liquidGlass: false), animated: false)
            let old = controller.tableView.item(stableId: stableId)
            settle { controller.tableView.item(stableId: stableId) !== old }
            let current = controller.tableView.item(stableId: stableId)!.viewNecessary!
            check(foreground(allSubviews(current).compactMap { $0 as? NSTextField }.first { $0.stringValue == "Live detail" }) == theme.colors.grayText, "static description preserves its semantic color across repeated theme rebinding")
        }

        let blocked = DispatchSemaphore(value: 0)
        let unblock = DispatchSemaphore(value: 0)
        prepareQueue.async { blocked.signal(); _ = unblock.wait(timeout: .now() + 8) }
        check(blocked.wait(timeout: .now() + 1) == .success, "shared prepare queue is blocked for switch isolation test")
        let next = InputDataSignalValue(entries: [.general(sectionId: 1, index: 0, value: .none, error: nil, identifier: id, data: .init(name: "Updated title", color: theme.colors.text, type: .switchable(true), viewType: .singleItem, action: { actions += 1 }))])
        source.set(.single(next))
        settle { (controller.tableView.item(stableId: stableId) as? RegramNativeRowItem)?.data.name == "Updated title" }
        check((controller.tableView.item(stableId: stableId) as? RegramNativeRowItem)?.data.name == "Updated title", "settings updates do not wait for unrelated shared prepare work")
        unblock.signal()
        check(!window.isVisible && !window.isKeyWindow && actions == 0, "theme and switch checks keep the account and visible desktop untouched")
    }
}
