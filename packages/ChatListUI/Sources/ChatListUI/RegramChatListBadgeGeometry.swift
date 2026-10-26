import Foundation

enum RegramChatListBadgeGeometry {
    static func frame(x: CGFloat, titleFrame: CGRect, baseline: CGFloat, ascent: CGFloat, descent: CGFloat, badgeSize: CGSize, rowHeight: CGFloat) -> CGRect {
        let center = titleFrame.minY + baseline - (ascent - descent) / 2
        let y = max(0, min(max(0, rowHeight - badgeSize.height), floor(center - badgeSize.height / 2)))
        return CGRect(x: x, y: y, width: badgeSize.width, height: badgeSize.height)
    }
}
