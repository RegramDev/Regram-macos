#!/usr/bin/env python3
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location("regram_install", ROOT / "scripts/install-regram-release.py")
INSTALL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INSTALL)
ARCHITECTURES = ("arm64", "x86_64")


def thin_application(app, architecture):
    INSTALL.validate_release_bundle(app)
    count = 0
    for directory, directories, filenames in os.walk(app, followlinks=False):
        directory = Path(directory)
        directories[:] = [name for name in directories if not (directory / name).is_symlink()]
        for name in filenames:
            path = directory / name
            if path.is_symlink() or not path.is_file() or not INSTALL.is_mach_o(path):
                continue
            architectures = subprocess.check_output(["lipo", "-archs", str(path)], text=True).split()
            if architecture not in architectures:
                raise ValueError(f"Missing {architecture} code: {path}")
            if architectures != [architecture]:
                temporary = path.with_name(path.name + ".regram-thin")
                try:
                    subprocess.run(["lipo", str(path), "-thin", architecture, "-output", str(temporary)], check=True)
                    shutil.copymode(path, temporary)
                    os.replace(temporary, path)
                finally:
                    temporary.unlink(missing_ok=True)
            count += 1
    return count


def package_application(source, output, architecture, identity):
    INSTALL.validate_release_bundle(source)
    info = INSTALL.bundle_info(source)
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    filename = f"Regram-{version}-{build}-{architecture}.dmg"
    destination = output / filename
    if destination.exists():
        raise ValueError(f"Package already exists: {destination}")
    with tempfile.TemporaryDirectory(prefix=".Regram-package-", dir=output) as directory:
        directory = Path(directory)
        contents = directory / "contents"
        contents.mkdir()
        app = contents / "Regram.app"
        subprocess.run(["ditto", str(source), str(app)], check=True)
        count = thin_application(app, architecture)
        subprocess.run(["xcrun", "strip", "-S", "-x", str(app / "Contents/MacOS/Regram")], check=True)
        subprocess.run(["python3", str(ROOT / "buildbox/verify-no-labs.py"), str(app)], check=True)
        INSTALL.sign_application(app, identity)
        INSTALL.verify_signed_bundle(app)
        size = sum(path.stat().st_size for path in app.rglob("*") if path.is_file() and not path.is_symlink())
        (contents / "Applications").symlink_to("/Applications", target_is_directory=True)
        temporary_image = directory / filename
        subprocess.run(["hdiutil", "create", "-volname", f"Regram {version} {architecture}", "-srcfolder", str(contents), "-format", "UDZO", "-imagekey", "zlib-level=9", str(temporary_image)], check=True)
        subprocess.run(["hdiutil", "verify", str(temporary_image)], check=True)
        os.replace(temporary_image, destination)
    digest = hashlib.sha256()
    with destination.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return {"filename": filename, "architecture": architecture, "version": version, "build": build, "appBytes": size, "downloadBytes": destination.stat().st_size, "codeFiles": count, "sha256": digest.hexdigest()}


def main():
    parser = argparse.ArgumentParser(description="Build separate Apple Silicon and Intel Regram Release DMGs")
    parser.add_argument("--architecture", action="append", choices=ARCHITECTURES)
    parser.add_argument("--derived-data", type=Path, default=Path.home() / "Library/Caches/RegramReleaseDerivedData")
    parser.add_argument("--output", type=Path, default=Path.home() / "Downloads/Regram")
    parser.add_argument("--source-app", type=Path)
    parser.add_argument("--jobs", type=int, default=4)
    arguments = parser.parse_args()
    architectures = list(dict.fromkeys(arguments.architecture or ARCHITECTURES))
    identity = INSTALL.signing_identity(None)
    derived = arguments.derived_data.expanduser().resolve()
    output = arguments.output.expanduser().resolve()
    output.mkdir(parents=True, exist_ok=True)
    source = arguments.source_app.expanduser().resolve() if arguments.source_app else derived / "Build/Products/Release/Regram.app"
    reports = []
    for architecture in architectures:
        if arguments.source_app is None:
            INSTALL.build_release(derived, architecture, jobs=max(1, arguments.jobs))
        reports.append(package_application(source, output, architecture, identity))
        report = reports[-1]
        (output / (report["filename"] + ".json")).write_text(json.dumps(report, indent=2) + "\n")
        print(f"Created {output / report['filename']}: {report['downloadBytes'] / 1024 / 1024:.1f} MiB", flush=True)
    if arguments.source_app is None:
        INSTALL.remove_build_bundles([source])


if __name__ == "__main__":
    main()
