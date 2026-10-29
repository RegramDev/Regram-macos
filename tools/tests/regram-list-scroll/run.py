import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, default=Path('/tmp/regram-list-scroll-20261029'))
parser.add_argument('--expect-immediate', action='store_true')
args = parser.parse_args()
package = args.output / 'Package'
source = package / 'Sources/SwiftSignalKit'
tests = package / 'Tests'
package.mkdir(parents=True, exist_ok=True)
shutil.rmtree(source, ignore_errors=True)
shutil.copytree(ROOT / 'submodules/telegram-ios/submodules/SSignalKit/SwiftSignalKit/Source', source)
tests.mkdir(exist_ok=True)
(package / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ScrollRefreshChecks", platforms: [.macOS(.v10_13)], targets: [.target(name: "SwiftSignalKit"), .testTarget(name: "ScrollRefreshTests", dependencies: ["SwiftSignalKit"], path: "Tests")])
''')
path = ROOT / 'packages/ChatListUI/Sources/ChatListUI/ChatListScrollUpdates.swift'
helper = path.read_text()
controller = (ROOT / 'packages/ChatListUI/Sources/ChatListUI/ChatListController.swift').read_text()
assert 'chatListSettledScrollUpdates(visibleStoryRefreshEvents.signal(), visibility: self.viewOnStage)' in controller
assert 'self?.visibleStoryRefreshEvents.putNext(())' in controller
assert 'visibleStoryRefreshDisposable.dispose()' in controller
if args.expect_immediate:
    helper = '''import SwiftSignalKit
func chatListSettledScrollUpdates(_ events: Signal<Void, NoError>, visibility: Signal<Bool, NoError>, queue: Queue) -> Signal<Void, NoError> {
    visibility |> distinctUntilChanged |> deliverOn(queue) |> mapToSignal { visible in
        visible ? (.single(()) |> then(events |> deliverOn(queue))) : .never()
    }
}
'''
(tests / 'ChatListScrollUpdates.swift').write_text(helper)
shutil.copy2(HERE / 'ScrollRefreshTests.swift', tests)
(args.output / 'manifest.json').write_text(json.dumps({'sourceSHA256': hashlib.sha256(path.read_bytes()).hexdigest(), 'controllerSHA256': hashlib.sha256(controller.encode()).hexdigest(), 'immediateNegativeControl': args.expect_immediate}, indent=2) + '\n')
negative = ['testInitialRefreshWaitsForScrollingToSettle', 'testRapidVisibleRangeChangesRefreshLatestPeersOnce', 'testHidingListCancelsPendingRefresh', 'testDisposalCancelsPendingRefresh']
selected = '|'.join('ScrollRefreshTests/' + name for name in negative) if args.expect_immediate else 'ScrollRefreshTests'
log_path = args.output / 'tests.log'
with log_path.open('w') as log:
    result = subprocess.run(['swift', 'test', '--package-path', str(package), '--scratch-path', str(args.output / 'build'), '--configuration', 'release', '--jobs', '2', '-Xswiftc', '-DSTABLE', '--filter', selected], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
output = log_path.read_text()
for line in output.splitlines():
    if ': error:' in line or line.startswith('error:') or ' passed ' in line or ' failed ' in line or 'Executed ' in line:
        print(line[:600])
print('Full log:', log_path)
if args.expect_immediate:
    valid = result.returncode != 0 and all(f"{name}]' failed" in output for name in negative)
    print('PASS: immediate refresh behavior detected' if valid else 'FAIL: negative control was inconclusive')
    raise SystemExit(0 if valid else 1)
raise SystemExit(result.returncode)
