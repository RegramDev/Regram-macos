import SwiftSignalKit

func makeChatListTransitionQueue() -> Queue {
    return Queue(name: "chatListTransitions", qos: .userInitiated)
}
