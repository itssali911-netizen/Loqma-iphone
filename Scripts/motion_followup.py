#!/usr/bin/env python3
"""Recheck corrected UI automation against the already compiled motion source.

The complete SDK, Core, font and screenshot evidence belongs to ef485cb. This
runner refuses to reuse that evidence if any production input has changed.
It exercises the real application again; no assertion or result is synthesized.
"""
from pathlib import Path
import hashlib,json,os,re,subprocess,sys
from build_ios import BuildError,require_mac
from ui_interactions import run_scenario
from ui_preview import command,select_runtime
from vision_compat import apply_vision_compat

ROOT=Path(__file__).resolve().parents[1]
VERIFIED='ef485cbae17c519809a6d8dde6ef790f4d7931bd'
INPUTS=['Luqma','Luqma.xcodeproj','Package.swift','Scripts/qwen3vl-compat.json','Scripts/vision_compat.py']

def main():
    require_mac(26)
    output=ROOT/'Motion-Followup'
    if output.exists():raise BuildError('Preserve existing evidence and choose a clean checkout.')
    output.mkdir()
    report=dict(status='running',verified_production_revision=VERIFIED,
                revision=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
                earlier_run=40780795084,scenarios=[],physical_device_tested=False,
                fps='Not Measured',ipa_exported=False,merged=False)
    try:
        changed=subprocess.check_output(['git','diff','--name-only',VERIFIED,'HEAD','--',*INPUTS],cwd=ROOT,text=True).splitlines()
        report['production_input_changes']=changed
        if changed:raise BuildError('Production inputs changed: do not reuse the previous build/screenshots.')
        report['identical_production_inputs']=True
        report['production_source_tree']=subprocess.check_output(['git','rev-parse','HEAD:Luqma'],cwd=ROOT,text=True).strip()
        packages=ROOT/'BuildOutput/Packages';derived=ROOT/'BuildOutput/simulator-derived'
        command(['xcodebuild','-resolvePackageDependencies','-project','Luqma.xcodeproj','-scheme','Luqma',
                 '-clonedSourcePackagesDirPath',str(packages)],output,'resolve-packages',900)
        lock=ROOT/'Luqma.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
        data=lock.read_bytes();(output/'Package.resolved').write_bytes(data)
        report['package_lock_sha256']=hashlib.sha256(data).hexdigest()
        apply_vision_compat(packages)
        inventory=json.loads(command(['xcrun','simctl','list','--json'],output,'simulator-inventory'))
        runtime=select_runtime(inventory)
        # Every legacy method except denial runs on one new device. Denial was
        # already verified independently; never reset native permission state.
        legacy=tuple(n for n in re.findall(r'\bfunc\s+(test\w+)\s*\(',
                         (ROOT/'TestsUI/LuqmaInteractionTests.swift').read_text('utf8'))
                     if n!='testNotificationDeniedDoesNotClaimDelivery')
        motion=tuple(re.findall(r'\bfunc\s+(test\w+)\s*\(',
                         (ROOT/'TestsUI/MotionInteractionTests.swift').read_text('utf8')))
        if len(legacy)!=7 or len(motion)!=2:raise BuildError('Unexpected test inventory; inspect before changing coverage.')
        failures=[]
        for name,methods,test_class,record in [('legacy',legacy,'LuqmaInteractionTests',False),
                                              ('native-motion',motion,'MotionInteractionTests',True)]:
            item=dict(name=name,status='running',required_cases=list(methods));report['scenarios'].append(item)
            try:
                run_scenario(output/name,packages,derived,runtime,methods,item,
                             os.environ.get('BUILD_NUMBER','123'),
                             signing_settings=['CODE_SIGNING_ALLOWED=YES','CODE_SIGN_IDENTITY=-'],
                             test_class=test_class,record_video=record)
            except (BuildError,OSError,ValueError) as error:failures.append(str(error))
        if failures:raise BuildError('; '.join(failures))
        report['status']='passed'
    except BaseException as error:
        report.update(status='failed',error=str(error));raise
    finally:
        (output/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf8')

if __name__=='__main__':
    try:main()
    except (BuildError,OSError,ValueError) as error:print(str(error),file=sys.stderr);sys.exit(1)
