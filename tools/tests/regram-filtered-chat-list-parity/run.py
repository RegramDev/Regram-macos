#!/usr/bin/env python3
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def declaration(text, anchor):
    start = text.index(anchor)
    opening = text.index('{', start)
    depth = 1
    cursor = opening + 1
    while depth:
        depth += (text[cursor] == '{') - (text[cursor] == '}')
        cursor += 1
    return text[start:cursor]


def without_imports(text):
    return re.sub(r'^(?:internal )?import [^\n]+\n', '', text, flags=re.MULTILINE)


postbox = ROOT / 'submodules/telegram-ios/submodules/Postbox/Sources'
core = ROOT / 'submodules/telegram-ios/submodules/TelegramCore/Sources'
chat_list = ROOT / 'packages/ChatListUI/Sources/ChatListUI'
message = (postbox / 'Message.swift').read_text()
engine = (core / 'TelegramEngine/Messages/ChatList.swift').read_text()
production = without_imports((chat_list / 'RegramFilteredChatListPolicy.swift').read_text())
production += '\n' + without_imports((postbox / 'PeerReadState.swift').read_text())
production += '\n' + without_imports((core / 'MacOS/RegramConditionalRead.swift').read_text())
production += '\n' + without_imports((ROOT / 'submodules/telegram-ios/submodules/SSignalKit/SwiftSignalKit2/Source/Atomic.swift').read_text())
adapters = (HERE / 'Adapters.swift').read_text()
adapters = adapters.replace('MESSAGE_INDEX_COMPARATOR', declaration(message, 'public static func <(lhs: MessageIndex'))
adapters = adapters.replace('CHAT_LIST_INDEX_COMPARATOR', declaration(message, 'public static func <(lhs: ChatListIndex'))
adapters = adapters.replace('ENGINE_ITEM_DECLARATION', declaration(engine, 'public final class Item: Equatable'))
coordinator = (chat_list / 'RegramChatListPreview.swift').read_text()
controller = (chat_list / 'ChatListController.swift').read_text()
assert 'presentation.entries.sorted()' in controller
assert 'previousChatList.swap(result.list)' in controller
assert 'let view = strongSelf.paginationView()' in controller
assert 'previousChatList.with' in controller
assert coordinator.index('regramChatListCanReadHiddenUnread(transaction:') < coordinator.index('lease.with { current') < coordinator.index('withCurrentRevision(accountId:') < coordinator.index('withUnrevealed(accountId:')
assert 'isHidden: visibility.isHidden' in coordinator
assert 'trackHoles: false' in coordinator
assert 'while inactivePreviewLRU.count > 128' in coordinator
assert 'offsetId: request.upperBound.id.id' in coordinator
assert 'regramChatListSourceTop(messages)' in coordinator
assert 'regramChatListPreviewUpperBound(messages)' in coordinator
assert 'regramChatListSourceKeys(messages)' in coordinator
assert 'allHiddenIds.contains(entry.stableId)' in coordinator
assert 'additionalItem == nil, case .chatList = item.id' in coordinator
assert 'unreadLease.swap(nil)' in coordinator
assert 'unreadLease.modify { $0 == nil ? nil : currentRequests }' in coordinator
assert 'replaceUnreadRequests(unreadOrder.compactMap { unreadRequests[$0] })' in coordinator
native = (core / 'TelegramEngine/Messages/ApplyMaxReadIndexInteractively.swift').read_text()
native = declaration(native, 'func _internal_applyMaxReadIndexInteractively(transaction:')
assert 'Regram' not in native
message_policy = (ROOT / 'packages/ChatHistoryModel/Sources/ChatHistoryModel/RegramMessagePolicy.swift').read_text()
payload = declaration(message_policy, 'public struct RegramMessageFilterPayload:')
payload = payload.replace('fileprivate func filterText() -> String {', 'fileprivate func filterText() -> String {\n        TestCounters.shared.increment("text")')
cache = declaration(message_policy, 'private final class RegramMessageVisibilityCache')
cache = cache.replace('        let identity = RegramMessageFilterPayload.CacheIdentity(payload)', '''        if key.accountId == 77219 {
            TestCounters.shared.increment("captureStores")
            if hidden != (revision % 2 == 1) { TestCounters.shared.increment("captureMismatch") }
        }
        let identity = RegramMessageFilterPayload.CacheIdentity(payload)''')
cache = cache[:-1] + '''
    func testReset() {
        lock.lock(); values.removeAll(); evictionKeys.removeAll(); evictionOffset = 0; cost = 0; lock.unlock()
    }
    func testStats() -> (Int, Int) {
        lock.lock(); defer { lock.unlock() }; return (values.count, cost)
    }
}'''
production += '\n' + payload + '\n' + cache
production += '\nfunc resetVisibilityCache() { RegramMessageVisibilityCache.shared.testReset() }\n'
production += '\nfunc visibilityCacheStats() -> (Int, Int) { RegramMessageVisibilityCache.shared.testStats() }\n'
production += '\n' + declaration(message_policy, 'public func regramShouldHideMessage(_ message: Message, accountId: Int64, filter:')
legacy = declaration(message_policy, 'public func regramShouldHideMessage(_ message: Message, accountId: Int64, temporaryReveal:')
assert 'captureFilter(accountId: accountId)' in legacy
production += '\n' + legacy.replace('RegramPreferences.shared', 'testPreferences').replace('RegramTemporaryReveal.shared', 'testReveal')
conditional = declaration(coordinator, 'when: { transaction, apply in')
conditional = conditional[conditional.index('guard '):conditional.rindex('}')]
conditional = conditional.replace('RegramPreferences.shared', 'preferences').replace('RegramTemporaryReveal.shared', 'reveal')
production += '\nfunc submit(account: Account, request: UnreadRequest, lease: Atomic<[Int: UnreadRequest]?>, filter: RegramFilterSnapshot, preferences: RegramPreferences, reveal: RegramTemporaryReveal) -> Bool {\n'
production += 'guard let messages = account.postbox.transaction({ transaction -> [Message]? in guard lease.with({ $0?[request.id] == request }) else { return nil }; return regramChatListUnreadMessages(transaction: transaction, snapshot: request.snapshot) }).run() else { return false }\n'
production += 'let visibility = RegramChatListPreparedVisibility(messages: messages, accountId: request.source.accountId, filter: filter, revision: request.source.preferencesRevision)\n'
production += 'return regramApplyMaxReadIndexInteractively(account: account, index: request.snapshot.sourceTop, when: { transaction, apply in\n' + conditional + '\n}).run()\n}\n'
methods = ['    private func unreadKey(', '    private func unreadWasAttempted(', '    private func replaceUnreadRequests(', '    private func invalidateUnreadEvidence(', '    private func observeUnreadEvidence(', '    private func loadNextUnread()']
scheduling = '\n'.join(declaration(coordinator, anchor) for anchor in methods)
scheduling = scheduling.replace('RegramPreferences.shared', 'preferences').replace('RegramTemporaryReveal.shared', 'reveal')
scheduling = scheduling.replace('    private func loadNextUnread() {', '    private func loadNextUnread() {\n        let preferences = self.preferences\n        let reveal = self.reveal')
dispose = declaration(coordinator, '    func dispose()')
dispose = dispose[dispose.index('{') + 1:dispose.index('        scanDisposable.dispose()')]
production += """
final class SchedulingFixture {
    private let queue = prepareQueue
    private typealias CacheId = RegramChatListPeerKey
    let account: Account
    let accountId: Int64
    let preferences: RegramPreferences
    let reveal: RegramTemporaryReveal
    var postbox: Postbox { account.postbox }
    let disposed = Atomic(value: false)
    let previewLease = Atomic<Bool?>(value: false)
    let unreadLease = Atomic<[Int: UnreadRequest]?>(value: [:])
    var pendingUnread: [UnreadRequest] = []
    var unreadQueueGeneration: UInt64 = 0
    var unreadStartedInBatch = 0
    var unreadContinuationScheduled = false
    var unreadDisposables: [Int: (UnreadRequest, MetaDisposable)] = [:]
    private var unreadAttempts: [CacheId: UnreadAttempt] = [:]
    private var unreadEvidenceRevisions: [CacheId: UInt64] = [:]
    private var unreadObservations: [CacheId: UnreadObservation] = [:]
    private var currentUnreadRequests: [CacheId: UnreadRequest] = [:]
    private var nextUnreadObservationToken: UInt64 = 0
    init(account: Account, accountId: Int64, preferences: RegramPreferences, reveal: RegramTemporaryReveal) {
        self.account = account
        self.accountId = accountId
        self.preferences = preferences
        self.reveal = reveal
    }
    func update(_ requests: [UnreadRequest]) { replaceUnreadRequests(requests); loadNextUnread() }
"""
for anchor in ['    private struct UnreadAttempt', '    private struct UnreadObservation']:
    production += declaration(coordinator, anchor).replace('SourceKey', 'UnreadSource') + '\n'
production += '    func dispose() {\n' + dispose + '\n    }\n' + scheduling + '\n}\n'
full_coordinator = without_imports(coordinator)
remote = declaration(full_coordinator, '    private func loadRemotePage(')
full_coordinator = full_coordinator.replace(remote, '    private func loadRemotePage(_ request: Request, offsetId: Int32, number: Int, disposable: MetaDisposable) { testRemoteStarts += 1; if !testHoldRemote { finishRemote(request, candidate: nil) } }')
full_coordinator = full_coordinator.replace('RegramPreferences.shared', 'testPreferences').replace('RegramTemporaryReveal.shared', 'testReveal')
full_coordinator = full_coordinator[:full_coordinator.rfind('}')] + """
    var testInactiveCount: Int { inactivePreviewLRU.count }
    var testCacheCount: Int { states.count }
    var testActiveRemoteCount: Int { remoteDisposables.count }
    var testPendingPreviewCount: Int { pending.count }
    var testInFlightPreviewCount: Int { inFlight.count }
    var testPreviewRunning: Bool { running }
""" + full_coordinator[full_coordinator.rfind('}'):]
production += '\nvar testHoldRemote = false\nvar testRemoteStarts = 0\n' + full_coordinator + '\n'

with tempfile.TemporaryDirectory(prefix='regram-filtered-chat-list-parity-') as directory:
    work = Path(directory)
    source = work / 'ProductionPolicy.swift'
    source.write_text(adapters + '\n' + production)
    binary = work / 'checks'
    sources = sorted((ROOT / 'packages/RegramCore/Sources/RegramCore').glob('*.swift'))
    message_filter_path = ROOT / 'packages/RegramCore/Sources/RegramCore/MessageFilter.swift'
    instrumented_filter = work / 'MessageFilter.swift'
    instrumented_filter.write_text(message_filter_path.read_text().replace('public static func shouldHide(text: String, peerId: Int64?, rules: [RGMessageFilterRule]) -> Bool {', 'public static func shouldHide(text: String, peerId: Int64?, rules: [RGMessageFilterRule]) -> Bool {\n        TestCounters.shared.increment("matches")'))
    sources = [path for path in sources if path != message_filter_path] + [instrumented_filter]
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-DSTABLE', '-warnings-as-errors', *map(str, sources), str(source), str(HERE / 'main.swift'), '-o', str(binary)], cwd=ROOT, check=True)
    subprocess.run([str(binary)], cwd=ROOT, check=True, timeout=45)
