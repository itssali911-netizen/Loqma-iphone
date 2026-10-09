"""Synthetic profiles only. No real Apple certificates, device IDs or secrets."""
import base64
import hashlib
import os
import plistlib
import sys
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / "Scripts"
sys.path.insert(0, str(SCRIPTS))
from signing import BuildError, decode_secret, select_identity, validate_profile
from build_ios import installed_signing, public_environment, require_mac

TEAM = "A1B2C3D4E5"
BUNDLE = "app.example.luqma"
NOW = datetime.now(timezone.utc)
CERTIFICATE = b"synthetic-test-certificate-not-a-real-DER-certificate"
FINGERPRINT = hashlib.sha1(CERTIFICATE).hexdigest().upper()
UUID = "A1234567-B123-C123-D123-E12345678901"


def profile_data(mode="ad-hoc"):
    data = {
        "UUID": UUID, "TeamIdentifier": [TEAM], "Platform": ["iOS"],
        "ApplicationIdentifierPrefix": [TEAM],
        "ExpirationDate": (NOW + timedelta(days=200)).replace(tzinfo=None),
        "DeveloperCertificates": [CERTIFICATE],
        "Entitlements": {"application-identifier": TEAM + "." + BUNDLE,
                         "com.apple.developer.team-identifier": TEAM,
                         "com.apple.developer.healthkit": True, "get-task-allow": False},
    }
    if mode == "ad-hoc":
        data["ProvisionedDevices"] = ["synthetic-test-device"]
    return data


def validated(data=None, mode="ad-hoc"):
    return validate_profile(plistlib.dumps(data or profile_data(mode)), TEAM, BUNDLE, mode, NOW)


class SigningTests(unittest.TestCase):
    def test_ad_hoc_export_keeps_health_and_uses_registered_devices(self):
        profile = validated()
        self.assertEqual(profile.method, "release-testing")
        self.assertEqual(profile.device_count, 1)
        options = profile.export_options(FINGERPRINT)
        self.assertEqual(options["provisioningProfiles"], {BUNDLE: UUID})
        self.assertEqual(options["signingCertificate"], FINGERPRINT)
        self.assertEqual(options["destination"], "export")

    def test_app_store_export_is_not_direct_sideload(self):
        profile = validated(mode="app-store")
        self.assertEqual(profile.method, "app-store-connect")
        self.assertEqual(profile.device_count, 0)
        with self.assertRaisesRegex(BuildError, "App Store"):
            validated(profile_data(), mode="app-store")
        with self.assertRaisesRegex(BuildError, "registered"):
            validated(profile_data("app-store"))

    def test_healthkit_missing_team_bundle_platform_and_wildcard_rejected(self):
        changes = [
            ("health", lambda p: p["Entitlements"].pop("com.apple.developer.healthkit")),
            ("team", lambda p: p.update(TeamIdentifier=["WRONGTEAM1"])),
            ("bundle", lambda p: p["Entitlements"].update({"application-identifier": TEAM + ".app.other"})),
            ("wildcard", lambda p: p["Entitlements"].update({"application-identifier": TEAM + ".*"})),
            ("platform", lambda p: p.update(Platform=["OSX"])),
            ("entitlement-team", lambda p: p["Entitlements"].update({"com.apple.developer.team-identifier": "WRONGTEAM1"})),
        ]
        for name, modify in changes:
            with self.subTest(name=name):
                data = profile_data()
                modify(data)
                with self.assertRaises(BuildError):
                    validated(data)

    def test_legacy_app_prefix_can_differ_from_team(self):
        data = profile_data()
        data["ApplicationIdentifierPrefix"] = ["OLDPREFIX1"]
        data["Entitlements"]["application-identifier"] = "OLDPREFIX1." + BUNDLE
        self.assertEqual(validated(data).team, TEAM)

    def test_expired_development_enterprise_and_invalid_uuid_rejected(self):
        changes = [
            lambda p: p.update(ExpirationDate=NOW.replace(tzinfo=None)),
            lambda p: p["Entitlements"].update({"get-task-allow": True}),
            lambda p: p.update(ProvisionsAllDevices=True),
            lambda p: p.update(UUID="../../profile"),
            lambda p: p.update(DeveloperCertificates=[]),
        ]
        for modify in changes:
            data = profile_data()
            modify(data)
            with self.assertRaises(BuildError):
                validated(data)

    def test_identity_must_include_matching_private_key_and_distribution_certificate(self):
        output = f'  1) {FINGERPRINT} "Apple Distribution: Example ({TEAM})"\n  1 valid identities found\n'
        self.assertEqual(select_identity(output, validated()), FINGERPRINT)
        for invalid in ("0 valid identities found", output.replace(FINGERPRINT, "F" * 40),
                        output.replace("Apple Distribution:", "Apple Development:")):
            with self.assertRaises(BuildError):
                select_identity(invalid, validated())

    def test_strict_base64_private_permissions_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "certificate.p12"
            decode_secret("\n " + base64.b64encode(CERTIFICATE).decode() + "\n", path)
            self.assertEqual(path.read_bytes(), CERTIFICATE)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                decode_secret(base64.b64encode(CERTIFICATE).decode(), path)
            for invalid in ("not-base64!", ""):
                with self.assertRaises(BuildError):
                    decode_secret(invalid, Path(directory) / "bad")

    def test_secrets_not_in_build_process_environment(self):
        with patch.dict(os.environ, {"BUILD_CERTIFICATE_BASE64": "private", "P12_PASSWORD": "private",
                                     "BUILD_PROVISION_PROFILE_BASE64": "private", "BUNDLE_ID": BUNDLE}):
            environment = public_environment()
        self.assertNotIn("P12_PASSWORD", environment)
        self.assertNotIn("BUILD_CERTIFICATE_BASE64", environment)
        self.assertNotIn("BUILD_PROVISION_PROFILE_BASE64", environment)
        self.assertEqual(environment["BUNDLE_ID"], BUNDLE)

    def test_linux_cannot_claim_to_compile_ios(self):
        with patch("build_ios.platform.system", return_value="Linux"):
            with self.assertRaisesRegex(BuildError, "macOS"):
                require_mac()

    def test_signing_cleanup_runs_after_build_failure_and_restores_existing_profiles(self):
        calls = []
        data = plistlib.dumps(profile_data())
        def private(arguments, label):
            calls.append(arguments)
            if "cms" in arguments:
                return data
            if "list-keychains" in arguments and "-s" not in arguments:
                return b'"/original/login.keychain-db"\n'
            if "find-identity" in arguments:
                return f'1) {FINGERPRINT} "Apple Distribution: Example ({TEAM})"'.encode()
            return b""
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            original = home / "Library/MobileDevice/Provisioning Profiles" / (UUID + ".mobileprovision")
            original.parent.mkdir(parents=True)
            original.write_bytes(b"existing-user-profile")
            original.chmod(0o640)
            env = {"BUILD_CERTIFICATE_BASE64": base64.b64encode(CERTIFICATE).decode(), "P12_PASSWORD": "",
                   "BUILD_PROVISION_PROFILE_BASE64": base64.b64encode(b"synthetic-CMS").decode()}
            with patch.dict(os.environ, env), patch("build_ios.Path.home", return_value=home), \
                    patch("build_ios.private_command", side_effect=private), \
                    patch("build_ios.subprocess.run") as run:
                run.return_value.returncode = 0
                with self.assertRaisesRegex(RuntimeError, "forced build failure"):
                    with installed_signing("ad-hoc", TEAM, BUNDLE):
                        self.assertEqual(original.read_bytes(), b"synthetic-CMS")
                        raise RuntimeError("forced build failure")
                cleanup = [call.args[0] for call in run.call_args_list]
            self.assertEqual(original.read_bytes(), b"existing-user-profile")
            self.assertEqual(original.stat().st_mode & 0o777, 0o640)
            self.assertFalse((home / "Library/Developer/Xcode/UserData/Provisioning Profiles" / (UUID + ".mobileprovision")).exists())
            self.assertTrue(any("delete-keychain" in call for call in cleanup))
            self.assertIn(["security", "list-keychains", "-d", "user", "-s", "/original/login.keychain-db"], cleanup)


if __name__ == "__main__":
    unittest.main()
