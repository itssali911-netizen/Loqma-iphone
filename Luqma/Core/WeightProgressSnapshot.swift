import Foundation

/// One immutable preparation pass serves both the chart and its history list.
/// Canonical day keys sort chronologically, so range filtering needs no date
/// formatter per reading. Stored readings and their order remain unchanged.
struct WeightProgressSnapshot {
    struct Point: Identifiable {
        var reading: WeightReading
        var date: Date
        var id: String { reading.id }
    }

    var readings: [WeightReading]
    var points: [Point]
    var lowerBound: Double

    static func make(_ weights: [WeightReading], ending today: String, range: Int,
                     timeZone: TimeZone = .current) -> WeightProgressSnapshot {
        let empty = WeightProgressSnapshot(readings: [], points: [], lowerBound: 0)
        guard range >= 0, let ending = canonicalComponents(today) else { return empty }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let end = utc.date(from: ending) else { return empty }

        var firstDay: String?
        if range > 0, let first = utc.date(byAdding: .day, value: 1 - range, to: end) {
            let parts = utc.dateComponents([.era, .year, .month, .day], from: first)
            if parts.era == 1, let year = parts.year, let month = parts.month, let day = parts.day {
                firstDay = String(format: "%04d-%02d-%02d", locale: Locale(identifier: "en_US_POSIX"), year, month, day)
            }
        }
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        var result = empty
        var minimum: Double?
        for reading in weights {
            guard reading.day <= today, firstDay.map({ reading.day >= $0 }) ?? true,
                  let components = canonicalComponents(reading.day) else { continue }
            // Display each original day at local midnight, as the chart did
            // previously. Retain its point even if a zone has skipped a day.
            guard let date = local.date(from: components) ?? utc.date(from: components) else { continue }
            result.readings.append(reading)
            result.points.append(Point(reading: reading, date: date))
            minimum = minimum.map { min($0, reading.kg) } ?? reading.kg
        }
        result.lowerBound = minimum.map { $0 - 1 } ?? 0
        return result
    }

    private static func canonicalComponents(_ key: String) -> DateComponents? {
        let bytes = Array(key.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45 else { return nil }
        for index in [0, 1, 2, 3, 5, 6, 8, 9] where !(48...57).contains(bytes[index]) { return nil }
        let year = Int(bytes[0] - 48) * 1000 + Int(bytes[1] - 48) * 100 + Int(bytes[2] - 48) * 10 + Int(bytes[3] - 48)
        let month = Int(bytes[5] - 48) * 10 + Int(bytes[6] - 48)
        let day = Int(bytes[8] - 48) * 10 + Int(bytes[9] - 48)
        guard (1...9999).contains(year), (1...12).contains(month) else { return nil }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let monthDays = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...monthDays[month - 1]).contains(day) else { return nil }
        return DateComponents(era: 1, year: year, month: month, day: day)
    }
}
