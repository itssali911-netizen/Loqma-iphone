#!/usr/bin/env python3
"""Real HealthKit UI evidence on one caller-created, empty iOS Simulator.

No Health samples, permission responses or application state are injected.
Simulator ad-hoc signing enables the real native entitlement for this SDK test;
it is explicitly not Apple-provisioned device/IPA distribution signing.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import uuid

from build_ios import BuildError, public_environment, require_mac
from simulator_support import prepare_created_simulator
from ui_preview import command, png_details, select_runtime, validate_app

ROOT=Path(__file__).resolve().parents[1]
BUNDLE='app.luqma.diary'
TESTS=('testARealNativeAuthorizationOrExplicitUnavailableKeepsGoals',
       'testBEnglishSettingsAndProgressAreUsable','testCArabicSettingsAndProgressAreUsable')
AUTH_OUTCOMES={'native_sheet_declined','native_sheet_completed_without_grant_claim',
               'explicit_unavailable','request_completed_without_observed_sheet'}
REQUIRED_CAPTURES={f'health-{language}-{screen}' for language in ('en','ar') for screen in ('settings','overview','progress')}
REQUIRED_CAPTURES|={'health-en-before-authorization','health-en-after-authorization'}
SIGNING_INPUTS=('BUILD_CERTIFICATE_BASE64','P12_PASSWORD','BUILD_PROVISION_PROFILE_BASE64','APPLE_TEAM_ID')
SIGNING_STEPS=[
    'Use an Apple Developer team with HealthKit enabled for the explicit app.luqma.diary App ID; regenerate its distribution profile.',
    'Provide matching BUILD_CERTIFICATE_BASE64, P12_PASSWORD and BUILD_PROVISION_PROFILE_BASE64 secrets, plus APPLE_TEAM_ID. Keep their values private.',
    'On macOS with Xcode selected, run: python3 Scripts/build_ios.py check --output HealthSDKCheck',
    'For registered iPhones, run: python3 Scripts/build_ios.py ad-hoc --output HealthSigned (with BUILD_NUMBER, APPLE_TEAM_ID, BUNDLE_ID and signing inputs configured).',
    'For an App Store distribution profile instead, run: python3 Scripts/build_ios.py app-store --output HealthStoreExport. No upload or publication is performed.',
    'The existing build script must verify the exported application signature and requested HealthKit entitlements before a signed IPA can be delivered.'
]

def save_json(path:Path,value:dict)->None:
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,indent=2)+'\n',encoding='utf8')

def github_output(name:str,value:str)->None:
    if path:=os.environ.get('GITHUB_OUTPUT'):
        with open(path,'a',encoding='utf8') as stream:stream.write(name+'='+value+'\n')

def signing_status()->None:
    missing=[name for name in SIGNING_INPUTS if not os.environ.get(name,'').strip()]
    status=dict(status='missing_credentials' if missing else 'ready_for_verified_export',
                signed_ipa_produced=False,bundle_identifier=BUNDLE,missing_input_names=missing,
                healthkit_profile_verified=False,remaining_steps=SIGNING_STEPS)
    save_json(ROOT/'HealthSigning/signing-status.json',status)
    github_output('configured','false' if missing else 'true')
    print('Apple signing inputs: '+('not configured; no signed IPA claimed.' if missing else 'configured; a verified export is required.'))

def signed_export()->None:
    require_mac()
    output=ROOT/'BuildSigned'
    status_path=ROOT/'HealthSigning/signing-status.json'
    missing=[name for name in SIGNING_INPUTS if not os.environ.get(name,'').strip()]
    if missing:
        signing_status();github_output('signed_available','false');return
    status=dict(status='not_exported',signed_ipa_produced=False,bundle_identifier=BUNDLE,
                requested_mode='ad-hoc',healthkit_profile_verified=False,remaining_steps=SIGNING_STEPS)
    if output.exists():
        status['reason']='A fresh signing output directory is required; no prior IPA was reused.'
    else:
        environment=os.environ.copy();environment['BUNDLE_ID']=BUNDLE
        # The established signing script owns ephemeral certificate/profile and
        # keychain cleanup. Its private command output is not uploaded or echoed.
        with tempfile.TemporaryFile() as private_log:
            result=subprocess.run([sys.executable,str(ROOT/'Scripts/build_ios.py'),'ad-hoc','--output',str(output)],
                                  cwd=ROOT,env=environment,stdout=private_log,stderr=subprocess.STDOUT)
        if result.returncode:
            status['status']='manual_signing_required'
            status['reason']='Configured inputs did not produce a verified HealthKit-capable Ad Hoc export. A matching profile (or the App Store mode for an App Store profile) is required.'
        else:
            try:
                summary=json.loads((output/'build-summary.json').read_text('utf8'))
                ipa=output/'Luqma.ipa'
                if not (ipa.is_file() and ipa.stat().st_size>0 and summary.get('mode')=='ad-hoc' and
                        summary.get('exported_signature_verified') is True and summary.get('exported_requested_entitlements_verified') is True):
                    raise ValueError('No independently verified exported IPA')
                status.update(status='signed_export_verified',signed_ipa_produced=True,healthkit_profile_verified=True,
                              file='BuildSigned/Luqma.ipa',sha256=hashlib.sha256(ipa.read_bytes()).hexdigest(),
                              bytes=ipa.stat().st_size,remaining_steps=[])
            except (OSError,ValueError):
                status['status']='manual_signing_required';status['reason']='The expected verified export receipt is unavailable; no signed IPA is claimed.'
    save_json(status_path,status)
    github_output('signed_available','true' if status['signed_ipa_produced'] else 'false')
    print('Apple signing status: '+status['status']+'. No credentials or profile contents were printed.')

def collect_attachments(output:Path,report:dict)->None:
    bundle=output/'healthkit.xcresult'
    if not bundle.exists():return
    directory=output/'test-attachments'
    command(['xcrun','xcresulttool','export','attachments','--path',str(bundle),'--output-path',str(directory)],output,'export-test-attachments',120)
    manifest=json.loads((directory/'manifest.json').read_text('utf8'))
    captures=output/'captures';captures.mkdir(exist_ok=True)
    seen=set()
    for test in manifest:
        for item in test.get('attachments',[]):
            name=item.get('suggestedHumanReadableName','')
            key=next((candidate for candidate in REQUIRED_CAPTURES|{'health-en-native-permission-sheet'} if name.startswith(candidate+'_')),None)
            if key is None:continue
            file_name=item.get('exportedFileName','')
            source=directory/file_name
            if source.resolve().parent!=directory.resolve() or source.suffix.lower()!='.png':
                raise BuildError('Unexpected native test screenshot path')
            if key in seen:raise BuildError('Duplicate native Health capture name')
            target=captures/(key+'.png');shutil.copy2(source,target)
            details=png_details(target)
            if details['near_empty_black_frame']:raise BuildError('A native Health screenshot is near-empty black')
            report['screenshots'].append(dict(screen=key,source='XCTest Simulator screenshot; no UI fixture or Health samples injected',**details))
            seen.add(key)
    report['required_capture_names']=sorted(REQUIRED_CAPTURES)
    report['missing_capture_names']=sorted(REQUIRED_CAPTURES-seen)

def validate()->None:
    require_mac()
    output=ROOT/'HealthValidation'
    if output.exists():raise BuildError('HealthValidation must be a fresh evidence directory')
    output.mkdir()
    derived=ROOT/'BuildOutput/simulator-derived'
    packages=ROOT/'BuildOutput/Packages'
    app=derived/'Build/Products/Debug-iphonesimulator/Luqma.app'
    report=dict(status='running',commit=os.environ.get('GITHUB_SHA','local'),framework='SwiftUI / native HealthKit',
                test_status='not_run',required_tests=list(TESTS),passed_tests=[],screenshots=[],errors=[],
                fresh_simulator=False,existing_user_device_modified=False,health_samples_injected=False,
                physical_iphone_verified=False,physical_data_retrieval_verified=False,read_permission_grant_inferred=False,
                simulator_signing='Local ad-hoc Simulator signature only; not Apple-provisioned device or IPA signing',
                native_permission_flow_verified=False,simulator_data_retrieval='Empty fresh Simulator only; no physical Health readings verified')
    device=None
    try:
        report['prebuilt_app']=validate_app(app,BUNDLE,output)
        inventory=json.loads(command(['xcrun','simctl','list','--json'],output,'inventory'))
        runtime=select_runtime(inventory)
        device=command(['xcrun','simctl','create','Luqma Health '+uuid.uuid4().hex[:8],
                        'com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max',runtime['identifier']],output,'create').strip()
        if re.fullmatch(r'[0-9A-Fa-f-]{36}',device) is None:
            device=None;raise BuildError('Simulator creation returned an invalid identifier')
        report['fresh_simulator']=True;report['simulator_runtime']=runtime['name']
        report['preparation']=prepare_created_simulator(device,lambda args,label,timeout:command(args,output,label,timeout))
        selection=['-only-testing:LuqmaUITests/AppleHealthInteractionTests/'+name for name in TESTS]
        try:
            log=command(['xcodebuild','-project','Luqma.xcodeproj','-scheme','Luqma',
                         '-clonedSourcePackagesDirPath',str(packages),'-disableAutomaticPackageResolution',
                         '-destination','id='+device,'-configuration','Debug','-derivedDataPath',str(derived),
                         '-resultBundlePath',str(output/'healthkit.xcresult'),'-parallel-testing-enabled','NO',*selection,
                         'ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','CODE_SIGNING_ALLOWED=YES','CODE_SIGN_IDENTITY=-',
                         'CURRENT_PROJECT_VERSION='+os.environ.get('BUILD_NUMBER','1'),'test'],output,'native-healthkit-tests',1500)
            report['passed_tests']=[name for name in TESTS if re.search(r"Test Case '.*"+re.escape(name)+r".*' passed",log)]
            if set(report['passed_tests'])!=set(TESTS):raise BuildError('The native run did not execute and pass all required Health tests')
            outcomes=set(re.findall(r'LUQMA_HEALTHKIT_VALIDATION:([a-z_]+)',log))
            observed=outcomes&AUTH_OUTCOMES
            if len(observed)!=1:raise BuildError('Native authorization outcome was not unambiguously recorded')
            outcome=observed.pop();report['authorization_outcome']=outcome
            report['native_permission_flow_verified']=outcome.startswith('native_sheet_')
            report['calorie_target_unchanged']='calorie_target_unchanged' in outcomes
            report['manual_refresh_tapped']='manual_refresh_tapped' in outcomes
            if not report['calorie_target_unchanged']:raise BuildError('Calorie target preservation was not verified')
            if not report['native_permission_flow_verified']:
                report['native_permission_limitation']='No native consent sheet was observed. The actual app showed an explicit issue or a completed check; this does not verify physical-device consent or read access.'
            report['test_status']='passed'
        except BuildError as error:
            report['test_status']='failed';report['errors'].append(str(error))
        # Read only the Simulator signature's public capability receipt, never
        # Health values, app files, secrets or a real user's provisioning profile.
        claims=subprocess.run(['codesign','--display','--entitlements','-','--xml',str(app)],capture_output=True,env=public_environment())
        try:
            values=plistlib.loads(claims.stdout)
            report['simulator_healthkit_entitlement_verified']=values.get('com.apple.developer.healthkit') is True
        except (ValueError,TypeError,plistlib.InvalidFileException):report['simulator_healthkit_entitlement_verified']=False
        if not report['simulator_healthkit_entitlement_verified']:report['errors'].append('The actual Simulator executable does not claim HealthKit')
        collect_attachments(output,report)
        if report.get('missing_capture_names'):report['errors'].append('Required actual Settings/Health/Progress screenshots are missing')
        report['tested_app']=validate_app(app,BUNDLE,output)
        if report['errors']:raise BuildError('; '.join(report['errors']))
        report['status']='passed'
    except BaseException as error:
        report['status']='failed'
        if str(error) not in report['errors']:report['errors'].append(str(error))
        raise
    finally:
        if device:
            for action in ('shutdown','delete'):
                try:command(['xcrun','simctl',action,device],output,'cleanup-'+action,90,allow_failure=True)
                except (BuildError,OSError):report.setdefault('cleanup_warnings',[]).append('Caller-created Simulator cleanup did not finish')
        save_json(output/'report.json',report)

def interrupted(signum,_frame):raise SystemExit(128+signum)

def main()->int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',nargs='?',default='validate',choices=('validate','signing-status','signed-export'))
    args=parser.parse_args();signal.signal(signal.SIGTERM,interrupted)
    try:
        {'validate':validate,'signing-status':signing_status,'signed-export':signed_export}[args.mode]()
    except (BuildError,OSError,ValueError) as error:
        print('HealthKit validation: '+str(error),file=sys.stderr);return 1
    return 0

if __name__=='__main__':sys.exit(main())
