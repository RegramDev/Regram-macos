from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def declaration(source, marker):
    start = source.index(marker)
    cursor = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[start:cursor]


parser = argparse.ArgumentParser()
parser.add_argument("--native-output", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
command = shlex.split((args.native_output / "compile-command.txt").read_text())
command = [part for part in command if not part.endswith(".swift")]
command[command.index("-module-name") + 1] = "MessageExpiryChecks"
app = args.output / "MessageExpiryChecks.app/Contents"
(app / "MacOS").mkdir(parents=True, exist_ok=True)
(app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "local.regram.MessageExpiryChecks", "CFBundleExecutable": "expiry-checks", "CFBundlePackageType": "APPL", "LSUIElement": True}))
executable = app / "MacOS/expiry-checks"
command[command.index("-o") + 1] = str(executable)
retention = ROOT / "submodules/telegram-ios/submodules/TelegramCore/Sources/State/RegramMessageRetention.swift"
timers = ROOT / "submodules/telegram-ios/submodules/TelegramCore/Sources/State/ManagedAutoremoveMessageOperations.swift"
row = ROOT / "packages/ChatUI/Sources/ChatUI/ChatRowItem.swift"
helper = declaration(retention.read_text(), "func rgIgnoreMessageExpiry(").replace("transaction: Transaction", "transaction: ExpiryTransaction")
selector = next(line.strip() for line in timers.read_text().splitlines() if "let retentionKey =" in line)
opacity = row.read_text().split("            let showsRevokedMarker =", 1)[1].split("            let dateFormatter =", 1)[0]
opacity = "let showsRevokedMarker =" + opacity.replace("self.regramRevokedOpacity =", "return")
source = args.output / "ExpiryBindings.swift"
source.write_text("import Cocoa\nimport Postbox\nimport TelegramCore\nimport RegramCore\n" + helper + "\nfunc ignoresExpiry(_ message: Message, isRemove: Bool, settings: RegramAccountSettings) -> Bool {\n" + selector + "\nreturn settings[retentionKey].bool\n}\nfunc revokedOpacity(_ message: Message, regramSettings: RegramAccountSettings) -> CGFloat {\n" + opacity + "\n}\n")
command.extend([str(source), str(HERE / "MessageExpiryChecks.swift")])
(args.output / "manifest.json").write_text(json.dumps({"productionSources": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [retention, timers, row]}, "adaptation": "Extract the unchanged expiry mutation and timer/opacity expressions; record Postbox updates with a transaction fixture. Use real TelegramCore message and timeout attributes."}, indent=2))
with (args.output / "compile.log").open("w") as log:
    result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
if result.returncode:
    raise SystemExit(f"Compile failed: {args.output / 'compile.log'}")
with (args.output / "tests.log").open("w") as log:
    result = subprocess.run([str(executable)], cwd=args.output, stdout=log, stderr=subprocess.STDOUT)
print((args.output / "tests.log").read_text()[-2000:])
raise SystemExit(result.returncode)
