import Cocoa
import XCTest
@testable import TGUIKit

final class AppMenuPlacementTests: XCTestCase {
    private let screen = NSMakeRect(0, 24, 1440, 852)
    private let owner = NSMakeRect(200, 100, 900, 700)

    func testClickAtButtonTopKeepsMenuBelowVisibleTop() {
        let frame = NSMakeRect(800, 500, 280, 400)
        let result = appMenuAdjustedFrame(frame, screenFrame: screen, ownerFrame: owner, parentFrame: nil, betterInside: true)
        XCTAssertEqual(result.maxY, owner.maxY)
        XCTAssertTrue(owner.contains(result))
        XCTAssertEqual(result.size, frame.size)
    }

    func testMenuTallerThanOwnerFitsAvailableScreen() {
        let shortOwner = NSMakeRect(200, 200, 800, 300)
        let frame = NSMakeRect(500, 450, 280, 600)
        let result = appMenuAdjustedFrame(frame, screenFrame: screen, ownerFrame: shortOwner, parentFrame: nil, betterInside: true)
        XCTAssertEqual(result.maxY, screen.maxY)
        XCTAssertTrue(screen.contains(result))
        XCTAssertEqual(result.size, frame.size)
    }

    func testFullscreenUsesItsCompleteScreenBounds() {
        let fullScreen = NSMakeRect(0, 0, 1440, 900)
        let frame = NSMakeRect(800, 700, 280, 400)
        let result = appMenuAdjustedFrame(frame, screenFrame: fullScreen, ownerFrame: fullScreen, parentFrame: nil, betterInside: false)
        XCTAssertEqual(result.maxY, fullScreen.maxY)
        XCTAssertTrue(fullScreen.contains(result))
    }

    func testBottomOverflowMovesMenuUp() {
        let frame = NSMakeRect(500, -200, 280, 400)
        let result = appMenuAdjustedFrame(frame, screenFrame: screen, ownerFrame: owner, parentFrame: nil, betterInside: false)
        XCTAssertEqual(result.minY, screen.minY)
        XCTAssertTrue(screen.contains(result))
    }

    func testRightSubmenuOpensOnLeftAndRemainsInsideScreen() {
        let parent = NSMakeRect(1200, 200, 220, 500)
        let frame = NSMakeRect(1400, 650, 280, 400)
        let result = appMenuAdjustedFrame(frame, screenFrame: screen, ownerFrame: owner, parentFrame: parent, betterInside: true)
        XCTAssertEqual(result.minX, parent.minX - frame.width + 45)
        XCTAssertTrue(screen.contains(result))
    }

    func testLeftSubmenuOpensOnRightAndRemainsInsideScreen() {
        let parent = NSMakeRect(0, 200, 220, 500)
        let frame = NSMakeRect(-250, 100, 280, 400)
        let result = appMenuAdjustedFrame(frame, screenFrame: screen, ownerFrame: owner, parentFrame: parent, betterInside: true)
        XCTAssertEqual(result.minX, parent.maxX - 40)
        XCTAssertTrue(screen.contains(result))
    }

    func testSecondaryDisplaySupportsNegativeCoordinates() {
        let second = NSMakeRect(-1920, -1000, 1920, 1080)
        let secondOwner = NSMakeRect(-1800, -900, 900, 700)
        let result = appMenuAdjustedFrame(NSMakeRect(-100, 30, 280, 500), screenFrame: second, ownerFrame: secondOwner, parentFrame: nil, betterInside: false)
        XCTAssertTrue(second.contains(result))
        XCTAssertEqual(result.maxY, second.maxY)
    }

    func testValidAnchorIsUnchanged() {
        let frame = NSMakeRect(300, 200, 280, 400)
        XCTAssertEqual(appMenuAdjustedFrame(frame, screenFrame: screen, ownerFrame: owner, parentFrame: nil, betterInside: true), frame)
    }

    func testOwnerPartlyOutsideScreenCannotPlaceMenuOutsideScreen() {
        let outsideOwner = NSMakeRect(1000, 500, 900, 700)
        let frame = NSMakeRect(1500, 700, 280, 400)
        let result = appMenuAdjustedFrame(frame, screenFrame: screen, ownerFrame: outsideOwner, parentFrame: nil, betterInside: true)
        XCTAssertTrue(screen.contains(result))
    }

    func testMenusAtDisplayEdgesRemainInsideForManySizes() {
        for origin in [NSPoint(x: 0, y: 24), NSPoint(x: -1920, y: -1080), NSPoint(x: 1440, y: 900)] {
            let bounds = NSRect(origin: origin, size: NSSize(width: 1440, height: 852))
            let owner = bounds.insetBy(dx: 100, dy: 100)
            for width in [CGFloat(100), 280, 500] {
                for height in [CGFloat(40), 400, 700] {
                    for x in [bounds.minX - 500, bounds.minX, bounds.maxX - 20, bounds.maxX + 500] {
                        for y in [bounds.minY - 500, bounds.minY, bounds.maxY - 20, bounds.maxY + 500] {
                            for inside in [false, true] {
                                let frame = NSMakeRect(x, y, width, height)
                                let result = appMenuAdjustedFrame(frame, screenFrame: bounds, ownerFrame: owner, parentFrame: nil, betterInside: inside)
                                XCTAssertTrue(bounds.contains(result), "\(frame) -> \(result), bounds \(bounds)")
                                XCTAssertEqual(result.size, frame.size)
                            }
                        }
                    }
                }
            }
        }
    }
}
