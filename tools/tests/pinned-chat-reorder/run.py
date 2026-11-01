from pathlib import Path
import hashlib
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
source_path = ROOT / 'packages/ChatListUI/Sources/ChatListUI/ChatListController.swift'
source = source_path.read_text()
method_start = source.index('    private func resortPinned(')
body_start = source.index('        default:\n            guard from != to', method_start) + len('        default:\n')
body_end = source.index('\n        }\n', body_start)
fixture = (HERE / 'PinnedChatReorderTests.swift').read_text().replace('__REORDER_BODY__', source[body_start:body_end])
with tempfile.TemporaryDirectory(prefix='pinned-chat-reorder-') as temporary:
    directory = Path(temporary)
    dependency = str(ROOT / 'submodules/telegram-ios/submodules/SSignalKit')
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "PinnedChatReorder", platforms: [.macOS(.v10_13)], dependencies: [.package(path: "''' + dependency + '''")], targets: [.testTarget(name: "PinnedChatReorderTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/PinnedChatReorderTests.swift').write_text(fixture)
    print('Production source SHA-256: ' + hashlib.sha256(source_path.read_bytes()).hexdigest(), flush=True)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--configuration', 'release', '-Xswiftc', '-DSTABLE', '--jobs', '2']).returncode)
