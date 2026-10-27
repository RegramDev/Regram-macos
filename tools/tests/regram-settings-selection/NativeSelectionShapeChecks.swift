import Cocoa
import GeneralRows
import TGUIKit
import TelegramTheme
import TelegramIconsTheme
import SwiftSignalKit
import ColorPalette
import InAppSettings
import ThemeSettings

enum ShortcutEntry {
    case savedMessages(index: Int, viewType: GeneralViewType)
    case bookmarks(index: Int, viewType: GeneralViewType)

    var name: String {
        switch self {
        case .savedMessages: return "Saved Messages"
        case .bookmarks: return "Bookmarks"
        }
    }

    var viewType: GeneralViewType {
        switch self {
        case let .savedMessages(_, value), let .bookmarks(_, value): return value
        }
    }
}

final class SelectionDelegate: TableViewDelegate {
    func selectionDidChange(row: Int, item: TableRowItem, byClick: Bool, isNew: Bool) {}
    func selectionWillChange(row: Int, item: TableRowItem, byClick: Bool) -> Bool { true }
    func isSelectable(row: Int, item: TableRowItem) -> Bool { true }
}

@main
struct NativeSelectionShapeChecks {
    static var checks = 0
    static var failures: [String] = []
    static var measurements: [[String: Any]] = []

    static func check(_ value: @autoclosure () -> Bool, _ name: String) {
        checks += 1
        if !value() { failures.append(name); print("FAIL \(name)") }
    }

    static func near(_ left: CGFloat, _ right: CGFloat) -> Bool { abs(left - right) < 0.01 }

    static func colorDistance(_ left: NSColor, _ right: NSColor) -> CGFloat {
        guard let a = left.usingColorSpace(.deviceRGB), let b = right.usingColorSpace(.deviceRGB) else { return 1 }
        return max(abs(a.redComponent - b.redComponent), abs(a.greenComponent - b.greenComponent), abs(a.blueComponent - b.blueComponent), abs(a.alphaComponent - b.alphaComponent))
    }

    static func measure(_ entries: [ShortcutEntry], items: [GeneralInteractedRowItem], table: TableView, host: NSWindow, name: String) {
        host.layoutIfNeeded()
        table.layoutSubtreeIfNeeded()
        for (entry, item) in zip(entries, items) {
            let label = name + "/" + entry.name
            guard let row = item.viewNecessary as? GeneralInteractedRowView else {
                check(false, label + "/native-row-available")
                continue
            }
            row.updateLayout(size: row.frame.size, transition: .immediate)
            row.updateColors()
            row.layoutSubtreeIfNeeded()
            let container = row.containerView
            guard let mask = container.layer?.mask as? CAShapeLayer, let path = mask.path else {
                check(false, label + "/native-mask-available")
                continue
            }
            let rect = container.frame
            let expectedWidth = min(CGFloat(600), row.frame.width - 24)
            check(near(rect.minX, (row.frame.width - expectedWidth) / 2) && near(rect.width, expectedWidth), label + "/container-horizontal-CGRect")
            check(near(rect.minY, 0) && near(rect.height, item.height), label + "/container-vertical-CGRect")
            let maskBounds = path.boundingBoxOfPath
            check(near(maskBounds.minX, container.bounds.minX) && near(maskBounds.minY, container.bounds.minY) && near(maskBounds.width, container.bounds.width) && near(maskBounds.height, container.bounds.height), label + "/native-mask-CGRect")
            let bounds = container.bounds
            let corners = [CGPoint(x: 1, y: 1), CGPoint(x: bounds.maxX - 1, y: 1), CGPoint(x: 1, y: bounds.maxY - 1), CGPoint(x: bounds.maxX - 1, y: bounds.maxY - 1)]
            let squareCorners = corners.map { path.contains($0) }
            check(squareCorners.allSatisfy { !$0 }, label + "/four-rounded-corners")
            check(container.morphCorners.rawValue == 15, label + "/native-four-corner-mask")
            let interior = [CGPoint(x: bounds.midX, y: bounds.midY), CGPoint(x: bounds.midX, y: 1), CGPoint(x: bounds.midX, y: bounds.maxY - 1), CGPoint(x: 1, y: bounds.midY), CGPoint(x: bounds.maxX - 1, y: bounds.midY)]
            check(interior.allSatisfy { path.contains($0) }, label + "/native-pill-interior")
            let expectedColor = item.isSelected ? theme.colors.accent : NSColor.clear
            let background = container.layer?.backgroundColor.flatMap { NSColor(cgColor: $0) } ?? .clear
            check(row.isSelect == item.isSelected, label + "/native-selection-state")
            check(colorDistance(background, expectedColor) < 0.01, label + "/native-selected-background")
            measurements.append(["name": label, "selected": item.isSelected, "row": NSStringFromRect(row.frame), "container": NSStringFromRect(rect), "maskBounds": NSStringFromRect(path.boundingBoxOfPath), "cornerMask": container.morphCorners.rawValue, "squareCornersTopLeftTopRightBottomLeftBottomRight": squareCorners, "backgroundAlpha": background.alphaComponent])
        }
        check(!host.isVisible && !host.isKeyWindow && !host.isMainWindow, name + "/hidden-host")
    }

    static func scenario(width: CGFloat, enabled: Bool, paletteName: String, previous: Bool) {
        let entries = previous ? previousShortcutEntries(bookmarksEnabled: enabled) : productionShortcutEntries(bookmarksEnabled: enabled)
        check(entries.count == (enabled ? 2 : 1), "\(paletteName)/\(width)/flag-\(enabled)/production-row-count")
        let table = TableView(frame: NSRect(x: 0, y: 0, width: width, height: 180))
        let delegate = SelectionDelegate()
        table.delegate = delegate
        let items = entries.map { entry in
            GeneralInteractedRowItem(NSSize(width: width, height: 44), stableId: entry.name, name: entry.name, type: .next, viewType: entry.viewType, inset: productionShortcutInset(), customTheme: .initialize(theme, background: .clear))
        }
        for item in items { _ = table.addItem(item: item) }
        let host = NSWindow(contentRect: table.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        host.isReleasedWhenClosed = false
        host.appearance = theme.appearance
        host.contentView = table
        defer { table.delegate = nil; host.contentView = nil; host.close() }
        let name = "\(paletteName)/\(Int(width))/flag-\(enabled)"
        measure(entries, items: items, table: table, host: host, name: name + "/before")
        if let first = items.first {
            check(table.select(item: first, notify: false), name + "/select-saved")
            check(first.isSelected && items.dropFirst().allSatisfy { !$0.isSelected }, name + "/saved-exclusive-selection")
            measure(entries, items: items, table: table, host: host, name: name + "/saved-selected")
        }
        if items.count == 2 {
            check(table.select(item: items[1], notify: false), name + "/select-bookmarks")
            check(items[1].isSelected && !items[0].isSelected, name + "/bookmarks-exclusive-selection")
            measure(entries, items: items, table: table, host: host, name: name + "/bookmarks-selected")
        }
        table.cancelSelection()
        check(items.allSatisfy { !$0.isSelected }, name + "/deselected")
        measure(entries, items: items, table: table, host: host, name: name + "/after-deselect")
    }

    static func main() throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        System.updateScaleFactor(2)
        System.liquidGlass = false
        GeneralRowsHooks.install(.placeholder)
        TelegramThemeHooks.install(TelegramThemeHooks(image: nativeThemeImage, icons: generateIcons, sendingFrame: generateSendingFrame, clockMinImage: generateClockMinImage, chatGroupToggleSelected: { generateChatGroupToggleSelected(foregroundColor: $0, backgroundColor: $1) }, chatGroupToggleUnselected: { generateChatGroupToggleUnselected(foregroundColor: $0, backgroundColor: $1) }, setDefaultTheme: { _ in }, liteMode: { .standart }, darkAppearance: { theme }, liveStreamBadgeColor: { .systemRed }))
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let previous = CommandLine.arguments.contains("--previous-grouping")
        for (name, palette) in [("light", dayClassicPalette), ("dark", darkPalette)] {
            telegramUpdateTheme(generateTheme(palette: palette, cloudTheme: nil, bubbled: false, fontSize: 13, wallpaper: ThemeWallpaper(), liquidGlass: false), animated: false)
            check(theme.colors.background != theme.colors.listBackground, name + "/native-rounded-card-mode")
            for width: CGFloat in [320, 600, 800] {
                scenario(width: width, enabled: true, paletteName: name, previous: previous)
                scenario(width: width, enabled: false, paletteName: name, previous: previous)
            }
        }
        check(NSApp.activationPolicy() == .prohibited, "activation-prohibited")
        check(NSApp.windows.allSatisfy { !$0.isVisible && !$0.isKeyWindow && !$0.isMainWindow }, "all-windows-hidden")
        let report: [String: Any] = ["checks": checks, "failures": failures, "measurements": measurements, "previousGrouping": previous]
        let path = output.appendingPathComponent(previous ? "previous-report.json" : "report.json")
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: path)
        print("Native settings selection shape: \(checks) checks, \(failures.count) failures, report=\(path.path)")
        if !failures.isEmpty { exit(EXIT_FAILURE) }
    }
}
