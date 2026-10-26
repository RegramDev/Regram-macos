import importlib.util
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("regram_install", ROOT / "scripts/install-regram-release.py")
INSTALL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(INSTALL)


class ReleaseInstallTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="regram-install-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()

    def app(self, name, value, source="STABLE", bundle="app.regram.macos"):
        path = self.root / name
        (path / "Contents/MacOS").mkdir(parents=True)
        (path / "Contents/MacOS/Regram").write_text(value)
        (path / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": bundle, "CFBundleExecutable": "Regram", "SOURCE": source
        }))
        return path

    def mach_o(self, path, universal=False):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes((b"\xca\xfe\xba\xbe" if universal else b"\xcf\xfa\xed\xfe") + bytes(28))
        return path

    def code_bundle(self, path, executable, identifier):
        (path / "Contents/MacOS").mkdir(parents=True)
        (path / "Contents/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": identifier, "CFBundleExecutable": executable
        }))
        self.mach_o(path / "Contents/MacOS" / executable)
        return path

    def signing_fixture(self, app=None):
        app = app or self.app("build/Regram.app", "main")
        self.mach_o(app / "Contents/MacOS/Regram", universal=True)
        framework = app / "Contents/Frameworks/Sparkle.framework"
        version = framework / "Versions/A"
        (version / "Resources").mkdir(parents=True)
        (version / "Resources/Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "org.sparkle-project.Sparkle", "CFBundleExecutable": "Sparkle"
        }))
        self.mach_o(version / "Sparkle")
        (framework / "Versions/Current").symlink_to("A", target_is_directory=True)
        (framework / "Resources").symlink_to("Versions/Current/Resources", target_is_directory=True)
        (framework / "Sparkle").symlink_to("Versions/Current/Sparkle")
        updater = self.code_bundle(version / "Resources/Autoupdate.app", "Autoupdate", "org.sparkle-project.Sparkle.Autoupdate")
        fileop = self.mach_o(updater / "Contents/MacOS/fileop")
        share = self.code_bundle(app / "Contents/PlugIns/TelegramShare.appex", "TelegramShare", "app.regram.macos.share")
        xpc = self.code_bundle(share / "Contents/XPCServices/Worker.xpc", "Worker", "app.regram.macos.share.worker")
        library = self.mach_o(app / "Contents/Frameworks/Helper.dylib")
        (app / "Contents/Frameworks/Resource.dylib").write_text("not executable code")
        return {"app": app, "framework": framework, "updater": updater, "fileop": fileop, "share": share, "xpc": xpc, "library": library}

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

    def test_signing_targets_include_nested_helpers_without_signing_bundle_executables_twice(self):
        fixture = self.signing_fixture()
        targets = INSTALL.signing_targets(fixture["app"])
        self.assertEqual(set(targets), set(fixture.values()))
        self.assertEqual(len(targets), len(set(targets)))
        self.assertEqual(targets[-1], fixture["app"])
        self.assertLess(targets.index(fixture["fileop"]), targets.index(fixture["updater"]))
        self.assertLess(targets.index(fixture["updater"]), targets.index(fixture["framework"]))
        self.assertLess(targets.index(fixture["xpc"]), targets.index(fixture["share"]))

    def test_each_signing_target_preserves_its_own_entitlements_without_adding_permissions(self):
        fixture = self.signing_fixture()
        app = fixture["app"]
        metadata = {path: path.read_bytes() for path in app.rglob("Info.plist")}
        with mock.patch.object(INSTALL.subprocess, "run") as run:
            INSTALL.sign_application(app, "fixed-identity")
        commands = [call.args[0] for call in run.call_args_list]
        self.assertEqual([Path(command[-1]) for command in commands], INSTALL.signing_targets(app))
        for command in commands:
            self.assertEqual(command[:5], ["codesign", "--force", "--sign", "fixed-identity", "--timestamp=none"])
            preserved = next(value.partition("=")[2] for value in command if value.startswith("--preserve-metadata="))
            self.assertEqual(set(preserved.split(",")), {"entitlements", "flags", "runtime"})
            self.assertNotIn("--entitlements", command)
            self.assertNotIn("--options", command)
            self.assertNotIn("--requirements", command)
            self.assertNotIn("--deep", command)
        self.assertEqual(metadata, {path: path.read_bytes() for path in metadata})

    def test_signing_does_not_follow_code_symlinks_outside_the_application(self):
        fixture = self.signing_fixture()
        external = self.mach_o(self.root / "outside-helper")
        alias = fixture["app"] / "Contents/MacOS/ExternalHelper"
        alias.symlink_to(external)
        targets = INSTALL.signing_targets(fixture["app"])
        self.assertNotIn(alias, targets)
        self.assertNotIn(external, targets)

    def test_invalid_nested_bundle_fails_before_any_signing(self):
        fixture = self.signing_fixture()
        broken = fixture["app"] / "Contents/Helpers/Broken.app/Contents"
        broken.mkdir(parents=True)
        (broken / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "Missing"}))
        with mock.patch.object(INSTALL.subprocess, "run") as run:
            with self.assertRaisesRegex(ValueError, "Missing code bundle executable"):
                INSTALL.sign_application(fixture["app"], "fixed-identity")
        run.assert_not_called()

    def test_nested_signing_failure_does_not_sign_the_outer_application(self):
        fixture = self.signing_fixture()
        with mock.patch.object(INSTALL.subprocess, "run", side_effect=INSTALL.subprocess.CalledProcessError(1, "codesign")) as run:
            with self.assertRaises(INSTALL.subprocess.CalledProcessError):
                INSTALL.sign_application(fixture["app"], "fixed-identity")
        self.assertEqual(run.call_count, 1)
        self.assertNotEqual(Path(run.call_args.args[0][-1]), fixture["app"])

    def test_skip_build_signs_existing_universal_app_without_rebuilding_or_thinning(self):
        derived = self.root / "UniversalDerivedData"
        app = self.app("UniversalDerivedData/Build/Products/Release/Regram.app", "main")
        fixture = self.signing_fixture(app)
        executable = app / "Contents/MacOS/Regram"
        original = executable.read_bytes()
        settings = self.root / "Signing.local.json"
        with mock.patch("sys.argv", ["install-regram-release.py", "--skip-build", "--derived-data", str(derived)]), \
             mock.patch.object(INSTALL, "SIGNING_SETTINGS", settings), \
             mock.patch.object(INSTALL, "signing_identity", return_value="fixed-identity"), \
             mock.patch.object(INSTALL, "stop_running_regram"), \
             mock.patch.object(INSTALL, "install_application") as install, \
             mock.patch.object(INSTALL, "remove_build_bundles"), \
             mock.patch.object(INSTALL.subprocess, "run") as run, \
             mock.patch("builtins.print"):
            INSTALL.main()
        commands = [call.args[0] for call in run.call_args_list]
        self.assertFalse(any(command[0] in {"xcodebuild", "lipo"} for command in commands))
        self.assertFalse(any("-thin" in command for command in commands))
        self.assertEqual(executable.read_bytes(), original)
        signing = [command for command in commands if command[0] == "codesign" and "--sign" in command]
        self.assertEqual([Path(command[-1]) for command in signing], INSTALL.signing_targets(fixture["app"]))
        self.assertIn(["codesign", "--verify", "--deep", "--strict", str(app)], commands)
        install.assert_called_once_with(app)


if __name__ == "__main__":
    unittest.main()
