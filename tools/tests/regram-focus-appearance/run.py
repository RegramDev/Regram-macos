from pathlib import Path
import argparse
import hashlib
import json
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def declaration(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    cursor = opening + 1
    depth = 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source', type=Path, default=ROOT / 'Telegram-Mac/packages-integration/bridges/RegramAppearanceIntegration.swift')
    parser.add_argument('--products', type=Path, default=Path.home() / 'Library/Caches/RegramReleaseDerivedData-arm64/Build/Products/Release')
    parser.add_argument('--output', type=Path, default=Path('/tmp/regram-focus-appearance-checks'))
    options = parser.parse_args()
    bridge = options.source.read_text()
    font_path = ROOT / 'packages/TGUIKit/Sources/InterfaceFontProvider.swift'
    appearance_path = ROOT / 'packages/TelegramTheme/Sources/TelegramTheme/AppearanceGlobal.swift'
    replacements = {
        'PRODUCTION_BINDING': declaration(bridge, 'private final class RegramFontAppearanceBinding {'),
        'PRODUCTION_BIND_FUNCTION': declaration(bridge, 'func bindRegramFonts('),
        'PRODUCTION_FONT_PROVIDER': font_path.read_text(),
        'PRODUCTION_APPEARANCE_SIGNAL': declaration(appearance_path.read_text(), 'public var appearanceSignal:Signal<Appearance, NoError>').replace('public ', ''),
    }
    fixture = (HERE / 'FocusAppearanceChecks.swift').read_text()
    for name, value in replacements.items():
        if fixture.count(name) != 1:
            raise RuntimeError('Invalid marker ' + name)
        fixture = fixture.replace(name, value)
    options.output.mkdir(parents=True, exist_ok=True)
    source = options.output / 'ProductionFocusAppearanceChecks.swift'
    source.write_text(fixture)
    (options.output / 'manifest.json').write_text(json.dumps({'source': str(options.source), 'sourceSHA256': hashlib.sha256(bridge.encode()).hexdigest(), 'extractedProductionHashes': {name: hashlib.sha256(value.encode()).hexdigest() for name, value in replacements.items()}, 'fontProvider': str(font_path), 'appearanceSignal': str(appearance_path), 'notificationCenter': 'real', 'signals': 'real SwiftSignalKit', 'appKitWindows': 'two hidden NSWindow instances with synthetic key notifications', 'realAccountOrPreferenceAccess': False}, indent=2))
    binary = options.output / 'focus-appearance-checks'
    args = ['xcrun', 'swiftc', '-parse-as-library', '-D', 'STABLE', '-target', platform.machine() + '-apple-macos12.0', '-I', str(options.products), str(options.products / 'SwiftSignalKit.o'), str(source), '-o', str(binary)]
    with (options.output / 'compile.log').open('w') as log:
        result = subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print(f'compile exit={result.returncode}; log={options.output / "compile.log"}')
        raise SystemExit(result.returncode)
    raise SystemExit(subprocess.run([str(binary), str(options.output)]).returncode)


if __name__ == '__main__':
    main()
