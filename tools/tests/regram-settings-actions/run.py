from pathlib import Path
import argparse
import platform
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--core-products", type=Path, default=ROOT / "packages/RegramCore/.build/release")
    parser.add_argument("--signal-products", type=Path, default=ROOT / "packages/RegramCore/.build/debug")
    args = parser.parse_args()
    shared = (ROOT / "tools/tests/regram-network-policy/NetworkEditorChecks.swift").read_text().split("struct RegramDNSResult", 1)[0]
    shared = shared.replace("RegramNetworkEditorChecks.", "RegramBackupActionChecks.")
    shared = shared.replace("enabled: Bool = true, action: (() -> Void)? = nil", "enabled: Bool = true, color: NSColor? = nil, action: (() -> Void)? = nil")
    shared = shared.replace("updateDatas: @escaping ([InputDataIdentifier: InputDataValue]) -> InputDataValidation,", "updateDatas: @escaping ([InputDataIdentifier: InputDataValue]) -> InputDataValidation = { _ in .fail(.none) },")
    production = (ROOT / "packages/RegramUI/Sources/RegramUI/RegramSettingsBackupController.swift").read_text()
    for boundary in ["NSSavePanel()", "NSOpenPanel()", ".encoded().write(to: url, options: .atomic)", "RegramSettingsBackup.read(from: url)"]:
        if production.count(boundary) != 1:
            raise RuntimeError("Update the in-memory boundary for the changed production controller: " + boundary)
    production = "\n".join(line for line in production.splitlines() if not line.startswith("import "))
    production = production.replace("RegramFormController(", "InputDataController(").replace("public func Regram", "func Regram").replace("RegramPreferences.shared", "testPreferences")
    production = production.replace("NSSavePanel()", "FixtureSavePanel()").replace("NSOpenPanel()", "FixtureOpenPanel()")
    production = production.replace(".encoded().write(to: url, options: .atomic)", ".encoded().fixtureWrite(to: url, options: .atomic)").replace("RegramSettingsBackup.read(from: url)", "FixtureFiles.read(url)")
    with tempfile.TemporaryDirectory(prefix="regram-backup-actions-") as directory:
        directory = Path(directory)
        source = directory / "BackupActionChecks.swift"
        source.write_text(shared + "\n" + (HERE / "BackupActionChecks.swift").read_text() + "\n" + production)
        binary = directory / "backup-checks"
        subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-target", platform.machine() + "-apple-macos12.0", "-I", str(args.core_products), "-I", str(args.signal_products), str(args.core_products / "RegramCore.o"), str(args.signal_products / "SwiftSignalKit.o"), str(source), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    main()
