import Cocoa

extension ChatRowGeometry.Bubble {
    @inline(__always) init(item: ChatRowItem, rowWidth: CGFloat) {
        let isIncoming = item.isLeftAligned
        self.init(rowWidth: rowWidth, layoutFrame: item.bubbleFrame, leftInset: isIncoming ? 0 : item.leftInset, isIncoming: isIncoming, isCenteredThread: item.chatInteraction.mode.isThreadMode && item.chatInteraction.chatLocation.threadMsgId == item.message?.id)
    }
}

extension ChatRowGeometry.Content {
    @inline(__always) init(item: ChatRowItem, bubbleFrame: NSRect) {
        self.init(offset: item.contentOffset, size: item.contentSize, bubbleFrame: bubbleFrame, isBubbled: item.isBubbled, isIncoming: item.isLeftAligned, bubbleInset: item.bubbleContentInset, additionInset: item.additionBubbleInset)
    }
}

extension ChatRowGeometry.Timestamp {
    @inline(__always) init(item: ChatRowItem, rowWidth: CGFloat, bubbleFrame: NSRect, contentFrame: NSRect) {
        self.init()
        self.rowWidth = rowWidth
        self.size = item.rightSize
        self.rightInset = item.rightInset
        self.topOffset = item.defaultContentTopOffset
        self.bubbleFrame = bubbleFrame
        self.contentFrame = contentFrame
        self.isBubbled = item.isBubbled
        if isBubbled {
            self.hasBubble = item.hasBubble
            self.isIncoming = item.isLeftAligned
            self.bubbleInset = item.bubbleContentInset
            self.additionInset = item.additionBubbleInset
            self.isOverlay = item.isStateOverlayLayout
            if let video = item as? ChatVideoMessageItem {
                self.isVideoMessage = true
                self.canTranscribeVideo = video.canTranscribe
            }
            if let message = item as? ChatMessageItem {
                self.containsBigEmoji = message.containsBigEmoji
                if !containsBigEmoji && message.actionButtonText != nil && message.webpageLayout == nil {
                    self.actionButtonHeight = message.actionButtonHeight
                }
            }
            if item.hasBubble && item.commentsBubbleData != nil {
                self.commentsHeight = ChatRowItem.channelCommentsBubbleHeight
            }
        }
    }
}
