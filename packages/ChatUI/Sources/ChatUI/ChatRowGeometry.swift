import Cocoa

struct ChatRowGeometry {
    static let translationStackMinimumHeight: CGFloat = 70

    static func quickTranslationFrame(shareFrame: CGRect, stacked: Bool, rowHeight: CGFloat) -> CGRect {
        let size = CGSize(width: 30, height: 30)
        let y = stacked ? shareFrame.minY - size.height - 4 : max(0, min(rowHeight - size.height, shareFrame.minY))
        return CGRect(x: shareFrame.midX - size.width / 2, y: y, width: size.width, height: size.height)
    }

    struct SendFlightTarget: Equatable {
        let rowFrame: NSRect
        let bubbleFrame: NSRect
        let contentFrame: NSRect
        let timestampFrame: NSRect

        func canContinue(with current: SendFlightTarget, sameItem: Bool) -> Bool {
            sameItem && self == current
        }
    }

    struct Bubble {
        let rowWidth: CGFloat
        let layoutFrame: NSRect
        let leftInset: CGFloat
        let isIncoming: Bool
        let isCenteredThread: Bool
    }

    struct Content {
        let offset: NSPoint
        let size: NSSize
        let bubbleFrame: NSRect
        let isBubbled: Bool
        let isIncoming: Bool
        let bubbleInset: CGFloat
        let additionInset: CGFloat
    }

    struct Timestamp {
        var rowWidth: CGFloat = 0
        var size: NSSize = .zero
        var rightInset: CGFloat = 0
        var topOffset: CGFloat = 0
        var bubbleFrame: NSRect = .zero
        var contentFrame: NSRect = .zero
        var isBubbled = false
        var hasBubble = false
        var isIncoming = false
        var bubbleInset: CGFloat = 0
        var additionInset: CGFloat = 0
        var isOverlay = false
        var isVideoMessage = false
        var canTranscribeVideo = false
        var containsBigEmoji = false
        var actionButtonHeight: CGFloat?
        var commentsHeight: CGFloat = 0
    }

    @inline(__always) static func bubbleFrame(_ input: Bubble) -> NSRect {
        var frame = NSRect(x: input.isIncoming ? input.layoutFrame.minX : input.rowWidth - input.layoutFrame.width - input.leftInset, y: input.layoutFrame.minY, width: input.layoutFrame.width, height: input.layoutFrame.height)
        if input.isCenteredThread {
            frame.origin.x = round((input.rowWidth - (frame.width + 8)) / 2)
        }
        return frame
    }

    @inline(__always) static func contentFrame(_ input: Content) -> NSRect {
        var frame = NSRect(origin: input.offset, size: input.size)
        if input.isBubbled {
            frame.origin.x = input.bubbleFrame.minX + input.bubbleInset
            if input.isIncoming { frame.origin.x += input.additionInset }
        }
        return frame
    }

    @inline(__always) static func timestampFrame(_ input: Timestamp) -> NSRect {
        var frame = NSRect(x: input.rowWidth - input.size.width - input.rightInset, y: input.topOffset, width: input.size.width, height: input.size.height)
        if input.isBubbled {
            frame.origin = NSPoint(x: (input.hasBubble ? input.bubbleFrame.maxX : input.contentFrame.maxX) - input.size.width - input.bubbleInset - (input.isIncoming ? 0 : input.additionInset), y: input.bubbleFrame.maxY - input.size.height - 6 - (input.isOverlay && !input.hasBubble ? 2 : 0))
            if input.isOverlay {
                if input.isVideoMessage {
                    frame.origin.y = input.contentFrame.maxY - frame.height - 3
                } else {
                    frame.origin.x += 5
                    frame.origin.y -= 2
                    frame.origin.x = max(20, frame.origin.x)
                }
            }
            if input.isVideoMessage {
                if input.canTranscribeVideo && input.isIncoming {
                    frame.origin.x = input.contentFrame.maxX + 5
                } else {
                    frame.origin.x = input.isIncoming ? input.contentFrame.maxX - 40 : input.contentFrame.maxX - input.size.width
                }
                frame.origin.y += 3
            }
            if input.containsBigEmoji {
                frame.origin.y = input.bubbleFrame.maxY - input.size.height
            } else if let height = input.actionButtonHeight {
                frame.origin.y = input.bubbleFrame.maxY - input.size.height - height - 6
            }
            frame.origin.y -= input.commentsHeight
        }
        return frame
    }
}
