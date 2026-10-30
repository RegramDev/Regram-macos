import Cocoa
import TGUIKit
import InputDataUI
import GeneralRows
import TelegramTheme
import SwiftSignalKit

extension NativeUIChecks {
    static func nativeGlassSurfaces() {
        let rows = [
            makeView(regramSegmentedRowItem(NSSize(width: 600, height: 50), stableId: "glass.segments", labels: ["消息", "媒体", "界面"], selected: 0, changed: { _ in }), width: 600)
        ]
        let liquidGlass = System.liquidGlass
        let blur = System.blurEnabled
        defer { System.liquidGlass = liquidGlass; System.blurEnabled = blur }
        for row in rows {
            let surfaces = allSubviews(row).compactMap { $0 as? LiquidGlassView }
            check(surfaces.count == 1, "each category selector owns one glass surface")
            guard let glass = surfaces.first else { continue }
            let effect = glass.effectView
            let count = allSubviews(row).count
            for _ in 0..<25 { row.updateColors(); row.layout() }
            check(glass.effectView === effect && allSubviews(row).count == count, "rebinding unchanged appearance reuses the glass effect and its views")
            check(glass.isEventLess && !glass.userInteractionEnabled, "glass does not intercept settings controls")
            check(!glass.hasShadow, "settings glass avoids an extra shadow surface")
            System.liquidGlass = false
            System.blurEnabled = false
            row.updateColors()
            check(glass.effectView is View, "disabling effects uses a solid settings surface")
            System.liquidGlass = liquidGlass
            System.blurEnabled = blur
            row.updateColors()
        }
        let row = formRow(.init(name: "普通设置", color: theme.colors.text, type: .switchable(true), viewType: .singleItem, action: {}), id: "glass.none", width: 600)
        check(!allSubviews(row).contains { $0 is LiquidGlassView }, "ordinary scrolling rows do not allocate glass effects")
    }

    static func nativeSearchEditing() throws {
        var edits: [String] = []
        let entry = regramSettingsHomeEntries(query: "", language: "zh-Hans", update: { edits.append($0) }, open: { _ in }).first { $0.stableId == .custom(InputDataIdentifier("pro.home.search")) }!
        let item = entry.item(arguments: InputDataArguments(select: { _ in }, dataUpdated: {}), initialSize: NSSize(width: 600, height: 50))
        let row = makeView(item, width: 600) as! SearchRowView
        let search = row.searchView
        check(!allSubviews(row).contains { $0 is NSSearchField || $0 is LiquidGlassView }, "settings home reuses Telegram search without an AppKit field or a second glass surface")
        let host = Window(contentRect: row.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.contentView = row
        defer { host.contentView = nil; host.close() }
        search.send(event: .Click)
        check(search.state == .Focus && !search.input.isHidden, "clicking settings search enters Telegram's editing state")
        check(!search.input.drawsBackground && search.input.backgroundColor.alphaComponent == 0 && search.input.focusRingType == .none, "focused search keeps a transparent editor without a rectangular focus ring")
        edits.removeAll()
        search.setString("翻译")
        check(edits == ["翻译"], "Telegram settings search delivers one query update")
        search.setString("")
        check(edits == ["翻译", ""], "Telegram search clear restores an empty query")
        let short = RegramNativeInputItem(NSSize(width: 600, height: 80), stableId: "inline", text: "", mode: .plain, data: .init(viewType: .singleItem), label: "服务地址", placeholder: "", error: nil, limit: 2048, filter: { $0 }, updated: {})
        _ = short.makeSize(600)
        check(short.fieldFrame.minX > short.labelFrame.maxX && short.height == 44, "wide service fields align labels and native editors in one compact row")
        _ = short.makeSize(320)
        check(short.fieldFrame.minY > short.labelFrame.maxY, "narrow service fields stack without compressing the editor")
        let error = RegramNativeInputItem(NSSize(width: 320, height: 80), stableId: "error", text: "", mode: .plain, data: .init(viewType: .singleItem), label: "地址", placeholder: "", error: .init(description: String(repeating: "请检查地址。", count: 6), target: .data), limit: 2048, filter: { $0 }, updated: {})
        let errorView = makeView(error, width: 320)
        let errorLabel = allSubviews(errorView).compactMap { $0 as? NSTextField }.first { $0.stringValue.hasPrefix("请检查") }!
        check(errorLabel.frame.height >= errorLabel.cell!.cellSize(forBounds: NSRect(x: 0, y: 0, width: errorLabel.frame.width, height: 10000)).height, "native validation messages have enough vertical space")
    }

    static func nativeSearchNavigation() throws {
        let currentQuery = Atomic(value: "")
        let query = ValuePromise("", ignoreRepeated: true)
        let controller = RegramFormController(dataSignal: query.get() |> map { value in
            InputDataSignalValue(entries: regramSettingsHomeEntries(query: value, language: "zh-Hans", update: { next in
                _ = currentQuery.swap(next)
                query.set(next)
            }, open: { _ in }))
        }, title: "Regram Pro", removeAfterDisappear: false, hasDone: false)
        regramRestoreSearchQuery(controller, identifier: InputDataIdentifier("pro.home.search"), autofocusSearch: false, query: { currentQuery.with { $0 } })
        let host = Window(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        let navigation = NavigationViewController(controller, host)
        navigation.loadViewIfNeeded(NSRect(x: 0, y: 0, width: 600, height: 700))
        host.contentView = navigation.view
        defer { host.contentView = nil; host.close() }
        let id = InputDataEntryId.custom(InputDataIdentifier("pro.home.search"))
        func settle(_ condition: () -> Bool) {
            let end = Date().addingTimeInterval(3)
            while !condition() && Date() < end { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
        }
        settle { controller.tableView.item(stableId: id) != nil }
        let row = controller.tableView.item(stableId: id)!.viewNecessary! as! SearchRowView
        let search = row.searchView
        check(controller.firstResponder() === controller.tableView.documentView, "home does not autofocus an empty search field")
        search.change(state: .Focus, false)
        _ = host.makeFirstResponder(search.input)
        search.setString("翻译")
        settle { controller.tableView.count > 3 && currentQuery.with { $0 } == "翻译" }
        check(host.firstResponder === search.input && search.query == "翻译", "live settings search retains its editor after updating the table")
        check(row.containerView.backgroundColor.alphaComponent == 0 && !search.input.drawsBackground, "search results keep Telegram's single surface while editing")
        let child = ViewController()
        child.loadViewIfNeeded(NSRect(x: 0, y: 0, width: 600, height: 700))
        child.readyOnce()
        navigation.push(child, false)
        settle { navigation.controller === child }
        navigation.back(animated: false)
        settle { navigation.controller === controller && search.window === host }
        check(search.query == "翻译", "search query survives navigation to a setting and back")
        check(controller.firstResponder() !== search.input && host.firstResponder !== search.input, "returning to settings does not steal focus into search")
        search.change(state: .Focus, false)
        _ = host.makeFirstResponder(search.input)
        search.setString("")
        settle { currentQuery.with { $0 }.isEmpty }
        check(host.firstResponder === search.input && search.query.isEmpty, "clearing results preserves Telegram search focus")
    }

    static func settingsHome(width: CGFloat, palette: String, output: URL) throws {
        var opened: [String] = []
        let entries = regramSettingsHomeEntries(query: "", language: fixtureLanguage, update: { _ in }, open: { opened.append($0) })
        let items = regramNativeEntries(entries).map { $0.item(arguments: InputDataArguments(select: { _ in }, dataUpdated: {}), initialSize: NSSize(width: width, height: 700)) }
        let root = View(frame: NSRect(x: 0, y: 0, width: width, height: 1))
        root.backgroundColor = theme.colors.listBackground
        var y: CGFloat = 0
        for item in items {
            _ = item.makeSize(width)
            let view = (item.viewClass() as! TableRowView.Type).init(frame: NSRect(x: 0, y: y, width: width, height: item.height))
            view.set(item: item)
            root.addSubview(view)
            view.updateLayout(size: view.frame.size, transition: .immediate)
            view.layout()
            y += item.height
            if let row = view as? RegramNativeRowView, item is RegramNativeRowItem {
                check(!allSubviews(row).contains { $0 is NSSwitch || $0 is NSPopUpButton }, "home navigation rows do not create hidden toggle or popup controls")
                let action = allSubviews(row).compactMap { $0 as? NSButton }.first { !$0.isHidden }!
                formAction(action)
            }
        }
        root.setFrameSize(NSSize(width: width, height: y + 16))
        check(opened.contains("pro.messages") && opened.contains("localGifts") && Set(opened).count == opened.count, "home categories keep unique working destinations")
        try layerComposite(root, path: output.appendingPathComponent("settings-home-\(palette)-\(Int(width)).png"))
    }

    static func scrollingWorkload(output: URL) throws {
        let choices = (0..<250).map { ContextMenuItem("Service model \($0)", state: $0 == 125 ? .on : .off) }
        let rows = (0..<240).map { index -> RegramNativeRowItem in
            let type: GeneralInteractedType
            switch index % 3 {
            case 0: type = .next
            case 1: type = .switchable(true)
            default: type = .contextSelector("Service model 125", choices)
            }
            return RegramNativeRowItem(NSSize(width: 600, height: 50), stableId: "scroll.\(index)", data: .init(name: "Setting \(index)", color: theme.colors.text, type: type, viewType: .singleItem, action: {}))
        }
        for row in rows { _ = row.makeSize(600) }
        let view = makeView(rows[0], width: 600)
        var bindSamples: [Double] = []
        for pass in 0..<6 {
            let start = CACurrentMediaTime()
            for item in rows {
                view.set(item: item)
                view.setFrameSize(NSSize(width: 600, height: item.height))
                view.updateLayout(size: view.frame.size, transition: .immediate)
                view.layout()
            }
            if pass > 0 { bindSamples.append((CACurrentMediaTime() - start) * 1000) }
        }
        let table = TableView(frame: NSRect(x: 0, y: 0, width: 600, height: 600))
        let host = NSWindow(contentRect: table.frame, styleMask: .borderless, backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.contentView = table
        defer { host.contentView = nil; host.close() }
        table.insert(items: rows, redraw: true)
        table.layoutSubtreeIfNeeded()
        var scrollSamples: [Double] = []
        var visibleRows = Set<Int>()
        for index in 0..<180 {
            let progress = CGFloat(index < 90 ? index : 179 - index) / 89
            let start = CACurrentMediaTime()
            table.contentView.scroll(to: NSPoint(x: 0, y: max(0, table.listHeight - 600) * progress))
            table.reflectScrolledClipView(table.contentView)
            table.layoutSubtreeIfNeeded()
            table.documentView?.layoutSubtreeIfNeeded()
            table.enumerateViews { row in row.layoutSubtreeIfNeeded(); return true }
            scrollSamples.append((CACurrentMediaTime() - start) * 1000)
            visibleRows.insert(table.visibleRows().location)
        }
        check(visibleRows.count > 50, "scroll workload traverses the long native table in both directions")
        let navigation = makeView(rows[0], width: 600)
        let popupView = makeView(rows[2], width: 600)
        let popup = allSubviews(popupView).compactMap { $0 as? NSPopUpButton }.first!
        let sorted = scrollSamples.sorted()
        let report: [String: Any] = [
            "rowCount": rows.count, "menuChoicesPerRow": choices.count,
            "bind240RowsMilliseconds": bindSamples,
            "scrollStepMilliseconds": ["median": sorted[sorted.count / 2], "p95": sorted[Int(Double(sorted.count - 1) * 0.95)], "max": sorted.last!],
            "navigationControlCount": allSubviews(navigation).filter { $0 is NSControl }.count,
            "boundPopupMenuItemCount": popup.numberOfItems,
            "distinctVisibleStarts": visibleRows.count,
            "limitations": "Optimized Release/STABLE native rows and hidden NSTableView; measures main-thread CPU work, not display FPS or real gesture hitches."
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("scroll-workload.json"))
    }
}
