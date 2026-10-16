#!/usr/bin/env python3
"""Run real controls/persistence tests on an own disposable iPhone Simulator.

Uses the XCUITest target, never read-only screenshot fixtures. No private API key,
Apple account or existing Simulator is used. Native results remain in xcresult.
Apple test-result documentation:
https://developer.apple.com/documentation/xcode/running-tests-and-interpreting-results
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import sys
import time
import uuid

from build_ios import BuildError, require_mac
from simulator_support import prepare_created_simulator
from ui_preview import DEVICE_TYPE, command, select_runtime
from vision_compat import apply_vision_compat

TESTS = ('testFoodAddResizePersistenceAndDelete', 'testTabNavigationAndGoalsPersistAfterRelaunch',
         'testLanguageSelectionPersistsAfterRelaunch')


def run_tests(output: Path, packages: Path, derived: Path) -> None:
    require_mac()
    if output.exists():
        raise BuildError('Choose a new interaction output directory.')
    output.mkdir(parents=True)
    started=time.monotonic()
    report=dict(status='running', commit=os.environ.get('GITHUB_SHA','local'),
                started_at=datetime.now(timezone.utc).isoformat(),
                test_method='XCUITest taps actual application controls; no preview flags or service stubs',
                fresh_simulator=False, existing_device_data_modified=False,
                api_key_used=False, physical_device_verified=False)
    device=None
    try:
        inventory=json.loads(command(['xcrun','simctl','list','--json'],output,'inventory'))
        runtime=select_runtime(inventory)
        device=command(['xcrun','simctl','create','Luqma Interaction '+uuid.uuid4().hex[:8],DEVICE_TYPE,runtime['identifier']],output,'create').strip()
        if not re.fullmatch(r'[0-9A-Fa-f-]{36}',device):
            device=None
            raise BuildError('Simulator creation did not return a valid identifier.')
        report['fresh_simulator']=True
        report['simulator']=dict(udid=device,device='iPhone 16 Pro Max',runtime=runtime['name'])
        report['preparation']=prepare_created_simulator(device,lambda args,label,timeout:command(args,output,label,timeout))
        apply_vision_compat(packages)
        result=output/'interactions.xcresult'
        log=command(['xcodebuild','-project','Luqma.xcodeproj','-scheme','Luqma',
                     '-clonedSourcePackagesDirPath',str(packages),'-disableAutomaticPackageResolution',
                     '-destination','id='+device,'-configuration','Debug','-derivedDataPath',str(derived),
                     '-resultBundlePath',str(result),'-parallel-testing-enabled','NO',
                     '-only-testing:LuqmaUITests','ARCHS=arm64','ONLY_ACTIVE_ARCH=YES',
                     'CODE_SIGNING_ALLOWED=NO','test'],output,'native-interactions',1200)
        # Do not infer a pass from a rendering or a zero-exit build with zero tests.
        passed=[name for name in TESTS if re.search(r"Test Case '.*"+name+r".*' passed",log)]
        report['passed_cases']=passed
        if len(passed)!=len(TESTS):
            raise BuildError('Native run did not report all required interaction cases as passed.')
        summary=command(['xcrun','xcresulttool','get','test-results','summary','--path',str(result)],output,'xcresult-summary')
        (output/'xcresult-summary.json').write_text(json.dumps(json.loads(summary),indent=2)+'\n',encoding='utf-8')
        apply_vision_compat(packages,verify_only=True)
        report['status']='passed'
    except BaseException as error:
        report['status']='failed'
        report['error']=str(error)
        raise
    finally:
        if device:
            for operation in ('shutdown','delete'):
                try:command(['xcrun','simctl',operation,device],output,'cleanup-'+operation,90,allow_failure=True)
                except (BuildError,OSError) as error:report.setdefault('cleanup_warnings',[]).append(str(error))
        report['elapsed_seconds']=round(time.monotonic()-started,2)
        report['completed_at']=datetime.now(timezone.utc).isoformat()
        (output/'interaction-report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=Path('UIInteractions'))
    parser.add_argument('--packages',type=Path,default=Path('BuildOutput/Packages'))
    parser.add_argument('--derived',type=Path,default=Path('UIPreview/derived'))
    args=parser.parse_args()
    try:run_tests(args.output.resolve(),args.packages.resolve(),args.derived.resolve())
    except (BuildError,OSError,ValueError) as error:
        print(str(error),file=sys.stderr)
        sys.exit(1)
