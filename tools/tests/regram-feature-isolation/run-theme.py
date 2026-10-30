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
parser.add_argument("--output", type=Path, default=Path("/tmp/regram-theme-switch"))
parser.add_argument("--shared-queue-control", action="store_true")
parser.add_argument("--snapshot-control", action="store_true")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
path = ROOT / "Telegram-Mac/app/AppDelegate.swift"
source = path.read_text()
start = source.index("                let previousBackingScale: Atomic<CGFloat>")
end = source.index("                _ = signal.start(next: { updatedTheme", start)
pipeline = source[start:end].replace("themeSettingsView(accountManager: accountManager)", "updates.get()")
opening = source.index("{ updatedTheme in", end) + len("{ updatedTheme in")
depth, cursor = 1, opening
while depth:
    depth += (source[cursor] == "{") - (source[cursor] == "}")
    cursor += 1
application = source[opening:cursor - 1]
if args.snapshot_control:
    application = application.replace("animated: false", "animated: true")
if args.shared_queue_control:
    pipeline = pipeline.replace('Queue(name: "regram.application-theme", qos: .userInitiated)', "resourcesQueue")
test_source = args.output / "ThemeSwitchChecks.swift"
test_source.write_text((HERE / "ThemeSwitchChecks.swift").read_text().replace("__THEME_PIPELINE__", pipeline).replace("__APPLY_THEME__", application))
(args.output / "manifest.json").write_text(json.dumps({"source": str(path.relative_to(ROOT)), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "sharedQueueControl": args.shared_queue_control, "snapshotControl": args.snapshot_control, "boundaries": "Production theme subscription operators and application closure; fixture settings, renderer, windows and application contexts, actual SwiftSignalKit queues and cancellation"}, indent=2) + "\n")
binary = args.output / "theme-switch-checks"
subprocess.run(["xcrun", "swiftc", "-O", "-D", "STABLE", "-parse-as-library", "-target", platform.machine() + "-apple-macos12.0", "-I", str(args.products), str(args.products / "SwiftSignalKit.o"), str(test_source), "-o", str(binary)], check=True)
result = subprocess.run([str(binary)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=25)
(args.output / "checks.log").write_text(result.stdout)
print(result.stdout[-6000:])
raise SystemExit(result.returncode)
