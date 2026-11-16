import AppKit
import Postbox
import RegramCore
import SwiftSignalKit
import TelegramCore

public func rgAdInput(_ message: Message) -> RGAdInput {
    let source = message.text as NSString
    let entities = (message.textEntitiesAttribute?.entities ?? []).compactMap { entity -> RGAdEntity? in
        let range = RGAdRange(entity.range.lowerBound, entity.range.upperBound)
        guard range.lower >= 0, range.upper <= source.length, range.upper > range.lower else { return nil }
        let kind: RGAdEntity.Kind
        let value: String?
        switch entity.type {
        case .TextUrl(let url):
            kind = .link
            value = url
        case .Url:
            kind = .link
            value = source.substring(with: range.nsRange)
        case .Mention:
            kind = .mention
            value = source.substring(with: range.nsRange)
        case .TextMention:
            kind = .mention
            value = nil
        case .Code, .Pre:
            kind = .code
            value = nil
        case .BlockQuote:
            kind = .quote
            value = nil
        case .CustomEmoji(_, let fileId):
            kind = .customEmoji
            value = String(fileId)
        default:
            kind = .format
            value = nil
        }
        return RGAdEntity(range: range, kind: kind, value: value)
    }
    let markup = message.attributes.first { $0 is ReplyMarkupMessageAttribute } as? ReplyMarkupMessageAttribute
    let buttons = (markup?.flags.contains(.inline) == true ? markup?.rows ?? [] : []).enumerated().map { row, value in
        value.buttons.enumerated().map { column, button -> RGAdButton in
            let target: String?
            switch button.action {
            case .url(let url), .urlAuth(let url, _), .openWebView(let url, _): target = url
            default: target = nil
            }
            return RGAdButton(id: "\(row):\(column)", title: button.title, target: target)
        }
    }
    let preview = message.media.compactMap { media -> String? in
        if let web = media as? TelegramMediaWebpage, case .Loaded(let content) = web.content { return content.url }
        return nil
    }.first
    return RGAdInput(
        text: message.text, peerId: message.id.peerId.toInt64(), entities: entities, buttons: buttons,
        hasMedia: message.media.contains { !($0 is TelegramMediaWebpage) }, previewTarget: preview)
}

public func rgCanCorrectAds(_ message: Message) -> Bool {
    message.id.namespace == Namespaces.Message.Cloud && message.id.peerId.namespace != Namespaces.Peer.SecretChat
        && !message.isCopyProtected() && !message.containsSecretMedia && message.richText == nil
        && (!message.text.isEmpty || !message.media.isEmpty || message.attributes.contains { $0 is ReplyMarkupMessageAttribute })
}

private func rgIsAdFilteringPeer(_ message: Message) -> Bool {
    let peer = message.peers[message.id.peerId]
    return peer is TelegramChannel || peer is TelegramGroup
}

@available(macOS 10.15, *)
public func rgAdSampleDraft(_ message: Message, store: RGAdSampleStore) throws -> RGAdSample {
    try store.draft(
        input: rgAdInput(message), messageKey: rgAdSampleKey(message), mediaKinds: rgAdMediaKinds(message),
        mediaIdentity: rgAdMediaIdentity(message))
}
private func rgAdSampleKey(_ message: Message) -> String { "\(message.id.peerId.toInt64()):\(message.id.namespace):\(message.id.id)" }
private func rgAdMediaIdentity(_ message: Message) -> String { message.media.map { String(describing: $0.id) }.joined(separator: ":") }
private func rgAdMediaKinds(_ message: Message) -> [String] {
    message.media.filter { !($0 is TelegramMediaWebpage) }.map { media in
        if media is TelegramMediaImage { return "image" }
        if let file = media as? TelegramMediaFile { return file.isVideo ? "video" : file.isVoice ? "voice" : "file" }
        return "other"
    }
}

private final class RGAdOriginalAttribute: MessageAttribute {
    let source: Message?
    let removedRanges: [RGAdRange]
    let bodyLength: Int
    init(_ source: Message, projection: RGAdProjection? = nil) {
        self.source = source
        removedRanges = projection?.removedRanges ?? []
        bodyLength = projection?.text.utf16.count ?? source.text.utf16.count
    }
    required init(decoder: PostboxDecoder) {
        source = nil
        removedRanges = []
        bodyLength = 0
    }
    func encode(_ encoder: PostboxEncoder) {}
}

public func rgAdOriginalMessage(_ message: Message) -> Message {
    (message.attributes.first { $0 is RGAdOriginalAttribute } as? RGAdOriginalAttribute)?.source ?? message
}

public func rgAdMessageWasFiltered(_ message: Message) -> Bool { message.attributes.contains { $0 is RGAdOriginalAttribute } }

func rgAdTextWasFiltered(_ message: Message) -> Bool {
    message.attributes.contains { ($0 as? RGAdOriginalAttribute)?.removedRanges.isEmpty == false }
}

public func rgAdQuoteIsVisible(_ quote: EngineMessageReplyQuote, in message: Message) -> Bool {
    guard let attribute = message.attributes.first(where: { $0 is RGAdOriginalAttribute }) as? RGAdOriginalAttribute else { return true }
    guard attribute.bodyLength > 0, let original = attribute.source, let offset = quote.offset else { return false }
    let source = original.text as NSString
    guard offset >= 0, quote.text.utf16.count <= source.length, offset <= source.length - quote.text.utf16.count else { return false }
    let range = RGAdRange(offset, offset + quote.text.utf16.count)
    return source.substring(with: range.nsRange) == quote.text && !attribute.removedRanges.contains(where: { $0.intersects(range) })
}

public func rgAdOriginalRange(_ message: Message, range: NSRange) -> NSRange? {
    guard let attribute = message.attributes.first(where: { $0 is RGAdOriginalAttribute }) as? RGAdOriginalAttribute else { return range }
    guard let source = attribute.source, range.location >= 0, range.length > 0, range.location <= attribute.bodyLength,
        range.length <= attribute.bodyLength - range.location
    else { return nil }
    var originalStart = 0
    var displayStart = 0
    for cut in attribute.removedRanges + [RGAdRange(source.text.utf16.count, source.text.utf16.count)] {
        let length = cut.lower - originalStart
        if range.location >= displayStart, NSMaxRange(range) <= displayStart + length {
            return NSRange(location: originalStart + range.location - displayStart, length: range.length)
        }
        originalStart = cut.upper
        displayStart += length
    }
    return nil
}

@available(macOS 12, *)
public final class RegramAdFilterSession {
    public enum Scope: Hashable {
        case history(UUID)
        case pinned(UUID)
        case chatList(UUID)
        case chatListFallback(UUID)
    }

    private static let didChange = Notification.Name("Regram.ReSieve.DidChange")

    public func changes(for scope: Scope) -> Signal<Void, NoError> {
        Signal { [self] subscriber in
            let observer = NotificationCenter.default.addObserver(forName: Self.didChange, object: nil, queue: nil) {
                [weak self] notification in
                guard let self, notification.object as? RegramAdFilterSession === self else { return }
                if let scopes = notification.userInfo?["scopes"] as? Set<Scope>, !scopes.contains(scope) { return }
                subscriber.putNext(())
            }
            subscriber.putNext(())
            return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
        }
    }

    public var preparationRevision: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return workRevision
    }
    private static let registryLock = NSLock()
    private final class WeakSession {
        weak var value: RegramAdFilterSession?
        init(_ value: RegramAdFilterSession) { self.value = value }
    }
    private static var sessions: [String: WeakSession] = [:]
    public static func get(_ account: Account) -> RegramAdFilterSession {
        registryLock.lock()
        defer { registryLock.unlock() }
        let path = account.basePath
        if let session = sessions[path]?.value { return session }
        sessions = sessions.filter { $0.value.value != nil }
        let session = RegramAdFilterSession(path: path)
        sessions[path] = WeakSession(session)
        return session
    }

    private let queue = DispatchQueue(label: "regram.ad-filter", qos: .utility)
    private let lock = NSLock()
    private let store: RGAdSampleStore
    private var knowledge = RGAdPolicy.Knowledge()
    private var lastBatches: [Scope: [MessageId: RGAdInput]] = [:]
    private var lastMedia: [Scope: [MessageId: String]] = [:]
    private var requestedVersions: [Scope: [MessageId: UInt32]] = [:]
    private var requestGenerations: [Scope: UInt64] = [:]
    private var salt = ""
    private var workRevision: UInt64 = 0
    private var loadedSamples = false
    private final class Cached {
        let input: RGAdInput
        let mediaIdentity: String
        let projection: RGAdProjection?
        let revision: UInt32
        let preservesMedia: Bool
        let completed: Bool
        weak var validatedSource: Message?
        init(
            input: RGAdInput, mediaIdentity: String, projection: RGAdProjection?, revision: UInt32, preservesMedia: Bool, source: Message,
            completed: Bool
        ) {
            self.input = input
            self.mediaIdentity = mediaIdentity
            self.projection = projection
            self.revision = revision
            self.preservesMedia = preservesMedia
            self.validatedSource = source
            self.completed = completed
        }
        var estimatedMemoryCost: Int {
            input.estimatedMemoryCost
                + (projection.map { 256 + $0.text.utf8.count * 2 + $0.entities.count * 96 + $0.buttons.flatMap { $0 }.count * 128 } ?? 0)
        }
    }
    private final class Batch {
        let scope: Scope
        let generation: UInt64
        let messages: [Message]
        let account: PeerId
        let inputs: [MessageId: RGAdInput]
        let identities: [MessageId: String]
        let previousHidden: Set<MessageId>
        var cursor = 0
        var incomplete = false
        var requests: [(RGAdWorkRequest, (() -> Void)?)] = []
        init(
            scope: Scope, generation: UInt64, messages: [Message], account: PeerId, inputs: [MessageId: RGAdInput],
            identities: [MessageId: String], previousHidden: Set<MessageId>
        ) {
            self.scope = scope
            self.generation = generation
            self.messages = messages
            self.account = account
            self.inputs = inputs
            self.identities = identities
            self.previousHidden = previousHidden
        }
    }
    private lazy var scheduler = RGAdWorkScheduler(queue: queue)
    private var pending: [Scope: Batch] = [:]
    private var sourceGroups: [PeerId: String] = [:]
    private var sharedCache = RGAdBoundedCache<MessageId, Cached>(countLimit: 2048, costLimit: 8 * 1024 * 1024)
    private var cacheEpoch: UInt64 = 0
    private var refreshWork: DispatchWorkItem?
    private var refreshDeadline: TimeInterval = 0
    private var refreshScopes = Set<Scope>()
    private var refreshAllScopes = false
    private var retryNeeded = false
    private var retryScheduled = false
    private var foreground = true
    private var observers: [NSObjectProtocol] = []
    private var revision: UInt32 = 0
    private var cached: [Scope: [MessageId: Cached]] = [:]
    private var order: [Scope: [MessageId]] = [:]
    private init(path: String) {
        store = RGAdSampleStore(accountDirectory: URL(fileURLWithPath: path))
        queue.async { [weak self] in
            guard let self else { return }
            self.updateWorkConditions()
        }
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                    self?.queue.async { [weak self] in self?.updateWorkConditions() }
                })
        }
        for (name, active) in [(NSApplication.didHideNotification, false), (NSApplication.didUnhideNotification, true)] {
            observers.append(
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                    self?.queue.async { [weak self] in
                        self?.foreground = active
                        self?.updateWorkConditions()
                    }
                })
        }
        DispatchQueue.main.async { [weak self] in
            let visible = NSApp?.isHidden != true
            self?.queue.async { [weak self] in
                self?.foreground = visible
                self?.updateWorkConditions()
            }
        }
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        refreshWork?.cancel()
    }

    private func updateWorkConditions() {
        let conditions = RGAdWorkConditions(
            foreground: foreground, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermal: ProcessInfo.processInfo.thermalState.rawValue)
        scheduler.updateConditions(conditions)
        if !conditions.paused { scheduleRetry() }
    }

    private func scheduleRetry() {
        guard retryNeeded, !retryScheduled else { return }
        retryScheduled = true
        queue.asyncAfter(deadline: .now() + 60) { [weak self] in
            guard let self else { return }
            self.retryScheduled = false
            guard self.retryNeeded, self.foreground, ProcessInfo.processInfo.thermalState.rawValue < 3 else { return }
            self.retryNeeded = false
            self.lock.lock()
            self.workRevision &+= 1
            self.lock.unlock()
            self.changed()
        }
    }

    private func reload() throws {
        let samples = try store.load(reviewedOnly: true)
        let salt = try store.salt()
        knowledge = RGAdPolicy.Knowledge(samples: samples)
        self.salt = salt
        loadedSamples = true
        lastBatches.removeAll()
        lastMedia.removeAll()
        sourceGroups.removeAll()
        pending.removeAll()
        retryNeeded = false
        lock.lock()
        cacheEpoch &+= 1
        workRevision &+= 1
        cached.removeAll()
        order.removeAll()
        sharedCache.removeAll()
        lock.unlock()
        scheduler.discardCancelled()
    }
    private func changed(_ scope: Scope? = nil) {
        let delay = scope.map { priority($0) == 0 ? 0.05 : 0.024 } ?? 0.024
        let deadline = ProcessInfo.processInfo.systemUptime + delay
        lock.lock()
        defer { lock.unlock() }
        if let scope {
            refreshScopes.insert(scope)
        } else {
            refreshAllScopes = true
        }
        if refreshWork != nil && refreshDeadline <= deadline { return }
        refreshWork?.cancel()
        refreshDeadline = deadline
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lock.lock()
            guard self.refreshDeadline == deadline else {
                self.lock.unlock()
                return
            }
            self.refreshWork = nil
            let userInfo: [AnyHashable: Any]? = self.refreshAllScopes ? nil : ["scopes": self.refreshScopes]
            self.refreshScopes.removeAll()
            self.refreshAllScopes = false
            self.lock.unlock()
            NotificationCenter.default.post(name: Self.didChange, object: self, userInfo: userInfo)
        }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    public func perform<T>(
        changes: Bool = false, _ work: @escaping (RGAdSampleStore) throws -> T, completion: @escaping (Result<T, Error>) -> Void
    ) {
        queue.async {
            let result: Result<T, Error>
            do {
                let value = try work(self.store)
                if changes {
                    try self.reload()
                    self.changed()
                }
                result = .success(value)
            } catch { result = .failure(error) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func isCurrent(_ scope: Scope, generation: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return requestGenerations[scope] == generation
    }

    @discardableResult
    public func prepare(_ messages: [Message], accountPeerId: PeerId, scope: Scope, completion: (() -> Void)? = nil) -> RGAdWorkRequest {
        let token = RGAdWorkRequest()
        let roots: [Message]
        let includeReplies: Bool
        switch scope {
        case .chatList, .chatListFallback:
            roots = Array(messages.prefix(capacity(scope)))
            includeReplies = false
        default:
            roots = Array(messages.suffix(capacity(scope)).reversed())
            includeReplies = true
        }
        var sources: [Message] = []
        var seen = Set<MessageId>()
        var replyCount = 0
        for message in roots {
            if seen.insert(message.id).inserted { sources.append(message) }
            if includeReplies, replyCount < 128, canProjectReply(in: message, accountPeerId: accountPeerId),
                let reply = message.attributes.first(where: { $0 is ReplyMessageAttribute }) as? ReplyMessageAttribute,
                let target = message.associatedMessages[reply.messageId], seen.insert(target.id).inserted
            {
                sources.append(rgAdOriginalMessage(target))
                replyCount += 1
            }
        }
        var versions: [MessageId: UInt32] = [:]
        for message in sources { versions[message.id] = message.stableVersion }
        lock.lock()
        if requestedVersions[scope] != versions {
            requestedVersions[scope] = versions
            requestGenerations[scope] = (requestGenerations[scope] ?? 0) &+ 1
        }
        let generation = requestGenerations[scope] ?? 0
        lock.unlock()
        queue.async {
            guard !token.isCancelled else { return }
            guard self.isCurrent(scope, generation: generation) else {
                completion?()
                return
            }
            let eligible = sources.filter { self.canProject($0, accountPeerId: accountPeerId) }
            if !eligible.isEmpty, !self.loadedSamples {
                self.loadedSamples = true
                try? self.reload()
            }
            var inputs: [MessageId: RGAdInput] = [:]
            var identities: [MessageId: String] = [:]
            for message in eligible {
                inputs[message.id] = rgAdInput(message)
                identities[message.id] = rgAdMediaIdentity(message)
            }
            if let batch = self.pending[scope], batch.generation == generation, batch.inputs == inputs, batch.identities == identities {
                batch.requests.append((token, completion))
                return
            }
            guard inputs != self.lastBatches[scope] || identities != self.lastMedia[scope] else {
                completion?()
                return
            }
            let batch = Batch(
                scope: scope, generation: generation, messages: eligible, account: accountPeerId, inputs: inputs, identities: identities,
                previousHidden: self.hiddenMessageIds(in: eligible, accountPeerId: accountPeerId, scope: scope))
            batch.requests.append((token, completion))
            self.pending[scope] = batch
            self.scheduler.enqueue(
                priority: self.priority(scope),
                cancelled: {
                    self.pending[scope] !== batch || !self.isCurrent(scope, generation: generation)
                        || batch.requests.allSatisfy { $0.0.isCancelled }
                },
                step: {
                    if batch.cursor < batch.messages.count {
                        let message = batch.messages[batch.cursor]
                        self.process(message, batch: batch)
                        batch.cursor += 1
                    }
                    if batch.cursor == batch.messages.count {
                        self.finish(batch, completed: true)
                        return true
                    }
                    return false
                }, onCancel: { self.finish(batch, completed: false) })
        }
        return token
    }

    private func capacity(_ scope: Scope) -> Int {
        switch scope {
        case .history: return 512
        case .pinned: return 128
        case .chatList: return 4096
        case .chatListFallback: return 128
        }
    }

    private func priority(_ scope: Scope) -> Int {
        switch scope {
        case .pinned: return 2
        case .history: return 1
        case .chatList, .chatListFallback: return 0
        }
    }

    private func process(_ message: Message, batch: Batch) {
        let scope = batch.scope
        guard canProject(message, accountPeerId: batch.account), let input = batch.inputs[message.id] else { return }
        let mediaIdentity = batch.identities[message.id] ?? ""
        lock.lock()
        let old = cached[scope]?[message.id]
        let reuse = [old, sharedCache[message.id]].compactMap { $0 }.first {
            $0.completed && $0.input == input && $0.mediaIdentity == mediaIdentity
        }
        lock.unlock()
        let value: Cached
        var detection: RGAdProjection?
        if let reuse {
            value = reuse
        } else {
            let group: String
            if let existing = sourceGroups[message.id.peerId] {
                group = existing
            } else {
                if sourceGroups.count >= 1024 { sourceGroups.removeAll() }
                group = RGAdSampleStore.sourceGroup(salt: salt, peerId: message.id.peerId.toInt64())
                sourceGroups[message.id.peerId] = group
            }
            let sampleId = input.hasMedia ? try? RGAdSampleStore.sampleId(
                input: input, salt: salt, messageKey: rgAdSampleKey(message), mediaIdentity: mediaIdentity) : nil
            var completed = true
            let result: RGAdProjection?
            do {
                result = try knowledge.resolve(input, sourceGroup: group, sampleId: sampleId) { input in
                    let semantic = RGAdSemanticClassifier.shared.predict(input)
                    completed = semantic.completed
                    return semantic
                }
            } catch RGAdFilterError.budgetExceeded {
                completed = false
                result = nil
            } catch { result = nil }
            let projected = result?.disposition == .keep ? nil : result
            if !completed {
                batch.incomplete = true
                retryNeeded = true
                scheduleRetry()
                guard projected != nil else { return }
                if let old, old.input == input, old.mediaIdentity == mediaIdentity, old.projection == projected { return }
            }
            detection = projected
            revision &+= 1
            value = Cached(
                input: input, mediaIdentity: mediaIdentity, projection: projected, revision: revision,
                preservesMedia: knowledge.preservesMedia(input, sourceGroup: group, sampleId: sampleId), source: message,
                completed: completed)
        }
        lock.lock()
        if cached[scope]?[message.id] == nil {
            if order[scope, default: []].count >= capacity(scope) + 128, let evicted = order[scope]?.removeFirst() {
                cached[scope]?.removeValue(forKey: evicted)
            }
            order[scope, default: []].append(message.id)
        }
        cached[scope, default: [:]][message.id] = value
        sharedCache.insert(value, for: message.id, cost: value.estimatedMemoryCost)
        lock.unlock()
        if old !== value && (old?.projection != nil || value.projection != nil) {
            changed(scope)
        }
        if let detection, !salt.isEmpty {
            try? store.recordDetection(
                input: input, messageKey: rgAdSampleKey(message), mediaKinds: rgAdMediaKinds(message), mediaIdentity: mediaIdentity,
                projection: detection)
        }
    }

    private func finish(_ batch: Batch, completed: Bool) {
        if pending[batch.scope] === batch { pending.removeValue(forKey: batch.scope) }
        if completed {
            if !batch.incomplete {
                lastBatches[batch.scope] = batch.inputs
                lastMedia[batch.scope] = batch.identities
            }
            lock.lock()
            cached[batch.scope] = cached[batch.scope]?.filter { batch.inputs[$0.key] != nil }
            order[batch.scope] = order[batch.scope]?.filter { batch.inputs[$0] != nil }
            lock.unlock()
            let hidden = hiddenMessageIds(in: batch.messages, accountPeerId: batch.account, scope: batch.scope)
            if hidden != batch.previousHidden { changed(batch.scope) }
            for message in batch.messages
            where hidden.contains(message.id) && !shouldHide(message, accountPeerId: batch.account, scope: batch.scope) {
                if !salt.isEmpty, let input = batch.inputs[message.id] {
                    let projection = RGAdProjection(
                        disposition: .hide, text: "", entities: [], buttons: [], removedRanges: [], removedButtonIds: [],
                        hideLinkPreview: true)
                    try? store.recordDetection(
                        input: input, messageKey: rgAdSampleKey(message), mediaKinds: rgAdMediaKinds(message),
                        mediaIdentity: batch.identities[message.id] ?? "", projection: projection)
                }
            }
        }
        for (token, completion) in batch.requests where !token.isCancelled { completion?() }
    }

    public func release(scope: Scope) {
        lock.lock()
        requestedVersions.removeValue(forKey: scope)
        requestGenerations.removeValue(forKey: scope)
        lock.unlock()
        queue.async {
            self.lastBatches.removeValue(forKey: scope)
            self.lastMedia.removeValue(forKey: scope)
            self.pending.removeValue(forKey: scope)
            self.lock.lock()
            self.cached.removeValue(forKey: scope)
            self.order.removeValue(forKey: scope)
            self.lock.unlock()
            self.scheduler.discardCancelled()
        }
    }

    private func prepared(_ message: Message, scope: Scope?) -> Cached? {
        lock.lock()
        let epoch = cacheEpoch
        var candidates = [scope.flatMap { cached[$0]?[message.id] }, sharedCache[message.id]].compactMap { $0 }
        if candidates.isEmpty && scope == nil { candidates = cached.values.compactMap { $0[message.id] } }
        if let value = candidates.first(where: { $0.validatedSource === message }) {
            lock.unlock()
            return value
        }
        lock.unlock()
        guard !candidates.isEmpty else { return nil }
        let input = rgAdInput(message)
        let mediaIdentity = rgAdMediaIdentity(message)
        guard let value = candidates.first(where: { $0.input == input && $0.mediaIdentity == mediaIdentity }) else { return nil }
        lock.lock()
        guard cacheEpoch == epoch else {
            lock.unlock()
            return nil
        }
        value.validatedSource = message
        lock.unlock()
        return value
    }

    private func canProject(_ message: Message, accountPeerId: PeerId) -> Bool {
        guard rgCanCorrectAds(message), message.effectivelyIncoming(accountPeerId), rgIsAdFilteringPeer(message),
            message.adAttribute == nil, message.activeEphemeralReplacementMessage == nil
        else { return false }
        return allowsFiltering(peerId: message.id.peerId, accountPeerId: accountPeerId)
    }

    private func allowsFiltering(peerId: PeerId, accountPeerId: PeerId) -> Bool {
        let accountId = accountPeerId.toInt64()
        let peerId = peerId.toInt64()
        return RegramPreferences.shared.settings(accountId: accountId).reSieveEnabled(for: peerId)
            && !RegramTemporaryReveal.shared.isRevealed(accountId: accountId, peerId: peerId)
    }

    private func canProjectReply(in message: Message, accountPeerId: PeerId) -> Bool {
        rgCanCorrectAds(message) && rgIsAdFilteringPeer(message) && message.adAttribute == nil
            && message.activeEphemeralReplacementMessage == nil && allowsFiltering(peerId: message.id.peerId, accountPeerId: accountPeerId)
    }

    private func projection(_ message: Message, accountPeerId: PeerId, scope: Scope?) -> Cached? {
        guard canProject(message, accountPeerId: accountPeerId) else { return nil }
        return prepared(message, scope: scope)
    }

    public func shouldHide(_ message: Message, accountPeerId: PeerId, scope: Scope? = nil) -> Bool {
        projection(message, accountPeerId: accountPeerId, scope: scope)?.projection?.disposition == .hide
    }

    public func isPrepared(_ message: Message, accountPeerId: PeerId, scope: Scope? = nil) -> Bool {
        !canProject(message, accountPeerId: accountPeerId) || prepared(message, scope: scope)?.completed == true
    }

    public func hiddenMessageIds(in messages: [Message], accountPeerId: PeerId, scope: Scope? = nil) -> Set<MessageId> {
        struct Album: Hashable {
            let peerId: PeerId
            let namespace: Int32
            let key: Int64
        }
        var values: [MessageId: Cached] = [:]
        var hidden = Set<MessageId>()
        for message in messages {
            if let value = projection(message, accountPeerId: accountPeerId, scope: scope) {
                values[message.id] = value
                if value.projection?.disposition == .hide { hidden.insert(message.id) }
            }
        }
        var albums: [Album: [Message]] = [:]
        for message in messages {
            if let key = message.groupingKey {
                albums[Album(peerId: message.id.peerId, namespace: message.id.namespace, key: key), default: []].append(message)
            }
        }
        for members in albums.values {
            let captions = members.filter {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || $0.attributes.contains { $0 is ReplyMarkupMessageAttribute }
            }
            guard !captions.isEmpty, captions.allSatisfy({ hidden.contains($0.id) }),
                members.allSatisfy({ values[$0.id]?.preservesMedia == false })
            else { continue }
            for message in members where values[message.id]?.input.hasMedia == true { hidden.insert(message.id) }
        }
        return hidden
    }

    public func display(_ message: Message, accountPeerId: PeerId, scope: Scope? = nil, includeReply: Bool = true) -> Message {
        let original = rgAdOriginalMessage(message)
        let body = displayBody(original, accountPeerId: accountPeerId, scope: scope)
        guard includeReply, canProjectReply(in: original, accountPeerId: accountPeerId),
            let reply = original.attributes.first(where: { $0 is ReplyMessageAttribute }) as? ReplyMessageAttribute,
            let target = original.associatedMessages[reply.messageId], target.id != original.id,
            let value = projection(rgAdOriginalMessage(target), accountPeerId: accountPeerId, scope: scope),
            let projected = value.projection
        else { return body }
        var attributes = body.attributes
        var associated = body.associatedMessages
        if projected.disposition == .hide {
            attributes.removeAll { $0 is ReplyMessageAttribute || $0 is QuotedReplyMessageAttribute }
        } else {
            let preview = displayBody(rgAdOriginalMessage(target), accountPeerId: accountPeerId, scope: scope)
            associated[reply.messageId] = preview
            let keepQuote = reply.quote.map { rgAdQuoteIsVisible($0, in: preview) } ?? false
            attributes = attributes.compactMap { attribute in
                if attribute is QuotedReplyMessageAttribute { return nil }
                if attribute is ReplyMessageAttribute, reply.quote != nil, !keepQuote {
                    return ReplyMessageAttribute(
                        messageId: reply.messageId, threadMessageId: reply.threadMessageId, quote: nil, isQuote: false,
                        innerSubject: reply.innerSubject)
                }
                return attribute
            }
        }
        if !attributes.contains(where: { $0 is RGAdOriginalAttribute }) { attributes.append(RGAdOriginalAttribute(original)) }
        return Message(
            stableId: body.stableId, stableVersion: body.stableVersion &+ 0x4000_0000 &+ value.revision,
            id: body.id, globallyUniqueId: body.globallyUniqueId, groupingKey: body.groupingKey,
            groupInfo: body.groupInfo, threadId: body.threadId, timestamp: body.timestamp, flags: body.flags,
            tags: body.tags, globalTags: body.globalTags, localTags: body.localTags, customTags: body.customTags,
            forwardInfo: body.forwardInfo, author: body.author, text: body.text, attributes: attributes,
            media: body.media, peers: body.peers, associatedMessages: associated, associatedMessageIds: body.associatedMessageIds,
            associatedMedia: body.associatedMedia, associatedThreadInfo: body.associatedThreadInfo,
            associatedStories: body.associatedStories
        )
    }

    func replyPreview(_ message: Message, accountPeerId: PeerId, scope: Scope) -> Message {
        displayBody(rgAdOriginalMessage(message), accountPeerId: accountPeerId, scope: scope, clearHiddenBody: true)
    }

    private func displayBody(_ message: Message, accountPeerId: PeerId, scope: Scope?, clearHiddenBody: Bool = false) -> Message {
        guard let value = projection(message, accountPeerId: accountPeerId, scope: scope), let projection = value.projection,
            projection.disposition == .trim || clearHiddenBody
        else { return message }
        let removed = projection.removedRanges
        func mapped(_ range: Range<Int>) -> [Range<Int>] {
            var result: [Range<Int>] = []
            var offset = 0
            var start = 0
            for cut in removed + [RGAdRange(message.text.utf16.count, message.text.utf16.count)] {
                let lower = max(start, range.lowerBound)
                let upper = min(cut.lower, range.upperBound)
                if lower < upper { result.append((lower - offset)..<(upper - offset)) }
                offset += cut.upper - cut.lower
                start = cut.upper
            }
            return result
        }
        var attributes: [MessageAttribute] = []
        for attribute in message.attributes {
            if let entities = attribute as? TextEntitiesMessageAttribute {
                attributes.append(
                    TextEntitiesMessageAttribute(
                        entities: entities.entities.flatMap { entity in
                            mapped(entity.range).map { MessageTextEntity(range: $0, type: entity.type) }
                        }))
            } else if let markup = attribute as? ReplyMarkupMessageAttribute, markup.flags.contains(.inline) {
                let ids = Set(projection.removedButtonIds)
                let rows = markup.rows.enumerated().compactMap { row, item -> ReplyMarkupRow? in
                    let buttons = item.buttons.enumerated().compactMap { column, button in ids.contains("\(row):\(column)") ? nil : button }
                    return buttons.isEmpty ? nil : ReplyMarkupRow(buttons: buttons)
                }
                if !rows.isEmpty {
                    attributes.append(ReplyMarkupMessageAttribute(rows: rows, flags: markup.flags, placeholder: markup.placeholder))
                }
            } else if !(attribute is TranslationMessageAttribute) && !(attribute is RegramTranslationMessageAttribute) {
                attributes.append(attribute)
            }
        }
        attributes.append(RGAdOriginalAttribute(message, projection: projection))
        var result = message.withUpdatedText(projection.text).withUpdatedAttributes(attributes).withUpdatedStableVersion(
            stableVersion: message.stableVersion &+ 0x8000_0000 &+ value.revision)
        if projection.disposition == .hide {
            result = result.withUpdatedMedia([])
        } else if projection.hideLinkPreview {
            result = result.withUpdatedMedia(message.media.filter { !($0 is TelegramMediaWebpage) })
        }
        return result
    }
}

@available(macOS 12, *)
public final class RegramAdFilterWorkScope {
    public let scope: RegramAdFilterSession.Scope
    private let session: RegramAdFilterSession
    private let lock = NSLock()
    private var request: RGAdWorkRequest?
    private var sources: [Message] = []
    private var preferencesRevision: Int64?
    private var preparationRevision: UInt64?

    public init(session: RegramAdFilterSession, scope: RegramAdFilterSession.Scope) {
        self.session = session
        self.scope = scope
    }

    public func prepare(_ messages: [Message], accountPeerId: PeerId) {
        let accountId = accountPeerId.toInt64()
        let settings = RegramPreferences.shared.settings(accountId: accountId)
        let peers = Set(messages.map { $0.id.peerId })
        let allowedPeers = Set(
            peers.filter {
                settings.reSieveEnabled(for: $0.toInt64())
                    && !RegramTemporaryReveal.shared.isRevealed(accountId: accountId, peerId: $0.toInt64())
            })
        let messages = messages.filter { allowedPeers.contains($0.id.peerId) }
        let preferencesRevision = RegramPreferences.shared.revision(accountId: accountId)
        let preparationRevision = session.preparationRevision
        lock.lock()
        defer { lock.unlock() }
        guard
            self.preferencesRevision != preferencesRevision || self.preparationRevision != preparationRevision
                || sources.count != messages.count || !zip(sources, messages).allSatisfy({ $0.0 === $0.1 })
        else { return }
        self.preferencesRevision = preferencesRevision
        self.preparationRevision = preparationRevision
        sources = messages
        request?.cancel()
        request = session.prepare(messages, accountPeerId: accountPeerId, scope: scope)
    }

    deinit {
        request?.cancel()
        session.release(scope: scope)
    }
}
