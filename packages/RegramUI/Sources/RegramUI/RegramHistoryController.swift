import Cocoa
import Postbox
import TelegramCore
import TelegramContext
import TelegramTheme
import TelegramUtils
import SwiftSignalKit
import TGUIKit
import InputDataUI
import GeneralRows
import AlertsUI
import RegramSignals
import ChatHistoryModel
import RegramCore

private struct HistoryVersion {
    let index: Int
    let text: String
    let date: Int32
    let current: Bool
    let original: Bool
    let image: TelegramMediaImage?
    let data: Data?
    let spoiler: Bool
}

private struct HistoryPhotos: Equatable {
    var images: [Int: NSImage] = [:]
    var loading = Set<Int>()
    var failed = Set<Int>()
    var revealed = Set<Int>()
}

public func RegramEditHistoryController(context: any AccountContextProtocol, message: Message, focusSetting: String? = nil) -> InputDataController? {
    guard let history = message.rgEditHistory else { return nil }
    let accountId = context.peerId.toInt64()
    let request = MetaDisposable()
    let lifetime = Atomic(value: UUID())
    let expectedVersion = Atomic(value: message.stableVersion)
    var photoRequests: [Int: DisposableSet] = [:]
    let currentDate = message.attributes.compactMap { ($0 as? EditedMessageAttribute)?.date }.first ?? message.timestamp
    let currentImage = message.containsSecretMedia ? nil : message.media.compactMap { $0 as? TelegramMediaImage }.first
    var versions = [HistoryVersion(index: history.entries.count, text: message.text, date: currentDate, current: true, original: false, image: currentImage, data: currentImage.flatMap { rgEditHistoryCachedImageData(image: $0, mediaBox: context.account.postbox.mediaBox) }, spoiler: message.attributes.contains { $0 is MediaSpoilerMessageAttribute })]
    for (index, entry) in history.entries.enumerated().reversed() {
        versions.append(HistoryVersion(index: index, text: entry.text, date: entry.date, current: false, original: index == 0 && entry.date == message.timestamp, image: entry.image, data: entry.imageData, spoiler: entry.imageHasSpoiler))
    }
    var initialPhotos = HistoryPhotos()
    for version in versions { if let data = version.data, let image = NSImage(data: data) { initialPhotos.images[version.index] = image } }
    let photos = Atomic(value: initialPhotos)
    let photoPromise = ValuePromise(initialPhotos, ignoreRepeated: true)
    func updatePhotos(_ transform: (inout HistoryPhotos) -> Void) { photoPromise.set(photos.modify { current in var value = current; transform(&value); return value }) }

    func validate(photos: Bool = false) -> Signal<Bool, NoError> {
        context.account.postbox.transaction { transaction in
            guard let current = transaction.getMessage(message.id), current.stableVersion == expectedVersion.with({ $0 }) else { return false }
            let cached = transaction.getPeerCachedData(peerId: current.id.peerId)
            guard regramCanSaveMessage(current, accountId: accountId, cachedData: cached) else { return false }
            if photos {
                if current.isCopyProtected() { return false }
                if let cached = cached as? CachedUserData, cached.flags.contains(.copyProtectionEnabled) || cached.flags.contains(.myCopyProtectionEnabled) { return false }
            }
            return true
        }
    }
    func copy(_ text: String) {
        let token = lifetime.with { $0 }
        request.set((validate() |> deliverOnMainQueue).start(next: { allowed in
            guard allowed, lifetime.with({ $0 == token }) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }))
    }
    func refreshVersionAfterLocalCache() -> Signal<Never, NoError> {
        context.account.postbox.transaction { transaction in
            guard let current = transaction.getMessage(message.id), current.text == message.text,
                  current.textEntitiesAttribute?.entities == message.textEntitiesAttribute?.entities,
                  current.media.count == message.media.count,
                  zip(current.media, message.media).allSatisfy({ $0.isEqual(to: $1) }),
                  let updated = current.rgEditHistory, updated.entries.count == history.entries.count,
                  zip(updated.entries, history.entries).allSatisfy({ $0.text == $1.text && $0.entities == $1.entities && $0.date == $1.date && $0.image?.imageId == $1.image?.imageId && $0.imageHasSpoiler == $1.imageHasSpoiler }) else { return }
            _ = expectedVersion.swap(current.stableVersion)
        } |> ignoreValues
    }
    func loadPhoto(_ version: HistoryVersion) {
        guard let image = version.image, let representation = image.representations.max(by: { Int64($0.dimensions.width) * Int64($0.dimensions.height) < Int64($1.dimensions.width) * Int64($1.dimensions.height) }),
              !photos.with({ $0.loading.contains(version.index) }) else { return }
        let token = lifetime.with { $0 }
        let operation = DisposableSet()
        photoRequests[version.index]?.dispose()
        photoRequests[version.index] = operation
        updatePhotos { $0.loading.insert(version.index); $0.failed.remove(version.index) }
        func fail() {
            guard lifetime.with({ $0 == token }) else { return }
            operation.dispose()
            updatePhotos { $0.loading.remove(version.index); $0.failed.insert(version.index) }
        }
        operation.add((validate(photos: true) |> deliverOnMainQueue).start(next: { allowed in
            guard allowed, lifetime.with({ $0 == token }) else { fail(); return }
            let data = context.account.postbox.mediaBox.resourceData(representation.resource) |> filter { $0.complete } |> take(1) |> timeout(120, queue: .concurrentDefaultQueue(), alternate: .complete()) |> deliverOnMainQueue
            var receivedData = false
            operation.add(data.start(next: { resource in
                receivedData = true
                guard lifetime.with({ $0 == token }) else { return }
                guard resource.size <= Int64(RGEditHistoryEntry.maximumImageBytes),
                      let data = try? Data(contentsOf: URL(fileURLWithPath: resource.path)),
                      data.count <= RGEditHistoryEntry.maximumImageBytes, let loaded = NSImage(data: data) else { fail(); return }
                operation.add((validate(photos: true) |> deliverOnMainQueue).start(next: { allowed in
                    guard allowed, lifetime.with({ $0 == token }) else { fail(); return }
                    updatePhotos { $0.images[version.index] = loaded; $0.loading.remove(version.index); $0.failed.remove(version.index) }
                    if !version.current {
                        operation.add((rgSaveEditHistoryImageData(postbox: context.account.postbox, messageId: message.id, versionIndex: version.index, expectedImageId: image.imageId, data: data) |> then(refreshVersionAfterLocalCache())).start())
                    }
                }))
            }, completed: {
                if !receivedData, photos.with({ $0.loading.contains(version.index) }) { fail() }
            }))
            operation.add(fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .peer(message.id.peerId), userContentType: .image, reference: .media(media: .standalone(media: image), resource: representation.resource)).start(error: { _ in DispatchQueue.main.async { fail() } }))
        }))
    }
    func needsOriginal(_ image: NSImage, version: HistoryVersion) -> Bool {
        guard let photo = version.image else { return false }
        let width = image.representations.map(\.pixelsWide).max() ?? 0
        let height = image.representations.map(\.pixelsHigh).max() ?? 0
        return photo.representations.contains { Int($0.dimensions.width) > width || Int($0.dimensions.height) > height }
    }
    let permission = combineLatest(regramPreferenceChanges(accountId: accountId), context.account.postbox.peerView(id: message.id.peerId)) |> mapToSignal { _, _ in validate() }
    let signal = combineLatest(permission, photoPromise.get(), appearanceSignal) |> map { canExport, photoState, _ -> InputDataSignalValue in
        var rows: [InputDataEntry] = [.sectionId(0, type: .normal)]
        let showSpoilers = RegramPreferences.shared.settings(accountId: accountId)["automaticallyRevealSpoilers"].bool
        for (position, version) in versions.enumerated() {
            let index = Int32(position * 10)
            if version.image != nil {
                if let image = photoState.images[version.index] {
                    let hidden = version.spoiler && !showSpoilers && !photoState.revealed.contains(version.index)
                    rows.append(.custom(sectionId: 1, index: index, value: .none, identifier: InputDataIdentifier("history_photo_\(version.index)"), equatable: InputDataEquatable("\(image.hash)-\(hidden)"), comparable: nil, item: { size, stableId in
                        RegramHistoryPhotoRowItem(size, stableId: stableId, image: image, concealed: hidden, action: {
                            if hidden { updatePhotos { $0.revealed.insert(version.index) } }
                            else { context.bindings.rootNavigation().push(regramHistoryImageController(context: context, image: image)) }
                        })
                    }))
                    if !photoState.loading.contains(version.index), needsOriginal(image, version: version) {
                        rows.append(.general(sectionId: 1, index: index + 1, value: .none, error: nil, identifier: InputDataIdentifier("history_original_\(version.index)"), data: .init(name: regramString("EditHistory.LoadOriginal"), color: theme.colors.accent, type: .none, viewType: .singleItem, action: { loadPhoto(version) })))
                    }
                } else if !photoState.loading.contains(version.index) {
                    rows.append(.general(sectionId: 1, index: index + 1, value: .none, error: nil, identifier: InputDataIdentifier("history_load_\(version.index)"), data: .init(name: regramString("EditHistory.LoadPhoto"), color: theme.colors.accent, type: .none, viewType: .singleItem, action: { loadPhoto(version) })))
                }
                if photoState.loading.contains(version.index) {
                    rows.append(.general(sectionId: 1, index: index + 2, value: .none, error: nil, identifier: InputDataIdentifier("history_loading_\(version.index)"), data: .init(name: regramString("EditHistory.LoadingPhoto"), color: theme.colors.grayText, type: .loading, viewType: .singleItem)))
                }
                if photoState.failed.contains(version.index) {
                    rows.append(.desc(sectionId: 1, index: photoState.images[version.index] == nil ? index : index + 3, text: .plain(regramString("EditHistory.PhotoUnavailable")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
                }
            }
            if !version.text.isEmpty || version.image == nil {
                rows.append(.desc(sectionId: 1, index: index + 4, text: .plain(version.text.isEmpty ? regramString("EditHistory.EmptyText") : version.text), data: .init(color: version.text.isEmpty ? theme.colors.grayText : theme.colors.text, viewType: .singleItem, contextMenu: {
                    canExport && !version.text.isEmpty ? [ContextMenuItem(regramString("EditHistory.Copy"), handler: { copy(version.text) })] : []
                })))
            }
            if version.current || version.original {
                rows.append(.desc(sectionId: 1, index: index + 5, text: .plain(regramString(version.current ? "EditHistory.Current" : "EditHistory.Original")), data: .init(color: version.current ? theme.colors.accent : theme.colors.grayText, viewType: .textTopItem)))
            }
            let date = DateFormatter.localizedString(from: Date(timeIntervalSince1970: TimeInterval(version.date)), dateStyle: .medium, timeStyle: .medium)
            rows.append(.desc(sectionId: 1, index: index + 6, text: .plain(date), data: .init(color: theme.colors.grayText, viewType: .textBottomItem)))
        }
        rows.append(.desc(sectionId: 1, index: Int32(versions.count * 10), text: .plain(regramString("EditHistory.Notice")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        return InputDataSignalValue(entries: rows)
    }
    func stop() {
        _ = lifetime.swap(UUID())
        request.set(nil)
        for operation in photoRequests.values { operation.dispose() }
        photoRequests.removeAll()
        updatePhotos { $0.loading = [] }
    }
    let controller = InputDataController(dataSignal: signal, title: regramString("EditHistory.Title"), afterDisappear: stop, removeAfterDisappear: false, hasDone: false, identifier: "regram.editHistory")
    controller.didAppear = { (_: InputDataController) in
        if let current = versions.first, current.image != nil, !photos.with({ $0.images[current.index] != nil }) { loadPhoto(current) }
    }
    controller.onDeinit = { stop(); request.dispose() }
    regramFocusSettings(controller, page: "editHistory", item: focusSetting)
    return controller
}
private struct RetainedState: Equatable {
    var peerId: PeerId?
    var title = ""
    var query = ""
    var messages: [Message] = []
    var cursors: [Int32: MessageIndex] = [:]
    var ended = Set<Int32>()
    var scanned = 0
    var loading = false
    var generation = UUID()

    static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.peerId == rhs.peerId && lhs.title == rhs.title && lhs.query == rhs.query && lhs.messages.map(\.stableVersion) == rhs.messages.map(\.stableVersion) && lhs.messages.map(\.id) == rhs.messages.map(\.id) && lhs.scanned == rhs.scanned && lhs.loading == rhs.loading && lhs.ended == rhs.ended && lhs.generation == rhs.generation
    }
}

public func RegramRetainedMessagesController(context: any AccountContextProtocol, focusSetting: String? = nil) -> InputDataController {
    let namespaces = [Namespaces.Message.Cloud, Namespaces.Message.Local, Namespaces.Message.SecretIncoming]
    let stateValue = Atomic(value: RetainedState())
    let statePromise = ValuePromise(RetainedState(), ignoreRepeated: true)
    let request = MetaDisposable()
    let selection = MetaDisposable()
    func update(_ transform: (inout RetainedState) -> Void) {
        statePromise.set(stateValue.modify { current in var state = current; transform(&state); return state })
    }
    func load() {
        let state = stateValue.with { $0 }
        guard let peerId = state.peerId, !state.loading, state.ended.count < namespaces.count else { return }
        update { $0.loading = true }
        request.set((context.account.postbox.transaction { transaction -> ([Message], [Int32: MessageIndex], Set<Int32>, Int) in
            var cursors = state.cursors
            var ended = state.ended
            var messages: [Message] = []
            var scanned = 0
            for namespace in namespaces where !ended.contains(namespace) {
                let from = cursors[namespace] ?? MessageIndex.upperBound(peerId: peerId, namespace: namespace)
                let page = transaction.getMessages(peerId: peerId, namespace: namespace, from: from, includeFrom: false, to: MessageIndex.lowerBound(peerId: peerId, namespace: namespace), limit: 150)
                scanned += page.count
                messages.append(contentsOf: page.filter { $0.rgIsRevoked })
                if let last = page.last { cursors[namespace] = last.index }
                if page.count < 150 { ended.insert(namespace) }
            }
            return (messages, cursors, ended, scanned)
        } |> deliverOnMainQueue).start(next: { messages, cursors, ended, scanned in
            guard stateValue.with({ $0.generation }) == state.generation else { return }
            update { value in
                let existing = Set(value.messages.map(\.id))
                value.messages.append(contentsOf: messages.filter { !existing.contains($0.id) })
                value.messages.sort { $0.index > $1.index }
                value.cursors = cursors
                value.ended = ended
                value.scanned += scanned
                value.loading = false
            }
        }))
    }
    let signal = combineLatest(statePromise.get(), appearanceSignal) |> map { state, _ -> InputDataSignalValue in
        let visible = state.messages.filter { state.query.isEmpty || $0.text.localizedCaseInsensitiveContains(state.query) }
        var rows: [InputDataEntry] = [
            .sectionId(0, type: .normal),
            .general(sectionId: 1, index: 0, value: .none, error: nil, identifier: InputDataIdentifier("revokedMessages.selectChat"), data: .init(name: state.title.isEmpty ? regramString("ChatPreferences.SelectChat") : state.title, color: theme.colors.text, type: .next, viewType: .firstItem, action: {
                selection.set((RegramUIHooks.shared.selectChat(context, state.peerId) |> mapToSignal { id in
                    context.account.postbox.transaction { $0.getPeer(id) }
                } |> deliverOnMainQueue).start(next: { peer in
                    guard let peer else { return }
                    request.set(nil)
                    update { $0 = RetainedState(peerId: peer.id, title: peer.displayTitle) }
                    load()
                }))
            })),
            .input(sectionId: 1, index: 1, value: .string(state.query), error: nil, identifier: InputDataIdentifier("revokedMessages.search"), mode: .plain, data: .init(viewType: .lastItem), placeholder: nil, inputPlaceholder: regramString("Revoked.Search"), filter: { $0 }, limit: 4096),
            .desc(sectionId: 1, index: 2, text: .plain(regramString("Revoked.Notice")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)),
            .sectionId(1, type: .normal)
        ]
        for (index, message) in visible.enumerated() {
            let date = DateFormatter.localizedString(from: Date(timeIntervalSince1970: TimeInterval(message.timestamp)), dateStyle: .medium, timeStyle: .none)
            let viewType: GeneralViewType = visible.count == 1 ? .singleItem : index == 0 ? .firstItem : index == visible.count - 1 ? .lastItem : .innerItem
            rows.append(.general(sectionId: 2, index: Int32(index + 3), value: .none, error: nil, identifier: InputDataIdentifier("retained_\(message.id.namespace)_\(message.id.id)"), data: .init(name: String((message.text.isEmpty ? regramString("Revoked.Media") : message.text).prefix(400)), color: theme.colors.text, type: .next, viewType: viewType, description: date, action: { RegramUIHooks.shared.openMessage(context, message.id, message.threadId) })))
        }
        if state.peerId != nil {
            rows.append(.sectionId(2, type: .normal))
            if state.loading { rows.append(.loading) }
            else if state.ended.count < namespaces.count {
                rows.append(.general(sectionId: 3, index: Int32(visible.count + 3), value: .none, error: nil, identifier: InputDataIdentifier("revokedMessages.loadMore"), data: .init(name: regramString("Revoked.LoadMore"), color: theme.colors.accent, type: .none, viewType: state.messages.isEmpty ? .singleItem : .firstItem, action: load)))
            } else if visible.isEmpty {
                rows.append(.desc(sectionId: 3, index: Int32(visible.count + 3), text: .plain(regramString("Revoked.Empty")), data: .init(color: theme.colors.listGrayText, viewType: .singleItem)))
            }
            if !state.messages.isEmpty {
                rows.append(.general(sectionId: 3, index: Int32(visible.count + 4), value: .none, error: nil, identifier: InputDataIdentifier("revokedMessages.clearLoaded"), data: .init(name: regramString("Revoked.ClearLoaded"), color: theme.colors.redUI, type: .none, viewType: !state.loading && state.ended.count < namespaces.count ? .lastItem : .singleItem, enabled: !state.loading, action: {
                    verifyAlert(for: context.window, header: regramString("Revoked.ClearLoaded"), information: regramString("Revoked.Clear.Notice"), successHandler: { _ in
                        guard stateValue.with({ $0.generation == state.generation && !$0.loading }) else { return }
                        update { $0.loading = true }
                        request.set((context.account.postbox.transaction { transaction in
                            guard stateValue.with({ $0.generation == state.generation }) else { return }
                            let ids = state.messages.map(\.id).filter { transaction.getMessage($0)?.rgIsRevoked == true }
                            context.engine.messages.deleteMessages(transaction: transaction, ids: ids)
                        } |> deliverOnMainQueue).start(next: { _ in
                            guard stateValue.with({ $0.generation }) == state.generation else { return }
                            update { $0.messages = []; $0.loading = false }
                        }))
                    })
                })))
            }
            rows.append(.desc(sectionId: 3, index: Int32(visible.count + 5), text: .plain("\(state.scanned) " + regramString("Revoked.Scanned")), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        }
        return InputDataSignalValue(entries: rows)
    }
    let controller = InputDataController(dataSignal: signal, title: regramString("Revoked.Title"), updateDatas: { data in
        if let query = data[InputDataIdentifier("revokedMessages.search")]?.stringValue { update { $0.query = query } }
        return .fail(.none)
    }, removeAfterDisappear: false, hasDone: false, identifier: "regram.revokedMessages")
    controller.onDeinit = { update { $0.generation = UUID() }; request.dispose(); selection.dispose() }
    regramFocusSettings(controller, page: "revokedMessages", item: focusSetting)
    return controller
}
