"""Execute accessibility/lifecycle/feedback policy from the actual SwiftUI source.

The host probe is not evidence of physical haptics or iPhone frame pacing.
"""
from pathlib import Path
import shutil,subprocess,sys,tempfile,unittest

ROOT=Path(__file__).resolve().parents[1]
PROBE=r'''import SwiftUI
@main struct MotionPolicyProbe {
 static func main() {
  for kind in LuqmaMotion.Kind.allCases {
   precondition(LuqmaMotion.animation(kind,reduceMotion:true)==nil)
   precondition(LuqmaMotion.animation(kind,reduceMotion:false) != nil)
   precondition(kind.duration>0 && kind.duration<=0.5)
  }
  for reduced in [false,true] {
   for enabled in [false,true] {
    precondition(LuqmaMotion.pressScale(isPressed:false,reduceMotion:reduced,enabled:enabled)==1)
    precondition(LuqmaMotion.pressScale(isPressed:true,reduceMotion:reduced,enabled:enabled)==(enabled && !reduced ? 0.98:1))
   }
  }
  for active in [false,true] { for reduced in [false,true] { for scene in [false,true] {
   precondition(LuqmaMotion.permitsContinuousMotion(active:active,reduceMotion:reduced,sceneIsActive:scene)==(active && !reduced && scene))
  }}}
  func success(_ old:Bool,_ new:Bool,_ reduced:Bool=false,_ active:Bool=true)->Bool {
   LuqmaMotion.shouldPlayFeedback(old:old,new:new,reduceMotion:reduced,sceneIsActive:active){_,next in next}
  }
  precondition(success(false,true));precondition(!success(true,false));precondition(!success(true,true))
  precondition(!success(false,true,true));precondition(!success(false,true,false,false))
  print("Actual motion policy passed: rest identity, Reduce Motion, foreground-only loading and directional success feedback")
 }
}'''

class NativeMotionPolicyTests(unittest.TestCase):
 @unittest.skipUnless(sys.platform=='darwin' and shutil.which('xcrun'),'Native SwiftUI probe requires macOS/Xcode')
 def test_native_accessibility_lifecycle_and_feedback_policy(self):
  with tempfile.TemporaryDirectory() as directory:
   folder=Path(directory);source=folder/'Probe.swift';source.write_text(PROBE,encoding='utf8')
   executable=folder/'motion-policy'
   build=subprocess.run(['xcrun','swiftc','-parse-as-library','-target','arm64-apple-macosx14.0',
                         str(ROOT/'Luqma/Views/LuqmaMotion.swift'),str(source),'-o',str(executable)],capture_output=True,text=True,timeout=120)
   self.assertEqual(build.returncode,0,build.stdout+build.stderr)
   result=subprocess.run([str(executable)],capture_output=True,text=True,timeout=20)
   self.assertEqual(result.returncode,0,result.stdout+result.stderr)
   self.assertIn('Actual motion policy passed',result.stdout)

if __name__=='__main__':unittest.main()
