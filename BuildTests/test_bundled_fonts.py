"""Check that licensed fonts register and ship with readable Arabic/Latin glyphs.

Uses only the Python standard library, including on Windows; no fontTools,
network, installed system font, Xcode or device is needed.
"""
import hashlib
import json
import plistlib
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Luqma/Resources"
FONT_SHA256 = {
    "Tajawal-Light.ttf": "ab26ed3e0c5af2c71b469b5780decff8088d290ab91aa29b07321580136e813a",
    "Tajawal-Regular.ttf": "6882892da3e03527d5db2bbab3b48bde6ef2e878a43f522d1a4eebda90010a19",
    "Tajawal-Medium.ttf": "1ff8bd943a261c9dd7906bdb1993cab87b6d925a7fb5f848cdb51ed301531090",
    "Tajawal-Bold.ttf": "0342ab6b74b6bd1b4b5bf7beda45a9734a2b3147a31e8a3a45b6a3417a52d9d7",
    "Tajawal-ExtraBold.ttf": "3d1298b747c22579f9e1bdeb0d4165064cb17f7e66145e2f43f9deb12ad7a2cf",
    "WorkSans-Light.ttf": "64e857d0a24ba3825c3f8b888ab5abade9c7b61166504b17317feab3cb74b64e",
    "WorkSans-Regular.ttf": "c4df840f74d05fddda0e716c9991f6d176bb278e43c39c8817760bbcbfdad3c5",
    "WorkSans-Medium.ttf": "46bd48f4185ed341f24600527a7506aa84263cfe2f1a61fa9485076b5c95026f",
    "WorkSans-SemiBold.ttf": "083b456dcbd3f8b1227ee1db508c8a247a85a0f7d1ffe3396589b7ab4641359e",
    "WorkSans-Bold.ttf": "e32ca4477095e3b259915d3db0b2acd1091e9d142706a54ba3eb2dcc54184c41",
    "WorkSans-ExtraBold.ttf": "b92939c6aaca5d1c3babc8f6d66536184d0f99718da8a5dc3a3c19023ae8348e",
}
# The official license is pinned after LF normalization, so Git's Windows CRLF
# conversion cannot change its verified text.
LICENSE_SHA256 = {
    "Tajawal-OFL.txt": "184de01d11c016e7d7bb2f2f81db9a036171acb5374f006e74a36828faca1f12",
    "WorkSans-OFL.txt": "749aca05078664ce682dce1b1b10096ac397cb088c1a6df4e1bb56f0092a9272",
}
GLYPH_SAMPLE = (
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    "ابتثجحخدذرزسشصضطظعغفقكلمنهويءأإؤئةى"
)


class SfntFont:
    def __init__(self, data):
        self.data = data
        if len(data) < 12 or data[:4] not in (b"\x00\x01\x00\x00", b"OTTO"):
            raise ValueError("Expected an SFNT OpenType/TrueType font")
        count = self.unpack(">H", 4)[0]
        if not 1 <= count <= 128 or 12 + count * 16 > len(data):
            raise ValueError("Invalid SFNT table directory")
        self.tables = {}
        for index in range(count):
            tag, _, offset, size = self.unpack(">4sIII", 12 + index * 16)
            if tag in self.tables or offset + size > len(data):
                raise ValueError("Invalid or duplicate SFNT table")
            self.tables[tag] = data[offset:offset + size]
        if not {b"name", b"cmap"}.issubset(self.tables):
            raise ValueError("A bundled font needs name and cmap tables")

    def unpack(self, format_string, offset, data=None):
        data = self.data if data is None else data
        if offset < 0 or offset + struct.calcsize(format_string) > len(data):
            raise ValueError("Font field extends beyond its table")
        return struct.unpack_from(format_string, data, offset)

    def postscript_names(self):
        names = self.tables[b"name"]
        _, count, strings = self.unpack(">HHH", 0, names)
        result = set()
        for index in range(count):
            platform, _, _, name_id, size, offset = self.unpack(">HHHHHH", 6 + index * 12, names)
            if name_id != 6:
                continue
            begin = strings + offset
            if begin + size > len(names):
                raise ValueError("Invalid PostScript-name record")
            result.add(names[begin:begin + size].decode("utf-16-be" if platform in (0, 3) else "mac_roman"))
        return result

    def glyph_for(self, character):
        codepoint = ord(character)
        cmap = self.tables[b"cmap"]
        version, count = self.unpack(">HH", 0, cmap)
        if version != 0:
            raise ValueError("Invalid cmap version")
        for index in range(count):
            platform, encoding, offset = self.unpack(">HHI", 4 + index * 8, cmap)
            if not (platform == 0 or (platform == 3 and encoding in (1, 10))):
                continue
            format_id = self.unpack(">H", offset, cmap)[0]
            if format_id == 4 and codepoint <= 0xffff:
                length = self.unpack(">H", offset + 2, cmap)[0]
                table = cmap[offset:offset + length]
                segments = self.unpack(">H", 6, table)[0] // 2
                end_at = 14
                start_at = end_at + segments * 2 + 2
                delta_at = start_at + segments * 2
                range_at = delta_at + segments * 2
                for segment in range(segments):
                    first = self.unpack(">H", start_at + segment * 2, table)[0]
                    last = self.unpack(">H", end_at + segment * 2, table)[0]
                    if not first <= codepoint <= last:
                        continue
                    delta = self.unpack(">h", delta_at + segment * 2, table)[0]
                    range_value = self.unpack(">H", range_at + segment * 2, table)[0]
                    if range_value == 0:
                        glyph = (codepoint + delta) & 0xffff
                    else:
                        pointer = range_at + segment * 2 + range_value + 2 * (codepoint - first)
                        glyph = self.unpack(">H", pointer, table)[0]
                        if glyph:
                            glyph = (glyph + delta) & 0xffff
                    if glyph:
                        return glyph
            elif format_id == 12:
                length = self.unpack(">I", offset + 4, cmap)[0]
                table = cmap[offset:offset + length]
                groups = self.unpack(">I", 12, table)[0]
                for group in range(groups):
                    first, last, first_glyph = self.unpack(">III", 16 + group * 12, table)
                    if first <= codepoint <= last:
                        return first_glyph + codepoint - first
        return 0


class BundledFontTests(unittest.TestCase):
    def test_declared_font_files_and_full_license_are_pinned(self):
        info = plistlib.loads((ROOT / "Luqma/Info.plist").read_bytes())
        declared = info.get("UIAppFonts", [])
        self.assertEqual(len(declared), len(set(declared)), "Duplicate font registration")
        self.assertEqual(set(declared), set(FONT_SHA256))
        actual = {file.name for file in RESOURCES.iterdir() if file.suffix.lower() in (".ttf", ".otf")}
        self.assertEqual(actual, set(declared), "Every distributed font must be registered")
        for filename, expected_hash in FONT_SHA256.items():
            with self.subTest(font=filename):
                self.assertEqual(Path(filename).name, filename)
                self.assertEqual(hashlib.sha256((RESOURCES / filename).read_bytes()).hexdigest(), expected_hash)
        for filename, expected_hash in LICENSE_SHA256.items():
            with self.subTest(license=filename):
                license_data = (RESOURCES / filename).read_bytes().replace(b"\r\n", b"\n")
                self.assertEqual(hashlib.sha256(license_data).hexdigest(), expected_hash)
                self.assertIn(b"SIL OPEN FONT LICENSE Version 1.1", license_data)

    def test_registered_faces_match_actual_postscript_names(self):
        typography = (ROOT / "Luqma/Views/LuqmaTypography.swift").read_text(encoding="utf-8")
        requested_faces = set(re.findall(r'"((?:Tajawal|WorkSans)-[A-Za-z]+)"', typography))
        actual_faces = set()
        for filename in FONT_SHA256:
            with self.subTest(font=filename):
                faces = SfntFont((RESOURCES / filename).read_bytes()).postscript_names()
                self.assertEqual(faces, {Path(filename).stem})
                actual_faces.update(faces)
        self.assertEqual(requested_faces, actual_faces, "Font.custom must use actual PostScript names")

    def test_every_weight_covers_arabic_latin_and_western_digits(self):
        for filename in FONT_SHA256:
            with self.subTest(font=filename):
                font = SfntFont((RESOURCES / filename).read_bytes())
                required = GLYPH_SAMPLE if filename.startswith("Tajawal-") else GLYPH_SAMPLE[:62]
                missing = [character for character in required if not font.glyph_for(character)]
                self.assertEqual(missing, [], "Missing glyphs would silently fall back to a system font")
                self.assertNotIn(b"fvar", font.tables, "Ship the unchanged official static font files")
                if filename.startswith("WorkSans-"):
                    self.assertTrue(all(not font.glyph_for(character) for character in GLYPH_SAMPLE[62:]),
                                    "Arabic is supplied by the explicit Tajawal cascade")

    def test_fonts_and_license_are_in_xcode_resource_copy_phase(self):
        project = (ROOT / "Luqma.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        objects = dict(re.findall(r'^\t\t"([A-F0-9]{24})" = \{\n(.*?)^\t\t\};', project, re.M | re.S))
        self.assertTrue(objects, "Cannot read the committed generated project")
        resource_phases = [body for body in objects.values() if '"isa" = "PBXResourcesBuildPhase";' in body]
        self.assertEqual(len(resource_phases), 1)
        copied = set(re.findall(r'\b[A-F0-9]{24}\b', resource_phases[0]))
        for filename in list(FONT_SHA256) + list(LICENSE_SHA256):
            with self.subTest(resource=filename):
                references = [identity for identity, body in objects.items()
                              if '"isa" = "PBXFileReference";' in body and '"path" = "' + filename + '";' in body]
                self.assertEqual(len(references), 1, "Resource must exist in the committed Xcode project")
                build_entries = [identity for identity, body in objects.items()
                                 if '"isa" = "PBXBuildFile";' in body and '"fileRef" = ' + references[0] + ';' in body]
                self.assertEqual(len(build_entries), 1)
                self.assertIn(build_entries[0], copied, "A project reference alone does not put the font in the app")


NATIVE_PROBE_SOURCE = r'''
import Foundation
import UIKit
import SwiftUI
import CoreText

enum FontProbeError:Error {case failed(String)}

func runFaces(_ text:String,_ font:CTFont)throws->[String] {
    let key=NSAttributedString.Key(kCTFontAttributeName as String)
    let line=CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:[key:font]) as CFAttributedString)
    let runs=CTLineGetGlyphRuns(line) as! [CTRun]
    var names=Set<String>()
    for run in runs {
        let attributes=CTRunGetAttributes(run) as NSDictionary
        guard let value=attributes[kCTFontAttributeName as String] else{throw FontProbeError.failed("Missing run font")}
        let usedFont=value as! CTFont
        names.insert(CTFontCopyPostScriptName(usedFont) as String)
        var glyphs=[CGGlyph](repeating:0,count:CTRunGetGlyphCount(run))
        if !glyphs.isEmpty {
            glyphs.withUnsafeMutableBufferPointer{buffer in
                CTRunGetGlyphs(run,CFRange(location:0,length:0),buffer.baseAddress!)
            }
            guard glyphs.allSatisfy({$0 != 0}) else{throw FontProbeError.failed("Missing shaped glyph")}
        }
    }
    return names.sorted()
}

@MainActor final class FontProbeDelegate:NSObject,UIApplicationDelegate {
    var window:UIWindow?
    func application(_ application:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?)->Bool {
        window=UIWindow(frame:UIScreen.main.bounds)
        window?.rootViewController=UIViewController()
        window?.makeKeyAndVisible()
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5){
            do{try self.probe()}catch{self.save(["passed":false,"error":String(describing:error)])}
        }
        return true
    }
    private func save(_ report:[String:Any]) {
        let directory=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
        do {
            let data=try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys])
            try data.write(to:directory.appendingPathComponent("font-probe.json"),options:.atomic)
        }catch{NSLog("Font probe report could not be written")}
    }
    private func measured(_ category:DynamicTypeSize)->CGSize {
        let content=Text("123 Protein").luqmaFont(size:18,weight:.regular,relativeTo:.body)
            .dynamicTypeSize(category).fixedSize()
        let host=UIHostingController(rootView:content)
        let parent=window!.rootViewController!
        parent.addChild(host)
        host.view.frame=CGRect(x:0,y:0,width:1000,height:1000)
        parent.view.addSubview(host.view)
        host.didMove(toParent:parent)
        let result=host.sizeThatFits(in:CGSize(width:1000,height:1000))
        host.willMove(toParent:nil)
        host.view.removeFromSuperview()
        host.removeFromParent()
        return result
    }
    private func probe()throws {
        for name in LTypography.bundledFontNames {
            guard let font=UIFont(name:name,size:18),font.fontName==name else{
                throw FontProbeError.failed("Bundled face did not register: "+name)
            }
        }
        let weights:[(Font.Weight,String,String)]=[
            (.light,"WorkSans-Light","Tajawal-Light"),
            (.regular,"WorkSans-Regular","Tajawal-Regular"),
            (.medium,"WorkSans-Medium","Tajawal-Medium"),
            (.semibold,"WorkSans-SemiBold","Tajawal-Bold"),
            (.bold,"WorkSans-Bold","Tajawal-Bold"),
            (.heavy,"WorkSans-ExtraBold","Tajawal-ExtraBold")
        ]
        var results=[[String:Any]]()
        for (weight,latinName,arabicName) in weights {
            let font=LTypography.platformFont(size:18,weight:weight)
            let latin=try runFaces("123 Protein",font)
            let arabic=try runFaces("البروتين",font)
            let mixed=try runFaces("123 Protein البروتين",font)
            guard (CTFontCopyPostScriptName(font) as String)==latinName,
                  latin==[latinName],arabic==[arabicName],Set(mixed)==Set([latinName,arabicName]) else{
                throw FontProbeError.failed("Incorrect Latin/digit/Arabic cascade for "+latinName)
            }
            results.append(["latin":latin,"arabic":arabic,"mixed":mixed,"point_size":CTFontGetSize(font)])
        }
        let emoji=try runFaces("🥙",LTypography.platformFont(size:18))
        guard emoji.contains(where:{$0.lowercased().contains("emoji")}) else{
            throw FontProbeError.failed("System emoji fallback was lost")
        }
        let standard=measured(.large),accessibility=measured(.accessibility3)
        let metrics=UIFontMetrics(forTextStyle:.body)
        let standardPoints=metrics.scaledValue(for:18,compatibleWith:UITraitCollection(preferredContentSizeCategory:.large))
        let accessibilityPoints=metrics.scaledValue(for:18,compatibleWith:UITraitCollection(preferredContentSizeCategory:.accessibilityExtraLarge))
        let expectedScale=accessibilityPoints/standardPoints
        let observedScale=accessibility.width/standard.width
        guard standard.width>0,standard.height>0,
              accessibility.width>standard.width*1.3,accessibility.height>standard.height*1.3,
              abs(observedScale-expectedScale)<expectedScale*0.1 else{
            throw FontProbeError.failed("SwiftUI cascaded font did not scale with Dynamic Type")
        }
        save(["passed":true,"font_count":LTypography.bundledFontNames.count,"weights":results,
              "emoji_faces":emoji,"standard_width":standard.width,"standard_height":standard.height,
              "accessibility_width":accessibility.width,"accessibility_height":accessibility.height,
              "expected_scale":expectedScale,"observed_scale":observedScale,"scaled_exactly_once":true,
              "dynamic_type_environment_tested":true,"test_source":"Actual LuqmaTypography.swift in a fresh Simulator font probe"])
    }
}

@main struct FontProbeMain {
    @MainActor static func main() {
        UIApplicationMain(CommandLine.argc,CommandLine.unsafeArgv,nil,NSStringFromClass(FontProbeDelegate.self))
    }
}
'''


@unittest.skipUnless(sys.platform == "darwin", "Native iPhone font probe requires macOS/Xcode")
class NativeBundledFontTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.device = None
        cls.directory = tempfile.TemporaryDirectory(prefix="luqma-font-probe-")
        try:
            cls.report = cls.run_probe(Path(cls.directory.name))
        finally:
            if cls.device:
                for operation in ("shutdown", "delete"):
                    subprocess.run(["xcrun", "simctl", operation, cls.device],
                                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=45, check=False)
            cls.directory.cleanup()

    @classmethod
    def command(cls, arguments, timeout=90):
        result = subprocess.run(arguments, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=timeout, check=False, text=True, encoding="utf-8", errors="replace")
        if result.returncode:
            raise RuntimeError("Native font probe command failed: " + " ".join(arguments[:3]) + "\n" + result.stdout[-12000:])
        return result.stdout.strip()

    @classmethod
    def run_probe(cls, directory):
        sdk = cls.command(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-path"])
        bundle = directory / "FontProbe.app"
        bundle.mkdir()
        probe = directory / "FontProbe.swift"
        probe.write_text(NATIVE_PROBE_SOURCE, encoding="utf-8", newline="\n")
        bundle_id = "app.luqma.fontprobe." + uuid.uuid4().hex
        info = {"CFBundleIdentifier": bundle_id, "CFBundleExecutable": "FontProbe", "CFBundleName": "FontProbe",
                "CFBundlePackageType": "APPL", "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0",
                "CFBundleSupportedPlatforms": ["iPhoneSimulator"], "MinimumOSVersion": "17.0",
                "UIDeviceFamily": [1], "UILaunchScreen": {}, "UIUserInterfaceStyle": "Dark",
                "UIAppFonts": list(FONT_SHA256)}
        (bundle / "Info.plist").write_bytes(plistlib.dumps(info))
        for filename in FONT_SHA256:
            shutil.copyfile(RESOURCES / filename, bundle / filename)
        for filename in LICENSE_SHA256:
            shutil.copyfile(RESOURCES / filename, bundle / filename)
        architecture = "arm64" if __import__("platform").machine().lower() in ("arm64", "aarch64") else "x86_64"
        cls.command(["xcrun", "swiftc", "-swift-version", "5", "-strict-concurrency=minimal", "-parse-as-library",
                     "-sdk", sdk, "-target", architecture + "-apple-ios17.0-simulator",
                     str(ROOT / "Luqma/Views/LuqmaTypography.swift"), str(probe), "-o", str(bundle / "FontProbe")], timeout=180)
        cls.command(["codesign", "--force", "--sign", "-", str(bundle)])
        inventory = json.loads(cls.command(["xcrun", "simctl", "list", "--json"]))
        runtimes = [item for item in inventory.get("runtimes", []) if item.get("isAvailable")
                    and item.get("identifier", "").startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
        if not runtimes:
            raise RuntimeError("Native font probe needs an available iPhone Simulator runtime")
        runtime = max(runtimes, key=lambda item: tuple(int(value) for value in re.findall(r"\d+", item.get("version", ""))))
        cls.device = cls.command(["xcrun", "simctl", "create", "Luqma Font Probe " + uuid.uuid4().hex[:8],
                                  "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max", runtime["identifier"]])
        if not re.fullmatch(r"[0-9A-Fa-f-]{36}", cls.device):
            cls.device = None
            raise RuntimeError("Native font probe Simulator creation returned no valid identifier")
        cls.command(["xcrun", "simctl", "boot", cls.device])
        cls.command(["xcrun", "simctl", "bootstatus", cls.device, "-b"], timeout=240)
        cls.command(["xcrun", "simctl", "install", cls.device, str(bundle)])
        cls.command(["xcrun", "simctl", "launch", cls.device, bundle_id], timeout=90)
        data = Path(cls.command(["xcrun", "simctl", "get_app_container", cls.device, bundle_id, "data"]))
        report = data / "Documents/font-probe.json"
        deadline = time.monotonic() + 60
        while not report.is_file() and time.monotonic() < deadline:
            time.sleep(.25)
        if not report.is_file():
            raise RuntimeError("Native iPhone font probe produced no result")
        result = json.loads(report.read_text(encoding="utf-8"))
        if result.get("passed") is not True:
            raise RuntimeError("Native iPhone font probe failed: " + result.get("error", "unknown failure"))
        return result

    def test_actual_native_mixed_script_runs_use_declared_faces_and_emoji_fallback(self):
        self.assertEqual(self.report["font_count"], len(FONT_SHA256))
        self.assertEqual(len(self.report["weights"]), 6)
        self.assertTrue(self.report["emoji_faces"])

    def test_swiftui_cascaded_font_modifier_scales_on_iphone(self):
        self.assertTrue(self.report["dynamic_type_environment_tested"])
        self.assertTrue(self.report["scaled_exactly_once"])
        self.assertAlmostEqual(self.report["observed_scale"], self.report["expected_scale"],
                               delta=self.report["expected_scale"] * .1)
        self.assertGreater(self.report["accessibility_width"], self.report["standard_width"] * 1.3)
        self.assertGreater(self.report["accessibility_height"], self.report["standard_height"] * 1.3)


if __name__ == "__main__":
    unittest.main()
