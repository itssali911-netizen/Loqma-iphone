#!/usr/bin/env python3
"""Build with Apple's SDK on a local Mac or a GitHub macOS runner. No upload."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import plistlib
import re
import secrets
import shlex
import shutil
import signal
import subprocess
import sys
import tempfile
import zipfile
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

from signing import (BuildError, decode_secret, select_identity, validate_identifiers,
                     validate_profile, validate_signed_entitlements)
from vision_compat import apply_vision_compat

ROOT = Path(__file__).resolve().parent.parent
SECRET_NAMES = ("BUILD_CERTIFICATE_BASE64", "P12_PASSWORD", "BUILD_PROVISION_PROFILE_BASE64")


def public_environment() -> dict[str, str]:
    return {key: value for key, value in os.environ.items() if key not in SECRET_NAMES}


def private_command(arguments: list[str], label: str) -> bytes:
    result = subprocess.run(arguments, capture_output=True, env=public_environment())
    if result.returncode:
        # security's errors can contain private certificate/profile information.
        raise BuildError(f"{label} failed. Check your signing inputs; private command output is withheld.")
    return result.stdout


def run(arguments: list[str], log: Path) -> None:
    print("Running:", shlex.join(arguments), flush=True)
    with log.open("wb") as file:
        result = subprocess.run(arguments, cwd=ROOT, env=public_environment(), stdout=file, stderr=subprocess.STDOUT)
    if result.returncode:
        # These commands receive no signing secrets. Full diagnostics remain in the log artifact.
        lines = log.read_text(errors="replace").splitlines()
        diagnostics = list(dict.fromkeys(line for line in lines if ": error:" in line or ": warning:" in line))
        if diagnostics:
            print("\n".join(diagnostics[:200]), file=sys.stderr)
        tail = lines[-65:]
        print("\n".join(tail), file=sys.stderr)
        raise BuildError(f"Build command failed ({result.returncode}); see {log.name}.")


def require_mac(minimum: int = 16) -> None:
    if platform.system() != "Darwin":
        raise BuildError("iOS compilation requires macOS and Xcode. From Windows, run the included GitHub Actions workflow.")
    for command in ("xcodebuild", "swift", "security", "codesign", "ditto"):
        if not shutil.which(command):
            raise BuildError(f"Required macOS tool is missing: {command}.")
    result = subprocess.run(["xcodebuild", "-version"], capture_output=True, text=True, env=public_environment())
    match = re.search(r"Xcode (\d+)", result.stdout)
    if result.returncode or not match or int(match.group(1)) < minimum:
        raise BuildError(f"Select Xcode {minimum} or newer before building.")
    print(result.stdout.strip())


@contextmanager
def installed_signing(mode: str, team: str, bundle: str):
    validate_identifiers(team, bundle)
    for key in SECRET_NAMES:
        if key not in os.environ or (key != "P12_PASSWORD" and not os.environ[key].strip()):
            raise BuildError(f"Missing repository signing secret: {key}.")
    with tempfile.TemporaryDirectory(prefix="luqma-signing-", dir=os.environ.get("RUNNER_TEMP")) as folder:
        temporary = Path(folder)
        certificate = temporary / "certificate.p12"
        mobile = temporary / "profile.mobileprovision"
        keychain = temporary / "signing.keychain-db"
        keychain_password = secrets.token_urlsafe(32)
        decode_secret(os.environ["BUILD_CERTIFICATE_BASE64"], certificate)
        decode_secret(os.environ["BUILD_PROVISION_PROFILE_BASE64"], mobile)
        decoded = private_command(["security", "cms", "-D", "-i", str(mobile)], "Provisioning profile decoding")
        profile = validate_profile(decoded, team, bundle, mode)
        original_search = shlex.split(private_command(["security", "list-keychains", "-d", "user"], "Keychain discovery").decode())
        # Xcode 16+ reads the new directory; the legacy directory supports local older setups.
        directories = [Path.home() / "Library/Developer/Xcode/UserData/Provisioning Profiles",
                       Path.home() / "Library/MobileDevice/Provisioning Profiles"]
        restored: list[tuple[Path, bytes | None, int]] = []
        keychain_created = False
        search_changed = False
        try:
            private_command(["security", "create-keychain", "-p", keychain_password, str(keychain)], "Temporary keychain creation")
            keychain_created = True
            private_command(["security", "set-keychain-settings", "-lut", "7200", str(keychain)], "Keychain timeout setup")
            private_command(["security", "unlock-keychain", "-p", keychain_password, str(keychain)], "Keychain unlock")
            private_command(["security", "import", str(certificate), "-P", os.environ["P12_PASSWORD"], "-k", str(keychain), "-f", "pkcs12", "-T", "/usr/bin/codesign", "-T", "/usr/bin/security"], "Certificate import")
            private_command(["security", "set-key-partition-list", "-S", "apple-tool:,apple:", "-k", keychain_password, str(keychain)], "Code signing key access")
            private_command(["security", "list-keychains", "-d", "user", "-s", *original_search, str(keychain)], "Keychain search setup")
            search_changed = True
            identities = private_command(["security", "find-identity", "-v", "-p", "codesigning", str(keychain)], "Signing identity validation")
            identity = select_identity(identities.decode(), profile)
            for directory in directories:
                directory.mkdir(parents=True, exist_ok=True)
                installed = directory / (profile.uuid + ".mobileprovision")
                if installed.is_symlink():
                    raise BuildError("The existing provisioning profile path is a symbolic link; choose a clean runner.")
                old = installed.read_bytes() if installed.exists() else None
                permissions = installed.stat().st_mode & 0o777 if installed.exists() else 0o600
                restored.append((installed, old, permissions))
                installed.write_bytes(mobile.read_bytes())
                installed.chmod(0o600)
            yield profile, identity, keychain
        finally:
            cleanup_errors = []
            for path, original, permissions in restored:
                try:
                    if original is None:
                        path.unlink(missing_ok=True)
                    else:
                        path.write_bytes(original)
                        path.chmod(permissions)
                except OSError:
                    cleanup_errors.append("provisioning profile restoration")
            if search_changed:
                if subprocess.run(["security", "list-keychains", "-d", "user", "-s", *original_search], capture_output=True).returncode:
                    cleanup_errors.append("keychain search restoration")
            if keychain_created:
                if subprocess.run(["security", "delete-keychain", str(keychain)], capture_output=True).returncode:
                    cleanup_errors.append("temporary keychain removal")
            if cleanup_errors:
                raise BuildError("Signing cleanup failed: " + ", ".join(cleanup_errors) + ". Use a fresh runner.")


def result_summary(output: Path, mode: str, bundle: str, **details) -> None:
    payload = {"mode": mode, "bundle_id": bundle,
               "completed_at": datetime.now(timezone.utc).isoformat(),
               "commit": os.environ.get("GITHUB_SHA", "local"), **details}
    (output / "build-summary.json").write_text(json.dumps(payload, indent=2) + "\n")


def extract_exported_app(archive: zipfile.ZipFile, folder: Path) -> Path:
    """Extract the known application payload for verification after Xcode export."""
    members = [item for item in archive.infolist()
               if item.filename.startswith("Payload/Luqma.app/")]
    if not members or len(members) > 50000 or sum(item.file_size for item in members) > 512 * 1024 * 1024:
        raise BuildError("The exported application payload is missing or unexpectedly large.")
    seen = set()
    for item in members:
        relative = PurePosixPath(item.filename)
        if (item.orig_filename != item.filename
                or "\\" in item.filename or ":" in item.filename or ".." in relative.parts
                or relative.is_absolute() or item.filename in seen
                or relative.as_posix() != item.filename.rstrip("/")
                or item.file_size > 128 * 1024 * 1024
                or (item.external_attr >> 16) & 0o170000 == 0o120000):
            raise BuildError("The exported application payload contains an unsafe path or entry.")
        seen.add(item.filename)
        target = folder.joinpath(*relative.parts)
        if item.is_dir():
            target.mkdir(parents=True, exist_ok=True)
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            with archive.open(item) as source, target.open("xb") as destination:
                shutil.copyfileobj(source, destination)
            permissions = (item.external_attr >> 16) & 0o777
            if permissions:
                target.chmod(permissions)
    return folder / "Payload/Luqma.app"


def prepare_sideload(app: Path, output: Path, bundle: str) -> Path:
    """Package a device build for re-signing by AltStore on the user's computer.

    Ad-hoc hashes preserve requested entitlements for the re-signer. They are
    not an Apple developer signature and do not authorize installation.
    """
    if not app.is_dir():
        raise BuildError("The device build did not produce Luqma.app.")
    try:
        info = plistlib.loads((app / "Info.plist").read_bytes())
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        raise BuildError("The device build has no valid Info.plist.") from error
    if not isinstance(info, dict) or info.get("CFBundleIdentifier") != bundle:
        raise BuildError("The device application identifier does not match BUNDLE_ID.")
    if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
        raise BuildError("Only an iPhoneOS device app can be packaged for sideloading; a simulator app cannot.")
    executable = info.get("CFBundleExecutable", "")
    if not isinstance(executable, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", executable) or not (app / executable).is_file():
        raise BuildError("The device application executable is missing or invalid.")
    ipa = output / "Luqma-Sideload.ipa"
    with tempfile.TemporaryDirectory(prefix="luqma-payload-", dir=os.environ.get("RUNNER_TEMP")) as folder:
        payload = Path(folder) / "Payload"
        payload.mkdir()
        staged = payload / "Luqma.app"
        shutil.copytree(app, staged, symlinks=True)
        frameworks = staged / "Frameworks"
        if frameworks.is_dir():
            for framework in sorted(frameworks.iterdir()):
                if framework.suffix in (".framework", ".dylib"):
                    run(["codesign", "--force", "--sign", "-", str(framework)], output / ("sideload-" + framework.name + ".log"))
        run(["codesign", "--force", "--sign", "-", "--entitlements",
             str(ROOT / "Luqma/Luqma.entitlements"), str(staged)], output / "sideload-local-signature.log")
        run(["codesign", "--verify", "--deep", "--strict", str(staged)], output / "sideload-verify.log")
        run(["ditto", "-c", "-k", "--keepParent", str(payload), str(ipa)], output / "sideload-package.log")
    if not ipa.is_file() or not ipa.stat().st_size:
        raise BuildError("Packaging did not produce a nonempty sideload IPA.")
    with zipfile.ZipFile(ipa) as archive:
        if "Payload/Luqma.app/Info.plist" not in archive.namelist():
            raise BuildError("The sideload IPA has no application payload.")
    return ipa


def build(mode: str, output: Path) -> None:
    require_mac(26 if mode == "app-store" else 16)
    if output.exists():
        raise BuildError("The output directory already exists. Choose a new output path to avoid mixing builds.")
    output.mkdir(parents=True)
    bundle = os.environ.get("BUNDLE_ID", "") or "app.luqma.diary"
    team = os.environ.get("APPLE_TEAM_ID", "")
    number = os.environ.get("BUILD_NUMBER", "1") or "1"
    if not re.fullmatch(r"[1-9][0-9]{0,8}", number):
        raise BuildError("BUILD_NUMBER must be a positive integer with at most nine digits.")
    if mode in ("ad-hoc", "app-store"):
        validate_identifiers(team, bundle)
    elif not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", bundle):
        raise BuildError("BUNDLE_ID is invalid.")
    run(["swift", "test", "-j", "2"], output / "core-tests.log")
    run(["python3", "-m", "unittest", "discover", "-s", "BuildTests", "-v"], output / "build-tests.log")
    packages = output / "Packages"
    common = ["xcodebuild", "-project", "Luqma.xcodeproj", "-scheme", "Luqma",
              "-clonedSourcePackagesDirPath", str(packages), "-disableAutomaticPackageResolution"]
    # Resolve the exact ORT version before locking resolution for build commands.
    run(["xcodebuild", "-resolvePackageDependencies", "-project", "Luqma.xcodeproj",
         "-scheme", "Luqma", "-clonedSourcePackagesDirPath", str(packages)], output / "packages.log")
    apply_vision_compat(packages)
    settings = [f"PRODUCT_BUNDLE_IDENTIFIER={bundle}", f"CURRENT_PROJECT_VERSION={number}"]
    if mode == "sideload":
        run(common + ["-destination", "generic/platform=iOS", "-configuration", "Release",
                      "-derivedDataPath", str(output / "device-derived"),
                      "-resultBundlePath", str(output / "device.xcresult"),
                      "CODE_SIGNING_ALLOWED=NO", *settings, "build"], output / "device.log")
        app = output / "device-derived/Build/Products/Release-iphoneos/Luqma.app"
        apply_vision_compat(packages, verify_only=True)
        prepare_sideload(app, output, bundle)
        (output / "READ-ME.txt").write_text("Luqma-Sideload.ipa is an iPhoneOS build with local ad-hoc code-signing hashes, not an Apple developer signature. It has no Apple provisioning profile and cannot install directly. Apple Health is read-only and requires a re-signing process and provisioning profile that authorize com.apple.developer.healthkit for the final installed identifier; preserving an entitlement string alone does not grant access. Apple's current capability matrix lists HealthKit for free Apple Developer accounts, but Personal Team profiles expire after 7 days and re-signer compatibility must be verified. Use Xcode automatic signing for Personal Team device testing, or a properly provisioned Apple distribution export. Consent and data retrieval still require physical-device validation. No Apple account was accessed and no store upload was performed.\n")
        result_summary(output, mode, bundle, signed=False, apple_signed=False,
                       requires_personal_resigning=True, uploaded=False)
        return
    if mode == "check":
        for name, destination, configuration in (
                ("simulator", "generic/platform=iOS Simulator", "Debug"),
                ("device", "generic/platform=iOS", "Release")):
            run(common + ["-destination", destination, "-configuration", configuration,
                          "-derivedDataPath", str(output / (name + "-derived")),
                          "-resultBundlePath", str(output / (name + ".xcresult")),
                          "CODE_SIGNING_ALLOWED=NO", *settings, "build"], output / (name + ".log"))
        app = output / "simulator-derived/Build/Products/Debug-iphonesimulator/Luqma.app"
        apply_vision_compat(packages, verify_only=True)
        if not app.is_dir():
            raise BuildError("The simulator build did not produce Luqma.app.")
        run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app),
             str(output / "Luqma-Simulator.zip")], output / "simulator-zip.log")
        (output / "READ-ME.txt").write_text("SDK checks completed. Luqma-Simulator.zip is for the Mac iPhone Simulator only; it cannot install on an iPhone. No IPA was produced.\n")
        result_summary(output, mode, bundle, sdk_builds=["iOS Simulator", "iOS device"], signed=False)
        return
    with installed_signing(mode, team, bundle) as (profile, identity, keychain):
        archive = output / "Luqma.xcarchive"
        export_plist = output / "ExportOptions.plist"
        export_plist.write_bytes(plistlib.dumps(profile.export_options(identity)))
        run(common + ["-destination", "generic/platform=iOS", "-configuration", "Release",
                      "-archivePath", str(archive), "-derivedDataPath", str(output / "release-derived"),
                      "-resultBundlePath", str(output / "archive.xcresult"),
                      "CODE_SIGN_STYLE=Manual", f"DEVELOPMENT_TEAM={team}",
                      f"PROVISIONING_PROFILE_SPECIFIER={profile.uuid}", f"CODE_SIGN_IDENTITY={identity}",
                      "OTHER_CODE_SIGN_FLAGS=--keychain " + shlex.quote(str(keychain)), *settings, "archive"], output / "archive.log")
        run(["xcodebuild", "-exportArchive", "-archivePath", str(archive),
             "-exportPath", str(output / "export"), "-exportOptionsPlist", str(export_plist)], output / "export.log")
        exported = list((output / "export").glob("*.ipa"))
        if len(exported) != 1 or exported[0].stat().st_size == 0:
            raise BuildError("Xcode did not export exactly one nonempty IPA.")
        app = archive / "Products/Applications/Luqma.app"
        apply_vision_compat(packages, verify_only=True)
        run(["codesign", "--verify", "--deep", "--strict", str(app)], output / "signature.log")
        # Check the exported IPA's identifier/profile too: export can re-sign an archive.
        try:
            with zipfile.ZipFile(exported[0]) as ipa:
                plist_name = "Payload/Luqma.app/Info.plist"
                info = plistlib.loads(ipa.read(plist_name))
                ipa.getinfo("Payload/Luqma.app/embedded.mobileprovision")
                if info.get("CFBundleIdentifier") != bundle:
                    raise BuildError("The exported IPA has a different bundle identifier.")
                with tempfile.TemporaryDirectory(prefix="luqma-ipa-", dir=os.environ.get("RUNNER_TEMP")) as folder:
                    exported_app = extract_exported_app(ipa, Path(folder))
                    embedded_path = exported_app / "embedded.mobileprovision"
                    embedded_path.chmod(0o600)
                    decoded = private_command(["security", "cms", "-D", "-i", str(embedded_path)], "Exported profile decoding")
                    exported_profile = validate_profile(decoded, team, bundle, mode)
                    if exported_profile.uuid != profile.uuid or identity not in exported_profile.certificates:
                        raise BuildError("The exported IPA uses a different signing profile or certificate.")
                    private_command(["codesign", "--verify", "--deep", "--strict", str(exported_app)],
                                    "Exported application signature verification")
                    claims = private_command(["codesign", "--display", "--entitlements", "-", "--xml", str(exported_app)],
                                             "Exported signing entitlement verification")
                    validate_signed_entitlements(claims, exported_profile)
                    certificate_prefix = Path(folder) / "exported-signer-"
                    private_command(["codesign", "--display", "--extract-certificates", str(certificate_prefix), str(exported_app)],
                                    "Exported signing certificate verification")
                    leaf = Path(str(certificate_prefix) + "0")
                    if not leaf.is_file() or hashlib.sha1(leaf.read_bytes()).hexdigest().upper() != identity:
                        raise BuildError("The exported application's actual signing certificate differs from the validated certificate.")
        except (zipfile.BadZipFile, KeyError, plistlib.InvalidFileException) as error:
            raise BuildError("The exported IPA is missing valid application/signing metadata.") from error
        shutil.copyfile(exported[0], output / "Luqma.ipa")
        result_summary(output, mode, bundle, signed=True, uploaded=False,
                       export_method=profile.method, profile_expires=profile.expires.isoformat(),
                       registered_device_count=profile.device_count,
                       exported_signature_verified=True,
                       exported_requested_entitlements_verified=True)
        instruction = ("Ad Hoc IPA: install only on iPhones included in the provisioning profile.\n"
                       if mode == "ad-hoc" else
                       "App Store Connect IPA: upload through your Apple distribution account for TestFlight/App Store. No upload was performed. This IPA is not for direct sideloading.\n")
        (output / "READ-ME.txt").write_text(instruction)


def interrupted(signum, _frame):
    raise SystemExit(128 + signum)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("check", "sideload", "ad-hoc", "app-store"))
    parser.add_argument("--output", type=Path, default=ROOT / "BuildOutput")
    arguments = parser.parse_args()
    signal.signal(signal.SIGTERM, interrupted)
    try:
        build(arguments.mode, arguments.output.resolve())
    except BuildError as error:
        print("Luqma build:", str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
