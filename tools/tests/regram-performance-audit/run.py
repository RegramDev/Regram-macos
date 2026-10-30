from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--output", type=Path, default=Path("/tmp/regram-performance-audit"))
parser.add_argument("--diagnostics-ref")
args = parser.parse_args()
package = args.output / "Package"
sources = package / "Sources/SwiftSignalKit"
tests = package / "Tests"
sources.parent.mkdir(parents=True, exist_ok=True)
tests.mkdir(parents=True, exist_ok=True)
shutil.copytree(ROOT / "submodules/telegram-ios/submodules/SSignalKit/SwiftSignalKit/Source", sources, dirs_exist_ok=True)
(package / "Package.swift").write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "PerformanceAudit", platforms: [.macOS(.v12)], targets: [.target(name: "SwiftSignalKit"), .testTarget(name: "PerformanceAuditTests", dependencies: ["SwiftSignalKit"], path: "Tests")])
''')
diagnostics_path = ROOT / "packages/RegramUI/Sources/RegramUI/RegramDiagnosticsController.swift"
loader_path = ROOT / "packages/RegramUI/Sources/RegramUI/RegramHistoryImageLoader.swift"
diagnostics = subprocess.check_output(["git", "show", args.diagnostics_ref + ":" + str(diagnostics_path.relative_to(ROOT))], cwd=ROOT, text=True) if args.diagnostics_ref else diagnostics_path.read_text()
start = diagnostics.index("    var visible = false" if "    var visible = false" in diagnostics else "    let timer =")
end = diagnostics.index("    let signal =", start)
lifecycle = diagnostics[start:end].replace("NSApp.isActive", "active").replace("timeout: 1,", "timeout: 0.01,")
bindings = "\n".join(line for line in diagnostics.splitlines() if "controller.didAppear =" in line or "controller.willDisappear =" in line or "controller.onDeinit =" in line)
fixture = (HERE / "PerformanceAuditTests.swift").read_text().replace("__LIFECYCLE__", lifecycle).replace("__BINDINGS__", bindings)
(tests / "PerformanceAuditTests.swift").write_text(fixture)
shutil.copyfile(loader_path, tests / loader_path.name)
(args.output / "manifest.json").write_text(json.dumps({"diagnosticsRef": args.diagnostics_ref, "diagnosticsHash": hashlib.sha256(diagnostics.encode()).hexdigest(), "imageLoaderHash": hashlib.sha256(loader_path.read_bytes()).hexdigest()}, indent=2) + "\n")
log_path = args.output / "tests.log"
with log_path.open("w") as log:
    result = subprocess.run(["swift", "test", "--package-path", str(package), "--scratch-path", str(args.output / "build"), "-c", "release", "--jobs", "2", "-Xswiftc", "-DSTABLE"], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
for line in log_path.read_text().splitlines():
    if "error:" in line or " passed " in line or " failed " in line or "Executed " in line:
        print(line[:500])
print("Full log:", log_path)
raise SystemExit(result.returncode)
