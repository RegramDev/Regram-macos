from pathlib import Path
import argparse
import hashlib
import json
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path, default=ROOT / "packages/RegramServices/Sources/RegramServices/RGLLMTranslate.swift")
parser.add_argument("--products", type=Path, default=ROOT / "packages/RegramCore/.build/release")
parser.add_argument("--output", type=Path, default=Path("/tmp/regram-limiter-endurance"))
parser.add_argument("--cycles", type=int, default=20)
args = parser.parse_args()
if not 1 <= args.cycles <= 10000:
    parser.error("cycles must be between 1 and 10000")
args.output.mkdir(parents=True, exist_ok=True)
source = args.source.read_text()
start = source.index("private final class RGTranslationRequestLimiter {")
end = source.index("private let rgLLMRequestLimiter", start)
implementation = source[start:end]
generated = args.output / "LimiterChecks.swift"
generated.write_text((HERE / "LimiterChecks.swift").read_text() + "\n" + implementation)
binary = args.output / "limiter-checks"
command = ["xcrun", "swiftc", "-O", "-D", "STABLE", "-parse-as-library", "-target", platform.machine() + "-apple-macos12.0", "-I", str(args.products), str(args.products / "SwiftSignalKit.o"), str(generated), "-o", str(binary)]
(args.output / "manifest.json").write_text(json.dumps({"productionSource": str(args.source), "sha256": hashlib.sha256(source.encode()).hexdigest(), "boundaries": "Unchanged production limiter class, actual SwiftSignalKit; reflection reads its queue and counters, providers are controlled Signals; no network, account or credentials"}, indent=2) + "\n")
with (args.output / "compile.log").open("w") as log:
    result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
if result.returncode:
    raise SystemExit("Compile failed: " + str(args.output / "compile.log"))
result = subprocess.run([str(binary), str(args.cycles)], text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
(args.output / "checks.log").write_text(result.stdout)
if result.returncode == 0:
    (args.output / "report.json").write_text(result.stdout)
print(result.stdout[-5000:])
raise SystemExit(result.returncode)
