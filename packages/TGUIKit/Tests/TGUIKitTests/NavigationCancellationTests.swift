import Cocoa
import XCTest
@testable import TGUIKit

final class NavigationCancellationTests: XCTestCase {
    private var windows: [Window] = []

    override func setUp() {
        TGUIKitTestBootstrap.install()
    }

    override func tearDown() {
        windows.forEach { $0.close() }
        windows.removeAll()
    }

    private func makeNavigation() -> NavigationViewController {
        let window = Window(contentRect: NSMakeRect(100, 100, 400, 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        windows.append(window)
        return NavigationViewController(ViewController(), window)
    }

    func testCancelledControllerCannotEnterStackWhenItBecomesReady() {
        let navigation = makeNavigation()
        let originalCount = navigation.stackCount
        let pending = ViewController()
        navigation.push(pending, false)
        navigation.cancelPendingPush()
        pending.readyOnce()
        XCTAssertEqual(navigation.stackCount, originalCount)

        let current = ViewController()
        navigation.push(current, false)
        current.readyOnce()
        XCTAssertEqual(navigation.stackCount, originalCount + 1)
    }

    func testCancellationReleasesPendingController() {
        let navigation = makeNavigation()
        weak var pending: ViewController?
        do {
            let controller = ViewController()
            pending = controller
            navigation.push(controller, false)
        }
        XCTAssertNotNil(pending)
        navigation.cancelPendingPush()
        XCTAssertNil(pending)
    }
}
