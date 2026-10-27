import importlib.util
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("regram_packages", ROOT / "scripts/package-regram-release.py")
PACKAGES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PACKAGES)


class ReleasePackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="regram-architecture-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        source = self.root / "fixture.c"
        source.write_text("int main(void) { return 0; }\n")
        self.binaries = {}
        for architecture in PACKAGES.ARCHITECTURES:
            path = self.root / architecture
            subprocess.run(["xcrun", "clang", "-arch", architecture, "-mmacosx-version-min=12.0", str(source), "-o", str(path)], check=True)
            self.binaries[architecture] = path
        self.universal = self.root / "universal"
        subprocess.run(["lipo", "-create", *map(str, self.binaries.values()), "-output", str(self.universal)], check=True)

    def app(self, name):
        app = self.root / name
        (app / "Contents/MacOS").mkdir(parents=True)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "app.regram.macos", "CFBundleExecutable": "Regram", "SOURCE": "STABLE"}))
        shutil.copy2(self.universal, app / "Contents/MacOS/Regram")
        return app

    def test_each_package_contains_only_its_architecture_and_preserves_the_source(self):
        original = self.app("original.app")
        for architecture in PACKAGES.ARCHITECTURES:
            staged = self.root / (architecture + ".app")
            shutil.copytree(original, staged)
            helper = staged / "Contents/Frameworks/Helper.framework/Versions/A/Helper"
            helper.parent.mkdir(parents=True)
            shutil.copy2(self.universal, helper)
            (helper.parents[2] / "Helper").symlink_to("Versions/A/Helper")
            self.assertEqual(PACKAGES.thin_application(staged, architecture), 2)
            for binary in [staged / "Contents/MacOS/Regram", helper]:
                self.assertEqual(subprocess.check_output(["lipo", "-archs", str(binary)], text=True).strip(), architecture)
                self.assertTrue(binary.stat().st_mode & 0o111)
        self.assertEqual(set(subprocess.check_output(["lipo", "-archs", str(original / "Contents/MacOS/Regram")], text=True).split()), set(PACKAGES.ARCHITECTURES))

    def test_missing_architecture_is_rejected(self):
        app = self.app("missing.app")
        shutil.copy2(self.binaries["arm64"], app / "Contents/MacOS/Regram")
        with self.assertRaisesRegex(ValueError, "Missing x86_64"):
            PACKAGES.thin_application(app, "x86_64")

    def test_build_uses_one_architecture_release_stable_and_bounded_jobs(self):
        with mock.patch.object(PACKAGES.INSTALL.subprocess, "run") as run:
            PACKAGES.INSTALL.build_release(self.root / "cache", "x86_64")
        command = run.call_args.args[0]
        self.assertIn("ARCHS=x86_64", command)
        self.assertIn("ONLY_ACTIVE_ARCH=YES", command)
        self.assertIn("SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) STABLE", command)
        self.assertEqual(command[command.index("-configuration") + 1], "Release")
        self.assertEqual(command[command.index("-jobs") + 1], "4")


if __name__ == "__main__":
    unittest.main()
