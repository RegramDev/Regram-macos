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
parser.add_argument("--output", type=Path, default=Path("/tmp/regram-bookmark-loading"))
parser.add_argument("--db-projection-control", action="store_true")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
path = ROOT / "packages/RegramUI/Sources/RegramUI/RegramBookmarksController.swift"
source = path.read_text()

def declaration(marker):
    if source.count(marker) != 1:
        raise RuntimeError("Review the bookmark production boundary: " + marker)
    start = source.index(marker)
    opening = source.index("{", start)
    depth, end = 1, opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]

start = source.index("    let accountId =", source.index("public func RegramBookmarksController("))
end = source.index("    let arguments = BookmarkArguments", start)
pipeline = source[start:end].replace("RGMessageBookmarks.shared", "fixtureBookmarks")
if args.db_projection_control:
    boundary = "} |> deliverOn(loadingQueue) |> map { snapshots"
    if pipeline.count(boundary) != 1:
        raise RuntimeError("Review the bookmark projection queue boundary")
    pipeline = pipeline.replace(boundary, "} |> map { snapshots")
fetch = declaration("enum FetchError: Error, Equatable") + "\n" + declaration("let fetch: (BookmarkRow, Bool)")
fetch = fetch.replace("RGMessageBookmarks.shared", "fixtureBookmarks")
lifecycle = "\n".join(declaration(marker) for marker in ["controller.didAppear =", "controller.willDisappear =", "controller.onDeinit ="])
models = source[source.index("private enum BookmarkAvailability"):source.index("private final class BookmarkArguments")].replace("private ", "")
fixture = (HERE / "BookmarkLoadingChecks.swift").read_text().replace("__LOADING_PIPELINE__", pipeline).replace("__FETCH_PIPELINE__", fetch).replace("__LIFECYCLE__", lifecycle)
test_source = args.output / "BookmarkLoadingChecks.swift"
test_source.write_text(models + "\n" + fixture)
(args.output / "manifest.json").write_text(json.dumps({"source": str(path.relative_to(ROOT)), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "dbProjectionControl": args.db_projection_control, "boundaries": "Production loading/fetch/lifecycle closures; fixture context, in-memory bookmarks/DB/engine, preview formatter checks queue ownership"}, indent=2) + "\n")
binary = args.output / "bookmark-loading-checks"
subprocess.run(["xcrun", "swiftc", "-O", "-D", "STABLE", "-parse-as-library", "-target", platform.machine() + "-apple-macos12.0", "-I", str(args.products), str(args.products / "RegramCore.o"), str(args.products / "SwiftSignalKit.o"), str(test_source), "-o", str(binary)], check=True)
result = subprocess.run([str(binary)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=25)
(args.output / "checks.log").write_text(result.stdout)
print(result.stdout[-6000:])
raise SystemExit(result.returncode)
