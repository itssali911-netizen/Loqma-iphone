"""Bounded readiness checks for one Simulator freshly created by the caller.

The caller supplies a checked command runner that retains public command logs.
This module never creates/deletes devices or restarts global Simulator services.
"""
from __future__ import annotations

import json
from pathlib import PurePosixPath
import re
import subprocess
import time
from typing import Callable


Command = Callable[[list[str], str, int], str]
PROBE_BUNDLE = "com.apple.Preferences"
BOOT_TIMEOUT_SECONDS = 300
SETTINGS_TIMEOUT_SECONDS = 150
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


def _remaining_boot_seconds(deadline: float) -> int:
    remaining = int(deadline - time.monotonic())
    if remaining < 1:
        raise SimulatorSetupError(f"Simulator boot readiness exhausted its existing {BOOT_TIMEOUT_SECONDS}s deadline.")
    return remaining


def _wait_for_boot(device: str, command: Command, prefix: str,
                   handoffs: list[dict]) -> None:
    """Wait once without initiating another boot after a verified state race.

    Performance/UI runners retain stdout in their labeled log and expose a
    nonzero exit as ``<label> failed (<code>); see <file>.log.``. The native
    font probe uses a different envelope and keeps the existing recovery path.
    Exit 149 alone does
    not establish CoreSimulator error 405 or readiness. For this observed exit,
    require the exact available UUID to be Booted, then monitor without -b.
    The caller still requires a real Settings PID. A timeout is not this race.
    """
    deadline = time.monotonic() + BOOT_TIMEOUT_SECONDS
    label = prefix + "-boot-ready"
    try:
        command(["xcrun", "simctl", "bootstatus", device, "-b"], label, BOOT_TIMEOUT_SECONDS)
    except STARTUP_FAILURES as error:
        # Accept only the actual checked-runner nonzero-exit envelope. Do not
        # misclassify wrapped timeouts, arbitrary boot errors, or a launch error.
        envelope = (r"(?:[A-Za-z0-9_-]+-)?" + re.escape(label)
                    + r" failed \(149\); see [^\r\n]+\.log\.")
        if (isinstance(error, subprocess.TimeoutExpired)
                or isinstance(error.__cause__, subprocess.TimeoutExpired)
                or not isinstance(error, RuntimeError)
                or not re.fullmatch(envelope, str(error))):
            raise
        try:
            inventory = json.loads(command(["xcrun", "simctl", "list", "devices", "--json"],
                                           prefix + "-boot-state",
                                           min(30, _remaining_boot_seconds(deadline))))
            devices = inventory.get("devices") if isinstance(inventory, dict) else None
            matches = ([item for items in devices.values() for item in items
                        if isinstance(item, dict) and item.get("udid", "").lower() == device.lower()]
                       if isinstance(devices, dict) and all(isinstance(items, list) for items in devices.values()) else [])
            confirmed = (len(matches) == 1 and matches[0].get("state") == "Booted"
                         and matches[0].get("isAvailable") is True)
        except (ValueError, TypeError, AttributeError, *STARTUP_FAILURES):
            # The original nonzero wait remains the startup failure if the
            # exact current state cannot be independently confirmed.
            raise error
        if not confirmed:
            raise
        handoffs.append({"initial_error": str(error)[:1024], "confirmed_state": "Booted",
                         "attempt": int(prefix.rsplit("-", 1)[1]), "monitor_boots_device": False})
        # Consume the original boot deadline, never a fresh 300-second budget.
        command(["xcrun", "simctl", "bootstatus", device], prefix + "-boot-monitor",
                _remaining_boot_seconds(deadline))


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
    boot_wait_handoffs: list[dict] = []
    for attempt in (1, 2):
        prefix = f"simulator-bootstrap-{attempt}"
        try:
            command(["/usr/bin/open", "-g", "-a", simulator_app, "--args",
                     "-CurrentDeviceUDID", device], prefix + "-open", 30)
            # Keep the GUI prerequisite. If open and -b race to start this
            # exact device, verify Booted and continue monitoring without -b;
            # no extra reboot or enlarged readiness deadline is introduced.
            _wait_for_boot(device, command, prefix, boot_wait_handoffs)
            # Build 57 attempts 1/2 reached a running Settings process about
            # 96/101 seconds after bootstatus finished, with scene readiness
            # around 102/109 seconds. Allow that observed system startup lag;
            # the command must still return a real PID within this fixed limit.
            launched = command(["xcrun", "simctl", "launch", device, PROBE_BUNDLE],
                               prefix + "-settings", SETTINGS_TIMEOUT_SECONDS)
            process = re.search(r"(?m)^com\.apple\.Preferences:\s*([1-9][0-9]*)\s*$", launched)
            if not process:
                raise SimulatorSetupError("System Settings readiness probe returned no process ID.")
            return {"attempts": attempt, "reboot_performed": attempt == 2,
                    "probe_bundle": PROBE_BUNDLE, "probe_pid": int(process.group(1)),
                    "selected_simulator_app": simulator_app, "failures": failures,
                    "diagnostic_failures": diagnostic_failures, "boot_wait_handoffs": boot_wait_handoffs}
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
