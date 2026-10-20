#!/usr/bin/env python3
"""Capture real SwiftUI screens on a fresh iPhone 16 Pro Max Simulator.

Requires an Apple Silicon Mac, Xcode, and an installed iOS Simulator runtime.
This builds a Debug Simulator app, launches each native tab using the app's
DEBUG-only -loqma-preview-tab argument, and captures the Simulator framebuffer.
Additional launches show read-only meal/recipe fixtures, secondary native forms,
and an accessibility-sized dashboard. These are native UI evidence, not live
analyses. Fixture names identify display examples, and new form routes disable
interaction so their save actions cannot write to the diary.
It creates no mock UI, sends no image to an API, and modifies no existing device.

Apple command-line screenshot documentation:
https://developer.apple.com/library/archive/documentation/IDEs/Conceptual/iOS_Simulator_Guide/InteractingwiththeiOSSimulator/InteractingwiththeiOSSimulator.html
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import plistlib
import re
import shlex
import signal
import struct
import subprocess
import sys
import time
import uuid
import zlib

from build_ios import BuildError, public_environment, require_mac
from simulator_support import SimulatorSetupError, prepare_created_simulator
from vision_compat import apply_vision_compat


ROOT = Path(__file__).resolve().parent.parent
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro-Max"
REFERENCE_DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-13-mini"
SCREENS = ((0, "today"), (1, "kitchen"), (2, "progress"), (3, "settings"))
PHOTO_SCREEN = "photo-estimate"
RECIPE_SCREEN = "recipe-import"
EXTRA_ROUTES = (("search", "-loqma-preview-search"),
                ("meal-macros", "-loqma-preview-meals"),
                ("daily-overview", "-loqma-preview-overview"))
TEMPLATE_ROUTES = (("macro-goals", "goals"),
                   ("food-portion", "portion"),
                   ("recipe-editor", "recipe"),
                   ("recipe-details", "recipeDetail"),
                   ("weight-plan", "plan"),
                   ("weight-editor", "weight"),
                   ("analysis-connection", "connection"),
                   ("backup", "backup"),
                   ("about", "about"),
                   ("barcode-guide", "barcode"),
                   ("language", "language"),
                   ("notifications", "notifications"),
                   ("reminders", "reminders"),
                   ("state-error", "stateError"),
                   ("state-loading", "stateLoading"),
                   ("state-empty", "stateEmpty"),
                   ("state-success", "stateSuccess"))
FITNESS_ROUTES = (("assessment-goal", "assessmentGoal"),
                  ("assessment-gender", "assessmentGender"),
                  ("assessment-activity", "assessmentActivity"),
                  ("assessment-details", "assessmentDetails"),
                  ("assessment-review", "assessmentReview"),
                  ("fitness-profile", "fitnessProfile"),
                  ("fitness-plan", "fitnessPlan"))
ASSESSMENT_EXTRA_ROUTES = (("assessment-age", 3), ("assessment-height", 4),
                           ("assessment-weight", 5), ("assessment-target", 6),
                           ("assessment-training", 8), ("assessment-safety", 1))
ASSESSMENT_ACCESSIBILITY_ROUTES = (("accessibility-assessment-goal", 0),
                                  ("accessibility-assessment-age", 3),
                                  ("accessibility-assessment-safety", 1))
VARIANT_ROUTES = (("accessibility-today", ("-loqma-preview-overview", "-loqma-preview-accessibility")),
                  ("photo-components", ("-loqma-preview-photo", "-loqma-preview-photo-detailed")),
                  ("editorial-dinner", ("-loqma-preview-routine-dinner",)),
                  ("editorial-snack", ("-loqma-preview-routine-snack",)),
                  ("accessibility-editorial", ("-loqma-preview-accessibility", "-loqma-preview-editorial-expanded")))
EXPECTED_SCREEN_COUNT = len(SCREENS) + 2 + len(EXTRA_ROUTES) + len(TEMPLATE_ROUTES) + len(VARIANT_ROUTES) + len(FITNESS_ROUTES) + len(ASSESSMENT_EXTRA_ROUTES) + len(ASSESSMENT_ACCESSIBILITY_ROUTES)
MAX_EMPTY_FRAME_RETRIES = 2
EMPTY_FRAME_RETRY_SECONDS = 5.0


def preview_cases() -> list[dict]:
    cases = [{"tab": tab, "screen": screen, "arguments": ["-loqma-preview-tab", str(tab)],
              "synthetic_fixture": False} for tab, screen in SCREENS]
    routes = ((PHOTO_SCREEN, "-loqma-preview-photo"),
              (RECIPE_SCREEN, "-loqma-preview-recipe")) + EXTRA_ROUTES
    cases += [{"tab": None, "screen": screen, "arguments": [argument],
               "synthetic_fixture": screen in {PHOTO_SCREEN, RECIPE_SCREEN, "meal-macros", "daily-overview"}}
              for screen, argument in routes]
    cases += [{"tab": None, "screen": screen, "arguments": ["-loqma-preview-template", route],
               "template_route": route, "read_only_preview": True,
               "synthetic_fixture": route in {"portion", "recipe", "recipeDetail"} or route.startswith("state")}
              for screen, route in TEMPLATE_ROUTES]
    cases += [{"tab": None, "screen": screen, "arguments": list(arguments),
               "synthetic_fixture": screen in {"accessibility-today", "photo-components"},
               "read_only_preview": True,
               **({"dynamic_type_override": "accessibility3"}
                  if "-loqma-preview-accessibility" in arguments else
                  {"component_detail_preview": True} if "-loqma-preview-photo-detailed" in arguments else {})}
              for screen, arguments in VARIANT_ROUTES]
    cases += [{"tab": None, "screen": screen,
               "arguments": ["-loqma-preview-template", route],
               "template_route": route, "read_only_preview": True,
               "synthetic_fixture": True} for screen, route in FITNESS_ROUTES]
    cases += [{"tab": None, "screen": screen,
               "arguments": ["-loqma-preview-template", "assessmentGoal", "-loqma-preview-assessment-page", str(page),
                             *(["-loqma-preview-accessibility"] if screen.startswith("accessibility-") else [])],
               "template_route": "assessmentGoal", "read_only_preview": True, "synthetic_fixture": True,
               "assessment_page": page,
               **({"dynamic_type_override": "accessibility3"} if screen.startswith("accessibility-") else {})}
              for screen, page in ASSESSMENT_EXTRA_ROUTES + ASSESSMENT_ACCESSIBILITY_ROUTES]
    return cases


def validate_runtime_font_audit(value: dict, pid: int, accessibility: bool,
                                expected_scope: str | None = None) -> dict:
    """Check native UIFont registration AND actual CoreText shaped glyph runs.

    The app writes this DEBUG-only envelope after startup. The launch PID rejects
    stale data from the preceding screenshot process; filenames alone cannot
    establish that a requested custom font actually rendered on iOS.
    """
    if not isinstance(value, dict) or value.get("processIdentifier") != pid:
        raise BuildError("Runtime font audit is stale or has no matching application process ID.")
    scope = value.get("renderingScope")
    if (not isinstance(scope, str) or scope not in {"root", "template"} or
            (expected_scope is not None and (not isinstance(expected_scope, str) or expected_scope not in {"root", "template"} or scope != expected_scope))):
        raise BuildError("Runtime font audit has the wrong rendering scope for this captured view.")
    actual_size = value.get("swiftUIDynamicTypeSize")
    actual_accessibility = value.get("swiftUIIsAccessibilitySize")
    body_points = value.get("swiftUIBodyPoints")
    normal_sizes = {"xSmall", "small", "medium", "large", "xLarge", "xxLarge", "xxxLarge"}
    accessibility_sizes = {"accessibility1", "accessibility2", "accessibility3", "accessibility4", "accessibility5"}
    if (not isinstance(actual_size, str) or actual_size not in normal_sizes | accessibility_sizes or
            type(actual_accessibility) is not bool or actual_accessibility != (actual_size in accessibility_sizes)):
        raise BuildError("Runtime font audit lacks a valid actual SwiftUI Dynamic Type environment.")
    if (not isinstance(body_points, (int, float)) or isinstance(body_points, bool) or
            not math.isfinite(body_points) or body_points <= 0):
        raise BuildError("Runtime font audit has an invalid actual SwiftUI body size.")
    if accessibility:
        if actual_size != "accessibility3" or actual_accessibility is not True or body_points <= 16:
            raise BuildError("Accessibility preview did not actually scale its SwiftUI environment to accessibility3.")
    elif actual_accessibility or actual_size not in normal_sizes:
        raise BuildError("Ordinary preview unexpectedly uses an accessibility SwiftUI Dynamic Type environment.")
    audit = value.get("fontAudit")
    if not isinstance(audit, dict) or audit.get("source") != "Actual UIKit fonts and CoreText shaped runs from LuqmaTypography":
        raise BuildError("Runtime font audit lacks native UIKit/CoreText provenance.")
    if audit.get("passed") is not True:
        raise BuildError("The app's native runtime font audit failed; inspect the saved audit JSON.")
    entries = audit.get("entries")
    required = {"display", "screenTitle", "sectionTitle", "headline", "body", "subheadline",
                "helper", "caption", "caption2", "button", "metric", "legacyLightPromoted"}
    if not isinstance(entries, list) or not all(isinstance(entry, dict) for entry in entries):
        raise BuildError("Runtime font audit has no valid role entries.")
    roles = [entry.get("role") for entry in entries]
    if not all(isinstance(role, str) for role in roles) or len(set(roles)) != len(roles) or not required.issubset(roles):
        raise BuildError("Runtime font audit omits or duplicates required typography roles.")
    actual_fonts = set()
    for entry in entries:
        latin = entry.get("resolvedLatinPostScript", "")
        arabic = entry.get("resolvedArabicPostScript", "")
        if not isinstance(latin, str) or not isinstance(arabic, str) or not latin.startswith("WorkSans-") or not arabic.startswith("Tajawal-"):
            raise BuildError("A runtime font role resolved to an unexpected system or substitute face.")
        if not all(isinstance(entry.get(field), list) and all(isinstance(font, str) for font in entry[field])
                   for field in ("latinRuns", "arabicRuns", "mixedRuns")):
            raise BuildError("Runtime font audit has malformed shaped-font run data.")
        if (entry.get("passed") is not True or entry.get("registered") is not True or
                entry.get("missingGlyphs") != 0 or entry.get("uiFontPostScript") != latin or
                set(entry.get("latinRuns", [])) != {latin} or
                set(entry.get("arabicRuns", [])) != {arabic} or
                set(entry.get("mixedRuns", [])) != {latin, arabic}):
            raise BuildError("A runtime font role failed registration or actual Latin/Arabic shaping checks.")
        if entry.get("effectiveWeight") in {"light", "thin", "ultraLight"}:
            raise BuildError("App typography unexpectedly uses a thin effective text weight.")
        for field in ("basePoints", "scaledPoints", "lineHeight"):
            number = entry.get(field)
            if not isinstance(number, (int, float)) or isinstance(number, bool) or not math.isfinite(number) or number <= 0:
                raise BuildError("Runtime font audit contains an invalid measured font size.")
        if entry["basePoints"] < 12:
            raise BuildError("Runtime typography contains text below the declared readable base size.")
        if accessibility and entry["scaledPoints"] <= entry["basePoints"]:
            raise BuildError("Accessibility preview fonts did not actually scale above their base size.")
        actual_fonts.update((latin, arabic))
    category = audit.get("contentSizeCategory", "")
    if (not isinstance(category, str) or not category or
            ("Accessibility" in category) != actual_accessibility):
        raise BuildError("Runtime font audit has the wrong Dynamic Type category for this capture.")
    body = next(entry for entry in entries if entry["role"] == "body")
    if abs(body["basePoints"] - 16) > 0.000001 or abs(body["scaledPoints"] - body_points) > 0.5:
        raise BuildError("Actual SwiftUI body size does not match the measured body font role.")
    emoji = audit.get("emojiFonts")
    if not isinstance(emoji, list) or not any(isinstance(font, str) and "emoji" in font.lower() for font in emoji):
        raise BuildError("Runtime audit did not resolve the emoji sample through the system emoji cascade.")
    return {"passed": True, "process_id": pid, "roles_checked": len(entries),
            "actual_postscript_fonts": sorted(actual_fonts), "content_size_category": category,
            "rendering_scope": scope, "swiftui_dynamic_type_size": actual_size,
            "swiftui_body_points": body_points, "swiftui_is_accessibility_size": actual_accessibility,
            "swiftui_body_matches_role": True,
            "accessibility_scaling_verified": accessibility,
            "zero_missing_glyphs": True, "emoji_fonts": emoji}


def collect_runtime_font_audit(output: Path, device: str, bundle: str,
                               screen: str, pid: int, number: int, accessibility: bool) -> dict:
    container = Path(command(["xcrun", "simctl", "get_app_container", device, bundle, "data"],
                             output, "preview-font-container-" + screen).strip())
    if not container.is_absolute():
        raise BuildError("Simulator did not return an absolute app data container for font verification.")
    source = container / "Documents/luqma-font-audit.json"
    if not source.is_file() or source.stat().st_size > 250_000:
        raise BuildError("The launched app did not produce a bounded native runtime font audit.")
    data = source.read_bytes()
    directory = output / "font-audits"
    directory.mkdir(exist_ok=True)
    target = directory / f"{number:02d}-{screen}.json"
    target.write_bytes(data)
    try:
        value = json.loads(data)
    except (ValueError, UnicodeError) as error:
        raise BuildError("The launched app's runtime font audit is not valid JSON.") from error
    case = next((item for item in preview_cases() if item["screen"] == screen), None)
    if case is None:
        raise BuildError("Runtime font audit has no recognized captured view route.")
    expected_scope = "template" if "template_route" in case else "root"
    details = validate_runtime_font_audit(value, pid, accessibility, expected_scope=expected_scope)
    return {**details, "file": target.relative_to(output).as_posix(), "sha256": hashlib.sha256(data).hexdigest()}


def command(arguments: list[str], output: Path, label: str, timeout: int = 120,
            allow_failure: bool = False) -> str:
    print(f"UI preview {label}: {shlex.join(arguments)}", flush=True)
    log = output / (label + ".log")
    try:
        result = subprocess.run(arguments, cwd=ROOT, env=public_environment(),
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                timeout=timeout)
    except subprocess.TimeoutExpired as error:
        log.write_bytes(error.stdout or b"")
        raise BuildError(f"{label} exceeded {timeout} seconds; see {log.name}.") from error
    log.write_bytes(result.stdout)
    text = result.stdout.decode("utf-8", errors="replace")
    if result.returncode and not allow_failure:
        print("\n".join(text.splitlines()[-45:]), file=sys.stderr)
        raise BuildError(f"{label} failed ({result.returncode}); see {log.name}.")
    return text


def select_runtime(inventory: dict) -> dict:
    runtimes = [item for item in inventory.get("runtimes", [])
                if item.get("isAvailable") and
                item.get("identifier", "").startswith("com.apple.CoreSimulator.SimRuntime.iOS-")]
    if not runtimes:
        raise BuildError("No available iOS Simulator runtime is installed in the selected Xcode.")
    return max(runtimes, key=lambda item: tuple(int(n) for n in re.findall(
        r"\d+", item.get("version", item["identifier"]))))


def build_app(output: Path, packages: Path, bundle: str) -> Path:
    common = ["xcodebuild", "-project", "Luqma.xcodeproj", "-scheme", "Luqma",
              "-clonedSourcePackagesDirPath", str(packages)]
    command(common + ["-resolvePackageDependencies"], output, "preview-packages", 600)
    apply_vision_compat(packages)
    derived = output / "derived"
    command(common + ["-disableAutomaticPackageResolution", "-destination",
                      "generic/platform=iOS Simulator", "-configuration", "Debug",
                      "-derivedDataPath", str(derived), "-resultBundlePath",
                      str(output / "ui-preview.xcresult"), "ARCHS=arm64",
                      "ONLY_ACTIVE_ARCH=YES", "CODE_SIGNING_ALLOWED=NO",
                      f"PRODUCT_BUNDLE_IDENTIFIER={bundle}",
                      "CURRENT_PROJECT_VERSION=" + (os.environ.get("BUILD_NUMBER", "1") or "1"),
                      "build"],
            output, "preview-build", 1200)
    apply_vision_compat(packages, verify_only=True)
    return derived / "Build/Products/Debug-iphonesimulator/Luqma.app"


def validate_app(app: Path, bundle: str, output: Path) -> dict:
    if not app.is_dir():
        raise BuildError("The Simulator build did not produce Luqma.app.")
    try:
        info = plistlib.loads((app / "Info.plist").read_bytes())
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        raise BuildError("The Simulator app has no valid Info.plist.") from error
    if info.get("CFBundleIdentifier") != bundle:
        raise BuildError("The Simulator app identifier does not match the requested bundle.")
    if info.get("CFBundleSupportedPlatforms") != ["iPhoneSimulator"]:
        raise BuildError("UI preview only installs a Simulator build, never an iPhone IPA.")
    executable = info.get("CFBundleExecutable", "")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", executable):
        raise BuildError("The app executable name is invalid.")
    architectures = command(["xcrun", "lipo", "-archs", str(app / executable)],
                            output, "preview-architectures").split()
    if "arm64" not in architectures:
        raise BuildError("The Simulator app lacks the required arm64 architecture.")
    return {"bundle_id": bundle, "version": info.get("CFBundleShortVersionString"),
            "build": info.get("CFBundleVersion"), "architectures": architectures}


def decode_png(data: bytes, name: str) -> tuple[int, int, int, bytearray, bytes]:
    """Decode non-interlaced 8-bit Simulator PNGs without third-party packages.

    The final byte string retains the original filtered scanlines for the
    existing framebuffer hash. The separate pixel buffer is only inspected;
    neither buffer is written back into the captured screenshot.
    """
    if len(data) < 33 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise BuildError(f"{name} is not a valid PNG screenshot.")
    compressed = bytearray()
    header = None
    ended = False
    offset = 8
    while offset + 12 <= len(data):
        length = struct.unpack_from(">I", data, offset)[0]
        if offset + 12 + length > len(data):
            raise BuildError(f"{name} contains an incomplete PNG chunk.")
        kind = data[offset + 4:offset + 8]
        content = data[offset + 8:offset + 8 + length]
        expected_crc = struct.unpack_from(">I", data, offset + 8 + length)[0]
        if zlib.crc32(kind + content) & 0xffffffff != expected_crc:
            raise BuildError(f"{name} contains a damaged PNG chunk.")
        if kind == b"IHDR":
            if header is not None or offset != 8 or length != 13:
                raise BuildError(f"{name} has an invalid PNG header.")
            header = struct.unpack(">IIBBBBB", content)
        elif kind == b"IDAT":
            compressed.extend(content)
        elif kind == b"IEND":
            if length:
                raise BuildError(f"{name} has an invalid PNG end chunk.")
            ended = True
            offset += length + 12
            break
        offset += length + 12
    if not ended or offset != len(data) or header is None or not compressed:
        raise BuildError(f"{name} has an incomplete PNG framebuffer.")
    width, height, depth, color, compression, filtering, interlace = header
    channels = {0: 1, 2: 3, 4: 2, 6: 4}.get(color)
    if depth != 8 or channels is None or compression or filtering or interlace:
        raise BuildError(f"{name} is not a supported 8-bit Simulator PNG.")
    if not width or not height or width * height > 32_000_000:
        raise BuildError(f"{name} has invalid or excessive PNG dimensions.")
    row_bytes = width * channels
    expected_bytes = height * (row_bytes + 1)
    try:
        inflater = zlib.decompressobj()
        frame = inflater.decompress(compressed, expected_bytes + 1)
        if len(frame) != expected_bytes or not inflater.eof or inflater.unused_data or inflater.unconsumed_tail:
            raise BuildError(f"{name} has a PNG framebuffer size mismatch.")
    except zlib.error as error:
        raise BuildError(f"{name} has no readable PNG framebuffer.") from error
    pixels = bytearray(width * height * channels)
    previous = bytearray(row_bytes)
    for y in range(height):
        start = y * (row_bytes + 1)
        mode = frame[start]
        row = bytearray(frame[start + 1:start + 1 + row_bytes])
        if mode == 1:  # Sub
            for x in range(channels, row_bytes):
                row[x] = (row[x] + row[x - channels]) & 255
        elif mode == 2:  # Up
            row = bytearray((value + up) & 255 for value, up in zip(row, previous))
        elif mode in (3, 4):  # Average / Paeth
            for x in range(row_bytes):
                left = row[x - channels] if x >= channels else 0
                up = previous[x]
                upper_left = previous[x - channels] if x >= channels else 0
                if mode == 3:
                    predictor = (left + up) // 2
                else:
                    prediction = left + up - upper_left
                    distances = (abs(prediction - left), abs(prediction - up), abs(prediction - upper_left))
                    predictor = left if distances[0] <= distances[1] and distances[0] <= distances[2] else (
                        up if distances[1] <= distances[2] else upper_left)
                row[x] = (row[x] + predictor) & 255
        elif mode != 0:
            raise BuildError(f"{name} contains an invalid PNG scanline filter.")
        pixels[y * row_bytes:(y + 1) * row_bytes] = row
        previous = row
    return width, height, channels, pixels, frame


def framebuffer_content(width: int, height: int, channels: int, pixels: bytearray) -> dict:
    # Ignore the system status bar and home indicator: these can appear over an
    # otherwise black launch frame. Inspect real pixels in the central body.
    left, right = int(width * .04), int(width * .96)
    top, bottom = int(height * .10), int(height * .88)
    stride = max(1, int(((right - left) * (bottom - top) / 80_000) ** .5))
    sampled = near_black = 0
    for y in range(top, bottom, stride):
        for x in range(left, right, stride):
            offset = (y * width + x) * channels
            if channels in (1, 2):
                brightness = pixels[offset]
            else:
                brightness = max(pixels[offset], pixels[offset + 1], pixels[offset + 2])
            if channels in (2, 4):
                brightness = (brightness * pixels[offset + channels - 1]) // 255
            near_black += brightness <= 8
            sampled += 1
    if not sampled:
        raise BuildError("PNG framebuffer has no inspectable body pixels.")
    fraction = near_black / sampled
    return {"body_pixel_samples": sampled, "body_sample_stride": stride,
            "near_black_body_fraction": round(fraction, 6),
            "near_empty_black_frame": fraction >= .98}


def png_details(path: Path) -> dict:
    data = path.read_bytes()
    width, height, channels, pixels, frame = decode_png(data, path.name)
    if width < 700 or height < 1400:
        raise BuildError(f"{path.name} has unexpected phone screenshot dimensions.")
    return {"file": path.name, "width": width, "height": height,
            "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
            "frame_sha256": hashlib.sha256(frame).hexdigest(),
            **framebuffer_content(width, height, channels, pixels)}


def confirm_process(pid: int, seconds: float) -> None:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except OSError as error:
            raise BuildError("Luqma exited before the screenshot; inspect the Simulator log.") from error
        time.sleep(min(0.5, max(0, deadline - time.monotonic())))


def capture_screenshot(output: Path, device: str, screen: str, pid: int, screenshot: Path) -> dict:
    rejected = []
    for attempt in range(1, MAX_EMPTY_FRAME_RETRIES + 2):
        if attempt > 1:
            confirm_process(pid, EMPTY_FRAME_RETRY_SECONDS)
        command(["xcrun", "simctl", "io", device, "screenshot", "--type=png", str(screenshot)],
                output, f"preview-capture-{screen}-attempt-{attempt}", 90)
        confirm_process(pid, .25)
        details = png_details(screenshot)
        if not details["near_empty_black_frame"]:
            return {**details, "capture_attempts": attempt, "rejected_empty_frames": rejected}
        if attempt > MAX_EMPTY_FRAME_RETRIES:
            raise BuildError(f"Native {screen} remained near-empty black after {attempt} framebuffer captures.")
        rejected_directory = output / "rejected-framebuffers"
        rejected_directory.mkdir(exist_ok=True)
        rejected_path = rejected_directory / f"{screen}-attempt-{attempt}.png"
        screenshot.rename(rejected_path)
        rejected.append({"file": rejected_path.relative_to(output).as_posix(),
                         "sha256": details["sha256"], "near_black_body_fraction": details["near_black_body_fraction"]})
        print(f"Native {screen} was near-empty black; waiting for the same process before recapture.", flush=True)
    raise BuildError("Native screenshot capture exhausted its retry bound.")


def collect_failure_diagnostics(output: Path, device: str, report: dict) -> None:
    # A failed first launch can precede Luqma's process entirely. Retain the
    # own-device launch services and the host Simulator bootstrap log as well.
    diagnostics = (
        ("preview-app-diagnostic", ["xcrun", "simctl", "spawn", device, "log", "show", "--last", "10m",
                                    "--style", "compact", "--predicate",
                                    'process == "Luqma" OR process == "SpringBoard" OR process == "launchd_sim" '
                                    'OR process == "backboardd" OR eventMessage CONTAINS[c] "dyld"']),
        ("preview-host-diagnostic", ["/usr/bin/log", "show", "--last", "10m", "--style", "compact", "--predicate",
                                     f'eventMessage CONTAINS[c] "{device}" OR process == "CoreSimulatorService" '
                                     'OR process == "simctl" OR process == "Simulator"']),
    )
    for label, arguments in diagnostics:
        try:
            command(arguments, output, label, 90, allow_failure=True)
            report.setdefault("diagnostic_logs", []).append(label + ".log")
        except (BuildError, OSError) as diagnostic_error:
            report.setdefault("diagnostic_errors", []).append({"log": label + ".log", "error": str(diagnostic_error)})


def capture(output: Path, packages: Path, prebuilt: Path | None,
            bundle: str, settle_seconds: float, device_type: str=DEVICE_TYPE,
            language: str='ar', screens: list[str] | None=None) -> None:
    if output.exists():
        raise BuildError("Choose a new UI preview output directory to avoid mixing screenshots.")
    output.mkdir(parents=True)
    started = time.monotonic()
    report = {
        "status": "running", "commit": os.environ.get("GITHUB_SHA", "local"),
        "started_at": datetime.now(timezone.utc).isoformat(),
        "capture_method": "Native Debug SwiftUI app and simctl framebuffer screenshot",
        "fresh_simulator": False, "existing_device_data_modified": False,
        "api_key_used": False, "physical_device_verified": False,
        "expected_screenshot_count": len(screens) if screens else EXPECTED_SCREEN_COUNT,
        "language": language,
        "synthetic_photo_fixture": True,
        "synthetic_recipe_fixture": True,
        "synthetic_meal_fixture": True,
        "synthetic_overview_fixture": True,
        "synthetic_portion_fixture": True,
        "synthetic_recipe_editor_fixture": True,
        "synthetic_fitness_profile_fixtures": True,
        "fitness_preview_writes_real_profile": False,
        "secondary_form_previews_read_only": True,
        "accessibility_preview_dynamic_type": "accessibility3",
        "preview_language_override": "DEBUG English flag on this newly created Simulator" if language=='en' else "Default Arabic diary language",
        "search_uses_actual_catalog": True,
        "barcode_preview_uses_live_guide_component": True,
        "barcode_camera_session_started": False,
        "health_data_fixture_used": False,
        "layout_review": "Pending visual inspection of the native screenshots",
        "empty_frame_guard": {"body_crop": [0.04, 0.10, 0.96, 0.88],
                              "near_black_rgb_maximum": 8, "near_black_fraction_threshold": .98,
                              "maximum_recaptures": MAX_EMPTY_FRAME_RETRIES,
                              "pixel_check_proves_layout_correct": False},
        "screenshots": [],
        "runtime_font_audits": [],
    }
    device = None
    try:
        require_mac(26)
        if platform.machine().lower() not in ("arm64", "aarch64"):
            raise BuildError("Native arm64 UI preview requires an Apple Silicon runner.")
        app = prebuilt or build_app(output, packages, bundle)
        report["app"] = validate_app(app, bundle, output)
        inventory = json.loads(command(["xcrun", "simctl", "list", "--json"],
                                       output, "preview-inventory"))
        types = inventory.get("devicetypes", inventory.get("deviceTypes", []))
        if not any(item.get("identifier") == device_type for item in types):
            raise BuildError("The selected Xcode lacks the requested Simulator device type: "+device_type)
        runtime = select_runtime(inventory)
        name = "Luqma UI Preview " + uuid.uuid4().hex[:8]
        device = command(["xcrun", "simctl", "create", name, device_type,
                          runtime["identifier"]], output, "preview-create").strip()
        if not re.fullmatch(r"[0-9A-Fa-f-]{36}", device):
            device = None
            raise BuildError("Simulator creation did not return a valid device identifier.")
        report["simulator"] = {"udid": device, "device": "iPhone 13 mini" if device_type==REFERENCE_DEVICE_TYPE else "iPhone 16 Pro Max",
                               "runtime": runtime["name"], "runtime_id": runtime["identifier"]}
        report["fresh_simulator"] = True
        try:
            report["simulator_preparation"] = prepare_created_simulator(
                device, lambda arguments, label, timeout: command(arguments, output, "preview-" + label, timeout))
        except SimulatorSetupError as error:
            raise BuildError(str(error)) from error
        command(["xcrun", "simctl", "ui", device, "appearance", "dark"],
                output, "preview-appearance")
        command(["xcrun", "simctl", "status_bar", device, "override",
                 "--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active",
                 "--wifiBars", "3", "--cellularMode", "active", "--cellularBars", "4",
                 "--batteryState", "charged", "--batteryLevel", "100"],
                output, "preview-status-bar")
        command(["xcrun", "simctl", "install", device, str(app)],
                output, "preview-install", 180)
        cases=[case for case in preview_cases() if not screens or case['screen'] in screens]
        if screens and len(cases)!=len(screens):
            raise BuildError('One or more requested screen names are unknown or duplicated.')
        for number, case in enumerate(cases, 1):
            tab, screen, arguments = case["tab"], case["screen"], case["arguments"]
            launched = command(["xcrun", "simctl", "launch", "--terminate-running-process",
                                device, bundle, *arguments,
                                "-loqma-preview-font-audit",
                                *(["-loqma-ui-test-en"] if language=='en' else []),
                                "-AppleLanguages", "("+language+")", "-AppleLocale", "en_US" if language=='en' else "ar_SA"],
                               output, "preview-launch-" + screen, 300 if number == 1 else 120)
            match = re.search(r":\s*(\d+)\s*$", launched)
            if not match:
                raise BuildError(f"Launch of {screen} returned no application process ID.")
            pid = int(match.group(1))
            confirm_process(pid, settle_seconds)
            screenshot = output / f"{number:02d}-{screen}.png"
            details = capture_screenshot(output, device, screen, pid, screenshot)
            font_details = collect_runtime_font_audit(output, device, bundle, screen, pid, number,
                                                      "-loqma-preview-accessibility" in arguments)
            report["runtime_font_audits"].append({"screen": screen, **font_details})
            report["screenshots"].append({"tab": tab, "screen": screen,
                                          "kind": "tab" if tab is not None else screen,
                                          "synthetic_fixture": case["synthetic_fixture"],
                                          **{key: case[key] for key in ("template_route", "read_only_preview", "dynamic_type_override") if key in case},
                                          "process_still_running": True,
                                          **details})
            print(f"Captured native {screen}: {screenshot.name}", flush=True)
        if len(report["screenshots"]) != report['expected_screenshot_count']:
            raise BuildError("The native preview did not capture all required screens.")
        if len({item["frame_sha256"] for item in report["screenshots"]}) != report['expected_screenshot_count']:
            raise BuildError("Screenshots are identical; verify the DEBUG preview routes are installed.")
        if len(report["runtime_font_audits"]) != report['expected_screenshot_count']:
            raise BuildError("Native font verification did not cover every captured screen.")
        report["runtime_fonts_verified"] = True
        report["status"] = "captured"
    except BaseException as error:
        report["status"] = "cancelled" if isinstance(error, (SystemExit, KeyboardInterrupt)) else "failed"
        report["error"] = str(error)
        if device:
            collect_failure_diagnostics(output, device, report)
        raise
    finally:
        if device:
            for operation in ("shutdown", "delete"):
                try:
                    command(["xcrun", "simctl", operation, device], output,
                            "preview-cleanup-" + operation, 90, allow_failure=True)
                except (BuildError, OSError) as error:
                    report.setdefault("cleanup_warnings", []).append(str(error))
        report["completed_at"] = datetime.now(timezone.utc).isoformat()
        report["elapsed_seconds"] = round(time.monotonic() - started, 2)
        report["screenshot_count"] = len(report["screenshots"])
        (output / "ui-preview.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "UIPreview")
    parser.add_argument("--packages", type=Path, default=ROOT / "BuildOutput/Packages")
    parser.add_argument("--app", type=Path, help="Reuse an existing Debug arm64 Simulator .app")
    parser.add_argument("--bundle-id", default=os.environ.get("BUNDLE_ID", "") or "app.luqma.diary")
    parser.add_argument("--settle-seconds", type=float, default=6.0)
    parser.add_argument("--device-type",choices=[DEVICE_TYPE,REFERENCE_DEVICE_TYPE],default=DEVICE_TYPE)
    parser.add_argument("--language",choices=['ar','en'],default='ar')
    parser.add_argument("--screens",nargs='+',help='Optional subset of named native routes')
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", args.bundle_id):
        parser.error("Bundle identifier is invalid.")
    if not 1 <= args.settle_seconds <= 30:
        parser.error("Settle time must be between 1 and 30 seconds.")
    if not re.fullmatch(r"[1-9][0-9]{0,8}", os.environ.get("BUILD_NUMBER", "1") or "1"):
        parser.error("BUILD_NUMBER must be a positive integer with at most nine digits.")
    try:
        capture(args.output.resolve(), args.packages.resolve(),
                args.app.resolve() if args.app else None, args.bundle_id, args.settle_seconds,
                args.device_type,args.language,args.screens)
    except (BuildError, OSError, ValueError) as error:
        print("Luqma native UI preview:", str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda signum, _frame: sys.exit(128 + signum))
    sys.exit(main())
