import XCTest
import SwiftSignalKit
import Foundation

typealias MediaId = Int
extension Int { var id: Int64 { Int64(self) } }
protocol MediaResource {}
struct InvalidResource: MediaResource {}
final class CloudDocumentMediaResource: MediaResource {
    let fileId: Int64
    let accessHash: Int64 = 0
    let fileReference: Data? = nil
    init(_ id: Int) { fileId = Int64(id) }
}
struct TelegramMediaFile: Equatable {
    let fileId: Int
    var version: Int = 0
    var validResource = true
    var id: Int? { fileId }
    var resource: MediaResource { validResource ? CloudDocumentMediaResource(fileId) : InvalidResource() }
}
struct FileMediaReference { let media: TelegramMediaFile }
enum AddSavedMusicError { case generic }
struct SavedMusicIdsList { let items: [Int64] }
struct Buffer { init(data: Data?) {} }
struct SaveRequest { let flags: Int32; let id: Api.InputDocument; let afterId: Api.InputDocument? }
enum EnginePeer { typealias Id = Int }
struct Peer { var valid = true }
func apiInputUser(_ peer: Peer) -> Int? { peer.valid ? 1 : nil }
struct MTRpcError: Error {}
struct Request { let offset: Int32; let limit: Int32 }
enum Api {
    enum functions {
        enum account {
            static func saveMusic(flags: Int32, id: InputDocument, afterId: InputDocument?) -> SaveRequest { SaveRequest(flags: flags, id: id, afterId: afterId) }
        }
        enum users {
            static func getSavedMusic(id: Int, offset: Int32, limit: Int32, hash: Int64) -> Request { Request(offset: offset, limit: limit) }
        }
    }
    struct Saved { let documents: [TelegramMediaFile]; let count: Int32 }
    struct NotModified { let count: Int32 }
    enum Result { case savedMusic(Saved), savedMusicNotModified(NotModified) }
    enum Bool { case boolTrue, boolFalse }
    struct Document { let id: Int64; let accessHash: Int64; let fileReference: Buffer }
    enum InputDocument { case inputDocument(Document) }
}
func telegramMediaFileFromApiDocument(_ file: TelegramMediaFile, altDocuments: [TelegramMediaFile]?) -> TelegramMediaFile? { file.fileId < 0 ? nil : file }
struct CachedProfileSavedMusic { let files: [TelegramMediaFile]; let count: Int32 }
struct CodableEntry {
    let value: Any
    init?<T>(_ value: T) { self.value = value }
    func get<T>(_ type: T.Type) -> T? { value as? T }
}
func entryId(peerId: Int) -> Int { peerId }
typealias PreferencesEntry = CodableEntry
enum PreferencesKeys { static func savedMusicIds() -> Int { 1 } }
protocol CachedPeerData {}
final class CachedUserData: CachedPeerData {
    let savedMusic: TelegramMediaFile?
    init(_ file: TelegramMediaFile?) { savedMusic = file }
    func withUpdatedSavedMusic(_ file: TelegramMediaFile?) -> CachedUserData { CachedUserData(file) }
}
final class Transaction {
    var caches: [Int: CodableEntry] = [:]
    var cache: CodableEntry? { get { caches[1] } set { caches[1] = newValue } }
    var preferences: CodableEntry?
    var peerData: CachedPeerData? = CachedUserData(nil)
    func retrieveItemCacheEntry(id: Int) -> CodableEntry? { caches[id] }
    func putItemCacheEntry(id: Int, entry: CodableEntry) { caches[id] = entry }
    func getPreferencesEntry(key: Int) -> CodableEntry? { preferences }
    func setPreferencesEntry(key: Int, value: CodableEntry?) { preferences = value }
    func updatePeerCachedData(peerIds: Set<Int>, update: (Int, CachedPeerData?) -> CachedPeerData?) { peerData = update(peerIds.first!, peerData) }
}
final class Postbox {
    var peer = Peer()
    let storage = Transaction()
    var delayNextTransaction = false
    var finishTransaction: (() -> Void)?
    func loadedPeerWithId(_ id: Int) -> Signal<Peer, NoError> { .single(peer) }
    func transaction<T>(_ f: @escaping (Transaction) -> T) -> Signal<T, NoError> {
        if delayNextTransaction {
            delayNextTransaction = false
            return Signal { subscriber in
                self.finishTransaction = {
                    subscriber.putNext(f(self.storage))
                    subscriber.putCompletion()
                }
                return ActionDisposable { self.finishTransaction = nil }
            }
        }
        return Signal { subscriber in
            subscriber.putNext(f(self.storage))
            subscriber.putCompletion()
            return EmptyDisposable
        }
    }
}
final class Pending {
    let request: Request
    var subscriber: Subscriber<Api.Result, MTRpcError>?
    var cancelled = false
    init(_ request: Request) { self.request = request }
    func succeed(_ ids: [Int], count: Int32) {
        subscriber?.putNext(.savedMusic(Api.Saved(documents: ids.map { TelegramMediaFile(fileId: $0) }, count: count)))
        subscriber?.putCompletion()
    }
    func fail() { subscriber?.putError(MTRpcError()) }
    func finishEmpty() { subscriber?.putCompletion() }
}
final class Network {
    var pending: [Pending] = []
    var mutations: [PendingMutation] = []
    func request(_ request: SaveRequest) -> Signal<Api.Bool, MTRpcError> {
        Signal { subscriber in
            let pending = PendingMutation(request)
            self.mutations.append(pending)
            pending.subscriber = subscriber
            return ActionDisposable { pending.cancelled = true; pending.subscriber = nil }
        }
    }
    func request(_ request: Request) -> Signal<Api.Result, MTRpcError> {
        let pending = Pending(request)
        self.pending.append(pending)
        return Signal { subscriber in
            pending.subscriber = subscriber
            return ActionDisposable { pending.cancelled = true; pending.subscriber = nil }
        }
    }
}
final class PendingMutation {
    let request: SaveRequest
    var subscriber: Subscriber<Api.Bool, MTRpcError>?
    var cancelled = false
    init(_ request: SaveRequest) { self.request = request }
    func succeed(_ accepted: Bool = true) { subscriber?.putNext(accepted ? .boolTrue : .boolFalse); subscriber?.putCompletion() }
    func fail() { subscriber?.putError(MTRpcError()) }
}
final class Account { let peerId = 1; let postbox = Postbox(); let network = Network() }
func revalidatedMusic<T>(account: Account, file: FileMediaReference, signal: (CloudDocumentMediaResource) -> Signal<T, MTRpcError>) -> Signal<T, MTRpcError> {
    guard let resource = file.media.resource as? CloudDocumentMediaResource else { return .fail(MTRpcError()) }
    return signal(resource)
}
__MUTATIONS__
__CONTEXT__

struct SendAudioState {
    var savedMusic: [TelegramMediaFile] = []
    var sharedAudio: [TelegramMediaFile] = []
    var savedMusicLoaded = false
    var sharedAudioLoaded = false
    var searchQuery = ""
}
func applySaved(_ state: ProfileSavedMusicContext.State, to current: SendAudioState) -> SendAudioState {
    let messages = state.files
    __UI_UPDATE__
}
func showsEmpty(_ state: SendAudioState) -> Bool {
    __EMPTY__
    return contentEmpty
}
enum Style { case normal, singleItem }
enum Value { case none }
struct GeneralLoadingRowItem {
    init(_ size: Int, stableId: Int, viewType: Style) {}
}
struct Entry {
    let section: Int32?
    static func sectionId(_ id: Int32, type: Style) -> Entry { Entry(section: id) }
    static func custom(sectionId: Int32, index: Int32, value: Value, identifier: Int, equatable: Int?, comparable: Int?, item: (Int, Int) -> GeneralLoadingRowItem) -> Entry { Entry(section: nil) }
}
func sharedSections(_ state: SendAudioState) -> [Int32] {
    var entries: [Entry] = []
    let s_shared: Int32 = 3
    let i_loading: Int32 = 900
    let _id_loading = 1
    __LOADING__
    return entries.compactMap { $0.section }
}

final class SavedMusicTests: XCTestCase {
    func file(_ id: Int) -> FileMediaReference { FileMediaReference(media: TelegramMediaFile(fileId: id)) }
    func seed(_ account: Account, _ ids: [Int], count: Int32? = nil) {
        account.postbox.storage.cache = CodableEntry(CachedProfileSavedMusic(files: ids.map { TelegramMediaFile(fileId: $0) }, count: count ?? Int32(ids.count)))
        account.postbox.storage.preferences = CodableEntry(SavedMusicIdsList(items: ids.map(Int64.init)))
        account.postbox.storage.peerData = CachedUserData(ids.first.map { TelegramMediaFile(fileId: $0) })
    }
    func cachedIds(_ account: Account) -> [Int]? { account.postbox.storage.cache?.get(CachedProfileSavedMusic.self)?.files.map { $0.fileId } }
    func preferenceIds(_ account: Account) -> Set<Int64> { Set(account.postbox.storage.preferences?.get(SavedMusicIdsList.self)?.items ?? []) }
    func testCreatingMutationSignalDoesNotApplyOrSendUntilSubscribed() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        account.network.pending[0].succeed([1], count: 1)
        var state: ProfileSavedMusicContext.State?
        let sub = context.state.start(next: { state = $0 })
        let signal = context.addMusic(file: file(2))
        XCTAssertEqual(state?.files.map { $0.fileId }, [1])
        XCTAssertTrue(account.network.mutations.isEmpty)
        let action = signal.start()
        XCTAssertEqual(state?.files.map { $0.fileId }, [2, 1])
        XCTAssertEqual(account.network.mutations.count, 1)
        action.dispose(); sub.dispose()
    }
    func testAddCancelsInitialPageAndRefreshesAfterCommit() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        var state: ProfileSavedMusicContext.State?
        let sub = context.state.start(next: { state = $0 })
        let action = context.addMusic(file: file(1)).start()
        XCTAssertTrue(account.network.pending[0].cancelled)
        account.network.pending[0].succeed([9], count: 1)
        XCTAssertEqual(state?.files.map { $0.fileId }, [1])
        account.network.mutations[0].succeed()
        XCTAssertEqual(account.network.pending.count, 2)
        if account.network.pending.count == 2 {
            XCTAssertEqual(account.network.pending[1].request.offset, 0)
            account.network.pending[1].succeed([1], count: 1)
        }
        XCTAssertEqual(state?.files.map { $0.fileId }, [1])
        action.dispose(); sub.dispose()
    }
    func testRemoveCancelsOldPageAndPreventsReinsertion() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        account.network.pending[0].succeed([1, 2], count: 4)
        context.loadMore()
        var state: ProfileSavedMusicContext.State?
        let sub = context.state.start(next: { state = $0 })
        let action = context.removeMusic(file: file(1)).start()
        XCTAssertTrue(account.network.pending[1].cancelled)
        account.network.pending[1].succeed([1, 3], count: 4)
        XCTAssertEqual(state?.files.map { $0.fileId }, [2])
        account.network.mutations[0].succeed()
        XCTAssertEqual(account.network.pending.count, 3)
        if account.network.pending.count == 3 {
            XCTAssertEqual(account.network.pending[2].request.offset, 0)
            account.network.pending[2].succeed([2, 3, 4], count: 3)
            XCTAssertEqual(state?.files.map { $0.fileId }, [2, 3, 4])
        }
        action.dispose(); sub.dispose()
    }
    func testRefreshWaitsForAllMutationsIncludingOutOfOrderCompletion() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        account.network.pending[0].succeed([1], count: 1)
        let first = context.addMusic(file: file(2)).start()
        let second = context.addMusic(file: file(3)).start()
        context.reload(); context.loadMore()
        XCTAssertEqual(account.network.pending.count, 1)
        account.network.mutations[1].succeed()
        XCTAssertEqual(account.network.pending.count, 1)
        account.network.mutations[0].succeed()
        XCTAssertEqual(account.network.pending.count, 2)
        first.dispose(); second.dispose()
        XCTAssertEqual(account.network.pending.count, 2)
    }
    func testFailedAddForwardsErrorAndReloadRestoresServerState() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        account.network.pending[0].succeed([1], count: 1)
        var state: ProfileSavedMusicContext.State?
        let sub = context.state.start(next: { state = $0 })
        var failed = false
        let action = context.addMusic(file: file(2)).start(error: { _ in failed = true })
        account.network.mutations[0].fail()
        XCTAssertTrue(failed)
        XCTAssertEqual(cachedIds(account), [1])
        XCTAssertEqual(account.network.pending.count, 2)
        if account.network.pending.count == 2 { account.network.pending[1].succeed([1], count: 1) }
        XCTAssertEqual(state?.files.map { $0.fileId }, [1])
        action.dispose(); sub.dispose()
    }
    func testCancellingMutationUnblocksRefreshAndCancelsRequest() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        account.network.pending[0].succeed([1], count: 1)
        let action = context.addMusic(file: file(2)).start()
        action.dispose()
        XCTAssertTrue(account.network.mutations[0].cancelled)
        XCTAssertEqual(account.network.pending.count, 2)
        action.dispose()
        XCTAssertEqual(account.network.pending.count, 2)
    }
    func testLocalOnlyUpdateKeepsExplicitNoNetworkContract() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        account.network.pending[0].succeed([1], count: 1)
        var state: ProfileSavedMusicContext.State?
        let sub = context.state.start(next: { state = $0 })
        _ = context.addMusic(file: file(2), apply: false)
        XCTAssertEqual(state?.files.map { $0.fileId }, [2, 1])
        XCTAssertTrue(account.network.mutations.isEmpty)
        XCTAssertEqual(account.network.pending.count, 1)
        sub.dispose()
    }
    func testMoveAfterItselfDoesNotReorderOrSendRequest() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        account.network.pending[0].succeed([1, 2, 3], count: 3)
        var state: ProfileSavedMusicContext.State?
        let sub = context.state.start(next: { state = $0 })
        let action = context.addMusic(file: file(2), afterFile: file(2)).start()
        XCTAssertEqual(state?.files.map { $0.fileId }, [1, 2, 3])
        XCTAssertEqual(cachedIds(account), [1, 2, 3])
        XCTAssertTrue(account.network.mutations.isEmpty)
        action.dispose(); sub.dispose()
    }
    func testRepeatedRemoveDoesNotRepeatedlyDecreaseCount() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        account.network.pending[0].succeed([1, 2], count: 2)
        account.postbox.storage.preferences = CodableEntry(SavedMusicIdsList(items: [1, 2]))
        var state: ProfileSavedMusicContext.State?
        let sub = context.state.start(next: { state = $0 })
        let first = context.removeMusic(file: file(1)).start()
        let second = context.removeMusic(file: file(1)).start()
        XCTAssertEqual(state?.count, 1)
        account.network.mutations[0].succeed()
        account.network.mutations[1].succeed()
        XCTAssertEqual(account.postbox.storage.cache?.get(CachedProfileSavedMusic.self)?.count, 1)
        first.dispose(); second.dispose(); sub.dispose()
    }
    func testMissingLoadedAnchorUsesSameOrderInContextAndCache() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        account.network.pending[0].succeed([1, 2, 3], count: 5)
        var state: ProfileSavedMusicContext.State?
        let sub = context.state.start(next: { state = $0 })
        let action = context.addMusic(file: file(1), afterFile: file(99)).start()
        XCTAssertEqual(state?.files.map { $0.fileId }, [2, 3, 1])
        account.network.mutations[0].succeed()
        XCTAssertEqual(cachedIds(account), [2, 3, 1])
        action.dispose(); sub.dispose()
    }
    func testOtherProfileIsNotChangedBySavingToOwnMusic() {
        let account = Account()
        seed(account, [1])
        let context = ProfileSavedMusicContext(account: account, peerId: 2)
        account.network.pending[0].succeed([10, 11], count: 2)
        var state: ProfileSavedMusicContext.State?
        let sub = context.state.start(next: { state = $0 })
        let action = context.addMusic(file: file(11)).start()
        XCTAssertEqual(state?.files.map { $0.fileId }, [10, 11])
        account.network.mutations[0].succeed()
        XCTAssertEqual(cachedIds(account), [11, 1])
        XCTAssertEqual(account.network.pending.count, 1)
        action.dispose(); sub.dispose()
    }
    func testOtherProfileIsNotChangedByRemovingFromOwnMusic() {
        let account = Account()
        seed(account, [10])
        let context = ProfileSavedMusicContext(account: account, peerId: 2)
        account.network.pending[0].succeed([10, 11], count: 2)
        var state: ProfileSavedMusicContext.State?
        let sub = context.state.start(next: { state = $0 })
        let action = context.removeMusic(file: file(10)).start()
        account.network.mutations[0].succeed()
        XCTAssertEqual(state?.files.map { $0.fileId }, [10, 11])
        XCTAssertEqual(cachedIds(account), [])
        action.dispose(); sub.dispose()
    }
    func testRawAddCommitsOnlyAfterServerAccepts() {
        for result in 0..<3 {
            let account = Account()
            seed(account, [1])
            var failed = false
            let action = _internal_addSavedMusic(account: account, file: file(2), afterFile: nil).start(error: { _ in failed = true })
            XCTAssertEqual(cachedIds(account), [1])
            XCTAssertEqual(preferenceIds(account), [1])
            if result == 0 { account.network.mutations[0].fail() } else { account.network.mutations[0].succeed(result == 2) }
            XCTAssertEqual(cachedIds(account), result == 2 ? [2, 1] : [1])
            XCTAssertEqual(preferenceIds(account), result == 2 ? [1, 2] : [1])
            XCTAssertEqual(failed, result != 2)
            action.dispose()
        }
    }
    func testRawRemoveFailureOrFalseLeavesCachesUnchanged() {
        for error in [true, false] {
            let account = Account()
            seed(account, [1, 2])
            let action = _internal_removeSavedMusic(account: account, file: file(1)).start()
            XCTAssertEqual(cachedIds(account), [1, 2])
            if error { account.network.mutations[0].fail() } else { account.network.mutations[0].succeed(false) }
            XCTAssertEqual(cachedIds(account), [1, 2])
            XCTAssertEqual(preferenceIds(account), [1, 2])
            XCTAssertEqual((account.postbox.storage.peerData as? CachedUserData)?.savedMusic?.fileId, 1)
            action.dispose()
        }
    }
    func testAddWithoutPageCacheUpdatesKnownIdsAndProfileHeader() {
        let account = Account()
        account.postbox.storage.preferences = CodableEntry(SavedMusicIdsList(items: []))
        let action = _internal_addSavedMusic(account: account, file: file(7), afterFile: nil).start()
        account.network.mutations[0].succeed()
        XCTAssertEqual(preferenceIds(account), [7])
        XCTAssertEqual((account.postbox.storage.peerData as? CachedUserData)?.savedMusic?.fileId, 7)
        XCTAssertNil(account.postbox.storage.cache)
        action.dispose()
    }
    func testRemoveWithoutPageCacheUpdatesKnownIdsAndProfileHeader() {
        let account = Account()
        account.postbox.storage.preferences = CodableEntry(SavedMusicIdsList(items: [7]))
        account.postbox.storage.peerData = CachedUserData(file(7).media)
        let action = _internal_removeSavedMusic(account: account, file: file(7)).start()
        account.network.mutations[0].succeed()
        XCTAssertEqual(preferenceIds(account), [])
        XCTAssertNil((account.postbox.storage.peerData as? CachedUserData)?.savedMusic)
        action.dispose()
    }
    func testRemovingHeaderSongPromotesNextCachedSong() {
        let account = Account()
        seed(account, [1, 2])
        let action = _internal_removeSavedMusic(account: account, file: file(1)).start()
        account.network.mutations[0].succeed()
        XCTAssertEqual((account.postbox.storage.peerData as? CachedUserData)?.savedMusic?.fileId, 2)
        action.dispose()
    }
    func testMutationDoesNotRetainContextAndStillCommitsAfterItCloses() {
        let account = Account()
        var context: ProfileSavedMusicContext? = ProfileSavedMusicContext(account: account, peerId: 1)
        account.network.pending[0].succeed([1], count: 1)
        let action = context!.addMusic(file: file(2)).start()
        weak var weakContext = context
        context = nil
        XCTAssertNil(weakContext)
        XCTAssertFalse(account.network.mutations[0].cancelled)
        account.network.mutations[0].succeed()
        XCTAssertEqual(cachedIds(account), [2, 1])
        XCTAssertEqual(account.network.pending.count, 1)
        action.dispose()
    }
    func testSynchronousFailureDoesNotLeaveMutationPending() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        account.network.pending[0].succeed([1], count: 1)
        var failed = false
        let action = context.addMusic(file: FileMediaReference(media: TelegramMediaFile(fileId: 2, validResource: false))).start(error: { _ in failed = true })
        XCTAssertTrue(failed)
        XCTAssertTrue(account.network.mutations.isEmpty)
        XCTAssertEqual(account.network.pending.count, 2)
        action.dispose()
        XCTAssertEqual(account.network.pending.count, 2)
    }
    func testNestedMutationStartsInUserActionOrder() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        account.network.pending[0].succeed([1], count: 1)
        var nested: Disposable?
        var triggered = false
        let sub = context.state.start(next: { state in
            if !triggered, state.files.first?.fileId == 2 {
                triggered = true
                nested = context.addMusic(file: self.file(3)).start()
            }
        })
        let first = context.addMusic(file: file(2)).start()
        XCTAssertEqual(account.network.mutations.map { pending -> Int64 in switch pending.request.id { case let .inputDocument(document): return document.id } }, [2, 3])
        first.dispose(); nested?.dispose(); sub.dispose()
    }
    func testMovingTopSongUpdatesProfileHeader() {
        let account = Account()
        seed(account, [1, 2, 3])
        let action = _internal_addSavedMusic(account: account, file: file(1), afterFile: file(2)).start()
        account.network.mutations[0].succeed()
        XCTAssertEqual(cachedIds(account), [2, 1, 3])
        XCTAssertEqual((account.postbox.storage.peerData as? CachedUserData)?.savedMusic?.fileId, 2)
        action.dispose()
    }
    func testCancelledNestedMutationIsNotSentLater() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        account.network.pending[0].succeed([1], count: 1)
        var triggered = false
        let sub = context.state.start(next: { state in
            if !triggered, state.files.first?.fileId == 2 {
                triggered = true
                let nested = context.addMusic(file: self.file(3)).start()
                nested.dispose()
            }
        })
        let first = context.addMusic(file: file(2)).start()
        XCTAssertEqual(account.network.mutations.count, 1)
        first.dispose(); sub.dispose()
    }
    func testMutationCancelsPendingCacheRead() {
        let account = Account()
        seed(account, [9])
        account.postbox.delayNextTransaction = true
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        let savedCacheRead = account.postbox.finishTransaction
        var state: ProfileSavedMusicContext.State?
        let sub = context.state.start(next: { state = $0 })
        let action = context.addMusic(file: file(1)).start()
        savedCacheRead?()
        XCTAssertEqual(state?.files.map { $0.fileId }, [1])
        XCTAssertNil(account.postbox.finishTransaction)
        action.dispose(); sub.dispose()
    }
    func testDuplicatePageEntriesUseRawServerCursor() {
        let account = Account()
        let subject = ProfileSavedMusicContext(account: account, peerId: 1)
        var state: ProfileSavedMusicContext.State?
        let subscription = subject.state.start(next: { state = $0 })
        account.network.pending[0].succeed([1, 1, 2], count: 5)
        XCTAssertEqual(state?.files.map { $0.fileId }, [1, 2])
        subject.loadMore()
        XCTAssertEqual(account.network.pending[1].request.offset, 3)
        subscription.dispose()
    }
    func testOverlappingPagesDeduplicateWithoutRepeatingOffset() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        var state: ProfileSavedMusicContext.State?
        let subscription = context.state.start(next: { state = $0 })
        account.network.pending[0].succeed([1, 2], count: 5)
        context.loadMore()
        account.network.pending[1].succeed([2, 3], count: 5)
        XCTAssertEqual(state?.files.map { $0.fileId }, [1, 2, 3])
        context.loadMore()
        XCTAssertEqual(account.network.pending[2].request.offset, 4)
        account.network.pending[2].succeed([4], count: 5)
        XCTAssertEqual(state?.files.map { $0.fileId }, [1, 2, 3, 4])
        XCTAssertEqual(state?.dataState, .ready(canLoadMore: false))
        subscription.dispose()
    }
    func testUnsupportedDocumentsAdvanceCursorAndDoNotEndPagination() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        var state: ProfileSavedMusicContext.State?
        let subscription = context.state.start(next: { state = $0 })
        account.network.pending[0].succeed([-1, -2], count: 4)
        XCTAssertEqual(state?.files, [])
        XCTAssertEqual(state?.dataState, .ready(canLoadMore: true))
        context.loadMore()
        XCTAssertEqual(account.network.pending.count, 2)
        if account.network.pending.count == 2 {
            XCTAssertEqual(account.network.pending[1].request.offset, 2)
            account.network.pending[1].succeed([3, 4], count: 4)
            XCTAssertEqual(state?.files.map { $0.fileId }, [3, 4])
            XCTAssertEqual(state?.dataState, .ready(canLoadMore: false))
        }
        subscription.dispose()
    }
    func testLaterPageWithoutVisibleFilesDoesNotReloadFirstPageCache() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        account.network.pending[0].succeed([-1, -2], count: 4)
        account.postbox.delayNextTransaction = true
        context.loadMore()
        XCTAssertEqual(account.network.pending.count, 2)
        XCTAssertNil(account.postbox.finishTransaction)
    }
    func testLoadingNextPageDoesNotCancelFirstPageCacheWrite() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        account.postbox.delayNextTransaction = true
        account.network.pending[0].succeed([1], count: 2)
        XCTAssertNotNil(account.postbox.finishTransaction)
        context.loadMore()
        XCTAssertNotNil(account.postbox.finishTransaction)
        account.postbox.finishTransaction?()
        XCTAssertEqual(account.postbox.storage.cache?.get(CachedProfileSavedMusic.self)?.files.map { $0.fileId }, [1])
    }
    func testContextDeinitCancelsPendingCacheReadOrWrite() {
        for cacheRead in [true, false] {
            let account = Account()
            account.postbox.delayNextTransaction = cacheRead
            var context: ProfileSavedMusicContext? = ProfileSavedMusicContext(account: account, peerId: 1)
            if !cacheRead {
                account.postbox.delayNextTransaction = true
                account.network.pending[0].succeed([1], count: 2)
            }
            XCTAssertNotNil(account.postbox.finishTransaction)
            weak var weakContext = context
            context = nil
            XCTAssertNil(weakContext)
            XCTAssertNil(account.postbox.finishTransaction)
            XCTAssertTrue(account.network.pending[0].cancelled)
        }
    }
    func testDuplicatePageRefreshesMetadataInPlace() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        var state: ProfileSavedMusicContext.State?
        let subscription = context.state.start(next: { state = $0 })
        account.network.pending[0].succeed([1, 2], count: 4)
        context.loadMore()
        account.network.pending[1].subscriber?.putNext(.savedMusic(.init(documents: [TelegramMediaFile(fileId: 2, version: 9), TelegramMediaFile(fileId: 3)], count: 4)))
        account.network.pending[1].subscriber?.putCompletion()
        XCTAssertEqual(state?.files.map { $0.fileId }, [1, 2, 3])
        XCTAssertEqual(state?.files.first(where: { $0.fileId == 2 })?.version, 9)
        subscription.dispose()
    }
    func testRetryAfterOverlappingPageUsesSameRawOffset() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        account.network.pending[0].succeed([1, 1, 2], count: 5)
        context.loadMore()
        account.network.pending[1].fail()
        context.loadMore()
        XCTAssertEqual(account.network.pending.map { $0.request.offset }, [0, 3, 3])
    }
    func testNotModifiedWithoutHashPreservesVisibleMusicAndCanRetry() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        var state: ProfileSavedMusicContext.State?
        let subscription = context.state.start(next: { state = $0 })
        account.network.pending[0].succeed([1, 2], count: 2)
        context.reload()
        account.network.pending[1].subscriber?.putNext(.savedMusicNotModified(.init(count: 2)))
        account.network.pending[1].subscriber?.putCompletion()
        XCTAssertEqual(state?.files.map { $0.fileId }, [1, 2])
        XCTAssertEqual(state?.dataState, .ready(canLoadMore: true))
        context.loadMore()
        XCTAssertEqual(account.network.pending.count, 3)
        if account.network.pending.count == 3 { XCTAssertEqual(account.network.pending[2].request.offset, 0) }
        subscription.dispose()
    }
    func testLoadingObserverReloadCannotBeReplacedByOuterRequest() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        account.network.pending[0].succeed([1], count: 4)
        var reloadOnLoading = true
        let subscription = context.state.start(next: { state in
            if reloadOnLoading, state.dataState == .loading {
                reloadOnLoading = false
                context.reload()
            }
        })
        context.loadMore()
        XCTAssertEqual(account.network.pending.count, 2)
        XCTAssertEqual(account.network.pending[1].request.offset, 0)
        XCTAssertFalse(account.network.pending[1].cancelled)
        subscription.dispose()
    }
    func testReadyObserverCanContinueFromUpdatedRawCursor() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        var loadNext = true
        let subscription = context.state.start(next: { state in
            if loadNext, state.dataState == .ready(canLoadMore: true) {
                loadNext = false
                context.loadMore()
            }
        })
        account.network.pending[0].succeed([1, 1], count: 4)
        XCTAssertEqual(account.network.pending.count, 2)
        XCTAssertEqual(account.network.pending[1].request.offset, 2)
        XCTAssertFalse(account.network.pending[1].cancelled)
        subscription.dispose()
    }
    func testFailureLeavesLoadingAndCanRetry() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        var state: ProfileSavedMusicContext.State?
        let subscription = context.state.start(next: { state = $0 })
        XCTAssertEqual(state?.dataState, .loading)
        context.loadMore()
        XCTAssertEqual(account.network.pending.count, 1)
        account.network.pending[0].fail()
        XCTAssertEqual(state?.dataState, .ready(canLoadMore: true))
        context.loadMore()
        XCTAssertEqual(account.network.pending.count, 2)
        subscription.dispose()
    }

    func testCompletionWithoutResponseLeavesLoading() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        var state: ProfileSavedMusicContext.State?
        let subscription = context.state.start(next: { state = $0 })
        account.network.pending[0].finishEmpty()
        XCTAssertEqual(state?.dataState, .ready(canLoadMore: true))
        subscription.dispose()
    }

    func testMissingPeerLeavesLoadingWithoutNetworkRequest() {
        let account = Account()
        account.postbox.peer.valid = false
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        var state: ProfileSavedMusicContext.State?
        let subscription = context.state.start(next: { state = $0 })
        XCTAssertEqual(state?.dataState, .ready(canLoadMore: true))
        XCTAssertTrue(account.network.pending.isEmpty)
        subscription.dispose()
    }

    func testReloadFailurePreservesPreviouslyVisibleMusic() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        var state: ProfileSavedMusicContext.State?
        let subscription = context.state.start(next: { state = $0 })
        account.network.pending[0].succeed([1, 2], count: 2)
        context.reload()
        XCTAssertEqual(account.network.pending[1].request.offset, 0)
        XCTAssertEqual(state?.files.map { $0.fileId }, [1, 2])
        XCTAssertEqual(state?.dataState, .loading)
        account.network.pending[1].fail()
        XCTAssertEqual(state?.files.map { $0.fileId }, [1, 2])
        XCTAssertEqual(state?.dataState, .ready(canLoadMore: true))
        subscription.dispose()
    }

    func testSuccessPaginatesThenStopsOnEmptyPage() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        var state: ProfileSavedMusicContext.State?
        let subscription = context.state.start(next: { state = $0 })
        account.network.pending[0].succeed([1, 2], count: 5)
        XCTAssertEqual(state?.dataState, .ready(canLoadMore: true))
        context.loadMore()
        XCTAssertEqual(account.network.pending[1].request.offset, 2)
        account.network.pending[1].succeed([], count: 5)
        XCTAssertEqual(state?.dataState, .ready(canLoadMore: false))
        XCTAssertEqual(state?.files.map { $0.fileId }, [1, 2])
        context.loadMore()
        XCTAssertEqual(account.network.pending.count, 2)
        subscription.dispose()
    }

    func testContextDeinitCancelsOutstandingRequest() {
        let account = Account()
        var context: ProfileSavedMusicContext? = ProfileSavedMusicContext(account: account, peerId: 1)
        weak var weakContext = context
        context = nil
        XCTAssertNil(weakContext)
        XCTAssertTrue(account.network.pending[0].cancelled)
    }

    func testFailedLaterPagePreservesFilesAndRetriesSameOffset() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        var state: ProfileSavedMusicContext.State?
        let subscription = context.state.start(next: { state = $0 })
        account.network.pending[0].succeed([1, 2], count: 4)
        context.loadMore()
        account.network.pending[1].fail()
        XCTAssertEqual(state?.files.map { $0.fileId }, [1, 2])
        XCTAssertEqual(state?.dataState, .ready(canLoadMore: true))
        context.loadMore()
        XCTAssertEqual(account.network.pending.map { $0.request.offset }, [0, 2, 2])
        if account.network.pending.count == 3 {
            account.network.pending[2].succeed([3, 4], count: 4)
            XCTAssertEqual(state?.files.map { $0.fileId }, [1, 2, 3, 4])
            XCTAssertEqual(state?.dataState, .ready(canLoadMore: false))
        }
        subscription.dispose()
    }

    func testReloadCancelsOldRequestAndReplacesFilesOnSuccess() {
        let account = Account()
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        var state: ProfileSavedMusicContext.State?
        let subscription = context.state.start(next: { state = $0 })
        context.reload()
        XCTAssertTrue(account.network.pending[0].cancelled)
        account.network.pending[0].succeed([1, 2], count: 2)
        account.network.pending[1].succeed([9], count: 1)
        XCTAssertEqual(state?.files.map { $0.fileId }, [9])
        XCTAssertEqual(state?.dataState, .ready(canLoadMore: false))
        subscription.dispose()
    }

    func testCachedMusicRemainsVisibleAfterRequestFailure() {
        let account = Account()
        account.postbox.storage.cache = CodableEntry(CachedProfileSavedMusic(files: [TelegramMediaFile(fileId: 7)], count: 3))
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        var state: ProfileSavedMusicContext.State?
        let subscription = context.state.start(next: { state = $0 })
        XCTAssertEqual(state?.files.map { $0.fileId }, [7])
        XCTAssertEqual(account.network.pending[0].request.offset, 0)
        account.network.pending[0].fail()
        XCTAssertEqual(state?.files.map { $0.fileId }, [7])
        XCTAssertEqual(state?.dataState, .ready(canLoadMore: true))
        subscription.dispose()
    }

    func testCachedFirstPageRetryStillStartsAtZeroAndReplacesCache() {
        let account = Account()
        account.postbox.storage.cache = CodableEntry(CachedProfileSavedMusic(files: [TelegramMediaFile(fileId: 7)], count: 3))
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        var state: ProfileSavedMusicContext.State?
        let subscription = context.state.start(next: { state = $0 })
        account.network.pending[0].fail()
        context.loadMore()
        XCTAssertEqual(account.network.pending.map { $0.request.offset }, [0, 0])
        if account.network.pending.count == 2 {
            account.network.pending[1].succeed([9], count: 1)
            XCTAssertEqual(state?.files.map { $0.fileId }, [9])
        }
        subscription.dispose()
    }

    func testCacheArrivingAfterFailureIsPublished() {
        let account = Account()
        account.postbox.storage.cache = CodableEntry(CachedProfileSavedMusic(files: [TelegramMediaFile(fileId: 7)], count: 3))
        account.postbox.delayNextTransaction = true
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        var state: ProfileSavedMusicContext.State?
        let subscription = context.state.start(next: { state = $0 })
        account.network.pending[0].fail()
        account.postbox.finishTransaction?()
        XCTAssertEqual(state?.files.map { $0.fileId }, [7])
        XCTAssertEqual(state?.dataState, .ready(canLoadMore: true))
        subscription.dispose()
    }

    func testStaleCacheWriteCannotOverwriteAcceptedMutation() throws {
        let account = Account()
        seed(account, [1])
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        account.postbox.delayNextTransaction = true
        account.network.pending[0].succeed([1], count: 1)
        let staleWrite = try XCTUnwrap(account.postbox.finishTransaction)
        let action = context.addMusic(file: file(2)).start()
        account.network.mutations[0].succeed()
        XCTAssertEqual(cachedIds(account), [2, 1])
        staleWrite()
        XCTAssertEqual(cachedIds(account), [2, 1])
        XCTAssertEqual(preferenceIds(account), [1, 2])
        action.dispose()
    }

    func testReloadInvalidatesAlreadyCapturedCacheWrite() throws {
        let account = Account()
        seed(account, [9])
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        account.postbox.delayNextTransaction = true
        account.network.pending[0].succeed([1], count: 1)
        let staleWrite = try XCTUnwrap(account.postbox.finishTransaction)
        context.reload()
        account.network.pending[1].succeed([2], count: 1)
        XCTAssertEqual(cachedIds(account), [2])
        staleWrite()
        XCTAssertEqual(cachedIds(account), [2])
    }

    func testUnsubscribedMutationDoesNotRetainContext() {
        let account = Account()
        var context: ProfileSavedMusicContext? = ProfileSavedMusicContext(account: account, peerId: 1)
        account.network.pending[0].succeed([1], count: 1)
        let signal = context!.addMusic(file: file(2))
        weak var weakContext = context
        context = nil
        XCTAssertNil(weakContext)
        XCTAssertTrue(account.network.mutations.isEmpty)
        let action = signal.start()
        account.network.mutations[0].succeed()
        XCTAssertEqual(cachedIds(account), [2, 1])
        XCTAssertEqual(account.network.pending.count, 1)
        action.dispose()
    }

    func testRejectedMutationRefreshesWithoutPersistingOptimisticValue() {
        let account = Account()
        seed(account, [1])
        let context = ProfileSavedMusicContext(account: account, peerId: 1)
        account.network.pending[0].succeed([1], count: 1)
        var state: ProfileSavedMusicContext.State?
        let subscription = context.state.start(next: { state = $0 })
        var failed = false
        let action = context.addMusic(file: file(2)).start(error: { _ in failed = true })
        XCTAssertEqual(state?.files.map { $0.fileId }, [2, 1])
        account.network.mutations[0].succeed(false)
        XCTAssertTrue(failed)
        XCTAssertEqual(cachedIds(account), [1])
        XCTAssertEqual(preferenceIds(account), [1])
        XCTAssertEqual(account.network.pending.count, 2)
        if account.network.pending.count == 2 {
            XCTAssertEqual(account.network.pending[1].request.offset, 0)
            account.network.pending[1].succeed([1], count: 1)
        }
        XCTAssertEqual(state?.files.map { $0.fileId }, [1])
        action.dispose()
        subscription.dispose()
    }

    func testPickerDoesNotShowEmptyWhileSavedMusicLoads() {
        var picker = SendAudioState()
        picker.sharedAudioLoaded = true
        picker = applySaved(.init(files: [], count: nil, dataState: .loading), to: picker)
        XCTAssertFalse(picker.savedMusicLoaded)
        XCTAssertFalse(showsEmpty(picker))
        picker = applySaved(.init(files: [], count: 0, dataState: .ready(canLoadMore: false)), to: picker)
        XCTAssertTrue(picker.savedMusicLoaded)
        XCTAssertTrue(showsEmpty(picker))
    }

    func testLoadingSectionIsUniqueWhenSharedAudioAlreadyExists() {
        var picker = SendAudioState()
        picker.sharedAudio = [TelegramMediaFile(fileId: 1)]
        picker.sharedAudioLoaded = true
        XCTAssertEqual(sharedSections(picker), [3])
        picker.sharedAudio = []
        XCTAssertEqual(sharedSections(picker), [3])
        picker.savedMusicLoaded = true
        XCTAssertEqual(sharedSections(picker), [])
    }
}
