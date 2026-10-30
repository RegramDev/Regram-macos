from pathlib import Path
import argparse
import hashlib
import json
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--products", type=Path, default=ROOT / "packages/RegramCore/.build/release")
parser.add_argument("--output", type=Path, default=Path("/tmp/regram-feature-isolation"))
parser.add_argument("--uncached-control", action="store_true")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
translation_path = ROOT / "packages/ChatHistoryModel/Sources/ChatHistoryModel/RegramTranslation.swift"
history_path = ROOT / "packages/ChatHistoryModel/Sources/ChatHistoryModel/ChatHistoryEntry.swift"
outgoing_path = ROOT / "packages/RegramServices/Sources/RegramServices/RegramOutgoingTranslation.swift"
translation = translation_path.read_text()
presentation = translation[translation.index("func regramTranslationCacheIdentity("):translation.index("func regramTranslationMatches(")]
boundary = "private lazy var identity = settings.translationIdentity"
if presentation.count(boundary) != 1:
    raise RuntimeError("Review the translation identity instrumentation boundary")
presentation = presentation.replace(boundary, "private lazy var identity = recordTranslationIdentity(settings)")
if args.uncached_control:
    presentation = presentation.replace("private lazy var identity = recordTranslationIdentity(settings)", "private var identity: String { recordTranslationIdentity(settings) }")
history = history_path.read_text()
for expected in ["let regramTranslation = RegramTranslationPresentation(settings: regramSettings, tone: translate?.tone ?? .neutral)", "regramTranslation.matches(message)", "regramTranslation.matches(replyMessage)", "regramTranslation.quickLanguage(message)", "regramTranslation.hidesQuickTranslation(message)"]:
    if history.count(expected) != 1:
        raise RuntimeError("Review the batch presentation integration: " + expected)
for path in [ROOT / "packages/RegramUI/Sources/RegramUI/RegramOutgoingLanguageController.swift", ROOT / "packages/ChatUI/Sources/ChatUI/RegramOutgoingTranslation.swift", ROOT / "packages/ChatUI/Sources/ChatUI/ChatInterfaceInteraction.swift"]:
    for line in path.read_text().splitlines():
        if "RegramOutgoingTranslationPolicy." in line and "_internalGetInt64Value" in line:
            raise RuntimeError("Namespace-less outgoing language call: " + str(path))
language_source = (ROOT / "packages/RegramUI/Sources/RegramUI/RegramOutgoingLanguageController.swift").read_text()
if 'action: { select("off") }' not in language_source:
    raise RuntimeError("Review the outgoing translation off action")
source = args.output / "PresentationChecks.swift"
source.write_text((HERE / "PresentationChecks.swift").read_text() + "\n" + presentation + "\n" + outgoing_path.read_text())
manifest = {"productionSources": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [translation_path, history_path, outgoing_path]}, "uncachedControl": args.uncached_control, "instrumentation": "Count accesses to the production lazy identity initializer; message/attribute boundary is synthetic"}
(args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
binary = args.output / "presentation-checks"
command = ["xcrun", "swiftc", "-O", "-D", "STABLE", "-parse-as-library", "-target", platform.machine() + "-apple-macos12.0", "-I", str(args.products), str(args.products / "RegramCore.o"), str(source), "-o", str(binary)]
subprocess.run(command, check=True)
result = subprocess.run([str(binary)], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
(args.output / "checks.log").write_text(result.stdout)
print(result.stdout[-6000:])
if result.returncode == 0:
    (args.output / "report.json").write_text(result.stdout)
    marker = "    func select(_ language: String)"
    start = language_source.index(marker)
    opening = language_source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (language_source[end] == "{") - (language_source[end] == "}")
        end += 1
    selection = language_source[start:end].replace("RegramPreferences.shared", "testPreferences")
    action_source = args.output / "OutgoingLanguageChecks.swift"
    action_source.write_text((HERE / "OutgoingLanguageChecks.swift").read_text().replace("__SELECT_LANGUAGE__", selection) + "\n" + outgoing_path.read_text())
    action_binary = args.output / "outgoing-language-checks"
    subprocess.run(command[:-3] + [str(action_source), "-o", str(action_binary)], check=True)
    subprocess.run([str(action_binary)], check=True)
raise SystemExit(result.returncode)
