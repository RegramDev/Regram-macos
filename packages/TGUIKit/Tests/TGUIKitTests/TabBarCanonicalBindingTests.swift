import XCTest
import AppKit
@testable import TGUIKit

private final class BoundTabIcon: NSView {
    let asset: CGImage
    var selected = false
    init(asset: CGImage) {
        self.asset = asset
        super.init(frame: NSMakeRect(0, 0, 24, 24))
        let image = NSImageView(frame: bounds)
        image.image = NSImage(cgImage: asset, size: bounds.size)
        addSubview(image)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class BoundTabItem: TabItem {
    override func makeView() -> NSView { BoundTabIcon(asset: image) }
    override func setSelected(_ selected: Bool, for view: NSView, animated: Bool) { (view as? BoundTabIcon)?.selected = selected }
}

private final class BoundTabBadge: Node {
    init() { super.init(View(frame: NSMakeRect(0, 0, 10, 10))) }
}

final class TabBarCanonicalBindingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    private func item(_ title: String, color: NSColor, badge: Bool = false) -> BoundTabItem {
        let context = CGContext(data: nil, width: 24, height: 24, bitsPerComponent: 8, bytesPerRow: 96, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 24, height: 24))
        let image = context.makeImage()!
        let controller = ViewController()
        controller.bar = .init(height: 0)
        let item = BoundTabItem(image: image, selectedImage: image, controller: controller, subNode: badge ? BoundTabBadge() : nil)
        item.accessibilityTitle = title
        return item
    }

    private func controller() -> TabBarController {
        let controller = TabBarController()
        controller.bar = .init(height: 0)
        controller._frameRect = NSMakeRect(0, 0, 380, 700)
        controller.loadViewIfNeeded()
        controller.updatePresentation(.init(showsLabels: true))
        return controller
    }

    private func assertBindings(_ controller: TabBarController, _ items: [BoundTabItem], file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(controller.count, items.count, file: file, line: line)
        for (index, item) in items.enumerated() {
            let control = controller.control(for: index)
            let icon = try XCTUnwrap(control.subviews.first as? BoundTabIcon, file: file, line: line)
            XCTAssertTrue(icon.asset === item.image, file: file, line: line)
            XCTAssertTrue(controller.tab(at: index).controller === item.controller, file: file, line: line)
            XCTAssertEqual(control.accessibilityLabel(), item.accessibilityTitle, file: file, line: line)
            XCTAssertEqual(control.toolTip, item.accessibilityTitle, file: file, line: line)
            XCTAssertEqual(icon.selected, index == controller.selectedIndex, file: file, line: line)
            XCTAssertEqual(control.isAccessibilitySelected(), index == controller.selectedIndex, file: file, line: line)
            if let badge = item.subNode?.view { XCTAssertTrue(badge.superview === control, file: file, line: line) }
        }
    }

    func testHideRestoreAndReorderKeepAssetsTargetsBadgesAndAccessibilityTogether() throws {
        let controller = controller()
        let contacts = item("Contacts", color: .red)
        let calls = item("Calls", color: .blue)
        let chats = item("Chats", color: .green, badge: true)
        let settings = item("Settings", color: .purple, badge: true)
        for item in [contacts, calls, chats, settings] { controller.add(tab: item) }
        controller.select(index: 2)
        controller.remove(at: 3)
        controller.remove(at: 2)
        controller.replace(tab: chats, at: 0)
        controller.replace(tab: settings, at: 1)
        controller.select(index: 0)
        try assertBindings(controller, [chats, settings])
        XCTAssertTrue(controller.control(for: 1).accessibilityPerformPress())
        XCTAssertTrue(controller.current === settings.controller)
        try assertBindings(controller, [chats, settings])
        controller.replace(tab: contacts, at: 0)
        controller.replace(tab: calls, at: 1)
        controller.add(tab: chats)
        controller.add(tab: settings)
        controller.select(index: 2)
        try assertBindings(controller, [contacts, calls, chats, settings])
        controller.replace(tab: settings, at: 0)
        controller.replace(tab: chats, at: 1)
        controller.replace(tab: calls, at: 2)
        controller.replace(tab: contacts, at: 3)
        controller.select(index: 1)
        try assertBindings(controller, [settings, chats, calls, contacts])
        XCTAssertTrue(controller.control(for: 0).accessibilityPerformPress())
        XCTAssertTrue(controller.current === settings.controller)
        XCTAssertTrue(controller.control(for: 3).accessibilityPerformPress())
        XCTAssertTrue(controller.current === contacts.controller)
        try assertBindings(controller, [settings, chats, calls, contacts])
    }

    func testChangingRendererForSameControllerReplacesItsImmutableView() throws {
        let controller = controller()
        let original = item("Chats", color: .green)
        let plain = TabItem(image: original.image, selectedImage: original.image, controller: original.controller)
        controller.add(tab: plain)
        controller.select(index: 0)
        let oldView = controller.control(for: 0).subviews.first
        controller.replace(tab: original, at: 0)
        XCTAssertNil(oldView?.superview)
        try assertBindings(controller, [original])
    }

    func testDifferentControllerDoesNotInheritPreviousSlotsAccessibilityTitle() {
        let controller = controller()
        let original = item("Calls", color: .blue)
        controller.add(tab: original)
        let replacement = item("Settings", color: .purple)
        replacement.accessibilityTitle = nil
        controller.replace(tab: replacement, at: 0)
        XCTAssertNil(replacement.accessibilityTitle)
        XCTAssertNil(controller.control(for: 0).accessibilityLabel())
    }
}
