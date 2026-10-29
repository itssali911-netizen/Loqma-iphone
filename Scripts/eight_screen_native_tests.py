#!/usr/bin/env python3
"""Exercise real production controls on disposable native iOS Simulators."""
import json
from pathlib import Path
from ui_interactions import run_scenario
from ui_preview import command, select_runtime

root=Path(__file__).resolve().parents[1]
output=root/'EightScreenTests'
output.mkdir(exist_ok=False)
inventory=json.loads(command(['xcrun','simctl','list','--json'],output,'inventory'))
runtime=select_runtime(inventory)
scenarios=[('review','EightScreenReviewTests',('testWeightValidationSameDayReplacementAndRelaunch','testArabicRecipeDraftReturnsFromIngredientSearch')),
           ('existing','LuqmaInteractionTests',('testRecipeDraftSurvivesIngredientSearch','testTabNavigationAndGoalsPersistAfterRelaunch'))]
for name,cls,methods in scenarios:
    report={'status':'running','synthetic_service_data':False,'test_class':cls,'cases':list(methods)}
    run_scenario(output/name,root/'BuildOutput/Packages',root/'EightScreenTestDerived',runtime,methods,report,'124',
                 signing_settings=['CODE_SIGNING_ALLOWED=YES','CODE_SIGN_IDENTITY=-'],test_class=cls,timeout_seconds=2400)
