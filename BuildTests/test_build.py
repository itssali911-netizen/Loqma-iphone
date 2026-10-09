"""Command orchestration tests with mocks; these do not compile Apple's SDK."""
import os
import plistlib
import sys
import tempfile
import unittest
import zipfile
from contextlib import contextmanager
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Scripts"))
from build_ios import build, prepare_sideload
from signing import BuildError
from test_signing import BUNDLE, FINGERPRINT, TEAM, profile_data, validated


class BuildTests(unittest.TestCase):
    def setUp(self):
        # Package checkouts belong to Xcode; orchestration fixtures mock this
        # boundary along with xcodebuild. Real builds verify both source hashes.
        patcher = patch("build_ios.apply_vision_compat")
        self.addCleanup(patcher.stop)
        patcher.start()

    def test_sideload_packages_device_only_without_apple_secrets_or_claiming_signed_install(self):
        calls = []
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "output"
            def run(args, log):
                calls.append(args)
                log.write_text("mock command only\n")
                if "build" in args:
                    app = output / "device-derived/Build/Products/Release-iphoneos/Luqma.app"
                    app.mkdir(parents=True)
                    (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": BUNDLE,
                        "CFBundleSupportedPlatforms": ["iPhoneOS"], "CFBundleExecutable": "Luqma"}))
                    (app / "Luqma").write_bytes(b"synthetic executable, not an iOS binary")
                    (app / "Frameworks/Runtime.framework").mkdir(parents=True)
                if args[0] == "ditto":
                    payload = Path(args[-2])
                    with zipfile.ZipFile(args[-1], "w") as archive:
                        for file in payload.rglob("*"):
                            if file.is_file():
                                archive.write(file, "Payload/" + file.relative_to(payload).as_posix())
            with patch("build_ios.require_mac"), patch("build_ios.run", side_effect=run), \
                    patch.dict(os.environ, {"BUNDLE_ID": BUNDLE, "APPLE_TEAM_ID": "", "BUILD_NUMBER": "2"}), \
                    patch("build_ios.installed_signing") as signing:
                build("sideload", output)
                signing.assert_not_called()
            self.assertTrue((output / "Luqma-Sideload.ipa").is_file())
            self.assertFalse((output / "Luqma.ipa").exists())
            self.assertFalse(any("generic/platform=iOS Simulator" in args for args in calls))
            self.assertTrue(any("CODE_SIGNING_ALLOWED=NO" in args for args in calls))
            signatures = [args for args in calls if args[0] == "codesign" and "--sign" in args]
            self.assertEqual(len(signatures), 2)
            self.assertNotIn("--entitlements", signatures[0])
            self.assertIn("--entitlements", signatures[1])
            self.assertIn('"requires_personal_resigning": true', (output / "build-summary.json").read_text())

    def test_simulator_app_cannot_be_packaged_for_iphone_sideloading(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "Luqma.app"
            app.mkdir()
            (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": BUNDLE,
                "CFBundleSupportedPlatforms": ["iPhoneSimulator"], "CFBundleExecutable": "Luqma"}))
            with self.assertRaisesRegex(BuildError, "simulator"):
                prepare_sideload(app, Path(directory), BUNDLE)

    def test_unsigned_check_builds_both_sdks_without_claiming_an_ipa(self):
        calls = []
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "output"
            def run(args, log):
                calls.append(args)
                log.write_text("mock command only\n")
                if "build" in args and "generic/platform=iOS Simulator" in args:
                    app = output / "simulator-derived/Build/Products/Debug-iphonesimulator/Luqma.app"
                    app.mkdir(parents=True)
                if args[0] == "ditto":
                    (output / "Luqma-Simulator.zip").write_bytes(b"test-placeholder")
            with patch("build_ios.require_mac"), patch("build_ios.run", side_effect=run), \
                    patch.dict(os.environ, {"BUNDLE_ID": "", "BUILD_NUMBER": "1"}), \
                    patch("build_ios.installed_signing") as signing:
                build("check", output)
                signing.assert_not_called()
            sdk = [args for args in calls if args[-1] == "build"]
            self.assertEqual(len(sdk), 2)
            self.assertTrue(all("CODE_SIGNING_ALLOWED=NO" in args for args in sdk))
            self.assertTrue(any("generic/platform=iOS" in args for args in sdk))
            self.assertFalse((output / "Luqma.ipa").exists())
            self.assertIn("cannot install on an iPhone", (output / "READ-ME.txt").read_text())

    def test_failed_sdk_build_stops_without_success_summary(self):
        def run(args, log):
            if args[-1] == "build":
                raise BuildError("SDK failure")
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "failed"
            with patch("build_ios.require_mac"), patch("build_ios.run", side_effect=run), \
                    patch.dict(os.environ, {"BUNDLE_ID": "", "BUILD_NUMBER": "1"}):
                with self.assertRaisesRegex(BuildError, "SDK failure"):
                    build("check", output)
            self.assertFalse((output / "build-summary.json").exists())

    def test_signed_export_checks_embedded_profile_and_never_uploads(self):
        calls = []
        profile = validated()
        @contextmanager
        def signing(*_):
            yield profile, FINGERPRINT, Path("/synthetic/keychain")
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "signed"
            def run(args, log):
                calls.append(args)
                log.write_text("mock command only\n")
                if "-exportArchive" in args:
                    (output / "export").mkdir()
                    with zipfile.ZipFile(output / "export/Luqma.ipa", "w") as ipa:
                        ipa.writestr("Payload/Luqma.app/Info.plist", plistlib.dumps({"CFBundleIdentifier": BUNDLE}))
                        ipa.writestr("Payload/Luqma.app/embedded.mobileprovision", b"synthetic-CMS")
            with patch("build_ios.require_mac"), patch("build_ios.run", side_effect=run), \
                    patch("build_ios.installed_signing", signing), \
                    patch("build_ios.private_command", return_value=plistlib.dumps(profile_data())), \
                    patch.dict(os.environ, {"BUNDLE_ID": BUNDLE, "APPLE_TEAM_ID": TEAM, "BUILD_NUMBER": "12"}):
                build("ad-hoc", output)
            self.assertTrue((output / "Luqma.ipa").is_file())
            self.assertIn('"uploaded": false', (output / "build-summary.json").read_text())
            self.assertTrue(any("archive" in args for args in calls))
            self.assertFalse(any("upload" in args or "-allowProvisioningUpdates" in args for args in calls))

    def test_existing_output_is_not_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            sentinel = output / "keep.txt"
            sentinel.write_text("original")
            with patch("build_ios.require_mac"):
                with self.assertRaisesRegex(BuildError, "already exists"):
                    build("check", output)
            self.assertEqual(sentinel.read_text(), "original")


if __name__ == "__main__":
    unittest.main()
