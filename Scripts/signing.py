"""Validate Apple signing inputs without printing certificates or device IDs."""
from __future__ import annotations

import base64
import binascii
import hashlib
import os
import plistlib
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


class BuildError(RuntimeError):
    pass

REQUESTED_ENTITLEMENTS=plistlib.loads((Path(__file__).resolve().parents[1]/"Luqma/Luqma.entitlements").read_bytes())


@dataclass(frozen=True)
class SigningProfile:
    uuid: str
    team: str
    bundle: str
    method: str
    expires: datetime
    certificates: tuple[str, ...]
    device_count: int
    application_identifier: str
    allowed_entitlements: dict

    def export_options(self, identity: str) -> dict:
        return {
            "method": self.method,
            "destination": "export",
            "signingStyle": "manual",
            "signingCertificate": identity,
            "teamID": self.team,
            "provisioningProfiles": {self.bundle: self.uuid},
            "manageAppVersionAndBuildNumber": False,
            "stripSwiftSymbols": True,
            "uploadSymbols": False,
        }


def validate_identifiers(team: str, bundle: str) -> None:
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise BuildError("APPLE_TEAM_ID must be the 10-character Apple team identifier.")
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle):
        raise BuildError("BUNDLE_ID must be an explicit application identifier, without wildcards.")


def validate_profile(data: bytes, team: str, bundle: str, mode: str,
                     now: datetime | None = None) -> SigningProfile:
    validate_identifiers(team, bundle)
    if mode not in ("development", "ad-hoc", "app-store"):
        raise BuildError("Signed export mode must be development, ad-hoc or app-store.")
    try:
        profile = plistlib.loads(data)
    except (ValueError, TypeError, plistlib.InvalidFileException) as error:
        raise BuildError("The decoded provisioning profile is not a valid plist.") from error
    if not isinstance(profile, dict):
        raise BuildError("The provisioning profile must be a dictionary.")
    identifier = profile.get("UUID", "")
    if not isinstance(identifier, str) or not re.fullmatch(
            r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}", identifier):
        raise BuildError("The provisioning profile has no valid UUID.")
    if team not in profile.get("TeamIdentifier", []):
        raise BuildError("The provisioning profile belongs to a different Apple team.")
    if "iOS" not in profile.get("Platform", []):
        raise BuildError("An iOS provisioning profile is required.")
    entitlements = profile.get("Entitlements")
    if not isinstance(entitlements, dict):
        raise BuildError("The provisioning profile has no entitlements.")
    application_id = entitlements.get("application-identifier", "")
    if not isinstance(application_id, str) or "." not in application_id:
        raise BuildError("The provisioning profile has no application identifier.")
    prefix, actual_bundle = application_id.split(".", 1)
    if actual_bundle != bundle or prefix not in profile.get("ApplicationIdentifierPrefix", []):
        raise BuildError("BUNDLE_ID does not match the profile's explicit App ID.")
    if entitlements.get("com.apple.developer.team-identifier") != team:
        raise BuildError("The profile's entitlement team does not match APPLE_TEAM_ID.")
    for key,value in REQUESTED_ENTITLEMENTS.items():
        if entitlements.get(key)!=value or type(entitlements.get(key)) is not type(value):
            raise BuildError("The provisioning profile does not allow the requested capability: "+key)
    if mode == "development" and entitlements.get("get-task-allow") is not True:
        raise BuildError("A development profile permitting debugging is required for development signing.")
    if mode != "development" and entitlements.get("get-task-allow", False) is not False:
        raise BuildError("A distribution profile is required, not a development profile.")
    if profile.get("ProvisionsAllDevices"):
        raise BuildError("Enterprise profiles are not supported by this distribution workflow.")
    devices = profile.get("ProvisionedDevices", [])
    if not isinstance(devices, list) or any(not isinstance(x, str) or not x for x in devices):
        raise BuildError("The provisioning profile's device list is malformed.")
    if mode == "ad-hoc" and not devices:
        raise BuildError("An Ad Hoc profile containing registered iPhones is required.")
    if mode == "development" and not devices:
        raise BuildError("A development profile containing registered iPhones is required.")
    if mode == "app-store" and "ProvisionedDevices" in profile:
        raise BuildError("App Store export requires an App Store Connect distribution profile.")
    expires = profile.get("ExpirationDate")
    if not isinstance(expires, datetime):
        raise BuildError("The provisioning profile has no expiration date.")
    expires = expires.replace(tzinfo=timezone.utc) if expires.tzinfo is None else expires.astimezone(timezone.utc)
    current = now or datetime.now(timezone.utc)
    current = current.replace(tzinfo=timezone.utc) if current.tzinfo is None else current.astimezone(timezone.utc)
    if expires <= current:
        raise BuildError("The provisioning profile has expired. Generate a new profile.")
    certificates = profile.get("DeveloperCertificates", [])
    if not isinstance(certificates, list) or not certificates or any(
            not isinstance(x, bytes) or not x for x in certificates):
        raise BuildError("The profile contains no valid signing certificate data.")
    methods = {"development": "debugging", "ad-hoc": "release-testing", "app-store": "app-store-connect"}
    return SigningProfile(identifier, team, bundle, methods[mode],
                          expires, tuple(hashlib.sha1(x).hexdigest().upper() for x in certificates), len(devices),
                          application_id, dict(entitlements))


def _entitlement_value_allowed(actual, allowed) -> bool:
    """Match an iOS profile allowlist without coercing booleans or globbing.

    A profile can allow an anchored trailing wildcard such as PREFIX.*. Code
    signatures must contain concrete values. Arrays claim a subset of the
    profile's permitted values; an entitlement absent from the signature is fine.
    """
    if type(actual) is not type(allowed):
        return False
    if isinstance(actual, str):
        if "*" in actual:
            return False
        if "*" not in allowed:
            return actual == allowed
        if allowed.count("*") != 1 or not allowed.endswith("*"):
            return False
        prefix = allowed[:-1]
        return bool(prefix) and actual.startswith(prefix) and len(actual) > len(prefix)
    if isinstance(actual, list):
        return all(any(_entitlement_value_allowed(value, permitted) for permitted in allowed)
                   for value in actual)
    if isinstance(actual, dict):
        return all(key in allowed and _entitlement_value_allowed(value, allowed[key])
                   for key, value in actual.items())
    return actual == allowed


def validate_signed_entitlements(data: bytes, profile: SigningProfile) -> None:
    """Check the *exported executable's* claims, not only the profile allowlist.

    codesign verifies the signature and resource seal separately. The actual
    claims must match the app's requested capabilities and the profile allowlist.
    """
    try:
        claims = plistlib.loads(data)
    except (ValueError, TypeError, plistlib.InvalidFileException) as error:
        raise BuildError("The exported application has no valid code-signing entitlements.") from error
    if not isinstance(claims, dict):
        raise BuildError("The exported application's signing entitlements must be a dictionary.")
    required = {
        "application-identifier": profile.application_identifier,
        "com.apple.developer.team-identifier": profile.team,
    }
    required.update(REQUESTED_ENTITLEMENTS)
    for key, expected in required.items():
        actual = claims.get(key)
        if actual != expected or type(actual) is not type(expected):
            raise BuildError(f"The exported application's signature is missing or changes {key}.")
    if profile.method == "debugging" and claims.get("get-task-allow") is not True:
        raise BuildError("The exported development application's debugging entitlement does not match its profile.")
    if profile.method != "debugging" and claims.get("get-task-allow", False) is not False:
        raise BuildError("The exported distribution application still permits debugging.")
    # Every claimed iOS entitlement must be provisioned, including keys outside
    # com.apple.developer.* (for example keychain-access-groups and aps-environment).
    # Keep the app's explicit capability scope stricter than the profile allowlist.
    for key, value in claims.items():
        if (key.startswith("com.apple.developer.") and
                key != "com.apple.developer.team-identifier" and key not in REQUESTED_ENTITLEMENTS):
            raise BuildError("The exported application claims a capability removed from this app: "+key)
        if key not in profile.allowed_entitlements or not _entitlement_value_allowed(value, profile.allowed_entitlements[key]):
            raise BuildError(f"The exported application claims an unprovisioned capability: {key}.")


def decode_secret(value: str, path: Path) -> None:
    try:
        data = base64.b64decode("".join(value.split()), validate=True)
    except (binascii.Error, ValueError) as error:
        raise BuildError("A signing file secret is not valid Base64.") from error
    if not data or len(data) > 10 * 1024 * 1024:
        raise BuildError("A signing file secret is empty or unexpectedly large.")
    with path.open("xb") as file:
        os.chmod(path, 0o600)
        file.write(data)


def select_identity(output: str, profile: SigningProfile) -> str:
    development = profile.method == "debugging"
    prefixes = (("Apple Development:", "iPhone Developer:") if development else
                ("Apple Distribution:", "iPhone Distribution:"))
    for fingerprint, name in re.findall(r'\b([A-Fa-f0-9]{40})\s+"([^"\n]+)"', output):
        if fingerprint.upper() in profile.certificates and name.startswith(prefixes):
            return fingerprint.upper()
    kind = "development" if development else "distribution"
    raise BuildError("No valid "+kind+" certificate with a private key matches the profile. Check the P12 file and password.")
