import RegramCore
import RegramSignals
import RegramServices
import Foundation
import NaturalLanguage
import Postbox
import SwiftSignalKit
import TelegramCore
import Translate
import InAppSettings
import TGUIKit
import TelegramContext
import TelegramUtils
import TelegramTheme
import Localization
import MessageUtils



public struct ChatTranslationState: Codable, Equatable {
    private static let currentRecognitionVersion: Int32 = 1

    public enum CodingKeys: String, CodingKey {
        case baseLang
        case fromLang
        case toLang
        case isEnabled
        case paywall
        case tone
        case timestamp
        case recognitionVersion
    }

    public var baseLang: String
    public var fromLang: String
    public var toLang: String?
    public var isEnabled: Bool?
    public var paywall: Bool
    public var tone: TranslationTone?
    public var timestamp: Int32?
    private let recognitionVersion: Int32?

    public init(
        baseLang: String,
        fromLang: String,
        toLang: String?,
        isEnabled: Bool?,
        paywall: Bool,
        tone: TranslationTone? = nil,
        timestamp: Int32? = nil
    ) {
        self.baseLang = baseLang
        self.fromLang = fromLang
        self.toLang = toLang
        self.isEnabled = isEnabled
        self.paywall = paywall
        self.tone = tone
        self.timestamp = timestamp
        self.recognitionVersion = Self.currentRecognitionVersion
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.baseLang = try container.decode(String.self, forKey: .baseLang)
        self.fromLang = try container.decode(String.self, forKey: .fromLang)
        self.toLang = try container.decodeIfPresent(String.self, forKey: .toLang)
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled)
        self.paywall = try container.decodeIfPresent(Bool.self, forKey: .paywall) ?? false
        self.timestamp = try container.decodeIfPresent(Int32.self, forKey: .timestamp)
        self.recognitionVersion = try container.decodeIfPresent(Int32.self, forKey: .recognitionVersion)
        if let toneRaw = try container.decodeIfPresent(String.self, forKey: .tone) {
            self.tone = TranslationTone(rawValue: toneRaw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(self.baseLang, forKey: .baseLang)
        try container.encode(self.fromLang, forKey: .fromLang)
        try container.encodeIfPresent(self.toLang, forKey: .toLang)
        try container.encodeIfPresent(self.isEnabled, forKey: .isEnabled)
        try container.encode(self.paywall, forKey: .paywall)
        try container.encodeIfPresent(self.tone?.rawValue, forKey: .tone)
        try container.encodeIfPresent(self.timestamp, forKey: .timestamp)
        try container.encodeIfPresent(self.recognitionVersion, forKey: .recognitionVersion)
    }

    func hasCurrentRecognition(baseLang: String, now: Int32) -> Bool {
        self.recognitionVersion == Self.currentRecognitionVersion && self.baseLang == baseLang && RegramChatLanguagePolicy.isFresh(timestamp: self.timestamp, now: now)
    }
}


private func cachedChatTranslationState(engine: TelegramEngine, peerId: EnginePeer.Id) -> Signal<ChatTranslationState?, NoError> {
    let key = ValueBoxKey(length: 8)
    key.setInt64(0, value: peerId.id._internalGetInt64Value())
    
    return engine.data.subscribe(TelegramEngine.EngineData.Item.ItemCache.Item(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: key))
    |> map { entry -> ChatTranslationState? in
        return entry?.get(ChatTranslationState.self)
    }
    |> distinctUntilChanged
}

private func updateChatTranslationState(engine: TelegramEngine, peerId: EnginePeer.Id, state: ChatTranslationState?) -> Signal<Never, NoError> {
    let key = ValueBoxKey(length: 8)
    key.setInt64(0, value: peerId.id._internalGetInt64Value())
    
    if let state = state {
        return engine.itemCache.put(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: key, item: state)
    } else {
        return engine.itemCache.remove(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: key)
    }
}

public func updateChatTranslationStateInteractively(engine: TelegramEngine, peerId: EnginePeer.Id, _ f: @escaping (ChatTranslationState) -> ChatTranslationState) -> Signal<Never, NoError> {
    let key = ValueBoxKey(length: 8)
    key.setInt64(0, value: peerId.id._internalGetInt64Value())
    
    return engine.data.get(TelegramEngine.EngineData.Item.ItemCache.Item(collectionId: ApplicationSpecificItemCacheCollectionId.translationState, id: key))
    |> map { entry -> ChatTranslationState? in
        return entry?.get(ChatTranslationState.self)
    }
    |> mapToSignal { current -> Signal<Never, NoError> in
        if let current = current {
            return updateChatTranslationState(engine: engine, peerId: peerId, state: f(current))
        } else {
            return .never()
        }
    }
}



final class RegramChatTranslationScheduler {
    enum Event {
        case loading([MessageId])
        case settled(completed: [MessageId], failed: [MessageId])
    }

    private enum Phase: Equatable {
        case queued
        case loading
        case complete
        case failed
    }

    private struct Job {
        let message: Message
        var phase: Phase = .queued
        var attempts = 0
        var readyAt: TimeInterval = 0
    }

    private struct Batch {
        let token: UInt64
        let generation: UInt64
        let messages: [Message]
    }

    private let queue: Queue
    private let retryDelays: [Double]
    private let request: ([Message], UInt64) -> Signal<Set<MessageId>, TranslateFetchError>
    private let changed: (Event) -> Void
    private let requestDisposable = MetaDisposable()
    private let retryDisposable = MetaDisposable()
    private var generation: UInt64 = 0
    private var nextToken: UInt64 = 0
    private var active: Batch?
    private var jobs: [MessageId: Job] = [:]
    private var order: [MessageId] = []

    init(queue: Queue, retryDelays: [Double] = [1, 3], request: @escaping ([Message], UInt64) -> Signal<Set<MessageId>, TranslateFetchError>, changed: @escaping (Event) -> Void) {
        self.queue = queue
        self.retryDelays = retryDelays
        self.request = request
        self.changed = changed
    }

    deinit {
        requestDisposable.dispose()
        retryDisposable.dispose()
    }

    func reset(generation: UInt64) {
        self.generation = generation
        active = nil
        jobs.removeAll()
        order.removeAll()
        requestDisposable.set(nil)
        retryDisposable.set(nil)
    }

    func update(_ messages: [Message], generation: UInt64) {
        if self.generation != generation { reset(generation: generation) }
        let ids = Set(messages.map(\.id))
        let activeIds = Set(active?.messages.map(\.id) ?? [])
        jobs = jobs.filter { ids.contains($0.key) || activeIds.contains($0.key) }
        order.removeAll(keepingCapacity: true)
        var seen = Set<MessageId>()
        for message in messages.reversed() where seen.insert(message.id).inserted {
            order.append(message.id)
            if jobs[message.id]?.message.stableVersion != message.stableVersion {
                jobs[message.id] = Job(message: message)
            }
        }
        drain()
    }

    private func drain() {
        guard active == nil else { return }
        retryDisposable.set(nil)
        let now = ProcessInfo.processInfo.systemUptime
        var messages: [Message] = []
        var length = 0
        var nextReady: TimeInterval?
        for id in order {
            guard let job = jobs[id], job.phase == .queued else { continue }
            if job.readyAt > now {
                nextReady = min(nextReady ?? job.readyAt, job.readyAt)
                continue
            }
            let count = max(1, job.message.text.utf16.count)
            if !messages.isEmpty && length + count > 25_000 { continue }
            messages.append(job.message)
            length += count
            if messages.count >= 20 { break }
        }
        guard !messages.isEmpty else {
            if let nextReady {
                let signal = Signal<Void, NoError>.single(()) |> delay(max(0, nextReady - now), queue: queue)
                retryDisposable.set(signal.start(next: { [weak self] in self?.drain() }))
            }
            return
        }
        nextToken &+= 1
        let batch = Batch(token: nextToken, generation: generation, messages: messages)
        active = batch
        for message in messages {
            jobs[message.id]?.phase = .loading
            jobs[message.id]?.attempts += 1
        }
        changed(.loading(messages.map(\.id)))
        let signal = request(messages, generation) |> take(1)
        requestDisposable.set(signal.start(next: { [weak self] completed in
            self?.queue.justDispatch { [weak self] in self?.finish(batch, completed: completed) }
        }, error: { [weak self] _ in
            self?.queue.justDispatch { [weak self] in self?.finish(batch, completed: []) }
        }, completed: { [weak self] in
            self?.queue.justDispatch { [weak self] in self?.finish(batch, completed: []) }
        }))
    }

    private func finish(_ batch: Batch, completed: Set<MessageId>) {
        guard generation == batch.generation, active?.token == batch.token else { return }
        active = nil
        requestDisposable.set(nil)
        var successful: [MessageId] = []
        var failed: [MessageId] = []
        let now = ProcessInfo.processInfo.systemUptime
        for message in batch.messages {
            guard var job = jobs[message.id], job.message.stableVersion == message.stableVersion else { continue }
            if completed.contains(message.id) {
                job.phase = .complete
                successful.append(message.id)
            } else if job.attempts <= retryDelays.count {
                job.phase = .queued
                job.readyAt = now + retryDelays[job.attempts - 1]
            } else {
                job.phase = .failed
                failed.append(message.id)
            }
            jobs[message.id] = job
        }
        if !successful.isEmpty || !failed.isEmpty { changed(.settled(completed: successful, failed: failed)) }
        drain()
    }
}

private func makeChatTranslationQueue() -> Queue {
    return Queue(name: "chatTranslation", qos: .userInitiated)
}

private func chatTranslationLanguageCode(_ code: String) -> String {
    return RegramChatLanguagePolicy.targetCode(code)
}

@available(macOS 10.14, *)
private let chatTranslationRecognizableLanguages: Set<String> = {
    var languages: [NLLanguage] = [
        .amharic, .arabic, .armenian, .bengali, .bulgarian, .burmese,
        .catalan, .cherokee, .croatian, .czech, .danish, .dutch,
        .english, .finnish, .french, .georgian, .german, .greek,
        .gujarati, .hebrew, .hindi, .hungarian, .icelandic, .indonesian,
        .italian, .japanese, .kannada, .khmer, .korean, .lao,
        .malay, .malayalam, .marathi, .mongolian, .norwegian, .oriya,
        .persian, .polish, .portuguese, .punjabi, .romanian, .russian,
        .simplifiedChinese, .sinhalese, .slovak, .spanish, .swedish,
        .tamil, .telugu, .thai, .tibetan, .traditionalChinese, .turkish,
        .ukrainian, .urdu, .vietnamese
    ]
    if #available(macOS 13.0, *) {
        languages.append(.kazakh)
    }
    return Set(languages.map { chatTranslationLanguageCode($0.rawValue) })
}()

private func chatTranslationNeedsTranslation(_ texts: [String], toLang: String) -> Bool {
    let target = chatTranslationLanguageCode(toLang)
    guard #available(macOS 10.14, *) else {
        return false
    }
    guard chatTranslationRecognizableLanguages.contains(target) else {
        return false
    }
    let recognizer = NLLanguageRecognizer()
    for text in texts {
        var needsTranslation = false
        text.enumerateSubstrings(in: text.startIndex ..< text.endIndex, options: .bySentences) { sentence, _, _, stop in
            var remaining = (sentence ?? "")[...]
            while !remaining.isEmpty {
                let sample = String(remaining.prefix(256))
                remaining = remaining.dropFirst(sample.count)
                recognizer.processString(sample)
                let language = recognizer.languageHypotheses(withMaximum: 1).first
                recognizer.reset()
                if let language = language, language.value >= 0.9, chatTranslationLanguageCode(language.key.rawValue) != target {
                    needsTranslation = true
                    stop = true
                    break
                }
            }
        }
        if needsTranslation {
            return true
        }
    }
    return false
}

private func chatTranslationTexts(_ blocks: [InstantPageBlock]) -> [String] {
    var texts: [String] = []
    for block in blocks {
        switch block {
        case let .title(text), let .subtitle(text), let .header(text), let .subheader(text),
             let .paragraph(text), let .footer(text), let .kicker(text), let .thinking(text),
             let .heading(text, _), let .authorDate(text, _), let .preformatted(text, _):
            texts.append(text.plainText)
        case let .list(items, _):
            for item in items {
                switch item {
                case let .text(text, _, _):
                    texts.append(text.plainText)
                case let .blocks(blocks, _, _):
                    texts.append(contentsOf: chatTranslationTexts(blocks))
                case .unknown:
                    break
                }
            }
        case let .blockQuote(blocks, caption, _), let .details(caption, blocks, _):
            texts.append(caption.plainText)
            texts.append(contentsOf: chatTranslationTexts(blocks))
        case let .pullQuote(text, caption):
            texts.append(contentsOf: [text.plainText, caption.plainText])
        case let .cover(block):
            texts.append(contentsOf: chatTranslationTexts([block]))
        case let .table(title, rows, _, _, _):
            texts.append(title.plainText)
            for row in rows {
                texts.append(contentsOf: row.cells.compactMap { $0.text?.plainText })
            }
        case let .postEmbed(_, _, _, _, _, blocks, caption), let .collage(blocks, caption), let .slideshow(blocks, caption):
            texts.append(contentsOf: chatTranslationTexts(blocks))
            texts.append(contentsOf: [caption.text.plainText, caption.credit.plainText])
        case let .image(_, caption, _, _, _), let .video(_, caption, _, _, _),
             let .audio(_, caption), let .document(_, caption), let .webEmbed(_, _, _, caption, _, _, _),
             let .map(_, _, _, _, caption):
            texts.append(contentsOf: [caption.text.plainText, caption.credit.plainText])
        case let .buttonRow(_, buttons):
            texts.append(contentsOf: buttons.map { $0.text.plainText })
        case let .relatedArticles(title, _):
            texts.append(title.plainText)
        default:
            break
        }
    }
    return texts
}

public func canTranslateChatMessage(_ message: Message, accountPeerId: PeerId?, toLang: String, transcription: Bool = false) -> Bool {
    guard let accountPeerId = accountPeerId, message.author?.id == accountPeerId || !message.effectivelyIncoming(accountPeerId) else {
        return true
    }
    if transcription {
        guard let transcription = message.audioTranscription, !transcription.isPending else {
            return false
        }
        return chatTranslationNeedsTranslation([transcription.text], toLang: toLang)
    }
    var texts = [message.text]
    if let rich = message.attributes.compactMap({ $0 as? RichTextMessageAttribute }).first {
        texts.append(contentsOf: chatTranslationTexts((rich.fullInstantPage ?? rich.instantPage).blocks))
    }
    if let poll = message.media.first as? TelegramMediaPoll {
        texts.append(poll.text)
        texts.append(contentsOf: poll.options.map { $0.text })
        if let solution = poll.results.solution {
            texts.append(solution.text)
        }
    }
    return chatTranslationNeedsTranslation(texts, toLang: toLang)
}

public struct ChatTranslationSource: Equatable {
    private let text: String
    private let entities: [MessageTextEntity]
    private let richText: [InstantPageBlock]?
    private let pollTexts: [String]

    public init(_ message: Message) {
        self.text = message.text
        self.entities = message.textEntitiesAttribute?.entities ?? []
        let richText = message.attributes.compactMap { $0 as? RichTextMessageAttribute }.first
        self.richText = richText.map { ($0.fullInstantPage ?? $0.instantPage).blocks }
        if let poll = message.media.first as? TelegramMediaPoll {
            self.pollTexts = [poll.text] + poll.options.map { $0.text } + (poll.results.solution.map { [$0.text] } ?? [])
        } else {
            self.pollTexts = []
        }
    }
}

struct ChatTranslationMessages {
    let messages: [Message]
    let sources: [ChatLiveTranslateContext.State.Key: ChatTranslationSource]
    let eligibility: [ChatLiveTranslateContext.State.Key: ChatTranslationSource]

    init(_ messages: [Message], replies: [Message], accountPeerId: PeerId?, toLang: String) {
        let eligible = messages.filter { canTranslateChatMessage($0, accountPeerId: accountPeerId, toLang: toLang) }
        var ids = Set<MessageId>()
        self.messages = (eligible + replies).filter { ids.insert($0.id).inserted }.sorted(by: { $0.id < $1.id })
        var sources: [ChatLiveTranslateContext.State.Key: ChatTranslationSource] = [:]
        for message in messages + replies {
            let key = ChatLiveTranslateContext.State.Key(id: message.id, toLang: toLang)
            if sources[key] == nil {
                sources[key] = ChatTranslationSource(message)
            }
        }
        self.sources = sources
        var eligibility: [ChatLiveTranslateContext.State.Key: ChatTranslationSource] = [:]
        for message in eligible {
            let key = ChatLiveTranslateContext.State.Key(id: message.id, toLang: toLang)
            eligibility[key] = sources[key]
        }
        self.eligibility = eligibility
    }
}

public final class ChatLiveTranslateContext {

    public struct State : Equatable {

        public enum Result : Equatable {
            case loading(toLang: String)
            case complete(toLang: String)
            public var toLang: String {
                switch self {
                case let .loading(toLang):
                    return toLang
                case let .complete(toLang):
                    return toLang
                }
            }
        }

        public enum TranscriptionResult : Equatable {
            case loading(toLang: String)
            case complete(toLang: String, text: String)
            public var toLang: String {
                switch self {
                case let .loading(toLang):
                    return toLang
                case let .complete(toLang, _):
                    return toLang
                }
            }
            public var text: String? {
                switch self {
                case .loading:
                    return nil
                case let .complete(_, text):
                    return text
                }
            }
        }

        public enum SummarizeResult : Equatable {
            case loading(toLang: String?)
            case complete(toLang: String?)

            public var toLang: String? {
                switch self {
                case let .loading(toLang):
                    return toLang
                case let .complete(toLang):
                    return toLang
                }
            }
        }

        public var canTranslate: Bool
        public var translate: Bool
        public var autotranslate: Bool
        public var from: String
        public var to: String
        public var paywall: Bool
        public var tone: TranslationTone = .neutral
        fileprivate var regramConfiguration = ""
        fileprivate var regramGeneration: UInt64 = 0
        fileprivate var hasTelegramPremium = false

        public struct Key: Hashable {
            public let id: MessageId
            public let toLang: String

            public static func Key(id: MessageId, toLang: String) -> Key {
                return .init(id: id, toLang: toLang)
            }
            public init(id: MessageId, toLang: String) {
                self.id = id
                self.toLang = toLang
            }
        }

        public struct TranscriptionKey: Hashable {
            public let id: MessageId
            public let toLang: String

            public static func Key(id: MessageId, toLang: String) -> TranscriptionKey {
                return .init(id: id, toLang: toLang)
            }
            public init(id: MessageId, toLang: String) {
                self.id = id
                self.toLang = toLang
            }
        }

        public struct SummarizeKey: Hashable {
            public let id: MessageId

            public static func Key(id: MessageId) -> SummarizeKey {
                return .init(id: id)
            }
            public init(id: MessageId) {
                self.id = id
            }
        }

        public var result:[Key : Result]
        public var translationEligibility: [Key: ChatTranslationSource] = [:]
        public var transcriptionResult:[TranscriptionKey : TranscriptionResult]
        public var summarizeResult:[SummarizeKey : SummarizeResult]

        public static var `default`: State {
            return .init(canTranslate: false, translate: false, autotranslate: false, from: "", to: "", paywall: false, tone: .neutral, result: [:], transcriptionResult: [:], summarizeResult: [:])
        }

        public func translationResult(for message: Message, accountPeerId: PeerId?, matchingTranslation: Bool = true) -> Result? {
            guard canTranslate, translate, canTranslateChatMessage(message, accountPeerId: accountPeerId, toLang: to) else {
                return nil
            }
            if matchingTranslation, message.hasTranslationAttribute(toLang: to) {
                return .complete(toLang: to)
            }
            return result[.Key(id: message.id, toLang: to)]
        }

        public func replyTranslationResult(for message: Message, matchingTranslation: Bool = true) -> Result? {
            if canTranslate, translate, matchingTranslation, message.hasTranslationAttribute(toLang: to) {
                return .complete(toLang: to)
            }
            return result[.Key(id: message.id, toLang: to)]
        }

        mutating func updateTranslation(_ batch: ChatTranslationMessages, toLang: String, matches: (Message) -> Bool = { _ in true }) {
            guard canTranslate, translate, to == toLang else {
                return
            }
            for (key, source) in batch.sources {
                if let previous = translationEligibility[key], previous != source {
                    result.removeValue(forKey: key)
                }
            }
            for message in batch.messages {
                let key = Key(id: message.id, toLang: toLang)
                if matches(message), message.hasTranslationAttribute(toLang: toLang) {
                    result[key] = .complete(toLang: toLang)
                } else if result[key] == .complete(toLang: toLang) {
                    result.removeValue(forKey: key)
                }
            }
            translationEligibility = batch.eligibility
        }

        public func transcriptionTranslationResult(for message: Message, accountPeerId: PeerId?) -> TranscriptionResult? {
            guard canTranslate, translate, canTranslateChatMessage(message, accountPeerId: accountPeerId, toLang: to, transcription: true) else {
                return nil
            }
            return transcriptionResult[.Key(id: message.id, toLang: to)]
        }

        public struct Transcription : Equatable {
            public var messageId: MessageId
            public var string: String
            public init(messageId: MessageId, string: String) {
                self.messageId = messageId
                self.string = string
            }
        }

        fileprivate var queuedTranscriptions:[Transcription] = []
        fileprivate var queuedSummarizes:[Message] = []
        public init(canTranslate: Bool, translate: Bool, autotranslate: Bool, from: String, to: String, paywall: Bool, tone: TranslationTone = .neutral, result: [Key : Result], transcriptionResult: [TranscriptionKey : TranscriptionResult], summarizeResult: [SummarizeKey : SummarizeResult]) {
            self.canTranslate = canTranslate
            self.translate = translate
            self.autotranslate = autotranslate
            self.from = from
            self.to = to
            self.paywall = paywall
            self.tone = tone
            self.result = result
            self.transcriptionResult = transcriptionResult
            self.summarizeResult = summarizeResult
        }
    }
    
    private let peerId: PeerId
    private let context: any AccountContextProtocol
    private let queue = makeChatTranslationQueue()
    
    
    
    private let statePromise = ValuePromise<State>(ignoreRepeated: true)
    private let stateValue = Atomic(value: State.default)

    private func updateState(_ f: (State) -> State) -> Void {
        statePromise.set(stateValue.modify (f))
    }

    private let shouldDisposable = MetaDisposable()
    private let actionsDisposable = DisposableSet()
    private var translationActions = DisposableSet()
    private var translationScheduler: RegramChatTranslationScheduler?
    private var translationMessages: [Message] = []
    private var translationReplies: [Message] = []
    private var translationSources: [State.Key: ChatTranslationSource] = [:]
    private var transcriptionMessages: [Message] = []
    private var translationFailureReported = false

    private let summarizeCompletedPipe = ValuePipe<MessageId>()
    public var summarizeCompleted: Signal<MessageId, NoError> {
        return summarizeCompletedPipe.signal()
    }
    private var pendingSummarizeScrollMessageId: MessageId?
    deinit {
        shouldDisposable.dispose()
        actionsDisposable.dispose()
        translationActions.dispose()
        translationScheduler = nil
    }
    
    public init(peerId: PeerId, context: any AccountContextProtocol) {
        self.peerId = peerId
        self.context = context
        self.translationScheduler = RegramChatTranslationScheduler(queue: self.queue, request: { [weak self] messages, generation in
            guard let self else { return .fail(.outdated) }
            let state = self.stateValue.with { $0 }
            guard state.regramGeneration == generation, self.isCurrentTranslation(state) else { return .fail(.outdated) }
            return self.translationSignal(for: messages.map(\.id), state: state)
        }, changed: { [weak self] event in
            guard let self else { return }
            self.updateState { current in
                var current = current
                switch event {
                case let .loading(ids):
                    for id in ids { current.result[.Key(id: id, toLang: current.to)] = .loading(toLang: current.to) }
                case let .settled(completed, failed):
                    for id in completed { current.result[.Key(id: id, toLang: current.to)] = .complete(toLang: current.to) }
                    for id in failed { current.result.removeValue(forKey: .Key(id: id, toLang: current.to)) }
                }
                return current
            }
            if case let .settled(_, failed) = event, !failed.isEmpty, !self.translationFailureReported {
                self.translationFailureReported = true
                let provider = RegramPreferences.shared.settings(accountId: context.peerId.toInt64())["translationBackend"].string
                let state = self.stateValue.with { $0 }
                DispatchQueue.main.async { [weak self] in
                    guard self?.isCurrentTranslation(state) == true else { return }
                    let language = appCurrentLanguage.primaryLanguage.languageCode
                    let name = regramLocalizedString("Settings.Translation.Backend." + provider, languageCode: language)
                    showModalText(for: context.window, text: regramLocalizedString("Translation.Chat.Failed", languageCode: language).replacingOccurrences(of: "%@", with: name))
                }
            }
        })
        
        let cachedData = getCachedDataView(peerId: peerId, postbox: context.account.postbox) |> map {
            $0
        }
        
        let translationState = chatTranslationState(context: context, peerId: peerId)
        
        let autoTranslate = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.AutoTranslateEnabled(id: peerId))


        
        let should: Signal<(ChatTranslationState?, Appearance, Bool, Bool, String, Bool), NoError> = combineLatest(queue: self.queue, cachedData, translationState, baseAppSettings(accountManager: context.sharedContext.accountManager), appearanceSignal, getPeerView(peerId: context.peerId, postbox: context.account.postbox), autoTranslate, regramPreferenceChanges(accountId: context.peerId.toInt64())) |> map { cachedData, translationState, settings, appearance, peer, autoTranslate, regramSettings in
            let customBackend = regramSettings["translationBackend"].string != "default"
            
            var isHidden: Bool
            if let cachedData = cachedData as? CachedChannelData {
                isHidden = cachedData.flags.contains(.translationHidden)
            } else if let cachedData = cachedData as? CachedGroupData {
                isHidden = cachedData.flags.contains(.translationHidden)
            } else if let cachedData = cachedData as? CachedUserData {
                isHidden = cachedData.flags.contains(.translationHidden)
            } else {
                isHidden = true
            }
            
            var translationState = translationState
            translationState?.paywall = false
            if peerId.namespace == Namespaces.Peer.SecretChat { isHidden = true }
            let hasTelegramPremium = (peer as? TelegramUser)?.flags.contains(.isPremium) ?? false
            let canUseTranslation = hasTelegramPremium || autoTranslate || RegramChatTranslationPolicy.usesTextRequests(settings: regramSettings, hasTelegramPremium: hasTelegramPremium)
            
            let translateConfig = AppConfigTranslateState(rawValue: context.appConfiguration.getStringValue("translations_auto_enabled", orElse: "enabled")) ?? .disabled

            if !isHidden, !translateConfig.canTranslate, !customBackend {
                isHidden = true
            }
            
            if !isHidden {
                return (translationState, appearance, canUseTranslation, autoTranslate, regramSettings.translationIdentity, hasTelegramPremium)
            } else {
                return (nil, appearance, canUseTranslation, autoTranslate, regramSettings.translationIdentity, hasTelegramPremium)
            }
            
        } |> deliverOn(self.queue)
        
        shouldDisposable.set(should.start(next: { [weak self] state, appearance, canUseTranslation, autoTranslate, regramConfiguration, hasTelegramPremium in
            guard let self else { return }
            let previousGeneration = self.stateValue.with { $0.regramGeneration }
            self.updateState { current in
                var current = current
                let interfaceLanguage = RegramChatLanguagePolicy.interfaceCode(primary: appearance.language.primaryLanguage.languageCode, base: appearance.languageCode)
                let target = state?.toLang ?? interfaceLanguage
                let to = RegramChatLanguagePolicy.targetCode(target)
                let active = (state?.isEnabled ?? autoTranslate) && canUseTranslation
                let previousTranslation = current.translate
                let requestChanged = current.to != to || current.regramConfiguration != regramConfiguration || current.tone != (state?.tone ?? .neutral)
                current.regramConfiguration = regramConfiguration
                current.hasTelegramPremium = hasTelegramPremium
                current.tone = state?.tone ?? .neutral
                if let state, RegramChatLanguagePolicy.canDisplay(source: state.fromLang, target: to, interfaceLanguage: interfaceLanguage, active: active) {
                    current.from = RegramChatLanguagePolicy.comparisonCode(state.fromLang)
                    current.to = to
                    current.canTranslate = true
                } else {
                    current.from = ""
                    current.to = to
                    current.canTranslate = false
                }
                current.translate = current.canTranslate && active
                current.autotranslate = autoTranslate
                current.paywall = false
                if requestChanged || previousTranslation != current.translate {
                    current.regramGeneration &+= 1
                    current.queuedTranscriptions.removeAll()
                    current.result.removeAll()
                    current.translationEligibility.removeAll()
                    current.transcriptionResult.removeAll()
                }
                return current
            }
            if self.stateValue.with({ $0.regramGeneration }) != previousGeneration {
                self.translationActions.dispose()
                self.translationActions = DisposableSet()
                self.translationScheduler?.reset(generation: self.stateValue.with { $0.regramGeneration })
                self.translationFailureReported = false
                self.translationSources.removeAll()
                self.translate(self.translationMessages, replies: self.translationReplies)
                self.translateTranscription(self.transcriptionMessages)
            }
        }))
        actionsDisposable.add(state.start(next: { [weak self] state in
            self?.queue.justDispatch { [weak self] in
                if !state.queuedTranscriptions.isEmpty {
                    let transcriptions = state.queuedTranscriptions.filter { state.transcriptionResult[.Key(id: $0.messageId, toLang: state.to)] == nil }
                    for transcription in transcriptions {
                        self?.activateTranscriptionTranslation(for: transcription.messageId, text: transcription.string, state: state)
                    }
                }
                if !state.queuedSummarizes.isEmpty {
                    let summarizes = state.queuedSummarizes.filter { state.summarizeResult[.Key(id: $0.id)] == nil }
                    for message in summarizes {
                        self?.activateSummarization(for: message, state: state)
                    }
                }
            }
        }))
    }
        
    private func isCurrentTranslation(_ state: State) -> Bool {
        stateValue.with {
            $0.translate && $0.regramGeneration == state.regramGeneration && $0.regramConfiguration == state.regramConfiguration && $0.to == state.to && $0.tone == state.tone
        }
    }

    private func translationSignal(for msgIds: [MessageId], state: State) -> Signal<Set<MessageId>, TranslateFetchError> {
        let settings = RegramPreferences.shared.settings(accountId: context.peerId.toInt64())
        guard settings.translationIdentity == state.regramConfiguration, isCurrentTranslation(state) else { return .fail(.outdated) }
        return regramTranslateMessages(account: context.account, messageIds: msgIds, to: state.to, settings: settings, configurationIdentity: settings.translationIdentity, isCurrent: { [weak self] in
            self?.isCurrentTranslation(state) == true
        }, tone: state.tone) |> mapToSignal { [account = context.account] _ in
            account.postbox.transaction { transaction in
                Set(msgIds.filter { id in
                    guard let message = transaction.getMessage(id), regramSupportsSelectedTranslationProvider(message), !message.isCopyProtected(cachedData: transaction.getPeerCachedData(peerId: id.peerId)) else { return false }
                    return message.hasTranslationAttribute(toLang: state.to) && regramTranslationMatches(message, settings: settings, tone: state.tone)
                })
            } |> castError(TranslateFetchError.self)
        } |> deliverOn(self.queue)
    }

    private func activateTranscriptionTranslation(for messageId: MessageId, text: String, state: State) -> Void {
        let account = context.account
        let accountId = context.peerId.toInt64()
        let settings = RegramPreferences.shared.settings(accountId: accountId)
        guard settings.translationIdentity == state.regramConfiguration, isCurrentTranslation(state) else { return }
        let isCurrent: () -> Bool = { [weak self] in
            self?.isCurrentTranslation(state) == true && RegramPreferences.shared.settings(accountId: accountId).translationIdentity == settings.translationIdentity
        }
        let snapshot = account.postbox.transaction { transaction -> (Message, [String])? in
            guard isCurrent(), let message = transaction.getMessage(messageId), regramSupportsSelectedTranslationProvider(message), !message.isCopyProtected(cachedData: transaction.getPeerCachedData(peerId: messageId.peerId)), message.audioTranscription?.text == text else { return nil }
            return (message, regramLLMTranslationContext(transaction: transaction, message: message, settings: settings))
        }
        let signal = snapshot |> castError(TranslateFetchError.self) |> mapToSignal { snapshot -> Signal<String, TranslateFetchError> in
            guard let (original, history) = snapshot else { return .fail(.outdated) }
            let permitted: () -> Signal<Bool, NoError> = {
                account.postbox.transaction { transaction -> Bool in
                    guard isCurrent(), let current = transaction.getMessage(messageId), current.stableVersion == original.stableVersion, regramSupportsSelectedTranslationProvider(current), !current.isCopyProtected(cachedData: transaction.getPeerCachedData(peerId: messageId.peerId)), current.audioTranscription?.text == text else { return false }
                    return true
                }
            }
            return regramProtectedTranslation(text: text, to: state.to, accountId: accountId, settings: settings, ranges: [], protectedIds: [], context: history, permitsNetworkFallback: permitted, telegramTranslate: { text, target in
                TelegramEngine(account: account).messages.translate(text: text, toLang: RegramChatLanguagePolicy.targetCode(target), entities: [], tone: state.tone)
                |> mapError { _ in TranslateFetchError.network }
                |> mapToSignal { result -> Signal<String, TranslateFetchError> in
                    guard let result else { return .fail(.network) }
                    return .single(result.0)
                }
            }) |> mapToSignal { result -> Signal<String, TranslateFetchError> in
                permitted() |> castError(TranslateFetchError.self) |> mapToSignal { allowed -> Signal<String, TranslateFetchError> in
                    allowed ? .single(result.text) : .fail(.outdated)
                }
            }
        } |> deliverOn(self.queue)
        self.updateState { current in
            var current = current
            current.queuedTranscriptions.removeAll(where: { $0.messageId == messageId })
            current.transcriptionResult[.Key(id: messageId, toLang: state.to)] = .loading(toLang: state.to)
            return current
        }
        translationActions.add(signal.start(next: { [weak self] translatedText in
            guard let self, self.isCurrentTranslation(state) else { return }
            self.updateState { current in
                var current = current
                current.transcriptionResult[.Key(id: messageId, toLang: state.to)] = .complete(toLang: state.to, text: translatedText)
                return current
            }
        }, error: { [weak self] _ in
            guard let self, self.isCurrentTranslation(state) else { return }
            self.updateState { current in
                var current = current
                current.transcriptionResult.removeValue(forKey: .Key(id: messageId, toLang: state.to))
                return current
            }
        }))
    }

    private func activateSummarization(for message: Message, state: State) -> Void {
        let toLang: String? = state.to
        let context = self.context
        let signal = context.engine.messages.summarizeMessage(messageId: message.id, translateToLang: toLang)
        |> deliverOn(self.queue)

        actionsDisposable.add(signal.start(error: { [weak self] error in
            self?.updateState { current in
                var current = current
                current.summarizeResult.removeValue(forKey: .Key(id: message.id))
                return current
            }
            if self?.pendingSummarizeScrollMessageId == message.id {
                self?.pendingSummarizeScrollMessageId = nil
            }
            DispatchQueue.main.async {
                switch error {
                case .limitExceeded:
                    showModalText(for: context.window, text: strings().loginFloodWait)
                case .generic, .invalidMessageId, .invalidLanguage:
                    showModalText(for: context.window, text: strings().unknownError)
                case .limitExceededPremium:
                    showModalText(for: context.window, text: strings().unknownError)
                }
            }
        }, completed: { [weak self] in
            self?.updateState { current in
                var current = current
                current.summarizeResult[.Key(id: message.id)] = .complete(toLang: toLang)
                return current
            }
            if self?.pendingSummarizeScrollMessageId == message.id {
                self?.pendingSummarizeScrollMessageId = nil
                self?.summarizeCompletedPipe.putNext(message.id)
            }
        }))

        self.updateState { current in
            var current = current
            current.queuedSummarizes.removeAll(where: { $0.id == message.id })
            current.summarizeResult[.Key(id: message.id)] = .loading(toLang: toLang)
            return current
        }
    }

    public func summarize(_ message: Message) {
        self.queue.justDispatch { [weak self] in
            guard let self = self else {
                return
            }
            let existingResult = self.stateValue.with { $0.summarizeResult[.Key(id: message.id)] }
            if existingResult != nil {
                return
            }

            let toLang: String? = self.stateValue.with { $0.to }
            if let summarizeAttribute = message.summarizeAttribute, summarizeAttribute.summaryForLang(toLang) != nil {
                self.updateState { current in
                    var current = current
                    current.summarizeResult[.Key(id: message.id)] = .complete(toLang: toLang)
                    return current
                }
                self.summarizeCompletedPipe.putNext(message.id)
                return
            }

            self.pendingSummarizeScrollMessageId = message.id
            self.updateState { current in
                var current = current
                if !current.queuedSummarizes.contains(where: { $0.id == message.id }) {
                    current.queuedSummarizes.append(message)
                }
                return current
            }
        }
    }

    public func clearSummarize(_ messageId: MessageId) {
        self.queue.justDispatch { [weak self] in
            self?.updateState { current in
                var current = current
                current.summarizeResult.removeValue(forKey: .Key(id: messageId))
                current.queuedSummarizes.removeAll(where: { $0.id == messageId })
                return current
            }
            self?.summarizeCompletedPipe.putNext(messageId)
        }
    }

    public func toggleTranslate() {
        
        let state = stateValue.with { $0 }
        
        _ = updateChatTranslationStateInteractively(engine: context.engine, peerId: peerId, { current in
            var current = current
            if let isEnabled = current.isEnabled {
                current.isEnabled = !isEnabled
            } else {
                current.isEnabled = !state.autotranslate
            }
            return current
        }).start()
    }
    
    public var state: Signal<State, NoError> {
        return statePromise.get()
    }
    
    public func translate(_ message: [Message], replies: [Message] = []) {
        self.queue.justDispatch { [weak self] in
            guard let self else { return }
            self.translationMessages = message
            self.translationReplies = replies
            let state = self.stateValue.with { $0 }
            guard state.canTranslate && state.translate else { return }
            let settings = RegramPreferences.shared.settings(accountId: self.context.peerId.toInt64())
            let presentation = RegramTranslationPresentation(settings: settings, tone: state.tone)
            let eligible = message.filter { regramSupportsSelectedTranslationProvider($0) && regramHasSelectedTranslationContent($0) }
            let eligibleReplies = replies.filter { regramSupportsSelectedTranslationProvider($0) && regramHasSelectedTranslationContent($0) }
            let batch = ChatTranslationMessages(eligible, replies: eligibleReplies, accountPeerId: self.context.peerId, toLang: state.to)
            let pending = batch.messages.filter { !$0.hasTranslationAttribute(toLang: state.to) || !presentation.matches($0) }
            let changedKeys = batch.sources.compactMap { key, source -> State.Key? in
                guard let previous = self.translationSources[key], previous != source else { return nil }
                return key
            }
            self.translationSources = batch.sources
            if !changedKeys.isEmpty {
                self.translationScheduler?.reset(generation: state.regramGeneration)
            }
            self.updateState { current in
                var current = current
                for key in changedKeys {
                    current.result.removeValue(forKey: key)
                }
                current.updateTranslation(batch, toLang: state.to, matches: presentation.matches)
                return current
            }
            self.translationScheduler?.update(pending, generation: state.regramGeneration)
        }
    }

    public func hideTranslation() {
        _ = context.engine.messages.togglePeerMessagesTranslationHidden(peerId: self.peerId, hidden: true).start()
        _ = updateChatTranslationStateInteractively(engine: context.engine, peerId: peerId, { current in
            var current = current
            current.isEnabled = false
            return current
        }).start()
    }
    public func translate(toLang: String) -> Void {
        _ = updateChatTranslationStateInteractively(engine: context.engine, peerId: peerId, { current in
            var current = current
            current.toLang = toLang
            current.isEnabled = true
            return current
        }).start()
    }

    public func setTone(_ tone: TranslationTone) {
        _ = updateChatTranslationStateInteractively(engine: context.engine, peerId: peerId, { current in
            var current = current
            current.tone = tone
            return current
        }).start()
    }

    public func translateTranscription(_ messages: [Message]) {
        self.queue.justDispatch { [weak self] in
            guard let `self` = self else {
                return
            }
            self.transcriptionMessages = messages
            let isEnabled = self.stateValue.with { $0.canTranslate && $0.translate }
            if !isEnabled {
                return
            }
            let toLang = self.stateValue.with { $0.to }

            let messagesToQueue = messages.compactMap { message -> State.Transcription? in
                guard regramSupportsSelectedTranslationProvider(message), canTranslateChatMessage(message, accountPeerId: self.context.peerId, toLang: toLang, transcription: true), let transcription = message.audioTranscription, !transcription.text.isEmpty else {
                    return nil
                }
                let existingResult = self.stateValue.with { $0.transcriptionResult[.Key(id: message.id, toLang: toLang)] }
                if existingResult != nil {
                    return nil
                }
                return State.Transcription(messageId: message.id, string: transcription.text)
            }

            if messagesToQueue.isEmpty {
                return
            }

            self.updateState { current in
                var current = current
                if current.translate {
                    for transcription in messagesToQueue {
                        if !current.queuedTranscriptions.contains(where: { $0.messageId == transcription.messageId }) {
                            current.queuedTranscriptions.append(transcription)
                        }
                    }
                }
                return current
            }
        }
    }
    
    public func enablePaywall() -> Void {
        _ = updateBaseAppSettingsInteractively(accountManager: context.sharedContext.accountManager, {
            $0.withUpdatedPaywall($0.paywall?.increase() ?? .initialize())
        }).start()
    }
    public func disablePaywall() -> Void {
        _ = updateBaseAppSettingsInteractively(accountManager: context.sharedContext.accountManager, {
            $0.withUpdatedPaywall($0.paywall?.flush())
        }).start()
    }
}

extension MessageTextEntityType {
    public var isCode: Bool {
        switch self {
        case .Code, .Pre:
            return true
        default:
            return false
        }
    }
}

private let chatLanguageRecognitionQueue = Queue(name: "chatLanguageRecognition", qos: .userInitiated)

public func chatTranslationState(context: any AccountContextProtocol, peerId: EnginePeer.Id) -> Signal<ChatTranslationState?, NoError> {
    if peerId == PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(777000)) || peerId.namespace == Namespaces.Peer.SecretChat { return .single(nil) }
    return combineLatest(baseAppSettings(accountManager: context.sharedContext.accountManager), appearanceSignal, context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.AutoTranslateEnabled(id: peerId)))
    |> mapToSignal { settings, appearance, autoTranslate -> Signal<ChatTranslationState?, NoError> in
        guard settings.translateChats || autoTranslate else { return .single(nil) }
        let baseLang = RegramChatLanguagePolicy.interfaceCode(primary: appearance.language.primaryLanguage.languageCode, base: appearance.languageCode)
        let ignoredLanguages = RegramChatLanguagePolicy.ignoredLanguages(interfaceLanguage: baseLang, configured: settings.doNotTranslate, systemLanguages: Locale.preferredLanguages)
        return cachedChatTranslationState(engine: context.engine, peerId: peerId)
        |> deliverOn(prepareQueue)
        |> mapToSignal { cached -> Signal<ChatTranslationState?, NoError> in
            let now = Int32(clamping: Int64(Date().timeIntervalSince1970))
            if let cached, cached.hasCurrentRecognition(baseLang: baseLang, now: now) {
                return .single(RegramChatLanguagePolicy.isIgnored(source: cached.fromLang, languages: ignoredLanguages) ? nil : cached)
            }
            return .single(nil)
            |> then(context.account.viewTracker.aroundMessageHistoryViewForLocation(.peer(peerId: peerId, threadId: nil), index: .upperBound, anchorIndex: .upperBound, count: 32, fixedCombinedReadStates: nil)
            |> filter { $0.0.entries.count > 1 }
            |> take(1)
            |> deliverOn(chatLanguageRecognitionQueue)
            |> map { history, _, _ -> ChatTranslationState? in
                let samples = history.entries.map { entry -> RegramChatLanguagePolicy.Sample in
                    let message = entry.message
                    let excluded = (message.textEntitiesAttribute?.entities ?? []).compactMap { entity -> NSRange? in
                        switch entity.type {
                        case .Pre, .Code, .Url, .Email, .Mention, .Hashtag, .BotCommand:
                            return NSRange(location: entity.range.lowerBound, length: entity.range.count)
                        default: return nil
                        }
                    }
                    let hint = message.attributes.compactMap { ($0 as? SummarizationMessageAttribute)?.fromLang }.first
                    return .init(text: message.text, incoming: message.effectivelyIncoming(context.peerId), excludedRanges: excluded, languageHint: hint)
                }
                let fromLang = RegramChatLanguagePolicy.dominantLanguage(samples: samples, supported: Set(Translate.supportedTranslationLanguages), detect: Translate.detectLanguage) ?? ""
                let timestamp = Int32(clamping: Int64(Date().timeIntervalSince1970))
                let state = ChatTranslationState(baseLang: baseLang, fromLang: fromLang, toLang: cached?.toLang, isEnabled: cached?.isEnabled ?? autoTranslate, paywall: false, tone: cached?.tone, timestamp: timestamp)
                _ = updateChatTranslationState(engine: context.engine, peerId: peerId, state: state).start()
                return RegramChatLanguagePolicy.isIgnored(source: fromLang, languages: ignoredLanguages) ? nil : state
            })
        }
    }
}

public func chatDictationLanguage(context: any AccountContextProtocol, peerId: EnginePeer.Id) -> Signal<String?, NoError> {
    return cachedChatTranslationState(engine: context.engine, peerId: peerId)
    |> take(1)
    |> mapToSignal { cached -> Signal<String?, NoError> in
        if let language = cached?.fromLang, !language.isEmpty {
            return .single(language)
        }
        return context.account.viewTracker.aroundMessageHistoryViewForLocation(.peer(peerId: peerId, threadId: nil), index: .upperBound, anchorIndex: .upperBound, count: 32, fixedCombinedReadStates: nil)
        |> filter { !$0.0.isLoading }
        |> take(1)
        |> deliverOn(prepareQueue)
        |> map { history, _, _ -> String? in
            var languages: [String] = []
            for entry in history.entries where entry.message.text.count > 10 {
                let message = entry.message
                let codeRanges = (message.textEntitiesAttribute?.entities ?? []).compactMap { entity -> NSRange? in
                    guard entity.type.isCode else { return nil }
                    return NSRange(location: entity.range.lowerBound, length: entity.range.count)
                }
                let text = RegramChatLanguagePolicy.recognitionText(.init(text: message.text, incoming: true, excludedRanges: codeRanges))
                if text.count >= 10, let language = Translate.detectLanguage(for: text) {
                    languages.append(language)
                    if languages.count == 16 { break }
                }
            }
            guard languages.count >= 2 else { return nil }
            let counts = languages.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
            return languages.max { counts[$0, default: 0] < counts[$1, default: 0] }
        }
    }
    |> timeout(0.5, queue: prepareQueue, alternate: .single(nil))
}
