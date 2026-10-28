#!/usr/bin/env python3
"""Review-only scope and native UI evidence for the reference calorie card.

Never exports or publishes an IPA. A separate disposable Simulator app renders
the exact production card for controlled component examples; the main app is
tested independently with its real diary controls and persistence.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import uuid
import xml.etree.ElementTree as ET

from build_ios import BuildError, require_mac
from simulator_support import prepare_created_simulator
from ui_preview import (capture_screenshot, command, confirm_process, decode_png,
                        framebuffer_content, select_runtime, validate_app)

ROOT = Path(__file__).resolve().parents[1]
BASELINE = "0198a2d257a993373309a5a470ca35831690d2ef"
DIARY = "Luqma/Views/DiaryView.swift"
CARD = "Luqma/Views/DailyCalorieCard.swift"
ICON_LICENSE = "Luqma/Resources/CalorieCardIcons-LICENSE.txt"
CARD_ASSETS = ("CalorieCardFlame", "CalorieCardProtein", "CalorieCardCarbs", "CalorieCardFat")
NEW_ASSET_FILES = {f"Luqma/Resources/Assets.xcassets/{name}.imageset/{file}"
                   for name in CARD_ASSETS for file in ("source.svg", "Contents.json")}
HOST_SOURCE = "ReviewSupport/CalorieCardReviewApp.swift"
TEST_SOURCE = "TestsUI/CalorieCardInteractionTests.swift"
APP_BUNDLE = "app.luqma.diary"
HOST_BUNDLE = "app.luqma.calorie-review"
TEST_CLASS = "CalorieCardInteractionTests"
START = "    private func dailySummary("
END = "    private func mealList("


def canonical(data: bytes) -> bytes:
    return data.replace(b"\r\n", b"\n")


def diary_scope(before: bytes, after: bytes) -> str | None:
    old, new = canonical(before).decode("utf8"), canonical(after).decode("utf8")
    if any(value.count(marker) != 1 for value in (old, new) for marker in (START, END)):
        return "The original summary/helper boundaries are ambiguous."
    if old[:old.index(START)] != new[:new.index(START)]:
        return "Home content before dailySummary changed."
    if old[old.index(END):] != new[new.index(END):]:
        return "Meal sections or other Home code after dailySummary changed."
    return None


def git(root: Path, *args: str) -> bytes:
    result = subprocess.run(["git", *args], cwd=root, capture_output=True)
    if result.returncode:
        raise BuildError("The authenticated calorie-card baseline or Git operation is unavailable.")
    return result.stdout


def freeze(root: Path = ROOT) -> dict:
    """Compare every app source/asset with the last actually shipped source."""
    report = dict(status="running", baseline=BASELINE, checked_scopes=["working_tree", "index"],
                  permitted_visual_change="dailySummary block, standalone calorie-card component and four named vector icons only",
                  unrelated_app_files_preserved=True, violations=[], changed_app_files=[])
    original = {}
    for record in git(root, "ls-tree", "-r", "-z", BASELINE, "--", "Luqma/").split(b"\0"):
        if record:
            metadata, path = record.split(b"\t", 1)
            mode, kind, digest = metadata.decode().split()
            if kind != "blob": raise BuildError("The baseline app inventory contains an unsupported Git object.")
            original[path.decode("utf8")] = (mode, digest)
    if DIARY not in original or CARD in original:
        raise BuildError("The verified baseline is not the expected pre-card application.")
    staged = {}
    for record in git(root, "ls-files", "--stage", "-z", "--", "Luqma/").split(b"\0"):
        if record:
            metadata, path = record.split(b"\t", 1)
            mode, digest, stage = metadata.decode().split()
            if stage != "0": raise BuildError("Resolve Git index conflicts before native UI review.")
            staged[path.decode("utf8")] = (mode, digest)
    extras = set()
    for args in (("--others", "--exclude-standard"), ("--others", "--ignored", "--exclude-standard")):
        extras.update(value.decode("utf8") for value in git(root, "ls-files", *args, "-z", "--", "Luqma/").split(b"\0") if value)
    for path in sorted(set(original) | set(staged) | extras):
        before_entry = original.get(path)
        before = git(root, "cat-file", "blob", before_entry[1]) if before_entry else None
        for scope in ("working_tree", "index"):
            file = root/path
            if scope == "working_tree":
                present = file.is_file() and not file.is_symlink()
                after = file.read_bytes() if present else None
                mode = staged.get(path, before_entry or ("100644", ""))[0] if present else None
                if present and os.name != "nt": mode = "100755" if file.stat().st_mode & 0o111 else "100644"
            else:
                entry = staged.get(path)
                after = git(root, "cat-file", "blob", entry[1]) if entry else None
                mode = entry[0] if entry else None
            text_file=Path(path).suffix in {".swift",".json",".strings",".plist",".xcprivacy",".entitlements",".storyboard",".txt",".svg"}
            if before == after or text_file and before is not None and after is not None and canonical(before) == canonical(after):
                if before_entry is None or mode == before_entry[0]: continue
            problem = None
            if before_entry is not None and mode != before_entry[0]:
                problem = "An original app file was removed or its mode changed."
            elif path == DIARY and before is not None and after is not None:
                problem = diary_scope(before, after)
            elif path == CARD and before is None and after is not None and mode == "100644":
                try: after.decode("utf8")
                except UnicodeError: problem = "The new component must remain Swift source text."
            elif path in NEW_ASSET_FILES and before is None and after is not None and mode == "100644":
                try:
                    if path.endswith(".json"): json.loads(after)
                    else:
                        if ET.fromstring(after).tag.rsplit("}",1)[-1] != "svg":
                            problem = "The named icon source must be an SVG document."
                except (ValueError,UnicodeError,ET.ParseError): problem = "The new named icon contains invalid vector or catalog data."
            elif path == ICON_LICENSE and before is None and after is not None and mode == "100644":
                try:
                    copy=after.decode("utf8")
                    if len(copy)<200 or "ISC" not in copy or "ermission" not in copy:
                        problem = "The new vector icon license must contain the complete ISC permission notice."
                except UnicodeError:problem = "The icon license must remain UTF-8 text."
            else:
                problem = "An unrelated app source, asset, font, configuration or capability changed."
            if path not in report["changed_app_files"]: report["changed_app_files"].append(path)
            if problem: report["violations"].append(dict(path=path, scope=scope, reason=problem))
    report["baseline_app_files"] = len(original)
    report["unrelated_app_files_preserved"] = not report["violations"]
    report["status"] = "failed" if report["violations"] else "passed"
    return report


class Ref(str): pass


def encode(value, level=0) -> str:
    if isinstance(value, Ref): return str(value)
    if isinstance(value, dict):
        return "{\n"+"".join("\t"*(level+1)+json.dumps(str(key))+" = "+encode(item, level+1)+";\n" for key,item in value.items())+"\t"*level+"}"
    if isinstance(value, list): return "(\n"+"".join("\t"*(level+1)+encode(item, level+1)+",\n" for item in value)+"\t"*level+")"
    return str(value) if isinstance(value, int) else json.dumps(str(value), ensure_ascii=False)


def generate_host(folder: Path, root: Path = ROOT) -> dict:
    """Generate only build-output metadata; reference original production files."""
    if folder.exists(): raise BuildError("The review host requires a fresh output directory.")
    host_source = root/HOST_SOURCE
    if not host_source.is_file(): raise BuildError("The review-only component host source is missing.")
    info = plistlib.loads((root/"Luqma/Info.plist").read_bytes())
    fonts = info.get("UIAppFonts", [])
    if not fonts or len(fonts) != len(set(fonts)) or not all(isinstance(name,str) and Path(name).name == name and (root/"Luqma/Resources"/name).is_file() for name in fonts):
        raise BuildError("The component review must use the application's actual registered bundled fonts.")
    sources = [*sorted((root/"Luqma/Core").glob("*.swift")), root/CARD, root/"Luqma/Views/LuqmaTypography.swift", host_source]
    if any(not path.is_file() for path in sources): raise BuildError("An exact production source required by the host is unavailable.")
    folder.mkdir(parents=True)
    project = folder/"CalorieCardReview.xcodeproj";project.mkdir()
    objects = {}
    def add(key, isa, **values):
        identifier=Ref(hashlib.sha256(("calorie-card-host:"+key).encode()).hexdigest()[:24].upper())
        objects[identifier]=dict(isa=isa,**values);return identifier
    source_builds=[];font_builds=[];file_refs=[]
    license_file=root/ICON_LICENSE
    if not license_file.is_file():raise BuildError("The production vector icon license resource is missing.")
    for path in [*sources,*(root/"Luqma/Resources"/name for name in fonts),license_file]:
        relative=path.relative_to(root).as_posix()
        ref=add("file:"+relative,"PBXFileReference",lastKnownFileType="sourcecode.swift" if path.suffix==".swift" else "file",
                path=os.path.relpath(path,folder).replace(os.sep,"/"),sourceTree="<group>")
        file_refs.append(ref)
        build=add("build:"+relative,"PBXBuildFile",fileRef=ref)
        (source_builds if path.suffix==".swift" else font_builds).append(build)
    assets=folder/"Assets.xcassets";assets.mkdir()
    original_assets=root/"Luqma/Resources/Assets.xcassets"
    shutil.copy2(original_assets/"Contents.json",assets/"Contents.json")
    asset_hashes={}
    for name in CARD_ASSETS:
        source=original_assets/(name+".imageset")
        if not source.is_dir() or {p.name for p in source.iterdir()} != {"source.svg","Contents.json"}:
            raise BuildError("A required named calorie-card vector imageset is unavailable or unexpected.")
        shutil.copytree(source,assets/source.name)
        for file in ("source.svg","Contents.json"):
            asset_hashes[f"{name}.imageset/{file}"]=hashlib.sha256((source/file).read_bytes()).hexdigest()
    asset_ref=add("assets","PBXFileReference",lastKnownFileType="folder.assetcatalog",path="Assets.xcassets",sourceTree="<group>")
    file_refs.append(asset_ref)
    font_builds.append(add("assets:build","PBXBuildFile",fileRef=asset_ref))
    product=add("product","PBXFileReference",explicitFileType="wrapper.application",path="CalorieCardReview.app",sourceTree="BUILT_PRODUCTS_DIR")
    products=add("products","PBXGroup",children=[product],name="Products",sourceTree="<group>")
    main=add("main","PBXGroup",children=file_refs+[products],sourceTree="<group>")
    phases=[add("sources","PBXSourcesBuildPhase",buildActionMask=2147483647,files=source_builds,runOnlyForDeploymentPostprocessing=0),
            add("frameworks","PBXFrameworksBuildPhase",buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0),
            add("resources","PBXResourcesBuildPhase",buildActionMask=2147483647,files=font_builds,runOnlyForDeploymentPostprocessing=0)]
    project_config=add("project:debug","XCBuildConfiguration",name="Debug",buildSettings=dict(CLANG_ENABLE_MODULES="YES",CLANG_ENABLE_OBJC_ARC="YES",SDKROOT="iphoneos",IPHONEOS_DEPLOYMENT_TARGET="17.0",DEBUG_INFORMATION_FORMAT="dwarf"))
    target_config=add("target:debug","XCBuildConfiguration",name="Debug",buildSettings=dict(CODE_SIGN_STYLE="Automatic",DEVELOPMENT_TEAM="",CODE_SIGN_IDENTITY="-",GENERATE_INFOPLIST_FILE="NO",INFOPLIST_FILE="Info.plist",PRODUCT_BUNDLE_IDENTIFIER=HOST_BUNDLE,PRODUCT_NAME="CalorieCardReview",SDKROOT="iphoneos",SUPPORTED_PLATFORMS="iphonesimulator",SUPPORTS_MACCATALYST="NO",IPHONEOS_DEPLOYMENT_TARGET="17.0",TARGETED_DEVICE_FAMILY="1",SWIFT_VERSION="5.0",SWIFT_STRICT_CONCURRENCY="minimal",SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG $(inherited)",SWIFT_OPTIMIZATION_LEVEL="-Onone",ONLY_ACTIVE_ARCH="YES",LD_RUNPATH_SEARCH_PATHS=["$(inherited)","@executable_path/Frameworks"]))
    pc=add("project:configs","XCConfigurationList",buildConfigurations=[project_config],defaultConfigurationIsVisible=0,defaultConfigurationName="Debug")
    tc=add("target:configs","XCConfigurationList",buildConfigurations=[target_config],defaultConfigurationIsVisible=0,defaultConfigurationName="Debug")
    target=add("target","PBXNativeTarget",buildConfigurationList=tc,buildPhases=phases,buildRules=[],dependencies=[],name="CalorieCardReview",productName="CalorieCardReview",productReference=product,productType="com.apple.product-type.application")
    root_object=add("project","PBXProject",attributes=dict(BuildIndependentTargetsInParallel="YES",LastUpgradeCheck="1600",TargetAttributes={target:dict(CreatedOnToolsVersion="16.0",ProvisioningStyle="Automatic")}),buildConfigurationList=pc,compatibilityVersion="Xcode 14.0",developmentRegion="ar",hasScannedForEncodings=0,knownRegions=["ar","en","Base"],mainGroup=main,productRefGroup=products,projectDirPath="",projectRoot="",targets=[target])
    (project/"project.pbxproj").write_text("// !$*UTF8*$!\n"+encode(dict(archiveVersion=1,classes={},objectVersion=56,objects=objects,rootObject=root_object))+"\n",encoding="utf8")
    bp=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="CalorieCardReview.app" BlueprintName="CalorieCardReview" ReferencedContainer="container:CalorieCardReview.xcodeproj"/>'
    schemes=project/"xcshareddata/xcschemes";schemes.mkdir(parents=True)
    (schemes/"CalorieCardReview.xcscheme").write_text(f'<?xml version="1.0" encoding="UTF-8"?>\n<Scheme LastUpgradeVersion="1600" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="NO" buildForArchiving="NO" buildForAnalyzing="YES">{bp}</BuildActionEntry></BuildActionEntries></BuildAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="NO"><BuildableProductRunnable runnableDebuggingMode="0">{bp}</BuildableProductRunnable></LaunchAction><AnalyzeAction buildConfiguration="Debug"/></Scheme>\n',encoding="utf8")
    host_info=dict(CFBundleDevelopmentRegion="ar",CFBundleDisplayName="Luqma Card Review",CFBundleExecutable="$(EXECUTABLE_NAME)",CFBundleIdentifier="$(PRODUCT_BUNDLE_IDENTIFIER)",CFBundleInfoDictionaryVersion="6.0",CFBundleName="CalorieCardReview",CFBundlePackageType="APPL",CFBundleShortVersionString="1.0",CFBundleVersion="1",LSRequiresIPhoneOS=True,MinimumOSVersion="17.0",UILaunchScreen={},UIUserInterfaceStyle="Dark",UISupportedInterfaceOrientations=["UIInterfaceOrientationPortrait"],UIAppFonts=fonts)
    (folder/"Info.plist").write_bytes(plistlib.dumps(host_info))
    return dict(project=str(project),scheme="CalorieCardReview",bundle_id=HOST_BUNDLE,
                exact_production_card_sha256=hashlib.sha256((root/CARD).read_bytes()).hexdigest(),
                exact_typography_sha256=hashlib.sha256((root/"Luqma/Views/LuqmaTypography.swift").read_bytes()).hexdigest(),
                source_files=[path.relative_to(root).as_posix() for path in sources],fonts=fonts,
                exact_production_card_asset_sha256=asset_hashes,
                component_examples_are_synthetic=True,production_diary_mutated_by_host=False)


def host_source_hashes(root: Path = ROOT) -> dict:
    files=[*sorted((root/"Luqma/Core").glob("*.swift")),root/CARD,root/"Luqma/Views/LuqmaTypography.swift",root/HOST_SOURCE,root/ICON_LICENSE,
           *(root/"Luqma/Resources"/name for name in plistlib.loads((root/"Luqma/Info.plist").read_bytes())["UIAppFonts"]),
           *(root/path for path in sorted(NEW_ASSET_FILES))]
    return {file.relative_to(root).as_posix():hashlib.sha256(file.read_bytes()).hexdigest() for file in files}


def preflight_host(render: bool = True) -> dict:
    require_mac()
    output=ROOT/"Restore103Validation/CalorieCardHost"
    if output.exists():raise BuildError("The native host preflight requires a fresh output directory.")
    output.mkdir(parents=True)
    report=dict(status="running",commit=os.environ.get("GITHUB_SHA","local"),source_hashes=host_source_hashes(),screenshots=[],fresh_simulator=False,existing_user_device_modified=False)
    device=None
    try:
        host=generate_host(output/"Host")
        derived=output/"Derived"
        command(["xcodebuild","-project",host["project"],"-scheme",host["scheme"],"-configuration","Debug","-destination","generic/platform=iOS Simulator","-derivedDataPath",str(derived),"ARCHS=arm64","ONLY_ACTIVE_ARCH=YES","CODE_SIGNING_ALLOWED=YES","CODE_SIGN_IDENTITY=-","build"],output,"component-host-build",900)
        app=derived/"Build/Products/Debug-iphonesimulator/CalorieCardReview.app"
        host["built_app"]=validate_app(app,HOST_BUNDLE,output)
        report.update(status="passed",component_host=host,app_path=str(app),executable_sha256=hashlib.sha256((app/"CalorieCardReview").read_bytes()).hexdigest(),render_validation_requested=render)
        if not render:
            # The strict review renders all 18 cases and tests interactions on
            # its own fresh Simulator after the main app is built. Do not boot
            # a redundant Simulator here or claim this build-only step rendered.
            return report
        inventory=json.loads(command(["xcrun","simctl","list","--json"],output,"preflight-inventory"))
        runtime=select_runtime(inventory)
        device=command(["xcrun","simctl","create","Luqma Card Preflight "+uuid.uuid4().hex[:8],"com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max",runtime["identifier"]],output,"preflight-create").strip()
        if re.fullmatch(r"[0-9A-Fa-f-]{36}",device) is None:
            device=None;raise BuildError("Preflight Simulator creation returned an invalid identifier.")
        report["fresh_simulator"]=True;report["simulator_runtime"]=runtime["name"]
        report["preparation"]=prepare_created_simulator(device,lambda args,label,timeout:command(args,output,label,timeout))
        command(["xcrun","simctl","ui",device,"appearance","dark"],output,"preflight-appearance")
        command(["xcrun","simctl","install",device,str(app)],output,"preflight-install",120)
        capture_component_cases(device,output,report,[dict(state="zero",width=width,language="ar",dynamic_type="large") for width in (390,320)])
    except BaseException as error:
        report.update(status="failed",error=str(error));raise
    finally:
        if device:
            for action in ("shutdown","delete"):
                try:command(["xcrun","simctl",action,device],output,"preflight-cleanup-"+action,90,allow_failure=True)
                except (BuildError,OSError):report.setdefault("cleanup_warnings",[]).append("Caller-created preflight Simulator cleanup did not complete.")
        (output/"host-build-report.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf8")
    return report


def verified_preflight_host() -> dict:
    directory=ROOT/"Restore103Validation/CalorieCardHost"
    file=directory/"host-build-report.json"
    if not file.is_file():return preflight_host()
    report=json.loads(file.read_text("utf8"))
    app=Path(report.get("app_path",""))
    if (report.get("status")!="passed" or report.get("commit")!=os.environ.get("GITHUB_SHA","local")
            or report.get("source_hashes")!=host_source_hashes()
            or not app.resolve().is_relative_to(directory.resolve()) or not (app/"CalorieCardReview").is_file()
            or hashlib.sha256((app/"CalorieCardReview").read_bytes()).hexdigest()!=report.get("executable_sha256")):
        raise BuildError("The native component host preflight is stale or belongs to different source bytes.")
    return report


def component_geometry_matches(value, case: dict, pid: int, token: str) -> bool:
    """Reject preceding launches and pre-layout/transient sizes, even for identical cases."""
    if not isinstance(value, dict): return False
    expected = (value.get("process_id") == pid and value.get("capture_token") == token
                and value.get("state") == case["state"] and value.get("language") == case["language"]
                and value.get("canvas_width") == case["width"] and value.get("dynamic_type") == case["dynamic_type"])
    frame = value.get("card_frame", {})
    if not expected or not isinstance(frame, dict): return False
    numeric = all(type(frame.get(key)) in (int, float) and abs(frame[key]) < 100_000 for key in ("x", "y", "width", "height"))
    return (numeric and frame["height"] > 0 and abs(frame["width"]-(case["width"]-32)) <= 1
            and type(value.get("scale")) in (int, float) and 1 <= value["scale"] <= 4)


def capture_component_cases(device: str, output: Path, report: dict, cases: list[dict] | None = None) -> None:
    if cases is None:
        cases=[dict(state="zero",width=width,language="ar",dynamic_type="large") for width in (320,375,390,430)]
        cases += [dict(state=state,width=390,language="ar",dynamic_type="large") for state in ("partial","met","exceeded","missing","loading")]
        cases += [dict(state="long",width=width,language="ar",dynamic_type="large") for width in (320,390)]
        cases += [dict(state="partial",width=width,language="ar",dynamic_type="accessibility3") for width in (320,390)]
        cases += [dict(state=state,width=390,language="en",dynamic_type="large") for state in ("zero","partial")]
        cases += [dict(state="extreme",width=width,language="ar",dynamic_type="accessibility3") for width in (320,390)]
        cases += [dict(state="extreme",width=320,language="en",dynamic_type="accessibility3")]
    captures=output/"captures";captures.mkdir(exist_ok=True)
    container=Path(command(["xcrun","simctl","get_app_container",device,HOST_BUNDLE,"data"],output,"component-data-container",90).strip())
    if not container.is_absolute() or not container.is_dir():
        raise BuildError("The caller-created component host data container is unavailable.")
    geometry_file=container/"Documents/review-geometry.json"
    report["component_cases"]=[]
    for index,case in enumerate(cases):
        name=f'calorie-card-component-{case["language"]}-{case["state"]}-{case["width"]}-{case["dynamic_type"]}'
        token=uuid.uuid4().hex
        args=["--state",case["state"],"--width",str(case["width"]),"--language",case["language"],"--dynamic-type",case["dynamic_type"],
              "--capture-token",token,
              "-AppleLanguages","("+case["language"]+")","-AppleLocale","ar_SA" if case["language"]=="ar" else "en_US"]
        launched=command(["xcrun","simctl","launch","--terminate-running-process",device,HOST_BUNDLE,*args],output,"launch-"+name,180 if index==0 else 90)
        match=re.search(r":\s*(\d+)\s*$",launched)
        if not match:raise BuildError("The exact component host returned no actual process identifier.")
        pid=int(match.group(1));confirm_process(pid,3)
        # A busy CI Simulator can start the process before its first SwiftUI layout.
        # Wait for actual geometry from this PID/nonce instead of accepting an old file.
        deadline=time.monotonic()+45;geometry=None;last_geometry=None;stable_since=None
        while time.monotonic()<deadline:
            try:
                value=json.loads(geometry_file.read_text("utf8"))
                if component_geometry_matches(value,case,pid,token):
                    if value != last_geometry: stable_since=time.monotonic()
                    elif stable_since is not None and time.monotonic()-stable_since >= 0.3:
                        geometry=value;break
                else: stable_since=None
                last_geometry=value
            except (OSError,ValueError,TypeError): pass
            confirm_process(pid,0.1)
        if geometry is None:
            (captures/(name+"-rejected-geometry.json")).write_text(json.dumps(dict(expected_case=case,expected_process_id=pid,expected_capture_token=token,last_observed=last_geometry),indent=2)+"\n",encoding="utf8")
            raise BuildError("The native component geometry is missing, stale or does not match the requested review state.")
        screenshot=captures/(name+".png")
        details=capture_screenshot(output,device,name,pid,screenshot)
        scale=geometry["scale"];frame=geometry["card_frame"]
        card_pixels={key:round(frame[key]*scale,3) for key in ("x","y","width","height")}
        fully_visible=(card_pixels["x"]>=0 and card_pixels["y"]>=0 and card_pixels["x"]+card_pixels["width"]<=details["width"]+1 and card_pixels["y"]+card_pixels["height"]<=details["height"]+1)
        (captures/(name+"-geometry.json")).write_text(json.dumps(geometry,indent=2)+"\n",encoding="utf8")
        record={**case,**details,"canvas_width_points":case["width"],"name":name,"file":str(screenshot.relative_to(output)),"source":"Actual Simulator framebuffer captured with simctl io screenshot","scope":"review-only native component host; synthetic presentation inputs","synthetic_fixture":True,"process_still_running":True,"native_geometry":geometry,"card_frame_pixels":card_pixels,"card_fully_visible_in_frame":fully_visible}
        report["screenshots"].append(record);report["component_cases"].append(record)
    if len(report["component_cases"])!=len(cases):
        raise BuildError("The native component host did not cover every required review state.")
    command(["xcrun","simctl","terminate",device,HOST_BUNDLE],output,"terminate-component-host",90,allow_failure=True)


def collect_attachments(output: Path, report: dict) -> None:
    result=output/"calorie-card.xcresult"
    if not result.exists(): return
    directory=output/"test-attachments"
    command(["xcrun","xcresulttool","export","attachments","--path",str(result),"--output-path",str(directory)],output,"export-attachments",180)
    manifest=json.loads((directory/"manifest.json").read_text("utf8"))
    captures=output/"captures";captures.mkdir(exist_ok=True)
    seen=set()
    for test in manifest:
        for item in test.get("attachments",[]):
            name=item.get("suggestedHumanReadableName","")
            match=re.match(r"^(calorie-card-(?:home|component)-[a-zA-Z0-9-]+)(?:_|\.)",name)
            if not match: continue
            key=match.group(1)
            source=directory/item.get("exportedFileName","")
            if source.resolve().parent != directory.resolve() or source.suffix.lower() != ".png":
                raise BuildError("An unexpected native attachment path was returned.")
            # XCTest can preserve a failure screenshot from several test cases.
            # Keep every original attachment rather than masking the real test
            # failure with an unrelated duplicate-filename exception.
            if key in seen:
                suffix = 2
                while key + "-" + str(suffix) in seen: suffix += 1
                key += "-" + str(suffix)
            seen.add(key);target=captures/(key+".png");shutil.copy2(source,target)
            data=target.read_bytes();width,height,channels,pixels,frame=decode_png(data,target.name)
            if width<200 or height<100: raise BuildError("A native card screenshot is unexpectedly small.")
            content=framebuffer_content(width,height,channels,pixels)
            if content["near_empty_black_frame"]: raise BuildError("A native screenshot contains a near-empty black frame.")
            report["screenshots"].append(dict(name=key,file=str(target.relative_to(output)),width=width,height=height,bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),frame_sha256=hashlib.sha256(frame).hexdigest(),source="Native XCTest screenshot attachment",scope="production main-app Home" if key.startswith("calorie-card-home-") else "review-only native component host; synthetic presentation inputs",**content))
    if not any(name.startswith("calorie-card-home-") for name in seen):
        raise BuildError("The actual production Home screenshot is missing.")
    if not any(item["name"].startswith("calorie-card-component-") for item in report["screenshots"]):
        raise BuildError("Native component reference screenshots are missing.")


def validate() -> dict:
    require_mac()
    output=ROOT/"BuildOutput/CalorieCardReview"
    if output.exists(): raise BuildError("Native calorie-card evidence needs a fresh output directory.")
    output.mkdir(parents=True)
    report=dict(status="running",commit=os.environ.get("GITHUB_SHA","local"),baseline=BASELINE,approval_required=True,
                merged=False,ipa_published=False,physical_device_tested=False,promotion_120hz_tested=False,
                test_status="not_run",required_tests=[],passed_tests=[],screenshots=[],errors=[],
                fresh_simulator=False,existing_user_device_modified=False)
    device=None
    try:
        scope=freeze();report["source_scope"]=scope
        if scope["status"]!="passed": raise BuildError("Unrelated application source changed beyond the approved card region.")
        test_source=(ROOT/TEST_SOURCE).read_text("utf8")
        tests=re.findall(r"\bfunc\s+(test[A-Za-z0-9_]+)\s*\(",test_source)
        if len(tests)<4 or len(tests)!=len(set(tests)):
            raise BuildError("The dedicated native calorie-card suite must declare at least four unique tests.")
        report["required_tests"]=tests
        derived=ROOT/"BuildOutput/simulator-derived";packages=ROOT/"BuildOutput/Packages"
        app=derived/"Build/Products/Debug-iphonesimulator/Luqma.app"
        report["prebuilt_app"]=validate_app(app,APP_BUNDLE,output)
        preflight=verified_preflight_host();report["component_host"]=preflight["component_host"]
        report["component_host_preflight_source_bytes_verified"]=True
        host_app=Path(preflight["app_path"])
        inventory=json.loads(command(["xcrun","simctl","list","--json"],output,"inventory"))
        runtime=select_runtime(inventory)
        device=command(["xcrun","simctl","create","Luqma Card Review "+uuid.uuid4().hex[:8],"com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max",runtime["identifier"]],output,"create").strip()
        if re.fullmatch(r"[0-9A-Fa-f-]{36}",device) is None:
            device=None;raise BuildError("Simulator creation returned an invalid identifier.")
        report["fresh_simulator"]=True;report["simulator_runtime"]=runtime["name"]
        report["preparation"]=prepare_created_simulator(device,lambda args,label,timeout:command(args,output,label,timeout))
        command(["xcrun","simctl","ui",device,"appearance","dark"],output,"appearance")
        command(["xcrun","simctl","install",device,str(host_app)],output,"install-component-host",120)
        capture_component_cases(device,output,report)
        try:
            extra = ["-only-testing:LuqmaUITests/LuqmaInteractionTests"] if os.environ.get("LUQMA_STRICT_DESIGN_REVIEW") == "1" else []
            log=command(["xcodebuild","-project","Luqma.xcodeproj","-scheme","Luqma","-clonedSourcePackagesDirPath",str(packages),"-disableAutomaticPackageResolution","-destination","id="+device,"-configuration","Debug","-derivedDataPath",str(derived),"-resultBundlePath",str(output/"calorie-card.xcresult"),"-parallel-testing-enabled","NO","-only-testing:LuqmaUITests/"+TEST_CLASS,*extra,"ARCHS=arm64","ONLY_ACTIVE_ARCH=YES","CODE_SIGNING_ALLOWED=YES","CODE_SIGN_IDENTITY=-","CURRENT_PROJECT_VERSION="+os.environ.get("BUILD_NUMBER","121"),"test"],output,"native-calorie-card-tests",1800)
            report["passed_tests"]=[name for name in tests if re.search(r"Test Case '.*\b"+re.escape(name)+r"\b.*' passed",log)]
            if set(report["passed_tests"])!=set(tests): raise BuildError("The native run did not execute and pass every required card test.")
            report["test_status"]="passed"
        except BuildError as error:
            report["test_status"]="failed";report["errors"].append(str(error))
        collect_attachments(output,report)
        report["tested_app"]=validate_app(app,APP_BUNDLE,output)
        report["simulator_executable_sha256"]=hashlib.sha256((app/"Luqma").read_bytes()).hexdigest()
        if report["errors"]: raise BuildError("; ".join(report["errors"]))
        report["status"]="passed"
    except BaseException as error:
        report["status"]="failed"
        if str(error) not in report["errors"]: report["errors"].append(str(error))
        raise
    finally:
        if device:
            for action in ("shutdown","delete"):
                try:command(["xcrun","simctl",action,device],output,"cleanup-"+action,90,allow_failure=True)
                except (BuildError,OSError):report.setdefault("cleanup_warnings",[]).append("Caller-created Simulator cleanup did not complete.")
        (output/"report.json").write_text(json.dumps(report,indent=2)+"\n",encoding="utf8")
    return report


class ScopeTests(unittest.TestCase):
    def test_only_the_summary_region_can_change(self):
        before=("prefix\n"+START+"old)\nold helpers\n"+END+"same\nsuffix").encode()
        after=("prefix\n"+START+"new)\nnew component\n"+END+"same\nsuffix").encode()
        self.assertIsNone(diary_scope(before,after))
        self.assertIsNotNone(diary_scope(before,after.replace(b"prefix",b"changed")))
        self.assertIsNotNone(diary_scope(before,after.replace(b"suffix",b"changed")))
        self.assertIsNotNone(diary_scope(before,after+START.encode()))
    def test_canonical_crlf_does_not_change_scope(self):
        before=(START+"old\n"+END+"end\n").encode()
        self.assertIsNone(diary_scope(before,before.replace(b"\n",b"\r\n")))
    def test_geometry_requires_this_launch_and_final_canvas_width(self):
        case=dict(state="zero",width=320,language="ar",dynamic_type="large")
        value=dict(state="zero",canvas_width=320,language="ar",dynamic_type="large",process_id=123,
                   capture_token="this-launch",scale=3,card_frame=dict(x=76,y=112,width=288,height=200))
        self.assertTrue(component_geometry_matches(value,case,123,"this-launch"))
        self.assertFalse(component_geometry_matches(value,case,124,"this-launch"))
        self.assertFalse(component_geometry_matches(value,case,123,"preceding-launch"))
        self.assertFalse(component_geometry_matches({**value,"state":"partial"},case,123,"this-launch"))
        for width in (0,358,True,float("nan"),float("inf")):
            self.assertFalse(component_geometry_matches({**value,"card_frame":{**value["card_frame"],"width":width}},case,123,"this-launch"))
    def test_capture_keeps_native_pixels_separate_from_canvas_points(self):
        # This tests capture bookkeeping only; it is never evidence of native rendering.
        with tempfile.TemporaryDirectory() as temporary:
            output=Path(temporary);container=output/"mock-container";(container/"Documents").mkdir(parents=True)
            def fake_command(args,*_args,**_kwargs):
                if "get_app_container" in args: return str(container)
                if "launch" in args:
                    token=args[args.index("--capture-token")+1]
                    (container/"Documents/review-geometry.json").write_text(json.dumps(dict(
                        state="zero",canvas_width=320,language="ar",dynamic_type="large",process_id=123,
                        capture_token=token,scale=3,card_frame=dict(x=76,y=112,width=288,height=200))),encoding="utf8")
                    return HOST_BUNDLE+": 123"
                return ""
            report=dict(screenshots=[])
            module=sys.modules[__name__]
            with patch.object(module,"command",side_effect=fake_command), \
                    patch.object(module,"confirm_process",side_effect=lambda _pid,seconds: time.sleep(min(seconds,0.1))), \
                    patch.object(module,"capture_screenshot",return_value=dict(width=1320,height=2868)):
                capture_component_cases("mock-simulator",output,report,[dict(state="zero",width=320,language="ar",dynamic_type="large")])
            record=report["component_cases"][0]
            self.assertEqual(record["width"],1320)
            self.assertEqual(record["canvas_width_points"],320)
            self.assertEqual(record["card_frame_pixels"]["width"],864)
            self.assertTrue(record["card_fully_visible_in_frame"])


def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode",nargs="?",default="validate",choices=("freeze","host-preflight","validate"))
    parser.add_argument("--output",type=Path)
    parser.add_argument("--self-test",action="store_true")
    args=parser.parse_args()
    if args.self_test:
        result=unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(ScopeTests))
        return 0 if result.wasSuccessful() else 1
    try:
        report=freeze() if args.mode=="freeze" else preflight_host() if args.mode=="host-preflight" else validate()
        if args.output:
            args.output.parent.mkdir(parents=True,exist_ok=True)
            args.output.write_text(json.dumps(report,indent=2)+"\n",encoding="utf8")
        print(json.dumps(report,indent=2))
        return 0 if report["status"]=="passed" else 1
    except (BuildError,OSError,ValueError) as error:
        print("Calorie card review: "+str(error),file=sys.stderr);return 1


def interrupted(signum,_frame): raise SystemExit(128+signum)
if __name__=="__main__":
    signal.signal(signal.SIGTERM,interrupted)
    raise SystemExit(main())
