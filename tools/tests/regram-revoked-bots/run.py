import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
OUTPUT = Path('/tmp/regram-revoked-bots-20261029')
PACKAGE = OUTPUT / 'Package'
TESTS = PACKAGE / 'Tests'
TESTS.mkdir(parents=True, exist_ok=True)
bridge_path = ROOT / 'submodules/telegram-ios/submodules/TelegramCore/Sources/State/RegramMessageRetention.swift'
bridge = bridge_path.read_text().split('func rgShouldRetainRevokedMessage', 1)[1].split('func rgRevokedMessageAttributes', 1)[0]
bridge = ('func rgShouldRetainRevokedMessage' + bridge).replace('RegramPreferences.shared', 'fixturePreferences!')
replay = (ROOT / 'submodules/telegram-ios/submodules/TelegramCore/Sources/State/AccountStateManagementUtils.swift').read_text()
assert 'transaction: transaction, id: $0)' in replay
assert 'transaction: transaction, id: id) else { return true }' in replay
ui = (ROOT / 'packages/RegramUI/Sources/RegramUI/RegramPrivacyToolsController.swift').read_text()
assert '("antiRevokeSkipBots", "AntiFeatures.SkipBots")' in ui
groups = ui.split('    let groups:', 1)[1].split('    let signal =', 1)[0]
groups = '    let groups:' + groups
rows = ui.split('        var rows:', 1)[1].split('\n    }\n    let controller', 1)[0]
rows = ('        var rows:' + rows).replace('RegramPreferences.shared', 'fixturePreferences!')
(TESTS / 'PrivacyFixture.swift').write_text((HERE / 'PrivacyFixture.swift').read_text().replace('__PRIVACY_GROUPS__', groups).replace('__PRIVACY_ROWS__', rows))
(TESTS / 'RevokedBotsTests.swift').write_text((HERE / 'RevokedBotsTests.swift').read_text().replace('__RETENTION_BRIDGE__', bridge))
(PACKAGE / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "RevokedBotsChecks", platforms: [.macOS(.v12)], dependencies: [.package(path: "''' + str(ROOT / 'packages/RegramCore') + '''")], targets: [.testTarget(name: "RevokedBotsTests", dependencies: [.product(name: "RegramCore", package: "RegramCore")], path: "Tests")])
''')
paths = [bridge_path, ROOT / 'packages/RegramCore/Sources/RegramCore/RegramPreferences.swift', ROOT / 'packages/RegramCore/Sources/RegramCore/RegramSettingsBackup.swift', ROOT / 'packages/RegramCore/Sources/RegramCore/RegramSettingsCatalog.swift', ROOT / 'packages/RegramUI/Sources/RegramUI/RegramPrivacyToolsController.swift']
(OUTPUT / 'manifest.json').write_text(json.dumps({str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}, indent=2) + '\n')
log_path = OUTPUT / 'tests.log'
with log_path.open('w') as log:
    result = subprocess.run(['swift', 'test', '--package-path', str(PACKAGE), '--scratch-path', str(OUTPUT / 'build'), '--configuration', 'release', '--jobs', '2', '-Xswiftc', '-DSTABLE'], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
for line in log_path.read_text().splitlines():
    if ': error:' in line or line.startswith('error:') or ' passed ' in line or ' failed ' in line or 'Executed ' in line:
        print(line[:600])
print('Full log:', log_path)
raise SystemExit(result.returncode)
