#!/usr/bin/env python3
"""Package the checked iPhoneOS build; never claim Apple-authorized signing."""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess

from build_ios import BuildError, ROOT, prepare_sideload, require_mac
from verify_healthkit_signing import inspect_ipa


def main() -> None:
    require_mac(26)
    output = ROOT / 'Delivery'
    if output.exists():
        raise BuildError('Use a fresh delivery folder; do not overwrite an earlier IPA.')
    revision = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    baseline = '3d91e648557199e60b4981335b9b1eb36498f793'
    # The user requested distribution of the reviewed app, not a new UI change.
    subprocess.run(['git', 'diff', '--exit-code', baseline, 'HEAD', '--',
                    'Luqma', 'Luqma.xcodeproj', 'Package.swift', 'Tests', 'TestsUI'],
                   cwd=ROOT, check=True)
    checked = ROOT / 'BuildOutput'
    summary = json.loads((checked / 'build-summary.json').read_text('utf8'))
    if summary.get('mode') != 'check' or summary.get('commit') != revision:
        raise BuildError('The current source must pass both SDK builds before packaging.')
    app = checked / 'device-derived/Build/Products/Release-iphoneos/Luqma.app'
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    bundle = 'app.luqma.diary'
    if info.get('CFBundleIdentifier') != bundle or info.get('CFBundleVersion') != os.environ['BUILD_NUMBER']:
        raise BuildError('Built application metadata differs from the delivery configuration.')
    output.mkdir()
    ipa = prepare_sideload(app, output, bundle)
    target = output / f'LUQMA-{info["CFBundleShortVersionString"]}-build{info["CFBundleVersion"]}-Resignable.ipa'
    ipa.rename(target)
    report = inspect_ipa(target, bundle)
    (output / 'signing-report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf8')
    required = {'BuildIntegrity': 'PASS', 'CodeSignature': 'PASS',
                'ProvisioningProfile': 'ABSENT', 'HealthKitEntitlement': 'PRESENT',
                'HealthKitProfileAuthorization': 'NOTVERIFIED',
                'DeviceInstallation': 'NOTTESTED', 'RealHealthData': 'NOTTESTED'}
    if report['exit_code'] != 2 or any(report['statuses'].get(k) != v for k, v in required.items()):
        raise BuildError('The measured re-signable device package does not meet its integrity requirements.')
    signing = report['evidence']['signing']
    if signing.get('signing_kind') != 'ADHOC_HASH' or signing.get('apple_identity_verified') is not False:
        raise BuildError('Only a clearly identified local hash-signed re-signable candidate is expected.')
    shutil.copy2(ROOT / 'Luqma/Luqma.entitlements', output / 'Requested-HealthKit.entitlements')
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    manifest = dict(source_commit=revision, reviewed_app_source=baseline,
                    production_source_unchanged=True, bundle_identifier=bundle,
                    version=info['CFBundleShortVersionString'], build=info['CFBundleVersion'],
                    ipa_file=target.name, ipa_sha256=digest, ipa_bytes=target.stat().st_size,
                    platform='iPhoneOS', architecture='arm64', signing_kind='ADHOC_HASH',
                    apple_signed=False, provisioning_profile_present=False,
                    requires_resigning=True, physical_device_verified=False,
                    healthkit_profile_authorization_verified=False)
    (output / 'delivery-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf8')
    (output / 'READ-ME-AR.txt').write_text(
        'نسخة لقمة الحالية لأجهزة iPhone، مع آخر تعديلات مطبخي وجميع الوظائف الحالية.\n'
        'هذا الملف يتطلب إعادة توقيع عبر أداة متوافقة مثل iLoader قبل التثبيت.\n'
        'التوقيع الموجود يحمي سلامة الملفات محليًا؛ ليس شهادة توزيع من Apple.\n'
        'تكامل HealthKit موجود. عمله بعد التثبيت يتطلب أن يسمح ملف التزويد النهائي بصلاحية HealthKit وألا تحذفها أداة التوقيع.\n'
        'لا يوجد تأكيد على التوافق مع كل حساب أو كل أداة توقيع، ولم يختبر جهاز فعلي.\n'
        'للحفاظ على البيانات، لا تحذف النسخة الحالية؛ أنشئ نسخة احتياطية داخل التطبيق وحافظ على معرّف التطبيق وفريق التوقيع الحاليين عند التحديث.\n', encoding='utf8')
    (output / 'SHA256SUMS.txt').write_text(''.join(
        f'{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n'
        for path in sorted(output.iterdir()) if path.is_file() and path.name != 'SHA256SUMS.txt'), encoding='utf8')
    print(json.dumps(manifest, indent=2))


if __name__ == '__main__':
    main()
