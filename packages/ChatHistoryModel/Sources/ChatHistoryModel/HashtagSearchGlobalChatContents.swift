import Foundation
import SwiftSignalKit
import Postbox
import TGUIKit
import TelegramCore
import TelegramContext
import ChatModeTypes

public final class HashtagSearchGlobalChatContents: ChatCustomContentsProtocol {
    
    private final class Impl {
        let queue: Queue
        let context: any AccountContextProtocol
        
        fileprivate var query: String {
            didSet {
                if self.query != oldValue {
                    self.updateHistoryViewRequest(reload: true)
                }
            }
        }
        private let onlyMy: Bool
        private var currentSearchState: (SearchMessagesResult, SearchMessagesState)?
        
        private(set) var mergedHistoryView: MessageHistoryView?
        private var sourceHistoryView: MessageHistoryView?
        
        private var historyViewDisposable: Disposable?
        private let filterDisposable = MetaDisposable()
        let historyViewStream = ValuePipe<(MessageHistoryView, ViewUpdateType)>()
        var hashtagSearchResultsUpdate: ((SearchMessagesResult, SearchMessagesState)) -> Void = { _ in } {
            didSet {
                if let state = self.currentSearchState {
                    hashtagSearchResultsUpdate(state)
                }
            }
        }
        
        let isSearchingPromise = ValuePromise<Bool>(true)
        
        private let initialState:(SearchMessagesResult, SearchMessagesState)?
        
        init(queue: Queue, context: any AccountContextProtocol, query: String, onlyMy: Bool, initialState: (SearchMessagesResult, SearchMessagesState)?) {
            self.queue = queue
            self.context = context
            self.query = query
            self.onlyMy = onlyMy
            self.initialState = initialState
            
            self.currentSearchState = initialState
            
            if let initialState {
                let updateType: ViewUpdateType = .Initial
                let historyView = MessageHistoryView(tag: nil, namespaces: .just(Set([Namespaces.Message.Cloud])), entries: initialState.0.messages.reversed().map { MessageHistoryEntry(message: $0, isRead: false, location: nil, monthLocation: nil, attributes: MutableMessageHistoryEntryAttributes(authorIsContact: false)) }, holeEarlier: false, holeLater: false, isLoading: false)
                self.sourceHistoryView = historyView
                self.updateHistoryView(updateType: updateType)
            } else {
                self.updateHistoryViewRequest(reload: false)
            }
            filterDisposable.set((regramMessageFilterChanges(accountId: context.peerId.toInt64()) |> deliverOn(queue)).start(next: { [weak self] in
                if self?.sourceHistoryView != nil { self?.updateHistoryView(updateType: .Generic) }
            }))
        }
        
        deinit {
            self.historyViewDisposable?.dispose()
            filterDisposable.dispose()
        }
        
        private func updateHistoryViewRequest(reload: Bool) {
            guard self.historyViewDisposable == nil || reload else {
                return
            }
            self.historyViewDisposable?.dispose()
            
            let search: Signal<(SearchMessagesResult, SearchMessagesState), NoError>
            if self.onlyMy {
                search = self.context.engine.messages.searchMessages(location: .general(scope: .everywhere, groupId: nil, tags: nil, minDate: nil, maxDate: nil, folderId: nil, communityId: nil), query: "#\(self.query)", state: initialState?.1)
            } else {
                search = self.context.engine.messages.searchHashtagPosts(hashtag: self.query, state: initialState?.1)
            }
            
            self.isSearchingPromise.set(true)
            self.historyViewDisposable = (search
            |> deliverOn(self.queue)).start(next: { [weak self] result in
                guard let self else {
                    return
                }
                
                let updateType: ViewUpdateType = .Initial
                
                let historyView = MessageHistoryView(tag: nil, namespaces: .just(Set([Namespaces.Message.Cloud])), entries: result.0.messages.reversed().map { MessageHistoryEntry(message: $0, isRead: false, location: nil, monthLocation: nil, attributes: MutableMessageHistoryEntryAttributes(authorIsContact: false)) }, holeEarlier: false, holeLater: false, isLoading: false)
                self.sourceHistoryView = historyView
                self.updateHistoryView(updateType: updateType)
                                
                Queue.mainQueue().async {
                    self.currentSearchState = result
                    self.hashtagSearchResultsUpdate(result)
                }
                
                self.historyViewDisposable?.dispose()
                self.historyViewDisposable = nil
                
                self.isSearchingPromise.set(false)
            })
        }
        
        private func updateHistoryView(updateType: ViewUpdateType) {
            var entries = (self.sourceHistoryView?.entries ?? []).filter { !regramShouldHideMessage($0.message, accountId: context.peerId.toInt64()) }
            entries.sort(by: { $0.message.index < $1.message.index })
            
            let mergedHistoryView = MessageHistoryView(tag: nil, namespaces: .just(Set([Namespaces.Message.Cloud])), entries: entries, holeEarlier: false, holeLater: false, isLoading: false)
            self.mergedHistoryView = mergedHistoryView
            
            self.historyViewStream.putNext((mergedHistoryView, updateType))
        }
        
        func loadMore() {
            guard self.historyViewDisposable == nil, let currentSearchState = self.currentSearchState else {
                return
            }
            
            let search: Signal<(SearchMessagesResult, SearchMessagesState), NoError>
            if self.onlyMy {
                search = self.context.engine.messages.searchMessages(location: .general(scope: .everywhere, groupId: nil, tags: nil, minDate: nil, maxDate: nil, folderId: nil, communityId: nil), query: "#\(self.query)", state: currentSearchState.1)
            } else {
                search = self.context.engine.messages.searchHashtagPosts(hashtag: self.query, state: currentSearchState.1)
            }
            
            self.historyViewDisposable?.dispose()
            self.historyViewDisposable = (search
            |> deliverOn(self.queue)).startStrict(next: { [weak self] result in
                guard let self else {
                    return
                }
                
                let updateType: ViewUpdateType = .FillHole
                
                let historyView = MessageHistoryView(tag: nil, namespaces: .just(Set([Namespaces.Message.Cloud])), entries: result.0.messages.reversed().map { MessageHistoryEntry(message: $0, isRead: false, location: nil, monthLocation: nil, attributes: MutableMessageHistoryEntryAttributes(authorIsContact: false)) }, holeEarlier: false, holeLater: false, isLoading: false)
                self.sourceHistoryView = historyView
                                                     
                self.updateHistoryView(updateType: updateType)
                
                Queue.mainQueue().async {
                    self.currentSearchState = result
                    
                    self.hashtagSearchResultsUpdate(result)
                }
                
                self.historyViewDisposable?.dispose()
                self.historyViewDisposable = nil
            })
        }
        
        func enqueueMessages(messages: [EnqueueMessage]) {
        }

        func deleteMessages(ids: [EngineMessage.Id]) {
            
        }
        
        func messagesAtIds(_ ids: [MessageId], album: Bool) -> Signal<[Message], NoError> {
            let messages = self.mergedHistoryView?.entries.map { $0.message } ?? []
            
            let filtered = selectedMessagesWithAlbums(from: messages, ids: ids, includeAlbums: album, id: { $0.id }, groupId: { $0.groupingKey })

            return .single(filtered)
        }
        
        func editMessage(id: EngineMessage.Id, text: String, media: RequestEditMessageMedia, entities: TextEntitiesMessageAttribute?, webpagePreviewAttribute: WebpagePreviewMessageAttribute?, disableUrlPreview: Bool) {
        }
    }
    
    public var kind: ChatCustomContentsKind

    public var historyView: Signal<(MessageHistoryView, ViewUpdateType), NoError> {
        return self.impl.signalWith({ impl, subscriber in
            if let mergedHistoryView = impl.mergedHistoryView {
                subscriber.putNext((mergedHistoryView, .Initial))
            }
            return impl.historyViewStream.signal().start(next: subscriber.putNext)
        })
    }
    
    var searching: Signal<Bool, NoError> {
        return self.impl.signalWith({ impl, subscriber in
            return impl.isSearchingPromise.get().start(next: subscriber.putNext)
        })
    }
    
    public var messageLimit: Int? {
        return nil
    }
    
    private let queue: Queue
    private let impl: QueueLocalObject<Impl>
    
    public init(context: any AccountContextProtocol, kind: ChatCustomContentsKind, query: String, onlyMy: Bool, initialState: (SearchMessagesResult, SearchMessagesState)?) {
        self.kind = kind
        
        let queue = Queue()
        self.queue = queue
        self.impl = QueueLocalObject(queue: queue, generate: {
            return Impl(queue: queue, context: context, query: query, onlyMy: onlyMy, initialState: initialState)
        })
    }
    
    func enqueueMessages(messages: [EnqueueMessage]) {
        
    }

    public func deleteMessages(ids: [EngineMessage.Id]) {

    }
    
    public func editMessage(id: EngineMessage.Id, text: String, media: RequestEditMessageMedia, entities: TextEntitiesMessageAttribute?, webpagePreviewAttribute: WebpagePreviewMessageAttribute?, disableUrlPreview: Bool) {

    }
    
    func quickReplyUpdateShortcut(value: String) {
        
    }
    
    func businessLinkUpdate(message: String, entities: [TelegramCore.MessageTextEntity], title: String?) {
        
    }
    
    public func loadMore() {
        self.impl.with { impl in
            impl.loadMore()
        }
    }
    
    public var hashtagSearchResultsUpdate: ((SearchMessagesResult, SearchMessagesState)) -> Void = { _ in } {
        didSet {
            self.impl.with { impl in
                impl.hashtagSearchResultsUpdate = self.hashtagSearchResultsUpdate
            }
        }
    }
    
    public func hashtagSearchUpdate(query: String) {
        self.impl.with { impl in
            impl.query = query
        }
    }
    
    public func enqueueMessages(messages: [EnqueueMessage]) -> Signal<[MessageId?], NoError> {
        return .complete()
    }
    
    public func messagesAtIds(_ ids: [MessageId], album: Bool) -> Signal<[Message], NoError> {
        return self.impl.signalWith({ impl, subscriber in
            return impl.messagesAtIds(ids, album: album).startStandalone(next: { messages in
                subscriber.putNext(messages)
                subscriber.putCompletion()
            })
        })
    }
    
}

