import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("/tmp/regram-wallet-biometric-confirmation-20261101"))
    args = parser.parse_args()
    bridge_path = "Telegram-Mac/packages-integration/bridges/WalletUIIntegration.swift"
    prompt_path = "packages/WalletUI/Sources/WalletUI/WalletAuthorizeController.swift"
    bridge = (ROOT / bridge_path).read_text()
    prompt = (ROOT / prompt_path).read_text()
    start = bridge.index("    let authenticateBiometrics:")
    end = bridge.index("    return WalletUIAuthorizationPrompt(verify:", start)
    enum_start = prompt.index("public enum WalletUIPasscodeVerification {")
    enum_end = prompt.index("\n}", enum_start) + 2
    production = prompt[enum_start:enum_end] + "\n\nfunc makeAuthentication(biometrics: Bool, namespace: String, lifetime: Int, session: Atomic<TestSession?>) -> ((@escaping (WalletUIPasscodeVerification) -> Void) -> Void)? {\n" + bridge[start:end] + "    return authenticateBiometrics\n}\n"
    package = args.output / "Package"
    sources = package / "Sources/SwiftSignalKit"
    tests = package / "Tests/WalletBiometricTests"
    package.mkdir(parents=True, exist_ok=True)
    shutil.rmtree(sources, ignore_errors=True)
    shutil.copytree(ROOT / "submodules/telegram-ios/submodules/SSignalKit/SwiftSignalKit/Source", sources)
    tests.mkdir(parents=True, exist_ok=True)
    (package / "Package.swift").write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "WalletBiometricChecks", platforms: [.macOS(.v10_13)], targets: [.target(name: "SwiftSignalKit"), .testTarget(name: "WalletBiometricTests", dependencies: ["SwiftSignalKit"], path: "Tests/WalletBiometricTests")])
''')
    (tests / "Production.swift").write_text("import Foundation\nimport SwiftSignalKit\n\n" + production)
    shutil.copyfile(HERE / "WalletBiometricTests.swift", tests / "WalletBiometricTests.swift")
    manifest = {"configuration": "Release", "conditions": ["STABLE"], "sources": {path: hashlib.sha256((ROOT / path).read_bytes()).hexdigest() for path in [bridge_path, prompt_path]}, "extractedSourceSHA256": hashlib.sha256(production.encode()).hexdigest()}
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return subprocess.run(["swift", "test", "--package-path", str(package), "--scratch-path", str(args.output / "build"), "-c", "release", "-Xswiftc", "-DSTABLE", "-j", "2"], cwd=ROOT).returncode


if __name__ == "__main__":
    raise SystemExit(main())
