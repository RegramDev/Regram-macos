import Cocoa

extension ChatRowGeometry.SideAccessory {
    @inline(__always) init(item: ChatRowItem, size: NSSize, offset: CGFloat, contentFrame: NSRect) {
        let isOnSide = item.isBubbled && !item.hasBubble
        self.init(contentFrame: contentFrame, size: size, offset: offset, elementsInset: item.elementsContentInset, isOnSide: isOnSide, isIncoming: isOnSide && item.isLeftAligned, hasSideAction: isOnSide && (item.isSharable || item.hasSource || item.commentsBubbleDataOverlay != nil))
    }
}

extension ChatRowGeometry.Author {
    @inline(__always) init(item: ChatRowItem, contentFrame: NSRect) {
        let isBubbled = item.isBubbled
        self.init(contentFrame: contentFrame, topOffset: item.defaultContentTopOffset, topInset: isBubbled ? item.topInset : 0, elementsInset: item.elementsContentInset, forwardInset: !isBubbled && item.forwardType != nil ? item.leftContentInset : 0, isBubbled: isBubbled)
    }
}

extension ChatRowGeometry.ForwardName {
    @inline(__always) init(item: ChatRowItem, bubbleFrame: NSRect, contentFrame: NSRect, accessoryWidth: CGFloat?) {
        let isBubbled = item.isBubbled
        let hasBubble = isBubbled && item.hasBubble
        let isIncoming = item.isLeftAligned
        self.init(inset: item.forwardNameInset, bubbleFrame: bubbleFrame, contentFrame: contentFrame, isBubbled: isBubbled, hasBubble: hasBubble, isIncoming: isIncoming, bubbleInset: hasBubble ? item.bubbleContentInset : 0, additionInset: hasBubble && isIncoming ? item.additionBubbleInset : 0, accessoryWidth: accessoryWidth, hasAuthor: item.authorText != nil)
    }
}

extension ChatRowGeometry {
    @inline(__always) static func forwardLineFrame(item: ChatRowItem, rowHeight: CGFloat) -> NSRect {
        guard !item.isBubbled, let kind = forwardLineKind(item) else { return .zero }
        let nameTop = kind == .short || kind == .full ? item.forwardNameInset.y : 0
        let topOffset = kind == .short || kind == .bottom ? item.defaultContentTopOffset : 0
        return forwardLineFrame(kind: kind, rowHeight: rowHeight, leftInset: item.defLeftInset, nameTop: nameTop, topOffset: topOffset, isBubbled: false)
    }

    @inline(__always) static func forwardLineKind(_ item: ChatRowItem) -> ForwardLineKind? {
        switch item.forwardType {
        case .ShortHeader?: return .short
        case .FullHeader?: return .full
        case .Inside?: return .inside
        case .Bottom?: return .bottom
        case nil: return nil
        }
    }
}
