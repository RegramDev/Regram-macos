from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import re
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
parser.add_argument("--native-output", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
parser.add_argument("--parser-source", type=Path, default=ROOT / "packages/ChatUI/Sources/ChatUI/InputPasteboardParser.swift")
options = parser.parse_args()
options.output.mkdir(parents=True, exist_ok=True)
clipboard_path = ROOT / "packages/RegramServices/Sources/RegramServices/RegramClipboardImages.swift"
preview_path = ROOT / "packages/PreviewSenderUI/Sources/PreviewSenderUI/PreviewSenderController.swift"
sender_path = ROOT / "packages/ChatHistoryModel/Sources/ChatHistoryModel/SenderController.swift"
production = options.parser_source.read_text().replace("public ", "").replace("any AccountContextProtocol", "ClipboardFixtureContext")
production = production.replace("RegramPreferences.shared", "fixturePreferences")
production = production.replace("chatInteraction:ChatInteraction", "chatInteraction:ClipboardFixtureInteraction")
production = production.replace("Sender.generateMedia", "ClipboardFixtureSender.generateMedia")
production = production.replace("permissionText(from:", "fixturePermissionText(from:").replace("alert(for:", "fixtureAlert(for:")
production = production.replace("showFileLimit(context:", "fixtureFileLimit(context:").replace("fileSizeLimitExceed(context:", "fixtureSizeAllowed(context:")
production = production.replace("info: strings().unknownError", 'info: "Unknown error"').replace("for: mainWindow", "for: fixtureWindow")
generated = options.output / "ProductionClipboard.swift"
clipboard = clipboard_path.read_text().replace("FileManager.default.temporaryDirectory", "fixtureTemporaryDirectory")
production = production.replace("NSTemporaryDirectory()", "fixtureTemporaryDirectory.path + \"/\"")
generated.write_text(clipboard + "\n" + production)
preview = declaration(preview_path.read_text(), "    private func cachedSenderOptions(")
classifier = options.output / "ProductionClipboardClassifier.swift"
classifier.write_text("import Cocoa\nimport Darwin\nimport RegramCore\nimport TelegramTheme\nfinal class ClipboardPreviewClassifier {\n var senderOptionsCache: (key: [String], value: [PreviewOptions])?\n" + preview.replace("private func", "func", 1) + "\n}\n")
webp_guard = re.search(r'else if (mimeType.hasPrefix\("image/webp"\) && .+) \{', sender_path.read_text())[1]
with classifier.open("a") as source:
    source.write("func clipboardWebPUsesDocumentBranch(mimeType: String, path: String) -> Bool { " + webp_guard + " }\n")
fixture = options.output / "ClipboardRoutingChecks.swift"
fixture.write_text((HERE / fixture.name).read_text())
command = [part for part in shlex.split((options.native_output / "compile-command.txt").read_text()) if not part.endswith(".swift")]
command[command.index("-module-name") + 1] = "RegramClipboardRoutingChecks"
bundle = options.output / "ClipboardRoutingChecks.app/Contents"
(bundle / "MacOS").mkdir(parents=True, exist_ok=True)
resources = bundle / "Resources"
resources.mkdir(exist_ok=True)
(bundle / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "local.regram.ClipboardRoutingChecks", "CFBundleExecutable": "clipboard-checks", "CFBundlePackageType": "APPL", "LSUIElement": True}))
shutil.copytree(Path("/Applications/Regram.app/Contents/Resources/RegramCore_RegramCore.bundle"), resources / "RegramCore_RegramCore.bundle", dirs_exist_ok=True)
executable = bundle / "MacOS/clipboard-checks"
command[command.index("-o") + 1] = str(executable)
header = options.output / "ClipboardWebPFixture.h"
header.write_text('#include "' + str(ROOT / "core-xprojects/libwebp/build/libwebp/include/encode.h") + '"\n')
command += ["-import-objc-header", str(header)]
command += [str(generated), str(classifier), str(ROOT / "packages/ChatUI/Tests/ChatUITests/UITestBootstrap.swift"), str(fixture)]
(options.output / "manifest.json").write_text(json.dumps({"productionSources": {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in [options.parser_source, clipboard_path, preview_path, sender_path]}, "fixtureSHA256": hashlib.sha256(fixture.read_bytes()).hexdigest(), "boundaries": "Complete pasteboard parser and clipboard image helper, actual preview cachedSenderOptions and Sender WebP-branch predicate, AppKit pasteboard, ImageIO, Core and SwiftSignalKit. Unique named pasteboards and UserDefaults; temporary paths redirected under the evidence directory. Synthetic account/interaction, permission/size/error and media replacement boundaries. Only capture preview URLs/type; no complete Sender, real ChatInteraction, account, Keychain, HTTP, general pasteboard or send callbacks."}, indent=2) + "\n")
(options.output / "compile-command.txt").write_text(shlex.join(command))
with (options.output / "compile.log").open("w") as log:
    result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, cwd=ROOT)
if result.returncode:
    raise SystemExit("Compile failed: " + str(options.output / "compile.log"))
result = subprocess.run([str(executable), str(options.output)], cwd=options.output, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=90)
(options.output / "checks.log").write_text(result.stdout)
print("\n".join(line for line in result.stdout.splitlines() if line.startswith(("FAIL ", "Clipboard routing checks:")))[-4000:])
raise SystemExit(result.returncode)
