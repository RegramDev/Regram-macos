import Cocoa
import TGUIKit
import GeneralRows
import InputDataUI
import TelegramTheme
import TelegramIconsTheme
import SwiftSignalKit
import ColorPalette
import InAppSettings
import ThemeSettings
import RegramCore

func regramString(_ key: String) -> String { key }

private enum NativeCheckError: Error {
    case failed(String)
}

@main
struct NativeUIChecks {
    static var checks = 0
    static var failures: [String] = []
    static var measurements: [[String: Any]] = []

    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        checks += 1
        if !condition() { failures.append(name); print("FAIL \(name)") }
    }

    static func allSubviews(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + allSubviews($0) }
    }

    static func makeView(_ item: TableRowItem, width: CGFloat) -> GeneralContainableRowView {
        _ = item.makeSize(width, oldWidth: 0)
        let view = (item.viewClass() as! TableRowView.Type).init(frame: NSRect(x: 0, y: 0, width: width, height: item.height)) as! GeneralContainableRowView
        view.set(item: item, animated: false)
        view.updateLayout(size: view.frame.size, transition: .immediate)
        view.layout()
        return view
    }

    static func png(_ image: CGImage, path: URL) throws {
        try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: path)
    }

    static func render(_ view: NSView, path: URL) throws {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw NativeCheckError.failed("bitmap unavailable") }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: path)
    }

    static func layerComposite(_ view: NSView, path: URL) throws -> CGImage {
        let host = NSWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.contentView = view
        defer { host.contentView = nil; host.close() }
        host.layoutIfNeeded()
        host.displayIfNeeded()
        view.layoutSubtreeIfNeeded()
        for child in [view] + allSubviews(view) {
            child.displayIfNeeded()
            child.layer?.layoutIfNeeded()
            child.layer?.displayIfNeeded()
        }
        CATransaction.flush()
        check(!host.isVisible && !host.isKeyWindow && !host.isMainWindow, "native layer host remains hidden/inactive")
        let scale = System.backingScale
        guard let layer = view.layer, let context = CGContext(data: nil, width: Int(view.bounds.width * scale), height: Int(view.bounds.height * scale), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw NativeCheckError.failed("native layer composite unavailable") }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: view.bounds.height)
        context.scaleBy(x: 1, y: -1)
        layer.render(in: context)
        guard let image = context.makeImage() else { throw NativeCheckError.failed("native layer image unavailable") }
        try png(image, path: path)
        return image
    }

    static func colorDistance(_ left: NSColor, _ right: NSColor) -> CGFloat {
        let a = left.usingColorSpace(.deviceRGB)!
        let b = right.usingColorSpace(.deviceRGB)!
        return max(abs(a.redComponent - b.redComponent), abs(a.greenComponent - b.greenComponent), abs(a.blueComponent - b.blueComponent), abs(a.alphaComponent - b.alphaComponent))
    }

    static func searchSurface(_ view: SearchRowView, card: GeneralContainableRowView, width: CGFloat, name: String, output: URL, fixed: Bool) throws {
        let host = View(frame: NSRect(x: 0, y: 0, width: width, height: 120))
        host.backgroundColor = theme.colors.listBackground
        host.addSubview(view)
        card.frame.origin.y = 60
        host.addSubview(card)
        let image = try layerComposite(host, path: output.appendingPathComponent("search-layers-\(name).png"))
        let bitmap = NSBitmapImageRep(cgImage: image)
        let scale = CGFloat(bitmap.pixelsWide) / width
        let outside = bitmap.colorAt(x: Int(width / 2 * scale), y: Int(5 * scale))!
        let fieldCenter = bitmap.colorAt(x: Int(width / 2 * scale), y: Int(12 * scale))!
        let nativeField = view.convert(view.searchView.bounds, from: view.searchView)
        let containerAlpha = view.containerView.layer?.backgroundColor?.alpha ?? 0
        check(colorDistance(fieldCenter, view.searchView.backgroundColor) < 0.03, "\(name) layer compositor captures actual search background")
        if fixed {
            check(containerAlpha == 0 && view.containerView.backgroundColor.alphaComponent == 0, "\(name) native outer container is transparent")
            check(colorDistance(outside, theme.colors.listBackground) < 0.03, "\(name) no outer capsule pixels above search")
            check(nativeField.minX == card.containerView.frame.minX && nativeField.width == card.containerView.frame.width, "\(name) visible search matches native card width")
            check(abs(nativeField.midX - width / 2) < 1, "\(name) visible search is centered")
        } else {
            check(containerAlpha > 0 && nativeField.width < card.containerView.frame.width, "\(name) old double capsule negative control detected")
            if colorDistance(theme.colors.background, theme.colors.listBackground) > 0.03 {
                check(colorDistance(outside, theme.colors.background) < 0.03 && colorDistance(outside, theme.colors.listBackground) > 0.03, "\(name) native layer composite exposes old outer capsule")
            }
        }
        measurements.append(["kind": "searchLayerComposite", "name": name, "paneWidth": width, "field": NSStringFromRect(nativeField), "card": NSStringFromRect(card.containerView.frame), "containerAlpha": containerAlpha, "outsideDistanceFromList": colorDistance(outside, theme.colors.listBackground), "fieldPixelDistance": colorDistance(fieldCenter, view.searchView.backgroundColor), "fixed": fixed])
        view.removeFromSuperview()
        card.removeFromSuperview()
    }

    static func searchAppearance(output: URL) throws {
        var query = ""
        var setupCalls = 0
        var transactionCalls = 0
        let identifier = InputDataIdentifier("appearance.search")
        let controller = InputDataController(dataSignal: .never(), title: "Native search appearance", hasDone: false)
        controller.tableView.afterSetupItem = { _, _ in setupCalls += 1 }
        controller.afterTransaction = { _ in transactionCalls += 1 }
        regramRestoreSearchQuery(controller, identifier: identifier, query: { query })
        controller.didLoad(controller, [:])
        let arguments = InputDataArguments(select: { _ in }, dataUpdated: {})
        func item(_ width: CGFloat, _ type: GeneralViewType = .singleItem) -> TableRowItem {
            regramSearchEntry(sectionId: 1, index: 0, value: query, identifier: identifier, viewType: type, update: { query = $0 }).item(arguments: arguments, initialSize: NSSize(width: width, height: 50))
        }
        let row = makeView(item(600), width: 600) as! SearchRowView
        let card = makeView(GeneralInteractedRowItem(NSSize(width: 600, height: 44), stableId: "search-card", name: "Native setting", type: .next, viewType: .singleItem), width: 600)
        for (paletteName, palette) in [("light", dayClassicPalette), ("dark", darkPalette), ("light-return", dayClassicPalette)] {
            telegramUpdateTheme(generateTheme(palette: palette, cloudTheme: nil, bubbled: false, fontSize: 13, wallpaper: ThemeWallpaper(), liquidGlass: false), animated: false)
            row.updateColors()
            row.searchView.updateLocalizationAndTheme(theme: theme)
            let cardItem = GeneralInteractedRowItem(NSSize(width: card.frame.width, height: 44), stableId: "search-card", name: "Native setting", type: .next, viewType: .singleItem)
            _ = cardItem.makeSize(card.frame.width, oldWidth: 0)
            card.set(item: cardItem, animated: false)
            controller.tableView.afterSetupItem?(row, row.item!)
            for width: CGFloat in [320, 600, 1000, 320] {
                for current in [row, card] {
                    current.setFrameSize(NSSize(width: width, height: current.frame.height))
                    current.updateLayout(size: current.frame.size, transition: .immediate)
                    current.layout()
                }
                try searchSurface(row, card: card, width: width, name: "\(paletteName)-\(Int(width))-resize", output: output, fixed: true)
            }
            let replacement = item(320, .lastItem)
            row.set(item: replacement, animated: false)
            controller.tableView.afterSetupItem?(row, replacement)
            row.layout()
            try searchSurface(row, card: card, width: 320, name: "\(paletteName)-320-reused", output: output, fixed: true)
            if paletteName != "light-return" {
                let old = makeView(SearchRowItem(NSSize(width: 320, height: 50), stableId: "old-search", searchInteractions: SearchInteractions({ _, _ in }, { _ in }), viewType: .singleItem), width: 320) as! SearchRowView
                try searchSurface(old, card: card, width: 320, name: "\(paletteName)-320-negative", output: output, fixed: false)
            }
        }
        controller.tableView.frame = NSRect(x: 0, y: 0, width: 600, height: 120)
        let attached = item(600)
        _ = controller.tableView.addItem(item: attached, redraw: true)
        guard let native = attached.viewNecessary as? SearchRowView else { throw NativeCheckError.failed("native transaction row unavailable") }
        native.updateColors()
        controller.afterTransaction(controller)
        check(native.containerView.layer?.backgroundColor?.alpha == 0, "afterTransaction reapplies transparent native search after theme update")
        check(transactionCalls == 1 && setupCalls >= 6, "search appearance preserves transaction/setup callback chain")
    }

    static func iconMetrics(_ image: CGImage, name: String, requireBottomNotch: Bool = true) -> [String: Any] {
        let bitmap = NSBitmapImageRep(cgImage: image)
        var white: [(Int, Int)] = []
        var colored = 0
        var opaque = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.9 else { continue }
                opaque += 1
                if color.redComponent > 0.88 && color.greenComponent > 0.88 && color.blueComponent > 0.88 { white.append((x, y)) }
                if color.blueComponent - color.redComponent > 0.2 { colored += 1 }
            }
        }
        let minX = white.map { $0.0 }.min() ?? 0
        let maxX = white.map { $0.0 }.max() ?? 0
        let minY = white.map { $0.1 }.min() ?? 0
        let maxY = white.map { $0.1 }.max() ?? 0
        let centerX = (minX + maxX) / 2
        let centers = white.filter { abs($0.0 - centerX) <= 1 }.map { $0.1 }
        let topGap = (centers.min() ?? minY) - minY
        let bottomGap = maxY - (centers.max() ?? maxY)
        check(colored > opaque / 2, "\(name) blue background, no white block")
        check(white.count > 20 && white.count < opaque / 2, "\(name) visible bounded white glyph")
        if requireBottomNotch { check(bottomGap > topGap + 1, "\(name) bottom notch") }
        return ["name": name, "width": bitmap.pixelsWide, "whitePixels": white.count, "bluePixels": colored, "opaquePixels": opaque, "whiteBounds": [minX, minY, maxX, maxY], "topCenterGap": topGap, "bottomCenterGap": bottomGap]
    }

    static func renderIcon(_ image: CGImage, name: String, output: URL) throws -> CGImage {
        let item = GeneralInteractedRowItem(NSSize(width: 320, height: 44), stableId: name, name: name, icon: image, type: .next, viewType: .singleItem)
        let row = makeView(item, width: 320)
        row.layoutSubtreeIfNeeded()
        guard let bitmap = row.bitmapImageRepForCachingDisplay(in: row.bounds) else { throw NativeCheckError.failed("native account icon bitmap unavailable") }
        row.cacheDisplay(in: row.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("row-\(name).png"))
        let size = image.systemSize
        let rect = NSRect(x: item.viewType.innerInset.left, y: row.focus(size).minY, width: size.width, height: size.height)
        let scale = System.backingScale
        guard let context = CGContext(data: nil, width: Int(row.containerView.bounds.width * scale), height: Int(row.containerView.bounds.height * scale), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), let layer = row.containerView.layer else { throw NativeCheckError.failed("native layer callback context unavailable") }
        context.scaleBy(x: scale, y: scale)
        check(row.containerView.isFlipped, "native row uses flipped view coordinates")
        context.translateBy(x: 0, y: row.containerView.bounds.height)
        context.scaleBy(x: 1, y: -1)
        row.draw(layer, in: context)
        let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
        guard let cropped = context.makeImage()?.cropping(to: pixels) else { throw NativeCheckError.failed("native account icon crop unavailable") }
        try png(cropped, path: output.appendingPathComponent("native-icon-\(name).png"))
        return cropped
    }

    static func geometry(width: CGFloat, paletteName: String, output: URL) throws {
        let controller = InputDataController(dataSignal: .never(), title: "Native geometry", hasDone: false)
        var didLoadCalls = 0
        var setupCalls = 0
        var transactionCalls = 0
        controller.didLoad = { _, _ in didLoadCalls += 1 }
        controller.afterTransaction = { _ in transactionCalls += 1 }
        controller.tableView.afterSetupItem = { _, _ in setupCalls += 1 }
        regramConfigureSegmentedRows(controller)
        regramRestoreSearchQuery(controller, identifier: InputDataIdentifier("geometry.search"), query: { "" })
        controller.didLoad(controller, [:])
        let arguments = InputDataArguments(select: { _ in }, dataUpdated: {})
        let entry = regramSearchEntry(sectionId: 1, index: 0, value: "", identifier: InputDataIdentifier("geometry.search"), update: { _ in })
        let searchItem = entry.item(arguments: arguments, initialSize: NSSize(width: width, height: 50))
        let search = makeView(searchItem, width: width) as! SearchRowView
        controller.tableView.afterSetupItem?(search, searchItem)
        let cardItem = GeneralInteractedRowItem(NSSize(width: width, height: 44), stableId: "card", name: "Native setting", type: .next, viewType: .singleItem)
        let card = makeView(cardItem, width: width)
        check(search.containerView.frame.minX == card.containerView.frame.minX && search.containerView.frame.width == card.containerView.frame.width, "\(paletteName)/\(Int(width)) search matches native card")
        check(abs(search.containerView.frame.midX - width / 2) < 1, "\(paletteName)/\(Int(width)) search centered")
        check(search.containerView.frame.width == min(600, width - 40), "\(paletteName)/\(Int(width)) native block width")
        check(search.searchView.frame.width == search.containerView.frame.width, "\(paletteName)/\(Int(width)) visible search matches block")
        check(search.backgroundColor.alphaComponent == 0, "\(paletteName)/\(Int(width)) modern search transparent outer background")
        let root = View(frame: NSRect(x: 0, y: 0, width: width, height: 320))
        root.backgroundColor = theme.colors.listBackground
        root.addSubview(search)
        card.frame.origin.y = 60
        root.addSubview(card)
        var offset: CGFloat = 115
        let groups = [("messages", ["消息操作", "聊天列表", "分组"]), ("media", ["播放与链接", "照片", "贴纸", "录制"]), ("font", ["拉丁字体", "中文字体"])]
        for (name, labels) in groups {
            let item = regramSegmentedRowItem(NSSize(width: width, height: 50), stableId: name, labels: labels, selected: 0, changed: { _ in })
            let row = makeView(item, width: width)
            controller.tableView.afterSetupItem?(row, item)
            guard let segment = row.containerView.subviews.compactMap({ $0 as? ScrollableSegmentView }).first else { throw NativeCheckError.failed("missing native segment") }
            let cells = allSubviews(segment).filter { String(describing: type(of: $0)) == "SegmentItemView" }.sorted { $0.frame.minX < $1.frame.minX }
            check(cells.count == labels.count, "\(name) native cells count")
            check(segment.fitToWidth && segment.theme.border.alphaComponent == 0, "\(name) fitToWidth and transparent baseline")
            check(row.containerView.frame == search.containerView.frame, "\(name) native block centered")
            let frames = cells.map(\.frame)
            let intrinsicWidth = frames.reduce(CGFloat(0)) { $0 + $1.width }
            var gaps: [CGFloat] = []
            if intrinsicWidth < segment.frame.width, let first = frames.first, let last = frames.last {
                gaps = [first.minX] + zip(frames.dropFirst(), frames).map { $0.minX - $1.maxX } + [segment.frame.width - last.maxX]
                check((gaps.max() ?? 0) - (gaps.min() ?? 0) <= CGFloat(labels.count + 1), "\(name) equal distributed gaps")
                check((gaps.min() ?? 0) > 0, "\(name) avoids left packing")
            }
            measurements.append(["kind": "segment", "palette": paletteName, "paneWidth": width, "name": name, "count": cells.count, "block": NSStringFromRect(row.containerView.frame), "frames": frames.map(NSStringFromRect), "gaps": gaps, "intrinsicWidths": frames.map(\.width), "borderAlpha": segment.theme.border.alphaComponent])
            row.frame.origin.y = offset
            root.addSubview(row)
            offset += 60
        }
        check(didLoadCalls == 1 && setupCalls == groups.count + 1, "native segment hook chains didLoad/setup")
        controller.afterTransaction(controller)
        check(transactionCalls == 1, "native segment hook chains transaction")
        measurements.append(["kind": "search", "palette": paletteName, "paneWidth": width, "block": NSStringFromRect(search.containerView.frame), "field": NSStringFromRect(search.searchView.frame)])
        try render(root, path: output.appendingPathComponent("native-\(paletteName)-\(Int(width)).png"))
    }

    static func searchLifecycle(output: URL) throws {
        var query = "current query"
        var updateCalls = 0
        var setupCalls = 0
        let identifier = InputDataIdentifier("bookmarks_search")
        let controller = InputDataController(dataSignal: .never(), title: "Native search lifecycle", hasDone: false)
        controller.tableView.afterSetupItem = { _, _ in setupCalls += 1 }
        regramRestoreSearchQuery(controller, identifier: identifier, query: { query })
        controller.didLoad(controller, [:])
        let entry = regramSearchEntry(sectionId: 1, index: 0, value: query, identifier: identifier, update: { query = $0; updateCalls += 1 })
        let item = entry.item(arguments: InputDataArguments(select: { _ in }, dataUpdated: {}), initialSize: NSSize(width: 600, height: 50))
        let view = makeView(item, width: 600) as! SearchRowView
        controller.tableView.afterSetupItem?(view, item)
        check(view.searchView.query == "current query" && updateCalls == 0, "new native search binding restores current query without callbacks")
        check(view.searchView.state == .Focus, "restored nonempty native search state stays visible")
        view.searchView.setString("old recycled text")
        query = "latest retained query"
        let beforeRecycleCalls = updateCalls
        controller.tableView.afterSetupItem?(view, item)
        check(view.searchView.query == query && updateCalls == beforeRecycleCalls, "recycled native search gets latest query without callbacks")
        view.searchView.input.setSelectedRange(NSRange(location: 3, length: 0))
        let selection = view.searchView.input.selectedRange()
        controller.tableView.afterSetupItem?(view, item)
        check(view.searchView.input.selectedRange() == selection, "equal query binding preserves caret")
        view.searchView.input.setMarkedText(NSAttributedString(string: "输入中"), selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let markedText = view.searchView.query
        let markedRange = view.searchView.input.markedRange()
        query = "state changed during composition"
        controller.tableView.afterSetupItem?(view, item)
        check(view.searchView.input.hasMarkedText() && view.searchView.query == markedText && view.searchView.input.markedRange() == markedRange, "native IME marked text is not overwritten on binding")
        telegramUpdateTheme(generateTheme(palette: darkPalette, cloudTheme: nil, bubbled: false, fontSize: 13, wallpaper: ThemeWallpaper(), liquidGlass: false), animated: false)
        view.updateColors()
        view.searchView.updateLocalizationAndTheme(theme: theme)
        controller.tableView.afterSetupItem?(view, item)
        check(view.searchView.input.hasMarkedText() && view.searchView.query == markedText && view.searchView.input.markedRange() == markedRange && view.containerView.layer?.backgroundColor?.alpha == 0, "theme change preserves native IME composition and transparent container")
        view.setFrameSize(NSSize(width: 320, height: view.frame.height))
        view.updateLayout(size: view.frame.size, transition: .immediate)
        view.layout()
        check(view.searchView.input.hasMarkedText() && view.searchView.query == markedText && view.searchView.input.markedRange() == markedRange && view.containerView.layer?.backgroundColor?.alpha == 0, "resize preserves native IME composition and transparent container")
        view.searchView.input.unmarkText()
        query = ""
        controller.tableView.afterSetupItem?(view, item)
        check(view.searchView.query.isEmpty, "state reset clears recycled native field")
        controller.tableView.frame = NSRect(x: 0, y: 0, width: 600, height: 120)
        _ = controller.tableView.addItem(item: item, redraw: true)
        if let native = item.viewNecessary as? SearchRowView {
            native.searchView.setString("explicit reset")
            query = ""
            resetBookmarkSearch(controller)
            check(native.searchView.query.isEmpty, "production bookmark reset clears native viewNecessary field")
        } else {
            failures.append("native table viewNecessary unavailable without window")
        }
        check(setupCalls >= 5, "search afterSetupItem callback remains chained")
        measurements.append(["kind": "searchLifecycle", "setupCalls": setupCalls, "updateCalls": updateCalls, "imeHasMarkedText": !markedRange.isEmpty && markedRange.location != NSNotFound])
        try render(view, path: output.appendingPathComponent("native-search-lifecycle.png"))
    }

    static func searchNavigation(output: URL) throws {
        telegramUpdateTheme(generateTheme(palette: dayClassicPalette, cloudTheme: nil, bubbled: false, fontSize: 13, wallpaper: ThemeWallpaper(), liquidGlass: false), animated: false)
        let identifier = InputDataIdentifier("navigation.search")
        let query = Atomic(value: "")
        let queryState = ValuePromise("", ignoreRepeated: true)
        let signal = queryState.get() |> map { value in
            InputDataSignalValue(entries: [regramSearchEntry(sectionId: 0, index: 0, value: value, identifier: identifier, update: { value in
                _ = query.swap(value)
                queryState.set(value)
            })])
        }
        let controller = InputDataController(dataSignal: signal, title: "Regram Pro", removeAfterDisappear: false, hasDone: false)
        var appearanceCalls = 0
        var responderCalls = 0
        var transactionCalls = 0
        controller.didAppear = { _ in appearanceCalls += 1 }
        controller._externalFirstResponder = { responderCalls += 1; return nil }
        controller.afterTransaction = { _ in transactionCalls += 1 }
        regramRestoreSearchQuery(controller, identifier: identifier, query: { query.with { $0 } })
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let navigation = NavigationViewController(controller, window)
        navigation.loadViewIfNeeded(NSRect(x: 0, y: 0, width: 600, height: 300))
        window.contentView = navigation.view
        defer { window.contentView = nil; window.close() }
        func wait(_ label: String, _ condition: () -> Bool) {
            let end = Date().addingTimeInterval(3)
            while !condition() && Date() < end { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
            check(condition(), label)
        }
        func row() -> SearchRowView? {
            controller.tableView.item(stableId: AnyHashable(InputDataEntryId.custom(identifier)))?.viewNecessary as? SearchRowView
        }
        func layout() {
            window.layoutIfNeeded()
            navigation.view.layoutSubtreeIfNeeded()
            row()?.layout()
            row()?.searchView.layout()
        }
        func child() -> (ViewController, NSTextView) {
            let child = ViewController()
            child.loadViewIfNeeded(NSRect(x: 0, y: 0, width: 600, height: 300))
            let editor = NSTextView(frame: NSRect(x: 20, y: 20, width: 200, height: 30))
            editor.string = "Child page editor"
            child.view.addSubview(editor)
            child.readyOnce()
            return (child, editor)
        }
        func roundtrip() {
            let (child, editor) = child()
            navigation.push(child, false)
            wait("native navigation pushes child", { navigation.controller === child && editor.window === window })
            check(window.makeFirstResponder(editor), "child native editor accepts first responder")
            navigation.back(animated: false)
            wait("native navigation pops to existing Pro controller", { navigation.controller === controller && row()?.window === window })
            layout()
        }
        func snapshot(_ name: String) throws {
            layout()
            let view = navigation.view
            for child in [view] + allSubviews(view) {
                child.displayIfNeeded()
                child.layer?.layoutIfNeeded()
                child.layer?.displayIfNeeded()
            }
            CATransaction.flush()
            let scale = System.backingScale
            guard let layer = view.layer, let context = CGContext(data: nil, width: Int(view.bounds.width * scale), height: Int(view.bounds.height * scale), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw NativeCheckError.failed("navigation layer context unavailable") }
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: 0, y: view.bounds.height)
            context.scaleBy(x: 1, y: -1)
            layer.render(in: context)
            guard let image = context.makeImage() else { throw NativeCheckError.failed("navigation layer image unavailable") }
            try png(image, path: output.appendingPathComponent("search-navigation-\(name).png"))
        }
        wait("real initial transaction loads native search", { controller.didSetReady && row() != nil })
        guard var current = row() else { throw NativeCheckError.failed("navigation search row unavailable") }
        layout()
        check(current.containerView.layer?.backgroundColor?.alpha == 0, "real didLoad configures already-created native search container")
        roundtrip()
        current = row()!
        check(window.firstResponder !== current.searchView.input && current.searchView.state == .None, "empty Pro search returns idle without forced first responder")
        check(current.searchView.rightAccessory.isHidden && current.searchView.input.isHidden, "empty returned search has no stale clear or caret editor")
        try snapshot("light-600-empty-return")
        let document = controller.tableView.documentView
        check(window.makeFirstResponder(document), "native window accepts idle document fallback request")
        for _ in 0..<5 {
            check(controller.firstResponder() === document && controller.firstResponder() === document, "empty return responder remains stable across repeated getter calls")
            window.applyResponderIfNeeded()
            measurements.append(["kind": "searchNavigationResponderPass", "isDocument": window.firstResponder === document, "isSearchInput": window.firstResponder === current.searchView.input, "searchFocused": current.searchView.state == .Focus, "responder": window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil", "nextTarget": controller.firstResponder().map { String(describing: type(of: $0)) } ?? "nil"])
            check(window.firstResponder !== current.searchView.input && current.searchView.state == .None && current.searchView.rightAccessory.isHidden, "repeated native responder application keeps returned search idle")
        }
        current.searchView.change(state: .Focus, false)
        check(window.firstResponder === current.searchView.input && current.searchView.state == .Focus, "explicit empty search click still focuses native editor")
        let beforeQueryTransaction = transactionCalls
        current.searchView.setString("retained query")
        wait("native query update transaction settles", { transactionCalls > beforeQueryTransaction && row()?.searchView.query == "retained query" && query.with { $0 } == "retained query" })
        current = row()!
        current.searchView.input.setSelectedRange(NSRange(location: 3, length: 0))
        let selection = current.searchView.input.selectedRange()
        roundtrip()
        current = row()!
        check(current.searchView.query == "retained query" && current.searchView.input.selectedRange() == selection, "nonempty push pop preserves native query and caret")
        check(window.firstResponder === current.searchView.input, "nonempty returning search restores native editor responder")
        try snapshot("light-600-query-return")
        let beforeClearTransaction = transactionCalls
        current.searchView.cancelSearch()
        wait("native clear updates query state", { transactionCalls > beforeClearTransaction && query.with { $0.isEmpty } && row()?.searchView.query.isEmpty == true })
        current = row()!
        check(window.firstResponder === current.searchView.input, "native clear retains editing so typing can continue")
        let otherEditor = NSTextView(frame: NSRect(x: 20, y: 180, width: 180, height: 30))
        controller.view.addSubview(otherEditor)
        check(window.makeFirstResponder(otherEditor), "another editor within Pro accepts focus")
        check(controller.firstResponder() === otherEditor && current.searchView.state == .None, "existing Pro editor is preserved while empty search resigns")
        window.applyResponderIfNeeded()
        check(window.firstResponder === otherEditor, "native responder reapplication preserves existing Pro editor")
        otherEditor.removeFromSuperview()
        roundtrip()
        check(row()?.searchView.state == .None, "cleared query remains idle after another child return")
        for _ in 0..<5 {
            _ = controller.firstResponder()
            window.applyResponderIfNeeded()
            check(window.firstResponder !== row()?.searchView.input && row()?.searchView.state == .None, "cleared returned search stays idle across repeated native responder passes")
        }
        current = row()!
        current.searchView.change(state: .Focus, false)
        current.searchView.input.setMarkedText(NSAttributedString(string: "输入中"), selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let markedRange = current.searchView.input.markedRange()
        let markedText = current.searchView.query
        for (name, palette) in [("light", dayClassicPalette), ("dark", darkPalette)] {
            telegramUpdateTheme(generateTheme(palette: palette, cloudTheme: nil, bubbled: false, fontSize: 13, wallpaper: ThemeWallpaper(), liquidGlass: false), animated: false)
            for width: CGFloat in [320, 600, 1000] {
                window.setContentSize(NSSize(width: width, height: 300))
                controller.didAppear?(controller)
                controller.afterTransaction(controller)
                current.updateColors()
                current.searchView.updateLocalizationAndTheme(theme: theme)
                controller.afterTransaction(controller)
                layout()
                check(current.searchView.input.hasMarkedText() && current.searchView.query == markedText && current.searchView.input.markedRange() == markedRange, "\(name)/\(width) appearance and resize preserve marked text")
                check(current.containerView.layer?.backgroundColor?.alpha == 0, "\(name)/\(width) appearance keeps single native search surface")
            }
        }
        current.searchView.input.unmarkText()
        check(appearanceCalls >= 5 && responderCalls > 0, "native appear and external responder callbacks remain chained")
        check(!window.isVisible && !window.isKeyWindow && !window.isMainWindow, "navigation fixture window remains hidden and inactive")
        measurements.append(["kind": "searchNavigation", "appearanceCalls": appearanceCalls, "responderCalls": responderCalls, "transactionCalls": transactionCalls, "query": query.with { $0 }, "returnedCaret": NSStringFromRange(selection), "markedTextPreserved": current.searchView.query == markedText])
    }

    static func nativeThemeRows(output: URL) throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 4 { root.deleteLastPathComponent() }
        for name in ["Regram-Paper", "Regram-Graphite"] {
            let path = root.appendingPathComponent("themes/Regram-Quiet/\(name).palette")
            let source = try String(contentsOf: path)
            guard let background = source.components(separatedBy: "\n").first(where: { $0.hasPrefix("background = ") })?.components(separatedBy: " = ").last,
                  let fixed = importPalette(path.path) else { throw NativeCheckError.failed("missing theme \(name)") }
            let baselinePath = output.appendingPathComponent("\(name)-flat-baseline.palette")
            let baselineSource = source.replacingOccurrences(of: "(?m)^listBackground =.*$", with: "listBackground = \(background)", options: .regularExpression)
            try baselineSource.write(to: baselinePath, atomically: true, encoding: .utf8)
            guard let baseline = importPalette(baselinePath.path) else { throw NativeCheckError.failed("missing baseline \(name)") }
            let migrated = regramRepairedThemePalette(baseline)
            let isGraphite = name == "Regram-Graphite"
            check((migrated !== baseline) == isGraphite, "\(name) repair only matches old dark theme")
            check(regramRepairedThemePalette(fixed) === fixed, "\(name) repaired theme remains unchanged")
            check(regramRepairedThemePalette(migrated) === migrated, "\(name) repair is idempotent")
            check(regramRepairedThemePalette(baseline.withUpdatedName("Custom Graphite")).listBackground == baseline.listBackground, "\(name) custom theme remains unchanged")
            if isGraphite {
                check(migrated == fixed, "Graphite migration matches corrected palette")
                let previous = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ThemePaletteSettings.defaultTheme.withUpdatedPalette(baseline))) as! [String: Any]
                let updated = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ThemePaletteSettings.defaultTheme.withUpdatedPalette(migrated))) as! [String: Any]
                var expected = previous["palette"] as! [String: Any]
                expected["listBackground"] = Int32(bitPattern: NSColor(0x1e2127).argb)
                check(NSDictionary(dictionary: expected).isEqual(to: updated["palette"] as! [String: Any]), "Graphite migration preserves every other palette field")
                let customizedPath = output.appendingPathComponent("Graphite-customized.palette")
                let customizedSource = baselineSource.replacingOccurrences(of: "bubbleBackground_outgoing = #2A3748", with: "bubbleBackground_outgoing = #223344,#334455").replacingOccurrences(of: "accent = #5D97D0", with: "accent = #7799BB")
                try customizedSource.write(to: customizedPath, atomically: true, encoding: .utf8)
                guard let customized = importPalette(customizedPath.path) else { throw NativeCheckError.failed("missing customized theme") }
                let customizedRepair = regramRepairedThemePalette(customized)
                check(customized.bubbleBackground_outgoing.count == 2 && customizedRepair.bubbleBackground_outgoing == customized.bubbleBackground_outgoing && customizedRepair.accent == customized.accent, "Graphite repair preserves custom accent and outgoing gradient")
            }
            for (suffix, palette, repaired) in [("fixed", fixed, true), ("baseline", baseline, false), ("migrated", migrated, isGraphite)] {
                telegramUpdateTheme(generateTheme(palette: palette, cloudTheme: nil, bubbled: false, fontSize: 13, wallpaper: ThemeWallpaper(), liquidGlass: false), animated: false)
                let item = GeneralInteractedRowItem(NSSize(width: 600, height: 44), stableId: name + suffix, name: "Native settings row", type: .switchable(false), viewType: .singleItem)
                let view = makeView(item, width: 600)
                check(GeneralViewType.singleItem.isPlainMode == !repaired, "\(name)/\(suffix) native theme mode")
                check(view.borderView.isHidden == repaired, "\(name)/\(suffix) native single row separator")
                check(GeneralViewType.singleItem.corners.isEmpty == !repaired, "\(name)/\(suffix) native row corners")
                let mask = view.containerView.layer?.mask as? CAShapeLayer
                check(mask?.path?.contains(CGPoint(x: 1, y: 1)) == !repaired, "\(name)/\(suffix) real native corner mask")
                _ = try layerComposite(view, path: output.appendingPathComponent("theme-row-\(name)-\(suffix).png"))
                measurements.append(["kind": "nativeThemeRow", "theme": name, "repaired": repaired, "plain": GeneralViewType.singleItem.isPlainMode, "separatorHidden": view.borderView.isHidden])
            }
        }
        for palette in [dayClassicPalette, whitePalette, darkPalette, nightAccentPalette, systemPalette] {
            check(regramRepairedThemePalette(palette) === palette, "\(palette.name) built-in palette remains unchanged")
        }
    }

    static func nativeBottomBar(output: URL) throws {
        final class InsetTrackingController: ViewController {
            var insetUpdates = 0
            var appearances = 0
            var disappearances = 0

            override func updateContainerContentInsets(_ insets: NSEdgeInsets, transition: ContainedViewLayoutTransition) {
                insetUpdates += 1
                super.updateContainerContentInsets(insets, transition: transition)
            }

            override func viewWillAppear(_ animated: Bool) {
                appearances += 1
                super.viewWillAppear(animated)
            }

            override func viewWillDisappear(_ animated: Bool) {
                disappearances += 1
                super.viewWillDisappear(animated)
            }
        }
        for (name, palette) in [("light", dayClassicPalette), ("dark", darkPalette)] {
            telegramUpdateTheme(generateTheme(palette: palette, cloudTheme: nil, bubbled: false, fontSize: 13, wallpaper: ThemeWallpaper(), liquidGlass: false), animated: false)
            let icons = [("Contacts", theme.icons.tab_contacts, theme.icons.tab_contacts_active), ("Calls", theme.icons.tab_calls, theme.icons.tab_calls_active), ("Chats", theme.icons.tab_chats, theme.icons.tab_chats_active), ("Settings", theme.icons.tab_settings, theme.icons.tab_settings_active)]
            for width: CGFloat in [320, 600, 1000] {
                for selectedTitle in ["Chats", "Settings"] {
                    let controller = TabBarController()
                    controller.bar = .init(height: 0)
                    controller._frameRect = NSMakeRect(0, 0, width, 700)
                    controller.loadViewIfNeeded()
                    let items = icons.map { title, image, selectedImage -> TabItem in
                        let child = InsetTrackingController()
                        child.bar = .init(height: 0)
                        let item = TabItem(image: image, selectedImage: selectedImage, controller: child)
                        item.accessibilityTitle = title
                        return item
                    }
                    let selectedItem = items.first { $0.accessibilityTitle == selectedTitle }!
                    let selectedController = selectedItem.controller as! InsetTrackingController
                    let identifiers: [RegramBottomBarItemId] = [.contacts, .calls, .chats, .settings]
                    let tabs = Dictionary(uniqueKeysWithValues: zip(identifiers, items))
                    for visible in [[items[0], items[2], items[3]], [items[2], items[3]], items, [items[2], items[3]], [items[0], items[2], items[3]]] {
                        let preservesCurrent = controller.current === selectedController
                        let previousAppearances = selectedController.appearances
                        let previousDisappearances = selectedController.disappearances
                        let visibleIdentifiers = visible.map { item in identifiers[items.firstIndex { $0 === item }!] }
                        rebuildNativeBottomBar(controller, tabs: tabs, visible: visibleIdentifiers, selected: selectedTitle == "Chats" ? .chats : .settings)
                        controller.updateFrame(NSMakeRect(0, 0, width, 700), transition: .immediate)
                        controller.view.layoutSubtreeIfNeeded()
                        guard let bar = controller.view.subviews.compactMap({ $0 as? TabBarView }).first else { throw NativeCheckError.failed("missing native tab bar") }
                        let expectedWidth = min(500, width - 40)
                        check(bar.frame == NSMakeRect(floorToScreenPixels((width - expectedWidth) / 2), 636, expectedWidth, 48), "\(name)/\(width)/\(visible.count) upstream floating frame")
                        check(controller.contentBottomInset == 64, "\(name)/\(width)/\(visible.count) upstream bottom inset")
                        check(controller.current === selectedController, "\(name)/\(width)/\(visible.count) visibility keeps \(selectedTitle) selected")
                        if preservesCurrent {
                            check(selectedController.appearances == previousAppearances && selectedController.disappearances == previousDisappearances, "\(name)/\(width)/\(visible.count) visibility preserves \(selectedTitle) lifecycle")
                        }
                        for (index, item) in visible.enumerated() {
                            let control = controller.control(for: index)
                            check(allSubviews(control).allSatisfy { !($0 is NSTextField) }, "\(name)/\(width)/\(index) native icon without custom label")
                            check(control.accessibilityLabel() == item.accessibilityTitle && controller.tab(at: index).controller === item.controller, "\(name)/\(width)/\(index) native tab target and accessibility")
                        }
                        let controls = visible.indices.map { controller.control(for: $0) }
                        for showsLabels in [true, false] {
                            for fraction: CGFloat in [0.5, 0.75, 1] {
                                let previousHeight = bar.frame.height
                                let previousInsetUpdates = visible.map { ($0.controller as! InsetTrackingController).insetUpdates }
                                controller.updatePresentation(TabBarPresentation(showsLabels: showsLabels, width: .fraction(fraction)))
                                controller.view.layoutSubtreeIfNeeded()
                                let height: CGFloat = showsLabels ? 64 : 48
                                let requestedWidth = max(min(expectedWidth, CGFloat(visible.count) * 44 + 8), expectedWidth * fraction)
                                check(bar.frame.height == height && bar.frame.maxY == 684, "\(name)/\(width)/\(visible.count)/\(fraction) label height and native bottom gap")
                                check(bar.frame.width == requestedWidth && bar.frame.minX == floorToScreenPixels((width - requestedWidth) / 2), "\(name)/\(width)/\(visible.count)/\(fraction) adjustable centered width")
                                check(controller.contentBottomInset == height + 16, "\(name)/\(width)/\(visible.count)/\(fraction) label content inset")
                                check(controller.current === selectedController, "\(name)/\(width)/\(visible.count)/\(fraction) presentation preserves selected controller")
                                for (index, item) in visible.enumerated() {
                                    let control = controller.control(for: index)
                                    let expectedInsetUpdates = previousInsetUpdates[index] + (previousHeight == height ? 0 : 1)
                                    check((item.controller as! InsetTrackingController).insetUpdates == expectedInsetUpdates, "\(name)/\(width)/\(index) width changes avoid content relayout")
                                    let labels = allSubviews(control).compactMap { $0 as? NSTextField }
                                    check(control === controls[index], "\(name)/\(width)/\(index) presentation reuses native tab controls")
                                    check(labels.count == (showsLabels ? 1 : 0) && labels.allSatisfy { $0.stringValue == item.accessibilityTitle }, "\(name)/\(width)/\(index) label toggle and title")
                                    if let label = labels.first, let icon = control.subviews.first {
                                        check(label.frame.minY >= icon.frame.maxY && label.frame.maxY <= control.bounds.maxY, "\(name)/\(width)/\(index) label fits below icon")
                                    }
                                }
                                if width == 600 && visible.count == 3 && fraction == 0.75 && selectedTitle == "Settings" {
                                    try render(bar, path: output.appendingPathComponent("bottom-bar-\(name)-\(showsLabels ? "labels" : "icons").png"))
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    static func navigationSwitchFeedback() throws {
        let controller = InputDataController(dataSignal: .never(), title: "Native navigation switch feedback", hasDone: false)
        var setupCalls = 0
        controller.tableView.afterSetupItem = { _, _ in setupCalls += 1 }
        regramConfigureNavigationSwitches(controller)
        controller.didLoad(controller, [:])
        var applies = 0
        let item = GeneralInteractedRowItem(NSSize(width: 600, height: 50), name: "Show Labels", type: .switchable(false), viewType: .singleItem, action: { applies += 1 })
        let row = makeView(item, width: 600) as! GeneralInteractedRowView
        controller.tableView.afterSetupItem?(row, item)
        guard let toggle = row.switchView else { throw NativeCheckError.failed("missing native navigation switch") }
        let window = NSWindow(contentRect: row.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = row
        defer { window.contentView = nil; window.close() }
        check(toggle.commitsOnRelease && setupCalls == 1, "navigation production binding enables immediate release and preserves row setup")
        row.invokeAction(item)
        check(toggle.isOn && applies == 1, "navigation label setting applies before its spring finishes")
        toggle.setIsOn(true, animated: false)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            check(allSubviews(toggle).contains { $0.layer?.animation(forKey: "switchPosition") != nil }, "matching settings echo preserves the navigation switch spring")
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1.15))
        check(toggle.isOn && applies == 1, "navigation switch animation completion never applies twice")
        row.invokeAction(item)
        check(!toggle.isOn && applies == 2, "navigation label disable also applies immediately")
        toggle.isEnabled = false
        RunLoop.current.run(until: Date().addingTimeInterval(1.15))
        check(!toggle.isOn && applies == 2, "disabled navigation switch does not replay a committed change")
        check(!window.isVisible && !window.isKeyWindow && !window.isMainWindow, "navigation switch feedback window remains hidden")
    }

    static func main() throws {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        TelegramThemeHooks.install(TelegramThemeHooks(image: nativeThemeImage, icons: generateIcons, sendingFrame: generateSendingFrame, clockMinImage: generateClockMinImage, chatGroupToggleSelected: { generateChatGroupToggleSelected(foregroundColor: $0, backgroundColor: $1) }, chatGroupToggleUnselected: { generateChatGroupToggleUnselected(foregroundColor: $0, backgroundColor: $1) }, setDefaultTheme: { setDefaultTheme(for: $0) }, liteMode: { .standart }, darkAppearance: { theme }, liveStreamBadgeColor: { .systemRed }))
        setDefaultTheme()
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let searchOnly = CommandLine.arguments.contains("--search-only")
        let searchNavigationOnly = CommandLine.arguments.contains("--search-navigation-only")
        if !searchOnly && !searchNavigationOnly {
            try nativeBottomBar(output: output)
            try navigationSwitchFeedback()
            try nativeThemeRows(output: output)
        }
        if searchOnly {
            try searchAppearance(output: output)
        }
        for (name, palette) in searchOnly || searchNavigationOnly ? [] : [("light", dayClassicPalette), ("dark", darkPalette)] {
            telegramUpdateTheme(generateTheme(palette: palette, cloudTheme: nil, bubbled: false, fontSize: 13, wallpaper: ThemeWallpaper(), liquidGlass: false), animated: false)
            for width: CGFloat in [320, 600, 1000] { try geometry(width: width, paletteName: name, output: output) }
            guard let filled = savedSettingsIcon(), let outline = bookmarkSettingsIcon() else { throw NativeCheckError.failed("missing native icons") }
            try png(filled, path: output.appendingPathComponent("icon-\(name)-filled.png"))
            try png(outline, path: output.appendingPathComponent("icon-\(name)-outline.png"))
            measurements.append(iconMetrics(filled, name: "\(name)/raw-filled", requireBottomNotch: false))
            measurements.append(iconMetrics(outline, name: "\(name)/raw-outline", requireBottomNotch: false))
            let filledMetrics = iconMetrics(try renderIcon(filled, name: "\(name)-filled", output: output), name: "\(name)/filled")
            let outlineMetrics = iconMetrics(try renderIcon(outline, name: "\(name)-outline", output: output), name: "\(name)/outline")
            check((filledMetrics["whitePixels"] as! Int) > (outlineMetrics["whitePixels"] as! Int), "\(name) filled/outline glyphs distinguishable")
            measurements += [filledMetrics, outlineMetrics]
            if name == "light", let previous = previousSavedSettingsIcon() {
                let previousMetrics = iconMetrics(try renderIcon(previous, name: "previous-unflipped", output: output), name: "previous-unflipped", requireBottomNotch: false)
                check((previousMetrics["topCenterGap"] as! Int) > (previousMetrics["bottomCenterGap"] as! Int), "native layer negative control catches previous upside-down icon")
                measurements.append(previousMetrics)
            }
        }
        if !searchNavigationOnly { try searchLifecycle(output: output) }
        if !searchOnly { try searchNavigation(output: output) }
        let windows = NSApplication.shared.windows.map { ["class": String(describing: type(of: $0)), "visible": $0.isVisible, "key": $0.isKeyWindow, "main": $0.isMainWindow] as [String: Any] }
        check(NSApplication.shared.windows.allSatisfy { !$0.isVisible && !$0.isKeyWindow && !$0.isMainWindow }, "all own AppKit internal windows remain invisible/inactive")
        check(NSApplication.shared.activationPolicy() == .prohibited, "test activation remains prohibited")
        let report: [String: Any] = ["checks": checks, "failures": failures, "measurements": measurements, "internalWindows": windows, "searchOnly": searchOnly, "searchNavigationOnly": searchNavigationOnly, "limitations": ["fitToWidth distributes intrinsic-width cells with equal gaps; it does not impose equal cell widths", "search-only PNGs use the real native CALayer tree hosted in an invisible NSWindow; no orderFront or activation occurs", "NSView cacheDisplay omits native layer delegate pixels; icon checks invoke the production native row draw callback in its flipped view coordinates", "hidden native navigation exercises responder transfer to another editor; actual key-window caret painting and visible app switching remain untested", "no account or real preferences are used"]]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("report.json"))
        print("Native UI checks: \(checks), failures: \(failures.count), report=\(output.appendingPathComponent("report.json").path)")
        if !failures.isEmpty { exit(EXIT_FAILURE) }
    }
}
