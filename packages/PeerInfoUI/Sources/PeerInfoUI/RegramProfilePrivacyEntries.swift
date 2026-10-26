import Cocoa
import TelegramCore
import Postbox
import TGUIKit
import GeneralRows
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import InputDataUI
import RegramCore

private enum RegramProfilePrivacyEntry: PeerInfoEntry {
    case separator(Int)
    case toggle(Int, String, String, Bool, PeerId, viewType: GeneralViewType = .singleItem)
    case notice(Int, String)
    case remark(Int, String, PeerId, viewType: GeneralViewType = .singleItem)

    private var index: Int {
        switch self {
        case let .separator(index), let .toggle(index, _, _, _, _, _), let .notice(index, _), let .remark(index, _, _, _): return index
        }
    }

    var stableId: PeerInfoEntryStableId { IntPeerInfoEntryStableId(value: -81_000 - index) }

    func isEqual(to: PeerInfoEntry) -> Bool {
        guard let other = to as? RegramProfilePrivacyEntry else { return false }
        switch (self, other) {
        case let (.separator(a), .separator(b)): return a == b
        case let (.toggle(a, b, c, d, e, viewType), .toggle(f, g, h, i, j, otherViewType)): return a == f && b == g && c == h && d == i && e == j && viewType == otherViewType
        case let (.notice(a, b), .notice(c, d)): return a == c && b == d
        case let (.remark(a, b, c, viewType), .remark(d, e, f, otherViewType)): return a == d && b == e && c == f && viewType == otherViewType
        default: return false
        }
    }

    func isOrderedBefore(_ entry: PeerInfoEntry) -> Bool { false }

    func item<Context: AccountContextProtocol>(initialSize: NSSize, arguments: PeerInfoArguments<Context>) -> TableRowItem {
        func string(_ key: String) -> String { regramLocalizedString(key, languageCode: appCurrentLanguage.primaryLanguage.languageCode) }
        switch self {
        case .separator:
            return GeneralRowItem(initialSize, height: 20, stableId: stableId.hashValue, viewType: .separator)
        case let .notice(_, key):
            return GeneralTextRowItem(initialSize, stableId: stableId.hashValue, text: string(key), viewType: .textBottomItem)
        case let .toggle(_, key, title, value, peerId, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: string(title), type: .switchable(value), viewType: viewType, action: {
                RegramPreferences.shared.update(accountId: arguments.context.peerId.toInt64()) { settings in
                    guard key != "antiRevokePeerIds" || !settings["antiRevoke"].bool else { return }
                    let id = String(peerId.toInt64())
                    var ids = settings[key].strings
                    if ids.contains(id) { ids.removeAll { $0 == id } } else { ids.append(id) }
                    settings[key] = .strings(ids)
                }
            })
        case let .remark(_, value, peerId, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: string("GroupRemark.Title"), type: .nextContext(value), viewType: viewType, action: {
                if let controller = FeatureNavigationHooks.shared.makeRegramController(arguments.context, "remark/\(peerId.toInt64())") { arguments.pushViewController(controller) }
            })
        }
    }
}

func regramProfilePrivacyEntries<Context: AccountContextProtocol>(_ original: [PeerInfoEntry], view: PeerView, arguments: PeerInfoArguments<Context>) -> [PeerInfoEntry] {
    guard let peer = peerViewMainPeer(view), peer.id != arguments.context.peerId else { return original }
    let accountId = arguments.context.peerId.toInt64()
    let settings = RegramPreferences.shared.settings(accountId: accountId)
    var entries = original
    if peer is TelegramUser {
        let block = entries.firstIndex { entry in
            if let entry = entry as? UserInfoEntry<Context>, case .block = entry { return true }
            return false
        }
        let hidden: [PeerInfoEntry] = [
            RegramProfilePrivacyEntry.toggle(1, "blockedPeerIds", "BlockUser.Block", settings["blockedPeerIds"].strings.contains(String(peer.id.toInt64())), peer.id, viewType: block == nil ? .singleItem : .lastItem),
            RegramProfilePrivacyEntry.notice(2, "BlockUser.Notice")
        ]
        if let block, let entry = entries[block] as? UserInfoEntry<Context> {
            entries[block] = entry.withUpdatedViewType(entry.viewType == .singleItem || entry.viewType == .firstItem ? .firstItem : .innerItem)
            entries.insert(contentsOf: hidden, at: block + 1)
        } else {
            let media = entries.firstIndex { entry in
                if let entry = entry as? UserInfoEntry<Context>, case .media = entry { return true }
                return false
            } ?? entries.count
            entries.insert(contentsOf: [RegramProfilePrivacyEntry.separator(11)] + hidden, at: media)
        }
    }
    var additions: [PeerInfoEntry] = [RegramProfilePrivacyEntry.separator(3)]
    let hasRemark = peer is TelegramGroup || peer is TelegramChannel
    if hasRemark {
        let value = RGGroupRemarks.shared.name(accountId: accountId, peerId: peer.id.toInt64()) ?? regramLocalizedString("GroupRemark.NotSet", languageCode: appCurrentLanguage.primaryLanguage.languageCode)
        additions.append(RegramProfilePrivacyEntry.remark(4, value, peer.id, viewType: .firstItem))
    }
    let filtered = !settings["messageFilterDisabledPeerIds"].strings.contains(String(view.peerId.toInt64()))
    additions.append(RegramProfilePrivacyEntry.toggle(5, "messageFilterDisabledPeerIds", "MessageFilter.PerChat.Title", filtered, view.peerId, viewType: hasRemark ? .lastItem : .singleItem))
    additions.append(RegramProfilePrivacyEntry.notice(6, "MessageFilter.PerChat.Notice"))
    if settings["antiRevoke"].bool {
        additions.append(RegramProfilePrivacyEntry.notice(7, "AntiRevoke.PerChat.AllChats"))
    } else {
        additions.append(RegramProfilePrivacyEntry.separator(8))
        additions.append(RegramProfilePrivacyEntry.toggle(9, "antiRevokePeerIds", "AntiRevoke.PerChat.Title", settings["antiRevokePeerIds"].strings.contains(String(view.peerId.toInt64())), view.peerId))
        additions.append(RegramProfilePrivacyEntry.notice(10, "AntiRevoke.PerChat.Notice"))
    }
    entries.insert(contentsOf: additions, at: min(1, entries.count))
    return entries
}
