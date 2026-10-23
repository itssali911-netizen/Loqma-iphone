import Foundation

protocol FitnessOption: RawRepresentable, CaseIterable, Identifiable where RawValue == String {
    var labels: (String, String) { get }
}
extension FitnessOption {
    var id: String { rawValue }
    func title(_ language: AppLanguage) -> String { language.text(labels.0, labels.1) }
}

enum FitnessSex: String, Codable, FitnessOption {
    case male, female
    var labels: (String, String) { self == .male ? ("ذكر", "Male") : ("أنثى", "Female") }
}
enum FitnessGoal: String, Codable, FitnessOption {
    case fatLoss, muscleGain, recomposition, maintenance, wellbeing
    var labels: (String, String) {
        switch self {
        case .fatLoss: return ("خسارة الدهون", "Lose fat")
        case .muscleGain: return ("بناء العضلات", "Build muscle")
        case .recomposition: return ("خفض الدهون مع بناء العضلات", "Lose fat and build muscle")
        case .maintenance: return ("المحافظة على الوزن", "Maintain weight")
        case .wellbeing: return ("اللياقة والصحة العامة", "General fitness")
        }
    }
}
enum FitnessPace: String, Codable, FitnessOption {
    case gentle, moderate
    var labels: (String, String) { self == .gentle ? ("تدريجي — تعديل أصغر للسعرات", "Gentle — smaller calorie adjustment") : ("معتدل — تعديل أكبر للسعرات", "Moderate — larger calorie adjustment") }
}
enum FitnessActivity: String, Codable, FitnessOption {
    case sedentary, light, moderate, active, veryActive
    // App-selected categories within NIDDK's typical PAL range, not measured activity.
    var multiplier: Double {
        switch self { case .sedentary: return 1.4; case .light: return 1.6; case .moderate: return 1.8; case .active: return 2; case .veryActive: return 2.2 }
    }
    var labels: (String, String) {
        switch self {
        case .sedentary: return ("أغلب اليوم جلوس وحركة قليلة", "Mostly sitting, little movement")
        case .light: return ("جلوس مع مشي خفيف", "Sitting with some light walking")
        case .moderate: return ("أتحرك وأمشي جزءًا من اليوم", "Moving and walking part of the day")
        case .active: return ("أقف وأتحرك معظم اليوم", "Standing and moving most of the day")
        case .veryActive: return ("عمل بدني شاق أو حركة مكثفة", "Physical work or intensive movement")
        }
    }
}
enum FitnessSafety: String, Codable, FitnessOption {
    case generalAdult, pregnantOrBreastfeeding, medicalDiet
    var labels: (String, String) {
        switch self {
        case .generalAdult: return ("بالغ ولا أحتاج خطة طبية خاصة", "Adult with no specific medical diet")
        case .pregnantOrBreastfeeding: return ("حمل أو رضاعة", "Pregnant or breastfeeding")
        case .medicalDiet: return ("حالة صحية أو خطة غذائية علاجية", "Medical condition or therapeutic diet")
        }
    }
}
enum FitnessExperience: String, Codable, FitnessOption {
    case beginner, intermediate, advanced
    var labels: (String, String) {
        switch self { case .beginner: return ("مبتدئ", "Beginner"); case .intermediate: return ("متوسط", "Intermediate"); case .advanced: return ("متقدم", "Advanced") }
    }
}
enum FitnessTrainingPlace: String, Codable, FitnessOption {
    case home, gym, outdoors
    var labels: (String, String) {
        switch self { case .home: return ("المنزل", "Home"); case .gym: return ("النادي", "Gym"); case .outdoors: return ("الخارج", "Outdoors") }
    }
}
enum FitnessExercise: String, Codable, FitnessOption {
    case walking, strength, cardio, cycling, yoga, swimming
    var labels: (String, String) {
        switch self {
        case .walking: return ("المشي", "Walking")
        case .strength: return ("المقاومة", "Strength")
        case .cardio: return ("الكارديو", "Cardio")
        case .cycling: return ("الدراجة", "Cycling")
        case .yoga: return ("اليوغا والمرونة", "Yoga and mobility")
        case .swimming: return ("السباحة", "Swimming")
        }
    }
}
enum FitnessSleepQuality: String, Codable, FitnessOption {
    case poor, fair, good
    var labels: (String, String) {
        switch self { case .poor: return ("ضعيفة", "Poor"); case .fair: return ("متوسطة", "Fair"); case .good: return ("جيدة", "Good") }
    }
}
enum FitnessDietPreference: String, Codable, FitnessOption {
    case balanced, vegetarian, vegan, pescatarian, halal
    var labels: (String, String) {
        switch self {
        case .balanced: return ("متوازن", "Balanced")
        case .vegetarian: return ("نباتي مع ألبان أو بيض", "Vegetarian")
        case .vegan: return ("نباتي بالكامل", "Vegan")
        case .pescatarian: return ("نباتي مع أسماك", "Pescatarian")
        case .halal: return ("حلال", "Halal")
        }
    }
}
enum FitnessAssessmentStep: String, Codable, FitnessOption {
    case basics, goal, activity, recovery, nutrition, review
    var labels: (String, String) {
        switch self {
        case .basics: return ("عنك", "About you")
        case .goal: return ("هدفك", "Your goal")
        case .activity: return ("نشاطك", "Your activity")
        case .recovery: return ("الاستشفاء", "Recovery")
        case .nutrition: return ("تغذيتك", "Nutrition")
        case .review: return ("المراجعة", "Review")
        }
    }
    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// Stable screen identities keep saved progress independent of the visible
/// question count. The legacy index remains meaningful to earlier app builds.
enum FitnessAssessmentPage: String, Codable, CaseIterable {
    case goal, suitability, sex, age, height, weight, targetPace, activity, training, details, review

    var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    var legacyIndex: Int {
        switch self {
        case .goal: return 0
        case .suitability: return 15
        case .sex: return 1
        case .age: return 2
        case .height: return 3
        case .weight: return 4
        case .targetPace: return 5
        case .activity: return 7
        case .training: return 8
        case .details: return 11
        case .review: return 16
        }
    }
    var group: FitnessAssessmentStep {
        switch self {
        case .goal, .targetPace: return .goal
        case .suitability, .sex, .age, .height, .weight: return .basics
        case .activity, .training: return .activity
        case .details: return .nutrition
        case .review: return .review
        }
    }
    static func fromLegacyIndex(_ index: Int) -> Self {
        switch index {
        case 0: return .goal
        case 1: return .sex
        case 2: return .age
        case 3: return .height
        case 4: return .weight
        case 5, 6: return .targetPace
        case 7: return .activity
        case 8...10: return .training
        case 11...14: return .details
        case 15: return .suitability
        case 16...30: return .review
        default: return .goal
        }
    }
}

/// Form rules are separate from FitnessAnswers' permissive draft validation.
/// Raw text can therefore survive a restart without turning an invalid input
/// into a different accepted value. Clamping is reserved for direct controls.
enum FitnessAssessmentNumberField: String, CaseIterable {
    case age, height, weight, targetWeight, steps, trainingDays, sessionMinutes, sleepHours, meals

    var range: ClosedRange<Double> {
        switch self {
        case .age: return 18...100
        case .height: return 120...230
        case .weight, .targetWeight: return 35...300
        case .steps: return 0...100000
        case .trainingDays: return 0...7
        case .sessionMinutes: return 5...180
        case .sleepHours: return 0...24
        case .meals: return 1...8
        }
    }
    var integer: Bool {
        switch self {
        case .age, .steps, .trainingDays, .sessionMinutes, .meals: return true
        default: return false
        }
    }
    var required: Bool { self == .age || self == .height || self == .weight }
    var step: Double { integer ? 1 : 0.5 }
    var suggestedValue: Double {
        switch self {
        case .age: return 30
        case .height: return 170
        case .weight, .targetWeight: return 70
        case .steps: return 5000
        case .trainingDays: return 3
        case .sessionMinutes: return 30
        case .sleepHours: return 8
        case .meals: return 3
        }
    }
    func parse(_ raw: String) -> Double? {
        let normalized = DisplayFormat.westernDigits(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              normalized.unicodeScalars.allSatisfy({ (48...57).contains($0.value) || $0.value == 46 || $0.value == 44 || $0.value == 0x066B }),
              let number = TextSearch.number(normalized), number.isFinite,
              (!integer || number.rounded() == number), range.contains(number) else { return nil }
        return number
    }
    func validationMessage(for raw: String, language: AppLanguage) -> String? {
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return required ? language.text("أدخل قيمة قبل المتابعة.", "Enter a value before continuing.") : nil
        }
        guard parse(raw) == nil else { return nil }
        let lower = DisplayFormat.decimal(range.lowerBound, digits: 0)
        let upper = DisplayFormat.decimal(range.upperBound, digits: 0)
        return language.text(
            integer ? "أدخل عددًا صحيحًا من \(lower) إلى \(upper)." : "أدخل قيمة من \(lower) إلى \(upper).",
            integer ? "Enter a whole number from \(lower) to \(upper)." : "Enter a value from \(lower) to \(upper).")
    }
    func clampedInteractionValue(_ proposed: Double) -> Double {
        let bounded = min(range.upperBound, max(range.lowerBound, proposed.isFinite ? proposed : suggestedValue))
        return min(range.upperBound, max(range.lowerBound, (bounded / step).rounded() * step))
    }
    func displayText(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        if value == 0 { return "0" }
        if value < 0 { return "-" + displayText(-value) }
        let text = String(value)
        if text.hasSuffix(".0") { return String(text.dropLast(2)) }
        // Double.description preserves the stored value. Expand its rare
        // scientific notation so the result is still editable on a number pad.
        let parts = text.lowercased().split(separator: "e")
        guard parts.count == 2, let exponent = Int(parts[1]) else { return text }
        let coefficient = String(parts[0])
        let digits = coefficient.replacingOccurrences(of: ".", with: "")
        let point = (coefficient.firstIndex(of: ".").map { coefficient.distance(from: coefficient.startIndex, to: $0) } ?? coefficient.count) + exponent
        if point <= 0 { return "0." + String(repeating: "0", count: -point) + digits }
        if point >= digits.count { return digits + String(repeating: "0", count: point - digits.count) }
        let insertion = digits.index(digits.startIndex, offsetBy: point)
        return String(digits[..<insertion]) + "." + String(digits[insertion...])
    }
    func value(in answers: FitnessAnswers) -> Double? {
        switch self {
        case .age: return answers.age.map(Double.init)
        case .height: return answers.heightCM
        case .weight: return answers.weightKG
        case .targetWeight: return answers.targetWeightKG
        case .steps: return answers.stepsPerDay.map(Double.init)
        case .trainingDays: return answers.trainingDays.map(Double.init)
        case .sessionMinutes: return answers.sessionMinutes.map(Double.init)
        case .sleepHours: return answers.sleepHours
        case .meals: return answers.mealsPerDay.map(Double.init)
        }
    }
    func setValue(_ value: Double?, in answers: inout FitnessAnswers) {
        let accepted = value.flatMap { number in
            number.isFinite && range.contains(number) && (!integer || number.rounded() == number) ? number : nil
        }
        switch self {
        case .age: answers.age = accepted.map(Int.init)
        case .height: answers.heightCM = accepted
        case .weight: answers.weightKG = accepted
        case .targetWeight: answers.targetWeightKG = accepted
        case .steps: answers.stepsPerDay = accepted.map(Int.init)
        case .trainingDays: answers.trainingDays = accepted.map(Int.init)
        case .sessionMinutes: answers.sessionMinutes = accepted.map(Int.init)
        case .sleepHours: answers.sleepHours = accepted
        case .meals: answers.mealsPerDay = accepted.map(Int.init)
        }
    }
}

/// Only information needed for a local estimate; no name, email or exact birth date.
struct FitnessAnswers: Codable, Equatable {
    var sex: FitnessSex?
    var age: Int?
    var heightCM: Double?
    var weightKG: Double?
    var targetWeightKG: Double?
    var goal: FitnessGoal?
    var pace: FitnessPace?
    var activity: FitnessActivity?
    var safety: FitnessSafety?
    var stepsPerDay: Int?
    var experience: FitnessExperience?
    var trainingDays: Int?
    var sessionMinutes: Int?
    var trainingPlace: FitnessTrainingPlace?
    var exercise: [FitnessExercise] = []
    var sleepHours: Double?
    var sleepQuality: FitnessSleepQuality?
    var bedtime: String?
    var wakeTime: String?
    var stress: Int?
    var diet: FitnessDietPreference?
    var mealsPerDay: Int?
    var dislikedFoods = ""
    var allergies = ""
    var restrictions = ""

    func validate(complete: Bool = false) throws {
        func require(_ valid: Bool, _ ar: String, _ en: String) throws {
            if !valid { throw AppError.invalid(ar, en) }
        }
        try require(age.map { (0...120).contains($0) } ?? true, "راجع العمر.", "Check your age.")
        try require(heightCM.map { $0.isFinite && (0...260).contains($0) } ?? true, "راجع الطول بالسنتيمتر.", "Check your height in cm.")
        try require([weightKG, targetWeightKG].allSatisfy { $0.map { $0.isFinite && (0...350).contains($0) } ?? true }, "راجع الوزن بالكيلوجرام.", "Check your weight in kg.")
        try require(stepsPerDay.map { (0...100000).contains($0) } ?? true, "راجع متوسط الخطوات.", "Check your daily steps.")
        try require(trainingDays.map { (0...7).contains($0) } ?? true, "اختر من 0 إلى 7 أيام تدريب.", "Choose 0 to 7 training days.")
        try require(sessionMinutes.map { (5...180).contains($0) } ?? true, "اختر مدة من 5 إلى 180 دقيقة.", "Choose 5 to 180 minutes per session.")
        try require(sleepHours.map { $0.isFinite && (0...24).contains($0) } ?? true, "راجع ساعات النوم.", "Check your sleep hours.")
        try require(stress.map { (1...5).contains($0) } ?? true, "اختر مستوى الإجهاد من 1 إلى 5.", "Choose a stress level from 1 to 5.")
        try require(mealsPerDay.map { (1...8).contains($0) } ?? true, "اختر من 1 إلى 8 وجبات.", "Choose 1 to 8 meals.")
        try require([bedtime, wakeTime].allSatisfy { $0.map(Self.validTime) ?? true }, "اكتب الوقت بصيغة HH:mm.", "Use HH:mm for the time.")
        try require(Set(exercise).count == exercise.count && exercise.count <= FitnessExercise.allCases.count && [dislikedFoods, allergies, restrictions].allSatisfy { $0.count <= 1000 }, "اختصر الملاحظات وراجع الاختيارات.", "Shorten the notes and check the selections.")
        if complete {
            try require(sex != nil && goal != nil && activity != nil && safety != nil && age != nil && heightCM != nil && weightKG != nil, "أكمل الجنس المستخدم للحساب والعمر والطول والوزن والهدف والنشاط وسؤال الملاءمة.", "Complete sex used for the equation, age, height, weight, goal, activity and suitability.")
            try require(age.map { (18...100).contains($0) } ?? false, "هذه الحاسبة للبالغين من 18 إلى 100 سنة. يمكنك متابعة تسجيل الطعام بأهدافك الحالية.", "This estimator supports adults aged 18 to 100. You can keep logging food with your current goals.")
            try require(heightCM.map { (120...230).contains($0) } ?? false, "الطول خارج نطاق هذه الحاسبة (120–230 سم).", "Height is outside this estimator's range (120–230 cm).")
            try require(weightKG.map { (35...300).contains($0) } ?? false, "الوزن خارج نطاق هذه الحاسبة (35–300 كجم).", "Weight is outside this estimator's range (35–300 kg).")
            try require(targetWeightKG.map { (35...300).contains($0) } ?? true, "وزن الهدف خارج نطاق هذه الحاسبة.", "Target weight is outside this estimator's range.")
            try require(safety == .generalAdult, "لا تُنشئ هذه الحاسبة خطة للحمل أو الرضاعة أو الحالات والخطط الطبية الخاصة. احتفظ بأهداف يحددها مختص.", "This estimator does not create plans for pregnancy, breastfeeding, or specific medical conditions or diets. Keep goals set with a qualified professional.")
        }
    }
    static func validTime(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        guard bytes.count == 5, bytes[2] == 58, [0,1,3,4].allSatisfy({ (48...57).contains(bytes[$0]) }) else { return false }
        return Int(text.prefix(2)).map { (0...23).contains($0) } == true && Int(text.suffix(2)).map { (0...59).contains($0) } == true
    }
}

struct FitnessAssessmentDraft: Codable, Equatable {
    var answers = FitnessAnswers()
    var step: FitnessAssessmentStep = .basics
    var updatedDay = DayKey.today
    var pageIndex: Int?
    var pageID: String? = nil
    var numericInputs: [String: String]? = nil
    var resolvedPage: FitnessAssessmentPage {
        if let pageID, let page = FitnessAssessmentPage(rawValue: pageID) { return page }
        if let pageIndex { return .fromLegacyIndex(pageIndex) }
        switch step {
        case .goal: return .goal
        case .basics: return .sex
        case .activity: return .activity
        case .recovery, .nutrition: return .details
        case .review: return .review
        }
    }
    func validate() throws {
        try answers.validate()
        guard DayKey.valid(updatedDay), pageIndex.map({ (0...30).contains($0) }) ?? true,
              pageID.map({ $0.count <= 64 }) ?? true,
              numericInputs.map({ inputs in
                  // Loading a future draft preserves its unknown fields and
                  // adds the current controls. Reserve their capacity so that
                  // a readable draft does not become impossible to save.
                  inputs.count <= 32 + FitnessAssessmentNumberField.allCases.count + ApprovedAssessmentMetadata.keys.count &&
                  inputs.keys.filter { FitnessAssessmentNumberField(rawValue: $0) == nil && !ApprovedAssessmentMetadata.keys.contains($0) }.count <= 32 &&
                  inputs.allSatisfy {
                      !$0.key.isEmpty && $0.key.count <= 64 && $0.value.count <= 64
                  }
              }) ?? true else {
            throw AppError.invalid("تعذّر قراءة تقدم التقييم.", "The assessment progress is invalid.")
        }
    }
}
struct FitnessProfile: Codable, Equatable, Identifiable {
    var id = UUID()
    var revision = 1
    var answers: FitnessAnswers
    var updatedDay = DayKey.today
    func validate() throws {
        try answers.validate(complete: true)
        guard (1...1000000).contains(revision), DayKey.valid(updatedDay) else {
            throw AppError.invalid("بيانات الملف الشخصي غير صالحة.", "The fitness profile is invalid.")
        }
    }
}
struct FitnessActivityPlan: Codable, Equatable {
    var trainingDays: Int
    var sessionMinutes: Int
    var weeklyCardioMinutes: Int
    var strengthDays: Int
    var stepsPerDay: Int
    var sleepHours: Double
}
struct FitnessPlan: Codable, Equatable, Identifiable {
    var id = UUID()
    var profileID: UUID
    var profileRevision: Int
    var answers: FitnessAnswers
    var createdDay: String
    var bmr: Double
    var tdee: Double
    var goals: Nutrition
    var energyAdjustment: Double
    var calorieFloorApplied: Bool
    var activity: FitnessActivityPlan
    func validate() throws {
        let profile = FitnessProfile(id: profileID, revision: profileRevision, answers: answers, updatedDay: createdDay)
        let expected = try FitnessEstimator.makePlan(profile: profile, day: createdDay)
        guard [bmr, tdee, energyAdjustment].allSatisfy(\.isFinite), goals.valid,
              abs(bmr - expected.bmr) < 0.000001, abs(tdee - expected.tdee) < 0.000001,
              abs(energyAdjustment - expected.energyAdjustment) < 0.000001,
              goals == expected.goals, calorieFloorApplied == expected.calorieFloorApplied, activity == expected.activity else {
            throw AppError.invalid("الخطة المحفوظة غير صالحة؛ أعد حسابها من إجاباتك.", "The saved fitness plan is invalid. Recalculate it from your answers.")
        }
    }
}

enum FitnessEstimator {
    // Mifflin et al., AJCN 1990, original REE coefficients (a resting estimate, called BMR in the UI):
    // https://pubmed.ncbi.nlm.nih.gov/2305711/ — 9.99*kg + 6.25*cm - 4.92*age + 166*sex - 161.
    // PAL categories / adult exclusions: https://www.niddk.nih.gov/bwp (not the Hall trajectory model).
    // Adult AMDR: https://www.canada.ca/en/health-canada/services/food-nutrition/healthy-eating/dietary-reference-intakes/tables/reference-values-macronutrients.html
    // Activity: https://www.cdc.gov/physical-activity-basics/guidelines/adults.html
    // Sleep: https://www.cdc.gov/sleep/about/index.html
    // Deficit/surplus, category mapping, steps and session suggestions are conservative app heuristics,
    // not clinical prescriptions or promised weight-change rates. Diet/allergy notes do not change the formula.
    static func makePlan(profile: FitnessProfile, day: String = DayKey.today) throws -> FitnessPlan {
        try profile.validate()
        guard DayKey.valid(day), let sex = profile.answers.sex, let age = profile.answers.age,
              let cm = profile.answers.heightCM, let kg = profile.answers.weightKG,
              let goal = profile.answers.goal, let level = profile.answers.activity else {
            throw AppError.invalid("أكمل بيانات التقييم.", "Complete the assessment.")
        }
        let answers = profile.answers, bmi = kg / pow(cm / 100, 2)
        if bmi < 18.5 || answers.targetWeightKG.map({ $0 / pow(cm / 100, 2) < 18.5 }) == true {
            throw AppError.invalid("الوزن الحالي أو المستهدف أقل من نطاق هذه الخطة العامة. استخدم أهدافًا مناسبة مع مختص؛ لم تتغير أهدافك الحالية.", "The current or target weight is below this general planner's supported range. Set suitable goals with a qualified professional; your current goals are unchanged.")
        }
        if let target = answers.targetWeightKG {
            if (goal == .fatLoss && target >= kg) || (goal == .muscleGain && target < kg) {
                throw AppError.invalid("راجع اتجاه وزن الهدف مع الهدف الرياضي أو اتركه فارغًا.", "Check that target weight agrees with your goal, or leave it blank.")
            }
        }
        let bmr = 9.99 * kg + 6.25 * cm - 4.92 * Double(age) + (sex == .male ? 5 : -161)
        let tdee = bmr * level.multiplier
        let gentle = answers.pace != .moderate
        let change: Double
        switch goal {
        case .fatLoss: change = -min(500, tdee * (gentle ? 0.10 : 0.15))
        case .muscleGain: change = min(250, tdee * (gentle ? 0.05 : 0.075))
        case .recomposition, .maintenance, .wellbeing: change = 0
        }
        // This product floor is deliberately conservative, not a universal minimum safe intake.
        let floor = max(bmr, sex == .male ? 1500 : 1200)
        let suggested = tdee + change
        let kcal = max(ceil(floor / 10) * 10, (suggested / 10).rounded() * 10)
        guard bmr > 0, tdee.isFinite, (1200...10000).contains(kcal) else {
            throw AppError.invalid("النتيجة خارج نطاق هذه الحاسبة؛ احتفظ بأهدافك الحالية وراجع مختصًا.", "The estimate is outside this planner's range. Keep your current goals and seek individual advice.")
        }
        let proteinShare = goal == .maintenance || goal == .wellbeing ? 0.20 : 0.25
        let fat = kcal * 0.30 / 9, protein = kcal * proteinShare / 4
        let nutrition = Nutrition(kcal: kcal, protein: protein, carbs: (kcal - protein * 4 - fat * 9) / 4, fat: fat)
        let experience = answers.experience ?? .beginner
        let dayCap = experience == .beginner ? 4 : (experience == .intermediate ? 5 : 6)
        let days = min(dayCap, answers.trainingDays ?? (experience == .beginner ? 2 : 3))
        let session = min(experience == .beginner ? 45 : 90, answers.sessionMinutes ?? 30)
        let starterSteps = answers.stepsPerDay ?? (level == .sedentary ? 3500 : (level == .light ? 5000 : 7500))
        let steps = min(10000, max(3000, starterSteps + (starterSteps < 8000 ? 500 : 0)))
        let activity = FitnessActivityPlan(trainingDays: days, sessionMinutes: session, weeklyCardioMinutes: 150,
                                           strengthDays: min(2, days), stepsPerDay: steps,
                                           sleepHours: min(age >= 65 ? 8 : 9, max(7, answers.sleepHours ?? 8)))
        return FitnessPlan(profileID: profile.id, profileRevision: profile.revision, answers: answers, createdDay: day,
                           bmr: bmr, tdee: tdee, goals: nutrition, energyAdjustment: kcal - tdee,
                           calorieFloorApplied: suggested < floor, activity: activity)
    }
}

/// Snapshot transforms keep persistence transactional in DiaryStore and testable without UIKit.
enum FitnessAssessmentState {
    static func saveDraft(_ draft: FitnessAssessmentDraft, in state: inout DiarySnapshot) throws {
        try draft.validate()
        state.fitnessDraft = draft
        if let proposed = state.proposedFitnessPlan, proposed.answers != draft.answers {
            state.proposedFitnessPlan = nil
        }
    }
    static func preview(_ answers: FitnessAnswers, in state: inout DiarySnapshot, day: String = DayKey.today) throws {
        let old = state.fitnessProfile
        let revision = (old?.revision ?? 0) + (old?.answers == answers ? 0 : 1)
        let profile = FitnessProfile(id: old?.id ?? UUID(), revision: max(1, revision), answers: answers, updatedDay: day)
        let proposal = try FitnessEstimator.makePlan(profile: profile, day: day)
        // Commit nothing if validation/calculation fails.
        state.fitnessProfile = profile
        state.proposedFitnessPlan = proposal
        state.fitnessDraft = FitnessAssessmentDraft(answers: answers, step: .review, updatedDay: day)
        state.fitnessOnboardingDismissed = true
    }
    static func apply(in state: inout DiarySnapshot) throws {
        guard let profile = state.fitnessProfile, let plan = state.proposedFitnessPlan,
              plan.profileID == profile.id, plan.profileRevision == profile.revision, plan.answers == profile.answers,
              state.fitnessDraft.map({ $0.answers == plan.answers }) ?? true else {
            throw AppError.invalid("أنشئ معاينة حديثة للخطة قبل اعتمادها.", "Create an up-to-date plan preview before applying it.")
        }
        try plan.validate()
        state.goals = plan.goals
        state.appliedFitnessPlan = plan
        state.proposedFitnessPlan = nil
        state.fitnessDraft = nil
        state.fitnessOnboardingDismissed = true
        // Keep the saved Hall plan available, but require a fresh opt-in before it can replace these goals.
        state.adaptive = false
    }
    static func deleteProfile(in state: inout DiarySnapshot) {
        state.fitnessDraft = nil
        state.fitnessProfile = nil
        state.proposedFitnessPlan = nil
        state.appliedFitnessPlan = nil
        state.fitnessOnboardingDismissed = true
        // Existing goals and any explicit advanced-plan preference are untouched.
    }
    static func hasAppliedGoals(_ state: DiarySnapshot) -> Bool {
        guard let applied = state.appliedFitnessPlan else { return false }
        return !state.adaptive && state.goals == applied.goals
    }
    static func stageLatestWeight(in state: inout DiarySnapshot, day: String = DayKey.today) {
        guard var profile = state.fitnessProfile,
              let reading = state.weights.filter({ $0.day <= day }).max(by: { $0.day < $1.day }),
              profile.answers.weightKG != reading.kg else { return }
        let previousAnswers = profile.answers
        profile.answers.weightKG = reading.kg
        profile.revision += 1
        profile.updatedDay = day
        // An unsupported new value must never prevent the underlying weight reading from being saved.
        guard (try? profile.validate()) != nil else { return }
        state.fitnessProfile = profile
        state.proposedFitnessPlan = try? FitnessEstimator.makePlan(profile: profile, day: day)
        if state.fitnessDraft == nil || state.fitnessDraft?.answers == previousAnswers {
            state.fitnessDraft = FitnessAssessmentDraft(answers: profile.answers, step: .review, updatedDay: day)
        }
    }
    static func validate(_ state: DiarySnapshot) throws {
        try state.fitnessDraft?.validate()
        try state.fitnessProfile?.validate()
        try state.proposedFitnessPlan?.validate()
        try state.appliedFitnessPlan?.validate()
        if let proposed = state.proposedFitnessPlan {
            guard let profile = state.fitnessProfile, proposed.profileID == profile.id,
                  proposed.profileRevision == profile.revision, proposed.answers == profile.answers else {
                throw AppError.invalid("معاينة الخطة لا تطابق الملف الشخصي.", "The plan preview does not match the fitness profile.")
            }
        }
        if let applied = state.appliedFitnessPlan {
            guard let profile = state.fitnessProfile, applied.profileID == profile.id, applied.profileRevision <= profile.revision else {
                throw AppError.invalid("مرجع الخطة المعتمدة غير صالح.", "The applied plan reference is invalid.")
            }
        }
    }
}
