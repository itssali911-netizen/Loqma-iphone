#!/usr/bin/env python3
"""Native camera fallback/picker test and explicitly labelled UI-state captures.

No API key, physical camera claim, or live nutrition request. Existing production
views are rendered with DEBUG-only fixtures for scan/results layout inspection.
"""
import json
import os
from pathlib import Path
import ui_preview as preview
from ui_interactions import run_scenario

ROOT=Path(__file__).resolve().parents[1]
output=ROOT/'CameraValidation'
output.mkdir(exist_ok=False)
packages=ROOT/'BuildOutput/Packages'
app=ROOT/'BuildOutput/simulator-derived/Build/Products/Debug-iphonesimulator/Luqma.app'
cases=[
    dict(tab=None,screen='camera-fallback',arguments=['-loqma-preview-template','approvedPhotoScan'],template_route='approvedPhotoScan',synthetic_fixture=False),
    dict(tab=None,screen='scan-ui-fixture',arguments=['-loqma-preview-template','approvedPhotoScan','-loqma-camera-ui-scan'],template_route='approvedPhotoScan',synthetic_fixture=True),
    dict(tab=None,screen='results-ui-fixture',arguments=['-loqma-preview-template','approvedPhotoResults','-loqma-approved-photo-results'],template_route='approvedPhotoResults',synthetic_fixture=True),
    dict(tab=None,screen='results-accessibility-fixture',arguments=['-loqma-preview-template','approvedPhotoResults','-loqma-approved-photo-results','-loqma-preview-accessibility'],template_route='approvedPhotoResults',synthetic_fixture=True),
]
for case in cases:case['read_only_preview']=True
preview.preview_cases=lambda:cases
bundle=os.environ.get('BUNDLE_ID') or 'app.luqma.diary'
failures=[]
for language in ['ar','en']:
    try:
        preview.capture(output/language,packages,app,bundle,3,preview.REFERENCE_DEVICE_TYPE,language,[c['screen'] for c in cases])
    except Exception as error:failures.append(str(error))
scenario=dict(status='running',required_cases=['testMealCameraFallbackAndSystemPhotoPicker'],physical_device_verified=False,api_key_used=False)
try:
    inventory=json.loads(preview.command(['xcrun','simctl','list','--json'],output,'inventory'))
    runtime=preview.select_runtime(inventory)
    run_scenario(output/'interactions',packages,ROOT/'BuildOutput/simulator-derived',runtime,tuple(scenario['required_cases']),scenario,os.environ.get('BUILD_NUMBER','1'))
except Exception as error:failures.append(str(error))
(output/'camera-test.json').write_text(json.dumps(scenario,indent=2)+'\n')
if failures:raise SystemExit('\n'.join(failures))
