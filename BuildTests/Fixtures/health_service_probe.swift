// Test executable only. The production AppleHealthService is compiled unchanged
// with an injected reader; no real Health store or authorization sheet is used.
import Foundation
import HealthKit

private struct ProbeFailure: Error { let check: String }

@MainActor private final class ProbeReader: AppleHealthReading {
    enum Mode { case empty, partial, complete }
    var availabilityIssue: HealthReadIssue?
    var authorizationFailure: Error?
    var readFailure: Error?
    var mode: Mode = .empty
    var holdAuthorization = false
    var holdRead = false
    private(set) var authorizationCalls = 0
    private(set) var readCalls = 0
    private var authorizationContinuation: CheckedContinuation<Void, Error>?
    private var readContinuation: CheckedContinuation<HealthReadSnapshot, Error>?
    private var readContext: (Date, Calendar)?

    func requestReadAccess() async throws {
        authorizationCalls += 1
        if holdAuthorization {
            try await withCheckedThrowingContinuation { authorizationContinuation = $0 }
        }
        if let authorizationFailure { throw authorizationFailure }
    }

    func readSnapshot(at date: Date, calendar: Calendar) async throws -> HealthReadSnapshot {
        readCalls += 1
        if holdRead {
            // Intentionally does not observe cancellation: the production
            // controller must reject a late completion rather than publishing it.
            readContext = (date, calendar)
            return try await withCheckedThrowingContinuation { readContinuation = $0 }
        }
        if let readFailure { throw readFailure }
        return try makeSnapshot(at: date, calendar: calendar)
    }

    func completeAuthorization() throws {
        guard let continuation = authorizationContinuation else { throw ProbeFailure(check: "authorization_not_pending") }
        authorizationContinuation = nil
        continuation.resume(returning: ())
    }

    func completeRead() throws {
        guard let continuation = readContinuation, let context = readContext else { throw ProbeFailure(check: "read_not_pending") }
        readContinuation = nil; readContext = nil
        continuation.resume(returning: try makeSnapshot(at: context.0, calendar: context.1))
    }

    private func makeSnapshot(at date: Date, calendar: Calendar) throws -> HealthReadSnapshot {
        guard let window = HealthDayWindow.containing(date, calendar: calendar) else { throw ProbeFailure(check: "invalid_probe_calendar") }
        let steps: HealthReadField, energy: HealthReadField, mass: HealthReadField, height: HealthReadField
        switch mode {
        case .empty:
            steps = .noData; energy = .noData; mass = .noData; height = .noData
        case .partial:
            steps = .value(HealthMeasurement(value: 0, date: date))
            energy = .noData
            mass = .value(HealthMeasurement(value: 72.25, date: date.addingTimeInterval(-86400)))
            height = .failed(.deviceLocked)
        case .complete:
            steps = .value(HealthMeasurement(value: 4760, date: date))
            energy = .value(HealthMeasurement(value: 215.5, date: date))
            mass = .value(HealthMeasurement(value: 72.25, date: date.addingTimeInterval(-86400)))
            height = .value(HealthMeasurement(value: 174, date: date.addingTimeInterval(-86400 * 30)))
        }
        return HealthReadSnapshot(windowStart: window.start, windowEnd: window.end,
                                  timeZoneIdentifier: window.timeZoneIdentifier, refreshedAt: Date(),
                                  steps: steps, activeEnergy: energy, bodyMass: mass, height: height)
    }
}

@MainActor private final class ProbeEnvironment {
    static let preferenceKey = "luqma.health.refreshOnOpen"
    let suite: String
    let preferences: UserDefaults
    let reader = ProbeReader()
    init() throws {
        let suite = "app.luqma.health-controller-probe." + UUID().uuidString
        guard let preferences = UserDefaults(suiteName: suite) else { throw ProbeFailure(check: "isolated_preferences_unavailable") }
        self.suite = suite
        self.preferences = preferences
        preferences.removePersistentDomain(forName: suite)
    }
    func clean() { preferences.removePersistentDomain(forName: suite) }
    func service() -> AppleHealthService { AppleHealthService(reader: reader, preferences: preferences) }
    func enableRefreshPreference() { preferences.set(true, forKey: Self.preferenceKey) }
}

@main struct HealthServiceProbe {
    @MainActor static func require(_ condition: Bool, _ check: String) throws {
        guard condition else { throw ProbeFailure(check: check) }
    }

    @MainActor static func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw ProbeFailure(check: "operation_did_not_reach_expected_boundary")
    }

    @MainActor static func emptyCompletion() async throws {
        let environment = try ProbeEnvironment(); defer { environment.clean() }
        let service = environment.service()
        await service.connect()
        try require(environment.reader.authorizationCalls == 1 && environment.reader.readCalls == 1, "completed_request_did_not_read")
        try require(service.refreshEnabled && !service.isWorking, "refresh_intent_not_recorded")
        try require(service.snapshot?.steps == .noData && service.snapshot?.activeEnergy == .noData,
                    "empty_read_was_not_unknown")
        try require(service.snapshot?.bodyMass.measurement == nil && service.snapshot?.height.measurement == nil,
                    "empty_read_invented_measurement")
        try require(service.issue == nil && service.lastAttempt != nil, "completed_request_reported_false_authorization_error")
    }

    @MainActor static func partialCompletion() async throws {
        let environment = try ProbeEnvironment(); defer { environment.clean() }
        environment.reader.mode = .partial
        let service = environment.service()
        await service.connect()
        try require(service.snapshot?.steps.measurement?.value == 0, "observed_zero_was_lost")
        try require(service.snapshot?.activeEnergy == .noData, "missing_energy_became_zero")
        try require(service.snapshot?.bodyMass.measurement != nil, "available_field_lost_after_partial_read")
        try require(service.snapshot?.height == .failed(.deviceLocked), "field_error_not_preserved")
        try require(service.issue == nil, "partial_read_became_global_failure")
    }

    @MainActor static func emptyRefreshReplaces() async throws {
        let environment = try ProbeEnvironment(); defer { environment.clean() }
        environment.reader.mode = .complete
        let service = environment.service()
        await service.connect()
        try require(service.snapshot?.steps.measurement != nil, "initial_observation_missing")
        environment.reader.mode = .empty
        await service.refresh()
        try require(environment.reader.readCalls == 2, "manual_refresh_not_queried")
        try require(service.snapshot?.steps == .noData && service.snapshot?.bodyMass == .noData,
                    "empty_refresh_retained_old_observations")
        try require(service.issue == nil, "empty_read_claimed_denial")
    }

    @MainActor static func queryFailureClears() async throws {
        let environment = try ProbeEnvironment(); defer { environment.clean() }
        environment.reader.mode = .complete
        let service = environment.service()
        await service.connect()
        environment.reader.readFailure = NSError(domain: "SyntheticHealthProbe", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "PRIVATE_ERROR_SENTINEL_MUST_NOT_BE_LOGGED"])
        await service.refresh()
        try require(service.snapshot == nil && service.issue == .queryFailed, "query_error_not_safely_mapped")
        try require(!service.isWorking && service.lastAttempt != nil, "query_error_left_stuck_operation")
    }

    @MainActor static func authorizationFailureDoesNotEnable() async throws {
        let environment = try ProbeEnvironment(); defer { environment.clean() }
        environment.reader.authorizationFailure = NSError(domain: HKErrorDomain,
                                                          code: HKError.Code.errorHealthDataRestricted.rawValue)
        let service = environment.service()
        await service.connect()
        await service.refreshIfEnabled()
        try require(!service.refreshEnabled && environment.reader.readCalls == 0, "failed_authorization_enabled_reading")
        try require(service.issue == .restricted && !service.isWorking, "authorization_error_not_safely_mapped")
        let stored = environment.preferences.persistentDomain(forName: environment.suite) ?? [:]
        try require(stored.isEmpty, "failed_authorization_persisted_connection")
    }

    @MainActor static func explicitCancellationRejectsLateData() async throws {
        let environment = try ProbeEnvironment(); defer { environment.clean() }
        environment.enableRefreshPreference(); environment.reader.holdRead = true; environment.reader.mode = .complete
        let service = environment.service()
        let operation = Task { await service.refresh() }
        try await waitUntil { environment.reader.readCalls == 1 }
        service.cancelRefresh()
        try environment.reader.completeRead()
        await operation.value
        try require(service.snapshot == nil && !service.isWorking, "cancelled_refresh_published_late_data")
        try require(service.refreshEnabled && service.issue == nil, "cancel_invented_permission_change")
    }

    @MainActor static func callerCancellationPreservesPriorObservation() async throws {
        let environment = try ProbeEnvironment(); defer { environment.clean() }
        environment.reader.mode = .complete
        let service = environment.service()
        await service.connect()
        let previous = service.snapshot
        try require(previous != nil, "initial_observation_missing")
        environment.reader.holdRead = true
        let operation = Task { await service.refresh() }
        try await waitUntil { environment.reader.readCalls == 2 }
        operation.cancel()
        try await waitUntil { !service.isRefreshing }
        try environment.reader.completeRead()
        await operation.value
        try require(service.snapshot == previous && service.issue == nil, "caller_cancellation_erased_or_replaced_observation")
        try require(service.refreshEnabled && !service.isWorking, "caller_cancellation_left_stuck_operation")
    }

    @MainActor static func disconnectRejectsLateData() async throws {
        let environment = try ProbeEnvironment(); defer { environment.clean() }
        environment.enableRefreshPreference(); environment.reader.holdRead = true; environment.reader.mode = .complete
        let service = environment.service()
        let operation = Task { await service.refresh() }
        try await waitUntil { environment.reader.readCalls == 1 }
        service.disconnect()
        try environment.reader.completeRead()
        await operation.value
        try require(service.snapshot == nil && !service.refreshEnabled && !service.isWorking,
                    "disconnect_published_late_data")
        try require(service.lastAttempt == nil && service.issue == nil, "disconnect_retained_attempt_or_error")
    }

    @MainActor static func onlyIntentPersists() async throws {
        let environment = try ProbeEnvironment(); defer { environment.clean() }
        environment.reader.mode = .complete
        let service = environment.service()
        await service.connect()
        let stored = environment.preferences.persistentDomain(forName: environment.suite) ?? [:]
        try require(Set(stored.keys) == Set([ProbeEnvironment.preferenceKey]), "health_observation_persisted_to_preferences")
        try require(stored[ProbeEnvironment.preferenceKey] as? Bool == true, "refresh_preference_not_boolean")
        let another = AppleHealthService(reader: ProbeReader(), preferences: environment.preferences)
        try require(another.refreshEnabled && another.snapshot == nil && another.issue == nil && another.lastAttempt == nil,
                    "new_service_restored_observations_or_permission_claim")
    }

    @MainActor static func unavailableDoesNotAuthorize() async throws {
        let environment = try ProbeEnvironment(); defer { environment.clean() }
        environment.reader.availabilityIssue = .unavailable
        let service = environment.service()
        await service.connect()
        try require(environment.reader.authorizationCalls == 0 && environment.reader.readCalls == 0,
                    "unavailable_health_called_native_flow")
        try require(service.issue == .unavailable && service.snapshot == nil && !service.refreshEnabled,
                    "unavailable_health_claimed_connection")
        environment.enableRefreshPreference()
        let enabled = environment.service()
        await enabled.refreshIfEnabled()
        try require(environment.reader.readCalls == 0 && enabled.issue == .unavailable && enabled.snapshot == nil,
                    "unavailable_health_refresh_invented_data")
    }

    @MainActor static func pendingAuthorizationSurvivesLifecycleChanges() async throws {
        let environment = try ProbeEnvironment(); defer { environment.clean() }
        environment.reader.holdAuthorization = true
        let service = environment.service()
        let operation = Task { await service.connect() }
        try await waitUntil { environment.reader.authorizationCalls == 1 }
        await service.calendarDidChange()
        service.disconnect()
        try require(service.isAuthorizing && environment.reader.readCalls == 0, "native_authorization_was_invalidated_by_lifecycle")
        try environment.reader.completeAuthorization()
        await operation.value
        try require(!service.isWorking && service.refreshEnabled && environment.reader.readCalls == 1,
                    "native_authorization_completion_left_stuck_operation")
        try require(service.snapshot?.steps == .noData && service.issue == nil, "completed_empty_authorization_claimed_grant_or_denial")
    }

    @MainActor static func main() async {
        var checks: [String] = []
        do {
            try await emptyCompletion(); checks.append("request_completed_empty_is_unknown")
            try await partialCompletion(); checks.append("partial_missing_and_zero")
            try await emptyRefreshReplaces(); checks.append("empty_refresh_replaces_observations")
            try await queryFailureClears(); checks.append("query_failure_clears_observations")
            try await authorizationFailureDoesNotEnable(); checks.append("authorization_failure_does_not_enable")
            try await explicitCancellationRejectsLateData(); checks.append("cancelled_refresh_rejects_late_data")
            try await callerCancellationPreservesPriorObservation(); checks.append("caller_cancellation_preserves_observation")
            try await disconnectRejectsLateData(); checks.append("disconnect_rejects_late_data")
            try await onlyIntentPersists(); checks.append("only_refresh_intent_persists")
            try await unavailableDoesNotAuthorize(); checks.append("unavailable_does_not_authorize")
            try await pendingAuthorizationSurvivesLifecycleChanges(); checks.append("authorization_survives_lifecycle_events")
            // Status identifiers only. No measurements, sample dates, raw errors,
            // UserDefaults payloads, or Health observations are logged.
            let report: [String: Any] = ["passed": true, "checks": checks]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
        } catch {
            let report: [String: Any] = ["passed": false, "failure": (error as? ProbeFailure)?.check ?? "unexpected_probe_failure"]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
                print(String(decoding: data, as: UTF8.self))
            }
            exit(1)
        }
    }
}
