import Foundation
import XCTest
@testable import LuqmaCore

final class WeightProgressSnapshotTests: XCTestCase {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private func weight(_ day: String, _ kg: Double = 70) -> WeightReading {
        WeightReading(day: day, kg: kg, source: "Manual", timestamp: nil)
    }

    func testRangeIncludesTodayAndItsFirstDayAcrossYearBoundaryButExcludesFuture() {
        let values = [weight("2025-12-26"), weight("2025-12-27"), weight("2025-12-31"),
                      weight("2026-01-01"), weight("2026-01-02"), weight("2026-01-03")]
        let result = WeightProgressSnapshot.make(values, ending: "2026-01-02", range: 7, timeZone: utc)
        XCTAssertEqual(result.readings, Array(values[1...4]))
        XCTAssertEqual(result.points.map(\.reading), result.readings)
        XCTAssertEqual(result.points.map(\.id), result.readings.map(\.id))
        XCTAssertEqual(values.count, 6, "Preparing the chart must not change the stored input")
    }

    func testLeapDayAndNonLeapYearHaveTheSameExclusiveRangeBoundary() {
        let leap = [weight("2024-02-28"), weight("2024-02-29"), weight("2024-03-01")]
        XCTAssertEqual(WeightProgressSnapshot.make(leap, ending: "2024-03-01", range: 2, timeZone: utc).readings, Array(leap.suffix(2)))
        XCTAssertEqual(WeightProgressSnapshot.make(leap, ending: "2024-03-01", range: 3, timeZone: utc).readings, leap)
        let normal = [weight("2023-02-27"), weight("2023-02-28"), weight("2023-03-01")]
        XCTAssertEqual(WeightProgressSnapshot.make(normal, ending: "2023-03-01", range: 2, timeZone: utc).readings, Array(normal.suffix(2)))
    }

    func testAllRangePreservesEveryValidPastPointAndOriginalOrder() {
        let wanted = [weight("2024-03-01", 72), weight("2000-02-29", 65), weight("2024-02-28", 70)]
        let invalid = [weight("2024-3-01"), weight("2023-02-29"), weight("1900-02-29"), weight("2024-04-31"),
                       weight("2024-00-10"), weight("0000-01-01"), weight("٢٠٢٤-٠٢-٢٩"), weight("not-a-date")]
        let result = WeightProgressSnapshot.make(wanted + invalid + [weight("2024-03-02")], ending: "2024-03-01", range: 0, timeZone: utc)
        XCTAssertEqual(result.readings, wanted)
        XCTAssertEqual(result.points.map(\.reading), wanted)
        XCTAssertEqual(result.lowerBound, 64)
    }

    func testChartDatesUseTheRequestedLocalDayAndOneSharedMinimum() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let values = [weight("2024-03-09", 73), weight("2024-03-10", 68.5), weight("2024-03-11", 71)]
        let result = WeightProgressSnapshot.make(values, ending: "2024-03-11", range: 3, timeZone: zone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        XCTAssertEqual(result.lowerBound, 67.5)
        XCTAssertEqual(result.points.count, values.count)
        for (point, day) in zip(result.points, [9, 10, 11]) {
            let components = calendar.dateComponents([.year, .month, .day, .hour], from: point.date)
            XCTAssertEqual(components.year, 2024)
            XCTAssertEqual(components.month, 3)
            XCTAssertEqual(components.day, day)
            XCTAssertEqual(components.hour, 0)
        }
    }

    func testInvalidEndingOrNegativeRangeReturnsNoPreviewPoints() {
        let values = [weight("2024-03-01")]
        for ending in ["", "2024-3-01", "2023-02-29", "0000-01-01", "٢٠٢٤-٠٣-٠١"] {
            let result = WeightProgressSnapshot.make(values, ending: ending, range: 7, timeZone: utc)
            XCTAssertTrue(result.readings.isEmpty)
            XCTAssertTrue(result.points.isEmpty)
        }
        XCTAssertTrue(WeightProgressSnapshot.make(values, ending: "2024-03-01", range: -1, timeZone: utc).readings.isEmpty)
    }
}
