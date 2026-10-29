import Cocoa
import XCTest
@testable import TGUIKit

final class AppMenuCloseTests: XCTestCase {
    private var previousLegacyMenu = true
    private var windows: [Window] = []
    private var popups: [AppMenu] = []

    override func setUp() {
        TGUIKitTestBootstrap.install()
        previousLegacyMenu = System.legacyMenu
        System.legacyMenu = false
    }

    override func tearDown() {
        popups.forEach { $0.close() }
        windows.forEach { $0.close() }
        popups.removeAll()
        windows.removeAll()
        System.legacyMenu = previousLegacyMenu
    }

    private func present(_ menu: ContextMenu) throws -> (AppMenu, Window) {
        let window = Window(contentRect: NSMakeRect(100, 100, 400, 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let anchor = NSView(frame: NSMakeRect(20, 20, 100, 40))
        window.contentView?.addSubview(anchor)
        windows.append(window)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: NSMakePoint(30, 30), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0))
        let popup = AppMenu(menu: menu, appearMode: .hover)
        popups.append(popup)
        popup.show(event: event, view: anchor)
        return (popup, window)
    }

    func testCloseDismissesItsMenuOnce() throws {
        let menu = ContextMenu()
        menu.addItem(ContextMenuItem("Preview"))
        var closed = 0
        menu.onClose = { closed += 1 }
        let (popup, window) = try present(menu)
        XCTAssertTrue(menu.isShown)
        XCTAssertEqual(window.contentView?.subviews.count, 1)
        popup.close()
        XCTAssertFalse(menu.isShown)
        XCTAssertEqual(closed, 1)
        popup.close()
        XCTAssertEqual(closed, 1)
    }

    func testCloseDoesNotDismissAnotherWindowMenu() throws {
        let first = ContextMenu()
        first.addItem(ContextMenuItem("First preview"))
        let (firstPopup, _) = try present(first)
        let second = ContextMenu()
        second.addItem(ContextMenuItem("Second menu"))
        _ = try present(second)
        XCTAssertTrue(first.isShown)
        XCTAssertTrue(second.isShown)
        firstPopup.close()
        XCTAssertFalse(first.isShown)
        XCTAssertTrue(second.isShown)
    }

    func testClosingPendingMenuPreventsLaterPresentation() throws {
        let menu = ContextMenu()
        let (popup, _) = try present(menu)
        XCTAssertFalse(menu.isShown)
        popup.close()
        menu.addItem(ContextMenuItem("Late preview"))
        XCTAssertFalse(menu.isShown)
    }
}
