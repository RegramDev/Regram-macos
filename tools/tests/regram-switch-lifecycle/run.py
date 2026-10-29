from pathlib import Path
import argparse
import hashlib
import json
import runpy
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def declaration(source, anchor):
    start = source.index(anchor)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, default=Path('/tmp/regram-switch-lifecycle-20261029'))
parser.add_argument('--expect-shared-queue', action='store_true')
parser.add_argument('--expect-menu-overflow', action='store_true')
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
exporter = runpy.run_path(str(ROOT / 'tools/tests/context-menu-topic-submenus/run.py'))
package = args.output / 'TGUIKit'
if package.exists():
    shutil.rmtree(package)
package = exporter['export_package'](None, args.output)
for name in ['AppMenuCloseTests.swift', 'NavigationCancellationTests.swift', 'ContextMenuItemsTests.swift', 'AppMenuPlacementTests.swift']:
    shutil.copy2(ROOT / 'packages/TGUIKit/Tests/TGUIKitTests' / name, package / 'Tests/TGUIKitTests' / name)
if args.expect_menu_overflow:
    path = package / 'Sources/AppMenuController.swift'
    source = path.read_text()
    corrected = '    frame.origin.y = max(visible.minY, min(frame.minY, visible.maxY - frame.height))'
    assert source.count(corrected) == 1
    path.write_text(source.replace(corrected, '''    if frame.minY < visible.minY {
        frame.origin.y = visible.minY
    } else if frame.maxY > visible.maxY {
        frame.origin.y = visible.maxY
    }'''))
sources = {
    '__NAVIGATION_REQUEST__': ('Telegram-Mac/app/ApplicationContext.swift', 'private final class ChatNavigationRequest'),
    '__HOVER_PREVIEW__': ('Telegram-Mac/utils/InAppLinks.swift', 'private final class LinkHoverPreview'),
    '__TRANSITION_QUEUE__': ('packages/ChatListUI/Sources/ChatListUI/ChatListTransitionQueue.swift', 'func makeChatListTransitionQueue()'),
    '__RESOURCE_QUEUE__': ('packages/TelegramTheme/Sources/TelegramTheme/ResourcesQueue.swift', 'public let prepareQueue ='),
}
fixture = (HERE / 'LifecycleChecks.swift').read_text()
manifest = {}
for marker, (path, anchor) in sources.items():
    source = (ROOT / path).read_text()
    extracted = next(line for line in source.splitlines() if line.startswith(anchor)) if marker == '__RESOURCE_QUEUE__' else declaration(source, anchor)
    if marker == '__TRANSITION_QUEUE__' and args.expect_shared_queue:
        extracted = 'func makeChatListTransitionQueue() -> Queue { return prepareQueue }'
    fixture = fixture.replace(marker, extracted)
    manifest[path] = hashlib.sha256(source.encode()).hexdigest()
for path in ['packages/TGUIKit/Sources/AppMenu.swift', 'packages/TGUIKit/Sources/AppMenuController.swift', 'packages/TGUIKit/Sources/NavigationViewController.swift', 'packages/TGUIKit/Tests/TGUIKitTests/AppMenuCloseTests.swift', 'packages/TGUIKit/Tests/TGUIKitTests/AppMenuPlacementTests.swift', 'packages/TGUIKit/Tests/TGUIKitTests/NavigationCancellationTests.swift', 'tools/tests/regram-switch-lifecycle/LifecycleChecks.swift']:
    manifest[path] = hashlib.sha256((ROOT / path).read_bytes()).hexdigest()
controller = (ROOT / 'packages/ChatListUI/Sources/ChatListUI/ChatListController.swift').read_text()
assert 'private let transitionQueue = makeChatListTransitionQueue()' in controller
assert 'accountId: context.peerId.toInt64(), queue: transitionQueue)' in controller
assert 'combineLatest(queue: transitionQueue, chatHistoryView' in controller
navigation = (ROOT / 'Telegram-Mac/app/ApplicationContext.swift').read_text()
assert 'navigation.cancelPendingPush()' in navigation
assert 'request.set(disposable, version: version)' in navigation
assert navigation.count('navigation.controller === expectedController') == 3
(package / 'Tests/TGUIKitTests/SwitchLifecycleChecks.swift').write_text(fixture)
(args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
test_filter = 'SwitchLifecycleChecks/testListQueueDoesNotWaitForUnrelatedBackgroundWork|SwitchLifecycleChecks/testIndependentListQueuesDoNotBlockEachOther' if args.expect_shared_queue else 'SwitchLifecycleChecks|NavigationCancellationTests|AppMenuCloseTests|ContextMenuItemsTests|AppMenuPlacementTests'
if args.expect_menu_overflow:
    test_filter = 'AppMenuPlacementTests/testClickAtButtonTopKeepsMenuBelowVisibleTop'
command = ['swift', 'test', '--package-path', str(package), '--scratch-path', str(args.output / 'build'), '--configuration', 'release', '--jobs', '2', '-Xswiftc', '-DSTABLE', '--filter', test_filter]
log_path = args.output / ('tests-menu-overflow.log' if args.expect_menu_overflow else 'tests-shared-queue.log' if args.expect_shared_queue else 'tests.log')
with log_path.open('w') as log:
    result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
output = log_path.read_text()
for line in output.splitlines():
    if ' error: ' in line or line.startswith('error:') or ' failed ' in line or ' passed ' in line or 'Executed ' in line:
        print(line)
print('Full log:', log_path)
if args.expect_shared_queue:
    passed = result.returncode != 0 and output.count('testIndependentListQueuesDoNotBlockEachOther]'+"' failed") == 1 and output.count('testListQueueDoesNotWaitForUnrelatedBackgroundWork]'+"' failed") == 1
    print('PASS: shared-queue negative control detected both blocked transitions' if passed else 'FAIL: shared-queue negative control did not fail as expected')
    raise SystemExit(0 if passed else 1)
if args.expect_menu_overflow:
    passed = result.returncode != 0 and "testClickAtButtonTopKeepsMenuBelowVisibleTop]' failed" in output
    print('PASS: original top-edge overflow detected' if passed else 'FAIL: top-edge overflow negative control was inconclusive')
    raise SystemExit(0 if passed else 1)
raise SystemExit(result.returncode)
