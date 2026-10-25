"""Bounded Mach-O capability checks; no real signing profiles or Health data."""
from pathlib import Path
import plistlib
import struct
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Scripts"))
from signing import BuildError
from simulator_entitlements import parse_simulator_entitlements, read_simulator_entitlements


def executable(claims=None, *, cpu=0x0100000C, platform=7, fmt=plistlib.FMT_XML,
               section_name=b"__entitlements", sections=1, payload=None):
    if claims is None:
        claims = {"com.apple.developer.healthkit": True}
    encoded = plistlib.dumps(claims, fmt=fmt) if payload is None else payload
    table_size = 72 + sections * 80 + 24
    offset = 32 + table_size
    total = offset + len(encoded)
    address = 0x100000000
    header = struct.pack("<IiiIIIII", 0xFEEDFACF, cpu, 0, 2, 2, table_size, 0, 0)
    segment = struct.pack("<II16sQQQQiiII", 0x19, 72 + sections * 80, b"__TEXT", address,
                          total, 0, total, 5, 5, sections, 0)
    section = struct.pack("<16s16sQQIIIIIIII", section_name, b"__TEXT", address + offset,
                          len(encoded), offset, 0, 0, 0, 0, 0, 0, 0)
    version = struct.pack("<IIIIII", 0x32, 24, platform, 17 << 16, 26 << 16, 0)
    return header + segment + section * sections + version + encoded


def changed(data, offset, fmt, value):
    result = bytearray(data)
    struct.pack_into(fmt, result, offset, value)
    return bytes(result)


class SimulatorEntitlementTests(unittest.TestCase):
    def test_reads_actual_thin_arm64_and_x86_executable_sections(self):
        for cpu in (0x0100000C, 0x01000007):
            with self.subTest(cpu=cpu):
                claims = parse_simulator_entitlements(executable(cpu=cpu))
                self.assertIs(claims.get("com.apple.developer.healthkit"), True)
        with tempfile.TemporaryDirectory() as folder:
            binary = Path(folder) / "Luqma"
            binary.write_bytes(executable())
            self.assertIs(read_simulator_entitlements(binary)["com.apple.developer.healthkit"], True)

    def test_valid_binary_plist_and_nul_padded_xml_are_supported(self):
        self.assertIs(parse_simulator_entitlements(executable(fmt=plistlib.FMT_BINARY))["com.apple.developer.healthkit"], True)
        payload = plistlib.dumps({"com.apple.developer.healthkit": True}) + b"\x00" * 8
        self.assertIs(parse_simulator_entitlements(executable(payload=payload))["com.apple.developer.healthkit"], True)

    def test_missing_false_or_wrong_type_claim_is_not_converted_to_true(self):
        for value in (False, 1, "true", [True]):
            with self.subTest(value=value):
                result = parse_simulator_entitlements(executable({"com.apple.developer.healthkit": value}))
                self.assertIsNot(result["com.apple.developer.healthkit"], True)
        self.assertNotIn("com.apple.developer.healthkit", parse_simulator_entitlements(executable({})))

    def test_rejects_device_mac_and_ambiguous_legacy_platforms(self):
        for platform in (1, 2, 6, 8):
            with self.subTest(platform=platform), self.assertRaises(BuildError):
                parse_simulator_entitlements(executable(platform=platform))
        # LC_VERSION_MIN_IPHONEOS does not distinguish physical arm64 iOS from
        # arm64 Simulator. A modern, explicit platform-7 build receipt is needed.
        data = executable()
        legacy = changed(data, 32 + 72 + 80, "<I", 0x25)
        with self.assertRaises(BuildError):
            parse_simulator_entitlements(legacy)

    def test_rejects_non_macho_fat_truncated_and_non_executable_files(self):
        data = executable()
        for malformed in (b"", b"<?xml not a binary", b"\xca\xfe\xba\xbe" + data[4:],
                          data[:31], data[:-1], changed(data, 12, "<I", 6),
                          changed(data, 4, "<i", 12)):
            with self.subTest(size=len(malformed)), self.assertRaises(BuildError):
                parse_simulator_entitlements(malformed)

    def test_rejects_load_command_size_count_and_truncated_section_tables(self):
        data = executable()
        cases = (changed(data, 16, "<I", 0), changed(data, 16, "<I", 3),
                 changed(data, 20, "<I", len(data)), changed(data, 36, "<I", 0),
                 changed(data, 36, "<I", 12), changed(data, 36, "<I", 0xFFFFFFF8),
                 changed(data, 32 + 64, "<I", 2),
                 changed(data, 32 + 72 + 80 + 20, "<I", 1))
        for index, malformed in enumerate(cases):
            with self.subTest(case=index), self.assertRaises(BuildError):
                parse_simulator_entitlements(malformed)

    def test_rejects_segment_and_section_file_virtual_bounds(self):
        data = executable()
        section = 32 + 72
        cases = (changed(data, 32 + 40, "<Q", len(data) + 1),
                 changed(data, 32 + 48, "<Q", len(data) + 1),
                 changed(data, section + 48, "<I", 16),
                 changed(data, section + 48, "<I", len(data) + 1),
                 changed(data, section + 40, "<Q", len(data)),
                 changed(data, section + 40, "<Q", 0),
                 changed(data, section + 32, "<Q", 0),
                 changed(data, section + 32, "<Q", 0x100000001),
                 changed(data, section + 64, "<I", 1))
        for index, malformed in enumerate(cases):
            with self.subTest(case=index), self.assertRaises(BuildError):
                parse_simulator_entitlements(malformed)

    def test_rejects_missing_duplicate_wrong_segment_and_malformed_plists(self):
        missing = executable(section_name=b"__unrelated")
        duplicate = executable(sections=2)
        wrong_segment = bytearray(executable())
        wrong_segment[32 + 72 + 16:32 + 72 + 32] = b"__DATA".ljust(16, b"\x00")
        for malformed in (missing, duplicate, bytes(wrong_segment), executable(payload=b"not a plist"),
                          executable(payload=b'<?xml version="1.0"?><plist><dict><key>broken</key>'),
                          executable(claims=["not a dictionary"])):
            with self.subTest(size=len(malformed)), self.assertRaises(BuildError):
                parse_simulator_entitlements(malformed)

    def test_missing_built_file_is_a_fixed_build_error(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(BuildError, "could not read the built Simulator executable"):
                read_simulator_entitlements(Path(folder) / "missing")


if __name__ == "__main__":
    unittest.main()
