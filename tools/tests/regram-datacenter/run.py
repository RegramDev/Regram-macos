from pathlib import Path
import argparse
import platform
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise RuntimeError("Review the changed fixture boundary: " + old)
    return source.replace(old, new)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--products", type=Path, default=ROOT / "packages/RegramCore/.build/release")
    args = parser.parse_args()
    shared = (ROOT / "tools/tests/regram-network-policy/NetworkEditorChecks.swift").read_text().split("struct EditorPeerId", 1)[0]
    shared = replace_once(shared, "case none, next, loading, switchable(Bool), contextSelector", "case none, next, loading, context(String), switchable(Bool), contextSelector")
    shared = replace_once(shared, '        case .loading: return "loading"\n', '        case .loading: return "loading"\n        case let .context(value): return value\n')
    shared = replace_once(shared, "updateDatas: @escaping ([InputDataIdentifier: InputDataValue]) -> InputDataValidation,", "updateDatas: @escaping ([InputDataIdentifier: InputDataValue]) -> InputDataValidation = { _ in .fail(.none) },")
    production = (ROOT / "packages/RegramUI/Sources/RegramUI/RegramDatacenterController.swift").read_text()
    if production.count("NSPasteboard.general") != 2:
        raise RuntimeError("Review the changed clipboard boundary")
    production = "\n".join(line for line in production.splitlines() if not line.startswith("import "))
    production = replace_once(production, "public func RegramDatacenterController", "func RegramDatacenterController").replace("NSPasteboard.general", "FixturePasteboard.general")
    probe = (ROOT / "submodules/telegram-ios/submodules/TelegramCore/Sources/Network/RegramDatacenterDiagnostics.swift").read_text()
    probe = probe.split("public struct RegramDatacenterProbeSample", 1)[1].split("public extension Network", 1)[0]
    probe = "public struct RegramDatacenterProbeSample" + probe
    with tempfile.TemporaryDirectory(prefix="regram-datacenter-checks-") as temporary:
        directory = Path(temporary)
        source = directory / "DatacenterChecks.swift"
        source.write_text(shared + "\n" + probe + "\n" + (HERE / "DatacenterChecks.swift").read_text() + "\n" + production)
        binary = directory / "datacenter-checks"
        subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-target", platform.machine() + "-apple-macos12.0", "-I", str(args.products), str(args.products / "RegramCore.o"), str(args.products / "SwiftSignalKit.o"), str(source), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    main()
