from pathlib import Path
import argparse
import hashlib
import json
import platform
import re
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
parser.add_argument("--products", type=Path, default=ROOT / "packages/RegramCore/.build/release")
parser.add_argument("--output", type=Path, default=Path("/tmp/regram-composer-combinations"))
parser.add_argument("--controller-source", type=Path, default=ROOT / "packages/ChatUI/Sources/ChatUI/ChatController.swift")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
source = args.controller_source.read_text()
preference_path = ROOT / "packages/ChatUI/Sources/ChatUI/RegramComposerPreferences.swift"
signal_path = ROOT / "packages/RegramCore/Sources/RegramSignals/RegramSignals.swift"
preference = preference_path.read_text()
signal = declaration(signal_path.read_text(), "public func regramPreferenceChanges(").replace("regramPreferenceChanges", "fixturePreferenceChanges").replace("RegramPreferences.shared", "fixturePreferences")
start = "        let composerPreferences = regramPreferenceChanges("
bindings = source[source.index(start):source.index("        let peerPresentationPreferences", source.index(start))] if start in source else ""
bindings = bindings.replace("regramPreferenceChanges", "fixturePreferenceChanges").replace("RegramPreferences.shared", "fixturePreferences")
cancel_marker = "    private func cancelRegramComposerQueries("
cancel = declaration(source, cancel_marker) if cancel_marker in source else "private func cancelRegramComposerQueries(_ changes: RegramComposerRefresh) {}"
input_change = re.search(r"let inputChanged = (.+)", source)
if input_change:
    input_change = input_change[1]
else:
    input_change = re.search(r"if (input != oldValue\.effectiveInput .+) \{", source)[1]
context_guard = re.search(r"if (inputChanged \|\| composerRefresh\.contains\(\.context\)) \{", source)
preview_guard = re.search(r"if (inputChanged \|\| composerRefresh\.contains\(\.preview\)) \{", source)
context_owner = re.search(r"if let strongSelf = self, let queryRequest, (.+) \{", source)
preview_owner = re.search(r"if let strongSelf = self, let previewRequest, (.+) \{", source)
outer_guard = "self.urlPreviewDetectionToken == detectionToken" if "self.urlPreviewDetectionToken == detectionToken" in source else "true"
parts = {"__BINDINGS__": bindings, "__CANCEL__": cancel, "__INPUT_CHANGE__": input_change, "__CONTEXT_GUARD__": context_guard[1] if context_guard else "inputChanged", "__PREVIEW_GUARD__": preview_guard[1] if preview_guard else "inputChanged", "__CONTEXT_OWNER__": context_owner[1].replace("strongSelf.", "self.") if context_owner else "true", "__PREVIEW_OWNER__": preview_owner[1].replace("strongSelf.", "self.") if preview_owner else "true", "__DETECTION_GUARD__": outer_guard}
fixture = (HERE / "ComposerBindingChecks.swift").read_text()
for marker, value in parts.items():
    fixture = fixture.replace(marker, value)
generated = args.output / "ComposerBindingChecks.swift"
generated.write_text(fixture + "\n" + signal + "\n" + preference)
binary = args.output / "composer-binding-checks"
command = ["xcrun", "swiftc", "-O", "-D", "STABLE", "-parse-as-library", "-target", platform.machine() + "-apple-macos12.0", "-I", str(args.products), str(args.products / "RegramCore.o"), str(args.products / "SwiftSignalKit.o"), str(generated), "-o", str(binary)]
(args.output / "manifest.json").write_text(json.dumps({"productionSources": {str(args.controller_source): hashlib.sha256(source.encode()).hexdigest(), str(preference_path): hashlib.sha256(preference.encode()).hexdigest(), str(signal_path): hashlib.sha256(signal_path.read_bytes()).hexdigest()}, "hasScopedBinding": bool(bindings), "boundaries": "Actual controller scoped subscription and cancellation method, query activation/ownership/token expressions, actual preference state helper and SwiftSignalKit/Core. Synthetic query providers/draft/context; preference singleton redirected to unique test suite. Before controller omits absent binding and uses its actual input-only guard. No complete ChatController, account, network or message send."}, indent=2) + "\n")
with (args.output / "compile.log").open("w") as log:
    result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
if result.returncode:
    raise SystemExit("Compile failed: " + str(args.output / "compile.log"))
result = subprocess.run([str(binary)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=20)
(args.output / "checks.log").write_text(result.stdout)
print(result.stdout[-4000:])
if result.returncode == 0:
    (args.output / "report.json").write_text(result.stdout)
raise SystemExit(result.returncode)
