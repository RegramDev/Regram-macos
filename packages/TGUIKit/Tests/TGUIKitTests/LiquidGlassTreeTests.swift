import XCTest
import AppKit
@testable import TGUIKit

final class LiquidGlassTreeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    override func tearDown() {
        System.liquidGlass = false
        super.tearDown()
    }

    private func modes() -> [Bool] {
        return System.liquidGlassAvailable ? [false, true] : [false]
    }

    func testGlassHostsItsEffectViewDirectly() {
        for liquidGlass in modes() {
            System.liquidGlass = liquidGlass
            let glass = LiquidGlassView(frame: NSMakeRect(0, 0, 40, 40), cornerRadius: 20)
            XCTAssertEqual(glass.subviews.count, 1, "liquidGlass \(liquidGlass)")
            XCTAssertTrue(glass.subviews.first === glass.effectView)
            XCTAssertNil(glass.appearanceContainer.superview)
            glass.setFrameSize(NSMakeSize(60, 40))
            glass.layout()
            XCTAssertEqual(glass.effectView.frame, NSMakeRect(0, 0, 60, 40))
        }
    }

    func testRebuiltEffectViewStaysBelowContent() {
        for liquidGlass in modes() {
            System.liquidGlass = liquidGlass
            let glass = LiquidGlassView(frame: NSMakeRect(0, 0, 40, 40), cornerRadius: 20, forceAppearance: .forceLight)
            let content = View(frame: NSMakeRect(4, 4, 32, 32))
            glass.addSubview(content)
            let previous = glass.effectView
            glass.forceAppearance = .forceDark
            XCTAssertFalse(previous === glass.effectView, "liquidGlass \(liquidGlass)")
            XCTAssertTrue(glass.subviews.first === glass.effectView, "liquidGlass \(liquidGlass)")
            XCTAssertTrue(glass.subviews.last === content, "liquidGlass \(liquidGlass)")
        }
    }

    func testGhostAddsOnlyItsEffectViewAsSibling() throws {
        guard System.liquidGlassAvailable else {
            throw XCTSkip("liquid glass is not available")
        }
        System.liquidGlass = true
        let container = GlassContainerView(frame: NSMakeRect(0, 0, 200, 40), flipped: true, spacing: 5)
        let glass = LiquidGlassView(frame: NSMakeRect(0, 0, 40, 40), cornerRadius: 20)
        container.addGhost(glass)
        XCTAssertEqual(container.glassContent.subviews.count, 2)
        XCTAssertTrue(container.glassContent.subviews.contains { $0 === glass })
        XCTAssertTrue(container.glassContent.subviews.contains { $0 === glass.effectView })
        XCTAssertNil(glass.appearanceContainer.superview)
        container.setGhostFrame(glass, frame: NSMakeRect(10, 0, 40, 40), transition: .immediate)
        XCTAssertEqual(glass.effectView.frame, NSMakeRect(10, 0, 40, 40))
        container.removeGhost(glass)
        XCTAssertNil(glass.effectView.superview)
        XCTAssertNil(glass.superview)
    }

    func testReduceTransparencyReplacesEffectsAndRestoresThem() {
        let previousReduction = LiquidGlassView.reduceTransparency
        let previousBlur = System.blurEnabled
        defer {
            LiquidGlassView.reduceTransparency = previousReduction
            System.blurEnabled = previousBlur
        }
        System.blurEnabled = true
        var reduced = false
        LiquidGlassView.reduceTransparency = { reduced }
        for mode in modes() {
            System.liquidGlass = mode
            let glass = LiquidGlassView(frame: NSMakeRect(0, 0, 180, 40), customTint: NSColor.red.withAlphaComponent(0.2))
            let content = View(frame: NSMakeRect(10, 10, 20, 20))
            glass.addSubview(content)
            let original = glass.effectView
            reduced = true
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
            XCTAssertFalse(original === glass.effectView)
            XCTAssertFalse(glass.effectView is NSVisualEffectView)
            if #available(macOS 26.0, *) {
                XCTAssertFalse(glass.effectView is NSGlassEffectView)
            }
            XCTAssertEqual(glass.effectView.layer?.backgroundColor?.alpha, 1)
            XCTAssertTrue(glass.subviews.first === glass.effectView)
            XCTAssertTrue(glass.subviews.last === content)
            XCTAssertEqual(glass.effectView.frame, glass.bounds)
            let solid = glass.effectView
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
            XCTAssertTrue(solid === glass.effectView)
            reduced = false
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
            XCTAssertFalse(solid === glass.effectView)
            XCTAssertTrue(type(of: original!) == type(of: glass.effectView!))
        }
    }

    func testReducedTransparencyPreservesHiddenReparentedGlassAndReleasesObserver() {
        let previousReduction = LiquidGlassView.reduceTransparency
        defer { LiquidGlassView.reduceTransparency = previousReduction }
        var reduced = false
        LiquidGlassView.reduceTransparency = { reduced }
        let host = View(frame: NSMakeRect(0, 0, 300, 100))
        weak var released: LiquidGlassView?
        autoreleasepool {
            let glass = LiquidGlassView(frame: NSMakeRect(0, 0, 80, 40), cornerRadius: 16)
            released = glass
            let frame = NSMakeRect(30, 20, 80, 40)
            host.addSubview(glass.effectView)
            glass.effectView.frame = frame
            glass.isHidden = true
            reduced = true
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
            XCTAssertTrue(glass.effectView.superview === host)
            XCTAssertEqual(glass.effectView.frame, frame)
            XCTAssertTrue(glass.effectView.isHidden)
        }
        XCTAssertNil(released)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: NSWorkspace.shared)
    }
}
