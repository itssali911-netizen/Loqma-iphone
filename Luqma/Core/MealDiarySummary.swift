import Foundation

/// Groups the saved quantities for one diary day. Nutrition already belongs to
/// the eaten amount, so it must not be multiplied by the amount a second time.
struct MealDiarySummary: Identifiable {
    var meal: Meal
    var entries: [DiaryEntry]
    var nutrition: Nutrition
    var id: Meal { meal }

    static func forDay(_ day: String, entries: [DiaryEntry]) -> [MealDiarySummary] {
        var grouped: [Meal: [DiaryEntry]] = [:]
        for entry in entries where entry.day == day {
            grouped[entry.meal, default: []].append(entry)
        }
        return Meal.allCases.map { meal in
            let items = grouped[meal] ?? []
            return MealDiarySummary(meal: meal, entries: items, nutrition: items.reduce(.zero) { $0 + $1.nutrition })
        }
    }
}
