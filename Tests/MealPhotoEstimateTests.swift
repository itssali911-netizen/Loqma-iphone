import XCTest
@testable import LuqmaCore

final class MealPhotoEstimateTests: XCTestCase {
    private func estimate(grams: Double = 100, low: Double = 75, high: Double = 140,
                          nutrition: Nutrition = Nutrition(kcal: 150, protein: 5, carbs: 25, fat: 3),
                          kcalLow: Double = 110, kcalHigh: Double = 210) throws -> MealPhotoEstimate {
        try MealPhotoEstimate(grams: grams, low: low, high: high, nutrition: nutrition, kcalLow: kcalLow, kcalHigh: kcalHigh,
            assumptions: "كمية مطبوخة تقريبية؛ الزيت غير واضح.", assumptionsEn: "Approximate cooked portion; oil is unclear.")
    }

    func testEstimateScalingKeepsPortionCaloriesAndBoundsTogether() throws {
        let value = try estimate()
        let half = try value.scaled(toGrams: 50)
        XCTAssertEqual(half.nutrition.kcal, 75)
        XCTAssertEqual(half.nutrition.protein, 2.5)
        XCTAssertEqual(half.kcalLow, 55)
        XCTAssertEqual(half.kcalHigh, 105)
        XCTAssertEqual(half.low, 37.5)
        XCTAssertEqual(half.high, 70)
        XCTAssertEqual(try value.scaled(toGrams: 1).nutrition.kcal, 1.5)
        for grams in [0.0, -5, 3001, .infinity, .nan] { XCTAssertThrowsError(try value.scaled(toGrams: grams)) }
        let boundary = try estimate(kcalLow: 137.5, kcalHigh: 160)
        for grams in [1.0, 1.03, 1.09, 13.57, 75.43, 2005.5] {
            XCTAssertTrue(try boundary.scaled(toGrams: grams).valid)
        }
    }

    func testAggregatesReviewedComponentsWithoutDoubleScaling() throws {
        let total = try MealPhotoEstimate.total([estimate(), estimate().scaled(toGrams: 50)])
        XCTAssertEqual(total.nutrition.kcal, 225)
        XCTAssertEqual(total.nutrition.protein, 7.5)
        XCTAssertEqual(total.nutrition.carbs, 37.5)
        XCTAssertEqual(total.kcalLow, 165)
        XCTAssertEqual(total.kcalHigh, 315)
        XCTAssertEqual(total.grams, 150)
        XCTAssertThrowsError(try MealPhotoEstimate.total([]))
        XCTAssertThrowsError(try MealPhotoEstimate.total(Array(repeating: estimate(), count: 13)))
    }

    func testGeneratedFoodHasDistinctValidatedEstimatedServingIdentity() throws {
        let value = try estimate()
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let food = try value.food(name: "خبز تقديري", nameEn: "Estimated bread", identity: id)
        XCTAssertEqual(food.catalogID, "photo-estimate:" + id.uuidString.lowercased())
        XCTAssertEqual(food.unit, .serving)
        XCTAssertTrue(MealPhotoEstimate.isValidPhotoEstimate(food))
        XCTAssertFalse(FoodSearch.isCatalogFood(food))
        XCTAssertEqual(try food.total(1, unit: .serving).kcal, 150)
        XCTAssertEqual(try food.total(2, unit: .serving).kcal, 300)
        let entry = try DiaryEntry(food: food, amount: 1, unit: .serving, meal: .lunch, day: "2026-10-12", language: .ar)
        XCTAssertEqual(entry.kcal, 150)
        var snapshot = DiarySnapshot(); snapshot.entries = [entry]; snapshot.products = [food]
        let restored = try Backup.decode(Backup.encode(snapshot))
        XCTAssertTrue(MealPhotoEstimate.isValidPhotoEstimate(restored.products[0]))
        XCTAssertEqual(restored.entries[0].foodID, food.id)
    }

    func testSourceOnlyOrTamperedEstimatedFoodIsNotAccepted() throws {
        let valid = try estimate().food(name: "Bread")
        var changed = valid; changed.sourceDescription = nil
        XCTAssertFalse(MealPhotoEstimate.isValidPhotoEstimate(changed))
        changed = valid; changed.servingNutrition?.kcal = 500
        XCTAssertFalse(MealPhotoEstimate.isValidPhotoEstimate(changed))
        changed = valid; changed.kcal = nil
        XCTAssertFalse(MealPhotoEstimate.isValidPhotoEstimate(changed))
        changed = valid; changed.unit = .g
        XCTAssertFalse(MealPhotoEstimate.isValidPhotoEstimate(changed))
        changed = valid; changed.barcode = "12345678"
        XCTAssertFalse(MealPhotoEstimate.isValidPhotoEstimate(changed))
        changed = valid; changed.sourceId = UUID().uuidString
        XCTAssertFalse(MealPhotoEstimate.isValidPhotoEstimate(changed))
        let spoof = Food(name: "Food", unit: .serving, nutrition: .zero, source: "Photo estimate")
        XCTAssertFalse(MealPhotoEstimate.isValidPhotoEstimate(spoof))
    }

    func testRejectsImpossibleMacroMassDensityAndEnergyOrExactClaim() throws {
        XCTAssertThrowsError(try estimate(nutrition: Nutrition(kcal: 150, protein: 100, carbs: 100, fat: 0)))
        XCTAssertThrowsError(try estimate(grams: 10, low: 5, high: 15, nutrition: Nutrition(kcal: 500, protein: 0, carbs: 0, fat: 55), kcalLow: 400, kcalHigh: 600))
        XCTAssertThrowsError(try estimate(nutrition: Nutrition(kcal: 500, protein: 0, carbs: 0, fat: 0), kcalLow: 300, kcalHigh: 700))
        XCTAssertThrowsError(try estimate(kcalLow: 150, kcalHigh: 150))
        XCTAssertThrowsError(try estimate(kcalHigh: 2000))
        XCTAssertThrowsError(try estimate(nutrition: Nutrition(kcal: .nan, protein: 5, carbs: 25, fat: 3)))
    }

    func testPhotoPartQuantityEditUpdatesSeparateEstimateWithoutChangingLegacyParts() throws {
        let value = try estimate()
        let n = value.nutrition
        let label = PhotoFood(id: "ai:gemini:0", name: "خبز", nameEn: "Bread", grams: 100, kcal: n.kcal, protein: n.protein, carbs: n.carbs, fat: n.fat)
        var part = PhotoPart(food: label, grams: 100, low: 75, high: 140, basis: "photo-estimate", tentative: true, mealEstimate: value)
        part.setGrams(200)
        XCTAssertEqual(part.nutrition.kcal, 300)
        XCTAssertEqual(part.mealEstimate?.nutrition.kcal, 300)
        XCTAssertEqual(part.mealEstimate?.kcalLow, 220)
        part.setGrams(-1)
        XCTAssertEqual(part.grams, 200)
        var legacy = PhotoPart(food: label, grams: 100, low: 75, high: 140, basis: "reference")
        legacy.setGrams(50)
        XCTAssertNil(legacy.mealEstimate)
        XCTAssertEqual(legacy.nutrition.kcal, 75)
    }

    func testReviewedNutritionCorrectionKeepsSameFoodIdentityAndUpdatesMetadata() throws {
        let food = try estimate().food(name: "Bread", language: .en)
        let correction = Nutrition(kcal: 180, protein: 6, carbs: 30, fat: 4)
        let changed = try MealPhotoEstimate.correctedFood(food, nutrition: correction)
        XCTAssertTrue(MealPhotoEstimate.isValidPhotoEstimate(changed))
        XCTAssertEqual(changed.id, food.id)
        XCTAssertEqual(changed.sourceId, food.sourceId)
        XCTAssertEqual(changed.serving, food.serving)
        XCTAssertEqual(changed.servingQuantity, food.servingQuantity)
        XCTAssertEqual(try changed.total(1, unit: .serving), correction)
        let estimate = try self.estimate().correcting(correction)
        XCTAssertEqual(estimate.kcalLow, 132)
        XCTAssertEqual(estimate.kcalHigh, 252)
        XCTAssertTrue(estimate.assumptionsEn.contains("adjusted by you"))
        var wrongBasis = food; wrongBasis.unit = .g
        XCTAssertThrowsError(try MealPhotoEstimate.correctedFood(wrongBasis, nutrition: correction))
    }

    func testCorrectionFromAndToZeroDoesNotInventOrLoseMacros() throws {
        let water = try estimate(nutrition: .zero, kcalLow: 0, kcalHigh: 0)
        let changed = try water.correcting(Nutrition(kcal: 50, protein: 0, carbs: 12, fat: 0))
        XCTAssertEqual(changed.kcalLow, 40)
        XCTAssertEqual(changed.kcalHigh, 60)
        XCTAssertEqual(try estimate().correcting(.zero).nutrition, .zero)
        XCTAssertThrowsError(try estimate().correcting(Nutrition(kcal: 0, protein: 0, carbs: 0, fat: 5)))
        XCTAssertThrowsError(try estimate().correcting(Nutrition(kcal: 2000, protein: 0, carbs: 0, fat: 200)))
    }
}
