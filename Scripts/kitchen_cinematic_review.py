#!/usr/bin/env python3
"""Focused native Kitchen validation. No substitute artwork or invented results.

The photo gate deliberately refuses to build until the exact original artwork
has been supplied and its expected SHA-256 has been independently recorded.
Existing screenshot scripts capture actual Simulator framebuffers. The control
scenarios exercise actual categories, search, presentation, and recipe-draft controls;
it does not claim camera, remote import, or HealthKit verification.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
from build_ios import BuildError, require_mac, run
from ui_interactions import run_scenario
from ui_preview import command, select_runtime
from vision_compat import apply_vision_compat

ROOT=Path(__file__).resolve().parents[1]
BASELINE='cc282f58be1aa562f3e9da6e22151d9cc298acef'


def verify_reference(relative_path: str, expected_sha256: str) -> dict:
    if not re.fullmatch(r'[0-9a-f]{64}', expected_sha256):
        raise BuildError('Record the SHA-256 of the original supplied kitchen photograph; no guessed image is accepted.')
    relative=Path(relative_path)
    if relative.is_absolute() or '..' in relative.parts:
        raise BuildError('The original artwork must be a project-relative asset path.')
    asset=(ROOT/relative).resolve()
    resources=(ROOT/'Luqma/Resources').resolve()
    if not asset.is_relative_to(resources) or not asset.is_file():
        raise BuildError('The exact original kitchen photograph has not been supplied under Luqma/Resources.')
    data=asset.read_bytes()
    if not (data.startswith(b'\x89PNG\r\n\x1a\n') or data.startswith(b'\xff\xd8\xff')):
        raise BuildError('The expected original asset is not a native PNG or JPEG photograph.')
    actual=hashlib.sha256(data).hexdigest()
    if actual!=expected_sha256:
        raise BuildError('The kitchen photograph differs from the recorded original; do not substitute or regenerate it.')
    return dict(original_asset=relative.as_posix(),original_asset_sha256=actual,bytes=len(data),
                screenshot_is_original_artwork=False,visual_match_verified=False)


VERIFIED_CHECKS_REVISION='a56ea3ff148c78ef069f91874ca1e318dff09159'
VERIFIED_CHECKS_RUN=41075370035


def focused_build(output: Path) -> None:
    """Repeat both real SDK builds without rerunning unchanged Core/test inputs.

    Previous actual Core/BuildTests evidence is explicitly attributed to its
    immutable run; this invocation never invents or repeats its pass counts.
    """
    require_mac(26)
    if output.exists():
        raise BuildError('Choose a clean build output; do not mix native results.')
    output.mkdir(parents=True)
    report=dict(mode='kitchen-focused-sdk-check',status='running',
                revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
                sdk_builds=[],signed=False,apple_signed=False,ipa_exported=False,
                core_tests_executed_this_run=False,build_tests_executed_this_run=False,
                preceding_core_and_buildtests_run=VERIFIED_CHECKS_RUN,
                preceding_core_and_buildtests_revision=VERIFIED_CHECKS_REVISION)
    try:
        # BuildTests also inspect resources, project metadata, and helper scripts.
        # Permit only this isolated follow-up instead of an incomplete input list.
        followup_files={'.github/workflows/kitchen-cinematic-review.yml',
                        'Luqma/Views/KitchenView.swift',
                        'Scripts/kitchen_cinematic_review.py',
                        'TestsUI/EightScreenReviewTests.swift'}
        changed=subprocess.check_output(['git','diff','--name-only',VERIFIED_CHECKS_REVISION,'--'],cwd=ROOT,text=True).splitlines()
        report['changes_since_preceding_checks']=changed
        changed_inputs=sorted(set(changed)-followup_files)
        report['changes_in_reused_check_inputs']=changed_inputs
        if changed_inputs:
            raise BuildError('Previously tested Core/check inputs changed; run the full check instead of reusing earlier evidence.')
        packages=output/'Packages'
        run(['xcodebuild','-resolvePackageDependencies','-project','Luqma.xcodeproj','-scheme','Luqma',
             '-clonedSourcePackagesDirPath',str(packages)],output/'packages.log')
        apply_vision_compat(packages)
        common=['xcodebuild','-project','Luqma.xcodeproj','-scheme','Luqma',
                '-clonedSourcePackagesDirPath',str(packages),'-disableAutomaticPackageResolution']
        bundle=os.environ.get('BUNDLE_ID','app.luqma.diary')
        number=os.environ.get('BUILD_NUMBER','123')
        if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+',bundle) or not re.fullmatch(r'[1-9][0-9]{0,8}',number):
            raise BuildError('Invalid existing bundle/build configuration.')
        for name,destination,configuration in [('simulator','generic/platform=iOS Simulator','Debug'),
                                                ('device','generic/platform=iOS','Release')]:
            run(common+['-destination',destination,'-configuration',configuration,
                        '-derivedDataPath',str(output/(name+'-derived')),
                        '-resultBundlePath',str(output/(name+'.xcresult')),
                        'CODE_SIGNING_ALLOWED=NO','PRODUCT_BUNDLE_IDENTIFIER='+bundle,
                        'CURRENT_PROJECT_VERSION='+number,'build'],output/(name+'.log'))
            product=output/(name+'-derived')/'Build/Products'/('Debug-iphonesimulator' if name=='simulator' else 'Release-iphoneos')/'Luqma.app'
            if not product.is_dir():
                raise BuildError('The '+name+' SDK build did not produce Luqma.app.')
            report['sdk_builds'].append(dict(platform=name,configuration=configuration,status='passed'))
        apply_vision_compat(packages,verify_only=True)
        report['status']='passed'
    except BaseException as error:
        report.update(status='failed',error=str(error))
        raise
    finally:
        (output/'build-summary.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')


def controls(output: Path, packages: Path, derived: Path) -> None:
    require_mac(26)
    if output.exists():
        raise BuildError('Choose a new output directory; preserve earlier native evidence.')
    output.mkdir(parents=True)
    report=dict(status='running',revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
                baseline=BASELINE,physical_device_tested=False,ipa_exported=False,
                test_scope='Real Kitchen categories, search/clear, keyboard, create/import dismissal, tab state; existing ingredient-search draft flow',
                remote_import_service_tested=False,visual_match_verified=False,scenarios=[])
    try:
        apply_vision_compat(packages)
        inventory=json.loads(command(['xcrun','simctl','list','--json'],output,'inventory'))
        runtime=select_runtime(inventory)
        for name,method,test_class in [
                ('kitchen-controls','testKitchenCategoriesSearchAndActionsRemainUsable','EightScreenReviewTests'),
                ('recipe-draft','testRecipeDraftSurvivesIngredientSearch','LuqmaInteractionTests')]:
            item=dict(name=name,status='running',required_cases=[method])
            report['scenarios'].append(item)
            run_scenario(output/name,packages,derived,runtime,tuple(item['required_cases']),item,
                         os.environ.get('BUILD_NUMBER','123'),
                         signing_settings=['CODE_SIGNING_ALLOWED=YES','CODE_SIGN_IDENTITY=-'],
                         test_class=test_class,timeout_seconds=2700)
        report['status']='passed'
    except BaseException as error:
        report.update(status='failed',error=str(error))
        raise
    finally:
        (output/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    commands=parser.add_subparsers(dest='mode',required=True)
    gate=commands.add_parser('verify-reference')
    gate.add_argument('--asset-path',required=True)
    gate.add_argument('--asset-sha256',required=True)
    gate.add_argument('--output',type=Path,default=Path('Kitchen-Reference-Gate.json'))
    build=commands.add_parser('build-focused')
    build.add_argument('--output',type=Path,default=Path('BuildOutput'))
    test=commands.add_parser('controls')
    test.add_argument('--output',type=Path,default=Path('Kitchen-Controls'))
    test.add_argument('--packages',type=Path,default=Path('BuildOutput/Packages'))
    test.add_argument('--derived',type=Path,default=Path('BuildOutput/simulator-derived'))
    args=parser.parse_args()
    if args.mode=='verify-reference':
        report=verify_reference(args.asset_path,args.asset_sha256)
        args.output.write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
        print('Original photograph byte identity verified; visual review remains required.')
    elif args.mode=='build-focused':
        focused_build(args.output.resolve())
    else:
        controls(args.output.resolve(),args.packages.resolve(),args.derived.resolve())


if __name__=='__main__':
    try: main()
    except (BuildError,OSError,ValueError) as error:
        print(str(error),file=sys.stderr)
        sys.exit(1)
