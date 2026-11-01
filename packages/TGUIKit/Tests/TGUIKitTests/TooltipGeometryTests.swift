import AppKit
import QuartzCore
import XCTest
@testable import TGUIKit

final class TooltipGeometryTests: XCTestCase {
    private var windows: [Window] = []

    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    override func tearDown() {
        for window in windows {
            window.contentView?.subviews.removeAll()
            window.orderOut(nil)
        }
        windows.removeAll()
        super.tearDown()
    }

    private func anchor(x: CGFloat = 290) throws -> NSView {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.borderless], backing: .buffered, defer: false)
        let anchor = NSView(frame: NSRect(x: x, y: 200, width: 20, height: 20))
        try XCTUnwrap(window.contentView).addSubview(anchor)
        windows.append(window)
        return anchor
    }

    private func show(_ text: String, at anchor: NSView, width: CGFloat = 180, button: (String, () -> Void)? = nil) throws -> (NSView, NSView, NSView) {
        tooltip(for: anchor, text: text, button: button, maxWidth: width, timeout: 30)
        let view = try XCTUnwrap(anchor.window?.contentView?.subviews.first { NSStringFromClass(type(of: $0)).contains("TooltipView") })
        view.layoutSubtreeIfNeeded()
        let container = try XCTUnwrap(view.subviews.first { $0.subviews.contains { $0 is TextView } })
        let arrow = try XCTUnwrap(view.subviews.first { $0 is ImageView })
        return (view, container, arrow)
    }

    private func assertArrowOnStraightEdge(container: NSView, arrow: NSView, file: StaticString = #filePath, line: UInt = #line) throws {
        let radius = try XCTUnwrap(container.layer, file: file, line: line).cornerRadius
        XCTAssertGreaterThanOrEqual(arrow.frame.minX, container.frame.minX + radius, file: file, line: line)
        XCTAssertLessThanOrEqual(arrow.frame.maxX, container.frame.maxX - radius, file: file, line: line)
        XCTAssertEqual(arrow.frame.minY, container.frame.maxY, accuracy: 0.5, file: file, line: line)
    }

    func testNarrowHintKeepsArrowCenteredAndWithinRoundedEdges() throws {
        let anchor = try anchor()
        let (_, container, arrow) = try show("x", at: anchor)
        XCTAssertEqual(container.frame.width, 40, accuracy: 0.5)
        XCTAssertEqual(arrow.frame.midX, container.frame.midX, accuracy: 0.5)
        XCTAssertGreaterThan(try XCTUnwrap(container.layer).cornerRadius, 0)
        XCTAssertLessThan(try XCTUnwrap(container.layer).cornerRadius, 14)
        try assertArrowOnStraightEdge(container: container, arrow: arrow)
    }

    func testMultilineAndButtonHintsClampArrowAtBothWindowEdges() throws {
        for x: CGFloat in [0, 580] {
            let anchor = try anchor(x: x)
            for button: (String, () -> Void)? in [nil, ("OK", {})] {
                let (_, container, arrow) = try show("First line\nSecond line\nThird line", at: anchor, button: button)
                XCTAssertEqual(try XCTUnwrap(container.layer).cornerRadius, 14, accuracy: 0.5)
                try assertArrowOnStraightEdge(container: container, arrow: arrow)
            }
        }
    }

    func testExistingHintAnimatesCornerRadiusWhenGrowingAndShrinking() throws {
        let anchor = try anchor()
        let (view, container, _) = try show("x", at: anchor)
        let layer = try XCTUnwrap(container.layer)
        let shortRadius = layer.cornerRadius
        for (text, expected) in [("First line\nSecond line\nThird line", CGFloat(14)), ("x", shortRadius)] {
            let previousRadius = layer.cornerRadius
            layer.removeAllAnimations()
            let (updated, updatedContainer, arrow) = try show(text, at: anchor)
            XCTAssertTrue(updated === view)
            XCTAssertTrue(updatedContainer === container)
            XCTAssertEqual(layer.cornerRadius, expected, accuracy: 0.5)
            let animation = try XCTUnwrap(layer.animationKeys()?.compactMap { layer.animation(forKey: $0) as? CABasicAnimation }.first { $0.keyPath == "cornerRadius" })
            XCTAssertEqual((animation.fromValue as? NSNumber)?.doubleValue, Double(previousRadius))
            XCTAssertEqual((animation.toValue as? NSNumber)?.doubleValue, Double(expected))
            XCTAssertEqual(animation.duration, 0.2, accuracy: 0.001)
            try assertArrowOnStraightEdge(container: container, arrow: arrow)
        }
    }
}
