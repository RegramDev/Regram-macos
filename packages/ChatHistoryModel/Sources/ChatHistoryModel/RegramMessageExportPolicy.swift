import Postbox
import TelegramCore
import MessageUtils
import RegramCore

public func regramCanSaveMessage(_ message: Message, accountId: Int64, cachedData: CachedPeerData? = nil) -> Bool {
    guard message.id.peerId.namespace != Namespaces.Peer.SecretChat, !message.containsSecretMedia,
          !message.media.contains(where: { $0 is TelegramMediaExpiredContent || $0 is TelegramMediaPaidContent }) else { return false }
    return !message.isCopyProtected(cachedData: cachedData) || RegramPreferences.shared.settings(accountId: accountId)["allowSavingProtectedContent"].bool
}

public func regramBookmarkCanFetchFromCloud(_ id: MessageId) -> Bool {
    id.namespace == Namespaces.Message.Cloud && [Namespaces.Peer.CloudUser, Namespaces.Peer.CloudGroup, Namespaces.Peer.CloudChannel].contains(id.peerId.namespace)
}
