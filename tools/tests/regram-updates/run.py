from pathlib import Path
import argparse
import platform
import subprocess
import tempfile
import uuid


ROOT = Path(__file__).resolve().parents[3]


def driver_source():
    source = (ROOT / "Telegram-Mac/updater/AppUpdateViewController.swift").read_text()
    sections = [
        ("final class RegramUpdater", "extension SUAppcastItem"),
        ("enum AppUpdateLoadingState", "private func updateString"),
        ("private func changeUpdateSettings", "func updateApplication"),
        ("struct AppUpdateState", "extension String"),
        ("private func updateArchiveMatchesSHA256", "func crashRecoveryUpdater"),
        ("func updateAppIfNeeded", "\n#endif"),
    ]
    selected = []
    for start, end in sections:
        first = source.index(start)
        last = source.index(end, first)
        selected.append(source[first:last])
    source = "\n".join(selected)
    source = source.replace("SUHost(bundle: Bundle.main)", "SUHost(bundle: testHostBundle)")
    source = source.replace("URLSession.shared.dataTask", "releaseTestSession.dataTask")
    source = source.replace("super.downloadUpdate()", "recordDownloadStart(self)")
    source = source.replace("super.extractUpdate()", "recordExtraction(self)")
    source = source.replace('download = SPUDownloaderSession(delegate: self)\n            download?.startPersistentDownload(with: SPUURLRequest(request: URLRequest(url: item.fileURL)), bundleIdentifier: host.bundle.bundleIdentifier!, desiredFilename: "Regram \\(item.versionString ?? "")")', "recordDownloadStart(self)")
    source = source.replace("super.install(withToolAndRelaunch: relaunch, displayingUserInterface: showUI)", "recordInstall(self, relaunch: relaunch, showUI: showUI)")
    if "SPUDownloaderSession(delegate:" in source or "super.install(withToolAndRelaunch:" in source:
        raise RuntimeError("Update the test transfer and installer boundaries after changing the production driver")
    return source


def main():
    parser = argparse.ArgumentParser()
    installed = Path("/Applications/Regram.app/Contents/Frameworks")
    cached = Path.home() / "Library/Caches/RegramReleaseDerivedData/Build/Products/Release"
    parser.add_argument("--products", type=Path, default=installed if installed.is_dir() else cached)
    parser.add_argument("--headers", type=Path, default=cached / "Sparkle.framework/Headers")
    parser.add_argument("--signal-products", type=Path, default=ROOT / "packages/RegramCore/.build/debug")
    args = parser.parse_args()
    framework = args.products / "Sparkle.framework/Sparkle"
    if not framework.is_file():
        raise FileNotFoundError("Pass --products with the Release folder containing Sparkle.framework")
    header = args.headers / "Sparkle.h"
    if not header.is_file():
        raise FileNotFoundError("Pass --headers with the Sparkle Release headers folder")
    if not (args.signal_products / "SwiftSignalKit.o").is_file():
        raise FileNotFoundError("Run swift test --package-path packages/RegramCore first")
    with tempfile.TemporaryDirectory(prefix="regram-update-checks-") as directory:
        directory = Path(directory)
        (directory / "module.modulemap").write_text('module NativeSparkle {\nheader "' + str(header) + '"\nexport *\n}\n')
        common = ["xcrun", "swiftc", "-target", platform.machine() + "-apple-macos12.0", "-I", str(directory), str(framework), "-Xlinker", "-rpath", "-Xlinker", str(args.products), str(ROOT / "packages/RegramCore/Sources/RegramCore/RegramUpdatePolicy.swift")]
        binary = directory / "appcast-checks"
        subprocess.run(common + [str(Path(__file__).with_name("UpdateAppcastChecks.swift")), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)
        source = directory / "UpdateDriverChecks.swift"
        source.write_text(Path(__file__).with_name("UpdateDriverChecks.swift").read_text() + "\n" + driver_source())
        binary = directory / ("driver-checks-" + uuid.uuid4().hex)
        subprocess.run(common + ["-I", str(args.signal_products), str(args.signal_products / "SwiftSignalKit.o"), str(source), "-o", str(binary)], check=True)
        subprocess.run([str(binary)], check=True)


if __name__ == "__main__":
    main()
