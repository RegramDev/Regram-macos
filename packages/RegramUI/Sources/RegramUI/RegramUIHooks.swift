import Cocoa
import TGUIKit
import TelegramContext
import TelegramCore
import Postbox
import SwiftSignalKit
import InputDataUI

public struct RegramUIHooks {
    public var selectChats: (any AccountContextProtocol, [PeerId]) -> Signal<[PeerId], NoError> = { _, _ in .complete() }
    public var selectChat: (any AccountContextProtocol, PeerId?) -> Signal<PeerId, NoError> = { context, peerId in RegramUIHooks.shared.selectChats(context, peerId.map { [$0] } ?? []) |> mapToSignal { ids in ids.first.map { .single($0) } ?? .complete() } }
    public var openMessage: (any AccountContextProtocol, MessageId, Int64?) -> Void = { _, _, _ in }
    public var openPeer: (any AccountContextProtocol, PeerId) -> Void = { _, _ in }
    public var openPeerInfo: (any AccountContextProtocol, PeerId) -> Void = { context, peerId in RegramUIHooks.shared.openPeer(context, peerId) }
    public var openNativeSettings: (any AccountContextProtocol, String) -> Void = { _, _ in }
    public var restartApplication: () -> Void = {}
    public var makeUpdateController: () -> InputDataController? = { nil }

    public init() {}
    public static var shared = RegramUIHooks()
}
