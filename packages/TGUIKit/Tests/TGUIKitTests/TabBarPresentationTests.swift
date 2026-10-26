import XCTest
import AppKit
import ColorPalette
@testable import TGUIKit

final class TabBarPresentationTests: XCTestCase {
    override func tearDown() {
        PeerNameColorProvider.install()
        super.tearDown()
    }

    func testDefaultPresentationPreservesUpstreamFloatingGeometry() {
        for size in [NSMakeSize(380, 700), NSMakeSize(800, 700), .zero] {
            XCTAssertEqual(TabBarPresentation().frame(in: size, count: 4), FloatingTabBarLayout.frame(in: size))
        }
        let labels = TabBarPresentation(showsLabels: true)
        XCTAssertEqual(labels.frame(in: NSMakeSize(380, 700), count: 4), NSMakeRect(20, 620, 340, 64))
    }

    func testOptionalCompactWidthAndAccessoryStayInsideThePane() {
        let size = NSMakeSize(380, 700)
        let compact = TabBarPresentation(width: .compact).frame(in: size, count: 2)
        XCTAssertLessThan(compact.width, FloatingTabBarLayout.frame(in: size).width)
        XCTAssertEqual(compact.midX, size.width / 2, accuracy: 0.5)
        let presentation = TabBarPresentation(showsLabels: true, width: .fraction(0.5), accessoryTitle: "Search", accessoryAction: {})
        let frame = presentation.frame(in: size, count: 4)
        XCTAssertGreaterThanOrEqual(frame.minX, FloatingTabBarLayout.sideInset)
        XCTAssertLessThanOrEqual(frame.maxX + presentation.height + 8, size.width - FloatingTabBarLayout.sideInset)
        let layout = FloatingTabBarLayout(size: NSMakeSize(300, 64), count: 4, externalIndex: 3)
        XCTAssertLessThan(layout.itemFrames[2].maxX, layout.itemFrames[3].minX)
        for index in layout.itemFrames.indices {
            XCTAssertEqual(layout.index(at: NSMakePoint(layout.itemFrames[index].midX, 30)), index)
            XCTAssertEqual(layout.selectionFrame(at: CGFloat(index), lifted: false), layout.itemFrames[index])
        }
        XCTAssertEqual(FloatingTabBarLayout(size: NSMakeSize(300, 48), count: 4, externalIndex: 10).itemFrames, FloatingTabBarLayout(size: NSMakeSize(300, 48), count: 4).itemFrames)
    }

    func testPeerColorProviderReentrancyAndOriginalScopeRestore() {
        let colors = PeerNameColors.Colors(main: .red, secondary: .green, tertiary: .blue)
        PeerNameColorProvider.install { _ in
            PeerNameColorProvider.install()
            return .black
        }
        XCTAssertEqual(colors.main, .black)
        XCTAssertEqual(colors.main, .red)
        PeerNameColorProvider.install(enabled: false, transform: { _ in .white })
        XCTAssertFalse(PeerNameColorProvider.isEnabled)
        enum Failure: Error { case expected }
        XCTAssertThrowsError(try PeerNameColorProvider.withOriginalColors {
            XCTAssertEqual(colors.main, .red)
            PeerNameColorProvider.withOriginalColors { XCTAssertEqual(colors.secondary, .green) }
            XCTAssertEqual(colors.tertiary, .blue)
            throw Failure.expected
        })
        XCTAssertEqual(colors.main, .white)
        PeerNameColorProvider.install()
        XCTAssertTrue(PeerNameColorProvider.isEnabled)
        XCTAssertEqual(colors.main, .red)
    }
}
