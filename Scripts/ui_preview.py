#!/usr/bin/env python3
"""Capture real SwiftUI screens on a fresh iPhone 16 Pro Simulator.

Requires an Apple Silicon Mac, Xcode, and an installed iOS Simulator runtime.
This builds a Debug Simulator app, launches each native tab using the app's
DEBUG-only -loqma-preview-tab argument, and captures the Simulator framebuffer.
Two more launches use -loqma-preview-photo and -loqma-preview-recipe to show
synthetic fixtures in the production meal and recipe reviews. These are native
UI evidence, not live analyses.
It creates no mock UI, sends no image to an API, and modifies no existing device.

Apple command-line screenshot documentation:
https://developer.apple.com/library/archive/documentation/IDEs/Conceptual/iOS_Simulator_Guide/InteractingwiththeiOSSimulator/InteractingwiththeiOSSimulator.html
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
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
from vision_compat import apply_vision_compat


ROOT = Path(__file__).resolve().parent.parent
DEVICE_TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"
SCREENS = ((0, "today"), (1, "kitchen"), (2, "progress"), (3, "settings"))
PHOTO_SCREEN = "photo-estimate"
RECIPE_SCREEN = "recipe-import"
EXPECTED_SCREEN_COUNT = len(SCREENS) + 2


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


def png_details(path: Path) -> dict:
    data = path.read_bytes()
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise BuildError(f"{path.name} is not a valid PNG screenshot.")
    width, height = struct.unpack(">II", data[16:24])
    if width < 700 or height < 1400:
        raise BuildError(f"{path.name} has unexpected phone screenshot dimensions.")
    # Compare framebuffer data rather than PNG metadata or compression bytes.
    compressed = bytearray()
    offset = 8
    while offset + 12 <= len(data):
        length = struct.unpack(">I", data[offset:offset + 4])[0]
        if offset + 12 + length > len(data):
            raise BuildError(f"{path.name} contains an incomplete PNG chunk.")
        if data[offset + 4:offset + 8] == b"IDAT":
            compressed.extend(data[offset + 8:offset + 8 + length])
        offset += length + 12
    try:
        frame = zlib.decompress(compressed)
    except zlib.error as error:
        raise BuildError(f"{path.name} has no readable PNG framebuffer.") from error
    return {"file": path.name, "width": width, "height": height,
            "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
            "frame_sha256": hashlib.sha256(frame).hexdigest()}


def confirm_process(pid: int, seconds: float) -> None:
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            os.kill(pid, 0)
        except OSError as error:
            raise BuildError("Luqma exited before the screenshot; inspect the Simulator log.") from error
        time.sleep(min(0.5, max(0, deadline - time.monotonic())))


def capture(output: Path, packages: Path, prebuilt: Path | None,
            bundle: str, settle_seconds: float) -> None:
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
        "expected_screenshot_count": EXPECTED_SCREEN_COUNT,
        "synthetic_photo_fixture": True,
        "synthetic_recipe_fixture": True,
        "layout_review": "Pending visual inspection of the native screenshots",
        "screenshots": [],
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
        if not any(item.get("identifier") == DEVICE_TYPE for item in types):
            raise BuildError("The selected Xcode has no iPhone 16 Pro Simulator device type.")
        runtime = select_runtime(inventory)
        name = "Luqma UI Preview " + uuid.uuid4().hex[:8]
        device = command(["xcrun", "simctl", "create", name, DEVICE_TYPE,
                          runtime["identifier"]], output, "preview-create").strip()
        if not re.fullmatch(r"[0-9A-Fa-f-]{36}", device):
            device = None
            raise BuildError("Simulator creation did not return a valid device identifier.")
        report["simulator"] = {"udid": device, "device": "iPhone 16 Pro",
                               "runtime": runtime["name"], "runtime_id": runtime["identifier"]}
        report["fresh_simulator"] = True
        command(["xcrun", "simctl", "boot", device], output, "preview-boot", 120)
        command(["xcrun", "simctl", "bootstatus", device, "-b"],
                output, "preview-boot-ready", 240)
        command(["xcrun", "simctl", "ui", device, "appearance", "dark"],
                output, "preview-appearance")
        command(["xcrun", "simctl", "status_bar", device, "override",
                 "--time", "9:41", "--dataNetwork", "wifi", "--wifiMode", "active",
                 "--wifiBars", "3", "--cellularMode", "active", "--cellularBars", "4",
                 "--batteryState", "charged", "--batteryLevel", "100"],
                output, "preview-status-bar")
        command(["xcrun", "simctl", "install", device, str(app)],
                output, "preview-install", 180)
        cases = list(SCREENS) + [(None, PHOTO_SCREEN), (None, RECIPE_SCREEN)]
        for number, (tab, screen) in enumerate(cases, 1):
            arguments = (["-loqma-preview-recipe"] if screen == RECIPE_SCREEN else ["-loqma-preview-photo"]) if tab is None else ["-loqma-preview-tab", str(tab)]
            launched = command(["xcrun", "simctl", "launch", "--terminate-running-process",
                                device, bundle, *arguments,
                                "-AppleLanguages", "(ar)", "-AppleLocale", "ar_SA"],
                               output, "preview-launch-" + screen, 120)
            match = re.search(r":\s*(\d+)\s*$", launched)
            if not match:
                raise BuildError(f"Launch of {screen} returned no application process ID.")
            pid = int(match.group(1))
            confirm_process(pid, settle_seconds)
            screenshot = output / f"{number:02d}-{screen}.png"
            command(["xcrun", "simctl", "io", device, "screenshot", "--type=png",
                     str(screenshot)], output, "preview-capture-" + screen, 90)
            confirm_process(pid, 0.25)
            report["screenshots"].append({"tab": tab, "screen": screen,
                                          "kind": "recipe-import" if screen == RECIPE_SCREEN else "meal-estimate" if tab is None else "tab",
                                          "synthetic_fixture": tab is None,
                                          "process_still_running": True,
                                          **png_details(screenshot)})
            print(f"Captured native {screen}: {screenshot.name}", flush=True)
        if len(report["screenshots"]) != EXPECTED_SCREEN_COUNT:
            raise BuildError("The native preview did not capture all four tabs and both meal/recipe reviews.")
        if len({item["frame_sha256"] for item in report["screenshots"]}) != EXPECTED_SCREEN_COUNT:
            raise BuildError("Screenshots are identical; verify the DEBUG preview tab and meal/recipe fixture routes are installed.")
        report["status"] = "captured"
    except BaseException as error:
        report["status"] = "cancelled" if isinstance(error, (SystemExit, KeyboardInterrupt)) else "failed"
        report["error"] = str(error)
        if device:
            try:
                command(["xcrun", "simctl", "spawn", device, "log", "show", "--last", "2m",
                         "--style", "compact", "--predicate", 'process == "Luqma"'],
                        output, "preview-app-diagnostic", 90, allow_failure=True)
            except (BuildError, OSError) as diagnostic_error:
                report["diagnostic_error"] = str(diagnostic_error)
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
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", args.bundle_id):
        parser.error("Bundle identifier is invalid.")
    if not 1 <= args.settle_seconds <= 30:
        parser.error("Settle time must be between 1 and 30 seconds.")
    if not re.fullmatch(r"[1-9][0-9]{0,8}", os.environ.get("BUILD_NUMBER", "1") or "1"):
        parser.error("BUILD_NUMBER must be a positive integer with at most nine digits.")
    try:
        capture(args.output.resolve(), args.packages.resolve(),
                args.app.resolve() if args.app else None, args.bundle_id, args.settle_seconds)
    except (BuildError, OSError, ValueError) as error:
        print("Luqma native UI preview:", str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, lambda signum, _frame: sys.exit(128 + signum))
    sys.exit(main())
