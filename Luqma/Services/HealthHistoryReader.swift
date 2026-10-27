import Foundation
import HealthKit

/// Volatile HealthKit query state. Neither samples nor anchors are persisted.
/// A complete reread on foreground/manual refresh also reconciles read revocation,
/// which HealthKit deliberately does not expose as an authorization status.
@MainActor final class HealthHistoryState {
    fileprivate var window: HealthHistoryCacheWindow?
    fileprivate var generation = UUID()
    fileprivate var weightAnchor: HKQueryAnchor?
    fileprivate var workoutAnchor: HKQueryAnchor?
    fileprivate var sleepAnchor: HKQueryAnchor?
    fileprivate var weights = HealthSampleDeltaStore<HealthWeightRecord>()
    fileprivate var workouts = HealthSampleDeltaStore<HealthWorkoutRecord>()
    fileprivate var sleep = HealthSampleDeltaStore<HealthSleepInterval>()
    fileprivate var observers: [HKObserverQuery] = []
    fileprivate var observerGeneration = UUID()
    fileprivate var pendingObserverChange: Task<Void, Never>?
}

fileprivate struct HealthHistoryCacheWindow: Equatable {
    let start: Date
    let end: Date
    let timeZoneIdentifier: String
    let days: Int
}

extension HealthKitReader {
    func readDetails(at date: Date, calendar: Calendar, days: Int,
                     forceFull: Bool) async throws -> HealthReadDetails {
        if let issue = availabilityIssue { throw AppleHealthFailure(issue: issue) }
        guard let range = HealthHistoryRange(rawValue: days) else {
            throw AppleHealthFailure(issue: .queryFailed)
        }
        let windows = range.dayWindows(ending: date, calendar: calendar)
        guard let first = windows.first, let last = windows.last else {
            throw AppleHealthFailure(issue: .queryFailed)
        }
        let identity = HealthHistoryCacheWindow(start: first.start, end: last.end,
            timeZoneIdentifier: calendar.timeZone.identifier, days: days)
        if forceFull || historyState.window != identity { resetHistoryCache() }
        historyState.window = identity
        let generation = historyState.generation
        try Task.checkCancellation()

        // HealthKit merges cumulative statistics. Never sum source subtotals,
        // raw Watch/iPhone samples, or workout energy into these daily values.
        async let stepSeries = historyTotals(.stepCount, unit: .count(), windows: windows, cutoff: date, calendar: calendar)
        async let energySeries = historyTotals(.activeEnergyBurned, unit: .kilocalorie(), windows: windows, cutoff: date, calendar: calendar)
        async let distanceSeries = historyTotals(.distanceWalkingRunning, unit: .meter(), windows: windows, cutoff: date, calendar: calendar)
        async let basalSeries = historyTotals(.basalEnergyBurned, unit: .kilocalorie(), windows: windows, cutoff: date, calendar: calendar)
        async let fat = latest(.bodyFatPercentage, unit: .percent(), cutoff: date)
        async let heart = latest(.heartRate, unit: HKUnit.count().unitDivided(by: .minute()), cutoff: date)
        async let weights = historyWeights(in: identity, generation: generation)
        async let workouts = historyWorkouts(in: identity, generation: generation)
        async let sleep = historySleep(in: identity, generation: generation)
        let readings = await (stepSeries, energySeries, distanceSeries, basalSeries, fat, heart, weights, workouts, sleep)
        try Task.checkCancellation()
        guard historyState.generation == generation else { throw CancellationError() }

        let daily = windows.indices.map { index in
            let components = calendar.dateComponents([.year, .month, .day], from: windows[index].start)
            let dayID = String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
            return HealthDailyActivity(idDate: dayID, date: windows[index].start,
                steps: readings.0.fields[index], activeEnergy: readings.1.fields[index],
                walkingDistance: readings.2.fields[index], basalEnergy: readings.3.fields[index])
        }
        // HKUnit.percent() is a fraction in 0...1, while the app displays 0...100.
        let percentage: HealthReadField
        if let measurement = readings.4.measurement {
            percentage = .value(HealthMeasurement(value: measurement.value * 100, date: measurement.date))
        } else { percentage = readings.4 }
        return HealthReadDetails(walkingDistance: readings.2.fields.last ?? .noData,
            basalEnergy: readings.3.fields.last ?? .noData, bodyFatPercentage: percentage,
            heartRate: readings.5, daily: daily, weights: readings.6.records,
            workouts: readings.7.records, sleep: readings.8.records, historyRangeDays: days,
            dailyIssue: [readings.0.issue, readings.1.issue, readings.2.issue, readings.3.issue].compactMap { $0 }.first,
            weightsIssue: readings.6.issue, workoutsIssue: readings.7.issue, sleepIssue: readings.8.issue)
            .sanitized(now: date, calendar: calendar)
    }

    func resetHistoryCache() {
        historyState.generation = UUID()
        historyState.window = nil
        historyState.weightAnchor = nil; historyState.workoutAnchor = nil; historyState.sleepAnchor = nil
        historyState.weights.reset(); historyState.workouts.reset(); historyState.sleep.reset()
    }

    /// Foreground notifications only. No background delivery is enabled here.
    /// Native notifications are coalesced so a Watch sync cannot stack refreshes.
    func startForegroundObservation(onChange: @escaping @MainActor () -> Void) {
        guard historyState.observers.isEmpty, availabilityIssue == nil else { return }
        let state = historyState
        let token = UUID(); state.observerGeneration = token
        let quantities: [HKQuantityTypeIdentifier] = [.stepCount, .activeEnergyBurned, .distanceWalkingRunning,
            .basalEnergyBurned, .bodyMass, .height, .bodyFatPercentage, .heartRate]
        var types: [HKSampleType] = quantities.compactMap { HKObjectType.quantityType(forIdentifier: $0) }
        types.append(HKObjectType.workoutType())
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.append(sleep) }
        state.observers = types.map { type in
            HKObserverQuery(sampleType: type, predicate: nil) { [weak state] _, completion, _ in
                // The notification contains no readings. Acknowledge receipt;
                // the foreground refresh performs the actual, fallible queries.
                completion()
                Task { @MainActor in
                    guard let state, state.observerGeneration == token else { return }
                    state.pendingObserverChange?.cancel()
                    state.pendingObserverChange = Task { @MainActor in
                        do { try await Task.sleep(for: .milliseconds(350)) }
                        catch { return }
                        guard !Task.isCancelled, state.observerGeneration == token else { return }
                        onChange()
                        state.pendingObserverChange = nil
                    }
                }
            }
        }
        for query in state.observers { store.execute(query) }
    }

    func stopForegroundObservation() {
        historyState.observerGeneration = UUID()
        historyState.pendingObserverChange?.cancel(); historyState.pendingObserverChange = nil
        for query in historyState.observers { store.stop(query) }
        historyState.observers.removeAll()
    }

    private func historyTotals(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit,
                               windows: [HealthDayWindow], cutoff: Date, calendar: Calendar) async -> HealthDailyQueryResult {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier), let first = windows.first else {
            return HealthDailyQueryResult(fields: windows.map { _ in .failed(.unavailable) }, issue: .unavailable)
        }
        // Include samples overlapping midnight and exclude future-ending samples.
        let predicate = HKQuery.predicateForSamples(withStart: first.start, end: cutoff, options: .strictEndDate)
        var interval = DateComponents(day: 1)
        interval.calendar = calendar; interval.timeZone = calendar.timeZone
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate), options: .cumulativeSum,
            anchorDate: first.start, intervalComponents: interval)
        do {
            let collection = try await descriptor.result(for: store)
            try Task.checkCancellation()
            let fields: [HealthReadField] = windows.map { window in
                guard let quantity = collection.statistics(for: window.start)?.sumQuantity() else { return .noData }
                let observedAt = min(cutoff, window.end.addingTimeInterval(-0.001))
                return .value(HealthMeasurement(value: quantity.doubleValue(for: unit), date: observedAt))
            }
            return HealthDailyQueryResult(fields: fields, issue: nil)
        } catch {
            let failure = Self.fieldFailure(error)
            if failure == .noData { return HealthDailyQueryResult(fields: windows.map { _ in .noData }, issue: nil) }
            return HealthDailyQueryResult(fields: windows.map { _ in failure }, issue: Self.issue(for: error))
        }
    }

    private func historyWeights(in window: HealthHistoryCacheWindow, generation: UUID) async -> HealthRecordsQueryResult<HealthWeightRecord> {
        guard let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return .failure(.unavailable) }
        do {
            let result = try await anchoredHistory(predicate: .quantitySample(type: type, predicate: historyPredicate(window)),
                anchor: historyState.weightAnchor, cache: historyState.weights) { sample in
                HealthWeightRecord(id: sample.uuid, date: sample.endDate,
                                   kg: sample.quantity.doubleValue(for: .gramUnit(with: .kilo)))
            }
            try Task.checkCancellation()
            guard historyState.generation == generation else { throw CancellationError() }
            historyState.weightAnchor = result.anchor; historyState.weights = result.cache
            return HealthRecordsQueryResult(records: result.cache.records.sorted { $0.date < $1.date }, issue: nil)
        } catch {
            if historyState.generation == generation { historyState.weightAnchor = nil; historyState.weights.reset() }
            return .failure(issue: Self.issue(for: error), field: Self.fieldFailure(error))
        }
    }

    private func historyWorkouts(in window: HealthHistoryCacheWindow, generation: UUID) async -> HealthRecordsQueryResult<HealthWorkoutRecord> {
        do {
            let result = try await anchoredHistory(predicate: .workout(historyPredicate(window)),
                anchor: historyState.workoutAnchor, cache: historyState.workouts) { sample in
                let kind: HealthWorkoutKind
                switch sample.workoutActivityType {
                case .walking: kind = .walking
                case .running: kind = .running
                case .cycling: kind = .cycling
                case .swimming: kind = .swimming
                case .traditionalStrengthTraining, .functionalStrengthTraining: kind = .strength
                case .yoga: kind = .yoga
                default: kind = .other
                }
                // Workout energy is deliberately absent: it overlaps daily active energy.
                return HealthWorkoutRecord(id: sample.uuid, start: sample.startDate, end: sample.endDate,
                                           kind: kind, durationSeconds: sample.duration)
            }
            try Task.checkCancellation()
            guard historyState.generation == generation else { throw CancellationError() }
            historyState.workoutAnchor = result.anchor; historyState.workouts = result.cache
            return HealthRecordsQueryResult(records: result.cache.records.sorted { $0.start < $1.start }, issue: nil)
        } catch {
            if historyState.generation == generation { historyState.workoutAnchor = nil; historyState.workouts.reset() }
            return .failure(issue: Self.issue(for: error), field: Self.fieldFailure(error))
        }
    }

    private func historySleep(in window: HealthHistoryCacheWindow, generation: UUID) async -> HealthRecordsQueryResult<HealthSleepInterval> {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return .failure(.unavailable) }
        do {
            let result = try await anchoredHistory(predicate: .categorySample(type: type, predicate: historyPredicate(window)),
                anchor: historyState.sleepAnchor, cache: historyState.sleep) { sample in
                switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
                case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
                    return HealthSleepInterval(id: sample.uuid, start: sample.startDate, end: sample.endDate)
                default: return nil // Awake/in-bed intervals are not sleep duration.
                }
            }
            try Task.checkCancellation()
            guard historyState.generation == generation else { throw CancellationError() }
            historyState.sleepAnchor = result.anchor; historyState.sleep = result.cache
            // The presentation model unions overlaps before displaying sleep totals.
            return HealthRecordsQueryResult(records: result.cache.records.sorted { $0.start < $1.start }, issue: nil)
        } catch {
            if historyState.generation == generation { historyState.sleepAnchor = nil; historyState.sleep.reset() }
            return .failure(issue: Self.issue(for: error), field: Self.fieldFailure(error))
        }
    }

    private func historyPredicate(_ window: HealthHistoryCacheWindow) -> NSPredicate {
        // Keep this predicate stable until its day/range/time-zone identity changes.
        // Moving its upper bound on each incremental query could skip an object
        // whose date becomes eligible after an anchor has already passed it.
        HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: [])
    }

    private func anchoredHistory<Sample: HKSample, Record: Identifiable & Sendable>(
        predicate: HKSamplePredicate<Sample>, anchor: HKQueryAnchor?, cache: HealthSampleDeltaStore<Record>,
        transform: (Sample) -> Record?) async throws -> (anchor: HKQueryAnchor, cache: HealthSampleDeltaStore<Record>) where Record.ID == UUID {
        let batchSize = 500
        var nextAnchor = anchor
        var updated = cache
        while true {
            try Task.checkCancellation()
            let descriptor = HKAnchoredObjectQueryDescriptor(predicates: [predicate], anchor: nextAnchor, limit: batchSize)
            let result = try await descriptor.result(for: store)
            try Task.checkCancellation()
            updated.apply(upserts: result.addedSamples.compactMap(transform), deletedIDs: result.deletedObjects.map(\.uuid))
            nextAnchor = result.newAnchor
            if result.addedSamples.count + result.deletedObjects.count < batchSize {
                return (result.newAnchor, updated)
            }
        }
    }
}

private struct HealthDailyQueryResult: Sendable {
    var fields: [HealthReadField]
    var issue: HealthReadIssue?
}

private struct HealthRecordsQueryResult<Record: Sendable>: Sendable {
    var records: [Record]
    var issue: HealthReadIssue?
    static func failure(_ issue: HealthReadIssue) -> Self { Self(records: [], issue: issue) }
    static func failure(issue: HealthReadIssue, field: HealthReadField) -> Self {
        Self(records: [], issue: field == .noData ? nil : issue)
    }
}
