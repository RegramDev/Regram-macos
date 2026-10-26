import Cocoa
import TelegramCore
import Postbox
import TGUIKit
import GeneralRows
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import LocationUI
import InAppSettings
import RegramCore
import RegramSignals
import SwiftSignalKit

private struct RegramOrderedPeerInfoEntry: PeerInfoEntry {
    let order: Int
    let entry: PeerInfoEntry
    var stableId: PeerInfoEntryStableId { entry.stableId }

    func isEqual(to: PeerInfoEntry) -> Bool {
        guard let other = to as? RegramOrderedPeerInfoEntry else { return false }
        return entry.isEqual(to: other.entry)
    }

    func isOrderedBefore(_ entry: PeerInfoEntry) -> Bool {
        guard let other = entry as? RegramOrderedPeerInfoEntry else { return false }
        return order < other.order
    }

    func item<C: AccountContextProtocol>(initialSize: NSSize, arguments: PeerInfoArguments<C>) -> TableRowItem {
        entry.item(initialSize: initialSize, arguments: arguments)
    }
}

private struct RegramProfileDetailEntry: PeerInfoEntry {
    let index: Int
    let label: String
    let text: String
    let viewType: GeneralViewType
    var stableId: PeerInfoEntryStableId { IntPeerInfoEntryStableId(value: -80_000 - index) }

    func isEqual(to: PeerInfoEntry) -> Bool {
        guard let other = to as? RegramProfileDetailEntry else { return false }
        return index == other.index && label == other.label && text == other.text && viewType == other.viewType
    }

    func isOrderedBefore(_ entry: PeerInfoEntry) -> Bool { false }

    func item<C: AccountContextProtocol>(initialSize: NSSize, arguments: PeerInfoArguments<C>) -> TableRowItem {
        if index == 0 { return GeneralRowItem(initialSize, height: 20, stableId: stableId.hashValue, viewType: .separator) }
        return TextAndLabelItem(initialSize, stableId: stableId.hashValue, label: label, copyMenuText: strings().textCopyText, text: text, context: arguments.context, viewType: viewType, canCopy: true, _copyToClipboard: { arguments.copy(text) })
    }
}

private struct RegramGroupProfileLocationEntry: PeerInfoEntry {
    let location: PeerGeoLocation
    let title: String
    let label: String
    let viewType: GeneralViewType
    var stableId: PeerInfoEntryStableId { IntPeerInfoEntryStableId(value: -80_008) }
    func isEqual(to: PeerInfoEntry) -> Bool {
        guard let other = to as? RegramGroupProfileLocationEntry else { return false }
        return location == other.location && title == other.title && label == other.label && viewType == other.viewType
    }
    func isOrderedBefore(_ entry: PeerInfoEntry) -> Bool { false }
    func item<C: AccountContextProtocol>(initialSize: NSSize, arguments: PeerInfoArguments<C>) -> TableRowItem {
        GeneralInteractedRowItem(initialSize, stableId: stableId.hashValue, name: location.address.replacingOccurrences(of: ", ", with: "\n"), description: label, type: .next, viewType: viewType, action: {
            let map = TelegramMediaMap(latitude: location.latitude, longitude: location.longitude, heading: nil, accuracyRadius: nil, venue: MapVenue(title: title, address: location.address, provider: nil, id: nil, type: nil), liveBroadcastingTimeout: nil, liveProximityNotificationRadius: nil)
            showModal(with: LocationModalPreview(arguments.context, map: map, peer: nil, messageId: nil), for: arguments.context.window)
        })
    }
}

func regramProfileEntries<Context: AccountContextProtocol>(_ original: [PeerInfoEntry], view: PeerView, arguments: PeerInfoArguments<Context>, firstMessage: Message?) -> [PeerInfoEntry] {
    let editing = (arguments.state as? UserInfoState)?.editingState != nil || (arguments.state as? GroupInfoState)?.editingState != nil || (arguments.state as? ChannelInfoState)?.editingState != nil
    guard !editing, let peer = peerViewMainPeer(view) else { return original }
    let settings = RegramPreferences.shared.settings(accountId: arguments.context.peerId.toInt64())
    let language = appCurrentLanguage.primaryLanguage.languageCode
    func string(_ key: String) -> String { regramLocalizedString(key, languageCode: language) }
    var details: [(id: Int, label: String, text: String)] = []
    if peer is TelegramGroup || peer is TelegramChannel, let remark = RGGroupRemarks.shared.name(accountId: arguments.context.peerId.toInt64(), peerId: peer.id.toInt64()) {
        details.append((6, string("profile.localRemark"), remark))
    }
    if settings["showProfileId"].bool && !FastSettings.canViewPeerId {
        let label: String
        if let user = peer as? TelegramUser { label = user.botInfo == nil ? "profile.userId" : "profile.botId" }
        else if let channel = peer as? TelegramChannel, case .broadcast = channel.info { label = "profile.channelId" }
        else { label = "profile.groupId" }
        details.append((1, string(label), String(peer.id.id._internalGetInt64Value())))
    }
    if settings["showDC"].bool {
        if let resource = peer.smallProfileImage?.resource as? CloudPeerPhotoSizeMediaResource {
            let id = resource.datacenterId
            let region: String?
            switch id { case 1, 3: region = "Miami"; case 2, 4: region = "Amsterdam"; case 5: region = "Singapore"; default: region = nil }
            details.append((2, string("profile.photoDC"), "DC\(id)" + (region.map { " · " + $0 } ?? "")))
        }
        if let country = (view.cachedData as? CachedUserData)?.peerStatusSettings?.phoneCountry, !country.isEmpty {
            let countryName = Locale(identifier: language).localizedString(forRegionCode: country) ?? country
            details.append((3, string("profile.phoneCountry"), countryName + " (\(country))"))
        }
    }
    if settings["showCreationDate"].bool {
        var timestamp: Int32?
        if let group = peer as? TelegramGroup { timestamp = group.creationDate }
        else if let firstMessage {
            timestamp = firstMessage.timestamp
            for media in firstMessage.media {
                if let action = media as? TelegramMediaAction, case let .channelMigratedFromGroup(_, groupId) = action.action, let group = firstMessage.peers[groupId] as? TelegramGroup { timestamp = group.creationDate }
            }
        }
        if let timestamp, timestamp > 0 {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: language)
            formatter.dateStyle = .medium
            details.append((4, string("profile.created"), formatter.string(from: Date(timeIntervalSince1970: Double(timestamp)))))
        }
    }
    if settings["showRegDate"].bool, let user = peer as? TelegramUser, user.botInfo == nil {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        let registered = (view.cachedData as? CachedUserData)?.peerStatusSettings?.registrationDate
        let parts = registered?.split(separator: ".").compactMap { Int($0) }
        if let parts, parts.count == 2, (1...12).contains(parts[0]), (2013...Calendar.current.component(.year, from: Date())).contains(parts[1]), let date = Calendar(identifier: .gregorian).date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: parts[1], month: parts[0], day: 1)) {
            formatter.setLocalizedDateFormatFromTemplate("yyyyMMMM")
            details.append((5, string("profile.registered"), formatter.string(from: date)))
        } else if let estimate = regramEstimateRegistrationDate(userId: user.id.id._internalGetInt64Value()) {
            formatter.setLocalizedDateFormatFromTemplate(estimate.to - estimate.from > 400 * 86400 ? "yyyy" : "yyyyMMMM")
            let midpoint = estimate.from + (estimate.to - estimate.from) / 2
            let date = Date(timeIntervalSince1970: Double(midpoint))
            details.append((5, string("profile.registeredEstimate"), "~" + formatter.string(from: date)))
        }
    }
    var locationEntry: RegramGroupProfileLocationEntry?
    if RegramGroupProfileSettingItem.location.isVisible(settings: settings), let channel = peer as? TelegramChannel, case .group = channel.info, channel.flags.contains(.isCreator), let location = (view.cachedData as? CachedChannelData)?.peerGeoLocation {
        locationEntry = RegramGroupProfileLocationEntry(location: location, title: channel.title, label: string("GroupInfo.Location"), viewType: details.isEmpty ? .singleItem : .lastItem)
    }
    var entries = regramProfilePrivacyEntries(original, view: view, arguments: arguments)
    guard !details.isEmpty || locationEntry != nil else { return entries.enumerated().map { RegramOrderedPeerInfoEntry(order: $0.offset, entry: $0.element) } }
    let insert = min(1, entries.count)
    var additions: [PeerInfoEntry] = [RegramProfileDetailEntry(index: 0, label: "", text: "", viewType: .singleItem)]
    let count = details.count + (locationEntry == nil ? 0 : 1)
    for (position, detail) in details.enumerated() {
        let type: GeneralViewType = count == 1 ? .singleItem : position == 0 ? .firstItem : position == count - 1 ? .lastItem : .innerItem
        additions.append(RegramProfileDetailEntry(index: detail.id, label: detail.label, text: detail.text, viewType: type))
    }
    if let locationEntry { additions.append(locationEntry) }
    entries.insert(contentsOf: additions, at: insert)
    return entries.enumerated().map { RegramOrderedPeerInfoEntry(order: $0.offset, entry: $0.element) }
}

func regramFirstProfileMessage<Context: AccountContextProtocol>(context: Context, peerId: PeerId) -> Signal<Message?, NoError> {
    guard peerId.namespace == Namespaces.Peer.CloudChannel else { return .single(nil) }
    let enabled = regramPreferenceChanges(accountId: context.peerId.toInt64()) |> map { _ in RegramPreferences.shared.settings(accountId: context.peerId.toInt64())["showCreationDate"].bool } |> distinctUntilChanged
    return enabled |> mapToSignal { enabled -> Signal<Message?, NoError> in
        guard enabled else { return .single(nil) }
        let message = context.engine.messages.getMessagesLoadIfNecessary([MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: 1)])
        |> `catch` { _ in .single(.result([])) }
        |> mapToSignal { result -> Signal<Message?, NoError> in
            guard case let .result(messages) = result else { return .complete() }
            return .single(messages.first)
        }
        return .single(nil) |> then(message)
    }
}
