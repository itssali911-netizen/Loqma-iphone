#!/usr/bin/env python3
"""Package only a measured, locally hash-signed device IPA; never grant entitlements."""
from __future__ import annotations
import argparse
from copy import deepcopy
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VERSION, BUILD, BUNDLE = '2.9', '120', 'app.luqma.diary'
IPA_NAME = f'LUQMA-HealthKit-Resignable-v{VERSION}-build{BUILD}.ipa'
ZIP_NAME = f'LUQMA-HealthKit-Release-v{VERSION}-build{BUILD}.zip'
HEALTH = 'com.apple.developer.healthkit'

def digest(path: Path) -> str:
    with path.open('rb') as stream:
        value = hashlib.sha256()
        for block in iter(lambda: stream.read(1024*1024), b''): value.update(block)
    return value.hexdigest()

def validate_resignable_report(report: dict, ipa: Path) -> None:
    expected = {'BuildIntegrity':'PASS', 'CodeSignature':'PASS', 'ProvisioningProfile':'ABSENT',
                'HealthKitEntitlement':'PRESENT', 'HealthKitProfileAuthorization':'NOTVERIFIED',
                'BackgroundDelivery':'UNSUPPORTED', 'DeviceInstallation':'NOTTESTED', 'RealHealthData':'NOTTESTED'}
    if report.get('statuses') != expected or report.get('exit_code') != 2:
        raise ValueError('Release requires the exact measured device/local-hash signing status; Apple signing is incomplete.')
    signing = report.get('evidence', {}).get('signing', {})
    if (signing.get('signing_kind') != 'ADHOC_HASH' or signing.get('apple_identity_verified') is not False
            or signing.get('profile_present') is not False):
        raise ValueError('Do not publish a personal Apple-signed or unmeasured package as this re-signable candidate.')
    if (report.get('bundle_identifier'),report.get('version'),str(report.get('build'))) != (BUNDLE,VERSION,BUILD):
        raise ValueError('Unexpected bundle, version, or build.')
    if not ipa.is_file() or report.get('ipa_sha256') != digest(ipa) or report.get('ipa_bytes') != ipa.stat().st_size:
        raise ValueError('IPA bytes differ from the actually inspected package.')

def test_counts(folder: Path) -> dict:
    core = (folder/'core-tests.log').read_text(errors='replace')
    build = (folder/'build-tests.log').read_text(errors='replace')
    counts = re.findall(r'Executed (\d+) tests?, with 0 failures', core)
    ran = re.search(r'Ran (\d+) tests? in ', build)
    if not counts or not ran or not re.search(r'^OK(?: \(skipped=\d+\))?\s*$', build, re.M):
        raise ValueError('Actual passing Core and BuildTests logs are required.')
    for file in ('device.log','simulator.log'):
        if '** BUILD SUCCEEDED **' not in (folder/file).read_text(errors='replace'):
            raise ValueError('Both actual SDK builds must succeed.')
    skipped = re.search(r'^OK \(skipped=(\d+)\)', build, re.M)
    return {'core_tests':max(map(int,counts)), 'build_tests':int(ran.group(1)),
            'build_tests_skipped':int(skipped.group(1)) if skipped else 0}

def package(ipa: Path, inspection: Path, build_output: Path, ui_report: Path, output: Path) -> None:
    report = json.loads(inspection.read_text('utf8')); validate_resignable_report(report, ipa)
    counts = test_counts(build_output)
    summary = json.loads((build_output/'build-summary.json').read_text('utf8'))
    ui = json.loads(ui_report.read_text('utf8'))
    commit = os.environ.get('GITHUB_SHA', '')
    if not re.fullmatch('[0-9a-f]{40}',commit) or summary.get('commit') != commit or ui.get('commit') != commit:
        raise ValueError('Build/UI evidence must refer to this exact source commit.')
    if (summary.get('mode') != 'check' or summary.get('bundle_id') != BUNDLE or
            ui.get('status') != 'passed' or ui.get('test_status') != 'passed' or
            ui.get('health_samples_injected') is not False or ui.get('physical_iphone_verified') is not False or
            set(ui.get('passed_tests',[])) != set(ui.get('required_tests',[])) or len(ui.get('passed_tests',[])) != 3):
        raise ValueError('Actual native empty-Simulator UI evidence is missing or inconsistent.')
    if output.exists(): raise ValueError('A fresh release output directory is required.')
    output.mkdir(parents=True)
    shutil.copy2(ipa, output/IPA_NAME)
    shutil.copy2(inspection,output/'signing-report.json')
    for path in sorted((ROOT/'Docs/HealthKitRelease').glob('*.md')):
        shutil.copy2(path,output/path.name)
    tools = output/'Tools'; tools.mkdir()
    for name in ('verify-healthkit-signing.sh','verify_healthkit_signing.py','build_ios.py','signing.py','vision_compat.py'):
        shutil.copy2(ROOT/'Scripts'/name, tools/name)
    (tools/'verify-healthkit-signing.sh').chmod(0o755)
    (output/'HealthKit-Entitlements-Example.plist').write_bytes(plistlib.dumps({HEALTH:True}))
    evidence = output/'Evidence'; evidence.mkdir()
    for name in ('build-summary.json','toolchain.json','core-tests.log','build-tests.log','health-service-probe.log'):
        source = build_output/name
        if not source.is_file(): raise ValueError('Missing build evidence: '+name)
        shutil.copy2(source,evidence/name)
    shutil.copy2(ui_report,evidence/'simulator-ui-report.json')
    captures = evidence/'Simulator-Screenshots'; captures.mkdir()
    sources = list((ui_report.parent/'captures').glob('*.png'))
    if len(sources) < 10: raise ValueError('Actual UI screenshots are incomplete.')
    for source in sources: shutil.copy2(source,captures/source.name)
    state = {'commit':commit,'version':VERSION,'build':BUILD,'bundle_identifier':BUNDLE,'ipa_file':IPA_NAME,
             'ipa_sha256':digest(ipa),'signing_kind':'ADHOC_HASH','apple_signed':False,
             'embedded_apple_profile':False,'requires_resigning':True,
             'physical_installation':'NOTTESTED','real_health_data':'NOTTESTED',
             'native_permission_sheet_in_simulator':ui.get('native_permission_flow_verified',False),
             'authorization_outcome_in_simulator':ui.get('authorization_outcome'),**counts}
    (output/'release-manifest.json').write_text(json.dumps(state,indent=2)+'\n',encoding='utf8')
    rows = '\n'.join(f'| {key} | {value} |' for key,value in report['statuses'].items())
    tested = (f'\n\n## Measured build evidence\n\nSource: `{commit}`. iPhoneOS Release and Simulator Debug: PASS. '
              f'Core: {counts["core_tests"]} passed. BuildTests: {counts["build_tests"]} run, '
              f'{counts["build_tests_skipped"]} skipped. Native empty-Simulator UI: 3 passed. '
              f'Authorization outcome: `{ui.get("authorization_outcome")}`. '
              f'Native sheet observed in Simulator: `{ui.get("native_permission_flow_verified",False)}`.\n\n'
              '| Inspection | Result |\n|---|---|\n'+rows+'\n\n'
              'CodeSignature PASS verifies local resource hashes, not an Apple identity or installation permission. '
              'No Health measurements or permissions were fabricated. Simulator screenshots are not physical-device evidence.\n')
    with (output/'HEALTHKIT-TEST-REPORT.md').open('a',encoding='utf8') as file:file.write(tested)
    with (output/'RELEASE-NOTES.md').open('a',encoding='utf8') as file:file.write(tested)
    inner_sums = ''.join(f'{digest(path)}  {path.relative_to(output).as_posix()}\n' for path in sorted(output.rglob('*')) if path.is_file())
    (output/'SHA256SUMS.txt').write_text(inner_sums,encoding='utf8')
    # Bundle a self-contained handoff; no private credentials/profiles are copied.
    with zipfile.ZipFile(output/ZIP_NAME,'x',zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(output.rglob('*')):
            if path.is_file() and path.name != ZIP_NAME:archive.write(path,path.relative_to(output).as_posix())
    sums = ''.join(f'{digest(path)}  {path.relative_to(output).as_posix()}\n' for path in sorted(output.rglob('*')) if path.is_file() and path.name != 'SHA256SUMS')
    (output/'SHA256SUMS').write_text(sums,encoding='utf8')
    print(json.dumps(state,indent=2))

class ReleaseGateTests(unittest.TestCase):
    def setUp(self):
        self.folder=tempfile.TemporaryDirectory();self.addCleanup(self.folder.cleanup)
        self.ipa=Path(self.folder.name)/'test.ipa';self.ipa.write_bytes(b'fixture only; not a real IPA')
        self.report={'statuses':{'BuildIntegrity':'PASS','CodeSignature':'PASS','ProvisioningProfile':'ABSENT',
            'HealthKitEntitlement':'PRESENT','HealthKitProfileAuthorization':'NOTVERIFIED','BackgroundDelivery':'UNSUPPORTED',
            'DeviceInstallation':'NOTTESTED','RealHealthData':'NOTTESTED'}, 'exit_code':2,
            'evidence':{'signing':{'signing_kind':'ADHOC_HASH','apple_identity_verified':False,'profile_present':False}},
            'bundle_identifier':BUNDLE,'version':VERSION,'build':BUILD,'ipa_sha256':digest(self.ipa),'ipa_bytes':self.ipa.stat().st_size}
    def test_expected_incomplete_apple_signature_passes_candidate_gate(self):validate_resignable_report(self.report,self.ipa)
    def test_each_unexpected_status_is_rejected(self):
        for key in self.report['statuses']:
            value=deepcopy(self.report);value['statuses'][key]='UNMEASURED'
            with self.subTest(key=key),self.assertRaises(ValueError):validate_resignable_report(value,self.ipa)
    def test_changed_bytes_and_personal_signature_are_rejected(self):
        value=deepcopy(self.report);value['evidence']['signing']['apple_identity_verified']=True
        with self.assertRaises(ValueError):validate_resignable_report(value,self.ipa)
        self.ipa.write_bytes(b'changed')
        with self.assertRaises(ValueError):validate_resignable_report(self.report,self.ipa)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--self-test',action='store_true')
    for name in ('ipa','inspection','build-output','ui-report','output'):parser.add_argument('--'+name,type=Path)
    args=parser.parse_args()
    if args.self_test:
        result=unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(ReleaseGateTests))
        return 0 if result.wasSuccessful() else 1
    if any(getattr(args,name) is None for name in ('ipa','inspection','build_output','ui_report','output')):parser.error('All input paths are required.')
    package(args.ipa,args.inspection,args.build_output,args.ui_report,args.output);return 0
if __name__=='__main__':raise SystemExit(main())
