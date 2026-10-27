from pathlib import Path
import argparse
import platform
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
MTP = ROOT / "submodules/telegram-ios/submodules/MtProtoKit"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--core-products", type=Path, default=ROOT / "packages/RegramCore/.build/release")
    parser.add_argument("--signal-products", type=Path, default=ROOT / "packages/RegramCore/.build/debug")
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="regram-network-checks-") as directory:
        directory = Path(directory)
        source = (HERE / "NetworkEditorChecks.swift").read_text()
        paths = [ROOT / "packages/RegramUI/Sources/RegramUI/RegramNetworkPolicyController.swift", ROOT / "packages/RegramUI/Sources/RegramUI/RegramDNSController.swift", ROOT / "submodules/telegram-ios/submodules/TelegramCore/Sources/Network/RegramNetworkPolicyBinding.swift"]
        for path in paths:
            source += "\n" + "\n".join(line for line in path.read_text().splitlines() if not line.startswith("import ")).replace("RegramPreferences.shared", "testPreferences").replace("public func Regram", "func Regram")
        swift = directory / "NetworkEditorChecks.swift"
        swift.write_text(source)
        binary = directory / "editor-checks"
        subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-target", platform.machine() + "-apple-macos12.0", "-I", str(args.core_products), "-I", str(args.signal_products), str(args.core_products / "RegramCore.o"), str(args.signal_products / "SwiftSignalKit.o"), str(swift), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
        native = directory / "dns-checks"
        sources = ["MTDNS", "MTRGDoHResolver", "MTRGDNSMessage", "MTRGIPPolicy", "MTSignal", "MTSubscriber", "MTDisposable", "MTQueue", "MTTimer", "MTAtomic", "MTBag", "MTLogging"]
        subprocess.run(["xcrun", "clang", "-fobjc-arc", "-fblocks", "-mmacosx-version-min=12.0", "-framework", "Foundation", "-lresolv", "-I", str(MTP / "PublicHeaders"), "-I", str(MTP / "Sources"), "-I", str(ROOT / "submodules/telegram-ios/submodules/EncryptionProvider/PublicHeaders")] + [str(MTP / ("Sources/" + name + ".m")) for name in sources] + [str(HERE / "NativeDNSChecks.m"), "-o", str(native)], check=True)
        subprocess.run([str(native)], check=True)


if __name__ == "__main__":
    main()
