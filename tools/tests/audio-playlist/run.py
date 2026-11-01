import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/AudioPlayerCore/Sources/AudioPlayerCore/AudioPlayerController.swift')
args = parser.parse_args()
s = args.source.read_text()

def section(start, end):
    offset = s.index(start)
    return s[offset:s.index(end, offset)]

fixture = Path(__file__).with_name('PlaylistTests.swift').read_text()
message_equality = (root / 'packages/TelegramUtils/Sources/TelegramUtils/IsEqualMessages.swift').read_text().replace('import TelegramCore', '').replace('import Postbox', '')
fixture = fixture.replace('__MESSAGE_EQUALITY__', message_equality.replace('public ', ''))
for key, value in [
    ('__STATE__', section('    public struct State : Equatable {', '    private var mediaPlayer:')),
    ('__TRANSITION__', section('public struct APTransition', 'fileprivate func prepareItems(')),
    ('__ENTRY_EQUALITY__', section('public func ==(lhs:APEntry', 'public func <(lhs:APEntry')),
    ('__MERGE__', section('    fileprivate func merge(with transition:', '    public func nextOrderState()')),
    ('__CHAT_APPLY__', section('        disposable.set(apply.start(next: { [weak self] transition in\n', '\n        }))').split('\n', 1)[1]),
    ('__SONG__', section('    private var _song:APSongItem?', '    public var timebase:')),
    ('__GLOBAL__', section('    public func notifyGlobalStateChanged(', '    public var isPlaying:')),
    ('__NOTIFICATIONS__', section('    private func notifyStateChanged(', '    private let streamable:')),
    ('__NAVIGATION__', section('    @discardableResult public func next()', '    fileprivate func play(with item:')),
    ('__FINISH__', section('    public var isLatest:', '    public func audioPlayerDidChangedTimebase')),
    ('__STOP__', section('    public func stop()', '    @discardableResult public func set(trackProgress:')),
    ('__CLEANUP__', section('    public func cleanup()', '    private func updateUIAfterTick')),
    ('__LISTENERS__', section('    public func add(listener:', '\n}\n\npublic class APChatController')),
]:
    fixture = fixture.replace(key, value.replace('public ', '').replace('fileprivate ', '').replace('private ', ''))
metadata = section('    fileprivate func updateMetadata(', '    public override var stableId:') if '    fileprivate func updateMetadata(' in s else ''
fixture = fixture.replace('__METADATA__', metadata.replace('fileprivate ', ''))
with tempfile.TemporaryDirectory(prefix='audio-playlist-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('// swift-tools-version:5.9\nimport PackageDescription\nlet package = Package(name: "AudioPlaylist", platforms: [.macOS(.v10_13)], dependencies: [.package(path: '+dependency+')], targets: [.testTarget(name: "PlaylistTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])\n')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/PlaylistTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
