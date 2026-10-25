"""Portable checks of bounded readiness and caller-owned Simulator recovery."""
import contextlib
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Scripts"))
from simulator_support import PROBE_BUNDLE, SimulatorSetupError, prepare_created_simulator
from signing import BuildError


DEVICE = "A9E07D7C-308C-4B99-AC79-877B728134A3"
OTHER_DEVICE = "1438B3C7-18F9-4357-9227-849B064F5181"
DEVELOPER = "/Applications/Xcode_26.3.app/Contents/Developer"


class FakeCommands:
    def __init__(self, overrides=None, state="Booted"):
        self.calls = []
        self.overrides = overrides or {}
        self.state = state

    def __call__(self, arguments, label, timeout):
        self.calls.append((list(arguments), label, timeout))
        if label in self.overrides:
            result = self.overrides[label]
            if isinstance(result, BaseException):
                raise result
            return result
        if arguments == ["xcrun", "--find", "simctl"]:
            return DEVELOPER + "/usr/bin/simctl\n"
        if arguments[:4] == ["xcrun", "simctl", "list", "devices"]:
            return json.dumps({"devices": {"iOS": [
                {"udid": DEVICE, "state": self.state, "isAvailable": True},
                {"udid": OTHER_DEVICE, "state": "Booted"}]}})
        if arguments[:3] == ["xcrun", "simctl", "launch"]:
            return PROBE_BUNDLE + ": 901\n"
        return ""


class SimulatorSupportTests(unittest.TestCase):
    def assert_only_owned_device_is_mutated(self, commands):
        for arguments, _, _ in commands.calls:
            self.assertFalse({"all", "booted", "unavailable", "erase", "delete", "killall"}.intersection(arguments))
            if arguments[:2] == ["xcrun", "simctl"] and arguments[2] in ("bootstatus", "launch", "shutdown", "spawn"):
                self.assertEqual(arguments[3], DEVICE)
            if arguments[0] == "/usr/bin/open":
                self.assertEqual(arguments[arguments.index("-CurrentDeviceUDID") + 1], DEVICE)

    def test_invalid_or_global_device_targets_are_rejected_before_commands(self):
        for device in ("all", "booted", "unavailable", "-" * 36, DEVICE + "\n", DEVICE + " extra", None):
            with self.subTest(device=device):
                commands = FakeCommands()
                with self.assertRaisesRegex(SimulatorSetupError, "exact caller-created"):
                    prepare_created_simulator(device, commands)
                self.assertEqual(commands.calls, [])

    def test_selected_xcode_opens_background_and_probes_settings_before_returning(self):
        commands = FakeCommands()
        result = prepare_created_simulator(DEVICE, commands)
        labels = [label for _, label, _ in commands.calls]
        self.assertEqual(labels, ["simulator-selected-tool", "simulator-bootstrap-1-open",
                                  "simulator-bootstrap-1-boot-ready", "simulator-bootstrap-1-settings"])
        self.assertEqual(commands.calls[1][0], ["/usr/bin/open", "-g", "-a",
                         DEVELOPER + "/Applications/Simulator.app", "--args", "-CurrentDeviceUDID", DEVICE])
        self.assertEqual(commands.calls[2][0], ["xcrun", "simctl", "bootstatus", DEVICE, "-b"])
        self.assertEqual(commands.calls[2][2], 300)
        self.assertEqual(commands.calls[3][2], 150)
        self.assertEqual(result["attempts"], 1)
        self.assertFalse(result["reboot_performed"])
        self.assertEqual((result["probe_bundle"], result["probe_pid"]), (PROBE_BUNDLE, 901))
        self.assertEqual(result["selected_simulator_app"], DEVELOPER + "/Applications/Simulator.app")
        self.assertEqual(result["failures"], [])
        json.dumps(result)
        self.assert_only_owned_device_is_mutated(commands)

    def test_actual_checked_runner_exit149_envelopes_handoff_to_monitor_and_real_settings(self):
        # Exercise both real wrapper formats, including the preview label
        # prefix, rather than assuming a CalledProcessError the runners do not
        # actually expose. Retained stdout contains the observed CI97 error.
        from performance_probe import execute
        from ui_preview import command
        boot = ["xcrun", "simctl", "bootstatus", DEVICE, "-b"]
        failure_output = (b"Device boot failed\n"
                          b"An error was encountered (domain=com.apple.CoreSimulator.SimError, code=405):\n"
                          b"Unable to boot device in current state: Booted\n")
        for runner, module, label in ((execute, "performance_probe", "simulator-bootstrap-1-boot-ready"),
                                      (command, "ui_preview", "preview-simulator-bootstrap-1-boot-ready")):
            with self.subTest(module=module), tempfile.TemporaryDirectory() as directory:
                with patch(module + ".subprocess.run", return_value=subprocess.CompletedProcess(boot, 149, failure_output)):
                    with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                        with self.assertRaises(BuildError) as caught:
                            runner(boot, Path(directory), label, 300)
                self.assertEqual((Path(directory) / (label + ".log")).read_bytes(), failure_output)
                commands = FakeCommands({"simulator-bootstrap-1-boot-ready": caught.exception})
                result = prepare_created_simulator(DEVICE, commands)
                labels = [name for _, name, _ in commands.calls]
                self.assertEqual(result["attempts"], 1)
                self.assertFalse(result["reboot_performed"])
                self.assertEqual(result["probe_pid"], 901)
                self.assertEqual(result["failures"], [])
                self.assertNotIn("simulator-recovery-shutdown", labels)
                self.assertFalse(any(name.endswith("-diagnostic") for name in labels))
                self.assertLess(labels.index("simulator-bootstrap-1-boot-state"), labels.index("simulator-bootstrap-1-boot-monitor"))
                self.assertLess(labels.index("simulator-bootstrap-1-boot-monitor"), labels.index("simulator-bootstrap-1-settings"))
                monitor = next(args for args, name, _ in commands.calls if name.endswith("-boot-monitor"))
                self.assertEqual(monitor, ["xcrun", "simctl", "bootstatus", DEVICE])
                self.assertEqual(result["boot_wait_handoffs"], [{"initial_error": str(caught.exception),
                                 "confirmed_state": "Booted", "attempt": 1, "monitor_boots_device": False}])
                json.dumps(result)
                self.assert_only_owned_device_is_mutated(commands)

    def test_exit149_handoff_requires_exact_unique_available_booted_device(self):
        error = BuildError("simulator-bootstrap-1-boot-ready failed (149); see simulator-bootstrap-1-boot-ready.log.")
        valid = {"udid": DEVICE, "state": "Booted", "isAvailable": True}
        variants = [[], [{"udid": OTHER_DEVICE, "state": "Booted", "isAvailable": True}],
                    [valid, valid], [dict(valid, state="Shutdown")], [dict(valid, state="Booting")],
                    [dict(valid, isAvailable=False)], [{"udid": DEVICE, "state": "Booted"}]]
        inventories = [json.dumps({"devices": {"iOS": items}}) for items in variants]
        inventories += ["not JSON", "[]", '{"devices":[]}', '{"devices":{"iOS":{}}}',
                        RuntimeError("inventory unavailable")]
        for inventory in inventories:
            with self.subTest(inventory=inventory):
                commands = FakeCommands({"simulator-bootstrap-1-boot-ready": error,
                                         "simulator-bootstrap-1-boot-state": inventory})
                result = prepare_created_simulator(DEVICE, commands)
                self.assertEqual(result["attempts"], 2)
                self.assertEqual(result["boot_wait_handoffs"], [])
                self.assertIn(str(error), result["failures"][0])
                self.assertFalse(any(name.endswith("-boot-monitor") for _, name, _ in commands.calls))
                self.assert_only_owned_device_is_mutated(commands)

    def test_timeouts_and_unrecognized_errors_never_use_boot_handoff(self):
        timeout = subprocess.TimeoutExpired(["xcrun", "simctl", "bootstatus", DEVICE, "-b"], 300)
        wrapped = BuildError("simulator-bootstrap-1-boot-ready exceeded 300s; evidence retained in simulator-bootstrap-1-boot-ready.log.")
        wrapped.__cause__ = timeout
        misleading = BuildError("simulator-bootstrap-1-boot-ready failed (149); see simulator-bootstrap-1-boot-ready.log.")
        misleading.__cause__ = timeout
        for error in (timeout, wrapped, misleading, OSError("boot I/O error"),
                      BuildError("simulator-bootstrap-1-boot-ready failed (65); see simulator-bootstrap-1-boot-ready.log."),
                      RuntimeError("149 Unable to boot device in current state: Booted")):
            with self.subTest(error=str(error)):
                commands = FakeCommands({"simulator-bootstrap-1-boot-ready": error})
                result = prepare_created_simulator(DEVICE, commands)
                self.assertEqual(result["attempts"], 2)
                self.assertFalse(any(name.endswith(("-boot-state", "-boot-monitor")) for _, name, _ in commands.calls))
                self.assertEqual(result["boot_wait_handoffs"], [])
                self.assert_only_owned_device_is_mutated(commands)

    def test_boot_handoff_consumes_existing_deadline_without_extending_it(self):
        error = BuildError("simulator-bootstrap-1-boot-ready failed (149); see simulator-bootstrap-1-boot-ready.log.")
        commands = FakeCommands({"simulator-bootstrap-1-boot-ready": error})
        with patch("simulator_support.time.monotonic", side_effect=[100.0, 104.0, 109.0]):
            result = prepare_created_simulator(DEVICE, commands)
        budgets = {name: timeout for _, name, timeout in commands.calls}
        self.assertEqual(budgets["simulator-bootstrap-1-boot-ready"], 300)
        self.assertEqual(budgets["simulator-bootstrap-1-boot-state"], 30)
        self.assertEqual(budgets["simulator-bootstrap-1-boot-monitor"], 291)
        self.assertEqual(budgets["simulator-bootstrap-1-settings"], 150)
        self.assertEqual(result["attempts"], 1)
        self.assert_only_owned_device_is_mutated(commands)

    def test_boot_handoff_cannot_monitor_after_existing_deadline_expires(self):
        error = BuildError("simulator-bootstrap-1-boot-ready failed (149); see simulator-bootstrap-1-boot-ready.log.")
        commands = FakeCommands({"simulator-bootstrap-1-boot-ready": error})
        with patch("simulator_support.time.monotonic", side_effect=[100.0, 101.0, 400.0, 500.0]):
            result = prepare_created_simulator(DEVICE, commands)
        self.assertEqual(result["attempts"], 2)
        self.assertIn("existing 300s deadline", result["failures"][0])
        self.assertFalse(any(name.endswith("-boot-monitor") for _, name, _ in commands.calls))
        self.assert_only_owned_device_is_mutated(commands)

    def test_failed_nonbooting_monitor_uses_only_existing_reboot_retry(self):
        error = BuildError("simulator-bootstrap-1-boot-ready failed (149); see simulator-bootstrap-1-boot-ready.log.")
        commands = FakeCommands({"simulator-bootstrap-1-boot-ready": error,
                                 "simulator-bootstrap-1-boot-monitor": RuntimeError("monitor failed")})
        result = prepare_created_simulator(DEVICE, commands)
        self.assertEqual(result["attempts"], 2)
        self.assertEqual(result["failures"], ["monitor failed"])
        self.assertEqual(len(result["boot_wait_handoffs"]), 1)
        self.assertEqual([name for _, name, _ in commands.calls].count("simulator-recovery-shutdown"), 1)
        self.assert_only_owned_device_is_mutated(commands)

    def test_booted_handoff_still_rejects_missing_real_settings_pid(self):
        error = BuildError("simulator-bootstrap-1-boot-ready failed (149); see simulator-bootstrap-1-boot-ready.log.")
        commands = FakeCommands({"simulator-bootstrap-1-boot-ready": error,
                                 "simulator-bootstrap-1-settings": "",
                                 "simulator-bootstrap-2-settings": ""})
        with self.assertRaisesRegex(SimulatorSetupError, "returned no process ID"):
            prepare_created_simulator(DEVICE, commands)
        self.assertEqual([name for _, name, _ in commands.calls].count("simulator-recovery-shutdown"), 1)
        self.assertFalse(any("bootstrap-3" in name for _, name, _ in commands.calls))
        self.assert_only_owned_device_is_mutated(commands)

    def test_readiness_timeout_reboots_only_owned_device_once_and_preserves_diagnostics(self):
        timeout = subprocess.TimeoutExpired(["xcrun", "simctl", "launch", DEVICE, PROBE_BUNDLE], 150)
        commands = FakeCommands({"simulator-bootstrap-1-settings": timeout})
        result = prepare_created_simulator(DEVICE, commands)
        self.assertEqual(result["attempts"], 2)
        self.assertTrue(result["reboot_performed"])
        self.assertEqual(len(result["failures"]), 1)
        labels = [label for _, label, _ in commands.calls]
        self.assertEqual(labels.count("simulator-recovery-shutdown"), 1)
        self.assertLess(labels.index("simulator-bootstrap-1-diagnostic"), labels.index("simulator-recovery-shutdown"))
        self.assertLess(labels.index("simulator-recovery-shutdown"), labels.index("simulator-bootstrap-2-open"))
        diagnostic = next(arguments for arguments, label, _ in commands.calls if label.endswith("-diagnostic"))
        self.assertEqual(diagnostic[diagnostic.index("--last") + 1], "10m")
        self.assert_only_owned_device_is_mutated(commands)

    def test_nonzero_boot_wait_has_one_retry_and_all_command_budgets_are_bounded(self):
        commands = FakeCommands({"simulator-bootstrap-1-boot-ready": RuntimeError("bootstatus nonzero")})
        result = prepare_created_simulator(DEVICE, commands)
        self.assertEqual(result["attempts"], 2)
        self.assertIn("bootstatus nonzero", result["failures"][0])
        self.assertLessEqual(max(timeout for _, _, timeout in commands.calls), 300)
        for attempt in (1, 2):
            budgets = [timeout for _, label, timeout in commands.calls
                       if label.startswith(f"simulator-bootstrap-{attempt}-") and not label.endswith("-diagnostic")]
            self.assertLessEqual(sum(budgets), 480)
        self.assert_only_owned_device_is_mutated(commands)

    def test_second_readiness_failure_is_fatal_and_does_not_make_a_third_attempt(self):
        second = RuntimeError("Settings launch failed again")
        commands = FakeCommands({"simulator-bootstrap-1-settings": RuntimeError("Settings unavailable"),
                                 "simulator-bootstrap-2-settings": second})
        with self.assertRaisesRegex(SimulatorSetupError, "both startup attempts") as caught:
            prepare_created_simulator(DEVICE, commands)
        self.assertIs(caught.exception.__cause__, second)
        labels = [label for _, label, _ in commands.calls]
        self.assertEqual(labels.count("simulator-recovery-shutdown"), 1)
        self.assertEqual(len([label for label in labels if label.endswith("-diagnostic")]), 2)
        self.assertFalse(any("bootstrap-3" in label for label in labels))
        budgets = {label: timeout for _, label, timeout in commands.calls}
        for attempt in (1, 2):
            prefix = f"simulator-bootstrap-{attempt}"
            self.assertEqual(budgets[prefix + "-open"], 30)
            self.assertEqual(budgets[prefix + "-boot-ready"], 300)
            self.assertEqual(budgets[prefix + "-settings"], 150)
            self.assertEqual(budgets[prefix + "-diagnostic"], 60)
            self.assertEqual(sum(budgets[prefix + suffix] for suffix in ("-open", "-boot-ready", "-settings")), 480)
        self.assertEqual(budgets["simulator-recovery-shutdown"], 60)
        self.assert_only_owned_device_is_mutated(commands)

    def test_failed_shutdown_is_fatal_when_exact_device_is_still_booted(self):
        shutdown = RuntimeError("could not shut down")
        commands = FakeCommands({"simulator-bootstrap-1-settings": RuntimeError("not ready"),
                                 "simulator-recovery-shutdown": shutdown}, state="Booted")
        with self.assertRaisesRegex(SimulatorSetupError, "could not be shut down") as caught:
            prepare_created_simulator(DEVICE, commands)
        self.assertIs(caught.exception.__cause__, shutdown)
        self.assertFalse(any("bootstrap-2" in label for _, label, _ in commands.calls))
        self.assert_only_owned_device_is_mutated(commands)

    def test_already_shutdown_is_accepted_only_after_exact_device_state_check(self):
        commands = FakeCommands({"simulator-bootstrap-1-open": RuntimeError("open failed"),
                                 "simulator-recovery-shutdown": RuntimeError("already shutdown")}, state="Shutdown")
        result = prepare_created_simulator(DEVICE, commands)
        self.assertEqual(result["attempts"], 2)
        self.assertEqual([label for _, label, _ in commands.calls].count("simulator-recovery-state"), 1)
        self.assert_only_owned_device_is_mutated(commands)

    def test_settings_must_return_a_positive_pid_and_missing_pid_is_not_silently_ready(self):
        for output in ("", PROBE_BUNDLE + ": 0", PROBE_BUNDLE + ": -7", "other.bundle: 123"):
            with self.subTest(output=output):
                commands = FakeCommands({"simulator-bootstrap-1-settings": output,
                                         "simulator-bootstrap-2-settings": output})
                with self.assertRaisesRegex(SimulatorSetupError, "returned no process ID"):
                    prepare_created_simulator(DEVICE, commands)
                self.assertEqual(len([label for _, label, _ in commands.calls if label.endswith("-settings")]), 2)
                self.assert_only_owned_device_is_mutated(commands)

    def test_invalid_selected_toolchain_paths_fail_before_any_device_mutation(self):
        for selected in ("simctl", "/usr/bin/simctl", "/Applications/Xcode.app/Contents/Developer/../usr/bin/simctl"):
            with self.subTest(selected=selected):
                commands = FakeCommands({"simulator-selected-tool": selected})
                with self.assertRaises(SimulatorSetupError):
                    prepare_created_simulator(DEVICE, commands)
                self.assertEqual(len(commands.calls), 1)
        commands = FakeCommands()
        with self.assertRaises(SimulatorSetupError):
            prepare_created_simulator(DEVICE, commands, developer_dir="relative/Contents/Developer")
        self.assertEqual(commands.calls, [])

    def test_diagnostic_failures_do_not_mask_the_original_exhausted_startup_error(self):
        last = RuntimeError("original second startup failure")
        commands = FakeCommands({"simulator-bootstrap-1-settings": RuntimeError("original first startup failure"),
                                 "simulator-bootstrap-2-settings": last,
                                 "simulator-bootstrap-1-diagnostic": RuntimeError("logging failed"),
                                 "simulator-bootstrap-2-diagnostic": RuntimeError("logging failed again")})
        with self.assertRaisesRegex(SimulatorSetupError, "original second startup failure") as caught:
            prepare_created_simulator(DEVICE, commands)
        self.assertIs(caught.exception.__cause__, last)
        self.assert_only_owned_device_is_mutated(commands)


if __name__ == "__main__":
    unittest.main()
