import AppKit
import CoreText
import XCTest
@testable import ChatListUI

final class RegramChatListBadgeGeometryTests: XCTestCase {
    func testCompactPremiumAndLeftBadgesFollowActualTitleBaselineWithSmallAvatar() {
        for font in [NSFont.systemFont(ofSize: 14), NSFont.systemFont(ofSize: 24), NSFont(name: "Menlo", size: 18) ?? .systemFont(ofSize: 18)] {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: "马牛逼", attributes: [.font: font]))
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
            let avatar = CGRect(x: 10, y: 9, width: 34, height: 34)
            let title = CGRect(x: avatar.maxX + 10, y: 3, width: ceil(width), height: ceil(ascent + descent))
            for x in [title.minX - 18, title.maxX + 2] {
                let badge = RegramChatListBadgeGeometry.frame(x: x, titleFrame: title, baseline: ascent, ascent: ascent, descent: descent, badgeSize: CGSize(width: 16, height: 16), rowHeight: 52)
                XCTAssertEqual(badge.minX, x)
                XCTAssertEqual(badge.midY, title.minY + (ascent + descent) / 2, accuracy: 1)
                XCTAssertGreaterThanOrEqual(badge.minY, 0)
                XCTAssertLessThanOrEqual(badge.maxY, 52)
            }
        }
    }

    func testTitleTopAndBadgeSizeChangesRemainInsideRow() {
        let title = CGRect(x: 54, y: 3, width: 100, height: 18)
        let regular = RegramChatListBadgeGeometry.frame(x: title.maxX + 2, titleFrame: title, baseline: 14, ascent: 14, descent: 4, badgeSize: CGSize(width: 16, height: 16), rowHeight: 52)
        let lower = RegramChatListBadgeGeometry.frame(x: title.maxX + 2, titleFrame: title.offsetBy(dx: 0, dy: 6), baseline: 14, ascent: 14, descent: 4, badgeSize: CGSize(width: 16, height: 16), rowHeight: 52)
        XCTAssertEqual(lower.minY - regular.minY, 6)
        let tall = RegramChatListBadgeGeometry.frame(x: title.maxX + 2, titleFrame: title, baseline: 14, ascent: 14, descent: 4, badgeSize: CGSize(width: 34, height: 20), rowHeight: 52)
        XCTAssertGreaterThanOrEqual(tall.minY, 0)
        XCTAssertEqual(tall.midY, regular.midY, accuracy: 1)
    }
}
