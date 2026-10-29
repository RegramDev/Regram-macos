import Cocoa
import XCTest
import SwiftSignalKit
@testable import TGUIKit

__NAVIGATION_REQUEST__

__HOVER_PREVIEW__

__TRANSITION_QUEUE__

__RESOURCE_QUEUE__

private final class PreviewFixtureWindow: Window {
    var active = true
    var pointer: NSPoint = .zero
    override var isKeyWindow: Bool { active }
    override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
}

final class SwitchLifecycleChecks: XCTestCase {
    private var windows: [Window] = []
    private var previousLegacyMenu = true

    override func setUp() {
        TGUIKitTestBootstrap.install()
        previousLegacyMenu = System.legacyMenu
        System.legacyMenu = false
        for _ in 0..<20 {
            if !contextMenuOnScreen() { break }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
    }

    override func tearDown() {
        AppMenu.closeAll()
        windows.forEach { $0.close() }
        windows.removeAll()
        System.legacyMenu = previousLegacyMenu
    }

    private func source() throws -> (PreviewFixtureWindow, NSView, NSEvent) {
        let window = PreviewFixtureWindow(contentRect: NSMakeRect(100, 100, 400, 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let view = NSView(frame: NSMakeRect(20, 20, 100, 40))
        window.contentView?.addSubview(view)
        window.pointer = view.convert(NSMakePoint(10, 10), to: nil)
        windows.append(window)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: window.pointer, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0))
        return (window, view, event)
    }

    func testNewNavigationCancelsPreviousQueryAndRejectsLateInstall() {
        let request = ChatNavigationRequest()
        var oldCancelled = 0
        var lateCancelled = 0
        var currentCancelled = 0
        let old = request.begin()
        request.set(ActionDisposable { oldCancelled += 1 }, version: old)
        let current = request.begin()
        XCTAssertEqual(oldCancelled, 1)
        XCTAssertFalse(request.isCurrent(old))
        XCTAssertTrue(request.isCurrent(current))
        request.set(ActionDisposable { currentCancelled += 1 }, version: current)
        request.set(ActionDisposable { lateCancelled += 1 }, version: old)
        XCTAssertEqual(lateCancelled, 1)
        XCTAssertEqual(currentCancelled, 0)
        _ = request.begin()
        XCTAssertEqual(currentCancelled, 1)
    }

    func testReentrantCancellationKeepsLatestRequestCurrent() {
        let request = ChatNavigationRequest()
        var reentered: UInt64 = 0
        let old = request.begin()
        request.set(ActionDisposable { reentered = request.begin() }, version: old)
        let replaced = request.begin()
        XCTAssertFalse(request.isCurrent(replaced))
        XCTAssertTrue(request.isCurrent(reentered))
    }

    func testIndependentNavigationScopesDoNotCancelEachOther() {
        let first = ChatNavigationRequest()
        let second = ChatNavigationRequest()
        let firstVersion = first.begin()
        let secondVersion = second.begin()
        _ = first.begin()
        XCTAssertFalse(first.isCurrent(firstVersion))
        XCTAssertTrue(second.isCurrent(secondVersion))
    }

    func testListQueueDoesNotWaitForUnrelatedBackgroundWork() {
        let background = prepareQueue
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let resumed = expectation(description: "Background queue resumed")
        background.async {
            entered.signal()
            release.wait()
            resumed.fulfill()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        let foreground = makeChatListTransitionQueue()
        let switched = expectation(description: "Foreground list switches")
        foreground.async { switched.fulfill() }
        wait(for: [switched], timeout: 2)
        release.signal()
        wait(for: [resumed], timeout: 2)
    }

    func testIndependentListQueuesDoNotBlockEachOther() {
        let first = makeChatListTransitionQueue()
        let second = makeChatListTransitionQueue()
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = expectation(description: "First list finishes")
        first.async {
            entered.signal()
            release.wait()
            finished.fulfill()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 2), .success)
        let switched = expectation(description: "Second list switches")
        second.async { switched.fulfill() }
        wait(for: [switched], timeout: 2)
        release.signal()
        wait(for: [finished], timeout: 2)
    }

    func testHoverDisposalClosesPreviewAndCancelsRequestOnce() throws {
        let (window, view, event) = try source()
        let preview = LinkHoverPreview(view: view, event: event)
        var cancelled = 0
        preview.setRequest(ActionDisposable { cancelled += 1 })
        let menu = ContextMenu()
        menu.addItem(ContextMenuItem("Peer preview"))
        preview.present(menu)
        XCTAssertTrue(menu.isShown)
        XCTAssertEqual(window.contentView?.subviews.count, 1)
        preview.dispose()
        XCTAssertFalse(menu.isShown)
        XCTAssertEqual(cancelled, 1)
        preview.dispose()
        XCTAssertEqual(cancelled, 1)
    }

    func testDisposedHoverRejectsLateResponseAndLateRequest() throws {
        let (_, view, event) = try source()
        let preview = LinkHoverPreview(view: view, event: event)
        preview.dispose()
        var cancelled = 0
        preview.setRequest(ActionDisposable { cancelled += 1 })
        let menu = ContextMenu()
        menu.addItem(ContextMenuItem("Late peer"))
        preview.present(menu)
        XCTAssertFalse(menu.isShown)
        XCTAssertEqual(cancelled, 1)
    }

    func testHoverRejectsDetachedOrInactiveSource() throws {
        let (window, view, event) = try source()
        let menu = ContextMenu()
        menu.addItem(ContextMenuItem("Peer preview"))
        let preview = LinkHoverPreview(view: view, event: event)
        window.active = false
        preview.present(menu)
        XCTAssertFalse(menu.isShown)
        window.active = true
        view.removeFromSuperview()
        preview.present(menu)
        XCTAssertFalse(menu.isShown)
        preview.dispose()
    }
}
