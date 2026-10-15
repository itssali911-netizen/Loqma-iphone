"""Portable checks of bounded readiness and caller-owned Simulator recovery."""
import json
from pathlib import Path
import subprocess
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "Scripts"))
from simulator_support import PROBE_BUNDLE, SimulatorSetupError, prepare_created_simulator


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
                {"udid": DEVICE, "state": self.state},
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
        self.assertEqual(result["attempts"], 1)
        self.assertFalse(result["reboot_performed"])
        self.assertEqual((result["probe_bundle"], result["probe_pid"]), (PROBE_BUNDLE, 901))
        self.assertEqual(result["selected_simulator_app"], DEVELOPER + "/Applications/Simulator.app")
        self.assertEqual(result["failures"], [])
        json.dumps(result)
        self.assert_only_owned_device_is_mutated(commands)

    def test_readiness_timeout_reboots_only_owned_device_once_and_preserves_diagnostics(self):
        timeout = subprocess.TimeoutExpired(["xcrun", "simctl", "launch", DEVICE, PROBE_BUNDLE], 90)
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
            self.assertLessEqual(sum(budgets), 420)
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
