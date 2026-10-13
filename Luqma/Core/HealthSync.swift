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
    // Optional fields preserve backups made before daily activity syncing.
    var distanceKM: Double?
    var exerciseMinutes: Double?
    var workoutCount: Int?
    var adjustmentEnabled: Bool?
    // Only a goal actually applied/recomputed from the saved plan has a known
    // activity baseline. Older backups intentionally decode as unknown.
    var planGoalAssociated: Bool?
}

/// HealthKit statistics are the sole source of activity energy. Step counts,
/// exercise minutes and workout totals must never be converted into a second
/// calorie allowance on top of that energy.
enum HealthActivity {
    static func setGoalAssociation(_ associated: Bool, in snapshot: inout DiarySnapshot) {
        if associated {
            var cache = snapshot.healthSync ?? HealthSyncState()
            cache.planGoalAssociated = true; snapshot.healthSync = cache
        } else if var cache = snapshot.healthSync {
            if cache.planGoalAssociated == true { cache.planGoalAssociated = false }
            if cache.adjustmentEnabled == true { cache.adjustmentEnabled = false }
            snapshot.healthSync = cache
        }
    }
    static func valid(_ value: Double?, maximum: Double) -> Double? {
        value.flatMap { $0.isFinite && (0...maximum).contains($0) ? $0 : nil }
    }
    static func update(_ cache: HealthSyncState, day: String, steps: Double?, activeCalories: Double?,
                       distanceKM: Double?, exerciseMinutes: Double?, workoutIDs: [UUID]) -> HealthSyncState {
        var next = cache
        next.activityDay = day
        next.steps = valid(steps, maximum: 300000)
        next.activeCalories = valid(activeCalories, maximum: 50000)
        next.distanceKM = valid(distanceKM, maximum: 1000)
        next.exerciseMinutes = valid(exerciseMinutes, maximum: 1440)
        // Replacing each daily snapshot also handles deleted activity samples.
        // UUID uniqueness prevents a repeated query result from duplicating workouts.
        next.workoutCount = workoutIDs.isEmpty ? nil : Set(workoutIDs).count
        return next
    }
    static func plannedCalories(_ snapshot: DiarySnapshot, day: String) -> Double? {
        // A manually entered goal does not declare its activity assumption.
        // Never guess that baseline and then add the same activity twice.
        guard snapshot.healthSync?.planGoalAssociated == true, var plan = snapshot.weightPlan else { return nil }
        do { try plan.validate() } catch { return nil }
        if snapshot.adaptive {
            let average = DiaryValidation.average(snapshot.weights, ending: day)
            if average.count >= 3, let kg = average.kg { plan.weight = kg }
        }
        let baseline = WeightModel.baseline(plan)
        let value = baseline.activity * plan.weight * (1 + plan.activityChange / 100)
        return valid(value, maximum: 50000)
    }
    static func adjustment(_ snapshot: DiarySnapshot, day: String, today: String = DayKey.today) -> Double {
        guard day == today, snapshot.healthEnabled, let cache = snapshot.healthSync,
              cache.adjustmentEnabled == true, cache.activityDay == day,
              let active = valid(cache.activeCalories, maximum: 50000),
              let planned = plannedCalories(snapshot, day: day), snapshot.goals.valid,
              (500...10000).contains(snapshot.goals.kcal) else { return 0 }
        return min(max(0, active - planned), 10000 - snapshot.goals.kcal).rounded(.down)
    }
    static func goals(_ snapshot: DiarySnapshot, day: String, today: String = DayKey.today) -> Nutrition {
        let extra = adjustment(snapshot, day: day, today: today)
        guard extra > 0 else { return snapshot.goals }
        // Keep the saved macro split coherent without mutating the saved plan.
        return snapshot.goals.scaled((snapshot.goals.kcal + extra) / snapshot.goals.kcal)
    }
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
