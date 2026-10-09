import Foundation

struct HealthWeightSample: Codable, Equatable {
    var id: UUID
    var kg: Double
    var end: Double
    var day: String { DayKey.string(Date(timeIntervalSince1970: end)) }
    func valid(now: Date) -> Bool { kg.isFinite && (35...300).contains(kg) && end.isFinite && end > 0 && end <= now.timeIntervalSince1970 }
}

/// The anchor and matching records are saved together only after a successful read.
/// A denied/empty read never erases previously imported weight history.
struct HealthSyncState: Codable, Equatable {
    var records: [HealthWeightSample] = []
    var anchor: Data?
    var activityDay: String?
    var steps: Double?
    var activeCalories: Double?
    var heightCM: Double?
    var updatedAt: Double?
}

enum HealthSync {
    static func apply(added: [HealthWeightSample], deleted: Set<UUID>, to cache: HealthSyncState,
                      weights: [WeightReading], now: Date = Date()) -> (cache: HealthSyncState, weights: [WeightReading]) {
        var next = cache
        var records = Dictionary(cache.records.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        var affected = Set<String>()
        for id in deleted { if let old = records.removeValue(forKey: id) { affected.insert(old.day) } }
        for sample in added where sample.valid(now: now) && !deleted.contains(sample.id) {
            if let old = records[sample.id] { affected.insert(old.day) }
            records[sample.id] = sample; affected.insert(sample.day)
        }
        next.records = records.values.sorted { $0.end == $1.end ? $0.id.uuidString < $1.id.uuidString : $0.end < $1.end }
        var daily: [String: HealthWeightSample] = [:]
        for sample in next.records where sample.valid(now: now) { daily[sample.day] = sample }
        var output = weights
        for day in affected {
            let existing = output.firstIndex { $0.day == day }
            // A manual reading remains authoritative even if Health changes or deletes that day.
            if let existing, output[existing].source != "Apple Health" { continue }
            if let sample = daily[day] {
                let reading = WeightReading(day: day, kg: sample.kg, source: "Apple Health", timestamp: sample.end)
                if let existing { output[existing] = reading } else { output.append(reading) }
            } else if let existing { output.remove(at: existing) }
        }
        return (next, output.sorted { $0.day < $1.day })
    }
}
