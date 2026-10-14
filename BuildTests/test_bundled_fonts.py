"""Check that licensed fonts register and ship with readable Arabic/Latin glyphs.

Uses only the Python standard library, including on Windows; no fontTools,
network, installed system font, Xcode or device is needed.
"""
import hashlib
import plistlib
import re
import struct
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Luqma/Resources"
FONT_SHA256 = {
    "Tajawal-Light.ttf": "ab26ed3e0c5af2c71b469b5780decff8088d290ab91aa29b07321580136e813a",
    "Tajawal-Regular.ttf": "6882892da3e03527d5db2bbab3b48bde6ef2e878a43f522d1a4eebda90010a19",
    "Tajawal-Medium.ttf": "1ff8bd943a261c9dd7906bdb1993cab87b6d925a7fb5f848cdb51ed301531090",
    "Tajawal-Bold.ttf": "0342ab6b74b6bd1b4b5bf7beda45a9734a2b3147a31e8a3a45b6a3417a52d9d7",
    "Tajawal-ExtraBold.ttf": "3d1298b747c22579f9e1bdeb0d4165064cb17f7e66145e2f43f9deb12ad7a2cf",
}
# The official license is pinned after LF normalization, so Git's Windows CRLF
# conversion cannot change its verified text.
LICENSE_SHA256 = "184de01d11c016e7d7bb2f2f81db9a036171acb5374f006e74a36828faca1f12"
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
        license_data = (RESOURCES / "Tajawal-OFL.txt").read_bytes().replace(b"\r\n", b"\n")
        self.assertEqual(hashlib.sha256(license_data).hexdigest(), LICENSE_SHA256)
        self.assertIn(b"SIL OPEN FONT LICENSE Version 1.1", license_data)

    def test_registered_faces_match_actual_postscript_names(self):
        typography = (ROOT / "Luqma/Views/LuqmaTypography.swift").read_text(encoding="utf-8")
        requested_faces = set(re.findall(r'"(Tajawal-[A-Za-z]+)"', typography))
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
                missing = [character for character in GLYPH_SAMPLE if not font.glyph_for(character)]
                self.assertEqual(missing, [], "Missing glyphs would silently fall back to a system font")

    def test_fonts_and_license_are_in_xcode_resource_copy_phase(self):
        project = (ROOT / "Luqma.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
        objects = dict(re.findall(r'^\t\t"([A-F0-9]{24})" = \{\n(.*?)^\t\t\};', project, re.M | re.S))
        self.assertTrue(objects, "Cannot read the committed generated project")
        resource_phases = [body for body in objects.values() if '"isa" = "PBXResourcesBuildPhase";' in body]
        self.assertEqual(len(resource_phases), 1)
        copied = set(re.findall(r'\b[A-F0-9]{24}\b', resource_phases[0]))
        for filename in list(FONT_SHA256) + ["Tajawal-OFL.txt"]:
            with self.subTest(resource=filename):
                references = [identity for identity, body in objects.items()
                              if '"isa" = "PBXFileReference";' in body and '"path" = "' + filename + '";' in body]
                self.assertEqual(len(references), 1, "Resource must exist in the committed Xcode project")
                build_entries = [identity for identity, body in objects.items()
                                 if '"isa" = "PBXBuildFile";' in body and '"fileRef" = ' + references[0] + ';' in body]
                self.assertEqual(len(build_entries), 1)
                self.assertIn(build_entries[0], copied, "A project reference alone does not put the font in the app")


if __name__ == "__main__":
    unittest.main()
