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
from ui_preview import DEVICE_TYPE, command, select_runtime, validate_app
from vision_compat import apply_vision_compat

PRIMARY_TESTS = ('testFoodAddResizePersistenceAndDelete', 'testTabNavigationAndGoalsPersistAfterRelaunch',
                 'testLanguageSelectionPersistsAfterRelaunch', 'testRecipeDraftSurvivesIngredientSearch',
                 'testNotificationPermissionAndReminderPersistence')
DENIED_TESTS = ('testNotificationDeniedDoesNotClaimDelivery',)
FITNESS_TESTS = ('testFitnessDraftApplyAndDeletePreserveDiary',)
TESTS = PRIMARY_TESTS + DENIED_TESTS + FITNESS_TESTS


def run_scenario(output: Path, packages: Path, derived: Path, runtime: dict,
                 methods: tuple[str, ...], report: dict, build_number: str) -> None:
    """Use a separately created device for each OS notification permission choice.

    simctl has no supported notifications privacy reset. A denied permission is
    never changed using defaults, a private API, or an app test flag. Each test
    must choose Allow/Don't Allow in the genuine first-run iOS system alert.
    """
    output.mkdir(parents=True, exist_ok=True)
    device=None
    try:
        device=command(['xcrun','simctl','create','Luqma Interaction '+uuid.uuid4().hex[:8],DEVICE_TYPE,runtime['identifier']],output,'create').strip()
        if not re.fullmatch(r'[0-9A-Fa-f-]{36}',device):
            device=None
            raise BuildError('Simulator creation did not return a valid identifier.')
        report['fresh_simulator']=True
        report['simulator']=dict(udid=device,device='iPhone 16 Pro Max',runtime=runtime['name'])
        report['preparation']=prepare_created_simulator(device,lambda args,label,timeout:command(args,output,label,timeout))
        result=output/'interactions.xcresult'
        report['result_bundle']=str(result)
        selection=['-only-testing:LuqmaUITests/LuqmaInteractionTests/'+name for name in methods]
        log=command(['xcodebuild','-project','Luqma.xcodeproj','-scheme','Luqma',
                     '-clonedSourcePackagesDirPath',str(packages),'-disableAutomaticPackageResolution',
                     '-destination','id='+device,'-configuration','Debug','-derivedDataPath',str(derived),
                     '-resultBundlePath',str(result),'-parallel-testing-enabled','NO',
                     *selection,'ARCHS=arm64','ONLY_ACTIVE_ARCH=YES',
                     'CODE_SIGNING_ALLOWED=NO','CURRENT_PROJECT_VERSION='+build_number,
                     'test'],output,'native-interactions',1500)
        # An empty XCTest run or successful rendering is not functional evidence.
        passed=[name for name in methods if re.search(r"Test Case '.*"+re.escape(name)+r".*' passed",log)]
        report['passed_cases']=passed
        if len(passed)!=len(methods):
            raise BuildError('Native run did not report all required interaction cases as passed.')
        summary=command(['xcrun','xcresulttool','get','test-results','summary','--path',str(result)],output,'xcresult-summary')
        (output/'xcresult-summary.json').write_text(json.dumps(json.loads(summary),indent=2)+'\n',encoding='utf-8')
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


def run_tests(output: Path, packages: Path, derived: Path) -> None:
    require_mac()
    if output.exists():
        raise BuildError('Choose a new interaction output directory.')
    output.mkdir(parents=True)
    started=time.monotonic()
    report=dict(status='running', commit=os.environ.get('GITHUB_SHA','local'),
                started_at=datetime.now(timezone.utc).isoformat(),
                test_method='XCUITest taps actual application controls and real iOS notification permission alerts; no preview flags or service stubs',
                fresh_simulator=False, existing_device_data_modified=False,
                api_key_used=False, physical_device_verified=False,
                physical_notification_delivery_verified=False, permissions_pregranted=False,
                scenarios=[], scenario_execution_order=[])
    try:
        build_number=os.environ.get('BUILD_NUMBER','1') or '1'
        if not re.fullmatch(r'[1-9][0-9]{0,8}',build_number):
            raise BuildError('BUILD_NUMBER must be a positive integer with at most nine digits.')
        bundle=os.environ.get('BUNDLE_ID','') or 'app.luqma.diary'
        if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+',bundle):
            raise BuildError('BUNDLE_ID is invalid.')
        inventory=json.loads(command(['xcrun','simctl','list','--json'],output,'inventory'))
        runtime=select_runtime(inventory)
        apply_vision_compat(packages)
        # Exercise the assessment first, before the longer existing scenarios.
        # Failed reports retain the actual partial execution order and evidence.
        for name,directory,methods in [('fitness-assessment',output/'fitness-assessment',FITNESS_TESTS),
                                        ('permission-allowed',output,PRIMARY_TESTS),
                                        ('permission-denied',output/'permission-denied',DENIED_TESTS)]:
            scenario=dict(name=name,status='running',fresh_simulator=False,required_cases=list(methods))
            report['scenarios'].append(scenario)
            report['scenario_execution_order'].append(name)
            run_scenario(directory,packages,derived,runtime,methods,scenario,build_number)
        # Successful evidence keeps the established consumer/schema order.
        # This reorders only actual completed scenarios, not their outcomes.
        completed={item['name']:item for item in report['scenarios']}
        report['scenarios']=[completed[name] for name in ('permission-allowed','permission-denied','fitness-assessment')]
        report['fresh_simulator']=all(item['fresh_simulator'] for item in report['scenarios'])
        report['simulator']=report['scenarios'][0]['simulator']
        report['passed_cases']=[name for item in report['scenarios'] for name in item['passed_cases']]
        if set(report['passed_cases'])!=set(TESTS):
            raise BuildError('Native runs did not report every required interaction case as passed.')
        apply_vision_compat(packages,verify_only=True)
        # Capture can reuse the tested Debug Simulator app without recompiling.
        # Its actual identity must match this run; no global bundle override is
        # applied to xcodebuild test, which also builds the XCTest runner target.
        report['app']=validate_app(derived/'Build/Products/Debug-iphonesimulator/Luqma.app',bundle,output)
        if str(report['app'].get('build'))!=build_number:
            raise BuildError('The tested Simulator application build does not match BUILD_NUMBER.')
        report['status']='passed'
    except BaseException as error:
        report['status']='failed'
        report['error']=str(error)
        raise
    finally:
        report['elapsed_seconds']=round(time.monotonic()-started,2)
        report['completed_at']=datetime.now(timezone.utc).isoformat()
        (output/'interaction-report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=Path('UIInteractions'))
    parser.add_argument('--packages',type=Path,default=Path('BuildOutput/Packages'))
    parser.add_argument('--derived',type=Path,default=Path('UIInteractionDerived'))
    args=parser.parse_args()
    try:run_tests(args.output.resolve(),args.packages.resolve(),args.derived.resolve())
    except (BuildError,OSError,ValueError) as error:
        print(str(error),file=sys.stderr)
        sys.exit(1)
