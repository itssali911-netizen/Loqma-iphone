"""Native controller checks using the actual service and isolated test-only reads.

This does not claim a Health authorization sheet or real Health-data retrieval.
HealthKit/Combine must compile against the actual macOS SDK; Windows cannot run it.
Only bounded fixed check identifiers are retained from the executable, never data.
"""
import json
import platform
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "Scripts"))
from build_ios import public_environment

CHECKS = (
    "request_completed_empty_is_unknown",
    "partial_missing_and_zero",
    "empty_refresh_replaces_observations",
    "query_failure_clears_observations",
    "authorization_failure_does_not_enable",
    "cancelled_refresh_rejects_late_data",
    "caller_cancellation_preserves_observation",
    "disconnect_rejects_late_data",
    "only_refresh_intent_persists",
    "unavailable_does_not_authorize",
    "authorization_survives_lifecycle_events",
    "history_range_contract_and_intent_persistence",
    "extended_partial_and_truthful_last_success",
    "foreground_observers_and_incremental_refresh",
    "observer_burst_queues_one_followup",
    "observer_event_does_not_cancel_its_inflight_read",
    "range_change_rejects_late_history",
    "suspended_authorization_waits_for_foreground",
    "background_calendar_change_stays_suspended",
)


@unittest.skipUnless(sys.platform == "darwin", "Native HealthKit/Combine controller probe requires macOS and the Xcode macOS SDK")
class NativeHealthServiceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory(prefix="luqma-health-service-") as directory:
            folder = Path(directory)
            logs = ROOT / "BuildOutput"
            logs.mkdir(exist_ok=True)
            sdk = subprocess.run(["xcrun", "--sdk", "macosx", "--show-sdk-path"], cwd=ROOT,
                                 env=public_environment(), text=True, encoding="utf-8", errors="replace",
                                 stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60, check=True).stdout.strip()
            if not Path(sdk).is_absolute():
                raise RuntimeError("Native Health controller probe could not resolve the macOS SDK")
            architecture = "arm64" if platform.machine().lower() in ("arm64", "arm64e", "aarch64") else "x86_64"
            executable = folder / "HealthServiceProbe"
            arguments = ["xcrun", "swiftc", "-swift-version", "5", "-strict-concurrency=minimal", "-parse-as-library",
                         "-sdk", sdk, "-target", architecture + "-apple-macosx14.0",
                         "-module-cache-path", str(folder / "Modules"), "-framework", "HealthKit", "-framework", "Combine"]
            arguments += [str(path) for path in sorted((ROOT / "Luqma/Core").glob("*.swift"))]
            arguments += [str(ROOT / "Luqma/Services/AppleHealthService.swift"),
                          str(ROOT / "Luqma/Services/HealthHistoryReader.swift"),
                          str(ROOT / "BuildTests/Fixtures/health_service_probe.swift"), "-o", str(executable)]
            compiled = subprocess.run(arguments, cwd=ROOT, env=public_environment(), stdout=subprocess.PIPE,
                                      stderr=subprocess.STDOUT, timeout=240, check=False)
            (logs / "health-service-compile.log").write_bytes(compiled.stdout)
            if compiled.returncode:
                raise RuntimeError("Actual Health service failed native compilation; see health-service-compile.log")
            result = subprocess.run([str(executable)], cwd=folder, env=public_environment(), stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, timeout=45, check=False)
            # Do not retain an unexpected raw runtime stream. In particular, a
            # future accidental health/error print must not become a CI log.
            if len(result.stdout) > 16384 or b"PRIVATE_ERROR_SENTINEL" in result.stdout:
                raise RuntimeError("Native Health controller probe emitted an unsafe status envelope")
            try:
                value = json.loads(result.stdout)
            except (ValueError, UnicodeError):
                raise RuntimeError("Native Health controller probe returned no valid status envelope") from None
            if not isinstance(value, dict) or set(value) - {"passed", "checks", "failure"}:
                raise RuntimeError("Native Health controller probe returned unexpected status fields")
            if result.returncode or value.get("passed") is not True:
                # The fixture emits fixed assertion identifiers only; even those
                # are bounded and never expanded into Health samples or errors.
                failure = value.get("failure")
                if not isinstance(failure, str) or not failure.replace("_", "").isalnum() or len(failure) > 100:
                    failure = "invalid_failure_identifier"
                (logs / "health-service-probe.log").write_text(json.dumps({"passed": False, "failure": failure}) + "\n", encoding="utf-8")
                raise RuntimeError("Native Health controller probe assertion failed: " + failure)
            checks = value.get("checks")
            if not isinstance(checks, list) or set(checks) != set(CHECKS) or len(checks) != len(CHECKS):
                raise RuntimeError("Native Health controller probe did not complete every required check")
            cls.report = {"passed": True, "checks": checks}
            (logs / "health-service-probe.log").write_text(json.dumps(cls.report, sort_keys=True) + "\n", encoding="utf-8")

    def test_request_completion_with_empty_reads_remains_unknown(self):
        self.assertIn("request_completed_empty_is_unknown", self.report["checks"])

    def test_partial_reads_preserve_known_zero_and_unknown_fields(self):
        self.assertIn("partial_missing_and_zero", self.report["checks"])

    def test_empty_refresh_replaces_previously_observed_values(self):
        self.assertIn("empty_refresh_replaces_observations", self.report["checks"])

    def test_query_failure_clears_values_and_has_only_fixed_issue(self):
        self.assertIn("query_failure_clears_observations", self.report["checks"])

    def test_authorization_error_does_not_enable_automatic_reads(self):
        self.assertIn("authorization_failure_does_not_enable", self.report["checks"])

    def test_cancelled_refresh_rejects_late_completion(self):
        self.assertIn("cancelled_refresh_rejects_late_data", self.report["checks"])

    def test_caller_cancellation_preserves_prior_observation(self):
        self.assertIn("caller_cancellation_preserves_observation", self.report["checks"])

    def test_disconnect_rejects_late_completion(self):
        self.assertIn("disconnect_rejects_late_data", self.report["checks"])

    def test_only_refresh_intent_is_persisted_and_new_service_has_no_snapshot(self):
        self.assertIn("only_refresh_intent_persists", self.report["checks"])

    def test_unavailable_health_never_starts_native_authorization(self):
        self.assertIn("unavailable_does_not_authorize", self.report["checks"])

    def test_native_authorization_survives_calendar_and_disconnect_events(self):
        self.assertIn("authorization_survives_lifecycle_events", self.report["checks"])

    def test_history_range_forwarding_and_only_intent_persistence(self):
        self.assertIn("history_range_contract_and_intent_persistence", self.report["checks"])

    def test_extended_readings_and_last_success_are_truthful(self):
        self.assertIn("extended_partial_and_truthful_last_success", self.report["checks"])

    def test_observers_stop_in_background_and_refresh_incrementally(self):
        self.assertIn("foreground_observers_and_incremental_refresh", self.report["checks"])

    def test_observer_bursts_queue_only_one_followup(self):
        self.assertIn("observer_burst_queues_one_followup", self.report["checks"])

    def test_range_change_rejects_late_old_data(self):
        self.assertIn("range_change_rejects_late_history", self.report["checks"])

    def test_observer_notification_does_not_cancel_its_existing_read(self):
        self.assertIn("observer_event_does_not_cancel_its_inflight_read", self.report["checks"])

    def test_suspended_authorization_waits_for_foreground(self):
        self.assertIn("suspended_authorization_waits_for_foreground", self.report["checks"])

    def test_background_calendar_event_does_not_reactivate_queries(self):
        self.assertIn("background_calendar_change_stays_suspended", self.report["checks"])
