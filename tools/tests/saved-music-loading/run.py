import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--core-source', type=Path, default=root / 'submodules/telegram-ios/submodules/TelegramCore/Sources/TelegramEngine/Peers/SavedMusic.swift')
parser.add_argument('--ui-source', type=Path, default=root / 'packages/PeerMediaUI/Sources/PeerMediaUI/SendAudioModalController.swift')
parser.add_argument('--output', type=Path, default=Path('/tmp/regram-saved-music-loading'))
parser.add_argument('--filter')
args = parser.parse_args()
core = args.core_source.read_text()
start = core.index('public final class ProfileSavedMusicContext')
context = core[start:]
context = context.replace('public ', '')
start = core.index('private func updatedSavedMusicFiles(') if 'private func updatedSavedMusicFiles(' in core else core.index('func _internal_addSavedMusic(')
mutations = core[start:core.index('private final class CachedProfileSavedMusic', start)]
ui = args.ui_source.read_text()
start = ui.index('        updateState { current in', ui.index('let savedMusicContext =')) + len('        updateState { current in')
update = ui[start:ui.index('\n        }', start)]
start = ui.index('        let contentEmpty =')
empty = ui[start:ui.index('\n', start)]
start = ui.index('        if !state.savedMusicLoaded || !state.sharedAudioLoaded {')
loading = ui[start:ui.index('\n    } else {', start)]
start = ui.index('        if !state.sharedAudio.isEmpty {')
shared = ui[start:ui.index('            entries.append(.desc', start)] + '\n        }\n'
fixture = Path(__file__).with_name('SavedMusicTests.swift').read_text()
for key, value in [('__CONTEXT__', context), ('__MUTATIONS__', mutations), ('__UI_UPDATE__', update), ('__EMPTY__', empty), ('__LOADING__', shared + loading)]:
    fixture = fixture.replace(key, value)
output = args.output.resolve()
directory = output / 'Package'
directory.mkdir(parents=True, exist_ok=True)
dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
(directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "SavedMusicLoading", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "SavedMusicTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
(directory / 'Tests').mkdir(exist_ok=True)
(directory / 'Tests/SavedMusicTests.swift').write_text(fixture)
command = ['swift', 'test', '--package-path', str(directory), '--scratch-path', str(output / 'build'), '--disable-sandbox', '--jobs', '2', '--configuration', 'release', '-Xswiftc', '-DSTABLE', '--xunit-output', str(output / 'results.xml')]
if args.filter:
    command += ['--filter', args.filter]
(output / 'manifest.json').write_text(json.dumps({'coreSource': str(args.core_source), 'coreSHA256': hashlib.sha256(core.encode()).hexdigest(), 'uiSource': str(args.ui_source), 'uiSHA256': hashlib.sha256(ui.encode()).hexdigest(), 'fixtureSHA256': hashlib.sha256(fixture.encode()).hexdigest(), 'command': command}, indent=2))
(output / 'results.xml').unlink(missing_ok=True)
with (output / 'tests.log').open('w') as log:
    result = subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT)
log_text = (output / 'tests.log').read_text()
for line in log_text.splitlines():
    if 'error:' in line or 'Executed ' in line or "' failed" in line:
        print(line)
print('Full log:', output / 'tests.log')
report = output / 'results.xml'
cases = ET.parse(report).getroot().findall('.//testcase') if report.exists() else []
failures = [case.attrib.get('name') for case in cases if case.find('failure') is not None or case.find('error') is not None]
if not cases:
    cases = re.findall(r"^Test Case '(.+)' (passed|failed) ", log_text, flags=re.M)
    failures = [name for name, outcome in cases if outcome == 'failed']
(output / 'report.json').write_text(json.dumps({'exitCode': result.returncode, 'tests': len(cases), 'failedCases': failures}, indent=2))
raise SystemExit(result.returncode or int(not cases or bool(failures)))
