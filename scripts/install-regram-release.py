#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import tempfile
import time


ROOT = Path(__file__).resolve().parent.parent
BUNDLE_ID = "app.regram.macos"
SIGNING_SETTINGS = ROOT / "Telegram-Mac/Signing.local.json"
DESTINATION = Path("/Applications/Regram.app")


def bundle_info(app):
    with (app / "Contents/Info.plist").open("rb") as source:
        return plistlib.load(source)


def validate_release_bundle(app):
    if app.is_symlink():
        raise ValueError(f"Application bundle must not be a symlink: {app}")
    info = bundle_info(app)
    if info.get("CFBundleIdentifier") != BUNDLE_ID or info.get("SOURCE") != "STABLE":
        raise ValueError(f"Expected a Regram STABLE application: {app}")
    if info.get("CFBundleExecutable") != "Regram" or not (app / "Contents/MacOS/Regram").is_file():
        raise ValueError(f"Missing Regram executable: {app}")
    if list(app.rglob("*.debug.dylib")):
        raise ValueError(f"Debug library found in Release application: {app}")


def verify_signed_bundle(app):
    validate_release_bundle(app)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)


def signing_identity(requested):
    configured = json.loads(SIGNING_SETTINGS.read_text()) if SIGNING_SETTINGS.exists() else {}
    identity = requested or configured.get("identity", "")
    identities = subprocess.check_output(["security", "find-identity", "-v", "-p", "codesigning"], text=True)
    valid = re.findall(r'\) ([A-F0-9]{40}) "', identities)
    if identity not in valid:
        raise ValueError("Configure a fixed signing certificate with --identity <SHA-1 fingerprint>; ad-hoc signing is not supported")
    return identity


def is_mach_o(path):
    with path.open("rb") as source:
        return source.read(4) in {
            b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe",
            b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
            b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
            b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca",
        }


def code_bundle_executable(bundle):
    for info_path in [bundle / "Contents/Info.plist", bundle / "Resources/Info.plist", bundle / "Info.plist"]:
        if not info_path.is_file():
            continue
        info = plistlib.loads(info_path.read_bytes())
        name = info.get("CFBundleExecutable")
        if not name:
            return None
        if not isinstance(name, str) or Path(name).name != name:
            raise ValueError(f"Invalid code bundle executable: {bundle}")
        for candidate in [bundle / "Contents/MacOS" / name, bundle / name]:
            if candidate.is_file():
                executable = candidate.resolve()
                if not executable.is_relative_to(bundle.resolve()):
                    raise ValueError(f"Code bundle executable is outside its bundle: {bundle}")
                return executable
        raise ValueError(f"Missing code bundle executable: {bundle}")
    return None


def signing_targets(app):
    validate_release_bundle(app)
    app = app.resolve()
    bundles = set()
    executables = set()
    bundle_executables = set()
    for directory, directories, filenames in os.walk(app, followlinks=False):
        directory = Path(directory)
        directories[:] = [name for name in directories if not (directory / name).is_symlink()]
        if directory == app or directory.suffix in {".app", ".appex", ".framework", ".xpc", ".bundle"}:
            executable = code_bundle_executable(directory)
            if executable is not None:
                bundle_executables.add(executable)
                if directory != app:
                    bundles.add(directory)
        for name in filenames:
            path = directory / name
            if not path.is_symlink() and path.is_file() and is_mach_o(path):
                executables.add(path)
    nested = bundles | (executables - bundle_executables)
    return sorted(nested, key=lambda path: (-len(path.parts), str(path))) + [app]


def sign_application(app, identity):
    targets = signing_targets(app)
    for target in targets:
        subprocess.run([
            "codesign", "--force", "--sign", identity, "--timestamp=none",
            "--preserve-metadata=entitlements,flags,runtime", str(target)
        ], check=True)


def stop_running_regram():
    candidates = subprocess.run(["pgrep", "-x", "Regram"], capture_output=True, text=True, timeout=3)
    if candidates.returncode == 1:
        return
    candidates.check_returncode()
    pids = [str(int(value)) for value in candidates.stdout.split()]
    if not pids:
        return
    result = subprocess.run(["ps", "-p", ",".join(pids), "-o", "pid=,comm="], capture_output=True, text=True, timeout=3)
    if result.returncode == 1 and not result.stdout.strip():
        return
    result.check_returncode()
    processes = result.stdout
    running = []
    for line in processes.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) != 2 or not parts[1].endswith("/Regram.app/Contents/MacOS/Regram"):
            continue
        app = Path(parts[1]).parents[2]
        if bundle_info(app).get("CFBundleIdentifier") == BUNDLE_ID:
            running.append(int(parts[0]))
    for pid in running:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + 20
    for pid in running:
        while True:
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                break
            if time.monotonic() > deadline:
                raise RuntimeError("Regram did not exit; the installed application has not been replaced")
            time.sleep(0.2)


def install_application(source, destination=DESTINATION, verify=verify_signed_bundle):
    verify(source)
    if destination.is_symlink():
        raise ValueError(f"Installation destination must not be a symlink: {destination}")
    if destination.exists() and bundle_info(destination).get("CFBundleIdentifier") not in [BUNDLE_ID, "dev.regram.desktop"]:
        raise ValueError(f"Installation destination contains another application: {destination}")
    staging = Path(tempfile.mkdtemp(prefix=".Regram-install-", dir=destination.parent))
    staged_app = staging / "Regram.app"
    previous = staging / "previous.app"
    try:
        subprocess.run(["ditto", str(source), str(staged_app)], check=True)
        verify(staged_app)
        if destination.exists():
            os.replace(destination, previous)
        try:
            os.replace(staged_app, destination)
            verify(destination)
        except BaseException:
            if destination.exists():
                shutil.rmtree(destination)
            if previous.exists():
                os.replace(previous, destination)
            raise
        if previous.exists():
            shutil.rmtree(previous)
    finally:
        if not previous.exists():
            shutil.rmtree(staging)


def remove_build_bundles(apps):
    for app in apps:
        if app == DESTINATION or app.is_symlink() or not app.exists():
            continue
        if bundle_info(app).get("CFBundleIdentifier") == BUNDLE_ID:
            shutil.rmtree(app)


def build_release(derived, architecture, jobs=4):
    if architecture not in {"arm64", "x86_64"}:
        raise ValueError(f"Unsupported architecture: {architecture}")
    with tempfile.TemporaryDirectory(prefix="regram-release-build-") as directory:
        configuration = Path(directory) / "Release.xcconfig"
        configuration.write_text("MACOSX_DEPLOYMENT_TARGET = 12.0\nCODE_SIGNING_ALLOWED = NO\n")
        subprocess.run([
            "xcodebuild", "build", "-workspace", str(ROOT / "Telegram-Mac.xcworkspace"),
            "-scheme", "Release", "-configuration", "Release", "-destination", f"platform=macOS,arch={architecture}",
            "-derivedDataPath", str(derived), "-xcconfig", str(configuration), "CODE_SIGNING_ALLOWED=NO",
            "ENABLE_DEBUG_DYLIB=NO", f"ARCHS={architecture}", "ONLY_ACTIVE_ARCH=YES",
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) STABLE", "-jobs", str(jobs)
        ], cwd=ROOT, check=True)


def main():
    parser = argparse.ArgumentParser(description="Build, sign and replace /Applications/Regram.app with Release")
    parser.add_argument("--identity", help="Fixed code-signing certificate SHA-1 fingerprint; saved locally after successful installation")
    parser.add_argument("--derived-data", type=Path, default=Path("/tmp/RegramMacReleaseDerivedData"))
    parser.add_argument("--skip-build", action="store_true", help="Install an existing Release build")
    arguments = parser.parse_args()
    identity = signing_identity(arguments.identity)
    derived = arguments.derived_data.expanduser().resolve()
    app = derived / "Build/Products/Release/Regram.app"
    if not arguments.skip_build:
        build_release(derived, os.uname().machine)
    validate_release_bundle(app)
    subprocess.run(["xcrun", "strip", "-S", "-x", str(app / "Contents/MacOS/Regram")], check=True)
    subprocess.run(["python3", str(ROOT / "buildbox/verify-no-labs.py"), str(app)], check=True)
    sign_application(app, identity)
    verify_signed_bundle(app)
    stop_running_regram()
    install_application(app)
    SIGNING_SETTINGS.write_text(json.dumps({"identity": identity}, indent=2) + "\n")
    remove_build_bundles([app, Path("/tmp/RegramMacDerivedData/Build/Products/Debug/Regram.app")])
    print(f"Installed Release: {DESTINATION}; previous and temporary application bundles removed")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        raise SystemExit(f"error: {error}")
