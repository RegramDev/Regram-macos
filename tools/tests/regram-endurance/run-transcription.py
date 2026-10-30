from pathlib import Path
import argparse
import hashlib
import json
import platform
import subprocess

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def declaration(source, anchor):
    start = source.index(anchor)
    cursor = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[cursor] == "{") - (source[cursor] == "}")
        cursor += 1
    return source[start:cursor]


parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path, default=ROOT / "packages/ChatUI/Sources/ChatUI/RegramTranscription.swift")
parser.add_argument("--products", type=Path, default=ROOT / "packages/RegramCore/.build/release")
parser.add_argument("--output", type=Path, default=Path("/tmp/regram-transcription-retention"))
parser.add_argument("--cycles", type=int, default=300)
args = parser.parse_args()
if not 1 <= args.cycles <= 10000:
    parser.error("cycles must be between 1 and 10000")
args.output.mkdir(parents=True, exist_ok=True)
paths = [args.source, ROOT / "packages/RegramServices/Sources/RegramServices/RegramTranscriptionTasks.swift", ROOT / "packages/RegramServices/Sources/RegramServices/RegramTaskSupport.swift", ROOT / "packages/RegramServices/Sources/RegramServices/RGOpenAITranscriptionProvider.swift", ROOT / "packages/RegramCore/Sources/RegramCore/MessageBookmarks.swift"]
sources = [path.read_text() for path in paths]
entry, tasks, support, provider, bookmarks = sources
parts = [declaration(entry, "func regramTranscriptionTaskKey("), declaration(entry, "func regramTranscribeMessage("), tasks.replace("import RegramCore\n", ""), declaration(support, "public struct RegramTaskToken:"), declaration(provider, "public enum RGTranscriptionError:"), declaration(bookmarks, "public struct RGBookmarkMessageId:")]
generated = args.output / "TranscriptionChecks.swift"
generated.write_text((HERE / "TranscriptionChecks.swift").read_text() + "\n" + "\n\n".join(parts))
binary = args.output / "transcription-checks"
command = ["xcrun", "swiftc", "-O", "-D", "STABLE", "-parse-as-library", "-target", platform.machine() + "-apple-macos12.0", "-I", str(args.products), str(args.products / "SwiftSignalKit.o"), str(generated), "-o", str(binary)]
manifest = {str(path): hashlib.sha256(source.encode()).hexdigest() for path, source in zip(paths, sources)}
manifest["boundaries"] = "Unchanged production entry functions, task manager and task value types with actual SwiftSignalKit; synthetic Message/Account/Postbox, memory-only settings and recognition; no real account, disk messages, credentials or network"
(args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
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
