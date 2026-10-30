import argparse
import hashlib
import json
from pathlib import Path
import shlex
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--native-output", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
command = shlex.split((args.native_output / "compile-command.txt").read_text())
command = [part for part in command if not part.endswith(".swift")]
command[command.index("-module-name") + 1] = "StarsReleaseChecks"
executable = args.output / "stars-release-checks"
command[command.index("-o") + 1] = str(executable)
fixture = HERE / "StarTransactionTabsTests.swift"
production = ROOT / "packages/StarsUI/Sources/StarsUI/StarTransactionTabsRowItem.swift"
glass = ROOT / "packages/TGUIKit/Sources/GlassSegmentView.swift"
bootstrap = ROOT / "packages/ChatUI/Tests/ChatUITests/UITestBootstrap.swift"
adapted = args.output / "StarTransactionTabsTests.swift"
adapted.write_text(fixture.read_text().replace("@testable import StarsUI\n", ""))
main = args.output / "Main.swift"
main.write_text('''import XCTest
import AppKit
@main
struct Main {
    static func main() {
        UITestBootstrap.install()
        NSApp.setActivationPolicy(.prohibited)
        let suite = StarTransactionTabsTests.defaultTestSuite
        suite.run()
        exit(suite.testRun?.hasSucceeded == true ? 0 : 1)
    }
}
''')
developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
frameworks = developer / "Platforms/MacOSX.platform/Developer/Library/Frameworks"
libraries = developer / "Platforms/MacOSX.platform/Developer/usr/lib"
command += [str(production), str(adapted), str(bootstrap), str(main), "-F", str(frameworks), "-L", str(libraries), "-framework", "XCTest", "-Xlinker", "-rpath", "-Xlinker", str(frameworks), "-Xlinker", "-rpath", "-Xlinker", str(libraries)]
(args.output / "manifest.json").write_text(json.dumps({"sources": {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in [production, glass, fixture, bootstrap]}, "adaptation": "Compile the unchanged production row beside upstream tests; remove only the testable import because dependencies are Release objects.", "activationPolicy": "prohibited"}, indent=2))
(args.output / "compile-command.txt").write_text(shlex.join(command))
with (args.output / "compile.log").open("w") as log:
    result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
if result.returncode:
    raise SystemExit(f"Compile failed; see {args.output / 'compile.log'}")
with (args.output / "tests.log").open("w") as log:
    result = subprocess.run([str(executable)], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
for line in (args.output / "tests.log").read_text().splitlines():
    if "passed" in line or "failed" in line or "error:" in line or "Executed " in line:
        print(line)
raise SystemExit(result.returncode)
