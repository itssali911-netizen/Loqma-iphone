from pathlib import Path
import plistlib,unittest

ROOT=Path(__file__).resolve().parents[1]

class RemovedHealthTests(unittest.TestCase):
    def test_release_requests_no_health_permission_or_capability(self):
        claims=plistlib.loads((ROOT/'Luqma/Luqma.entitlements').read_bytes())
        self.assertFalse(any('healthkit' in key for key in claims))
        info=plistlib.loads((ROOT/'Luqma/Info.plist').read_bytes())
        self.assertNotIn('NSHealthShareUsageDescription',info)
        self.assertNotIn('NSHealthUpdateUsageDescription',info)
        self.assertNotIn('com.apple.HealthKit',(ROOT/'Luqma.xcodeproj/project.pbxproj').read_text('utf-8'))

    def test_launch_and_views_have_no_health_connection_routes(self):
        self.assertFalse((ROOT/'Luqma/Services/HealthService.swift').exists())
        views='\n'.join(p.read_text('utf-8') for p in (ROOT/'Luqma/Views').glob('*.swift'))
        launch=(ROOT/'Luqma/LuqmaApp.swift').read_text('utf-8')
        for symbol in ['HealthService','HealthConnectionView','DailyActivitySummaryView','HealthImportView','import HealthKit']:
            self.assertNotIn(symbol,views+'\n'+launch)
        # Old backup fields and source tags remain readable; removal must not
        # erase historical weights or trigger old activity goal adjustments.
        self.assertIn('var healthEnabled=false;var healthSync:HealthSyncState?',(ROOT/'Luqma/Core/Models.swift').read_text('utf-8'))
        self.assertIn('func dailyGoals(_ day: String) -> Nutrition { state.goals }',(ROOT/'Luqma/Services/DiaryStore.swift').read_text('utf-8'))

if __name__=='__main__':unittest.main()
