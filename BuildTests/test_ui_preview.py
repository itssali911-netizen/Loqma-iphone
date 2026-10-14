"""Portable checks for real PNG decoding and bounded native capture retries.

The fixtures contain pixels, not fabricated app screenshots. Simulator and
process boundaries are mocked only when testing orchestration.
"""
import hashlib
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Scripts"))
from ui_preview import (BuildError, EXPECTED_SCREEN_COUNT, EXTRA_ROUTES,
                        SCREENS, TEMPLATE_ROUTES, VARIANT_ROUTES,
                        capture_screenshot, decode_png, framebuffer_content, png_details, preview_cases)


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
                         len(SCREENS) + 2 + len(EXTRA_ROUTES) + len(TEMPLATE_ROUTES) + len(VARIANT_ROUTES))
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
                self.assertEqual(case["synthetic_fixture"], route in {"portion", "recipe"})

    def test_accessibility_dashboard_composes_the_same_read_only_overview(self):
        cases = {case["screen"]: case for case in preview_cases()}
        case = cases["accessibility-today"]
        self.assertEqual(case["arguments"], ["-loqma-preview-overview", "-loqma-preview-accessibility"])
        self.assertEqual(case["dynamic_type_override"], "accessibility3")
        self.assertTrue(case["synthetic_fixture"])


if __name__ == "__main__":
    unittest.main()
