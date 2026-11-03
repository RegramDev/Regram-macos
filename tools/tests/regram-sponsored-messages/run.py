from pathlib import Path
import argparse
import subprocess


ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--revision')
parser.add_argument('--output', type=Path, default=Path('/tmp/regram-sponsored-messages-20261103/presentation-current'))
args = parser.parse_args()


def source(path):
    if args.revision:
        return subprocess.check_output(['git', '-C', str(ROOT), 'show', args.revision + ':' + path], text=True)
    return (ROOT / path).read_text()


chat = source('packages/ChatUI/Sources/ChatUI/ChatController.swift')
search = source('packages/ChatListUI/Sources/ChatListUI/SearchController.swift')
history = source('packages/ChatHistoryModel/Sources/ChatHistoryModel/ChatHistoryEntry.swift')
chat_list = source('packages/ChatListUI/Sources/ChatListUI/ChatListController.swift')
video = source('packages/GalleryUI/Sources/GalleryUI/SVideoController.swift')
header = chat.split('    func updateHeader(_ interfaceState:', 1)[1].split('    func updateMonoforumState(', 1)[0]
hide_header = next((line.strip() for line in header.splitlines() if 'let hidesSponsoredMessages =' in line), '')
bot_header = next(line.strip() for line in header.splitlines() if 'let botAd: Message?' in line)
promo = next(line.strip() for line in header.splitlines() if 'case let .ad(kind) = initialAction {' in line).split('else if ', 1)[1].rsplit('{', 1)[0].strip()
start = search.index('            var seenPeers = Set<PeerId>()')
search_projection = search[start:search.index('            visible = visible.enumerated()', start)]
channel_gate = '\n'.join(line.strip() for line in history.splitlines() if line.strip().startswith(('let adMessage = regramSettings', 'let dynamicAdMessages = regramSettings')))
start = chat_list.index('                let items = update.list.additionalItems.filter {')
proxy_list = chat_list[start:chat_list.index('                for (i, current) in items.enumerated()', start)]
start = video.index('self?.nextAdDisposable.set(delaySignal(Double(betweenDelay)).start(completed: {')
start = video.index('\n', start)
delayed_ad = video[start:video.index('                    }))', start)]
start = video.find('                guard let self, !enabled else { return }')
video_clear = '' if start < 0 else video[start:video.index('            }))', start)]
fixture = Path(__file__).with_name('SponsoredMessagePresentationTests.swift').read_text()
replacements = {'__HIDE_HEADER__': hide_header, '__BOT_HEADER__': bot_header, '__PROMO_CONDITION__': promo, '__SEARCH_PROJECTION__': search_projection, '__CHANNEL_GATE__': channel_gate, '__PROXY_LIST_GATE__': proxy_list, '__DELAYED_VIDEO_AD__': delayed_ad, '__VIDEO_CLEAR__': video_clear}
for key, value in replacements.items():
    fixture = fixture.replace(key, value)
output = args.output.resolve()
(output / 'Tests').mkdir(parents=True, exist_ok=True)
dependency = ROOT / 'submodules/telegram-ios/submodules/SSignalKit'
(output / 'Package.swift').write_text(f'''// swift-tools-version:5.5
import PackageDescription
let package = Package(name: "SponsoredMessagePresentation", platforms: [.macOS(.v12)], dependencies: [.package(name: "SSignalKit", path: "{dependency}")], targets: [.testTarget(name: "SponsoredMessagePresentationTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
(output / 'Tests/SponsoredMessagePresentationTests.swift').write_text(fixture)
print('Production revision: ' + (args.revision or 'working tree'), flush=True)
raise SystemExit(subprocess.run(['swift', 'test', '-c', 'release', '-Xswiftc', '-DSTABLE', '--package-path', str(output), '-j', '4']).returncode)
