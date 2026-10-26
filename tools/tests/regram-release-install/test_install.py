import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("regram_install", ROOT / "scripts/install-regram-release.py")
INSTALL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INSTALL)


class ReleaseInstallTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="regram-install-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def app(self, name, value, source="STABLE", bundle="app.regram.macos"):
        path = self.root / name
        (path / "Contents/MacOS").mkdir(parents=True)
        (path / "Contents/MacOS/Regram").write_text(value)
        (path / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": bundle, "CFBundleExecutable": "Regram", "SOURCE": source
        }))
        return path

    def test_installs_release_and_removes_previous_bundle(self):
        source = self.app("build/Regram.app", "new")
        destination = self.app("Regram.app", "old", source="DEBUG")
        INSTALL.install_application(source, destination, INSTALL.validate_release_bundle)
        self.assertEqual((destination / "Contents/MacOS/Regram").read_text(), "new")
        self.assertEqual(list(self.root.glob(".Regram-install-*")), [])
        self.assertTrue(source.exists())

    def test_restores_previous_application_when_installed_validation_fails(self):
        source = self.app("build/Regram.app", "new")
        destination = self.app("Regram.app", "old", source="DEBUG")

        def verify(path):
            INSTALL.validate_release_bundle(path)
            if path == destination:
                raise ValueError("Invalid installed signature")

        with self.assertRaisesRegex(ValueError, "signature"):
            INSTALL.install_application(source, destination, verify)
        self.assertEqual((destination / "Contents/MacOS/Regram").read_text(), "old")
        self.assertEqual(list(self.root.glob(".Regram-install-*")), [])

    def test_rejects_debug_build_without_replacing_installed_app(self):
        source = self.app("build/Regram.app", "new", source="DEBUG")
        destination = self.app("Regram.app", "old")
        with self.assertRaisesRegex(ValueError, "STABLE"):
            INSTALL.install_application(source, destination, INSTALL.validate_release_bundle)
        self.assertEqual((destination / "Contents/MacOS/Regram").read_text(), "old")

    def test_rejects_debug_library_in_release_bundle(self):
        source = self.app("build/Regram.app", "new")
        (source / "Contents/MacOS/Regram.debug.dylib").touch()
        with self.assertRaisesRegex(ValueError, "Debug library"):
            INSTALL.validate_release_bundle(source)

    def test_does_not_replace_another_application_or_a_symlink(self):
        source = self.app("build/Regram.app", "new")
        destination = self.app("Regram.app", "other", bundle="com.example.other")
        with self.assertRaisesRegex(ValueError, "another application"):
            INSTALL.install_application(source, destination, INSTALL.validate_release_bundle)
        symlink = self.root / "Linked.app"
        symlink.symlink_to(destination)
        with self.assertRaisesRegex(ValueError, "symlink"):
            INSTALL.install_application(source, symlink, INSTALL.validate_release_bundle)
        self.assertEqual((destination / "Contents/MacOS/Regram").read_text(), "other")


if __name__ == "__main__":
    unittest.main()
