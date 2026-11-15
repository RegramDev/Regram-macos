from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
source = (root / 'packages/ChatUI/Sources/ChatUI/InputPasteboardParser.swift').read_text()
start = source.index('    public class func proccess(')
method = source[start:source.rfind('\n}')]
fixture = Path(__file__).with_name('PasteTests.swift').read_text().replace('__PROCESS__', method)
with tempfile.TemporaryDirectory(prefix='media-paste-acquisition-') as directory:
    directory = Path(directory)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "MediaPasteAcquisition", targets: [.testTarget(name: "MediaPasteAcquisitionTests", path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/PasteTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '-c', 'release', '-Xswiftc', '-DSTABLE', '--disable-sandbox', '--jobs', '4']).returncode)
