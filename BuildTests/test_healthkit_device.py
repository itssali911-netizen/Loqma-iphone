"""Synthetic signing boundaries, never proof of real Apple signing or Health reads."""
from contextlib import ExitStack
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'Scripts'))
from healthkit_device import (BuildError, application_input, development_build,
                             device_command, inspect_app, private_json, selected_device)
from test_signing import BUNDLE, TEAM, CERTIFICATE, profile_data

DEVICE='00000000-1234567890ABCDEF'


class HealthDeviceSigningTests(unittest.TestCase):
    def setUp(self):
        self.folder=tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        self.app=Path(self.folder.name)/'Luqma.app';self.app.mkdir()
        self.info=dict(CFBundleIdentifier=BUNDLE,CFBundleSupportedPlatforms=['iPhoneOS'],
                       CFBundleShortVersionString='2.9',CFBundleVersion='119',NSHealthShareUsageDescription='Read four Health types')
        self.write_info()
        (self.app/'embedded.mobileprovision').write_bytes(b'synthetic CMS placeholder, not a real Apple signature')
        self.profile=profile_data();self.profile['Entitlements']['get-task-allow']=True
        self.profile['ProvisionedDevices']=[DEVICE]
        self.claims=dict(self.profile['Entitlements'])
        self.calls=[]

    def write_info(self):
        (self.app/'Info.plist').write_bytes(plistlib.dumps(self.info))

    def native(self,args,label):
        self.calls.append(args)
        if args[:3]==['security','cms','-D']:return plistlib.dumps(self.profile)
        if '--entitlements' in args:return plistlib.dumps(self.claims)
        if '--extract-certificates' in args:
            prefix=args[args.index('--extract-certificates')+1]
            Path(prefix+'0').write_bytes(CERTIFICATE)
        return b''

    def inspect(self):
        with patch('healthkit_device.private_command',side_effect=self.native):
            return inspect_app(self.app,BUNDLE,TEAM,DEVICE)

    def test_profile_claims_certificate_apple_anchor_and_trust_all_required(self):
        report=self.inspect()
        self.assertTrue(report['actual_signed_healthkit_verified'])
        self.assertTrue(report['selected_device_authorized'])
        self.assertEqual(report['profile_method'],'debugging')
        self.assertFalse(report['installation_verified'])
        self.assertFalse(report['profile_apple_authorization_verified'])
        self.assertFalse(report['physical_health_authorization_verified'])
        self.assertFalse(report['real_health_data_retrieval_verified'])
        self.assertTrue(any('-R' in a and 'anchor apple generic' in a for a in self.calls))
        self.assertTrue(any(a[:4]==['security','verify-cert','-p','codeSign'] for a in self.calls))
        self.assertNotIn(DEVICE,json.dumps(report))

    def test_unprovisioned_local_hash_ipa_cannot_be_a_signing_fix(self):
        (self.app/'embedded.mobileprovision').unlink()
        with self.assertRaisesRegex(BuildError,'No embedded Apple provisioning'):
            self.inspect()
        self.assertEqual(self.calls,[])

    def test_profile_missing_healthkit_blocks_even_if_claim_string_present(self):
        self.profile['Entitlements'].pop('com.apple.developer.healthkit')
        with self.assertRaisesRegex(BuildError,'requested capability'):
            self.inspect()
        self.assertFalse(any(a[0]=='codesign' for a in self.calls))

    def test_profile_allowlist_does_not_substitute_for_actual_signed_claim(self):
        self.claims.pop('com.apple.developer.healthkit')
        with self.assertRaisesRegex(BuildError,'healthkit'):
            self.inspect()

    def test_expired_profile_is_rejected(self):
        self.profile['ExpirationDate']=(datetime.now(timezone.utc)-timedelta(days=1)).replace(tzinfo=None)
        with self.assertRaisesRegex(BuildError,'expired'):
            self.inspect()

    def test_unregistered_device_is_rejected_before_signature_or_install(self):
        self.profile['ProvisionedDevices']=['another-synthetic-device']
        with self.assertRaisesRegex(BuildError,'not authorized'):
            self.inspect()
        self.assertFalse(any(a[0]=='codesign' for a in self.calls))

    def test_simulator_or_changed_identifier_cannot_verify_iphone_update(self):
        for change in ({'CFBundleSupportedPlatforms':['iPhoneSimulator']},{'CFBundleIdentifier':'changed.bundle'}):
            with self.subTest(change=change):
                old=dict(self.info);self.info.update(change);self.write_info()
                with self.assertRaises(BuildError):self.inspect()
                self.info=old

    def test_actual_certificate_must_match_profile_not_just_valid_claims(self):
        def other_cert(args,label):
            value=self.native(args,label)
            if '--extract-certificates' in args:
                Path(args[args.index('--extract-certificates')+1]+'0').write_bytes(b'another synthetic certificate')
            return value
        with patch('healthkit_device.private_command',side_effect=other_cert):
            with self.assertRaisesRegex(BuildError,'actual signer'):
                inspect_app(self.app,BUNDLE,TEAM,DEVICE)

    def test_apple_anchor_or_certificate_trust_failure_never_becomes_success(self):
        for rejected in ('Apple-anchored','trust and validity'):
            def failing(args,label):
                if rejected in label:raise BuildError('Synthetic trust failure')
                return self.native(args,label)
            with self.subTest(rejected=rejected),patch('healthkit_device.private_command',side_effect=failing):
                with self.assertRaisesRegex(BuildError,'trust failure'):
                    inspect_app(self.app,BUNDLE,TEAM,DEVICE)

    def test_build_uses_existing_xcode_account_and_never_installs_failed_signature(self):
        output=Path(self.folder.name)/'output';output.mkdir();calls=[]
        with ExitStack() as stack:
            stack.enter_context(patch('healthkit_device.require_mac'))
            stack.enter_context(patch('healthkit_device.private_run',side_effect=lambda a,p:calls.append(a)))
            stack.enter_context(patch('healthkit_device.apply_vision_compat'))
            stack.enter_context(patch('healthkit_device.inspect_app',side_effect=BuildError('HealthKit profile missing')))
            install=stack.enter_context(patch('healthkit_device.device_command'))
            with self.assertRaisesRegex(BuildError,'profile missing'):
                development_build(TEAM,BUNDLE,DEVICE,'119',output,True)
            install.assert_not_called()
        build=calls[-1]
        self.assertIn('CODE_SIGN_STYLE=Automatic',build)
        self.assertIn('CODE_SIGNING_ALLOWED=YES',build)
        self.assertIn('-allowProvisioningUpdates',build)
        self.assertIn('-allowProvisioningDeviceRegistration',build)
        self.assertFalse(any('--sign' in a for a in calls))

    def test_failed_launch_keeps_truthful_record_that_installation_did_happen(self):
        output=Path(self.folder.name)/'output';output.mkdir();evidence={}
        with ExitStack() as stack:
            for name in ('require_mac','private_run','apply_vision_compat'):
                stack.enter_context(patch('healthkit_device.'+name))
            stack.enter_context(patch('healthkit_device.inspect_app',return_value=dict(installation_verified=False)))
            stack.enter_context(patch('healthkit_device.device_command',side_effect=[None,BuildError('launch failed')]))
            with self.assertRaisesRegex(BuildError,'launch failed'):
                development_build(TEAM,BUNDLE,DEVICE,'119',output,True,evidence)
        self.assertTrue(evidence['installation_verified'])
        self.assertFalse(evidence.get('launch_command_succeeded',False))

    def test_native_device_command_requires_success_receipt_not_only_exit_zero(self):
        output=Path(self.folder.name)
        for payload in ({'info':{'outcome':'failed'}},[],{'info':[]},None):
            def result(args,log):
                Path(args[args.index('--json-output')+1]).write_text(json.dumps(payload))
            with self.subTest(payload=payload),patch('healthkit_device.private_run',side_effect=result):
                with self.assertRaisesRegex(BuildError,'did not confirm success'):
                    device_command(['device','install','app'],output,'install')

    def test_private_receipts_cannot_overwrite_previous_evidence(self):
        path=Path(self.folder.name)/'receipt.json';private_json(path,{'status':'not_verified'})
        with self.assertRaises(FileExistsError):private_json(path,{'status':'fake'})
        self.assertEqual(json.loads(path.read_text())['status'],'not_verified')
        for bad in ('Alice iPhone','../device','-option'):
            with self.assertRaises(BuildError):selected_device(bad)


if __name__=='__main__':unittest.main()
