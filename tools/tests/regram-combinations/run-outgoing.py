from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import shlex
import shutil
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
parser.add_argument("--native-output", type=Path, default=Path("/tmp/regram-native-ui"))
parser.add_argument("--output", type=Path, default=Path("/tmp/regram-outgoing-combinations"))
parser.add_argument("--source", type=Path, default=ROOT / "packages/ChatUI/Sources/ChatUI/RegramOutgoingInput.swift")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
production = args.source.read_text()
spacing = declaration(production, "private func regramPanguInput(")
outgoing = declaration(production, "public func regramOutgoingInput(")
boundary = "    let accountId = context.peerId.toInt64()\n    let settings = RegramPreferences.shared.settings(accountId: accountId)\n"
signature = "public func regramOutgoingInput(_ input: ChatTextInputState, context: any AccountContextProtocol, peerId: PeerId)"
if outgoing.count(boundary) != 1 or outgoing.count(signature) != 1:
    raise RuntimeError("Review the outgoing input account/settings boundary")
outgoing = outgoing.replace(boundary, "").replace(signature, "func combinationOutgoingInput(_ input: ChatTextInputState, settings: RegramAccountSettings, accountId: Int64, peerId: PeerId)")
editing = declaration(production, "public func regramEditingInput(")
editing_signature = "public func regramEditingInput(_ input: ChatTextInputState, context: any AccountContextProtocol)"
editing_boundary = 'RegramPreferences.shared.settings(accountId: context.peerId.toInt64())["features.enablePanguOnEditing"]'
if editing.count(editing_signature) != 1 or editing.count(editing_boundary) != 1:
    raise RuntimeError("Review the editing input settings boundary")
editing = editing.replace(editing_signature, "func combinationEditingInput(_ input: ChatTextInputState, settings: RegramAccountSettings)").replace(editing_boundary, 'settings["features.enablePanguOnEditing"]')
generated = args.output / "ProductionOutgoingInput.swift"
generated.write_text("import Foundation\nimport Postbox\nimport TelegramCore\nimport InputView\nimport RegramCore\n" + spacing + "\n" + outgoing + "\n" + editing)
command = [part for part in shlex.split((args.native_output / "compile-command.txt").read_text()) if not part.endswith(".swift")]
command[command.index("-module-name") + 1] = "RegramOutgoingCombinationChecks"
bundle = args.output / "OutgoingCombinationChecks.app/Contents"
(bundle / "MacOS").mkdir(parents=True, exist_ok=True)
resources = bundle / "Resources"
resources.mkdir(exist_ok=True)
(bundle / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "local.regram.OutgoingCombinationChecks", "CFBundleExecutable": "outgoing-checks", "CFBundlePackageType": "APPL", "LSUIElement": True}))
shutil.copytree(Path("/Applications/Regram.app/Contents/Resources/RegramCore_RegramCore.bundle"), resources / "RegramCore_RegramCore.bundle", dirs_exist_ok=True)
executable = bundle / "MacOS/outgoing-checks"
command[command.index("-o") + 1] = str(executable)
bootstrap = ROOT / "packages/ChatUI/Tests/ChatUITests/UITestBootstrap.swift"
command += [str(generated), str(bootstrap), str(HERE / "OutgoingCombinationChecks.swift")]
(args.output / "manifest.json").write_text(json.dumps({"productionSource": str(args.source), "sha256": hashlib.sha256(production.encode()).hexdigest(), "boundaries": "Unchanged Pangu/input transformation body, actual InputView, TelegramCore, Postbox, RegramCore and AppKit Release objects. Only context/settings read becomes explicit parameters. Test process initializes its own theme. No account, messages, credentials, network or send callbacks."}, indent=2) + "\n")
(args.output / "compile-command.txt").write_text(shlex.join(command))
with (args.output / "compile.log").open("w") as log:
    result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, cwd=ROOT)
if result.returncode:
    raise SystemExit("Compile failed: " + str(args.output / "compile.log"))
result = subprocess.run([str(executable)], cwd=args.output, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=120)
(args.output / "checks.log").write_text(result.stdout)
print(result.stdout[-4000:])
raise SystemExit(result.returncode)
