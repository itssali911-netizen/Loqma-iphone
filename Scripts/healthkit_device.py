#!/usr/bin/env python3
"""Official Xcode development signing and inspection of the final iPhone app.

Uses an Apple account already configured by the person in Xcode. No Apple ID
password is accepted, no entitlement is stripped, and no local-hash IPA is made.
Private Xcode/device diagnostics stay outside public CI artifacts.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import zipfile

from build_ios import (ROOT, BuildError, extract_exported_app, private_command,
                       public_environment, require_mac)
from signing import validate_identifiers, validate_profile, validate_signed_entitlements
from vision_compat import apply_vision_compat

BUNDLE = 'app.luqma.diary'


def private_json(path: Path, value: dict) -> None:
    with path.open('x', encoding='utf8') as stream:
        path.chmod(0o600)
        json.dump(value, stream, indent=2)
        stream.write('\n')


def private_run(arguments: list[str], log: Path) -> None:
    with log.open('xb') as stream:
        log.chmod(0o600)
        result = subprocess.run(arguments, cwd=ROOT, env=public_environment(),
                                stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode:
        raise BuildError('Xcode/device command failed. Review the private local log '+log.name+
                         '; no signed-build or installation success is claimed.')


def selected_device(value: str) -> str:
    if not re.fullmatch(r'[A-Za-z0-9-]{16,80}', value):
        raise BuildError('Provide the physical iPhone UDID from Xcode Devices and Simulators, not a device name.')
    return value


def inspect_app(app: Path, bundle: str, team: str | None = None,
                device: str | None = None) -> dict:
    """Verify native signature + Apple trust + profile + actual signed claims.

    Profile decoding alone is not signature verification. Apple platform trust
    and certificate policy checks are mandatory here, before installation.
    """
    try:
        info = plistlib.loads((app/'Info.plist').read_bytes())
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        raise BuildError('A readable, built iPhone application Info.plist is required.') from error
    if not isinstance(info, dict):
        raise BuildError('The built application Info.plist must be a dictionary.')
    if info.get('CFBundleSupportedPlatforms') != ['iPhoneOS']:
        raise BuildError('A real iPhoneOS app is required; a Simulator app cannot verify iPhone signing.')
    if info.get('CFBundleIdentifier') != bundle:
        raise BuildError('The signed app changes the expected installed Bundle Identifier; stop before risking local data.')
    if not info.get('NSHealthShareUsageDescription'):
        raise BuildError('The built app is missing its Health read purpose description.')
    mobile = app/'embedded.mobileprovision'
    if not mobile.is_file():
        raise BuildError('No embedded Apple provisioning profile: this package cannot verify provisioned HealthKit access. Do not install it as a signing fix.')
    decoded = private_command(['security', 'cms', '-D', '-i', str(mobile)], 'Apple provisioning profile decoding')
    try:
        raw = plistlib.loads(decoded)
        teams = raw.get('TeamIdentifier', [])
        mode = ('development' if raw.get('Entitlements', {}).get('get-task-allow') is True else
                'ad-hoc' if 'ProvisionedDevices' in raw else 'app-store')
    except (ValueError, TypeError, AttributeError, plistlib.InvalidFileException) as error:
        raise BuildError('The embedded provisioning profile is malformed.') from error
    if team is None:
        if not isinstance(teams, list) or len(teams) != 1 or not isinstance(teams[0], str):
            raise BuildError('The embedded profile has no unambiguous Apple team.')
        team = teams[0]
    profile = validate_profile(decoded, team, bundle, mode)
    if device is not None and selected_device(device) not in raw.get('ProvisionedDevices', []):
        raise BuildError('The selected physical iPhone is not authorized by this profile. No installation was attempted.')
    # A locally ad-hoc signed executable or a non-Apple certificate fails the
    # Apple anchor requirement even if a copied profile happens to be present.
    private_command(['codesign', '--verify', '--deep', '--strict', '-R',
                     'anchor apple generic', str(app)], 'Apple-anchored application signature verification')
    claims = private_command(['codesign', '--display', '--entitlements', '-', '--xml', str(app)],
                             'Actual executable entitlement inspection')
    validate_signed_entitlements(claims, profile)
    with tempfile.TemporaryDirectory(prefix='luqma-signer-') as folder:
        prefix = Path(folder)/'signer-'
        private_command(['codesign', '--display', '--extract-certificates', str(prefix), str(app)],
                        'Actual signing certificate extraction')
        certificates = sorted(Path(folder).glob('signer-*'))
        leaf = Path(str(prefix)+'0')
        if not leaf.is_file():
            raise BuildError('The executable has no Apple signing certificate; local hash signing is insufficient.')
        leaf_bytes = leaf.read_bytes()
        if hashlib.sha1(leaf_bytes).hexdigest().upper() not in profile.certificates:
            raise BuildError('The actual signer is not authorized by the embedded provisioning profile.')
        arguments = ['security', 'verify-cert', '-p', 'codeSign']
        for certificate in certificates:
            arguments += ['-c', str(certificate)]
        private_command(arguments, 'Signing certificate trust and validity verification')
        fingerprint = hashlib.sha256(leaf_bytes).hexdigest()
    # CMS decoding exposes profile claims, not independent proof that Apple
    # authorized that CMS/DER profile. iOS validates the provisioning profile
    # during installation; never turn a plist comparison into an Apple grant.
    return dict(status='app_signature_and_profile_claims_verified', bundle_identifier=bundle,
                version=info.get('CFBundleShortVersionString'), build=info.get('CFBundleVersion'),
                signing_team=profile.team, signing_certificate_sha256=fingerprint,
                profile_method=profile.method, profile_expires=profile.expires.isoformat(),
                profile_healthkit_declared=True, actual_signed_healthkit_verified=True,
                profile_apple_authorization_verified=False,
                profile_verification_limitation='Decoded profile claims were compared; independent Apple CMS/DER authentication is not claimed. iOS must validate provisioning on installation.',
                apple_anchor_verified=True, certificate_trust_verified=True,
                selected_device_authorized=device is not None,
                installation_verified=False, launch_command_succeeded=False,
                physical_health_authorization_verified=False, real_health_data_retrieval_verified=False)


@contextmanager
def application_input(app: Path | None, ipa: Path | None):
    if app is not None:
        yield app
        return
    if ipa is None:
        raise BuildError('Specify --app or --ipa for the final post-signing application.')
    with tempfile.TemporaryDirectory(prefix='luqma-final-ipa-') as folder:
        try:
            with zipfile.ZipFile(ipa) as archive:
                yield extract_exported_app(archive, Path(folder))
        except (OSError, zipfile.BadZipFile, KeyError) as error:
            raise BuildError('The final IPA could not be safely inspected.') from error


def device_command(arguments: list[str], output: Path, label: str) -> None:
    result_path = output/(label+'.json')
    private_run(['xcrun', 'devicectl', *arguments, '--json-output', str(result_path)], output/(label+'.private.log'))
    try:
        result = json.loads(result_path.read_text('utf8'))
    except (OSError, ValueError) as error:
        raise BuildError('No valid native device result was returned; success is not verified.') from error
    result_path.chmod(0o600)
    if (not isinstance(result, dict) or not isinstance(result.get('info'), dict) or
            result['info'].get('outcome') != 'success'):
        raise BuildError('The native device command did not confirm success.')


def development_build(team: str, bundle: str, device: str, number: str,
                      output: Path, install: bool, evidence: dict | None = None) -> dict:
    require_mac()
    validate_identifiers(team, bundle)
    selected_device(device)
    if not re.fullmatch(r'[1-9][0-9]{0,8}', number):
        raise BuildError('Build number must be a positive integer.')
    packages = output/'Packages'
    private_run(['xcodebuild', '-resolvePackageDependencies', '-project', 'Luqma.xcodeproj',
                 '-scheme', 'Luqma', '-clonedSourcePackagesDirPath', str(packages)], output/'packages.private.log')
    apply_vision_compat(packages)
    # Xcode uses the person's existing signed-in account. It may create a real
    # development profile/register the selected iPhone; no credentials are taken
    # by this script and no entitlement is replaced to force an install.
    private_run(['xcodebuild', '-project', 'Luqma.xcodeproj', '-scheme', 'Luqma',
                 '-clonedSourcePackagesDirPath', str(packages), '-disableAutomaticPackageResolution',
                 '-destination', 'id='+device, '-configuration', 'Debug',
                 '-derivedDataPath', str(output/'DerivedData'), '-allowProvisioningUpdates',
                 '-allowProvisioningDeviceRegistration', 'CODE_SIGN_STYLE=Automatic',
                 'CODE_SIGNING_ALLOWED=YES', 'DEVELOPMENT_TEAM='+team,
                 'PRODUCT_BUNDLE_IDENTIFIER='+bundle, 'CURRENT_PROJECT_VERSION='+number,
                 'build'], output/'development-build.private.log')
    apply_vision_compat(packages, verify_only=True)
    app = output/'DerivedData/Build/Products/Debug-iphoneos/Luqma.app'
    report = inspect_app(app, bundle, team, device)
    if evidence is not None:
        evidence.update(report)
    report['ipa_produced'] = False
    report['development_app'] = str(app)
    if install:
        device_command(['device', 'install', 'app', '--device', device, str(app)], output, 'install')
        report['installation_verified'] = True
        report['profile_apple_authorization_verified'] = True
        if evidence is not None:
            evidence['installation_verified'] = True
            evidence['profile_apple_authorization_verified'] = True
        # Starting a process is not proof of Health read permission or stability.
        device_command(['device', 'process', 'launch', '--device', device, bundle], output, 'launch')
        report['launch_command_succeeded'] = True
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('inspect', 'build'))
    inputs = parser.add_mutually_exclusive_group()
    inputs.add_argument('--app', type=Path)
    inputs.add_argument('--ipa', type=Path)
    parser.add_argument('--bundle-id', default=BUNDLE)
    parser.add_argument('--team', default=os.environ.get('APPLE_TEAM_ID'))
    parser.add_argument('--device', help='Physical iPhone UDID from Xcode; never published in reports')
    parser.add_argument('--build-number', default=os.environ.get('BUILD_NUMBER', '119'))
    parser.add_argument('--install', action='store_true', help='Install and launch only after every actual signing check passes')
    parser.add_argument('--output', type=Path, default=ROOT/'HealthSigning/device-check')
    args = parser.parse_args()
    if args.output.exists():
        parser.error('Choose a fresh output directory; previous signing evidence is never overwritten.')
    args.output.mkdir(parents=True, mode=0o700)
    args.output.chmod(0o700)
    report = dict(status='not_verified', ipa_produced=False, installation_verified=False,
                  physical_health_authorization_verified=False, real_health_data_retrieval_verified=False,
                  checked_at=datetime.now(timezone.utc).isoformat())
    try:
        require_mac()
        if args.mode == 'build':
            if not args.team or not args.device or args.app or args.ipa:
                raise BuildError('Development build needs --team and --device with an Apple account already configured in Xcode.')
            report.update(development_build(args.team, args.bundle_id, args.device, args.build_number,
                                            args.output.resolve(), args.install, report))
        else:
            if args.install:
                raise BuildError('--install is available only for a newly verified development build, not an unknown IPA.')
            with application_input(args.app, args.ipa) as app:
                report.update(inspect_app(app, args.bundle_id, args.team, args.device))
        print('App signature and HealthKit claims checked. iOS installation must validate provisioning; Health permission and real data remain unverified.')
        return 0
    except (BuildError, OSError) as error:
        report['status'] = 'not_verified'
        report['reason'] = str(error)
        print('HealthKit signing: '+str(error), file=sys.stderr)
        return 1
    finally:
        private_json(args.output/'signing-report.json', report)


if __name__ == '__main__':
    sys.exit(main())
