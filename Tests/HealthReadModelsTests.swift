import XCTest
@testable import LuqmaCore

final class HealthReadModelsTests: XCTestCase {
    private func date(_ text: String) -> Date {
        ISO8601DateFormatter().date(from: text)!
    }

    private func calendar(_ zone: String = "Asia/Riyadh") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private func snapshot(at now: Date, calendar: Calendar) throws -> HealthReadSnapshot {
        let window = try XCTUnwrap(HealthDayWindow.containing(now, calendar: calendar))
        return HealthReadSnapshot(windowStart: window.start, windowEnd: window.end,
                                  timeZoneIdentifier: window.timeZoneIdentifier, refreshedAt: now,
                                  steps: .value(HealthMeasurement(value: 0, date: now)),
                                  activeEnergy: .noData,
                                  bodyMass: .value(HealthMeasurement(value: 72.3, date: now.addingTimeInterval(-86400))),
                                  height: .value(HealthMeasurement(value: 170.5, date: now.addingTimeInterval(-86400 * 30))))
    }

    func testMissingAndFailedReadsStayUnknownWhileObservedZeroIsPreserved() throws {
        let now = date("2026-10-25T10:00:00Z")
        let zero = HealthReadField.value(HealthMeasurement(value: 0, date: now))
        XCTAssertNil(HealthReadField.noData.measurement)
        XCTAssertNil(HealthReadField.failed(.deviceLocked).measurement)
        XCTAssertEqual(zero.sanitized(allowZero: true, now: now).measurement?.value, 0)
        XCTAssertEqual(HealthReadField.noData.sanitized(allowZero: true, now: now), .noData)
        XCTAssertEqual(HealthReadField.failed(.restricted).sanitized(allowZero: true, now: now), .failed(.restricted))

        var state = try snapshot(at: now, calendar: calendar())
        state.activeEnergy = .failed(.deviceLocked)
        let clean = state.sanitized(now: now)
        XCTAssertEqual(clean.currentSteps(at: now, calendar: calendar())?.value, 0)
        XCTAssertNil(clean.currentActiveEnergy(at: now, calendar: calendar()))
        XCTAssertEqual(clean.activeEnergy, .failed(.deviceLocked))
        XCTAssertEqual(clean.bodyMass.measurement?.value, 72.3)
    }

    func testInvalidAndFutureMeasurementsAreRejectedWithoutInventingZero() {
        let now = date("2026-10-25T10:00:00Z")
        for value in [Double.nan, .infinity, -.infinity, -1] {
            let field = HealthReadField.value(HealthMeasurement(value: value, date: now))
            XCTAssertEqual(field.sanitized(allowZero: true, now: now), .failed(.queryFailed))
        }
        XCTAssertEqual(HealthReadField.value(HealthMeasurement(value: 0, date: now)).sanitized(allowZero: false, now: now), .failed(.queryFailed))
        let future = HealthReadField.value(HealthMeasurement(value: 100, date: now.addingTimeInterval(1)))
        XCTAssertEqual(future.sanitized(allowZero: true, now: now), .failed(.queryFailed))
        let invalidDate = HealthReadField.value(HealthMeasurement(value: 100, date: Date(timeIntervalSince1970: .infinity)))
        XCTAssertEqual(invalidDate.sanitized(allowZero: true, now: now), .failed(.queryFailed))

        // Reading a measurement is independent of the adult calorie calculator's bounds.
        XCTAssertEqual(HealthReadField.value(HealthMeasurement(value: 12, date: now)).sanitized(allowZero: false, now: now).measurement?.value, 12)
        XCTAssertEqual(HealthReadField.value(HealthMeasurement(value: 65, date: now)).sanitized(allowZero: false, now: now).measurement?.value, 65)
    }

    func testLocalDayWindowsRespectDSTAndExclusiveEnd() throws {
        let local = calendar("America/New_York")
        let spring = try XCTUnwrap(HealthDayWindow.containing(date("2026-03-08T16:00:00Z"), calendar: local))
        let autumn = try XCTUnwrap(HealthDayWindow.containing(date("2026-11-01T17:00:00Z"), calendar: local))
        XCTAssertEqual(spring.end.timeIntervalSince(spring.start), 23 * 3600)
        XCTAssertEqual(autumn.end.timeIntervalSince(autumn.start), 25 * 3600)
        XCTAssertEqual(local.component(.hour, from: spring.start), 0)
        XCTAssertEqual(local.component(.hour, from: autumn.start), 0)
        XCTAssertTrue(spring.contains(spring.start))
        XCTAssertTrue(spring.contains(spring.end.addingTimeInterval(-1)))
        XCTAssertFalse(spring.contains(spring.end))
        XCTAssertEqual(HealthDayWindow.containing(spring.end, calendar: local)?.start, spring.end)
    }

    func testDayTimezoneAndClockChangesInvalidateDailyTotals() throws {
        let now = date("2026-10-25T10:00:00Z"), local = calendar()
        let state = try snapshot(at: now, calendar: local)
        XCTAssertTrue(state.dailyReadingsAreCurrent(at: now, calendar: local))
        XCTAssertNil(state.currentSteps(at: state.windowEnd, calendar: local))
        XCTAssertFalse(state.dailyReadingsAreCurrent(at: now, calendar: calendar("America/New_York")))
        XCTAssertNil(state.currentSteps(at: now, calendar: calendar("America/New_York")))
        XCTAssertFalse(state.dailyReadingsAreCurrent(at: now.addingTimeInterval(-1), calendar: local))

        var malformed = state
        malformed.windowStart = state.windowStart.addingTimeInterval(1)
        XCTAssertFalse(malformed.dailyReadingsAreCurrent(at: now, calendar: local))
        malformed = state
        malformed.refreshedAt = state.windowStart.addingTimeInterval(-1)
        XCTAssertFalse(malformed.dailyReadingsAreCurrent(at: now, calendar: local))

        // Latest weight and height remain separate from the daily activity window.
        let nextDay = state.sanitized(now: state.windowEnd)
        XCTAssertEqual(nextDay.bodyMass.measurement?.value, 72.3)
        XCTAssertEqual(nextDay.height.measurement?.value, 170.5)
    }

    func testDailyMeasurementMustBelongToItsWindowAndObservedRefresh() throws {
        let now = date("2026-10-25T10:00:00Z"), local = calendar()
        var state = try snapshot(at: now, calendar: local)
        state.steps = .value(HealthMeasurement(value: 5000, date: state.windowStart.addingTimeInterval(-1)))
        XCTAssertNil(state.currentSteps(at: now, calendar: local))
        state.activeEnergy = .value(HealthMeasurement(value: 0, date: now))
        XCTAssertEqual(state.currentActiveEnergy(at: now, calendar: local)?.value, 0)
        state.activeEnergy = .value(HealthMeasurement(value: 500, date: now.addingTimeInterval(1)))
        XCTAssertNil(state.currentActiveEnergy(at: now.addingTimeInterval(2), calendar: local))
    }

    func testPartialSnapshotCodableRoundTripPreservesUnknownAndFailureStates() throws {
        let now = date("2026-10-25T10:00:00Z")
        var state = try snapshot(at: now, calendar: calendar())
        state.bodyMass = .noData
        state.activeEnergy = .failed(.deviceLocked)
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(HealthReadSnapshot.self, from: encoded)
        XCTAssertEqual(decoded, state)
        XCTAssertEqual(decoded.steps.measurement?.value, 0)
        XCTAssertNil(decoded.bodyMass.measurement)
        XCTAssertEqual(decoded.activeEnergy, .failed(.deviceLocked))
    }
}
