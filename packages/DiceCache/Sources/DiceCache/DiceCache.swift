import Cocoa
import TelegramCore

import SwiftSignalKit
import Postbox
import TelegramTheme
import FoundationUtils

public struct InteractiveEmojiConfetti : Equatable {
    public let playAt: Int32
    public let value:Int32
    public init(playAt: Int32, value: Int32) {
        self.playAt = playAt
        self.value = value
    }
}

public struct InteractiveEmojiConfiguration : Equatable {
    public static var defaultValue: InteractiveEmojiConfiguration {
        return InteractiveEmojiConfiguration(emojis: [], confettiCompitable: [:])
    }
    
    public let emojis: [String]
    private let confettiCompitable: [String: InteractiveEmojiConfetti]
        
    fileprivate init(emojis: [String], confettiCompitable: [String: InteractiveEmojiConfetti]) {
        self.emojis = emojis.map { $0.withoutColorizer }
        self.confettiCompitable = confettiCompitable
    }
    
    public static func with(appConfiguration: AppConfiguration) -> InteractiveEmojiConfiguration {
        if let data = appConfiguration.data, let value = data["emojies_send_dice"] as? [String] {
            let dict:[String : Any]? = data["emojies_send_dice_success"] as? [String:Any]
            
            var confetti:[String: InteractiveEmojiConfetti] = [:]
            if let dict = dict {
                for (key, value) in dict {
                    if let data = value as? [String: Any], let frameStart = data["frame_start"] as? Double, let value = data["value"] as? Double {
                        confetti[key] = InteractiveEmojiConfetti(playAt: Int32(frameStart), value: Int32(value))
                    }
                }
            }
            return InteractiveEmojiConfiguration(emojis: value, confettiCompitable: confetti)
        } else {
            return .defaultValue
        }
    }
    
    public func playConfetti(_ emoji: String) -> InteractiveEmojiConfetti? {
        return confettiCompitable[emoji]
    }
}

public struct EmojiesSoundConfiguration : Equatable {
    
    public static var defaultValue: EmojiesSoundConfiguration {
        return EmojiesSoundConfiguration(sounds: [:])
    }
    
    public let sounds: [String: TelegramMediaFile]
    
    fileprivate init(sounds: [String: TelegramMediaFile]) {
        self.sounds = sounds
    }
    
    public static func with(appConfiguration: AppConfiguration) -> EmojiesSoundConfiguration {
        if let data = appConfiguration.data, let values = data["emojies_sounds"] as? [String: Any] {
            var sounds: [String: TelegramMediaFile] = [:]
            for (key, value) in values {
                if let file = soundFile(value) {
                    sounds[key] = file
                }
            }
            return EmojiesSoundConfiguration(sounds: sounds)
        } else {
            return .defaultValue
        }
    }
    
    public static func sound(for emoji: String, appConfiguration: AppConfiguration) -> TelegramMediaFile? {
        if let data = appConfiguration.data, let values = data["emojies_sounds"] as? [String: Any], let value = values[emoji] {
            return soundFile(value)
        } else {
            return nil
        }
    }
    
    private static func soundFile(_ value: Any) -> TelegramMediaFile? {
        if let dict = value as? [String: String], var fileReferenceString = dict["file_reference_base64"] {
            fileReferenceString = fileReferenceString.replacingOccurrences(of: "-", with: "+")
            fileReferenceString = fileReferenceString.replacingOccurrences(of: "_", with: "/")
            while fileReferenceString.count % 4 != 0 {
                fileReferenceString.append("=")
            }
            
            if let idString = dict["id"], let id = Int64(idString), let accessHashString = dict["access_hash"], let accessHash = Int64(accessHashString), let fileReference = Data(base64Encoded: fileReferenceString) {
                let resource = CloudDocumentMediaResource(datacenterId: 1, fileId: id, accessHash: accessHash, size: nil, fileReference: fileReference, fileName: nil)
                return TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: 0), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "audio/ogg", size: nil, attributes: [], alternativeRepresentations: [])
            }
        }
        return nil
    }

    
}

private final class EmojiDataContext {
    public var data: [(String, Data?, TelegramMediaFile)] = []
    public let subscribers = Bag<([(String, Data?, TelegramMediaFile)]) -> Void>()
}

open class DiceCache {
    private let postbox: Postbox
    private let engine: TelegramEngine
    private let queue = Queue(name: "diceCache", qos: .userInitiated)
    private var dataContexts: [String : EmojiDataContext] = [:]
    private var dataEffectsContexts: [String : EmojiDataContext] = [:]
    
    private let fetchDisposable = MetaDisposable()
    private let loadDataDisposable = MetaDisposable()
    private let emojiesSoundDisposable = MetaDisposable()
    
    open var animatedEmojies:Signal<[String: StickerPackItem], NoError> {
        ensureLoaded()
        return _animatedEmojies.get()
    }
    private let _animatedEmojies:Promise<[String : StickerPackItem]> = .init()
    

    open func emojies_reactions(_ limit: Int) -> Signal<ItemCollectionsView, NoError> {
        return postbox.itemCollectionsView(orderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudRecentReactions, Namespaces.OrderedItemList.CloudTopReactions, Namespaces.OrderedItemList.CloudDefaultTagReactions], namespaces: [Namespaces.ItemCollection.CloudEmojiPacks], aroundIndex: nil, count: limit)
    }
    
    open func emojies_reactions_small(_ limit: Int) -> Signal<ItemCollectionsView, NoError> {
        return postbox.itemCollectionsView(orderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudRecentReactions, Namespaces.OrderedItemList.CloudTopReactions, Namespaces.OrderedItemList.CloudDefaultTagReactions], namespaces: [Namespaces.ItemCollection.CloudEmojiPacks], aroundIndex: nil, count: limit)
    }
    
    open var top_reactions: Signal<ItemCollectionsView, NoError> {
        return postbox.itemCollectionsView(orderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudRecentReactions, Namespaces.OrderedItemList.CloudTopReactions, Namespaces.OrderedItemList.CloudDefaultTagReactions], namespaces: [Namespaces.ItemCollection.CloudEmojiPacks], aroundIndex: nil, count: 100)
    }
    
    open var availableMessageEffects: Signal<AvailableMessageEffects?, NoError> {
        return engine.stickers.availableMessageEffects()
    }
    
    
    open var emojies_status: Signal<ItemCollectionsView, NoError> {
        return postbox.itemCollectionsView(orderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudFeaturedStatusEmoji, Namespaces.OrderedItemList.CloudRecentStatusEmoji, Namespaces.OrderedItemList.CloudUniqueStarGifts], namespaces: [Namespaces.ItemCollection.CloudEmojiPacks], aroundIndex: nil, count: 8000)
    }
    
    open var emojies_status_small: Signal<ItemCollectionsView, NoError> {
        return postbox.itemCollectionsView(orderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudFeaturedStatusEmoji, Namespaces.OrderedItemList.CloudRecentStatusEmoji, Namespaces.OrderedItemList.CloudUniqueStarGifts], namespaces: [Namespaces.ItemCollection.CloudEmojiPacks], aroundIndex: nil, count: 2000)
    }
    
    open var background_icons: Signal<ItemCollectionsView, NoError> {
        return postbox.itemCollectionsView(orderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudFeaturedBackgroundIconEmoji], namespaces: [Namespaces.ItemCollection.CloudEmojiPacks], aroundIndex: nil, count: 8000)
    }
    
    open var background_icons_small: Signal<ItemCollectionsView, NoError> {
        return postbox.itemCollectionsView(orderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudFeaturedBackgroundIconEmoji], namespaces: [Namespaces.ItemCollection.CloudEmojiPacks], aroundIndex: nil, count: 2000)
    }
    open var channel_statuses: Signal<ItemCollectionsView, NoError> {
        return postbox.itemCollectionsView(orderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudFeaturedChannelStatusEmoji], namespaces: [Namespaces.ItemCollection.CloudIconChannelStatusEmoji], aroundIndex: nil, count: 8000)
    }
    open var channel_statuses_small: Signal<ItemCollectionsView, NoError> {
        return postbox.itemCollectionsView(orderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudFeaturedChannelStatusEmoji], namespaces: [Namespaces.ItemCollection.CloudIconChannelStatusEmoji], aroundIndex: nil, count: 2000)
    }
    open var emojies: Signal<ItemCollectionsView, NoError> {
        return postbox.itemCollectionsView(orderedItemListCollectionIds: [], namespaces: [Namespaces.ItemCollection.CloudEmojiPacks], aroundIndex: nil, count: 8000)
    }
    open var emojies_small: Signal<ItemCollectionsView, NoError> {
        return postbox.itemCollectionsView(orderedItemListCollectionIds: [], namespaces: [Namespaces.ItemCollection.CloudEmojiPacks], aroundIndex: nil, count: 2000)
    }
    
    open var premium_gifts: Signal<LoadedStickerPack, NoError> {
        return engine.stickers.loadedStickerPack(reference: .premiumGifts, forceActualized: false)
    }
    
    public init(postbox: Postbox, engine: TelegramEngine) {
        self.postbox = postbox
        self.engine = engine
    }

    private let hasLoaded = Atomic(value: false)
    private func ensureLoaded() {
        if hasLoaded.swap(true) { return }

        let postbox = self.postbox
        let engine = self.engine

        self._animatedEmojies.set(engine.stickers.loadedStickerPack(reference: .animatedEmoji, forceActualized: false)
                                  |> map { result -> [String: StickerPackItem] in
                                      switch result {
                                      case let .result(_, items, _):
                                          var animatedEmojiStickers: [String: StickerPackItem] = [:]
                                          for case let item in items {
                                              if let emoji = item.getStringRepresentationsOfIndexKeys().first {
                                                  animatedEmojiStickers[emoji.withoutColorizer] = item
                                              }
                                          }
                                          return animatedEmojiStickers
                                      default:
                                          return [:]
                                      }
                              })
        
        let availablePacks = postbox.preferencesView(keys: [PreferencesKeys.appConfiguration]) |> map { view in
            return view.values[PreferencesKeys.appConfiguration]?.get(AppConfiguration.self) ?? .defaultValue
        } |> map {
            return InteractiveEmojiConfiguration.with(appConfiguration: $0)
        } |> distinctUntilChanged
        
        
        let emojiesSound = postbox.preferencesView(keys: [PreferencesKeys.appConfiguration]) |> map { view in
            return view.values[PreferencesKeys.appConfiguration]?.get(AppConfiguration.self) ?? AppConfiguration.defaultValue
        } |> map { value -> EmojiesSoundConfiguration in
            return EmojiesSoundConfiguration.with(appConfiguration: value)
        } |> distinctUntilChanged |> mapToSignal { value -> Signal<Never, NoError> in
            //val
            let list = value.sounds.map { fetchedMediaResource(mediaBox: postbox.mediaBox, userLocation: .other, userContentType: .other, reference: MediaResourceReference.standalone(resource: $0.value.resource )) }
            let signals = combineLatest(list)
            
            return signals |> ignoreValues |> `catch` { _ -> Signal<Never, NoError> in return .complete() }
        }
        
        emojiesSoundDisposable.set(emojiesSound.start())
        
        let packs = availablePacks |> mapToSignal { config -> Signal<[(String, [StickerPackItem])], NoError> in
            var signals: [Signal<(String, [StickerPackItem]), NoError>] = []
            
            var emojies = config.emojis
            if emojies.isEmpty {
                emojies.insert("🎲", at: 0)
            }
            
            for emoji in emojies {
                signals.append(engine.stickers.loadedStickerPack(reference: .dice(emoji), forceActualized: true)
                    |> map { result -> (String, [StickerPackItem]) in
                        switch result {
                        case let .result(_, items, _):
                            var dices: [StickerPackItem] = []
                            for case let item in items {
                                dices.append(item)
                            }
                            return (emoji, dices)
                        default:
                            return (emoji, [])
                        }
                    })
            }
            return combineLatest(signals)
        }
        
        let emojiEffects: Signal<[StickerPackItem], NoError> = engine.stickers.loadedStickerPack(reference: .animatedEmojiAnimations, forceActualized: true)
            |> map { result -> [StickerPackItem] in
                switch result {
                case let .result(_, items, _):
                    var effects: [StickerPackItem] = []
                    for case let item in items {
                        effects.append(item)
                    }
                    return effects
                default:
                    return []
                }
            }

        let sharedPacks = Promise<[(String, [StickerPackItem])]>()
        sharedPacks.set(packs)
        let sharedEmojiEffects = Promise<[StickerPackItem]>()
        sharedEmojiEffects.set(emojiEffects)

        let fetchDices = combineLatest(sharedPacks.get(), sharedEmojiEffects.get()) |> map { value, effects -> [StickerPackItem] in
            return value.map { $0.1 }.reduce([StickerPackItem](), { current, value in
                return current + value
            }) + effects
        } |> mapToSignal { dices -> Signal<Void, NoError> in
            let signals = dices.map { value -> Signal<FetchResourceSourceType, FetchResourceError> in
                let reference: MediaResourceReference
                let file = value.file._parse()
                if let stickerReference = file.stickerReference {
                    reference = FileMediaReference.stickerPack(stickerPack: stickerReference, media: file).resourceReference(file.resource)
                } else {
                    reference = FileMediaReference.standalone(media: file).resourceReference(file.resource)
                }
                return fetchedMediaResource(mediaBox: postbox.mediaBox, userLocation: .other, userContentType: .other, reference: reference)
            }
            return combineLatest(signals) |> map { _ in return } |> `catch` { _ in return .complete() }
        }
        
        fetchDisposable.set(fetchDices.start())
        
        let data = sharedPacks.get() |> mapToSignal { values -> Signal<[String : [(String, Data?, TelegramMediaFile)]], NoError> in
            
            var signals: [Signal<(String, [(String, Data?, TelegramMediaFile)]), NoError>] = []
            
            for value in values {
                let dices = value.1.map { value in
                    let file = value.file._parse()
                    return postbox.mediaBox.resourceData(file.resource) |> mapToSignal { resourceData -> Signal<Data?, NoError> in
                        if resourceData.complete, let data = try? Data(contentsOf: URL(fileURLWithPath: resourceData.path), options: [.mappedIfSafe]) {
                            return .single(data)
                        } else {
                            return .single(nil)
                        }
                    } |> map { ((file.stickerText ?? value.getStringRepresentationsOfIndexKeys().first!).withoutColorizer, $0, file) }
                }
                signals.append(combineLatest(dices) |> map { (value.0, $0) })
            }
            
            return combineLatest(signals) |> map { values in
                var dict: [String : [(String, Data?, TelegramMediaFile)]] = [:]
                
                for value in values {
                    dict[value.0.withoutColorizer] = value.1
                }
                return dict
            }
        } |> deliverOn(self.queue)
        
        
        let dataEffects = sharedEmojiEffects.get() |> mapToSignal { values -> Signal<[String: [(String, Data?, TelegramMediaFile)]], NoError> in
            
                        
            let effects = values.map { value in
                let file = value.file._parse()
                return postbox.mediaBox.resourceData(file.resource) |> mapToSignal { resourceData -> Signal<Data?, NoError> in
                    if resourceData.complete, let data = try? Data(contentsOf: URL(fileURLWithPath: resourceData.path), options: [.mappedIfSafe]) {
                        return .single(data)
                    } else {
                        return .single(nil)
                    }
                } |> map { ((file.stickerText ?? value.getStringRepresentationsOfIndexKeys().first!).withoutColorizer, $0, file) }
            }
            return combineLatest(effects) |> map { values in
                var dict: [String : [(String, Data?, TelegramMediaFile)]] = [:]
                
                for value in values {
                    var list = dict[value.0.withoutColorizer] ?? []
                    list.append(value)
                    dict[value.0] = list
                }
                return dict
            }
        } |> deliverOn(self.queue)
        
        loadDataDisposable.set(combineLatest(data, dataEffects).start(next: { [weak self] data, dataEffects in
            guard let `self` = self else {
                return
            }
            for diceData in data {
                let context = self.dataContexts[diceData.key] ?? EmojiDataContext()
                context.data = diceData.value
                self.dataContexts[diceData.key] = context
                for subscriber in context.subscribers.copyItems() {
                    subscriber(diceData.value)
                }
            }
            for effect in dataEffects {
                let context = self.dataEffectsContexts[effect.key] ?? EmojiDataContext()
                context.data = effect.value
                self.dataEffectsContexts[effect.key] = context
                for subscriber in context.subscribers.copyItems() {
                    subscriber(effect.value)
                }
            }
        }))
        
    }
    
    open func animationEffect(for emoji: String) -> Signal<[(String, Data?, TelegramMediaFile)], NoError> {
        ensureLoaded()
        return dataSignal(for: emoji.withoutColorizer, effects: true)
    }

    
    
    open func interactiveSymbolData(baseSymbol: String, synchronous _: Bool) -> Signal<[(String, Data?, TelegramMediaFile)], NoError> {
        ensureLoaded()
        return dataSignal(for: baseSymbol, effects: false)
    }

    private func dataSignal(for symbol: String, effects: Bool) -> Signal<[(String, Data?, TelegramMediaFile)], NoError> {
        return Signal { [weak self] subscriber in
            guard let `self` = self else {
                return EmptyDisposable
            }
            let cancelled = Atomic(value: false)
            let disposable = MetaDisposable()
            let queue = self.queue

            queue.async {
                guard !cancelled.with({ $0 }) else {
                    return
                }
                let dataContext: EmojiDataContext
                if effects {
                    dataContext = self.dataEffectsContexts[symbol] ?? EmojiDataContext()
                    self.dataEffectsContexts[symbol] = dataContext
                } else {
                    dataContext = self.dataContexts[symbol] ?? EmojiDataContext()
                    self.dataContexts[symbol] = dataContext
                }
                let index = dataContext.subscribers.add { data in
                    if !cancelled.with({ $0 }) {
                        subscriber.putNext(data)
                    }
                }
                disposable.set(ActionDisposable {
                    queue.async {
                        dataContext.subscribers.remove(index)
                    }
                })
                if !cancelled.with({ $0 }) {
                    subscriber.putNext(dataContext.data)
                }
            }

            return ActionDisposable {
                _ = cancelled.swap(true)
                disposable.dispose()
            }
        }
    }
    
    open func cleanup() {
        fetchDisposable.dispose()
        loadDataDisposable.dispose()
        emojiesSoundDisposable.dispose()
    }
    
    deinit {
       cleanup()
    }
}
