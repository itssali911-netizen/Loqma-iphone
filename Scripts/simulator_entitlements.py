"""Inspect Xcode's simulated entitlement section in an actual Simulator executable.

Simulator capabilities can live in __TEXT,__entitlements rather than the code
signature's entitlement blob. This is SDK-test evidence only, never proof of an
Apple-provisioned iPhone signature. Device export validation remains in signing.py.
Only current, little-endian, thin arm64/x86_64 iOS Simulator executables are accepted.
"""
from __future__ import annotations

from pathlib import Path
import plistlib
import struct
from xml.parsers.expat import ExpatError

from build_ios import BuildError

MAX_EXECUTABLE_BYTES = 256 * 1024 * 1024
MAX_ENTITLEMENT_BYTES = 1024 * 1024
_HEADER_SIZE = 32
_ARM64 = 0x0100000C
_X86_64 = 0x01000007
_LC_SEGMENT_64 = 0x19
_LC_BUILD_VERSION = 0x32
_PLATFORM_IOSSIMULATOR = 7


def _invalid(reason: str) -> BuildError:
    # Fixed parser messages contain no executable contents or entitlement values.
    return BuildError("Simulator entitlement verification: " + reason + ".")


def _name(value: bytes) -> bytes:
    """Mach-O names are at most 16 bytes, optionally NUL-padded."""
    return value.rstrip(b"\x00")


def parse_simulator_entitlements(data: bytes) -> dict:
    """Return the actual Mach-O __TEXT,__entitlements plist dictionary.

    Reject fat binaries, device/platform ambiguity, malformed load commands,
    duplicate sections, and any section outside its file-backed segment. Legacy
    minimum-version commands are deliberately insufficient to identify arm64
    Simulator binaries; the supported deployment target emits LC_BUILD_VERSION.
    """
    if not isinstance(data, bytes) or not _HEADER_SIZE <= len(data) <= MAX_EXECUTABLE_BYTES:
        raise _invalid("missing, truncated or oversized executable")
    if data[:4] != b"\xcf\xfa\xed\xfe":
        raise _invalid("expected a thin little-endian 64-bit Mach-O executable")
    _, cpu, _, file_type, command_count, command_bytes, _, _ = struct.unpack_from("<IiiIIIII", data)
    if cpu not in (_ARM64, _X86_64) or file_type != 2:
        raise _invalid("unsupported architecture or non-executable file type")
    command_end = _HEADER_SIZE + command_bytes
    if not command_count or command_count > command_bytes // 8 or command_end > len(data):
        raise _invalid("invalid load-command table bounds")
    cursor = _HEADER_SIZE
    platforms = []
    entitlement_sections = []
    for _ in range(command_count):
        if cursor + 8 > command_end:
            raise _invalid("truncated load command")
        command, size = struct.unpack_from("<II", data, cursor)
        if size < 8 or size % 8 or size > command_end - cursor:
            raise _invalid("invalid load-command size")
        if command == _LC_BUILD_VERSION:
            if size < 24:
                raise _invalid("truncated build-version command")
            platform, _, _, tools = struct.unpack_from("<IIII", data, cursor + 8)
            if size != 24 + tools * 8:
                raise _invalid("invalid build-version tool table")
            platforms.append(platform)
        elif command == _LC_SEGMENT_64:
            if size < 72:
                raise _invalid("truncated segment command")
            segment_name = _name(data[cursor + 8:cursor + 24])
            address, memory_size, file_offset, file_size = struct.unpack_from("<QQQQ", data, cursor + 24)
            sections = struct.unpack_from("<I", data, cursor + 64)[0]
            if size != 72 + sections * 80:
                raise _invalid("invalid segment section table")
            if file_offset > len(data) or file_size > len(data) - file_offset:
                raise _invalid("segment exceeds executable bounds")
            for index in range(sections):
                section = cursor + 72 + index * 80
                section_name = _name(data[section:section + 16])
                section_segment = _name(data[section + 16:section + 32])
                if section_name != b"__entitlements":
                    continue
                if segment_name != b"__TEXT" or section_segment != b"__TEXT":
                    raise _invalid("entitlement section is outside the text segment")
                section_address, section_size = struct.unpack_from("<QQ", data, section + 32)
                section_offset = struct.unpack_from("<I", data, section + 48)[0]
                flags = struct.unpack_from("<I", data, section + 64)[0]
                if flags & 0xFF:
                    raise _invalid("entitlement section is not ordinary file-backed data")
                if not 0 < section_size <= MAX_ENTITLEMENT_BYTES:
                    raise _invalid("empty or oversized entitlement section")
                if (section_offset < command_end or section_offset < file_offset or
                        section_offset > len(data) or section_size > len(data) - section_offset or
                        section_offset - file_offset > file_size or
                        section_size > file_size - (section_offset - file_offset)):
                    raise _invalid("entitlement section exceeds executable or segment bounds")
                if (section_address < address or section_address - address > memory_size or
                        section_size > memory_size - (section_address - address) or
                        section_address - address != section_offset - file_offset):
                    raise _invalid("entitlement section has inconsistent virtual and file bounds")
                entitlement_sections.append((section_offset, section_size))
        cursor += size
    if cursor != command_end:
        raise _invalid("load-command count and size disagree")
    if platforms != [_PLATFORM_IOSSIMULATOR]:
        raise _invalid("executable is not unambiguously built for iOS Simulator")
    if len(entitlement_sections) != 1:
        raise _invalid("expected exactly one embedded entitlement section")
    offset, size = entitlement_sections[0]
    encoded = data[offset:offset + size]
    try:
        # ld may pad the XML section with NULs. Never strip binary-plist trailer
        # bytes, which can legitimately end in zero.
        if encoded.lstrip().startswith((b"<?xml", b"<plist")):
            encoded = encoded.rstrip(b"\x00")
        claims = plistlib.loads(encoded)
    except (ValueError, TypeError, OverflowError, RecursionError, ExpatError, plistlib.InvalidFileException):
        raise _invalid("embedded entitlement section is not a valid property list") from None
    if not isinstance(claims, dict) or not all(isinstance(key, str) for key in claims):
        raise _invalid("embedded entitlement property list is not a dictionary")
    return claims


def read_simulator_entitlements(executable: Path) -> dict:
    """Read one built executable, not an intermediate .xcent or source plist."""
    try:
        with Path(executable).open("rb") as source:
            data = source.read(MAX_EXECUTABLE_BYTES + 1)
    except OSError:
        raise _invalid("could not read the built Simulator executable") from None
    return parse_simulator_entitlements(data)
