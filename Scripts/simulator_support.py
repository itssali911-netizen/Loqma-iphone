"""Bounded readiness checks for one Simulator freshly created by the caller.

The caller supplies a checked command runner that retains public command logs.
This module never creates/deletes devices or restarts global Simulator services.
"""
from __future__ import annotations

import json
from pathlib import PurePosixPath
import re
import subprocess
from typing import Callable


Command = Callable[[list[str], str, int], str]
PROBE_BUNDLE = "com.apple.Preferences"
BOOT_TIMEOUT_SECONDS = 300
STARTUP_FAILURES = (OSError, RuntimeError, subprocess.SubprocessError)
DEVICE_PATTERN = re.compile(r"[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}")


class SimulatorSetupError(RuntimeError):
    """The caller-owned device failed its bounded startup/readiness checks."""


def _validate_device(device: str) -> None:
    if not isinstance(device, str) or not DEVICE_PATTERN.fullmatch(device):
        raise SimulatorSetupError("Simulator preparation requires one exact caller-created device UUID.")


def _selected_simulator_app(command: Command, developer_dir: str | None) -> str:
    if developer_dir is None:
        # xcrun follows the selected toolchain, including DEVELOPER_DIR, rather
        # than guessing which Xcode happens to be the host's global default.
        selected = command(["xcrun", "--find", "simctl"], "simulator-selected-tool", 30).strip()
        tool = PurePosixPath(selected)
        if not tool.is_absolute() or tuple(tool.parts[-3:]) != ("usr", "bin", "simctl"):
            raise SimulatorSetupError("Selected Xcode returned an invalid simctl path.")
        developer_dir = str(tool.parents[2])
    developer = PurePosixPath(developer_dir)
    if (not developer.is_absolute() or ".." in developer.parts
            or tuple(developer.parts[-2:]) != ("Contents", "Developer")
            or len(developer.parts) < 4 or not developer.parents[1].name.endswith(".app")):
        raise SimulatorSetupError("Simulator preparation requires the selected Xcode app's developer directory.")
    return str(developer / "Applications/Simulator.app")


def collect_startup_diagnostics(device: str, command: Command, label: str) -> str | None:
    """Retain ten minutes of startup-service logs from this device only.

    Diagnosis must never hide the original readiness failure. Return a public
    logging failure for callers that want to include it in their report.
    """
    _validate_device(device)
    predicate = ('process == "SpringBoard" OR process == "runningboardd" '
                 'OR process == "launchd_sim" OR process == "installd"')
    try:
        command(["xcrun", "simctl", "spawn", device, "log", "show", "--last", "10m",
                 "--style", "compact", "--predicate", predicate], label, 60)
    except STARTUP_FAILURES as error:
        return str(error)[:1024]
    return None


def _confirm_shutdown(device: str, command: Command) -> bool:
    inventory = json.loads(command(["xcrun", "simctl", "list", "devices", "--json"],
                                   "simulator-recovery-state", 30))
    matches = [item for items in inventory.get("devices", {}).values() for item in items
               if item.get("udid", "").lower() == device.lower()]
    return len(matches) == 1 and matches[0].get("state") == "Shutdown"


def prepare_created_simulator(device: str, command: Command, *,
                              developer_dir: str | None = None) -> dict:
    """Boot/warm one caller-created Simulator, retrying its startup once.

    ``command(args, label, timeout)`` must raise on a timeout/nonzero exit and
    retain each labeled log. Settings must actually return a launch PID before
    the caller may install its own app. App installation, app launch, test
    assertions and the caller's exact-device cleanup remain outside this helper.
    """
    _validate_device(device)
    simulator_app = _selected_simulator_app(command, developer_dir)
    failures: list[str] = []
    diagnostic_failures: list[str] = []
    for attempt in (1, 2):
        prefix = f"simulator-bootstrap-{attempt}"
        try:
            command(["/usr/bin/open", "-g", "-a", simulator_app, "--args",
                     "-CurrentDeviceUDID", device], prefix + "-open", 30)
            # -b boots if needed and waits when Simulator.app already initiated
            # this exact device's boot; a separate boot would race with open.
            # A fresh iOS 26.5 device can still be running CoreLocation data
            # migration at three minutes. Let that existing migration finish
            # before using the single reboot; readiness must still succeed.
            command(["xcrun", "simctl", "bootstatus", device, "-b"], prefix + "-boot-ready", BOOT_TIMEOUT_SECONDS)
            launched = command(["xcrun", "simctl", "launch", device, PROBE_BUNDLE],
                               prefix + "-settings", 90)
            process = re.search(r"(?m)^com\.apple\.Preferences:\s*([1-9][0-9]*)\s*$", launched)
            if not process:
                raise SimulatorSetupError("System Settings readiness probe returned no process ID.")
            return {"attempts": attempt, "reboot_performed": attempt == 2,
                    "probe_bundle": PROBE_BUNDLE, "probe_pid": int(process.group(1)),
                    "selected_simulator_app": simulator_app, "failures": failures,
                    "diagnostic_failures": diagnostic_failures}
        except STARTUP_FAILURES as error:
            failures.append(str(error)[:1024])
            diagnostic = collect_startup_diagnostics(device, command, prefix + "-diagnostic")
            if diagnostic:
                diagnostic_failures.append(diagnostic)
            if attempt == 2:
                raise SimulatorSetupError("Caller-created Simulator failed both startup attempts: "
                                          + " | ".join(failures)) from error
            try:
                command(["xcrun", "simctl", "shutdown", device], "simulator-recovery-shutdown", 60)
            except STARTUP_FAILURES as shutdown_error:
                # A boot failure can leave an already-shutdown device. Accept
                # that case only after checking this exact UUID's actual state.
                try:
                    confirmed = _confirm_shutdown(device, command)
                except (ValueError, TypeError, *STARTUP_FAILURES):
                    confirmed = False
                if not confirmed:
                    raise SimulatorSetupError("Caller-created Simulator could not be shut down for its one retry: "
                                              + str(shutdown_error)[:1024]) from shutdown_error
    raise AssertionError("Unreachable bounded Simulator startup loop")
