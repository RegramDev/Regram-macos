import Postbox
import TelegramCore
import MessageUtils
import RegramCore

public func regramCanSaveMessage(_ message: Message, accountId: Int64, cachedData: CachedPeerData? = nil) -> Bool {
    guard message.id.peerId.namespace != Namespaces.Peer.SecretChat, !message.containsSecretMedia,
          !message.media.contains(where: { $0 is TelegramMediaExpiredContent || $0 is TelegramMediaPaidContent }) else { return false }
    return !message.isCopyProtected(cachedData: cachedData) || RegramPreferences.shared.settings(accountId: accountId)["allowSavingProtectedContent"].bool
}

public func regramCanCopyMessageText(_ source: Message, accountId: Int64, cachedData: CachedPeerData? = nil, peer: Peer? = nil) -> Bool {
    let message: Message
    if let peer, peer.id == source.id.peerId {
        var peers = source.peers
        peers[peer.id] = peer
        message = source.withUpdatedPeers(peers)
    } else {
        message = source
    }
    return !message.isCopyProtected(cachedData: cachedData) || regramCanSaveMessage(message, accountId: accountId, cachedData: cachedData)
}

public func regramBookmarkCanFetchFromCloud(_ id: MessageId) -> Bool {
    id.namespace == Namespaces.Message.Cloud && [Namespaces.Peer.CloudUser, Namespaces.Peer.CloudGroup, Namespaces.Peer.CloudChannel].contains(id.peerId.namespace)
}
