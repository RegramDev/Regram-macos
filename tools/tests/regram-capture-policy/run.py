from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import re
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--native-output', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
command = shlex.split((args.native_output / 'compile-command.txt').read_text())
command = [part for part in command if not part.endswith('.swift')]
command[command.index('-module-name') + 1] = 'CapturePolicyChecks'
app = args.output / 'CapturePolicyChecks.app/Contents'
(app / 'MacOS').mkdir(parents=True, exist_ok=True)
(app / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'local.regram.CapturePolicyChecks', 'CFBundleExecutable': 'capture-checks', 'CFBundlePackageType': 'APPL', 'LSUIElement': True}))
executable = app / 'MacOS/capture-checks'
command[command.index('-o') + 1] = str(executable)
chat = ROOT / 'packages/ChatUI/Sources/ChatUI/ChatMediaItem.swift'
gallery = ROOT / 'packages/GalleryUI/Sources/GalleryUI/GalleryViewer.swift'
thumb = ROOT / 'packages/GalleryUI/Sources/GalleryUI/GalleryThumbsControlView.swift'
policy = ROOT / 'packages/ChatHistoryModel/Sources/ChatHistoryModel/RegramMessageExportPolicy.swift'
export = ROOT / 'packages/GalleryUI/Sources/GalleryUI/RegramGalleryExport.swift'
chat_expression = re.search(r'parameters\?\.isProtected = (.+)', chat.read_text())[1].replace('context.peerId.toInt64()', 'accountId').replace('chatInteraction.presentation.cachedData', 'cachedData')
body = gallery.read_text().split('private func updateCaptureExclusion() {', 1)[1]
gallery_expression = body.split('let isProtected = ', 1)[1].split('\n        if isProtected', 1)[0].replace('pager.selectedItem', 'entry.map { Selection(entry: $0) }').replace('context.peerId.toInt64()', 'accountId')
thumb_expression = re.search(r'let preventsCapture = (.+)', thumb.read_text())[1].replace('item.item.entry', 'entry').replace('item.item.context.peerId.toInt64()', 'accountId')
source = args.output / 'CaptureBindings.swift'
source.write_text('import Cocoa\nimport Postbox\nimport TelegramCore\nimport GalleryUI\nimport MessageUtils\nstruct Selection { let entry: GalleryEntry }\n' + f'func chatProtects(_ message: Message, accountId: Int64, cachedData: CachedPeerData?) -> Bool {{ {chat_expression} }}\n' + f'func galleryProtects(_ entry: GalleryEntry?, accountId: Int64, cachedPeerData: CachedPeerData?) -> Bool {{ {gallery_expression} }}\n' + f'func thumbProtects(_ entry: GalleryEntry, accountId: Int64) -> Bool {{ {thumb_expression} }}\n')
export_source = args.output / 'RegramGalleryExport.swift'
export_source.write_text('import GalleryUI\n' + export.read_text())
command += [str(source), str(policy), str(export_source), str(HERE / 'CapturePolicyChecks.swift')]
(args.output / 'manifest.json').write_text(json.dumps({'productionSources': {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [chat, gallery, thumb, policy, export]}, 'adaptation': 'Extract actual capture expressions; replace context access with fixture arguments. Compile unchanged export policy and GalleryEntry extension using Release dependencies. Preferences belong to local.regram.CapturePolicyChecks.'}, indent=2))
with (args.output / 'compile.log').open('w') as log:
    result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
if result.returncode:
    raise SystemExit(f'Compile failed: {args.output / "compile.log"}')
with (args.output / 'tests.log').open('w') as log:
    result = subprocess.run([str(executable)], cwd=args.output, stdout=log, stderr=subprocess.STDOUT)
print((args.output / 'tests.log').read_text()[-1800:])
raise SystemExit(result.returncode)
