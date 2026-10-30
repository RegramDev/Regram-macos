import Cocoa
import TGUIKit
import GeneralRows
import InputDataUI
import TelegramCore
import Postbox
import RegramCore
import SwiftSignalKit

extension NativeUIChecks {
    static func productionCategoryPages(output: URL) throws {
        let cases = [
            ("messages", ["messageActions", "chatList", "folders"], ["messageBookmarksEnabled", "compactChatList", "native.foldersAtBottom"]),
            ("media", ["media", "photos", "stickers", "recording"], ["defaultVideoQuality", "outgoingPhotoQuality", "stickerSize", "forceBuiltInMic"])
        ]
        for (category, names, keys) in cases {
            let initial = RegramMessageMediaState(settings: RegramAccountSettings(), tab: names[0])
            let state = Atomic(value: initial)
            let promise = ValuePromise(initial, ignoreRepeated: true)
            var writes = 0
            var opens = 0
            let arguments = RegramMessageMediaArguments(context: RegramCategoryFixtureContext(peerId: PeerId(283388)), set: { _, _ in writes += 1 }, toggle: { _ in writes += 1 }, tab: { tab in
                promise.set(state.modify { value in
                    var value = value
                    value.tab = tab
                    return value
                })
            }, open: { _ in opens += 1 })
            let controller = RegramFormController(dataSignal: promise.get() |> map {
                InputDataSignalValue(entries: regramMessageMediaEntries($0, category: category, arguments: arguments))
            }, title: category, hasDone: false)
            let host = Window(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
            host.isReleasedWhenClosed = false
            let navigation = NavigationViewController(controller, host)
            navigation.loadViewIfNeeded(host.contentLayoutRect)
            host.contentView = navigation.view
            defer { host.contentView = nil; host.close() }
            func settle(_ condition: () -> Bool) {
                let end = Date().addingTimeInterval(3)
                while !condition() && Date() < end { _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01)) }
            }
            let id = InputDataEntryId.custom(InputDataIdentifier("parity_tabs"))
            settle { controller.tableView.item(stableId: id) != nil }
            let view = controller.tableView.item(stableId: id)!.viewNecessary!
            let segments = allSubviews(view).compactMap { $0 as? GlassSegmentView }.first!
            for index in Array(names.indices.reversed()) + Array(names.indices) {
                let tabs = view.accessibilityChildren()!.compactMap { $0 as? NSAccessibilityElement }
                check(tabs[index].accessibilityPerformPress(), "\(category)/\(names[index]) category press is accepted")
                let expectedId = InputDataEntryId.custom(InputDataIdentifier("parity_" + keys[index]))
                settle { state.with { $0.tab } == names[index] && controller.tableView.item(stableId: expectedId) != nil && segments.selectedIndex == index }
                check(state.with { $0.tab } == names[index] && controller.tableView.item(stableId: expectedId) != nil && segments.selectedIndex == index, "\(category)/\(names[index]) click updates selected state and actual production page content")
                for other in names.indices where other != index {
                    check(controller.tableView.item(stableId: InputDataEntryId.custom(InputDataIdentifier("parity_" + keys[other]))) == nil, "\(category)/\(names[index]) previous tab content is removed")
                }
            }
            let old = view.accessibilityChildren()!.compactMap { $0 as? NSAccessibilityElement }.first!
            let replacement = regramSegmentedRowItem(NSSize(width: 600, height: 50), stableId: "different.category", labels: ["Another", "Category"], selected: 0, changed: { _ in writes += 1 })
            view.set(item: replacement, animated: false)
            view.layout()
            check(!old.accessibilityPerformPress() && writes == 0, "\(category) retained accessibility actions cannot affect a rebound category")
            check(opens == 0 && writes == 0, "\(category) switching tabs does not persist preferences or open external features")
            check(!host.isVisible && !host.isKeyWindow, "\(category) production category regressions keep the window hidden")
        }
        let labels = (0..<8).map { "Localized category with a long title \($0)" }
        for width: CGFloat in [220, 320, 600] {
            var selected: [Int] = []
            let row = makeView(regramSegmentedRowItem(NSSize(width: width, height: 50), stableId: "long.categories", labels: labels, selected: 7, changed: { selected.append($0) }), width: width)
            let segments = allSubviews(row).compactMap { $0 as? GlassSegmentView }.first!
            let scroll = allSubviews(row).compactMap { $0 as? HorizontalScrollView }.first!
            let frame = segments.convert(segments.itemFrames[7], to: scroll.documentView!)
            check(scroll.documentOffset.x > 0 && frame.intersects(scroll.clipView.bounds), "\(width) long categories reveal the selected tab instead of truncating titles")
            let tabs = row.accessibilityChildren()!.compactMap { $0 as? NSAccessibilityElement }
            _ = tabs[0].accessibilityPerformPress()
            check(selected == [0] && scroll.documentOffset.x == 0, "\(width) first category remains selectable after scrolling")
        }
    }
}
