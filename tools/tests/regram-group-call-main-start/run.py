from pathlib import Path
import argparse
import hashlib
import platform
import re
import subprocess
import tempfile
import textwrap


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
PRODUCTION = ROOT / "packages/GroupCallScreenUI/Sources/GroupCallScreenUI/GroupCallLaunch.swift"
PRODUCTS = Path.home() / "Library/Caches/RegramReleaseDerivedData-arm64/Build/Products/Release"
MARKER = "__PRODUCTION_FALLBACK_SIGNAL__"


def extract_fallback(source):
    start = "public func getGroupCallPanelData("
    end = "public func requestOrJoinGroupCall("
    if source.count(start) != 1 or source.count(end) != 1:
        raise RuntimeError("Review the changed group-call panel function boundary")
    function = source.split(start, 1)[1].split(end, 1)[0]
    pattern = r"^(?P<indent>[ \t]*)return Signal \{ subscriber in[^\n]*\n.*?^(?P=indent)\}[^\n]*(?:\n[ \t]*\|>[^\n]*)*"
    matches = list(re.finditer(pattern, function, re.MULTILINE | re.DOTALL))
    if len(matches) != 1:
        raise RuntimeError("Review the changed fallback Signal boundary")
    expression = textwrap.dedent(matches[0].group())
    if "cachedGroupCallContexts(context)" not in expression or "callContext.impl.syncWith" not in expression:
        raise RuntimeError("The extracted branch no longer matches the cached-panel fallback")
    return expression


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--products", type=Path, default=PRODUCTS)
    args = parser.parse_args()
    if platform.machine() != "arm64":
        raise RuntimeError("This fixture requires the existing ARM Release SwiftSignalKit products")
    object_file = args.products / "SwiftSignalKit.o"
    architectures = subprocess.check_output(["/usr/bin/lipo", "-archs", str(object_file)], text=True).split()
    if "arm64" not in architectures:
        raise RuntimeError("SwiftSignalKit.o does not contain the ARM architecture")
    expression = extract_fallback(PRODUCTION.read_text())
    fixture = (HERE / "main.swift").read_text()
    if fixture.count(MARKER) != 1:
        raise RuntimeError("The fallback fixture must contain one production insertion point")
    fixture = fixture.replace(MARKER, expression)
    print("Production fallback SHA256: " + hashlib.sha256(expression.encode()).hexdigest(), flush=True)
    with tempfile.TemporaryDirectory(prefix="regram-group-call-main-start-") as temporary:
        directory = Path(temporary)
        source = directory / "main.swift"
        source.write_text(fixture)
        binary = directory / "checks"
        subprocess.run(["xcrun", "swiftc", "-O", "-D", "STABLE", "-target", "arm64-apple-macos12.0", "-I", str(args.products), str(object_file), str(source), "-o", str(binary)], check=True, timeout=30)
        subprocess.run([str(binary)], check=True, timeout=15)


if __name__ == "__main__":
    main()
