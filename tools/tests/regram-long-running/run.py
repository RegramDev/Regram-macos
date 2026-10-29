import argparse
import hashlib
import json
from pathlib import Path
import re
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


parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, default=Path('/tmp/regram-long-running-20261029'))
parser.add_argument('--expect-old-behavior', action='store_true')
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
let package = Package(name: "LongRunningChecks", platforms: [.macOS(.v10_13)], targets: [.target(name: "SwiftSignalKit"), .testTarget(name: "LongRunningTests", dependencies: ["SwiftSignalKit"], path: "Tests")])
''')
paths = [
    'packages/ChatUI/Sources/ChatUI/ChatHistoryRenderGate.swift',
    'packages/ChatListUI/Sources/ChatListUI/ChatListVisibleStoryResources.swift',
    'packages/ChatListUI/Sources/ChatListUI/RegramChatListPreview.swift',
    'packages/ChatUI/Sources/ChatUI/ChatController.swift',
    'packages/ChatListUI/Sources/ChatListUI/ChatListController.swift',
]
source = {path: (ROOT / path).read_text() for path in paths}
gate, stories, preview, controller, chat_list = [source[path] for path in paths]
remote = declaration(preview, '    private func isCurrentRemoteRequest(') + '\n' + declaration(preview, '    private func loadRemotePage(')
history_mapper = controller[controller.index('    ) |> filter { historyRenderGate.isCurrent'):controller.index('        let appliedTransition = historyViewTransition')]
owner_capture = '[weak self]' if '|> mapToQueue { [weak self]' in history_mapper else ''
owner_assignment = re.search(r'self\??\.currentRanks = data', history_mapper).group(0)
accept = 'gate.isCurrent($0.0.version)'
scroll_guard = 'guard gate.capture() != nil, visibleMessageWorkEnabled else { return }'
scroll_cancel = 'work?.cancel(); work = nil'
if args.expect_old_behavior:
    start = gate.index('func chatHistoryRenderingUpdates')
    gate = gate[:start] + '''func chatHistoryRenderingUpdates<Value>(_ history: Signal<Value, NoError>, visibility: Signal<Bool, NoError>, gate: ChatHistoryRenderGate) -> Signal<ChatHistoryRenderingUpdate<Value>, NoError> {
        return history |> map { ChatHistoryRenderingUpdate(value: $0, version: nil) }
    }
'''
    stories = '''import SwiftSignalKit
func chatListVisibleStoryResources<Value>(visibility: Signal<Bool, NoError>, hidden: Signal<Bool, NoError>, empty: Value, load: @escaping () -> Signal<Value, NoError>) -> Signal<Value, NoError> {
    return hidden |> distinctUntilChanged |> mapToSignal { hidden in hidden ? .single(empty) : load() } |> deliverOnMainQueue
}
'''
    remote = remote.replace('guard isCurrentRemoteRequest(request, disposable: disposable) else { return }', 'guard !disposed.with({ $0 }), states[request.id]?.key == request.key else { return }')
    remote = remote.replace('guard let self, self.isCurrentRemoteRequest(request, disposable: disposable) else { return }', 'guard let self, !self.disposed.with({ $0 }), self.states[request.id]?.key == request.key else { return }')
    accept = '_ in true'
    scroll_guard = ''
    scroll_cancel = ''
    owner_capture = ''
    owner_assignment = 'self.currentRanks = data'
assert 'let historyViewTransition = combineLatest(queue: queue,' in controller
assert 'renderingHistory,' in controller
assert 'filter { historyRenderGate.isCurrent($0.0.version) }' in controller
assert controller.index('let update = renderingUpdate.value') < controller.index('let pollAnswersLoading = uiState.pollAnswers')
hidden = declaration(controller, '    public override func viewWillDisappear(')
assert 'historyRenderGate.setActive(false)' in hidden and 'heavyScrollWorkItem?.cancel()' in hidden
assert 'historyRenderGate.setActive(true)' in declaration(controller, '    public override func viewWillAppear(')
assert 'genericView.tableView.notifyScrollHandlers()' in declaration(controller, '    public override func viewDidAppear(')
assert 'historyRenderGate.setActive' not in declaration(controller, '    public override func windowDidResignKey(')
assert 'historyRenderGate.setActive' not in declaration(controller, '    public override func windowDidBecomeKey(')
assert 'visibility.set' not in declaration(controller, '    public override func viewDidAppear(')
assert 'heavyScrollWorkItem?.cancel()' in declaration(controller, '    public override func windowDidResignKey(')
assert 'guard visibleMessageWorkEnabled else { return }' in declaration(controller, '    public override func windowDidBecomeKey(')
assert 'self.historyRenderGate.capture() != nil, self.visibleMessageWorkEnabled' in controller
assert 'strongSelf.historyRenderGate.capture() != nil, strongSelf.visibleMessageWorkEnabled' in controller
assert 'visibleMessageWorkEnabled = false' in hidden
assert 'visibleMessageWorkEnabled = true' in declaration(controller, '    public override func viewWillAppear(')
assert 'chatListVisibleStoryResources(visibility: self.viewOnStage' in chat_list
fixture = (HERE / 'LongRunningTests.swift').read_text()
for marker, value in {'__REMOTE_METHODS__': remote, '__RENDER_ACCEPT__': accept, '__SCROLL_GUARD__': scroll_guard, '__SCROLL_CANCEL__': scroll_cancel, '__HISTORY_OWNER_CAPTURE__': owner_capture, '__HISTORY_OWNER_ASSIGNMENT__': owner_assignment}.items():
    fixture = fixture.replace(marker, value)
(tests / 'ChatHistoryRenderGate.swift').write_text(gate)
(tests / 'ChatListVisibleStoryResources.swift').write_text(stories)
(tests / 'LongRunningTests.swift').write_text(fixture)
manifest = {path: hashlib.sha256(text.encode()).hexdigest() for path, text in source.items()}
manifest['negativeControl'] = args.expect_old_behavior
(args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
negative = ['testHiddenHistoryRetainsOnlyLatestAndResumesOnce', 'testQueuedOldHistoryCannotRenderAfterHideAndResume', 'testHiddenPresentationUpdatesDoNotBuildHistory', 'testHiddenStoriesDoNotStartPreload', 'testHidingStoriesCancelsCurrentSubscriptionAndClearsResources', 'testQueuedStoryResultCannotRestartPreloadAfterHide', 'testCancelledDelayedRemotePageDoesNotStartNetwork', 'testReplacedRemoteRequestCannotBeFinishedByOldTimer', 'testInactiveRemoteRequestDoesNotStartNetwork', 'testHiddenScrollWorkCannotRunAfterReturning', 'testHistorySubscriptionReleasesRemovedController']
selected = '|'.join('LongRunningTests/' + name for name in negative) if args.expect_old_behavior else 'LongRunningTests'
log_path = args.output / 'tests.log'
with log_path.open('w') as log:
    result = subprocess.run(['swift', 'test', '--package-path', str(package), '--scratch-path', str(args.output / 'build'), '--configuration', 'release', '--jobs', '2', '-Xswiftc', '-DSTABLE', '--filter', selected], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
output = log_path.read_text()
for line in output.splitlines():
    if ': error:' in line or line.startswith('error:') or ' passed ' in line or ' failed ' in line or 'Executed ' in line:
        print(line[:600])
print('Full log:', log_path)
if args.expect_old_behavior:
    valid = result.returncode != 0 and all(f"{name}]' failed" in output for name in negative)
    print(f'PASS: all {len(negative)} old lifecycle checks failed as expected' if valid else 'FAIL: old lifecycle negative control was inconclusive')
    raise SystemExit(0 if valid else 1)
raise SystemExit(result.returncode)
