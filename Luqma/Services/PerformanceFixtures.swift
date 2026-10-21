#if DEBUG && targetEnvironment(simulator)
import SwiftUI

/// Test infrastructure only. The probe creates a fresh disposable Simulator.
/// Seed the real diary file once, then let every launch use production decoding,
/// views and persistence. Never replace an unrelated existing diary.
@MainActor enum LuqmaPerformanceFixture {
    static let identity = "v1|entries=5000|days=7|today=800|seed=20261021"
    static func prepare(_ diary: DiaryStore) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-loqma-performance-fixture") else { return nil }
        guard let index = args.firstIndex(of: "-loqma-performance-entries"),
              args.indices.contains(index + 1), args[index + 1] == "5000" else { return "invalid-fixture-arguments" }
        if diary.state.entries.isEmpty {
            guard diary.state.recipes.isEmpty, diary.state.weights.isEmpty,
                  diary.state.products.isEmpty, (diary.state.customFoods ?? []).isEmpty,
                  diary.state.fitnessProfile == nil, diary.state.fitnessDraft == nil else { return "refused-unrelated-diary" }
            do {
                let snapshot = try makeSnapshot()
                diary.change { $0 = snapshot }
            } catch { diary.report(error); return "fixture-seed-failed" }
        }
        let entries = diary.state.entries
        guard entries.count == 5000, Set(entries.map(\.day)).count == 7,
              entries.filter({ $0.day == DayKey.today }).count == 800,
              entries.allSatisfy({ $0.foodID == "custom:luqma-performance-oats" }),
              diary.state.fitnessProfile != nil, diary.state.appliedFitnessPlan != nil else { return "fixture-verification-failed" }
        return identity
    }

    private static func makeSnapshot() throws -> DiarySnapshot {
        var snapshot = DiarySnapshot()
        snapshot.language = .en
        let food = Food(catalogID: "custom:luqma-performance-oats", name: "Luqma Performance Oats",
                        unit: .serving, nutrition: Nutrition(kcal: 100, protein: 10, carbs: 15, fat: 0),
                        serving: "1 serving", servingQuantity: 1, servingUnit: "serving",
                        servingNutrition: Nutrition(kcal: 100, protein: 10, carbs: 15, fat: 0), source: "Your food")
        snapshot.customFoods = [food]
        snapshot.products = [food]
        snapshot.searchHistory = [food]
        let calendar = DisplayFormat.calendar(.en)
        let today = calendar.startOfDay(for: Date())
        var prototype = try DiaryEntry(food: food, amount: 1, unit: .serving, meal: .breakfast, day: DayKey.today, language: .en)
        prototype.created = "2026-10-21T00:00:00Z"
        var ordinal = 0
        snapshot.entries.reserveCapacity(5000)
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { throw AppError.invalid("تاريخ الاختبار غير صالح.", "Invalid fixture date.") }
            let day = DayKey.string(date)
            for item in 0..<(offset == 0 ? 800 : 700) {
                ordinal += 1
                var entry = prototype
                entry.id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", ordinal))!
                entry.day = day
                entry.meal = Meal.allCases[item % Meal.allCases.count]
                snapshot.entries.append(entry)
            }
        }
        let answers = FitnessAnswers(sex: .male, age: 35, heightCM: 175, weightKG: 80,
                                     goal: .fatLoss, pace: .gentle, activity: .light, safety: .generalAdult)
        let profile = FitnessProfile(id: UUID(uuidString: "00000000-0000-4000-8000-000000090001")!, answers: answers)
        var plan = try FitnessEstimator.makePlan(profile: profile, day: DayKey.today)
        plan.id = UUID(uuidString: "00000000-0000-4000-8000-000000090002")!
        snapshot.fitnessProfile = profile
        snapshot.appliedFitnessPlan = plan
        snapshot.fitnessOnboardingDismissed = true
        snapshot.goals = plan.goals
        try DiaryValidation.check(snapshot)
        return snapshot
    }
}

struct LuqmaPerformanceMarker: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if let identity = AppServices.shared.performanceFixtureIdentity {
            content.accessibilityElement(children: .contain)
                .accessibilityIdentifier("performance.fixture.ready")
                .accessibilityValue(identity)
        } else { content }
    }
}
#endif
