"""HealthKit configuration and generator contracts; no SDK or consent simulation."""
from contextlib import redirect_stdout
import io
from pathlib import Path
import plistlib
import runpy
import unittest
from unittest.mock import patch

ROOT=Path(__file__).resolve().parents[1]


class HealthConfigurationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Inspect the generator's complete object graph without modifying the
        # checkout. This also catches a stale committed Xcode project.
        writes={}
        def capture(path,text,*args,**kwargs):
            writes[Path(path).resolve()]=text
            return len(text)
        with patch.object(Path,'mkdir',autospec=True), \
             patch.object(Path,'write_text',autospec=True,side_effect=capture), \
             redirect_stdout(io.StringIO()):
            generated=runpy.run_path(str(ROOT/'Scripts/build_project.py'))
        cls.objects=generated['objects'];cls.ref=staticmethod(generated['identity'])
        cls.generated=writes[(ROOT/'Luqma.xcodeproj/project.pbxproj').resolve()]

    def test_healthkit_is_the_only_requested_health_capability(self):
        claims=plistlib.loads((ROOT/'Luqma/Luqma.entitlements').read_bytes())
        self.assertIs(claims.get('com.apple.developer.healthkit'),True)
        self.assertEqual({key for key in claims if key.startswith('com.apple.developer.healthkit')},
                         {'com.apple.developer.healthkit'})

    def test_localized_read_purpose_without_write_or_clinical_permission(self):
        info=plistlib.loads((ROOT/'Luqma/Info.plist').read_bytes())
        self.assertGreater(len(info.get('NSHealthShareUsageDescription','').strip()),40)
        for key in ('NSHealthUpdateUsageDescription','NSHealthClinicalHealthRecordsShareUsageDescription',
                    'NSHealthRequiredReadAuthorizationTypeIdentifiers'):
            self.assertNotIn(key,info)
        for language in ('ar','en'):
            text=(ROOT/'Luqma/Resources'/f'{language}.lproj/InfoPlist.strings').read_text('utf8')
            self.assertIn('"NSHealthShareUsageDescription" = "',text)
            self.assertNotIn('NSHealthUpdateUsageDescription',text)

    def test_capability_and_system_framework_belong_only_to_the_app_target(self):
        objects=self.objects;ref=self.ref
        attributes=objects[ref('project')]['attributes']['TargetAttributes']
        self.assertEqual(attributes[ref('target')]['SystemCapabilities'].get('com.apple.HealthKit'),{'enabled':1})
        self.assertNotIn('com.apple.HealthKit',attributes[ref('target:uitests')].get('SystemCapabilities',{}))
        framework=objects[ref('framework:healthkit')]
        self.assertEqual(framework['path'],'System/Library/Frameworks/HealthKit.framework')
        self.assertEqual(framework['sourceTree'],'SDKROOT')
        self.assertIn(ref('healthkit:build'),objects[ref('phase:frameworks')]['files'])
        self.assertNotIn(ref('healthkit:build'),objects[ref('uitests:frameworks')]['files'])
        for name in ('Debug','Release'):
            app=objects[ref('config:target:'+name)]['buildSettings']
            self.assertEqual(app['CODE_SIGN_ENTITLEMENTS'],'Luqma/Luqma.entitlements')
            self.assertEqual(app['CODE_SIGN_STYLE'],'Automatic')
            self.assertEqual(app['PRODUCT_BUNDLE_IDENTIFIER'],'app.luqma.diary')
            tests=objects[ref('config:uitests:'+name)]['buildSettings']
            self.assertNotIn('CODE_SIGN_ENTITLEMENTS',tests)

    def test_committed_project_matches_generator_with_all_current_sources(self):
        self.assertEqual((ROOT/'Luqma.xcodeproj/project.pbxproj').read_text('utf8'),self.generated,
                         'Regenerate with python3 Scripts/build_project.py after adding source files.')

    def test_legacy_diary_fields_and_calorie_goal_behavior_are_preserved(self):
        # Preserve the original build103 regression assertions while replacing
        # its obsolete expectation that the app must not contain HealthKit.
        self.assertIn('var healthEnabled=false;var healthSync:HealthSyncState?',
                      (ROOT/'Luqma/Core/Models.swift').read_text('utf8'))
        self.assertIn('func dailyGoals(_ day: String) -> Nutrition { state.goals }',
                      (ROOT/'Luqma/Services/DiaryStore.swift').read_text('utf8'))


if __name__=='__main__':unittest.main()
