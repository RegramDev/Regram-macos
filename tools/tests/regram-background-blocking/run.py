import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def declaration(source, anchor):
    start = source.index(anchor)
    cursor = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor]


def read_source(path, revision):
    if revision:
        return subprocess.check_output(['git', 'show', f'{revision}:{path}'], cwd=ROOT, text=True)
    return (ROOT / path).read_text()


parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, default=Path('/tmp/regram-background-blocking-20261029'))
parser.add_argument('--revision')
parser.add_argument('--expect-blocking', action='store_true')
args = parser.parse_args()
package = args.output / 'Package'
sources = package / 'Sources/SwiftSignalKit'
tests = package / 'Tests'
package.mkdir(parents=True, exist_ok=True)
shutil.rmtree(sources, ignore_errors=True)
shutil.copytree(ROOT / 'submodules/telegram-ios/submodules/SSignalKit/SwiftSignalKit/Source', sources)
tests.mkdir(exist_ok=True)
(package / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "BackgroundBlockingChecks", platforms: [.macOS(.v10_13)], targets: [.target(name: "SwiftSignalKit"), .testTarget(name: "BackgroundBlockingTests", dependencies: ["SwiftSignalKit"], path: "Tests")])
''')
paths = {
    'dice': 'packages/DiceCache/Sources/DiceCache/DiceCache.swift',
    'badge': 'packages/GeneralRows/Sources/GeneralRows/GlobalBadgeNode.swift',
    'main': 'Telegram-Mac/app/MainViewController.swift',
    'queues': 'packages/TelegramTheme/Sources/TelegramTheme/ResourcesQueue.swift',
    'translation': 'packages/ChatHistoryModel/Sources/ChatHistoryModel/ChatLiveTranslateContext.swift',
    'preview': 'packages/PreviewSenderUI/Sources/PreviewSenderUI/PreviewSenderController.swift',
    'chat_list': 'packages/ChatListUI/Sources/ChatListUI/ChatListController.swift',
}
source = {key: read_source(path, args.revision) for key, path in paths.items()}
dice = source['dice']
methods = declaration(dice, '    open func animationEffect(') + '\n' + declaration(dice, '    open func interactiveSymbolData(')
if '    private func dataSignal(' in dice:
    methods += '\n' + declaration(dice, '    private func dataSignal(')
queue_line = next((line.strip() for line in dice.splitlines() if 'private let queue = Queue(' in line), 'private let queue = resourcesQueue')
updates = declaration(dice, '            for diceData in data {') + '\n' + declaration(dice, '            for effect in dataEffects {')
badge_start = source['badge'].index('        self.disposable.set(s.start(next:')
if '        let semaphore = DispatchSemaphore' in source['badge']:
    badge_start = source['badge'].index('        let semaphore = DispatchSemaphore')
badge_end = source['badge'].index('\n    }', badge_start)
badge = source['badge'][badge_start:badge_end]
ready = next(line.strip() for line in source['main'].splitlines() if 'self.ready.set(combineLatest(queue:' in line)
queues = '\n'.join(line for line in source['queues'].splitlines() if line.startswith('public let resourcesQueue =') or line.startswith('public let prepareQueue ='))
translation_factory = declaration(source['translation'], 'private func makeChatTranslationQueue()') if 'private func makeChatTranslationQueue()' in source['translation'] else 'private func makeChatTranslationQueue() -> Queue { return prepareQueue }'
preview_factory = declaration(source['preview'], 'private func makeMediaPreviewQueue()') if 'private func makeMediaPreviewQueue()' in source['preview'] else 'private func makeMediaPreviewQueue() -> Queue { return prepareQueue }'
preview_schedule = declaration(source['preview'], 'private func schedulePreviewPreparedMedias(')
if 'queue: Queue' not in preview_schedule:
    preview_schedule = preview_schedule.replace('attempt: Int = 0', 'queue: Queue, attempt: Int = 0').replace('schedulePreviewPreparedMedias(apply, attempt:', 'schedulePreviewPreparedMedias(apply, queue: queue, attempt:')
preview_schedule = preview_schedule.replace('NSEvent.pressedMouseButtons', '0')
translation_queue = 'self.queue' if 'combineLatest(queue: self.queue, cachedData' in source['translation'] else 'prepareQueue'
folder_gate_anchor = 'filter { value in\n            let filterData = value.0.1'
folder_gate = declaration(source['chat_list'], folder_gate_anchor) if folder_gate_anchor in source['chat_list'] else 'filter { _ in true }'
pagination = declaration(source['chat_list'], '    private func paginationView()') if '    private func paginationView()' in source['chat_list'] else 'private func paginationView() -> EngineChatList? { return previousChatList.with { $0 } }'
apply_metadata = '        _ = previousChatList.swap(result.list)\n        _ = displayedFilterData.swap(result.filterData)' if 'ChatListRenderedTransition' in source['chat_list'] else ''
background_publish = '_ = previousChatList.swap(list)' if '_ = previousChatList.swap(update.list)' in source['chat_list'] else ''
fixture = (HERE / 'BackgroundBlockingTests.swift').read_text()
for marker, value in {
    '__QUEUES__': queues,
    '__EMOJI_CONTEXT__': declaration(dice, 'private final class EmojiDataContext'),
    '__DICE_QUEUE__': queue_line,
    '__DICE_METHODS__': methods,
    '__DICE_UPDATES__': updates,
    '__BADGE_SUBSCRIPTION__': badge,
    '__BADGE_SYNC__': 'let sync = true' if 'if sync {' in badge else '',
    '__READY_PIPELINE__': ready,
    '__TRANSLATION_FACTORY__': translation_factory,
    '__PREVIEW_FACTORY__': preview_factory,
    '__PREVIEW_SCHEDULE__': preview_schedule,
    '__TRANSLATION_QUEUE__': translation_queue,
    '__TRANSLATION_SCHEDULER__': declaration(source['translation'], 'final class RegramChatTranslationScheduler'),
    '__FOLDER_SELECTION_GATE__': folder_gate,
    '__PAGINATION_VIEW__': pagination,
    '__APPLY_METADATA__': apply_metadata,
    '__BACKGROUND_PUBLISH__': background_publish,
}.items():
    fixture = fixture.replace(marker, value)
(tests / 'BackgroundBlockingTests.swift').write_text(fixture)
manifest = {paths[key]: hashlib.sha256(value.encode()).hexdigest() for key, value in source.items()}
manifest['revision'] = args.revision or 'working-tree'
if not args.revision:
    assert dice.count('} |> deliverOn(self.queue)') == 2
    assert 'if hasLoaded.swap(true) { return }' in dice
    assert 'resourcesQueue.sync' not in dice
    assert 'DispatchSemaphore' not in source['badge']
    hooks = (ROOT / 'Telegram-Mac/packages-integration/hooks/SettingsHooksInstall.swift').read_text()
    assert 'theme.colors.accent }, sync: true)' not in hooks
    peer_info = (ROOT / 'packages/PeerInfoUI/Sources/PeerInfoUI/PeerInfoController.swift').read_text()
    assert 'yearStickers) |> deliverOnMainQueue).startStandalone' in peer_info
    translation = source['translation']
    assert 'prepareQueue' not in translation and 'deliverOnPrepareQueue' not in translation
    assert 'RegramChatTranslationScheduler(queue: self.queue' in translation
    preview = source['preview']
    assert 'prepareQueue' not in preview and 'deliverOnPrepareQueue' not in preview
    assert 'combineLatest(queue: preparationQueue,' in preview
    assert 'deliverOn(preparationQueue)' in preview
    controller = (ROOT / 'packages/ChatUI/Sources/ChatUI/ChatController.swift').read_text()
    assert 'translateSignal = liveTranslate.state' in controller
    assert 'themeWallpaper, translateSignal,' in controller
    assert 'return hReady && iReady && appearanceReady && monoforumReady' in controller
    assert 'combineLatest(queue: queue, replyHistoryFirst' in controller
    chat_list = source['chat_list']
    assert '_ = previousChatList.swap(update.list)' not in chat_list
    assert 'let view = strongSelf.paginationView()' in chat_list
    assert 'ChatListRenderedTransition(transition: transition, list: update.list, filterData: filterData)' in chat_list
    apply = declaration(chat_list, '    private func enqueueTransition(')
    assert apply.index('previousChatList.swap(result.list)') < apply.index('tableView.merge(with: transition)')
    assert apply.index('displayedFilterData.swap(result.filterData)') < apply.index('tableView.merge(with: transition)')
(args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
negative_cases = ['testSymbolSubscriptionDoesNotWaitForBusyCacheQueue', 'testEffectSubscriptionDoesNotWaitForBusyCacheQueue', 'testBadgeCreationDoesNotWaitForMainThread', 'testReadinessDoesNotWaitForResourcePreparation', 'testChatAppearanceDoesNotWaitForPrepareQueue', 'testMediaPreviewWorkDoesNotBlockNewChatAppearance', 'testIndependentChatTranslationContextsDoNotBlockEachOther', 'testMediaPreviewCompletionDoesNotWaitForPrepareQueue', 'testOldFolderUpdatesDoNotBuildRowsAfterSelectionChanges', 'testOldPagingRequestsDoNotBuildRows', 'testCurrentFolderUpdatesKeepTheirOrderAfterDiscardingOldWork', 'testFolderSelectionCannotUsePreviousFoldersPagination', 'testPreparedListDoesNotBecomePaginationSourceBeforeDisplay', 'testDisplayedListBecomesPaginationSourceAfterApply', 'testPendingPageRequestDoesNotReuseDisplayedCursor', 'testBotsFolderCannotStartFromAllChatsCursor']
selected = '|'.join('BackgroundBlockingTests/' + name for name in negative_cases) if args.expect_blocking else 'BackgroundBlockingTests'
command = ['swift', 'test', '--package-path', str(package), '--scratch-path', str(args.output / 'build'), '--configuration', 'release', '--jobs', '2', '-Xswiftc', '-DSTABLE', '--filter', selected]
log_path = args.output / 'tests.log'
with log_path.open('w') as log:
    result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
output = log_path.read_text()
for line in output.splitlines():
    if ' error: ' in line or line.startswith('error:') or ' passed ' in line or ' failed ' in line or 'Executed ' in line:
        print(line)
print('Full log:', log_path)
if args.expect_blocking:
    passed = result.returncode != 0 and all(f"{name}]' failed" in output for name in negative_cases)
    print(f'PASS: all {len(negative_cases)} original blocking paths detected' if passed else 'FAIL: blocking negative control was inconclusive')
    raise SystemExit(0 if passed else 1)
raise SystemExit(result.returncode)
