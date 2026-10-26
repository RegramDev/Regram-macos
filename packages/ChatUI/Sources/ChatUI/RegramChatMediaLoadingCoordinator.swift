import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import TelegramContext
import TelegramMediaUtils
import SwiftSignalKit
import FetchManager
import MessageUtils
import RegramCore

private struct RegramChatMediaPreloadKey: Hashable {
    let messageId: MessageId
    let resourceId: String
}

private final class RegramChatMediaPreloadContext {
    let version: UInt32
    let partial: Bool
    let disposable: Disposable
    var removalTimer: SwiftSignalKit.Timer?

    init(version: UInt32, partial: Bool, disposable: Disposable) {
        self.version = version
        self.partial = partial
        self.disposable = disposable
    }

    deinit {
        removalTimer?.invalidate()
        disposable.dispose()
    }
}

final class RegramChatMediaLoadingCoordinator {
    private let context: any AccountContextProtocol
    private let owner = Int64.random(in: Int64.min...Int64.max)
    private weak var table: TableView?
    private var active = false
    private var previousFirstVisible: Int?
    private var observer: NSObjectProtocol?
    private var contexts: [RegramChatMediaPreloadKey: RegramChatMediaPreloadContext] = [:]
    private var retention = RegramMediaPreloadRetention<RegramChatMediaPreloadKey>()

    init(context: any AccountContextProtocol) {
        self.context = context
        observer = NotificationCenter.default.addObserver(forName: RegramPreferences.didChange, object: nil, queue: .main) { [weak self] notification in
            guard let self, notification.object as? Int64 == self.context.peerId.toInt64() else { return }
            self.clear()
            self.refresh()
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        context.fetchManager.setRegramChatMediaPriority(owner: owner, visibleResourceIds: [], preloadResourceIds: [])
        contexts.removeAll()
    }

    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        if !value { clear() }
        refresh()
    }

    func update(table: TableView) {
        self.table = table
        refresh()
    }

    private func clear() {
        contexts.removeAll()
        retention.reset()
        context.fetchManager.setRegramChatMediaPriority(owner: owner, visibleResourceIds: [], preloadResourceIds: [])
    }

    private func remove(_ key: RegramChatMediaPreloadKey) {
        retention.rescue(key)
        contexts.removeValue(forKey: key)
    }

    private func media(in message: Message) -> [(Media, String)] {
        var result: [(Media, String)] = []
        func append(_ media: Media) {
            if let file = media as? TelegramMediaFile {
                result.append((file, file.resource.id.stringRepresentation))
            } else if let image = media as? TelegramMediaImage, let representation = image.representationForDisplayAtSize(.init(width: 1280, height: 1280)) {
                result.append((image, representation.resource.id.stringRepresentation))
            }
        }
        for media in message.media {
            if let webpage = media as? TelegramMediaWebpage, case let .Loaded(content) = webpage.content {
                if let image = content.image { append(image) }
                if let file = content.file { append(file) }
            } else { append(media) }
        }
        return result
    }

    private func refresh() {
        guard active, RegramPreferences.shared.settings(accountId: context.peerId.toInt64())["mediaLoadingExperiment"].bool, let table else { clear(); return }
        let visible = table.visibleRows()
        guard visible.location != NSNotFound, visible.length > 0 else { clear(); return }
        let lower = max(0, visible.lowerBound)
        let upper = min(table.count, visible.upperBound)
        guard lower < upper else { clear(); return }
        let towardStart = previousFirstVisible.map { lower < $0 } ?? true
        previousFirstVisible = lower
        var visibleResources: [String] = []
        for index in lower..<upper {
            guard let row = table.item(at: index) as? ChatRowItem else { continue }
            for message in row.messages { visibleResources.append(contentsOf: media(in: message).map { $0.1 }) }
        }
        let adjacentRows = towardStart ? Array((0..<lower).reversed()) : Array(upper..<table.count)
        var scannedMedia = 0
        var valid = Set<RegramChatMediaPreloadKey>()
        var preloadResources: [String] = []
        for index in adjacentRows {
            if scannedMedia >= RegramMediaLoadingPolicy.preloadCount { break }
            guard let row = table.item(at: index) as? ChatRowItem else { continue }
            for message in row.messages {
                guard !message.containsSecretMedia, !message.flags.contains(.Unsent) else { continue }
                for (media, resourceId) in media(in: message) {
                    if scannedMedia >= RegramMediaLoadingPolicy.preloadCount { break }
                    scannedMedia += 1
                    let full = row.downloadSettings.isDownloable(message)
                    let partial = !full && row.entry.autoplayMedia.preloadVideos && (media as? TelegramMediaFile)?.isStreamable == true && message.id.peerId.namespace != Namespaces.Peer.SecretChat
                    guard full || partial else { continue }
                    let key = RegramChatMediaPreloadKey(messageId: message.id, resourceId: resourceId)
                    valid.insert(key)
                    preloadResources.append(resourceId)
                    if let existing = contexts[key], existing.version != message.stableVersion || existing.partial != partial { remove(key) }
                    if let existing = contexts[key] {
                        retention.rescue(key)
                        existing.removalTimer?.invalidate()
                        existing.removalTimer = nil
                        continue
                    }
                    let currentIndex = (table.item(at: lower) as? ChatRowItem)?.messageIndex
                    let toLater = currentIndex.map { MessageIndex(message) > $0 } ?? !towardStart
                    let priority = FetchManagerPriority.foregroundPrefetch(direction: toLater ? .toLater : .toEarlier, localOrder: MessageIndex(message))
                    let fetch: Signal<Void, NoError>
                    if let file = media as? TelegramMediaFile {
                        let ranges = partial ? IndexSet(integersIn: 0..<(2 * 1024 * 1024)) : IndexSet(integersIn: 0..<Int(Int32.max))
                        fetch = messageMediaFileInteractiveFetched(context: context, messageId: message.id, messageReference: MessageReference(message), file: file, ranges: ranges, userInitiated: false, priority: priority)
                    } else if let image = media as? TelegramMediaImage {
                        fetch = regramMessagePhotoInteractiveFetched(context: context, message: message, image: image, userInitiated: false, priority: priority)
                    } else { continue }
                    contexts[key] = RegramChatMediaPreloadContext(version: message.stableVersion, partial: partial, disposable: fetch.start())
                }
            }
        }
        for key in Array(contexts.keys) where !valid.contains(key) && retention.pending[key] == nil {
            let pending = retention.deferRemoval(key, now: ProcessInfo.processInfo.systemUptime)
            for evicted in pending.evicted { remove(evicted) }
            guard let existing = contexts[key] else { continue }
            let timer = SwiftSignalKit.Timer(timeout: RegramMediaLoadingPolicy.removalGraceInterval, repeat: false, completion: { [weak self] in
                guard let self, self.retention.expire(key, ticket: pending.ticket, now: ProcessInfo.processInfo.systemUptime) else { return }
                self.remove(key)
            }, queue: .mainQueue())
            existing.removalTimer = timer
            timer.start()
        }
        context.fetchManager.setRegramChatMediaPriority(owner: owner, visibleResourceIds: visibleResources, preloadResourceIds: preloadResources)
    }
}
