import Foundation

/// Nutrition describes this estimated edible portion, never a verified product.
/// These checks catch malformed estimates; they cannot establish photo accuracy.
struct MealPhotoEstimate: Codable, Equatable {
    static let source = "Photo estimate"
    private static let metadataPrefix = "luqma-photo-estimate-v1:"
    let grams: Double
    let low: Double
    let high: Double
    let nutrition: Nutrition
    let kcalLow: Double
    let kcalHigh: Double
    let assumptions: String
    let assumptionsEn: String

    init(grams: Double, low: Double, high: Double, nutrition: Nutrition, kcalLow: Double, kcalHigh: Double, assumptions: String, assumptionsEn: String) throws {
        self.grams = grams; self.low = low; self.high = high
        self.nutrition = nutrition; self.kcalLow = kcalLow; self.kcalHigh = kcalHigh
        self.assumptions = assumptions.trimmingCharacters(in: .whitespacesAndNewlines)
        self.assumptionsEn = assumptionsEn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard valid else { throw Self.invalid }
    }

    var valid: Bool {
        guard [grams, low, high].allSatisfy({ $0.isFinite && $0 >= 1 && $0 <= 3000 }), low <= grams, grams <= high,
              nutrition.valid, nutrition.kcal <= 27000,
              [nutrition.protein, nutrition.carbs, nutrition.fat].allSatisfy({ $0 <= 3000 }),
              [kcalLow, kcalHigh].allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 36000 }),
              kcalLow <= nutrition.kcal, nutrition.kcal <= kcalHigh,
              Self.validText(assumptions), Self.validText(assumptionsEn) else { return false }
        // Water and fibre mean gram weights cannot uniquely determine nutrition.
        // Allow rounding and label-energy differences, but reject impossible density.
        let macroMass = nutrition.protein + nutrition.carbs + nutrition.fat
        guard macroMass <= grams * 1.05 + 3, nutrition.kcal <= grams * 9.5 + 20, kcalHigh <= high * 9.5 + 30 else { return false }
        let tolerance = max(60, nutrition.kcal * 0.30)
        guard abs(nutrition.kcal - nutrition.macroCalories) <= tolerance,
              nutrition.kcal != 0 || nutrition.macroCalories <= 5 else { return false }
        // Positive calorie estimates must include meaningful uncertainty.
        return nutrition.kcal == 0 || kcalHigh - kcalLow + max(1e-8, nutrition.kcal * 1e-10) >= nutrition.kcal * 0.15
    }

    func scaled(toGrams value: Double) throws -> MealPhotoEstimate {
        guard valid, value.isFinite, value >= 1, value <= 3000 else { throw Self.invalid }
        let ratio = value / grams
        return try MealPhotoEstimate(grams: value, low: min(value, max(1, low * ratio)), high: min(3000, max(value, high * ratio)),
            nutrition: nutrition.scaled(ratio), kcalLow: kcalLow * ratio, kcalHigh: kcalHigh * ratio,
            assumptions: assumptions, assumptionsEn: assumptionsEn)
    }

    func combining(_ other: MealPhotoEstimate) throws -> MealPhotoEstimate {
        guard valid, other.valid else { throw Self.invalid }
        return try MealPhotoEstimate(grams: grams + other.grams, low: low + other.low, high: high + other.high,
            nutrition: nutrition + other.nutrition, kcalLow: kcalLow + other.kcalLow, kcalHigh: kcalHigh + other.kcalHigh,
            assumptions: combinedText(assumptions, other.assumptions), assumptionsEn: combinedText(assumptionsEn, other.assumptionsEn))
    }

    func correcting(_ value: Nutrition) throws -> MealPhotoEstimate {
        guard valid, value.valid else { throw Self.invalid }
        let correctedLow: Double, correctedHigh: Double
        if value.kcal == 0 {
            correctedLow = 0; correctedHigh = 0
        } else if nutrition.kcal > 0 {
            let ratio = value.kcal / nutrition.kcal
            correctedLow = kcalLow * ratio; correctedHigh = kcalHigh * ratio
        } else {
            correctedLow = value.kcal * 0.8; correctedHigh = value.kcal * 1.2
        }
        return try MealPhotoEstimate(grams: grams, low: low, high: high, nutrition: value,
            kcalLow: correctedLow, kcalHigh: correctedHigh,
            assumptions: String(("القيم معدّلة يدويًا؛ " + assumptions).prefix(240)),
            assumptionsEn: String(("Values adjusted by you; " + assumptionsEn).prefix(240)))
    }

    static func correctedFood(_ food: Food, nutrition: Nutrition, language: AppLanguage? = nil) throws -> Food {
        guard isValidPhotoEstimate(food), let identifier = food.sourceId, let identity = UUID(uuidString: identifier),
              let metadata = food.sourceDescription,
              let data = Data(base64Encoded: String(metadata.dropFirst(metadataPrefix.count))) else { throw invalid }
        let estimate = try JSONDecoder().decode(Self.self, from: data)
        let corrected = try estimate.correcting(nutrition)
        let labelLanguage = language ?? (food.serving == "Estimated portion" ? .en : .ar)
        return try corrected.food(name: food.name, nameEn: food.nameEn, identity: identity, language: labelLanguage)
    }

    static func total(_ values: [MealPhotoEstimate]) throws -> MealPhotoEstimateTotal {
        guard !values.isEmpty, values.count <= 12, values.allSatisfy(\.valid) else { throw invalid }
        let nutrition = values.reduce(Nutrition.zero) { $0 + $1.nutrition }
        let low = values.reduce(0) { $0 + $1.kcalLow }, high = values.reduce(0) { $0 + $1.kcalHigh }
        let grams = values.reduce(0) { $0 + $1.grams }, weightHigh = values.reduce(0) { $0 + $1.high }
        // Whole-image limits are 60,000 kcal centrally, 80,000 kcal upper bound,
        // and 10,000 g total upper weight; individual components stay narrower.
        guard nutrition.valid, nutrition.kcal <= 60000, high.isFinite, high <= 80000,
              grams.isFinite, grams <= 10000, weightHigh <= 10000 else { throw invalid }
        return MealPhotoEstimateTotal(nutrition: nutrition, kcalLow: low, kcalHigh: high, grams: grams)
    }

    func food(name: String, nameEn: String? = nil, identity: UUID = UUID(), language: AppLanguage = .ar) throws -> Food {
        guard valid, Self.validName(name), nameEn.map(Self.validName) ?? true else { throw Self.invalid }
        let identifier = identity.uuidString.lowercased()
        var result = Food(catalogID: "photo-estimate:" + identifier, name: name, nameEn: nameEn,
            unit: .serving, nutrition: nutrition, serving: language.text("حصة تقديرية", "Estimated portion"),
            servingQuantity: grams, servingUnit: "g", servingNutrition: nutrition, source: Self.source)
        result.sourceId = identifier
        result.sourceDescription = Self.metadataPrefix + (try JSONEncoder().encode(self)).base64EncodedString()
        return result
    }

    static func isValidPhotoEstimate(_ food: Food) -> Bool {
        guard food.source == source, food.unit == .serving, food.barcode == nil, food.brand == nil,
              food.servings?.isEmpty ?? true, food.portions?.isEmpty ?? true, food.selectedPortionID == nil,
              validName(food.name), food.nameEn.map(validName) ?? true,
              let identifier = food.sourceId, UUID(uuidString: identifier) != nil,
              food.catalogID == "photo-estimate:" + identifier,
              ["حصة تقديرية", "Estimated portion"].contains(food.serving ?? ""), food.servingUnit == "g",
              let metadata = food.sourceDescription, metadata.count <= 4096, metadata.hasPrefix(metadataPrefix),
              let data = Data(base64Encoded: String(metadata.dropFirst(metadataPrefix.count))), data.count <= 3000,
              let estimate = try? JSONDecoder().decode(Self.self, from: data), estimate.valid,
              food.servingQuantity == estimate.grams, food.servingNutrition == estimate.nutrition,
              food.per100 == estimate.nutrition else { return false }
        return true
    }

    private func combinedText(_ a: String, _ b: String) -> String {
        a == b ? a : String((a + " / " + b).prefix(240))
    }
    private static func validText(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 240 && text.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
    private static func validName(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= 120 && text.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
    private static var invalid: AppError {
        .invalid("راجع تقدير الكمية والقيم الغذائية قبل حفظ الوجبة.", "Review the estimated amount and nutrition before saving the meal.")
    }
}

struct MealPhotoEstimateTotal: Equatable {
    let nutrition: Nutrition
    let kcalLow: Double
    let kcalHigh: Double
    let grams: Double
}
