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
from build_ios import BuildError, require_mac
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
    test=commands.add_parser('controls')
    test.add_argument('--output',type=Path,default=Path('Kitchen-Controls'))
    test.add_argument('--packages',type=Path,default=Path('BuildOutput/Packages'))
    test.add_argument('--derived',type=Path,default=Path('BuildOutput/simulator-derived'))
    args=parser.parse_args()
    if args.mode=='verify-reference':
        report=verify_reference(args.asset_path,args.asset_sha256)
        args.output.write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')
        print('Original photograph byte identity verified; visual review remains required.')
    else:
        controls(args.output.resolve(),args.packages.resolve(),args.derived.resolve())


if __name__=='__main__':
    try: main()
    except (BuildError,OSError,ValueError) as error:
        print(str(error),file=sys.stderr)
        sys.exit(1)
