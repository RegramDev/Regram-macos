from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
settings = (root / 'packages/InAppSettings/Sources/InAppSettings/BaseApplicationSettings.swift').read_text()
settings = settings[settings.index('    public struct TranslatePaywall'):settings.index('    public let handleInAppKeys')]
source = (root / 'packages/ChatHistoryModel/Sources/ChatHistoryModel/ChatLiveTranslateContext.swift').read_text()
visibility = source[source.index('            var isHidden: Bool'):source.index('            let hasTelegramPremium =')]
fixture = Path(__file__).with_name('PaywallTests.swift').read_text()
fixture = fixture.replace('__SETTINGS__', settings).replace('__VISIBILITY__', visibility)
with tempfile.TemporaryDirectory(prefix='translation-paywall-') as directory:
    path = Path(directory)
    (path / 'main.swift').write_text(fixture)
    subprocess.run(['xcrun', 'swiftc', '-O', '-D', 'STABLE', str(path / 'main.swift'), '-o', str(path / 'tests')], check=True)
    subprocess.run([str(path / 'tests')], check=True)
