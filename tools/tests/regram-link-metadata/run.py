from pathlib import Path
import argparse
import platform
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--products", type=Path, default=ROOT / "packages/RegramCore/.build/release")
    args = parser.parse_args()
    source = (ROOT / "packages/ChatHistoryModel/Sources/ChatHistoryModel/RegramLinkMetadata.swift").read_text()
    start = "    public func refreshIfNeeded(engine: TelegramEngine)"
    end = "    private static func decodeMessages"
    if source.count(start) != 1 or source.count(end) != 1:
        raise RuntimeError("The production refresh boundary changed; update this fixture")
    source = source[:source.index(start)] + source[source.index(end):]
    source = source.replace("import TelegramCore\n", "")
    if source.count("regramSharedDefaults()") != 1:
        raise RuntimeError("Review new cache accesses before running this fixture")
    source = source.replace("regramSharedDefaults()", "fixtureSharedDefaults()")
    with tempfile.TemporaryDirectory(prefix="regram-link-metadata-") as temporary:
        directory = Path(temporary)
        production = directory / "RegramLinkMetadata.swift"
        production.write_text(source)
        binary = directory / "preview-url-checks"
        command = ["xcrun", "swiftc", "-parse-as-library", "-target", platform.machine() + "-apple-macos12.0", "-I", str(args.products), str(args.products / "RegramCore.o"), str(args.products / "SwiftSignalKit.o"), str(production), str(HERE / "PreviewURLChecks.swift"), "-o", str(binary)]
        subprocess.run(command, check=True)
        subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    main()
