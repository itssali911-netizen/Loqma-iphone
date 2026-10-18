#!/usr/bin/env python3
"""Generate the committed Xcode project. Standard library only; stable IDs."""
from pathlib import Path
import hashlib
import json
import plistlib

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / 'Luqma'
PROJECT = ROOT / 'Luqma.xcodeproj'
PROJECT.mkdir(exist_ok=True)
objects = {}

class Ref(str):
    pass

def identity(key):
    return Ref(hashlib.sha256(key.encode()).hexdigest()[:24].upper())

def add(key, isa, **values):
    identifier = identity(key)
    objects[identifier] = dict(isa=isa, **values)
    return identifier

def ref(key):
    return identity(key)

def encode(v, level=0):
    if isinstance(v, Ref):
        return str(v)
    if isinstance(v, dict):
        return '{\n' + ''.join('\t'*(level+1) + json.dumps(str(k)) + ' = ' + encode(val, level+1) + ';\n' for k,val in v.items()) + '\t'*level + '}'
    if isinstance(v, list):
        return '(\n' + ''.join('\t'*(level+1) + encode(x,level+1) + ',\n' for x in v) + '\t'*level + ')'
    if isinstance(v, int):
        return str(v)
    return json.dumps(str(v), ensure_ascii=False)

sources=[]
resources=[]
groups=[]
for folder in ['Core','Services','Views','Resources']:
    children=[]
    for file in sorted((APP/folder).iterdir()):
        if not file.is_file():
            continue
        if file.suffix not in ['.swift','.json','.txt','.xcprivacy','.ttf','.otf']:
            continue
        kind={'.swift':'sourcecode.swift','.json':'text.json','.txt':'text','.xcprivacy':'text.xml','.ttf':'file','.otf':'file'}[file.suffix]
        key=str(file.relative_to(ROOT))
        identifier=add('file:'+key,'PBXFileReference',lastKnownFileType=kind,path=file.name,sourceTree='<group>')
        children.append(identifier)
        build=add('build:'+key,'PBXBuildFile',fileRef=identifier)
        (sources if file.suffix=='.swift' else resources).append(build)
    if folder=='Resources':
        assets=add('assets','PBXFileReference',lastKnownFileType='folder.assetcatalog',path='Assets.xcassets',sourceTree='<group>')
        children.append(assets);resources.append(add('assets-build','PBXBuildFile',fileRef=assets))
        locales=[]
        for lang in ['ar','en']:
            locales.append(add('locale:'+lang,'PBXFileReference',lastKnownFileType='text.plist.strings',name=lang,path=lang+'.lproj/InfoPlist.strings',sourceTree='<group>'))
        localization=add('localization','PBXVariantGroup',children=locales,name='InfoPlist.strings',sourceTree='<group>')
        children.append(localization);resources.append(add('localization-build','PBXBuildFile',fileRef=localization))
    groups.append(add('group:'+folder,'PBXGroup',children=children,path=folder,sourceTree='<group>'))
rootfile=add('file:app','PBXFileReference',lastKnownFileType='sourcecode.swift',path='LuqmaApp.swift',sourceTree='<group>')
sources.append(add('build:app','PBXBuildFile',fileRef=rootfile))
infoplist=add('info','PBXFileReference',lastKnownFileType='text.plist.xml',path='Info.plist',sourceTree='<group>')
entitlement=add('entitlements','PBXFileReference',lastKnownFileType='text.plist.entitlements',path='Luqma.entitlements',sourceTree='<group>')
appgroup=add('group:app','PBXGroup',children=[rootfile,infoplist,entitlement]+groups,path='Luqma',sourceTree='<group>')
product=add('product','PBXFileReference',explicitFileType='wrapper.application',includeInIndex=0,path='Luqma.app',sourceTree='BUILT_PRODUCTS_DIR')
uitestfile=add('file:uitests','PBXFileReference',lastKnownFileType='sourcecode.swift',path='LuqmaInteractionTests.swift',sourceTree='<group>')
uitestgroup=add('group:uitests','PBXGroup',children=[uitestfile],path='TestsUI',sourceTree='<group>')
uitestproduct=add('product:uitests','PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex=0,path='LuqmaUITests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
productgroup=add('group:products','PBXGroup',children=[product,uitestproduct],name='Products',sourceTree='<group>')
main=add('group:main','PBXGroup',children=[appgroup,uitestgroup,productgroup],sourceTree='<group>')
package=add('package:ort','XCRemoteSwiftPackageReference',repositoryURL='https://github.com/microsoft/onnxruntime-swift-package-manager',requirement=dict(kind='exactVersion',version='1.24.2'))
ort=add('ort:product','XCSwiftPackageProductDependency',package=package,productName='onnxruntime')
ortbuild=add('ort:build','PBXBuildFile',productRef=ort)
mlxpackage=add('package:mlx-lm','XCRemoteSwiftPackageReference',repositoryURL='https://github.com/ml-explore/mlx-swift-lm',requirement=dict(kind='exactVersion',version='2.30.6'))
mlxbase=add('package:mlx','XCRemoteSwiftPackageReference',repositoryURL='https://github.com/ml-explore/mlx-swift',requirement=dict(kind='exactVersion',version='0.30.6'))
transformers=add('package:transformers','XCRemoteSwiftPackageReference',repositoryURL='https://github.com/huggingface/swift-transformers',requirement=dict(kind='exactVersion',version='1.1.6'))
mlxproducts=[add('mlx:'+name,'XCSwiftPackageProductDependency',package=mlxbase if name=='MLX' else mlxpackage,productName=name) for name in ['MLX','MLXLMCommon','MLXVLM']]
mlxbuilds=[add('mlx-build:'+str(p),'PBXBuildFile',productRef=p) for p in mlxproducts]
phases=[add('phase:sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=sources,runOnlyForDeploymentPostprocessing=0),add('phase:frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[ortbuild]+mlxbuilds,runOnlyForDeploymentPostprocessing=0),add('phase:resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=resources,runOnlyForDeploymentPostprocessing=0)]

targetsettings=dict(ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon',CODE_SIGN_ENTITLEMENTS='Luqma/Luqma.entitlements',CODE_SIGN_STYLE='Automatic',DEVELOPMENT_TEAM='',CURRENT_PROJECT_VERSION='1',GENERATE_INFOPLIST_FILE='NO',INFOPLIST_FILE='Luqma/Info.plist',IPHONEOS_DEPLOYMENT_TARGET='17.0',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/Frameworks'],MARKETING_VERSION='1.0',PRODUCT_BUNDLE_IDENTIFIER='app.luqma.diary',PRODUCT_NAME='$(TARGET_NAME)',SDKROOT='iphoneos',SUPPORTED_PLATFORMS='iphoneos iphonesimulator',SUPPORTS_MACCATALYST='NO',SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD='NO',SWIFT_VERSION='5.0',SWIFT_STRICT_CONCURRENCY='minimal',TARGETED_DEVICE_FAMILY='1')
projectconfigs=[]
targetconfigs=[]
for name in ['Debug','Release']:
    ps=dict(ALWAYS_SEARCH_USER_PATHS='NO',CLANG_ENABLE_MODULES='YES',CLANG_ENABLE_OBJC_ARC='YES',CLANG_CXX_LANGUAGE_STANDARD='gnu++17',CLANG_WARN_DOCUMENTATION_COMMENTS='YES',COPY_PHASE_STRIP='NO',ENABLE_STRICT_OBJC_MSGSEND='YES',GCC_C_LANGUAGE_STANDARD='gnu17',IPHONEOS_DEPLOYMENT_TARGET='17.0',SDKROOT='iphoneos')
    ts=targetsettings.copy()
    if name=='Debug':
        ps.update(DEBUG_INFORMATION_FORMAT='dwarf',ENABLE_TESTABILITY='YES',GCC_OPTIMIZATION_LEVEL='0',GCC_PREPROCESSOR_DEFINITIONS=['DEBUG=1','$(inherited)'],ONLY_ACTIVE_ARCH='YES')
        ts.update(SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG $(inherited)',SWIFT_OPTIMIZATION_LEVEL='-Onone')
    else:
        ps.update(DEBUG_INFORMATION_FORMAT='dwarf-with-dsym',ENABLE_NS_ASSERTIONS='NO')
        ts.update(SWIFT_COMPILATION_MODE='wholemodule',SWIFT_OPTIMIZATION_LEVEL='-O')
    projectconfigs.append(add('config:project:'+name,'XCBuildConfiguration',buildSettings=ps,name=name))
    targetconfigs.append(add('config:target:'+name,'XCBuildConfiguration',buildSettings=ts,name=name))
pc=add('configs:project','XCConfigurationList',buildConfigurations=projectconfigs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
tc=add('configs:target','XCConfigurationList',buildConfigurations=targetconfigs,defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
for config in targetconfigs: objects[config]['buildSettings']['MARKETING_VERSION']='2.5'
target=add('target','PBXNativeTarget',buildConfigurationList=tc,buildPhases=phases,buildRules=[],dependencies=[],name='Luqma',packageProductDependencies=[ort]+mlxproducts,productName='Luqma',productReference=product,productType='com.apple.product-type.application')
uitestconfigs=[]
for name in ['Debug','Release']:
    settings=dict(CODE_SIGN_STYLE='Automatic',GENERATE_INFOPLIST_FILE='YES',IPHONEOS_DEPLOYMENT_TARGET='17.0',PRODUCT_BUNDLE_IDENTIFIER='app.luqma.diary.uitests',PRODUCT_NAME='$(TARGET_NAME)',SDKROOT='iphoneos',SUPPORTED_PLATFORMS='iphoneos iphonesimulator',SWIFT_VERSION='5.0',TARGETED_DEVICE_FAMILY='1',TEST_TARGET_NAME='Luqma',LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/Frameworks','@loader_path/Frameworks'])
    if name=='Debug': settings.update(SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG $(inherited)',SWIFT_OPTIMIZATION_LEVEL='-Onone')
    uitestconfigs.append(add('config:uitests:'+name,'XCBuildConfiguration',buildSettings=settings,name=name))
uitestconfiglist=add('configs:uitests','XCConfigurationList',buildConfigurations=uitestconfigs,defaultConfigurationIsVisible=0,defaultConfigurationName='Debug')
uitestproxy=add('uitests:proxy','PBXContainerItemProxy',containerPortal=ref('project'),proxyType=1,remoteGlobalIDString=target,remoteInfo='Luqma')
uitestdependency=add('uitests:dependency','PBXTargetDependency',target=target,targetProxy=uitestproxy)
uitestphases=[add('uitests:sources','PBXSourcesBuildPhase',buildActionMask=2147483647,files=[add('uitests:source-build','PBXBuildFile',fileRef=uitestfile)],runOnlyForDeploymentPostprocessing=0),add('uitests:frameworks','PBXFrameworksBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0),add('uitests:resources','PBXResourcesBuildPhase',buildActionMask=2147483647,files=[],runOnlyForDeploymentPostprocessing=0)]
uitarget=add('target:uitests','PBXNativeTarget',buildConfigurationList=uitestconfiglist,buildPhases=uitestphases,buildRules=[],dependencies=[uitestdependency],name='LuqmaUITests',productName='LuqmaUITests',productReference=uitestproduct,productType='com.apple.product-type.bundle.ui-testing')
project=add('project','PBXProject',attributes=dict(BuildIndependentTargetsInParallel='YES',LastUpgradeCheck='1600',TargetAttributes={target:dict(CreatedOnToolsVersion='16.0',ProvisioningStyle='Automatic'),uitarget:dict(CreatedOnToolsVersion='16.0',TestTargetID=target)}),buildConfigurationList=pc,compatibilityVersion='Xcode 14.0',developmentRegion='ar',hasScannedForEncodings=0,knownRegions=['ar','en','Base'],mainGroup=main,packageReferences=[package,mlxpackage,mlxbase,transformers],productRefGroup=productgroup,projectDirPath='',projectRoot='',targets=[target,uitarget])
payload=dict(archiveVersion=1,classes={},objectVersion=56,objects=objects,rootObject=project)
(PROJECT/'project.pbxproj').write_text('// !$*UTF8*$!\n'+encode(payload)+'\n', encoding='utf-8', newline='\n')
scheme=PROJECT/'xcshareddata/xcschemes';scheme.mkdir(parents=True,exist_ok=True)
bp=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="Luqma.app" BlueprintName="Luqma" ReferencedContainer="container:Luqma.xcodeproj"/>'
uitestbp=f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uitarget}" BuildableName="LuqmaUITests.xctest" BlueprintName="LuqmaUITests" ReferencedContainer="container:Luqma.xcodeproj"/>'
(scheme/'Luqma.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{bp}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO" parallelizable="NO">{uitestbp}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{bp}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{bp}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''', encoding='utf-8', newline='\n')
print(f'Generated {PROJECT.name}: {len(sources)} Swift files, {len(resources)} resource entries')
