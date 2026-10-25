"""Source-pinned native search tests and real Simulator framebuffer captures."""
import json,os,re,subprocess,sys,time,uuid
from pathlib import Path
from build_ios import require_mac,BuildError
from ui_preview import command,select_runtime,validate_app,capture_screenshot,confirm_process,collect_runtime_font_audit
from simulator_support import prepare_created_simulator

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'SearchValidation'
TESTS=('testHomeSearchTypingSelectionAndReturn','testFiltersAndSortUseActualResults','testArabicSearchMirrorsOnlyDirectionalLayout')
def run():
    require_mac()
    if OUT.exists():raise BuildError('SearchValidation must be a fresh evidence directory')
    OUT.mkdir()
    report={'commit':os.environ.get('GITHUB_SHA'),'physical_device':False,'fps_measured':False,'screenshots':[],'test_status':'not_run','errors':[]}
    runtime=select_runtime(json.loads(command(['xcrun','simctl','list','--json'],OUT,'inventory')))
    derived=ROOT/'SearchDerived'
    devices=[]
    try:
        for index,(kind,label) in enumerate([('iPhone-13-mini','reference'),('iPhone-SE-3rd-generation','compact'),('iPhone-16-Pro-Max','large')]):
            device=command(['xcrun','simctl','create','Luqma Search '+uuid.uuid4().hex[:8],'com.apple.CoreSimulator.SimDeviceType.'+kind,runtime['identifier']],OUT,'create-'+label).strip()
            if re.fullmatch(r'[0-9A-Fa-f-]{36}',device) is None:raise BuildError('Invalid newly created Simulator identifier')
            devices.append(device)
            prepare_created_simulator(device,lambda args,tag,timeout:command(args,OUT,label+'-'+tag,timeout))
            if index==0:
                try:
                    log=command(['xcodebuild','-project','Luqma.xcodeproj','-scheme','Luqma','-clonedSourcePackagesDirPath','BuildOutput/Packages','-disableAutomaticPackageResolution','-destination','id='+device,'-configuration','Debug','-derivedDataPath',str(derived),'-resultBundlePath',str(OUT/'search.xcresult'),'-parallel-testing-enabled','NO','-only-testing:LuqmaUITests/SearchReferenceInteractionTests','ARCHS=arm64','ONLY_ACTIVE_ARCH=YES','CODE_SIGNING_ALLOWED=NO','CURRENT_PROJECT_VERSION='+os.environ.get('BUILD_NUMBER','1'),'test'],OUT,'native-search-tests',1500)
                    passed=[name for name in TESTS if re.search(r"Test Case '.*"+re.escape(name)+r".*' passed",log)]
                    if len(passed)!=len(TESTS):raise BuildError('Not all search tests ran and passed')
                    report['test_status']='passed';report['passed_tests']=passed
                except BuildError as error:
                    report['test_status']='failed';report['errors'].append(str(error))
            app=derived/'Build/Products/Debug-iphonesimulator/Luqma.app'
            validate_app(app,'app.luqma.diary',OUT)
            command(['xcrun','simctl','install',device,str(app)],OUT,'install-'+label,120)
            # Captures are actual view rendering. Loading/empty use read-only
            # DEBUG state injection; results use the real bundled food catalog.
            for language in ('en','ar'):
                for state in ('results','empty','loading'):
                    key=label+'-'+language+'-'+state
                    args=['-loqma-preview-search','-loqma-preview-search-query','milk' if language=='en' else 'حليب','-loqma-preview-font-audit','-AppleLanguages','('+language+')','-AppleLocale','en_US' if language=='en' else 'ar_SA']
                    args+=['-loqma-ui-test-en' if language=='en' else '-loqma-ui-test-ar']
                    if state!='results':args+=['-loqma-preview-search-state',state]
                    launched=command(['xcrun','simctl','launch','--terminate-running-process',device,'app.luqma.diary',*args],OUT,'launch-'+key,120)
                    pid=int(re.search(r':\s*(\d+)\s*$',launched).group(1))
                    confirm_process(pid,3)
                    details=capture_screenshot(OUT,device,key,pid,OUT/(key+'.png'))
                    fonts=collect_runtime_font_audit(OUT,device,'app.luqma.diary',key,pid,len(report['screenshots'])+1,False)
                    report['screenshots'].append(dict(screen=key,read_only_state_injection=state!='results',actual_bundled_foods=state=='results',fonts=fonts,**details))
            command(['xcrun','simctl','shutdown',device],OUT,'shutdown-'+label,60,allow_failure=True)
    except BaseException as error:
        report['errors'].append(str(error));raise
    finally:
        for device in devices:
            for action in ('shutdown','delete'):
                command(['xcrun','simctl',action,device],OUT,'cleanup-'+action+'-'+device,60,allow_failure=True)
        (OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    if report['errors']:raise BuildError('; '.join(report['errors']))
if __name__=='__main__':
    try:run()
    except (BuildError,OSError) as error:print(str(error),file=sys.stderr);sys.exit(1)
