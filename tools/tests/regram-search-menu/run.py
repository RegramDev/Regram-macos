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
    parser.add_argument('--source', type=Path, default=ROOT / 'packages/ChatListUI/Sources/ChatListUI/PeersListController.swift')
    parser.add_argument('--output', type=Path, default=Path('/tmp/regram-search-menu-checks'))
    options = parser.parse_args()
    peers = options.source.read_text()
    start = peers.index('                let items = [ContextMenuItem(strings().composePopoverNewGroup')
    end = peers.index('\n            }\n            return menu', start)
    reveal_path = ROOT / 'packages/ChatListUI/Sources/ChatListUI/ChatListRevealItem.swift'
    reveal = reveal_path.read_text()
    cache_start = reveal.index('        let previousItems = Dictionary(uniqueKeysWithValues: segmentItems.map')
    cache_end = reveal.index('        guard !items.isEmpty', cache_start)
    segment_path = ROOT / 'packages/TGUIKit/Sources/ScrollableSegmentView.swift'
    segment = segment_path.read_text()
    replacements = {
        'PRODUCTION_MENU_BODY': peers[start:end],
        'PRODUCTION_SEGMENT_CACHE': reveal[cache_start:cache_end],
        'PRODUCTION_SELECTION_CALLBACK': declaration(reveal, '        segmentView.didChangeSelectedItem = {'),
        'PRODUCTION_SEGMENT_EQUALITY': declaration(segment, '    public static func ==(lhs: ScrollableSegmentItem, rhs: ScrollableSegmentItem)').replace('public ', ''),
    }
    fixture = (HERE / 'SearchMenuChecks.swift').read_text()
    for name, value in replacements.items():
        if fixture.count(name) != 1:
            raise RuntimeError('Invalid marker ' + name)
        fixture = fixture.replace(name, value)
    options.output.mkdir(parents=True, exist_ok=True)
    source = options.output / 'ProductionSearchMenuChecks.swift'
    source.write_text(fixture)
    (options.output / 'manifest.json').write_text(json.dumps({'source': str(options.source), 'extractedProductionHashes': {name: hashlib.sha256(value.encode()).hexdigest() for name, value in replacements.items()}, 'nativeEqualitySource': str(segment_path), 'headerSource': str(reveal_path), 'userInterfaceOrAccountAccess': False}, indent=2))
    binary = options.output / 'search-menu-checks'
    args = ['xcrun', 'swiftc', '-parse-as-library', '-D', 'STABLE', '-target', platform.machine() + '-apple-macos12.0', str(source), '-o', str(binary)]
    with (options.output / 'compile.log').open('w') as log:
        result = subprocess.run(args, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        print(f'compile exit={result.returncode}; log={options.output / "compile.log"}')
        raise SystemExit(result.returncode)
    raise SystemExit(subprocess.run([str(binary), str(options.output)]).returncode)


if __name__ == '__main__':
    main()
