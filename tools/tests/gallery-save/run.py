import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/GalleryUI/Sources/GalleryUI/GalleryViewer.swift')
args = parser.parse_args()
source = args.source.read_text()
start = source.index('    public func saveAs(')
body = source[start:source.index('    public func showMessage()', start)]
start = body.index('                        if fast {')
end = body.index('                    }\n                }))', start)
body = body[:start] + '                        guard exportIsCurrent() else { return }\n                        strongSelf.saved.append(path)\n' + body[end:]
fixture = Path(__file__).with_name('GallerySaveTests.swift').read_text().replace('__SAVE__', body)
with tempfile.TemporaryDirectory(prefix='gallery-save-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "GallerySave", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "GallerySaveTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/GallerySaveTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '-c', 'release', '-Xswiftc', '-DSTABLE', '--disable-sandbox', '--jobs', '4']).returncode)
