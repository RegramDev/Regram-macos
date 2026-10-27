import Cocoa
import TGUIKit
import TelegramCore

import Postbox
import SwiftSignalKit
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows

public class ChatListMessageRowItem: ChatListRowItem {

    private let searchMessageId: MessageId

    public init(_ initialSize:NSSize, context: any AccountContextProtocol, message: Message, id: EngineChatList.Item.Id, query: String, renderedPeer:RenderedPeer, readState: CombinedPeerReadState?, mode: ChatListRowItem.Mode, titleMode: ChatListRowItem.TitleMode) {
        self.searchMessageId = message.id
        super.init(initialSize, context: context, stableId: .chatId(id, message.id.peerId, message.id.id), mode: mode, messages: [message], readState: .init(state: readState, isMuted: false), renderedPeer: .init(renderedPeer), highlightText: query, showBadge: false, titleMode: titleMode)
    }
    
    public override var stableId: AnyHashable {
        return searchMessageId
    }

    public override var showsCommunityDropdown: Bool {
        return false
    }
}
