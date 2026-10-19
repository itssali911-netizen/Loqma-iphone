"""Portable checks for real PNG decoding and bounded native capture retries.

The fixtures contain pixels, not fabricated app screenshots. Simulator and
process boundaries are mocked only when testing orchestration.
"""
import hashlib
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Scripts"))
from ui_preview import (BuildError, DEVICE_TYPE, EXPECTED_SCREEN_COUNT, EXTRA_ROUTES, FITNESS_ROUTES, SimulatorSetupError,
                        SCREENS, TEMPLATE_ROUTES, VARIANT_ROUTES,
                        capture, capture_screenshot, collect_runtime_font_audit, decode_png, framebuffer_content,
                        png_details, preview_cases, validate_runtime_font_audit)


def chunk(kind, content):
    return (struct.pack(">I", len(content)) + kind + content +
            struct.pack(">I", zlib.crc32(kind + content) & 0xffffffff))


def png(width, height, rows, color=2, depth=8):
    header = struct.pack(">IIBBBBB", width, height, depth, color, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) +
            chunk(b"IDAT", zlib.compress(b"".join(rows))) + chunk(b"IEND", b""))


class FramebufferTests(unittest.TestCase):
    def test_all_png_scanline_filters_decode_known_rgb_values(self):
        expected = bytes([1, 10, 100, 3, 14, 110, 7, 20, 130, 11, 30, 150])
        filtered = {
            0: ([1, 10, 100, 3, 14, 110], [7, 20, 130, 11, 30, 150]),
            1: ([1, 10, 100, 2, 4, 10], [7, 20, 130, 4, 10, 20]),
            2: ([1, 10, 100, 3, 14, 110], [6, 10, 30, 8, 16, 40]),
            3: ([1, 10, 100, 3, 9, 60], [7, 15, 80, 6, 13, 30]),
            4: ([1, 10, 100, 2, 4, 10], [6, 10, 30, 4, 10, 20]),
        }
        for mode, rows in filtered.items():
            with self.subTest(filter=mode):
                width, height, channels, pixels, original = decode_png(
                    png(2, 2, [bytes([mode] + row) for row in rows]), "filter.png")
                self.assertEqual((width, height, channels), (2, 2, 3))
                self.assertEqual(pixels, expected)
                self.assertEqual(original, b"".join(bytes([mode] + row) for row in rows))

    def test_status_bar_and_home_indicator_do_not_mask_black_launch_frame(self):
        width, height = 720, 1440
        white = b"\0" + bytes([255, 255, 255]) * width
        black = b"\0" + bytes([0, 0, 0]) * width
        rows = [white if y < 100 or y > 1330 else black for y in range(height)]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "frame.png"
            data = png(width, height, rows)
            path.write_bytes(data)
            result = png_details(path)
            self.assertTrue(result["near_empty_black_frame"])
            self.assertEqual(result["near_black_body_fraction"], 1.0)
            self.assertEqual(result["sha256"], hashlib.sha256(data).hexdigest())
            self.assertEqual(result["frame_sha256"], hashlib.sha256(b"".join(rows)).hexdigest())
            self.assertEqual(path.read_bytes(), data, "Inspection must not edit the actual capture")

    def test_dark_cards_on_black_background_are_not_rejected(self):
        width, height = 720, 1440
        black = b"\0" + bytes([0, 0, 0]) * width
        card = b"\0" + bytes([0, 0, 0]) * 30 + bytes([22, 22, 38]) * 660 + bytes([0, 0, 0]) * 30
        rows = [card if 340 <= y < 680 else black for y in range(height)]
        w, h, channels, pixels, _ = decode_png(png(width, height, rows), "dark-cards.png")
        details = framebuffer_content(w, h, channels, pixels)
        self.assertFalse(details["near_empty_black_frame"])
        self.assertLess(details["near_black_body_fraction"], .75)

    def test_rgba_and_grayscale_pixels_decode_and_transparency_is_black(self):
        for color, channels in ((0, 1), (4, 2), (6, 4)):
            with self.subTest(color=color):
                pixel = bytes([255] * (channels - 1) + [0]) if channels > 1 else b"\0"
                w, h, actual_channels, pixels, _ = decode_png(
                    png(20, 20, [b"\0" + pixel * 20] * 20, color=color), "pixels.png")
                self.assertEqual(actual_channels, channels)
                self.assertTrue(framebuffer_content(w, h, channels, pixels)["near_empty_black_frame"])

    def test_invalid_crc_size_filter_and_truncated_png_are_rejected(self):
        good = png(2, 1, [b"\0" + b"\xff" * 6])
        damaged = bytearray(good)
        damaged[29] ^= 1  # IHDR checksum
        bad_cases = [
            (bytes(damaged), "damaged"),
            (good[:-1], "incomplete"),
            (png(2, 2, [b"\0" + b"\xff" * 6]), "size mismatch"),
            (png(2, 1, [b"\5" + b"\xff" * 6]), "scanline filter"),
            (png(2, 1, [b"\0" + b"\xff" * 6], depth=16), "supported 8-bit"),
        ]
        for data, message in bad_cases:
            with self.subTest(failure=message), self.assertRaisesRegex(BuildError, message):
                decode_png(data, "broken.png")

    def test_phone_dimensions_are_checked_after_pixel_decoding(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "tiny.png"
            path.write_bytes(png(2, 1, [b"\0" + b"\xff" * 6]))
            with self.assertRaisesRegex(BuildError, "phone screenshot dimensions"):
                png_details(path)


class CaptureRetryTests(unittest.TestCase):
    def capture(self, directory, frames, fail_liveness=False):
        screenshot = Path(directory) / "09-daily-overview.png"
        commands = []
        details = [{"sha256": hashlib.sha256(data).hexdigest(), "near_black_body_fraction": 1.0 if empty else .5,
                    "near_empty_black_frame": empty} for data, empty in frames]
        frame_iterator = iter(frames)

        def command(arguments, *_args):
            commands.append(arguments)
            data, _ = next(frame_iterator)
            Path(arguments[-1]).write_bytes(data)
            return ""

        def liveness(_pid, seconds):
            if fail_liveness and seconds == 5.0:
                raise BuildError("Luqma exited before the screenshot")

        with patch("ui_preview.command", side_effect=command), \
                patch("ui_preview.png_details", side_effect=details), \
                patch("ui_preview.confirm_process", side_effect=liveness) as process:
            result = capture_screenshot(Path(directory), "simulator-id", "daily-overview", 1234, screenshot)
        return result, screenshot, commands, process

    def test_black_frame_is_preserved_and_same_process_recaptured_once(self):
        with tempfile.TemporaryDirectory() as directory:
            result, screenshot, commands, process = self.capture(
                directory, [(b"original black frame", True), (b"original visible frame", False)])
            self.assertEqual(result["capture_attempts"], 2)
            self.assertEqual(len(commands), 2)
            self.assertTrue(all(arguments[:6] == ["xcrun", "simctl", "io", "simulator-id", "screenshot", "--type=png"]
                                for arguments in commands))
            process.assert_any_call(1234, 5.0)
            self.assertTrue(all(call.args[0] == 1234 for call in process.call_args_list))
            self.assertEqual(screenshot.read_bytes(), b"original visible frame")
            rejected = Path(directory) / result["rejected_empty_frames"][0]["file"]
            self.assertEqual(rejected.read_bytes(), b"original black frame")

    def test_retry_bound_is_two_and_final_empty_capture_remains_unmodified(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(BuildError, "after 3 framebuffer captures"):
                self.capture(directory, [(b"black 1", True), (b"black 2", True), (b"black 3", True)])
            self.assertEqual((Path(directory) / "09-daily-overview.png").read_bytes(), b"black 3")
            self.assertEqual(len(list((Path(directory) / "rejected-framebuffers").glob("*.png"))), 2)

    def test_exited_process_cannot_be_recaptured(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaisesRegex(BuildError, "exited before"):
                self.capture(directory, [(b"black 1", True), (b"must not be captured", False)], fail_liveness=True)
            self.assertFalse((Path(directory) / "09-daily-overview.png").exists())
            self.assertEqual(len(list((Path(directory) / "rejected-framebuffers").glob("*.png"))), 1)

    def test_all_routes_have_distinct_names_and_the_count_tracks_coverage(self):
        cases = preview_cases()
        self.assertEqual(EXPECTED_SCREEN_COUNT,
                         len(SCREENS) + 2 + len(EXTRA_ROUTES) + len(TEMPLATE_ROUTES) + len(VARIANT_ROUTES) + len(FITNESS_ROUTES))
        self.assertEqual(len(cases), EXPECTED_SCREEN_COUNT)
        self.assertEqual(len({case["screen"] for case in cases}), len(cases))
        self.assertTrue(all(case["arguments"] and all(isinstance(value, str) for value in case["arguments"])
                            for case in cases))
        self.assertIn(("daily-overview", "-loqma-preview-overview"), EXTRA_ROUTES)
        self.assertEqual(cases[len(SCREENS) + 2 + len(EXTRA_ROUTES) - 1]["screen"], "daily-overview")

    def test_secondary_forms_use_one_read_only_route_and_mark_only_synthetic_examples(self):
        cases = {case["screen"]: case for case in preview_cases()}
        for screen, route in TEMPLATE_ROUTES:
            with self.subTest(route=route):
                case = cases[screen]
                self.assertEqual(case["arguments"], ["-loqma-preview-template", route])
                self.assertTrue(case["read_only_preview"])
                self.assertEqual(case["synthetic_fixture"], route in {"portion", "recipe", "recipeDetail"} or route.startswith("state"))

    def test_accessibility_dashboard_composes_the_same_read_only_overview(self):
        cases = {case["screen"]: case for case in preview_cases()}
        case = cases["accessibility-today"]
        self.assertEqual(case["arguments"], ["-loqma-preview-overview", "-loqma-preview-accessibility"])
        self.assertEqual(case["dynamic_type_override"], "accessibility3")
        self.assertTrue(case["synthetic_fixture"])

    def test_fitness_routes_are_explicit_read_only_synthetic_previews(self):
        cases = {case["screen"]: case for case in preview_cases()}
        self.assertEqual(len(FITNESS_ROUTES), 8)
        for screen, route in FITNESS_ROUTES:
            with self.subTest(screen=screen):
                self.assertEqual(cases[screen]["arguments"], ["-loqma-preview-template", route])
                self.assertTrue(cases[screen]["synthetic_fixture"])
                self.assertTrue(cases[screen]["read_only_preview"])


def synthetic_font_audit(pid=1234, accessibility=False):
    """Validator input only: this fixture is never used as native font evidence."""
    roles = ["display", "screenTitle", "sectionTitle", "headline", "body", "subheadline",
             "helper", "caption", "caption2", "button", "metric", "legacyLightPromoted"]
    entries = [{"role": role, "resolvedLatinPostScript": "WorkSans-Regular",
                "resolvedArabicPostScript": "Tajawal-Regular", "uiFontPostScript": "WorkSans-Regular",
                "latinRuns": ["WorkSans-Regular"], "arabicRuns": ["Tajawal-Regular"],
                "mixedRuns": ["WorkSans-Regular", "Tajawal-Regular"], "missingGlyphs": 0,
                "registered": True, "passed": True, "basePoints": 16,
                "scaledPoints": 32 if accessibility else 16, "lineHeight": 40 if accessibility else 20,
                "effectiveWeight": "regular"} for role in roles]
    return {"processIdentifier": pid, "fontAudit": {
        "source": "Actual UIKit fonts and CoreText shaped runs from LuqmaTypography", "passed": True,
        "entries": entries, "emojiFonts": ["AppleColorEmoji"],
        "contentSizeCategory": "UICTContentSizeCategoryAccessibilityXXXL" if accessibility else "UICTContentSizeCategoryL"}}


class RuntimeFontAuditTests(unittest.TestCase):
    def test_registered_names_and_actual_shaped_runs_are_both_required(self):
        value = synthetic_font_audit()
        self.assertTrue(validate_runtime_font_audit(value, 1234, False)["passed"])
        value["fontAudit"]["entries"][0]["arabicRuns"] = [".SFArabic-Regular"]
        with self.assertRaisesRegex(BuildError, "shaping"):
            validate_runtime_font_audit(value, 1234, False)

    def test_matching_process_id_rejects_stale_previous_launch(self):
        with self.assertRaisesRegex(BuildError, "process ID"):
            validate_runtime_font_audit(synthetic_font_audit(pid=42), 1234, False)

    def test_missing_glyphs_fail_even_when_app_summary_claims_passed(self):
        value = synthetic_font_audit()
        value["fontAudit"]["entries"][0]["missingGlyphs"] = 1
        with self.assertRaisesRegex(BuildError, "shaping"):
            validate_runtime_font_audit(value, 1234, False)

    def test_accessibility_requires_real_larger_points_and_category(self):
        self.assertTrue(validate_runtime_font_audit(synthetic_font_audit(accessibility=True), 1234, True)["accessibility_scaling_verified"])
        with self.assertRaisesRegex(BuildError, "scale"):
            validate_runtime_font_audit(synthetic_font_audit(), 1234, True)
        value = synthetic_font_audit(accessibility=True)
        value["fontAudit"]["contentSizeCategory"] = "UICTContentSizeCategoryL"
        with self.assertRaisesRegex(BuildError, "Dynamic Type"):
            validate_runtime_font_audit(value, 1234, True)

    def test_missing_roles_thin_weight_and_invalid_measured_size_fail(self):
        for change, message in ((lambda value: value["fontAudit"]["entries"].pop(), "roles"),
                                (lambda value: value["fontAudit"]["entries"][0].update(effectiveWeight="light"), "thin"),
                                (lambda value: value["fontAudit"]["entries"][0].update(scaledPoints=float("nan")), "size")):
            with self.subTest(message=message):
                value = synthetic_font_audit()
                change(value)
                with self.assertRaisesRegex(BuildError, message):
                    validate_runtime_font_audit(value, 1234, False)

    def test_native_audit_bytes_are_preserved_before_failed_validation(self):
        with tempfile.TemporaryDirectory() as directory:
            container = Path(directory) / "app-data"
            source = container / "Documents/luqma-font-audit.json"
            source.parent.mkdir(parents=True)
            value = synthetic_font_audit(pid=42)
            data = json.dumps(value).encode()
            source.write_bytes(data)
            output = Path(directory) / "capture"
            output.mkdir()
            with patch("ui_preview.command", return_value=str(container)):
                with self.assertRaisesRegex(BuildError, "process ID"):
                    collect_runtime_font_audit(output, "created-device", "app.luqma.diary", "today", 1234, 1, False)
            self.assertEqual((output / "font-audits/01-today.json").read_bytes(), data)


class SimulatorIntegrationTests(unittest.TestCase):
    def run_until_launch(self, directory, warmup_failure=False):
        device = "A1234567-1234-1234-1234-123456789ABC"
        events = []
        output = Path(directory) / "native-preview"
        inventory = {"devicetypes": [{"identifier": DEVICE_TYPE}],
                     "runtimes": [{"isAvailable": True, "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-0",
                                   "version": "26.0", "name": "iOS 26.0"}]}

        def command(arguments, _output, label, timeout=120, allow_failure=False):
            events.append((label, arguments, timeout))
            if label == "preview-inventory":
                return json.dumps(inventory)
            if label == "preview-create":
                return device
            if label.startswith("preview-launch-"):
                raise BuildError("Stop after the first actual app launch boundary")
            return ""

        def prepare(actual_device, callback):
            self.assertEqual(actual_device, device)
            events.append(("warm-up", [], 0))
            callback(["xcrun", "simctl", "bootstatus", actual_device, "-b"], "simulator-bootstrap-ready", 240)
            if warmup_failure:
                raise SimulatorSetupError("The own-device readiness probe failed")
            return {"attempts": 1, "reboot_performed": False, "probe_bundle": "com.apple.Preferences", "probe_pid": 123}

        with patch("ui_preview.require_mac"), patch("ui_preview.platform.machine", return_value="arm64"), \
                patch("ui_preview.validate_app", return_value={"bundle_id": "app.luqma.diary"}), \
                patch("ui_preview.command", side_effect=command), \
                patch("ui_preview.prepare_created_simulator", side_effect=prepare):
            expected = "readiness probe failed" if warmup_failure else "first actual app launch boundary"
            with self.assertRaisesRegex(BuildError, expected):
                capture(output, Path(directory) / "packages", Path(directory) / "Debug.app", "app.luqma.diary", 1)
        return device, events, json.loads((output / "ui-preview.json").read_text(encoding="utf-8"))

    def test_selected_simulator_warms_before_appearance_install_and_first_app_launch(self):
        with tempfile.TemporaryDirectory() as directory:
            device, events, report = self.run_until_launch(directory)
        labels = [event[0] for event in events]
        self.assertLess(labels.index("preview-create"), labels.index("warm-up"))
        self.assertLess(labels.index("preview-simulator-bootstrap-ready"), labels.index("preview-appearance"))
        self.assertLess(labels.index("preview-appearance"), labels.index("preview-install"))
        self.assertLess(labels.index("preview-install"), labels.index("preview-launch-today"))
        self.assertEqual(next(event[2] for event in events if event[0] == "preview-install"), 180)
        self.assertEqual(next(event[2] for event in events if event[0] == "preview-launch-today"), 300)
        self.assertEqual(report["simulator_preparation"]["probe_bundle"], "com.apple.Preferences")
        self.assertEqual(report["status"], "failed")
        self.assertEqual(report["expected_screenshot_count"], EXPECTED_SCREEN_COUNT)
        self.assertEqual(report["screenshot_count"], 0)
        device_diagnostic = next(event[1] for event in events if event[0] == "preview-app-diagnostic")
        self.assertEqual(device_diagnostic[:4], ["xcrun", "simctl", "spawn", device])
        self.assertEqual(device_diagnostic[device_diagnostic.index("--last") + 1], "10m")
        self.assertIn("SpringBoard", device_diagnostic[-1])
        self.assertIn("dyld", device_diagnostic[-1])
        self.assertIn("preview-host-diagnostic", labels)

    def test_failed_warmup_prevents_install_and_cleans_only_the_created_device(self):
        with tempfile.TemporaryDirectory() as directory:
            device, events, report = self.run_until_launch(directory, warmup_failure=True)
        labels = [event[0] for event in events]
        self.assertNotIn("preview-appearance", labels)
        self.assertNotIn("preview-install", labels)
        self.assertFalse(any(label.startswith("preview-launch-") for label in labels))
        cleanup = [event[1] for event in events if event[0].startswith("preview-cleanup-")]
        self.assertEqual(cleanup, [["xcrun", "simctl", "shutdown", device], ["xcrun", "simctl", "delete", device]])
        self.assertEqual(report["status"], "failed")
        self.assertEqual(report["screenshot_count"], 0)
        self.assertNotIn("simulator_preparation", report)


if __name__ == "__main__":
    unittest.main()
