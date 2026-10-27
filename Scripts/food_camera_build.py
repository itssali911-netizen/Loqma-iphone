#!/usr/bin/env python3
"""Compile both real iOS SDKs independently of Simulator-dependent tests.

Tests run as separate required workflow steps. A failed test still fails the job;
this script neither replaces tests nor reports their outcome as compilation.
"""
import json
import os
from pathlib import Path
from build_ios import run, require_mac
from vision_compat import apply_vision_compat

ROOT=Path(__file__).resolve().parents[1]
require_mac(26)
output=ROOT/'BuildOutput'
output.mkdir(exist_ok=False)
packages=output/'Packages'
run(['xcodebuild','-resolvePackageDependencies','-project','Luqma.xcodeproj','-scheme','Luqma','-clonedSourcePackagesDirPath',str(packages)],output/'packages.log')
apply_vision_compat(packages)
common=['xcodebuild','-project','Luqma.xcodeproj','-scheme','Luqma','-clonedSourcePackagesDirPath',str(packages),'-disableAutomaticPackageResolution']
for name,destination,configuration in [('simulator','generic/platform=iOS Simulator','Debug'),('device','generic/platform=iOS','Release')]:
    run(common+['-destination',destination,'-configuration',configuration,'-derivedDataPath',str(output/(name+'-derived')),'-resultBundlePath',str(output/(name+'.xcresult')),'CODE_SIGNING_ALLOWED=NO','PRODUCT_BUNDLE_IDENTIFIER=app.luqma.diary','CURRENT_PROJECT_VERSION='+os.environ.get('BUILD_NUMBER','1'),'build'],output/(name+'.log'))
apply_vision_compat(packages,verify_only=True)
(output/'build-summary.json').write_text(json.dumps(dict(commit=os.environ.get('GITHUB_SHA'),sdk_builds=['iOS Simulator Debug','iPhone Release'],signed=False,tests='Reported by separate required workflow steps',physical_device_verified=False),indent=2)+'\n')
