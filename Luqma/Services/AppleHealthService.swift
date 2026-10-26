import Foundation
import Combine
import HealthKit

@MainActor protocol AppleHealthReading {
    var availabilityIssue: HealthReadIssue? { get }
    func requestReadAccess() async throws
    func readSnapshot(at date: Date, calendar: Calendar) async throws -> HealthReadSnapshot
}

private struct AppleHealthFailure: Error { let issue: HealthReadIssue }

/// Native HealthKit only. No web bridge, third-party service, writes, or observers.
@MainActor final class HealthKitReader: AppleHealthReading {
    private let store = HKHealthStore()
    private let profileIssue: HealthReadIssue?
    private let identifiers: [HKQuantityTypeIdentifier] = [.stepCount, .bodyMass, .height, .activeEnergyBurned]

    init() {
        // A missing embedded profile is normal for some installation methods.
        // Unknown is not proof of a missing entitlement; the OS remains authoritative.
        if let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
           let data = try? Data(contentsOf: url, options: .mappedIfSafe),
           HealthSigning.profileSupportsHealth(data) == false {
            profileIssue = .missingEntitlement
        } else { profileIssue = nil }
    }
    var availabilityIssue: HealthReadIssue? {
        HKHealthStore.isHealthDataAvailable() ? profileIssue : .unavailable
    }
    func requestReadAccess() async throws {
        if let issue = availabilityIssue { throw AppleHealthFailure(issue: issue) }
        let types = Set<HKObjectType>(identifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) })
        guard types.count == 4 else { throw AppleHealthFailure(issue: .unavailable) }
        // Completion means the request was processed, never that reads were granted.
        // The native sheet lets the person choose each type. No Apple ID is requested.
        try await store.requestAuthorization(toShare: [], read: types)
        try Task.checkCancellation()
    }
    func readSnapshot(at date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) async throws -> HealthReadSnapshot {
        if let issue = availabilityIssue { throw AppleHealthFailure(issue: issue) }
        guard let window = HealthDayWindow.containing(date, calendar: calendar) else {
            throw AppleHealthFailure(issue: .queryFailed)
        }
        try Task.checkCancellation()
        async let steps = dailyTotal(.stepCount, unit: .count(), window: window, cutoff: date, calendar: calendar)
        async let energy = dailyTotal(.activeEnergyBurned, unit: .kilocalorie(), window: window, cutoff: date, calendar: calendar)
        async let mass = latest(.bodyMass, unit: .gramUnit(with: .kilo), cutoff: date)
        async let height = latest(.height, unit: .meterUnit(with: .centi), cutoff: date)
        let fields = await (steps, energy, mass, height)
        try Task.checkCancellation()
        return HealthReadSnapshot(windowStart: window.start, windowEnd: window.end,
                                  timeZoneIdentifier: window.timeZoneIdentifier, refreshedAt: Date(),
                                  steps: fields.0, activeEnergy: fields.1, bodyMass: fields.2, height: fields.3).sanitized()
    }
    private func dailyTotal(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit,
                            window: HealthDayWindow, cutoff: Date, calendar: Calendar) async -> HealthReadField {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return .failed(.unavailable) }
        // Include samples crossing midnight, but exclude future-ending samples.
        // HealthKit's calendar bucket apportions the matching cumulative data.
        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: cutoff, options: .strictEndDate)
        var interval = DateComponents(day: 1)
        interval.calendar = calendar; interval.timeZone = calendar.timeZone
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate), options: .cumulativeSum,
            anchorDate: window.start, intervalComponents: interval)
        do {
            let collection = try await descriptor.result(for: store)
            try Task.checkCancellation()
            // The default merged statistics resolve overlapping sources. Never
            // add iPhone/Watch/source subtotals, raw samples, or workout calories.
            guard let quantity = collection.statistics(for: window.start)?.sumQuantity() else { return .noData }
            return .value(HealthMeasurement(value: quantity.doubleValue(for: unit), date: cutoff))
        } catch { return Self.fieldFailure(error) }
    }
    private func latest(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, cutoff: Date) async -> HealthReadField {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return .failed(.unavailable) }
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: cutoff, options: .strictEndDate)
        let descriptor = HKSampleQueryDescriptor(predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\HKQuantitySample.endDate, order: .reverse),
                              SortDescriptor(\HKQuantitySample.startDate, order: .reverse)], limit: 1)
        do {
            let samples = try await descriptor.result(for: store)
            try Task.checkCancellation()
            guard let sample = samples.first else { return .noData }
            return .value(HealthMeasurement(value: sample.quantity.doubleValue(for: unit), date: sample.endDate))
        } catch { return Self.fieldFailure(error) }
    }
    private static func fieldFailure(_ error: Error) -> HealthReadField {
        let native = error as NSError
        if native.domain == HKErrorDomain, native.code == HKError.Code.errorNoData.rawValue { return .noData }
        return .failed(issue(for: error))
    }
    static func issue(for error: Error) -> HealthReadIssue {
        if let failure = error as? AppleHealthFailure { return failure.issue }
        if error is CancellationError { return .cancelled }
        let native = error as NSError
        guard native.domain == HKErrorDomain else { return .queryFailed }
        switch HKError.Code(rawValue: native.code) {
        case .errorHealthDataUnavailable: return .unavailable
        case .errorHealthDataRestricted, .errorAuthorizationDenied, .errorAuthorizationNotDetermined: return .restricted
        case .errorDatabaseInaccessible: return .deviceLocked
        default: return .queryFailed
        }
    }
}

/// Observations stay in memory only: never in DiarySnapshot, exports, UserDefaults,
/// logs, analytics, AI requests, or crash breadcrumbs. Only refresh intent persists.
@MainActor final class AppleHealthService: ObservableObject {
    @Published private(set) var snapshot: HealthReadSnapshot?
    @Published private(set) var issue: HealthReadIssue?
    @Published private(set) var refreshEnabled: Bool
    @Published private(set) var isAuthorizing = false
    @Published private(set) var isRefreshing = false
    @Published private(set) var referenceDate = Date()
    @Published private(set) var lastAttempt: Date?
    private let reader: any AppleHealthReading
    private let preferences: UserDefaults
    private static let preferenceKey = "luqma.health.refreshOnOpen"
    private var refreshTask: Task<Void, Never>?
    private var generation = UUID()
    var isWorking: Bool { isAuthorizing || isRefreshing }
    var availabilityIssue: HealthReadIssue? { reader.availabilityIssue }

    init(reader: (any AppleHealthReading)? = nil, preferences: UserDefaults = .standard) {
        self.reader = reader ?? HealthKitReader(); self.preferences = preferences
        refreshEnabled = preferences.bool(forKey: Self.preferenceKey)
    }
    func connect() async {
        guard !isWorking else { return }
        if let unavailable = availabilityIssue { issue = unavailable; return }
        let token = UUID(); generation = token; isAuthorizing = true; issue = nil
        defer { if generation == token { isAuthorizing = false } }
        do {
            try await reader.requestReadAccess()
            guard !Task.isCancelled, generation == token else { return }
            // This is the person's refresh preference, NOT an authorization status.
            refreshEnabled = true; preferences.set(true, forKey: Self.preferenceKey)
            isAuthorizing = false
            await refresh()
        } catch {
            guard generation == token else { return }
            let failure = HealthKitReader.issue(for: error)
            if failure != .cancelled { issue = failure }
        }
    }
    func refreshIfEnabled() async {
        referenceDate = Date()
        guard refreshEnabled else { return }
        await refresh()
    }
    func refresh() async {
        referenceDate = Date()
        guard refreshEnabled, !isWorking else { return }
        if let unavailable = availabilityIssue { issue = unavailable; snapshot = nil; return }
        let token = UUID(); generation = token; isRefreshing = true; issue = nil
        lastAttempt = Date()
        let provider = reader
        let task = Task { [weak self] in
            do {
                let value = try await provider.readSnapshot(at: Date(), calendar: .autoupdatingCurrent)
                try Task.checkCancellation()
                guard let self, generation == token, refreshEnabled else { return }
                // Empty or partially failed reads replace the prior observations.
                // Revocation cannot silently leave a previously seen value current.
                snapshot = value.sanitized(); referenceDate = Date(); issue = nil
            } catch {
                guard let self, generation == token else { return }
                let failure = HealthKitReader.issue(for: error)
                referenceDate = Date()
                if failure != .cancelled { snapshot = nil; issue = failure }
            }
            guard let self, generation == token else { return }
            isRefreshing = false
        }
        refreshTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
            Task { @MainActor [weak self] in
                guard let self, generation == token else { return }
                cancelRefresh()
            }
        }
        if generation == token { refreshTask = nil }
    }
    func cancelRefresh() {
        // Calendar/background events cannot cancel a native authorization sheet.
        // Leave its generation intact so its eventual completion clears busy state.
        guard !isAuthorizing else { referenceDate = Date(); return }
        generation = UUID(); refreshTask?.cancel(); refreshTask = nil; isRefreshing = false; referenceDate = Date()
    }
    func calendarDidChange() async {
        cancelRefresh()
        await refreshIfEnabled()
    }
    func suspend() { if !isAuthorizing { cancelRefresh() } }
    func disconnect() {
        guard !isAuthorizing else { return }
        cancelRefresh(); refreshEnabled = false; preferences.set(false, forKey: Self.preferenceKey)
        snapshot = nil; issue = nil; lastAttempt = nil
        // Local disconnect cannot revoke system permissions. The UI explains Health settings.
    }
}
