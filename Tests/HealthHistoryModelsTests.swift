import XCTest
@testable import LuqmaCore

final class HealthHistoryModelsTests: XCTestCase {
    func testOlderSnapshotWithoutDetailsDecodesAndPreservesKnownFields() throws {
        let now = Date(timeIntervalSinceReferenceDate: 100)
        let original = HealthReadSnapshot(windowStart: now, windowEnd: now.addingTimeInterval(86400),
            timeZoneIdentifier: "Asia/Riyadh", refreshedAt: now,
            steps: .value(HealthMeasurement(value: 0, date: now)), activeEnergy: .noData,
            bodyMass: .failed(.deviceLocked), height: .noData)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "details")
        let decoded = try JSONDecoder().decode(HealthReadSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.details, .empty)
    }
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    private func calendar(_ zone: String = "Asia/Riyadh") -> Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: zone)!; return value
    }
    private func field(_ value: Double, _ date: Date) -> HealthReadField { .value(HealthMeasurement(value: value, date: date)) }
    private func sleep(_ start: String, _ end: String, id: UUID = UUID()) -> HealthSleepInterval {
        HealthSleepInterval(id: id, start: date(start), end: date(end))
    }

    func testOnlySupportedHistoryRangesAreAcceptedAndInvalidDetailsRangesDefaultToThirty() throws {
        XCTAssertEqual(HealthHistoryRange.allCases.map(\.rawValue), [7, 30, 90])
        for value in [0, 1, 6, 8, 29, 31, 91, Int.max] {
            XCTAssertNil(HealthHistoryRange(rawValue: value))
            XCTAssertEqual(HealthReadDetails(historyRangeDays: value).historyRangeDays, 30)
        }
        let decoded = try JSONDecoder().decode(HealthReadDetails.self, from: Data("{\"historyRangeDays\":365}".utf8))
        XCTAssertEqual(decoded.historyRangeDays, 30)
        XCTAssertEqual(try JSONDecoder().decode(HealthHistoryRange.self, from: Data("90".utf8)), .quarter)
        XCTAssertThrowsError(try JSONDecoder().decode(HealthHistoryRange.self, from: Data("0".utf8)))
    }

    func testRangesContainConsecutiveLocalDaysRatherThanFixedTwentyFourHourBlocks() throws {
        let local = calendar("America/New_York"), end = date("2026-03-10T16:00:00Z")
        for range in HealthHistoryRange.allCases {
            let windows = range.dayWindows(ending: end, calendar: local)
            XCTAssertEqual(windows.count, range.days)
            XCTAssertEqual(windows.last?.start, local.startOfDay(for: end))
            for index in 1..<windows.count { XCTAssertEqual(windows[index - 1].end, windows[index].start) }
            XCTAssertEqual(windows.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }, Double(range.days * 24 - 1) * 3600)
        }
        XCTAssertTrue(HealthHistoryRange.week.dayWindows(ending: Date(timeIntervalSince1970: .infinity), calendar: local).isEmpty)
    }

    func testSleepUnionClipsMidnightMergesDevicesAndDoesNotSumContainedSamples() {
        let local = calendar(), on = date("2026-10-27T12:00:00Z"), now = date("2026-10-28T12:00:00Z")
        let samples = [sleep("2026-10-26T20:00:00Z", "2026-10-26T23:00:00Z"),
                       sleep("2026-10-26T22:00:00Z", "2026-10-27T01:00:00Z"),
                       sleep("2026-10-26T23:00:00Z", "2026-10-27T01:00:00Z"),
                       sleep("2026-10-27T03:00:00Z", "2026-10-27T04:00:00Z"),
                       sleep("2026-10-27T20:00:00Z", "2026-10-27T22:00:00Z")]
        XCTAssertEqual(HealthSleepUnion.availableDuration(samples, on: on, calendar: local, now: now), 6 * 3600)
        XCTAssertEqual(HealthSleepUnion.duration(samples + samples, on: on, calendar: local, now: now), 6 * 3600)
    }

    func testSleepUnionUsesRealSpringAndAutumnDayLengths() {
        let local = calendar("America/New_York"), now = date("2026-11-03T12:00:00Z")
        let spring = [sleep("2026-03-08T05:00:00Z", "2026-03-09T04:00:00Z")]
        let autumn = [sleep("2026-11-01T04:00:00Z", "2026-11-02T05:00:00Z")]
        XCTAssertEqual(HealthSleepUnion.duration(spring, on: date("2026-03-08T16:00:00Z"), calendar: local, now: now), 23 * 3600)
        XCTAssertEqual(HealthSleepUnion.duration(autumn, on: date("2026-11-01T17:00:00Z"), calendar: local, now: now), 25 * 3600)
    }

    func testSleepUnionChangesCorrectlyWithTheUsersTimezone() {
        let samples = [sleep("2026-10-26T23:00:00Z", "2026-10-27T06:00:00Z")]
        let on = date("2026-10-27T12:00:00Z"), now = date("2026-10-28T12:00:00Z")
        XCTAssertEqual(HealthSleepUnion.duration(samples, on: on, calendar: calendar(), now: now), 7 * 3600)
        XCTAssertEqual(HealthSleepUnion.duration(samples, on: on, calendar: calendar("America/New_York"), now: now), 2 * 3600)
    }

    func testSleepMissingInvalidFutureAndNonOverlappingSamplesRemainUnavailable() {
        let on = date("2026-10-27T12:00:00Z"), now = date("2026-10-28T12:00:00Z")
        let invalid = HealthSleepInterval(id: UUID(), start: Date(timeIntervalSince1970: .nan), end: now)
        for samples in [[], [invalid], [sleep("2026-10-27T08:00:00Z", "2026-10-27T07:00:00Z")],
                        [sleep("2026-10-28T13:00:00Z", "2026-10-28T14:00:00Z")]] {
            XCTAssertNil(HealthSleepUnion.availableDuration(samples, on: on, calendar: calendar(), now: now))
        }
        XCTAssertEqual(HealthSleepUnion.duration([], on: on, calendar: calendar(), now: now), 0, "The numeric convenience is mathematical only; product readouts use the optional result.")
    }

    func testSleepUnionNeverCountsTimeAfterTheCurrentMoment() {
        let now = date("2026-10-27T10:00:00Z")
        let sample = sleep("2026-10-27T08:00:00Z", "2026-10-27T20:00:00Z")
        XCTAssertEqual(HealthSleepUnion.duration([sample], on: now, calendar: calendar(), now: now), 2 * 3600)
        XCTAssertNil(sample.sanitized(now: now), "A future-ended anchored sample can stay in the native pending cache but is not published as a completed reading.")
    }

    func testAnchoredCacheUpdatesUUIDsHandlesDeletionAndResetWithoutDuplicateSamples() {
        let id = UUID(), now = date("2026-10-27T10:00:00Z")
        var cache = HealthSampleDeltaStore<HealthWeightRecord>()
        cache.apply(upserts: [HealthWeightRecord(id: id, date: now, kg: 70)], deletedIDs: [])
        cache.apply(upserts: [HealthWeightRecord(id: id, date: now, kg: 71)], deletedIDs: [])
        XCTAssertEqual(cache.count, 1); XCTAssertEqual(cache[id]?.kg, 71)
        cache.apply(upserts: [], deletedIDs: [UUID()]); XCTAssertEqual(cache.count, 1)
        cache.apply(upserts: [HealthWeightRecord(id: id, date: now, kg: 72)], deletedIDs: [id])
        XCTAssertEqual(cache.count, 0, "Deletion wins within a batch; a revoked/deleted sample must not reappear from the same batch.")
        cache.apply(upserts: [HealthWeightRecord(id: id, date: now, kg: 70)], deletedIDs: [])
        cache.reset(); XCTAssertTrue(cache.records.isEmpty)
    }

    func testAnchoredCacheCodableRoundTripKeepsIdentityAndStableOrdering() throws {
        let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        var cache = HealthSampleDeltaStore<HealthWeightRecord>()
        cache.apply(upserts: [HealthWeightRecord(id: second, date: Date(), kg: 72), HealthWeightRecord(id: first, date: Date(), kg: 71)], deletedIDs: [])
        XCTAssertEqual(cache.records.map(\.id), [first, second])
        let decoded = try JSONDecoder().decode(HealthSampleDeltaStore<HealthWeightRecord>.self, from: JSONEncoder().encode(cache))
        XCTAssertEqual(decoded, cache)
    }

    func testAdditionalMeasurementsSanitizeUnitsAndBoundsWithoutInventingZero() {
        let now = date("2026-10-27T10:00:00Z")
        let details = HealthReadDetails(walkingDistance: field(0, now), basalEnergy: field(.nan, now),
                                       bodyFatPercentage: field(101, now), heartRate: field(0, now))
            .sanitized(now: now, calendar: calendar())
        XCTAssertEqual(details.walkingDistance.measurement?.value, 0)
        XCTAssertEqual(details.basalEnergy, .failed(.queryFailed))
        XCTAssertEqual(details.bodyFatPercentage, .failed(.queryFailed))
        XCTAssertEqual(details.heartRate, .failed(.queryFailed))
        XCTAssertEqual(HealthReadDetails(bodyFatPercentage: field(100, now)).sanitized(now: now).bodyFatPercentage.measurement?.value, 100)
        XCTAssertEqual(HealthReadDetails(heartRate: .failed(.deviceLocked)).sanitized(now: now).heartRate, .failed(.deviceLocked))
        XCTAssertEqual(HealthReadDetails(heartRate: field(60, now.addingTimeInterval(1))).sanitized(now: now).heartRate, .failed(.queryFailed))
    }

    func testWorkoutValidationPreservesNetDurationAndHasNoEnergyContribution() {
        let now = date("2026-10-27T10:00:00Z"), start = date("2026-10-27T08:00:00Z"), end = date("2026-10-27T09:00:00Z")
        let workout = HealthWorkoutRecord(id: UUID(), start: start, end: end, kind: .running, durationSeconds: 1800)
        XCTAssertEqual(workout.sanitized(now: now)?.durationSeconds, 1800)
        for seconds in [-1, .infinity, .nan, 3602] {
            var invalid = workout; invalid.durationSeconds = seconds; XCTAssertNil(invalid.sanitized(now: now))
        }
        var invalid = workout; invalid.end = now.addingTimeInterval(1); XCTAssertNil(invalid.sanitized(now: now))
        invalid = workout; invalid.start = end; XCTAssertNil(invalid.sanitized(now: now))
        let details = HealthReadDetails(workouts: [workout]).sanitized(now: now, calendar: calendar())
        XCTAssertEqual(details.workouts, [workout])
        XCTAssertEqual(details.basalEnergy, .noData)
        XCTAssertEqual(details.walkingDistance, .noData)
    }

    func testUnknownWorkoutKindsDecodeAsOtherWithoutDroppingTheRecord() throws {
        XCTAssertEqual(try JSONDecoder().decode(HealthWorkoutKind.self, from: Data("\"future_sport\"".utf8)), .other)
        XCTAssertEqual(String(data: try JSONEncoder().encode(HealthWorkoutKind.running), encoding: .utf8), "\"running\"")
    }

    func testWeightValidationAllowsRealChildMeasurementsAndRejectsInvalidValues() {
        let now = date("2026-10-27T10:00:00Z")
        XCTAssertEqual(HealthWeightRecord(id: UUID(), date: now, kg: 12).sanitized(now: now)?.kg, 12)
        for kg in [0, -1, .infinity, .nan] { XCTAssertNil(HealthWeightRecord(id: UUID(), date: now, kg: kg).sanitized(now: now)) }
        XCTAssertNil(HealthWeightRecord(id: UUID(), date: now.addingTimeInterval(1), kg: 70).sanitized(now: now))
    }

    func testDailyRecordsRequireMatchingLocalMeasurementDatesAndPreserveUnknownOutcomes() throws {
        let local = calendar(), now = date("2026-10-27T10:00:00Z")
        let day = try XCTUnwrap(HealthDayWindow.containing(now, calendar: local))
        let record = HealthDailyActivity(idDate: "2026-10-27", date: day.start, steps: field(0, now),
                                         activeEnergy: .noData, walkingDistance: .failed(.restricted),
                                         basalEnergy: field(1500, day.end))
        let clean = try XCTUnwrap(record.sanitized(now: day.end, calendar: local))
        XCTAssertEqual(clean.steps.measurement?.value, 0); XCTAssertEqual(clean.activeEnergy, .noData)
        XCTAssertEqual(clean.walkingDistance, .failed(.restricted)); XCTAssertEqual(clean.basalEnergy, .failed(.queryFailed))
        XCTAssertNil(HealthDailyActivity(idDate: " ", date: now).sanitized(now: now))
        XCTAssertNil(HealthDailyActivity(idDate: "future", date: day.end).sanitized(now: now))
    }

    func testDetailsBoundTheRangeDeduplicateUUIDsAndKeepCrossBoundarySleep() throws {
        let local = calendar(), now = date("2026-10-27T10:00:00Z")
        let lower = try XCTUnwrap(HealthHistoryRange.week.dayWindows(ending: now, calendar: local).first?.start)
        let id = UUID(), old = UUID(), sleepID = UUID()
        let details = HealthReadDetails(weights: [HealthWeightRecord(id: id, date: now, kg: 70),
                                                  HealthWeightRecord(id: id, date: now, kg: 71),
                                                  HealthWeightRecord(id: old, date: lower.addingTimeInterval(-1), kg: 69)],
                                        sleep: [HealthSleepInterval(id: sleepID, start: lower.addingTimeInterval(-3600), end: lower.addingTimeInterval(3600))],
                                        historyRangeDays: 7).sanitized(now: now, calendar: local)
        XCTAssertEqual(details.weights.count, 1); XCTAssertEqual(details.weights.first?.kg, 71)
        XCTAssertEqual(details.sleep.count, 1)
        XCTAssertEqual(HealthSleepUnion.duration(details.sleep, on: lower, calendar: local, now: now), 3600)
    }

    func testReadableDataAndIssuesNeverInferPermissionFromEmptyOrFailedQueries() {
        let now = Date().addingTimeInterval(-60)
        XCTAssertFalse(HealthReadDetails.empty.hasReadableData)
        XCTAssertFalse(HealthReadDetails(daily: [HealthDailyActivity(idDate: "day", date: now)]).hasReadableData)
        let partial = HealthReadDetails(walkingDistance: field(0, now), heartRate: .failed(.deviceLocked),
                                        dailyIssue: .queryFailed, weightsIssue: .deviceLocked)
        XCTAssertTrue(partial.hasReadableData, "An observed zero is still an available observation.")
        XCTAssertEqual(partial.queryIssues, [.deviceLocked, .queryFailed])
        XCTAssertFalse(HealthReadDetails(heartRate: .failed(.restricted), sleepIssue: .queryFailed).hasReadableData)
        XCTAssertFalse(HealthReadDetails(weights: [HealthWeightRecord(id: UUID(), date: now, kg: .nan)]).hasReadableData)
    }

    func testPartialDetailsAndDailyDecodingDefaultToUnknownAndRoundTripErrors() throws {
        XCTAssertEqual(try JSONDecoder().decode(HealthReadDetails.self, from: Data("{}".utf8)), .empty)
        let daily = try JSONDecoder().decode(HealthDailyActivity.self, from: Data("{\"idDate\":\"day\",\"date\":0}".utf8))
        XCTAssertEqual(daily.steps, .noData); XCTAssertEqual(daily.basalEnergy, .noData)
        let details = HealthReadDetails(heartRate: .failed(.deviceLocked), daily: [daily], historyRangeDays: 90, sleepIssue: .queryFailed)
        XCTAssertEqual(try JSONDecoder().decode(HealthReadDetails.self, from: JSONEncoder().encode(details)), details)
        XCTAssertThrowsError(try JSONDecoder().decode(HealthReadDetails.self, from: Data("{\"heartRate\":123}".utf8)))
    }
}
