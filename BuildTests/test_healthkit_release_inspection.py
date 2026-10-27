"""Synthetic IPA/Mach-O/profile fixtures only; no accounts or real certificates."""
from datetime import datetime, timedelta, timezone
from pathlib import Path
import plistlib
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Scripts"))
from build_ios import BuildError
from verify_healthkit_signing import (HEALTH, BACKGROUND, inspect_ipa, inspect_macho,
                                     validate_profile_claims)

TEAM, BUNDLE = "A1B2C3D4E5", "app.example.luqma"


def macho(*, platform=2, cpu=0x0100000C, claims=None, flags=2, signed=True, der=False):
    version = struct.pack("<IIIIII", 0x32, 24, platform, 17 << 16, 26 << 16, 0)
    if not signed:
        return struct.pack("<IiiIIIII", 0xFEEDFACF, cpu, 0, 2, 1, 24, 0, 0) + version
    blobs = [(0, struct.pack(">IIII", 0xFADE0C02, 16, 0x20400, flags))]
    if der:
        blobs.append((7, struct.pack(">II", 0xFADE7172, 10) + b"\x30\x00"))
    else:
        xml = plistlib.dumps({HEALTH: True} if claims is None else claims)
        blobs.append((5, struct.pack(">II", 0xFADE7171, 8 + len(xml)) + xml))
    offset = 12 + len(blobs) * 8
    indexes = []
    for slot, blob in blobs:
        indexes.append(struct.pack(">II", slot, offset))
        offset += len(blob)
    signature = struct.pack(">III", 0xFADE0CC0, offset, len(blobs)) + b"".join(indexes) + b"".join(b for _, b in blobs)
    command = struct.pack("<IIII", 0x1D, 16, 32 + 24 + 16, len(signature))
    return struct.pack("<IiiIIIII", 0xFEEDFACF, cpu, 0, 2, 2, 40, 0, 0) + version + command + signature


def profile(claims=None):
    allowed = {"application-identifier": TEAM + "." + BUNDLE,
               "com.apple.developer.team-identifier": TEAM, HEALTH: True,
               "get-task-allow": True}
    allowed.update(claims or {})
    return {"ExpirationDate": datetime.now(timezone.utc) + timedelta(days=1),
            "Platform": ["iOS"], "TeamIdentifier": [TEAM],
            "ApplicationIdentifierPrefix": [TEAM], "Entitlements": allowed,
            "DeveloperCertificates": [b"synthetic-not-a-real-certificate"],
            "ProvisionedDevices": ["synthetic-not-a-real-device"]}


def package(path, *, binary=None, info=None, extras=None):
    metadata = {"CFBundleIdentifier": BUNDLE, "CFBundleExecutable": "Luqma",
                "CFBundleSupportedPlatforms": ["iPhoneOS"], "DTPlatformName": "iphoneos",
                "CFBundleShortVersionString": "2.9", "CFBundleVersion": "119",
                "MinimumOSVersion": "17.0"}
    metadata.update(info or {})
    with zipfile.ZipFile(path, "w") as archive:
        archive.writestr("Payload/Luqma.app/Info.plist", plistlib.dumps(metadata))
        archive.writestr("Payload/Luqma.app/Luqma", macho() if binary is None else binary)
        for name, data in (extras or {}).items():
            # Keep malicious fixture names literal even on Windows, where the
            # ZipInfo constructor ordinarily normalizes backslashes to '/'.
            entry = zipfile.ZipInfo("fixture-placeholder")
            entry.filename = entry.orig_filename = name
            archive.writestr(entry, data)
    return path


class MachOReleaseTests(unittest.TestCase):
    def test_actual_device_signature_blob_is_distinct_from_simulator_entitlements(self):
        result = inspect_macho(macho())
        self.assertEqual(result["platform"], "iPhoneOS")
        self.assertIs(result["claims"][HEALTH], True)
        self.assertTrue(result["ad_hoc_hash_only"])
        self.assertFalse(result["signature_seal_verified"])
        for platform, cpu in [(7, 0x0100000C), (7, 0x01000007), (2, 0x01000007), (1, 0x0100000C)]:
            with self.subTest(platform=platform, cpu=cpu), self.assertRaises(BuildError):
                inspect_macho(macho(platform=platform, cpu=cpu))

    def test_unsigned_and_der_only_do_not_invent_health_claims(self):
        self.assertEqual(inspect_macho(macho(signed=False))["claims"], {})
        self.assertIsNone(inspect_macho(macho(der=True))["claims"])
        for value in (False, 1, "true"):
            self.assertIsNot(inspect_macho(macho(claims={HEALTH: value}))["claims"][HEALTH], True)

    def test_truncated_or_overlapping_signature_and_command_bounds_are_rejected(self):
        original = macho()
        cases = [original[:20], original[:-1]]
        changed = bytearray(original)
        struct.pack_into("<I", changed, 32 + 24 + 8, 8)
        cases.append(bytes(changed))
        changed = bytearray(original)
        struct.pack_into(">I", changed, 72 + 12 + 8 + 4, 12 + 2 * 8)
        cases.append(bytes(changed))
        for value in cases:
            with self.subTest(length=len(value)), self.assertRaises(BuildError):
                inspect_macho(value)

    def test_universal_arm64_device_is_checked_per_slice(self):
        device = macho()
        header = struct.pack(">IIiiIII", 0xCAFEBABE, 1, 0x0100000C, 0, 4096, len(device), 12)
        binary = header + b"\0" * (4096 - len(header)) + device
        self.assertEqual(inspect_macho(binary)["slice_count"], 1)
        bad = bytearray(binary)
        struct.pack_into(">I", bad, 16, 4)
        with self.assertRaises(BuildError):
            inspect_macho(bytes(bad))


@patch("verify_healthkit_signing.platform.system", return_value="Windows")
class IPAReleaseTests(unittest.TestCase):
    def test_resignable_local_hash_build_never_becomes_apple_signed_pass(self, _host):
        with tempfile.TemporaryDirectory() as folder:
            result = inspect_ipa(package(Path(folder) / "test.ipa"), BUNDLE)
        self.assertEqual(result["statuses"]["BuildIntegrity"], "PASS")
        self.assertIsNone(result["statuses"]["CodeSignature"])
        self.assertEqual(result["evidence"]["signing"]["signing_kind"], "ADHOC_HASH")
        self.assertFalse(result["evidence"]["signing"]["apple_identity_verified"])
        self.assertEqual(result["statuses"]["ProvisioningProfile"], "ABSENT")
        self.assertEqual(result["statuses"]["HealthKitEntitlement"], "PRESENT")
        self.assertEqual(result["statuses"]["HealthKitProfileAuthorization"], "NOTVERIFIED")
        self.assertEqual(result["statuses"]["DeviceInstallation"], "NOTTESTED")
        self.assertEqual(result["statuses"]["RealHealthData"], "NOTTESTED")
        self.assertEqual(result["exit_code"], 2)

    def test_unavailable_native_tools_are_not_reported_as_unsigned_or_invalid(self, _host):
        with tempfile.TemporaryDirectory() as folder:
            result = inspect_ipa(package(Path(folder) / "test.ipa", binary=macho(flags=0),
                extras={"Payload/Luqma.app/embedded.mobileprovision": b"opaque-synthetic-CMS"}))
        self.assertIsNone(result["statuses"]["CodeSignature"])
        self.assertIsNone(result["statuses"]["ProvisioningProfile"])
        self.assertEqual(result["evidence"]["signing"]["signature_measurement"], "NOT_MEASURED")
        self.assertEqual(result["evidence"]["signing"]["profile_measurement"], "NOT_MEASURED")
        self.assertEqual(result["exit_code"], 2)

    def test_source_plist_or_purpose_text_cannot_substitute_for_signed_entitlement(self, _host):
        with tempfile.TemporaryDirectory() as folder:
            result = inspect_ipa(package(Path(folder) / "test.ipa", binary=macho(claims={}),
                info={"NSHealthShareUsageDescription": "Synthetic purpose"},
                extras={"Payload/Luqma.app/Luqma.entitlements": plistlib.dumps({HEALTH: True})}))
        self.assertEqual(result["statuses"]["HealthKitEntitlement"], "ABSENT")
        self.assertEqual(result["exit_code"], 1)

    def test_simulator_wrong_bundle_and_missing_declared_resources_fail(self, _host):
        cases = [dict(binary=macho(platform=7)), dict(info={"CFBundleSupportedPlatforms": ["iPhoneSimulator"]}),
                 dict(info={"UIAppFonts": ["missing-font.ttf"]}), dict(info={"UILaunchStoryboardName": "Missing"})]
        with tempfile.TemporaryDirectory() as folder:
            for index, kwargs in enumerate(cases):
                result = inspect_ipa(package(Path(folder) / (str(index) + ".ipa"), **kwargs))
                self.assertEqual(result["statuses"]["BuildIntegrity"], "FAIL")
            result = inspect_ipa(package(Path(folder) / "bundle.ipa"), "app.different.identifier")
            self.assertEqual(result["statuses"]["BuildIntegrity"], "FAIL")

    def test_traversal_symlinks_and_duplicate_members_are_rejected(self, _host):
        with tempfile.TemporaryDirectory() as folder:
            for index, name in enumerate(("../escape", "Payload/Luqma.app/../escape", "C:/escape", "Payload\\escape")):
                result = inspect_ipa(package(Path(folder) / (str(index) + ".ipa"), extras={name: b"invalid"}))
                self.assertEqual(result["statuses"]["BuildIntegrity"], "FAIL")
            path = package(Path(folder) / "link.ipa")
            with zipfile.ZipFile(path, "a") as archive:
                link = zipfile.ZipInfo("Payload/Luqma.app/link")
                link.external_attr = 0o120777 << 16
                archive.writestr(link, "../../../outside")
            self.assertEqual(inspect_ipa(path)["statuses"]["BuildIntegrity"], "FAIL")
            path = package(Path(folder) / "duplicate.ipa")
            with warnings.catch_warnings():
                warnings.simplefilter("ignore", UserWarning)
                with zipfile.ZipFile(path, "a") as archive:
                    archive.writestr("Payload/Luqma.app/Luqma", macho())
            self.assertEqual(inspect_ipa(path)["statuses"]["BuildIntegrity"], "FAIL")

    def test_der_only_on_windows_stays_unmeasured_and_absent_profile_is_not_invalid(self, _host):
        with tempfile.TemporaryDirectory() as folder:
            result = inspect_ipa(package(Path(folder) / "test.ipa", binary=macho(der=True)))
        self.assertIsNone(result["statuses"]["HealthKitEntitlement"])
        self.assertEqual(result["statuses"]["ProvisioningProfile"], "ABSENT")
        self.assertEqual(result["exit_code"], 2)


class ProfileClaimTests(unittest.TestCase):
    def test_decoded_valid_claims_never_establish_apple_profile_authorization(self):
        source = profile()
        result = validate_profile_claims(source, BUNDLE, dict(source["Entitlements"]))
        self.assertTrue(result["healthkit_allowed"])
        self.assertTrue(result["actual_claims_compared"])
        self.assertFalse(result["profile_apple_authorization_verified"])

    def test_generic_inspector_accepts_provisioned_extra_claims_without_source_allowlist(self):
        source = profile({"com.apple.developer.healthkit.access": [],
                          "com.apple.security.application-groups": ["group.synthetic"]})
        validate_profile_claims(source, BUNDLE, dict(source["Entitlements"]))

    def test_expiration_identity_and_unprovisioned_claims_fail(self):
        for change in ("expired", "identity", "extra", "type"):
            source = profile()
            actual = dict(source["Entitlements"])
            if change == "expired":
                source["ExpirationDate"] = datetime.now(timezone.utc) - timedelta(seconds=1)
            elif change == "identity":
                actual["application-identifier"] = TEAM + ".app.different"
            elif change == "extra":
                actual["aps-environment"] = "production"
            else:
                actual[HEALTH] = 1
            with self.subTest(change=change), self.assertRaises(BuildError):
                validate_profile_claims(source, BUNDLE, actual)

    def test_profile_without_healthkit_or_background_does_not_authorize_them(self):
        source = profile({HEALTH: False})
        result = validate_profile_claims(source, BUNDLE, dict(source["Entitlements"]))
        self.assertFalse(result["healthkit_allowed"])
        self.assertFalse(result["background_delivery_allowed"])

    def test_platform_and_registered_device_assertions_must_have_correct_types(self):
        for key, value in (("Platform", "iOS"), ("ProvisionedDevices", []),
                           ("ProvisionedDevices", "synthetic-device"),
                           ("ApplicationIdentifierPrefix", [True])):
            source = profile()
            source[key] = value
            with self.subTest(key=key), self.assertRaises(BuildError):
                validate_profile_claims(source, BUNDLE, dict(source["Entitlements"]))


class NativeClassificationTests(unittest.TestCase):
    @patch("verify_healthkit_signing.platform.system", return_value="Darwin")
    @patch("verify_healthkit_signing.shutil.which", return_value="/synthetic/tool")
    def test_mocked_native_local_seal_pass_is_never_apple_identity_or_health_grant(self, _which, _host):
        def native(arguments):
            if "--entitlements" in arguments:
                return plistlib.dumps({HEALTH: True})
            return b""
        with tempfile.TemporaryDirectory() as folder, patch("verify_healthkit_signing._run", side_effect=native):
            result = inspect_ipa(package(Path(folder) / "test.ipa"))
        self.assertEqual(result["statuses"]["CodeSignature"], "PASS")
        self.assertEqual(result["evidence"]["signing"]["signing_kind"], "ADHOC_HASH")
        self.assertFalse(result["evidence"]["signing"]["apple_identity_verified"])
        self.assertEqual(result["statuses"]["HealthKitProfileAuthorization"], "NOTVERIFIED")
        self.assertEqual(result["statuses"]["DeviceInstallation"], "NOTTESTED")
        self.assertEqual(result["exit_code"], 2)

    @patch("verify_healthkit_signing.platform.system", return_value="Windows")
    def test_notsigned_is_reserved_for_measured_signature_absence(self, _host):
        with tempfile.TemporaryDirectory() as folder:
            result = inspect_ipa(package(Path(folder) / "test.ipa", binary=macho(signed=False)))
        self.assertEqual(result["statuses"]["CodeSignature"], "NOTSIGNED")
        self.assertEqual(result["evidence"]["signing"]["signing_kind"], "NOTSIGNED")

    @patch("verify_healthkit_signing.platform.system", return_value="Darwin")
    @patch("verify_healthkit_signing.shutil.which", return_value="/synthetic/tool")
    def test_even_mocked_complete_native_static_pass_never_proves_install_or_health_access(self, _which, _host):
        data = profile({BACKGROUND: True})
        actual = dict(data["Entitlements"])
        def native(arguments):
            if "--entitlements" in arguments:
                return plistlib.dumps(actual)
            if "--extract-certificates" in arguments:
                prefix = arguments[arguments.index("--extract-certificates") + 1]
                Path(prefix + "0").write_bytes(data["DeveloperCertificates"][0])
            if arguments[:3] == ["security", "cms", "-D"]:
                return plistlib.dumps(data)
            return b""
        with tempfile.TemporaryDirectory() as folder, patch("verify_healthkit_signing._run", side_effect=native):
            result = inspect_ipa(package(Path(folder) / "test.ipa", binary=macho(claims=actual, flags=0),
                extras={"Payload/Luqma.app/embedded.mobileprovision": b"synthetic-opaque-CMS"}))
        self.assertEqual(result["statuses"]["CodeSignature"], "PASS")
        self.assertTrue(result["evidence"]["signing"]["apple_identity_verified"])
        self.assertEqual(result["statuses"]["ProvisioningProfile"], "VALID")
        self.assertEqual(result["statuses"]["BackgroundDelivery"], "SUPPORTED")
        self.assertEqual(result["statuses"]["HealthKitProfileAuthorization"], "NOTVERIFIED")
        self.assertFalse(result["evidence"]["signing"]["profile_apple_authorization_verified"])
        self.assertFalse(result["evidence"]["signing"]["background_runtime_delivery_tested"])
        self.assertEqual(result["statuses"]["DeviceInstallation"], "NOTTESTED")
        self.assertEqual(result["statuses"]["RealHealthData"], "NOTTESTED")
        self.assertEqual(result["exit_code"], 0)


if __name__ == "__main__":
    unittest.main()
