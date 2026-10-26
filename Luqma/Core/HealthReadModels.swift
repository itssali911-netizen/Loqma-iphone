import Foundation

/// Query outcomes, not guesses about whether Health read permission was denied.
enum HealthReadIssue: String, Codable, Equatable, Sendable {
    case unavailable, restricted, deviceLocked, missingEntitlement, queryFailed, cancelled
}

/// Units are fixed by the containing field: count, kcal, kg, or cm.
struct HealthMeasurement: Codable, Equatable, Sendable {
    var value: Double
    var date: Date
}

/// An empty Health query can mean no records or no read access. Neither is zero.
enum HealthReadField: Codable, Equatable, Sendable {
    case value(HealthMeasurement)
    case noData
    case failed(HealthReadIssue)

    var measurement: HealthMeasurement? {
        guard case let .value(measurement) = self else { return nil }
        return measurement
    }

    func sanitized(allowZero: Bool, now: Date = Date()) -> Self {
        guard case let .value(measurement) = self else { return self }
        let sampleTime = measurement.date.timeIntervalSince1970
        let currentTime = now.timeIntervalSince1970
        guard measurement.value.isFinite,
              allowZero ? measurement.value >= 0 : measurement.value > 0,
              sampleTime.isFinite, currentTime.isFinite, sampleTime <= currentTime else {
            return .failed(.queryFailed)
        }
        return self
    }
}

/// A local-calendar day, which may contain 23 or 25 hours at DST transitions.
struct HealthDayWindow: Equatable, Sendable {
    let start: Date
    let end: Date
    let timeZoneIdentifier: String

    static func containing(_ date: Date, calendar: Calendar = .current) -> HealthDayWindow? {
        guard date.timeIntervalSince1970.isFinite,
              let interval = calendar.dateInterval(of: .day, for: date),
              interval.start.timeIntervalSince1970.isFinite,
              interval.end.timeIntervalSince1970.isFinite,
              interval.start < interval.end else { return nil }
        return HealthDayWindow(start: interval.start, end: interval.end,
                               timeZoneIdentifier: calendar.timeZone.identifier)
    }

    func contains(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && start <= date && date < end
    }
}

/// Private, on-device read cache. Do not include this in diary exports or network payloads.
/// Query completion is not an assertion that the person granted read access.
struct HealthReadSnapshot: Codable, Equatable, Sendable {
    var windowStart: Date
    var windowEnd: Date
    var timeZoneIdentifier: String
    var refreshedAt: Date
    var steps: HealthReadField
    var activeEnergy: HealthReadField
    var bodyMass: HealthReadField
    var height: HealthReadField

    /// Validates observations without inventing measurements or adult-profile limits.
    /// Use the current-day accessors for daily totals; old totals remain historical cache data.
    func sanitized(now: Date = Date()) -> Self {
        var result = self
        result.steps = steps.sanitized(allowZero: true, now: now)
        result.activeEnergy = activeEnergy.sanitized(allowZero: true, now: now)
        result.bodyMass = bodyMass.sanitized(allowZero: false, now: now)
        result.height = height.sanitized(allowZero: false, now: now)
        return result
    }

    /// Matching a date label is insufficient after a timezone or clock change.
    func dailyReadingsAreCurrent(at now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let window = HealthDayWindow.containing(now, calendar: calendar),
              timeZoneIdentifier == window.timeZoneIdentifier,
              windowStart == window.start, windowEnd == window.end,
              refreshedAt.timeIntervalSince1970.isFinite,
              window.contains(refreshedAt), refreshedAt <= now else { return false }
        return true
    }

    func currentSteps(at now: Date = Date(), calendar: Calendar = .current) -> HealthMeasurement? {
        currentDailyMeasurement(steps, at: now, calendar: calendar)
    }

    func currentActiveEnergy(at now: Date = Date(), calendar: Calendar = .current) -> HealthMeasurement? {
        currentDailyMeasurement(activeEnergy, at: now, calendar: calendar)
    }

    private func currentDailyMeasurement(_ field: HealthReadField, at now: Date, calendar: Calendar) -> HealthMeasurement? {
        guard dailyReadingsAreCurrent(at: now, calendar: calendar),
              let measurement = field.sanitized(allowZero: true, now: now).measurement,
              measurement.date >= windowStart, measurement.date < windowEnd,
              measurement.date <= refreshedAt else { return nil }
        return measurement
    }
}
