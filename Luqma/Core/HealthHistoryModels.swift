import Foundation

/// Bounded, calendar-day query ranges, including the selected/current day.
enum HealthHistoryRange: Int, CaseIterable, Codable, Equatable, Sendable {
    case week = 7, month = 30, quarter = 90
    var days: Int { rawValue }

    /// Oldest first. Calendar arithmetic preserves 23/25-hour DST days.
    func dayWindows(ending date: Date, calendar: Calendar = .current) -> [HealthDayWindow] {
        guard let last = HealthDayWindow.containing(date, calendar: calendar) else { return [] }
        var windows: [HealthDayWindow] = []
        windows.reserveCapacity(days)
        for offset in (0..<days).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: last.start),
                  let window = HealthDayWindow.containing(day, calendar: calendar) else { return [] }
            windows.append(window)
        }
        return windows
    }
}

/// Units: steps=count, energy=kcal, walking distance=metres. The containing day,
/// not a formatted device-language number, supplies the stable chart identity.
struct HealthDailyActivity: Identifiable, Codable, Equatable, Sendable {
    var idDate: String
    var date: Date
    var steps: HealthReadField = .noData
    var activeEnergy: HealthReadField = .noData
    var walkingDistance: HealthReadField = .noData
    var basalEnergy: HealthReadField = .noData
    var id: String { idDate }
    private enum CodingKeys: String, CodingKey { case idDate, date, steps, activeEnergy, walkingDistance, basalEnergy }

    func sanitized(now: Date = Date(), calendar: Calendar = .current) -> Self? {
        guard !idDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              healthFinite(now), healthFinite(date), date <= now,
              let day = HealthDayWindow.containing(date, calendar: calendar) else { return nil }
        var result = self
        result.steps = dailyField(steps, day: day, now: now)
        result.activeEnergy = dailyField(activeEnergy, day: day, now: now)
        result.walkingDistance = dailyField(walkingDistance, day: day, now: now)
        result.basalEnergy = dailyField(basalEnergy, day: day, now: now)
        return result
    }

    private func dailyField(_ field: HealthReadField, day: HealthDayWindow, now: Date) -> HealthReadField {
        let value = field.sanitized(allowZero: true, now: now)
        guard let measurement = value.measurement else { return value }
        return day.contains(measurement.date) ? value : .failed(.queryFailed)
    }
}
extension HealthDailyActivity {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(idDate: try values.decode(String.self, forKey: .idDate),
                  date: try values.decode(Date.self, forKey: .date),
                  steps: try values.decodeIfPresent(HealthReadField.self, forKey: .steps) ?? .noData,
                  activeEnergy: try values.decodeIfPresent(HealthReadField.self, forKey: .activeEnergy) ?? .noData,
                  walkingDistance: try values.decodeIfPresent(HealthReadField.self, forKey: .walkingDistance) ?? .noData,
                  basalEnergy: try values.decodeIfPresent(HealthReadField.self, forKey: .basalEnergy) ?? .noData)
    }
}

enum HealthWorkoutKind: String, Codable, Equatable, Sendable {
    case walking, running, cycling, swimming, strength, yoga, other

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = Self(rawValue: raw) ?? .other
    }
}

/// Workout duration is observational only. No workout energy is summed into
/// HealthKit's already merged daily active energy or Luqma's calorie targets.
struct HealthWorkoutRecord: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var start: Date
    var end: Date
    var kind: HealthWorkoutKind
    var durationSeconds: Double

    func sanitized(now: Date = Date()) -> Self? {
        guard healthFinite(now), healthFinite(start), healthFinite(end),
              start < end, end <= now, durationSeconds.isFinite, durationSeconds >= 0,
              durationSeconds <= end.timeIntervalSince(start) + 1 else { return nil }
        return self
    }
}

struct HealthWeightRecord: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var date: Date
    var kg: Double

    func sanitized(now: Date = Date()) -> Self? {
        guard healthFinite(now), healthFinite(date), date <= now,
              kg.isFinite, kg > 0 else { return nil }
        return self
    }
}

/// Only samples classified as asleep belong here. The native adapter must omit
/// awake and in-bed stages. UUIDs preserve anchored-query deletions and updates.
struct HealthSleepInterval: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var start: Date
    var end: Date

    func sanitized(now: Date = Date()) -> Self? {
        guard healthFinite(now), healthFinite(start), healthFinite(end),
              start < end, end <= now else { return nil }
        return self
    }
}

/// Overlap union across devices/sources/stages. Half-open intervals are clipped
/// to the actual local day and now; elapsed seconds never assume a 24-hour day.
enum HealthSleepUnion {
    static func availableDuration(_ intervals: [HealthSleepInterval], on date: Date,
                                  calendar: Calendar = .current, now: Date = Date()) -> TimeInterval? {
        guard healthFinite(now), let day = HealthDayWindow.containing(date, calendar: calendar) else { return nil }
        let upper = min(day.end, now)
        guard upper > day.start else { return nil }
        let clipped: [(Date, Date)] = intervals.compactMap { interval in
            guard healthFinite(interval.start), healthFinite(interval.end), interval.start < interval.end else { return nil }
            let start = max(interval.start, day.start), end = min(interval.end, upper)
            return start < end ? (start, end) : nil
        }.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
        guard let first = clipped.first else { return nil }
        var start = first.0, end = first.1, seconds: TimeInterval = 0
        for next in clipped.dropFirst() {
            if next.0 <= end { end = max(end, next.1) }
            else { seconds += end.timeIntervalSince(start); start = next.0; end = next.1 }
        }
        return seconds + end.timeIntervalSince(start)
    }

    /// Mathematical convenience only: empty input is not proof of zero sleep.
    /// Product readouts should use availableDuration and render nil as unknown.
    static func duration(_ intervals: [HealthSleepInterval], on date: Date,
                         calendar: Calendar = .current, now: Date = Date()) -> TimeInterval {
        availableDuration(intervals, on: date, calendar: calendar, now: now) ?? 0
    }
}

/// Extended observations remain separate from diary/manual entries and targets.
/// Empty arrays alone reveal neither permission denial nor successful access.
struct HealthReadDetails: Codable, Equatable, Sendable {
    var walkingDistance: HealthReadField = .noData // metres
    var basalEnergy: HealthReadField = .noData // kcal
    var bodyFatPercentage: HealthReadField = .noData // percent, not fraction
    var heartRate: HealthReadField = .noData // beats/minute
    var daily: [HealthDailyActivity] = []
    var weights: [HealthWeightRecord] = []
    var workouts: [HealthWorkoutRecord] = []
    var sleep: [HealthSleepInterval] = []
    var historyRangeDays: Int = 30
    var dailyIssue: HealthReadIssue?
    var weightsIssue: HealthReadIssue?
    var workoutsIssue: HealthReadIssue?
    var sleepIssue: HealthReadIssue?
    static let empty = HealthReadDetails()

    init(walkingDistance: HealthReadField = .noData, basalEnergy: HealthReadField = .noData,
         bodyFatPercentage: HealthReadField = .noData, heartRate: HealthReadField = .noData,
         daily: [HealthDailyActivity] = [], weights: [HealthWeightRecord] = [],
         workouts: [HealthWorkoutRecord] = [], sleep: [HealthSleepInterval] = [],
         historyRangeDays: Int = 30, dailyIssue: HealthReadIssue? = nil,
         weightsIssue: HealthReadIssue? = nil, workoutsIssue: HealthReadIssue? = nil,
         sleepIssue: HealthReadIssue? = nil) {
        self.walkingDistance = walkingDistance; self.basalEnergy = basalEnergy
        self.bodyFatPercentage = bodyFatPercentage; self.heartRate = heartRate
        self.daily = daily; self.weights = weights; self.workouts = workouts; self.sleep = sleep
        self.historyRangeDays = HealthHistoryRange(rawValue: historyRangeDays)?.rawValue ?? 30
        self.dailyIssue = dailyIssue; self.weightsIssue = weightsIssue
        self.workoutsIssue = workoutsIssue; self.sleepIssue = sleepIssue
    }

    func sanitized(now: Date = Date(), calendar: Calendar = .current) -> Self {
        var result = self
        let range = HealthHistoryRange(rawValue: historyRangeDays) ?? .month
        result.historyRangeDays = range.rawValue
        result.walkingDistance = walkingDistance.sanitized(allowZero: true, now: now)
        result.basalEnergy = basalEnergy.sanitized(allowZero: true, now: now)
        result.bodyFatPercentage = Self.percentage(bodyFatPercentage, now: now)
        result.heartRate = heartRate.sanitized(allowZero: false, now: now)
        guard let lower = range.dayWindows(ending: now, calendar: calendar).first?.start else {
            result.daily = []; result.weights = []; result.workouts = []; result.sleep = []
            return result
        }
        // UUID/key upserts remove duplicate anchored batches without adding
        // their values together. The latest supplied version replaces the old.
        var days: [String: HealthDailyActivity] = [:]
        for record in daily {
            guard let clean = record.sanitized(now: now, calendar: calendar), clean.date >= lower else { continue }
            days[clean.idDate] = clean
        }
        result.daily = days.values.sorted { $0.date == $1.date ? $0.idDate < $1.idDate : $0.date < $1.date }
        var weightIDs: [UUID: HealthWeightRecord] = [:]
        for record in weights { if let clean = record.sanitized(now: now), clean.date >= lower { weightIDs[clean.id] = clean } }
        result.weights = weightIDs.values.sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date }
        var workoutIDs: [UUID: HealthWorkoutRecord] = [:]
        for record in workouts { if let clean = record.sanitized(now: now), clean.end > lower { workoutIDs[clean.id] = clean } }
        result.workouts = workoutIDs.values.sorted { $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start < $1.start }
        var sleepIDs: [UUID: HealthSleepInterval] = [:]
        for record in sleep { if let clean = record.sanitized(now: now), clean.end > lower { sleepIDs[clean.id] = clean } }
        result.sleep = sleepIDs.values.sorted { $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start < $1.start }
        return result
    }

    /// Existence of observations, never an assertion that all reads were granted.
    var hasReadableData: Bool {
        let now = Date()
        if walkingDistance.sanitized(allowZero: true, now: now).measurement != nil ||
           basalEnergy.sanitized(allowZero: true, now: now).measurement != nil ||
           Self.percentage(bodyFatPercentage, now: now).measurement != nil ||
           heartRate.sanitized(allowZero: false, now: now).measurement != nil { return true }
        if daily.contains(where: { record in
            guard let clean = record.sanitized(now: now) else { return false }
            return [clean.steps, clean.activeEnergy, clean.walkingDistance, clean.basalEnergy].contains { $0.measurement != nil }
        }) { return true }
        return weights.contains { $0.sanitized(now: now) != nil } ||
            workouts.contains { $0.sanitized(now: now) != nil } || sleep.contains { $0.sanitized(now: now) != nil }
    }

    /// Stable, deduplicated outcome codes only; never Health values or permission guesses.
    var queryIssues: [HealthReadIssue] {
        var result: [HealthReadIssue] = []
        func append(_ issue: HealthReadIssue?) { if let issue, !result.contains(issue) { result.append(issue) } }
        for field in [walkingDistance, basalEnergy, bodyFatPercentage, heartRate] {
            if case let .failed(issue) = field { append(issue) }
        }
        for issue in [dailyIssue, weightsIssue, workoutsIssue, sleepIssue] { append(issue) }
        for record in daily {
            for field in [record.steps, record.activeEnergy, record.walkingDistance, record.basalEnergy] {
                if case let .failed(issue) = field { append(issue) }
            }
        }
        return result
    }

    private static func percentage(_ field: HealthReadField, now: Date) -> HealthReadField {
        let clean = field.sanitized(allowZero: true, now: now)
        if let value = clean.measurement, value.value > 100 { return .failed(.queryFailed) }
        return clean
    }

    private enum CodingKeys: String, CodingKey {
        case walkingDistance, basalEnergy, bodyFatPercentage, heartRate, daily, weights, workouts, sleep
        case historyRangeDays, dailyIssue, weightsIssue, workoutsIssue, sleepIssue
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(walkingDistance: try values.decodeIfPresent(HealthReadField.self, forKey: .walkingDistance) ?? .noData,
                  basalEnergy: try values.decodeIfPresent(HealthReadField.self, forKey: .basalEnergy) ?? .noData,
                  bodyFatPercentage: try values.decodeIfPresent(HealthReadField.self, forKey: .bodyFatPercentage) ?? .noData,
                  heartRate: try values.decodeIfPresent(HealthReadField.self, forKey: .heartRate) ?? .noData,
                  daily: try values.decodeIfPresent([HealthDailyActivity].self, forKey: .daily) ?? [],
                  weights: try values.decodeIfPresent([HealthWeightRecord].self, forKey: .weights) ?? [],
                  workouts: try values.decodeIfPresent([HealthWorkoutRecord].self, forKey: .workouts) ?? [],
                  sleep: try values.decodeIfPresent([HealthSleepInterval].self, forKey: .sleep) ?? [],
                  historyRangeDays: try values.decodeIfPresent(Int.self, forKey: .historyRangeDays) ?? 30,
                  dailyIssue: try values.decodeIfPresent(HealthReadIssue.self, forKey: .dailyIssue),
                  weightsIssue: try values.decodeIfPresent(HealthReadIssue.self, forKey: .weightsIssue),
                  workoutsIssue: try values.decodeIfPresent(HealthReadIssue.self, forKey: .workoutsIssue),
                  sleepIssue: try values.decodeIfPresent(HealthReadIssue.self, forKey: .sleepIssue))
    }
}

/// An in-memory anchored-query cache. Apply an entire successful batch atomically
/// in its owner actor; deletion wins if a UUID appears in both lists in a batch.
struct HealthSampleDeltaStore<Record: Identifiable & Sendable>: Sendable where Record.ID == UUID {
    private var storage: [UUID: Record] = [:]
    init() {}
    var count: Int { storage.count }
    var records: [Record] { storage.keys.sorted { $0.uuidString < $1.uuidString }.compactMap { storage[$0] } }
    subscript(id: UUID) -> Record? { storage[id] }
    mutating func apply(upserts: [Record], deletedIDs: [UUID]) {
        for record in upserts { storage[record.id] = record }
        for id in deletedIDs { storage.removeValue(forKey: id) }
    }
    mutating func reset() { storage.removeAll(keepingCapacity: false) }
}
extension HealthSampleDeltaStore: Equatable where Record: Equatable {}
extension HealthSampleDeltaStore: Codable where Record: Codable {
    private enum CodingKeys: String, CodingKey { case records }
    init(from decoder: Decoder) throws {
        self.init()
        let values = try decoder.container(keyedBy: CodingKeys.self)
        apply(upserts: try values.decode([Record].self, forKey: .records), deletedIDs: [])
    }
    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(records, forKey: .records)
    }
}

private func healthFinite(_ date: Date) -> Bool { date.timeIntervalSince1970.isFinite }
