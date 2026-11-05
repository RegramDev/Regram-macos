from pathlib import Path
import argparse
import hashlib
import json
import plistlib
import re
import shlex
import subprocess


ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument("--native-output", type=Path, required=True)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
command = shlex.split((args.native_output / "compile-command.txt").read_text())
command = [part for part in command if not part.endswith(".swift")]
command[command.index("-module-name") + 1] = "SearchPeerMenuChecks"
command[command.index("-target") + 1] = "arm64-apple-macos14.0"
bundle = args.output / "SearchPeerMenuChecks.app/Contents"
(bundle / "MacOS").mkdir(parents=True, exist_ok=True)
(bundle / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "local.regram.SearchPeerMenuChecks", "CFBundleExecutable": "menu-checks", "CFBundlePackageType": "APPL", "LSUIElement": True}))
executable = bundle / "MacOS/menu-checks"
command[command.index("-o") + 1] = str(executable)
developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
frameworks = developer / "Platforms/MacOSX.platform/Developer/Library/Frameworks"
libraries = developer / "Platforms/MacOSX.platform/Developer/usr/lib"
command.extend(["-F", str(frameworks), "-L", str(libraries), "-framework", "XCTest", "-Xlinker", "-rpath", "-Xlinker", str(frameworks), "-Xlinker", "-rpath", "-Xlinker", str(libraries)])
production = ROOT / "packages/ChatListUI/Sources/ChatListUI/SearchPeerContextMenu.swift"
tests = ROOT / "packages/ChatListUI/Tests/ChatListUITests/SearchPeerContextMenuTests.swift"
bindings = args.output / "SearchPeerMenuBindings.swift"
bindings.write_text(production.read_text().split("func searchPeerContextMenuItems(", 1)[0])
test_source = args.output / tests.name
test_source.write_text(tests.read_text().replace("@testable import ChatListUI\n", ""))
methods = re.findall(r"    func (test\w+)\(", tests.read_text())
main = args.output / "MenuTestMain.swift"
main.write_text("import XCTest\nimport Darwin\n@main enum MenuTestMain { static func main() {\nlet suite = SearchPeerContextMenuTests.defaultTestSuite\nprecondition(suite.testCaseCount == " + str(len(methods)) + ")\nsuite.run()\nguard let run = suite.testRun else { fatalError(\"Missing test run\") }\nexit(run.hasSucceeded ? 0 : 1)\n} }\n")
support = [tests.parent / name for name in ["UITestBootstrap.swift", "MacEnglishStrings.swift"]]
command.extend(map(str, [bindings, test_source, main] + support))
(args.output / "manifest.json").write_text(json.dumps({"sources": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in [production, tests] + support}, "tests": len(methods), "adaptation": "Compile unchanged menu and folder helpers with the original upstream XCTest cases and bootstrap against the Release modules. Exclude only the account integration function and the testable module import."}, indent=2))
(args.output / "compile-command.txt").write_text(shlex.join(command))
with (args.output / "compile.log").open("w") as log:
    result = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
if result.returncode:
    raise SystemExit(f"Compile failed: {args.output / 'compile.log'}")
with (args.output / "tests.log").open("w") as log:
    result = subprocess.run([str(executable)], cwd=args.output, stdout=log, stderr=subprocess.STDOUT)
print((args.output / "tests.log").read_text()[-3000:])
raise SystemExit(result.returncode)
