"""Exact-source freeze cases, including staged changes hidden by the worktree."""
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Scripts"))
import verify_restored_source as guard

PURPOSE = "Read steps and active energy for daily activity, and weight and height for review."
APP = b'''import SwiftUI
    let reminders = ReminderService()
    RootView().luqmaFont(.body).foregroundStyle(Theme.text).environmentObject(diary).environmentObject(reminders)
    .onReceive(NotificationCenter.default.publisher(for:NSNotification.Name.NSSystemTimeZoneDidChange)){_ in Task{await reminders.refresh(language:diary.language)}}
struct RootView:View {
    let originalNavigation = true
}
'''


class RestoredSourceRulesTests(unittest.TestCase):
    def test_settings_adds_one_connection_without_restyling_surroundings(self):
        before = b'header\n    originalCard\nfooter\n'
        good = b'header\n' + ('    ' + guard.HEALTH_SETTINGS_ROW + '\n').encode() + b'    originalCard\nfooter\n'
        self.assertIsNone(guard.validate_settings(before, good))
        self.assertIsNotNone(guard.validate_settings(before, good.replace(b'originalCard', b'redesignedCard')))
        self.assertIsNotNone(guard.validate_settings(before, good + (guard.HEALTH_SETTINGS_ROW + '\n').encode()))

    def test_root_navigation_and_existing_app_appearance_remain_exact(self):
        health = APP.replace(b'    let reminders = ReminderService()\n',
                             b'    let reminders = ReminderService()\n    let health = AppleHealthService()\n')
        self.assertIsNone(guard.validate_app(APP, health))
        self.assertIsNotNone(guard.validate_app(APP, health.replace(b'originalNavigation = true', b'originalNavigation = false')))
        self.assertIsNotNone(guard.validate_app(APP, health.replace(b'.luqmaFont(.body)', b'.luqmaFont(.title)')))
        self.assertIsNotNone(guard.validate_app(APP, health.replace(b'import SwiftUI', b'import SwiftUI\n    let redesign = true')))

    def test_only_read_purpose_can_be_added_to_info(self):
        before = {'CFBundleIdentifier': 'app.luqma.diary', 'MinimumOSVersion': '17.0'}
        after = dict(before, NSHealthShareUsageDescription=PURPOSE)
        self.assertIsNone(guard.validate_plist(plistlib.dumps(before), plistlib.dumps(after)))
        for extra in ({'CFBundleIdentifier':'new.identifier'}, {'NSHealthUpdateUsageDescription':'Write foods'}, {'MinimumOSVersion':'18.0'}):
            with self.subTest(extra=extra):
                self.assertIsNotNone(guard.validate_plist(plistlib.dumps(before), plistlib.dumps(dict(after, **extra))))

    def test_exact_approved_arabic_purpose_preserves_bundle_and_rejects_unrelated_copy(self):
        purpose = "يستخدم لُقمة بيانات نشاطك ووزنك وطولك من تطبيق صحتي لعرض معلوماتك الصحية ومساعدتك على متابعة أهدافك الغذائية."
        actual = plistlib.loads((ROOT / "Luqma/Info.plist").read_bytes())
        self.assertEqual(actual["NSHealthShareUsageDescription"], purpose)
        localized = (ROOT / "Luqma/Resources/ar.lproj/InfoPlist.strings").read_text("utf8")
        self.assertIn('"NSHealthShareUsageDescription" = "' + purpose + '";', localized)
        self.assertTrue(guard.meaningful_purpose(purpose))
        before = {"CFBundleIdentifier": "app.luqma.diary"}
        after = dict(before, NSHealthShareUsageDescription=purpose)
        self.assertIsNone(guard.validate_plist(plistlib.dumps(before), plistlib.dumps(after)))
        names = '"CFBundleDisplayName" = "لُقمة";\n'.encode("utf8")
        self.assertIsNone(guard.validate_strings(names, names + ('"NSHealthShareUsageDescription" = "' + purpose + '";\n').encode("utf8")))
        for unrelated in ("اسمح بالوصول", "هذا وصف طويل يتعلق بألوان الواجهة وترتيب البطاقات ولا يشرح غرض قراءة بيانات صحتي."):
            with self.subTest(copy=unrelated):
                self.assertFalse(guard.meaningful_purpose(unrelated))
                self.assertIsNotNone(guard.validate_plist(plistlib.dumps(before), plistlib.dumps(dict(after, NSHealthShareUsageDescription=unrelated))))
        self.assertIsNotNone(guard.validate_plist(plistlib.dumps(before), plistlib.dumps(dict(after, CFBundleIdentifier="changed.identifier"))))

    def test_entitlement_preserves_other_capabilities_without_background_or_write_additions(self):
        before = {'original.capability': True}
        after = dict(before, **{'com.apple.developer.healthkit':True})
        self.assertIsNone(guard.validate_plist(plistlib.dumps(before), plistlib.dumps(after), entitlements=True))
        for wrong in ({'com.apple.developer.healthkit':1}, {'com.apple.developer.healthkit':True},
                      dict(after, **{'com.apple.developer.healthkit.background-delivery':True})):
            with self.subTest(wrong=wrong):
                self.assertIsNotNone(guard.validate_plist(plistlib.dumps(before), plistlib.dumps(wrong), entitlements=True))

    def test_localized_names_and_camera_purpose_cannot_change(self):
        before = b'"CFBundleDisplayName" = "Luqma";\n"NSCameraUsageDescription" = "Camera";\n'
        after = before + ('"NSHealthShareUsageDescription" = "' + PURPOSE + '";\n').encode()
        self.assertIsNone(guard.validate_strings(before, after))
        self.assertIsNotNone(guard.validate_strings(before, after.replace(b'"Luqma"', b'"New brand"')))
        self.assertIsNotNone(guard.validate_strings(before, after + b'"extra" = "unrelated";\n'))

    def test_ignore_changes_cannot_hide_unrelated_files(self):
        before = b'BuildOutput/\n*.ipa\n'
        self.assertIsNone(guard.validate_ignore(before, before + b'HealthValidation/\nRestore103Validation/\n'))
        self.assertIsNone(guard.validate_ignore(before, b'BuildOutput/\nHealthValidation/\n*.ipa\n'))
        self.assertIsNotNone(guard.validate_ignore(before, before + b'Luqma/new-design.swift\n'))
        self.assertIsNotNone(guard.validate_ignore(before, b'*.ipa\n'))

    def test_only_three_new_app_sources_and_no_progress_card(self):
        self.assertIsNone(guard.validate_delta('Luqma/Core/HealthReadModels.swift', None, b'import Foundation\n'))
        self.assertIsNotNone(guard.validate_delta('Luqma/Core/Nutrition.swift', b'original', b'changed'))
        self.assertIsNotNone(guard.validate_delta('Luqma/Resources/Assets.xcassets/new.imageset/Contents.json', None, b'{}'))
        self.assertIsNotNone(guard.validate_delta('Luqma/Views/AppleHealthView.swift', None, b'struct HealthProgressCard {}'))
        self.assertIsNotNone(guard.validate_delta('Luqma/Views/ProgressView.swift', b'original', b'changed'))


class RestoredSourceGitTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix='luqma-freeze-test-')
        self.root = Path(self.folder.name)
        self.git('init', '-q')
        self.git('config', 'core.autocrlf', 'true')
        self.put('.gitignore', b'BuildOutput/\n')
        self.put('Luqma/Core/Protected.swift', b'import Foundation\nlet original = 1\n')
        self.put('Luqma/Resources/image.png', b'\x89PNG\x00binary\r\n')
        self.git('add', '.')
        self.git('-c', 'user.name=Freeze Test', '-c', 'user.email=freeze@example.invalid', 'commit', '-q', '-m', 'Fixture baseline')
        self.baseline = self.git('rev-parse', 'HEAD').decode().strip()
        self.tree = self.git('rev-parse', 'HEAD^{tree}').decode().strip()

    def tearDown(self):
        self.folder.cleanup()

    def git(self, *arguments):
        result = subprocess.run(['git', *arguments], cwd=self.root, capture_output=True)
        if result.returncode:
            self.fail('Fixture Git operation failed: ' + arguments[0])
        return result.stdout

    def put(self, name, data):
        path = self.root/name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def inspect(self):
        with patch.object(guard, 'BASELINE', self.baseline), patch.object(guard, 'BASELINE_TREE', self.tree):
            return guard.inspect_repository(self.root)

    def test_canonical_text_crlf_is_accepted_but_binary_asset_changes_fail(self):
        self.put('Luqma/Core/Protected.swift', b'import Foundation\r\nlet original = 1\r\n')
        self.assertEqual(self.inspect()['status'], 'passed')
        self.put('Luqma/Resources/image.png', b'\x89PNG\x00changed\r\n')
        report = self.inspect()
        self.assertEqual(report['status'], 'failed')
        self.assertEqual(report['violations'][0]['path'], 'Luqma/Resources/image.png')

    def test_index_change_hidden_by_restored_worktree_still_fails(self):
        self.put('Luqma/Core/Protected.swift', b'import Foundation\nlet original = 2\n')
        self.git('add', 'Luqma/Core/Protected.swift')
        self.put('Luqma/Core/Protected.swift', b'import Foundation\nlet original = 1\n')
        report = self.inspect()
        self.assertEqual(report['status'], 'failed')
        self.assertEqual(report['violations'][0]['problems'][0]['scope'], 'index')

    def test_unknown_untracked_or_ignored_app_code_fails_while_generated_output_is_ignored(self):
        self.put('.gitignore', b'BuildOutput/\nHealthValidation/\n')
        self.put('HealthValidation/report.json', b'{}')
        self.assertEqual(self.inspect()['status'], 'passed')
        self.put('new-unapproved-file.txt', b'unrelated')
        self.assertEqual(self.inspect()['status'], 'failed')
        (self.root/'new-unapproved-file.txt').unlink()
        # Even a local exclude cannot conceal native source or new artwork.
        (self.root/'.git/info/exclude').write_text('Luqma/Core/Hidden.swift\n', encoding='utf8')
        self.put('Luqma/Core/Hidden.swift', b'let unapproved = true\n')
        self.assertEqual(self.inspect()['status'], 'failed')

    def test_missing_authenticated_baseline_fails_without_fetching_or_changing_git(self):
        with patch.object(guard, 'BASELINE', '0'*40):
            report = guard.inspect_repository(self.root)
        self.assertEqual(report['status'], 'failed')
        self.assertTrue(report['violations'])
        self.assertEqual(self.git('rev-parse', 'HEAD').decode().strip(), self.baseline)


if __name__ == '__main__':
    unittest.main()
