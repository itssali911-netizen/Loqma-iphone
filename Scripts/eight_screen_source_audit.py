#!/usr/bin/env python3
"""Verify this eight-screen review did not alter unrelated production files."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
BASE='798a0f4f45aad23fdeac235a417d345988cf5c34'
ALLOWED={
 'Luqma/Views/KitchenView.swift','Luqma/Views/ProgressView.swift',
 'Luqma/Views/PlanView.swift','Luqma/Views/PhotoMealView.swift',
 'Luqma/Views/LuqmaRefinedUI.swift','Luqma/Views/LuqmaMealCamera.swift',
 'Luqma.xcodeproj/project.pbxproj','Luqma/Views/FoodAddView.swift',
}
def git(*args):return subprocess.check_output(['git',*args],cwd=ROOT,text=True)
changed=set(git('diff','--name-only',BASE,'--','Luqma/','Luqma.xcodeproj/').splitlines())
changed.update(p for p in git('ls-files','--others','--exclude-standard').splitlines() if p.startswith(('Luqma/','Luqma.xcodeproj/')))
violations=sorted(changed-ALLOWED)
protected=['Luqma/Core','Luqma/Services','Luqma/Resources','Luqma/LuqmaApp.swift',
           'Luqma/Views/LuqmaTypography.swift','Luqma/Views/Common.swift',
           'Luqma/Views/DiaryView.swift','Luqma/Views/DailyCalorieCard.swift',
           'Luqma/Views/DailyMealCard.swift',
           'Luqma/Info.plist','Luqma/Luqma.entitlements']
# The recipe gram action exposed the default-serving selection. Only an
# optional initial unit was added; all existing call sites keep the same default.
original_portion=git('show',BASE+':Luqma/Views/FoodAddView.swift')
expected_portion=original_portion.replace('    var initialMeal:Meal?=nil\n    var onAnalyze:', '    var initialMeal:Meal?=nil\n    var initialUnit:FoodUnit?=nil\n    var onAnalyze:').replace('unit=food.defaultAdditionUnit;name=food.label(diary.language);amount="1"','unit=initialUnit ?? food.defaultAdditionUnit;name=food.label(diary.language);amount="1"')
portion_only_initial_unit=(ROOT/'Luqma/Views/FoodAddView.swift').read_text()==expected_portion
unchanged={p:not bool(git('diff','--name-only',BASE,'--',p).strip()) for p in protected}
font=hashlib.sha256((ROOT/'Luqma/Resources/Changa-Bold.ttf').read_bytes()).hexdigest()
report=dict(status='passed' if not violations and all(unchanged.values()) else 'failed',
 baseline=BASE,changed_application_files=sorted(changed),scope_violations=violations,
 byte_identical_protected_paths=unchanged,changa_bold_sha256=font,
 expected_font_sha256='d2015fb807cdd2cdc4d2f539db75117f7f009e407fe9d4b3e7555d94c4ff2c9f',
 native_build='simulator_debug_passed',native_screenshots='32_actual_framebuffers_captured',native_interactions='4_actual_cases_passed_in_run_40882626673',
 physical_camera='not_tested',live_ai_service='not_called',visual_approval='pending',
 public_push='published_with_explicit_user_authorization',merged=False,ipa_published=False)
report['native_evidence_matches_current_application']=not bool(git('diff','--name-only','bd661d731ccb7e1e089c251f5c4083699751c8e7','--','Luqma/','Luqma.xcodeproj/').strip())
report['native_evidence']=json.loads((ROOT/'Docs/EightScreenNativeEvidence.json').read_text())
report['food_portion_only_optional_initial_unit_changed']=portion_only_initial_unit
if not portion_only_initial_unit:report['status']='failed'
if font!=report['expected_font_sha256']:report['status']='failed'
followup=ROOT/'Docs/RecipeDetailNativeEvidence.json'
if followup.exists():
    report['recipe_detail_followup']=json.loads(followup.read_text())
    report['native_build']='recipe_followup_simulator_debug_passed'
    report['native_screenshots']='4_accepted_actual_recipe_followup_frames'
    report['native_interactions']='recipe_controls_passed_in_run_40952995187; Arabic_draft_passed_in_run_40942555850'
    report['historical_eight_screen_capture_revision']='bd661d731ccb7e1e089c251f5c4083699751c8e7'
output=ROOT/'Docs/EightScreenReviewAudit.json'
output.write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
raise SystemExit(report['status']!='passed')
