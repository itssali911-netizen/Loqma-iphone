import Foundation

enum ApprovedAssessmentMetadata {
    static let keys:Set<String> = ["unit.age","unit.height","unit.weight","input.imperial.age","input.imperial.height","input.imperial.weight"]
}

// Presentation adapters for the approved eleven-screen package. The current
// FitnessAnswers/Profile/Plan remain the single persisted assessment model.
enum ApprovedMeasurementUnit: String, CaseIterable, Identifiable {
    case metric, imperial
    var id: String { rawValue }
    func title(for field: FitnessAssessmentNumberField) -> String {
        field == .height ? (self == .metric ? "cm" : "ft / in") : (self == .metric ? "kg" : "lbs")
    }
    func displayed(_ value: Double, field: FitnessAssessmentNumberField) -> Double {
        guard self == .imperial else { return value }
        return field == .height ? value / 2.54 : value / 0.45359237
    }
    func metric(_ value: Double, field: FitnessAssessmentNumberField) -> Double {
        guard self == .imperial else { return value }
        return field == .height ? value * 2.54 : value * 0.45359237
    }
    func canonicalText(from raw:String,field:FitnessAssessmentNumberField)->String {
        let normalized=String(DisplayFormat.westernDigits(raw).prefix(64))
        guard self == .imperial else{return normalized}
        let candidate=normalized.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !candidate.isEmpty,
              candidate.unicodeScalars.allSatisfy({(48...57).contains($0.value) || $0.value == 46 || $0.value == 44 || $0.value == 0x066B}),
              let value=TextSearch.number(candidate),value.isFinite else{return normalized}
        return field.displayText(metric(value,field:field))
    }
}

enum ApprovedCalorieUnit: String, CaseIterable, Identifiable {
    case kcal, joules
    var id: String { rawValue }
    func title(_ language: AppLanguage) -> String {
        switch self {
        case .kcal: return language.text("Kcal (سعرة)", "Kcal")
        case .joules: return language.text("Joule’s (جول)", "Joule’s")
        }
    }
    func value(for calories: Double) -> Double { self == .kcal ? calories : calories * 4184 }
}

extension FitnessGoal {
    // Approved artwork, while retaining the actual goal meanings and formulas.
    var approvedIconName: String {
        switch self {
        case .fatLoss: return "CFAGoalScale"
        case .muscleGain: return "CFAGoalDumbbell"
        case .recomposition: return "CFAGoalRobot"
        case .maintenance: return "CFAGoalPhone"
        case .wellbeing: return "CFAGoalEndurance"
        }
    }
    static var approvedPresentationOrder: [FitnessGoal] {
        [.fatLoss, .recomposition, .muscleGain, .wellbeing, .maintenance]
    }
}

extension FitnessPace {
    func approvedTitle(_ language: AppLanguage) -> String {
        language.text(self == .gentle ? "تعديل بسيط" : "تعديل أكبر", self == .gentle ? "Smaller adjustment" : "Larger adjustment")
    }
    func approvedSubtitle(_ language: AppLanguage) -> String {
        self == .gentle
            ? language.text("يُجري تعديلاً يومياً أصغر في السعرات الحرارية، ويدعم نهجاً تدريجياً نحو هدفك المختار.", "Makes a smaller daily calorie adjustment and supports a gradual approach toward your selected goal.")
            : language.text("يُجري تعديلاً يومياً أكبر في السعرات الحرارية ضمن حدود هذه الحاسبة. النتائج الفعلية تختلف من شخص لآخر.", "Makes a larger daily calorie adjustment within this estimator’s limits. Actual results vary between people.")
    }
}

enum ApprovedPlanGoals {
    static func minimumCalories(for plan: FitnessPlan) -> Double {
        let productFloor = plan.answers.sex == .male ? 1500.0 : 1200.0
        return ceil(max(plan.bmr, productFloor) / 10) * 10
    }

    /// A deliberate manual target keeps the estimate intact. Macro shares are
    /// preserved; the caller commits the plan and these goals atomically.
    static func scaledGoals(for plan: FitnessPlan, calorieOverride: Double?) throws -> Nutrition {
        guard let calorieOverride else { return plan.goals }
        let minimum=minimumCalories(for:plan)
        guard calorieOverride.isFinite, plan.goals.kcal.isFinite, plan.goals.kcal > 0,
              plan.bmr.isFinite, minimum.isFinite, minimum<=10000,
              (minimum...10000).contains(calorieOverride) else {
            throw AppError.invalid("هدف السعرات خارج نطاق هذه الحاسبة. راجع القيمة قبل الاعتماد.", "The calorie target is outside this estimator’s range. Review it before applying.")
        }
        let goals = plan.goals.scaled(calorieOverride / plan.goals.kcal)
        guard goals.valid else {
            throw AppError.invalid("تعذّر حساب الماكروز لهذا الهدف.", "The macros could not be calculated for this target.")
        }
        return goals
    }
}
