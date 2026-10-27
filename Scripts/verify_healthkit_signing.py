#!/usr/bin/env python3
"""Inspect a final Luqma IPA without installing it or accessing health/account data.

Exit 0: native Apple signature + matching decoded profile claims + HealthKit.
Exit 1: a measured structural/signature/claim failure.
Exit 2: incomplete verification or a locally signed package requiring Apple signing.
None/NOT_MEASURED is deliberately distinct from a measured absence or failure.
CodeSignature PASS verifies the resource seal; Apple identity is a separate check.
Profile VALID describes decoded claims, never independent Apple CMS/DER approval.
No static outcome proves installation, user consent, or real HealthKit readings.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path, PurePosixPath
import platform
import plistlib
import re
import shutil
import struct
import subprocess
import tempfile
import zipfile

from build_ios import BuildError, extract_exported_app
from signing import _entitlement_value_allowed

HEALTH = "com.apple.developer.healthkit"
BACKGROUND = "com.apple.developer.healthkit.background-delivery"
MAX_EXECUTABLE = 128 * 1024 * 1024
MAX_PLIST = 1024 * 1024
ARM64 = 0x0100000C


def _invalid(message: str) -> BuildError:
    return BuildError("IPA inspection: " + message + ".")


def _plist(data: bytes) -> dict:
    if len(data) > MAX_PLIST:
        raise _invalid("metadata is unexpectedly large")
    try:
        value = plistlib.loads(data)
    except Exception:
        raise _invalid("metadata is not a valid property list") from None
    if not isinstance(value, dict) or not all(isinstance(key, str) for key in value):
        raise _invalid("metadata is not a property-list dictionary")
    return value


def _signature(data: bytes) -> dict:
    if len(data) < 12:
        raise _invalid("truncated code-signature container")
    magic, size, count = struct.unpack_from(">III", data)
    if magic != 0xFADE0CC0 or size > len(data) or size < 12 or not 0 < count <= 128:
        raise _invalid("invalid code-signature container")
    table_end = 12 + count * 8
    if table_end > size:
        raise _invalid("invalid code-signature index")
    seen, spans, flags, claims, has_der = set(), [], [], None, False
    for index in range(count):
        slot, offset = struct.unpack_from(">II", data, 12 + index * 8)
        if slot in seen or offset < table_end or offset + 8 > size:
            raise _invalid("invalid code-signature blob offset")
        seen.add(slot)
        kind, length = struct.unpack_from(">II", data, offset)
        if length < 8 or length > size - offset:
            raise _invalid("invalid code-signature blob length")
        if any(offset < end and start < offset + length for start, end in spans):
            raise _invalid("overlapping code-signature blobs")
        spans.append((offset, offset + length))
        if kind == 0xFADE0C02:  # CodeDirectory; its flags are metadata, not validation.
            if length < 16:
                raise _invalid("truncated code directory")
            flags.append(struct.unpack_from(">I", data, offset + 12)[0])
        if slot == 5:
            if kind != 0xFADE7171:
                raise _invalid("invalid XML entitlement blob")
            claims = _plist(data[offset + 8:offset + length])
        if slot == 7:
            if kind != 0xFADE7172:
                raise _invalid("invalid DER entitlement blob")
            has_der = True
    if not flags:
        raise _invalid("signature has no code directory")
    if len({bool(value & 2) for value in flags}) != 1:
        raise _invalid("code directories disagree about local-hash signing")
    return {"present": True, "ad_hoc_hash_only": bool(flags[0] & 2),
            "claims": claims if claims is not None or has_der else {},
            "der_entitlements_present": has_der,
            "signature_seal_verified": False}


def _thin_macho(data: bytes) -> dict:
    if len(data) < 32 or data[:4] != b"\xcf\xfa\xed\xfe":
        raise _invalid("expected a 64-bit little-endian device Mach-O")
    _, cpu, _, file_type, count, size, _, _ = struct.unpack_from("<IiiIIIII", data)
    if cpu != ARM64 or file_type != 2:
        raise _invalid("main executable is not an arm64 application")
    end = 32 + size
    if not 0 < count <= 8192 or count > size // 8 or end > len(data):
        raise _invalid("invalid executable load-command bounds")
    cursor, platforms, signatures = 32, [], []
    for _ in range(count):
        if cursor + 8 > end:
            raise _invalid("truncated executable load command")
        command, length = struct.unpack_from("<II", data, cursor)
        if length < 8 or length % 8 or length > end - cursor:
            raise _invalid("invalid executable load-command size")
        if command == 0x32:  # LC_BUILD_VERSION is unambiguous for iOS17+ builds.
            if length < 24:
                raise _invalid("truncated build-version command")
            target, _, _, tools = struct.unpack_from("<IIII", data, cursor + 8)
            if length != 24 + tools * 8:
                raise _invalid("invalid build-version tool table")
            platforms.append(target)
        elif command == 0x1D:
            if length != 16:
                raise _invalid("invalid code-signature load command")
            signatures.append(struct.unpack_from("<II", data, cursor + 8))
        cursor += length
    if cursor != end or platforms != [2]:
        raise _invalid("main executable is not unambiguously built for iPhoneOS")
    if len(signatures) > 1:
        raise _invalid("duplicate code-signature load commands")
    signature = {"present": False, "ad_hoc_hash_only": False, "claims": {},
                 "der_entitlements_present": False, "signature_seal_verified": False}
    if signatures:
        offset, length = signatures[0]
        if offset < end or not length or offset > len(data) or length > len(data) - offset:
            raise _invalid("code signature exceeds executable bounds")
        signature = _signature(data[offset:offset + length])
    return {"architecture": "arm64", "platform": "iPhoneOS", **signature}


def inspect_macho(data: bytes) -> dict:
    """Read actual load commands/signature blobs; never execute the binary."""
    if not 32 <= len(data) <= MAX_EXECUTABLE:
        raise _invalid("missing or oversized executable")
    magic = data[:4]
    formats = {b"\xca\xfe\xba\xbe": (">", False), b"\xbe\xba\xfe\xca": ("<", False),
               b"\xca\xfe\xba\xbf": (">", True), b"\xbf\xba\xfe\xca": ("<", True)}
    if magic not in formats:
        slices = [_thin_macho(data)]
    else:
        order, wide = formats[magic]
        count = struct.unpack_from(order + "I", data, 4)[0]
        width = 32 if wide else 20
        table_end = 8 + width * count
        if not 0 < count <= 16 or table_end > len(data):
            raise _invalid("invalid universal executable table")
        slices, spans = [], []
        for index in range(count):
            fields = struct.unpack_from(order + ("iiQQII" if wide else "iiIII"),
                                        data, 8 + index * width)
            cpu, _, offset, length, align = fields[:5]
            if (cpu != ARM64 or align > 30 or offset % (1 << align)
                    or offset < table_end or not length or offset > len(data)
                    or length > len(data) - offset
                    or any(offset < stop and start < offset + length for start, stop in spans)):
                raise _invalid("invalid or unsupported universal executable slice")
            spans.append((offset, offset + length))
            slices.append(_thin_macho(data[offset:offset + length]))
    for key in ("present", "ad_hoc_hash_only", "claims", "der_entitlements_present"):
        if any(item[key] != slices[0][key] for item in slices[1:]):
            raise _invalid("executable slices disagree about signed capabilities")
    return {**slices[0], "slice_count": len(slices)}


def _archive_checks(archive: zipfile.ZipFile) -> None:
    items = archive.infolist()
    if len(items) > 50000 or sum(item.file_size for item in items) > 512 * 1024 * 1024:
        raise _invalid("archive is unexpectedly large")
    seen = set()
    for item in items:
        name = item.filename
        path = PurePosixPath(name)
        if (item.orig_filename != name or name in seen or "\\" in name or ":" in name
                or path.is_absolute() or ".." in path.parts
                or path.as_posix() != name.rstrip("/")
                or item.file_size > MAX_EXECUTABLE
                or (item.external_attr >> 16) & 0o170000 == 0o120000):
            raise _invalid("unsafe or duplicate archive entry")
        seen.add(name)
    if archive.testzip() is not None:
        raise _invalid("archive resource CRC verification failed")
    mains = [name for name in seen if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)]
    if mains != ["Payload/Luqma.app/Info.plist"]:
        raise _invalid("expected exactly the Luqma application payload")


def _resources(app: Path, info: dict) -> None:
    for name in info.get("UIAppFonts", []):
        if (not isinstance(name, str) or "\\" in name or ":" in name
                or PurePosixPath(name).is_absolute() or ".." in PurePosixPath(name).parts
                or not (app / name).is_file()):
            raise _invalid("a declared font resource is missing or unsafe")
    launch = info.get("UILaunchStoryboardName")
    if launch is not None and (not isinstance(launch, str) or not re.fullmatch(r"[\w-]+", launch)
                               or not (app / (launch + ".storyboardc")).is_dir()):
        raise _invalid("the declared launch storyboard is missing")


def _run(arguments: list[str]) -> bytes | None:
    try:
        result = subprocess.run(arguments, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                timeout=90)
        return result.stdout if result.returncode == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def validate_profile_claims(profile: dict, bundle: str, claims: dict | None,
                            now: datetime | None = None) -> dict:
    """Validate decoded assertions only; CMS/DER approval is not inferred."""
    now = now or datetime.now(timezone.utc)
    expires = profile.get("ExpirationDate")
    if not isinstance(expires, datetime):
        raise _invalid("decoded profile has no expiration date")
    expires = expires.replace(tzinfo=timezone.utc) if expires.tzinfo is None else expires.astimezone(timezone.utc)
    if expires <= now:
        raise _invalid("decoded profile has expired")
    allowed = profile.get("Entitlements")
    teams, prefixes = profile.get("TeamIdentifier"), profile.get("ApplicationIdentifierPrefix")
    platforms = profile.get("Platform")
    if (not isinstance(allowed, dict) or not isinstance(teams, list) or len(teams) != 1
            or not isinstance(teams[0], str) or not isinstance(prefixes, list)
            or not prefixes or any(not isinstance(value, str) for value in prefixes)
            or not isinstance(platforms, list) or "iOS" not in platforms):
        raise _invalid("decoded profile has inconsistent platform or team assertions")
    app_id = allowed.get("application-identifier")
    if (not isinstance(app_id, str) or "." not in app_id
            or app_id.split(".", 1)[0] not in prefixes
            or app_id.split(".", 1)[1] != bundle
            or allowed.get("com.apple.developer.team-identifier") != teams[0]):
        raise _invalid("decoded profile does not match the application's identifier or team")
    if claims is not None:
        if (claims.get("application-identifier") != app_id
                or claims.get("com.apple.developer.team-identifier") != teams[0]):
            raise _invalid("actual signed identity does not match the decoded profile")
        if any(key not in allowed or not _entitlement_value_allowed(value, allowed[key])
               for key, value in claims.items()):
            raise _invalid("an actual signed capability is outside the decoded profile allowlist")
    certificates = profile.get("DeveloperCertificates")
    if not isinstance(certificates, list) or not certificates or any(
            not isinstance(item, bytes) or not item for item in certificates):
        raise _invalid("decoded profile has no signing certificates")
    devices = profile.get("ProvisionedDevices")
    if devices is not None and (not isinstance(devices, list) or not devices or any(
            not isinstance(item, str) or not item for item in devices)):
        raise _invalid("decoded profile has an invalid registered-device list")
    if profile.get("get-task-allow") is not None:
        raise _invalid("decoded profile has misplaced debugging assertions")
    debugging = allowed.get("get-task-allow", False)
    if type(debugging) is not bool or debugging and devices is None:
        raise _invalid("decoded profile has inconsistent development assertions")
    if "ProvisionsAllDevices" in profile and type(profile["ProvisionsAllDevices"]) is not bool:
        raise _invalid("decoded profile has an invalid enterprise assertion")
    method = ("enterprise" if profile.get("ProvisionsAllDevices") is True else
              "development" if debugging else "ad_hoc" if devices is not None else "app_store")
    return {"healthkit_allowed": allowed.get(HEALTH) is True,
            "background_delivery_allowed": allowed.get(BACKGROUND) is True,
            "actual_claims_compared": claims is not None,
            "distribution_method": method,
            "registered_device_count": len(devices) if devices is not None else None,
            "signing_certificates": certificates,
            "profile_apple_authorization_verified": False}


def _native_inspection(app: Path, signature: dict, profile_data: bytes | None,
                       bundle: str) -> dict:
    available = platform.system() == "Darwin" and all(shutil.which(x) for x in ("codesign", "security"))
    result = {"native_tools_available": bool(available), "code_signature_status": None,
              "signature_measurement": "NOT_MEASURED", "claims": signature["claims"],
              "profile_status": "ABSENT" if profile_data is None else None,
              "profile_measurement": "MEASURED" if profile_data is None else "NOT_MEASURED",
              "profile_claims": None, "profile_reason": None,
              "signing_kind": "ADHOC_HASH" if signature["ad_hoc_hash_only"] else "SIGNATURE_PRESENT" if signature["present"] else "NOTSIGNED",
              "apple_identity_verified": False if signature["ad_hoc_hash_only"] or not signature["present"] else None,
              "certificate_trust_verified": False, "signer_matches_profile": False}
    if not signature["present"]:
        result.update(code_signature_status="NOTSIGNED", signature_measurement="MEASURED")
    if not available:
        return result
    signed_xml = _run(["codesign", "--display", "--entitlements", "-", "--xml", str(app)])
    if signed_xml is not None:
        try:
            result["claims"] = _plist(signed_xml)
        except BuildError:
            result["claims"] = None
    certs = []
    if signature["present"]:
        result.update(code_signature_status="FAIL", signature_measurement="MEASURED")
        seal = _run(["codesign", "--verify", "--deep", "--strict", str(app)])
        if seal is not None:
            result["code_signature_status"] = "PASS"
    if signature["present"] and not signature["ad_hoc_hash_only"]:
        result["apple_identity_verified"] = False
        anchored = _run(["codesign", "--verify", "--deep", "--strict", "-R", "anchor apple generic", str(app)])
        with tempfile.TemporaryDirectory(prefix="luqma-signer-audit-") as folder:
            prefix = Path(folder) / "certificate-"
            extracted = _run(["codesign", "--display", "--extract-certificates", str(prefix), str(app)])
            paths = sorted(Path(folder).glob("certificate-*"))
            if extracted is not None and paths and Path(str(prefix) + "0").is_file():
                trust = ["security", "verify-cert", "-p", "codeSign"]
                for path in paths:
                    trust += ["-c", str(path)]
                trusted = _run(trust) is not None
                certs = [path.read_bytes() for path in paths]
                result["certificate_trust_verified"] = trusted
                if result["code_signature_status"] == "PASS" and anchored is not None and trusted:
                    result["apple_identity_verified"] = True
                    result["signing_kind"] = "APPLE_CERTIFICATE"
    if profile_data is not None:
        result["profile_measurement"] = "MEASURED"
        result["profile_status"] = "INVALID"
        with tempfile.TemporaryDirectory(prefix="luqma-profile-audit-") as folder:
            path = Path(folder) / "profile.mobileprovision"
            path.write_bytes(profile_data)
            path.chmod(0o600)
            decoded = _run(["security", "cms", "-D", "-i", str(path)])
        try:
            if decoded is None:
                raise _invalid("native profile decoding did not succeed")
            checked = validate_profile_claims(_plist(decoded), bundle, result["claims"])
            if certs:
                result["signer_matches_profile"] = certs[0] in checked["signing_certificates"]
                if not result["signer_matches_profile"]:
                    raise _invalid("actual signing certificate is not allowed by the decoded profile")
            result["profile_claims"] = {key: value for key, value in checked.items()
                                        if key != "signing_certificates"}
            result["profile_status"] = "VALID"
        except BuildError as error:
            result["profile_reason"] = str(error)
    return result


def inspect_ipa(ipa: Path, expected_bundle: str | None = None) -> dict:
    statuses = {"BuildIntegrity": "FAIL", "CodeSignature": None,
                "ProvisioningProfile": None, "HealthKitEntitlement": None,
                "HealthKitProfileAuthorization": "NOTVERIFIED",
                "BackgroundDelivery": "NOTTESTED", "DeviceInstallation": "NOTTESTED",
                "RealHealthData": "NOTTESTED"}
    report = {"schema_version": 1, "checked_at": datetime.now(timezone.utc).isoformat(),
              "ipa_file": Path(ipa).name, "statuses": statuses, "evidence": {},
              "scope": "Static package and native signing inspection only; no installation, account authorization, consent, or Health reads.",
              "profile_valid_meaning": "VALID means decoded profile assertions matched; independent Apple CMS/DER authorization is not established.",
              "code_signature_pass_meaning": "PASS means codesign verified the seal; apple_identity_verified separately records an Apple-anchored trusted signing identity.",
              "background_supported_meaning": "SUPPORTED describes checked signed/profile configuration only; actual background delivery remains untested.",
              "exit_code": 1}
    try:
        ipa = Path(ipa)
        if not ipa.is_file() or ipa.stat().st_size > 512 * 1024 * 1024:
            raise _invalid("input package is missing or unexpectedly large")
        digest = hashlib.sha256()
        with ipa.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
        report.update(ipa_sha256=digest.hexdigest(), ipa_bytes=ipa.stat().st_size)
        with tempfile.TemporaryDirectory(prefix="luqma-ipa-audit-") as folder:
            with zipfile.ZipFile(ipa) as archive:
                _archive_checks(archive)
                app = extract_exported_app(archive, Path(folder))
            info = _plist((app / "Info.plist").read_bytes())
            bundle, executable = info.get("CFBundleIdentifier"), info.get("CFBundleExecutable")
            if (info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]
                    or info.get("DTPlatformName", "iphoneos") != "iphoneos"):
                raise _invalid("application metadata does not describe an iPhoneOS build")
            if (not isinstance(bundle, str) or not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle)
                    or expected_bundle is not None and bundle != expected_bundle):
                raise _invalid("application identifier is invalid or differs from the expected identifier")
            if not isinstance(executable, str) or not re.fullmatch(r"[A-Za-z0-9_. -]+", executable) or executable in (".", ".."):
                raise _invalid("main executable name is invalid")
            _resources(app, info)
            signature = inspect_macho((app / executable).read_bytes())
            statuses["BuildIntegrity"] = "PASS"
            report.update(bundle_identifier=bundle, version=info.get("CFBundleShortVersionString"),
                          build=info.get("CFBundleVersion"), minimum_os=info.get("MinimumOSVersion"))
            report["evidence"]["build"] = {"archive_crc_verified": True,
                "declared_resources_checked": True, "architecture": "arm64", "platform": "iPhoneOS",
                "slice_count": signature["slice_count"], "structural_only": True}
            profile = app / "embedded.mobileprovision"
            native = _native_inspection(app, signature, profile.read_bytes() if profile.is_file() else None, bundle)
            claims = native.pop("claims")
            statuses["CodeSignature"] = native["code_signature_status"]
            statuses["ProvisioningProfile"] = native["profile_status"]
            statuses["HealthKitEntitlement"] = None if claims is None else "PRESENT" if claims.get(HEALTH) is True else "ABSENT"
            allowed = native["profile_claims"]
            background = None if claims is None else claims.get(BACKGROUND) is True
            if background is False or allowed is not None and not allowed["background_delivery_allowed"]:
                statuses["BackgroundDelivery"] = "UNSUPPORTED"
            elif (background is True and allowed is not None and allowed["healthkit_allowed"]
                  and statuses["HealthKitEntitlement"] == "PRESENT" and statuses["CodeSignature"] == "PASS"
                  and native["signer_matches_profile"] and native["apple_identity_verified"] is True):
                statuses["BackgroundDelivery"] = "SUPPORTED"
            report["evidence"]["signing"] = {**native,
                "ad_hoc_hash_only": signature["ad_hoc_hash_only"],
                "actual_signed_claims_source": "native codesign or embedded Mach-O entitlement blob",
                "healthkit_claim_measurement": "NOT_MEASURED" if claims is None else "MEASURED",
                "profile_present": profile.is_file(), "profile_apple_authorization_verified": False,
                "healthkit_profile_authorization_verified": False,
                "background_runtime_delivery_tested": False}
            failed = (statuses["CodeSignature"] == "FAIL" or statuses["ProvisioningProfile"] == "INVALID"
                      or statuses["HealthKitEntitlement"] == "ABSENT"
                      or allowed is not None and not allowed["healthkit_allowed"])
            complete = (statuses["CodeSignature"] == "PASS" and statuses["ProvisioningProfile"] == "VALID"
                        and statuses["HealthKitEntitlement"] == "PRESENT"
                        and allowed is not None and allowed["healthkit_allowed"]
                        and allowed["actual_claims_compared"] and native["signer_matches_profile"]
                        and native["apple_identity_verified"] is True)
            report["exit_code"] = 1 if failed else 0 if complete else 2
    except (BuildError, OSError, ValueError, TypeError, zipfile.BadZipFile, RuntimeError, struct.error) as error:
        # Never attach binary bytes, decoded profiles, certificates, tool stderr,
        # UDIDs or health values to public diagnostic reports.
        report["reason"] = str(error) if isinstance(error, BuildError) else "IPA structure or metadata could not be inspected."
        report["exit_code"] = 1
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ipa", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path, help="JSON report file, not a directory")
    parser.add_argument("--expected-bundle")
    args = parser.parse_args()
    if args.output.resolve() == args.ipa.resolve():
        parser.error("The report output must not replace the IPA input.")
    report = inspect_ipa(args.ipa, args.expected_bundle)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    for name, status in report["statuses"].items():
        print(name + ": " + (status if status is not None else "NOT_MEASURED"))
    signing = report["evidence"].get("signing", {})
    print("SigningKind: " + signing.get("signing_kind", "NOT_MEASURED"))
    identity = signing.get("apple_identity_verified")
    print("AppleSigningIdentity: " + ("VERIFIED" if identity is True else "NOTVERIFIED" if identity is False else "NOT_MEASURED"))
    print("Static inspection cannot establish iOS installation, Health consent or actual reads.")
    return report["exit_code"]


if __name__ == "__main__":
    raise SystemExit(main())
