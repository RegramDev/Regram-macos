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
UI = ROOT / "packages/RegramUI/Sources/RegramUI"


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
parser.add_argument("--source-directory", type=Path, default=UI)
options = parser.parse_args()
options.output.mkdir(parents=True, exist_ok=True)
names = ["RegramMessageMediaEditors.swift", "RegramInlineRulesController.swift", "RegramContextMenuController.swift", "RegramAppearancePages.swift", "RegramMessageMediaSettingsController.swift", "RegramSettingsController.swift", "RegramShowroomController.swift"]
paths = [options.source_directory / name for name in names]
parts = []
for path in paths:
    source = path.read_text()
    if path.name == "RegramSettingsController.swift":
        source = "import Localization\n" + declaration(source, "private func regramComposedSettingsController(").replace("private func ", "func ", 1)
    if path.name == "RegramShowroomController.swift":
        source = source.replace('lookupCountryIdByNumber(number, configuration: PhoneNumberUtilsHooks.shared.currentCountriesConfiguration(context).with { $0 })?.1.code ?? ""', '""')
        source = source.replace("RGLocalGiftsStore.shared", "fixtureGiftStore").replace("regramLocalGiftsAccount(context: context)", "fixtureGiftAccount")
        source = source.replace("regramLocalGiftsState(context: context)", "regramLocalGiftsChanges(account: fixtureGiftAccount, store: fixtureGiftStore)")
        source = source.replace("alert(for: context.window, info: ", "fixtureAlert(info: ")
    source = source.replace("public func ", "func ").replace("any AccountContextProtocol", "ToggleFixtureContext")
    source = source.replace("RegramPreferences.shared", "fixturePreferences").replace("RegramMessageMenuInventory.shared", "fixtureInventory")
    source = source.replace("RegramLinkMetadata.shared", "fixtureMetadata").replace("regramPreferenceChanges(", "fixturePreferenceChanges(")
    parts.append(source)
signal_path = ROOT / "packages/RegramCore/Sources/RegramSignals/RegramSignals.swift"
signal = declaration(signal_path.read_text(), "public func regramPreferenceChanges(")
signal = signal.replace("public func regramPreferenceChanges", "func fixturePreferenceChanges").replace("RegramPreferences.shared", "fixturePreferences")
generated = options.output / "ProductionToggleControllers.swift"
generated.write_text("\n".join(parts) + "\n" + signal)
fixture = options.output / "ToggleCombinationChecks.swift"
fixture.write_text((HERE / fixture.name).read_text())
command = [part for part in shlex.split((options.native_output / "compile-command.txt").read_text()) if not part.endswith(".swift")]
command[command.index("-module-name") + 1] = "RegramToggleCombinationChecks"
bundle = options.output / "ToggleCombinationChecks.app/Contents"
(bundle / "MacOS").mkdir(parents=True, exist_ok=True)
resources = bundle / "Resources"
resources.mkdir(exist_ok=True)
(bundle / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "local.regram.ToggleCombinationChecks", "CFBundleExecutable": "toggle-checks", "CFBundlePackageType": "APPL", "LSUIElement": True}))
shutil.copytree(Path("/Applications/Regram.app/Contents/Resources/RegramCore_RegramCore.bundle"), resources / "RegramCore_RegramCore.bundle", dirs_exist_ok=True)
executable = bundle / "MacOS/toggle-checks"
command[command.index("-o") + 1] = str(executable)
native = ["RegramNativeForm.swift", "RegramNativeRows.swift", "RegramNativeInput.swift", "RegramEmptyRow.swift", "RegramPageBuilder.swift", "RegramSelectionRows.swift"]
bootstrap = ROOT / "packages/ChatUI/Tests/ChatUITests/UITestBootstrap.swift"
command += list(map(str, [UI / name for name in native])) + [str(generated), str(bootstrap), str(fixture)]
manifest = {"productionSources": {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths + [UI / name for name in native] + [signal_path]}, "fixtureSHA256": hashlib.sha256(fixture.read_bytes()).hexdigest(), "boundaries": "Complete link preview, inline bot, context menu, appearance, message/media and showroom controllers, composed-controller declaration, real native form/rows, SSignalKit and Core. Account context/navigation, folder stream, metadata refresh and non-888 phone country lookup are inert fixtures. Preferences, local showroom and menu inventory use a unique UserDefaults suite. Local showroom signal is the real RegramSignals implementation with an explicit isolated store; alerts are assertions. Only hidden own windows and native control actions; no live account, network, credentials or send callbacks."}
(options.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
(options.output / "compile-command.txt").write_text(shlex.join(command))
with (options.output / "compile.log").open("w") as log:
    result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, cwd=ROOT)
if result.returncode:
    raise SystemExit("Compile failed: " + str(options.output / "compile.log"))
result = subprocess.run([str(executable), str(options.output)], cwd=options.output, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=180)
(options.output / "checks.log").write_text(result.stdout)
print(result.stdout[-4000:])
raise SystemExit(result.returncode)
