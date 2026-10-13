import Foundation
import XCTest
@testable import LuqmaCore

final class PhotoEstimatePersistenceTests: XCTestCase {
    private let identity = UUID(uuidString: "20261012-1111-4111-8111-123456789abc")!
    private func estimate(nutrition: Nutrition = Nutrition(kcal: 300, protein: 20, carbs: 40, fat: 8)) throws -> MealPhotoEstimate {
        try MealPhotoEstimate(grams: 200, low: 150, high: 250, nutrition: nutrition,
                              kcalLow: nutrition.kcal * 0.8, kcalHigh: nutrition.kcal * 1.2,
                              assumptions: "كمية الزيت غير واضحة", assumptionsEn: "The amount of oil is unclear")
    }
    private func food() throws -> Food {
        try estimate().food(name: "وجبة أرز", nameEn: "Rice meal", identity: identity, language: .en)
    }

    func testPhotoEstimateSurvivesCacheEvictionAndCanBeReusedFromRecentHistory() throws {
        let original = try food()
        var state = DiarySnapshot()
        state.entries = [try DiaryEntry(food: original, amount: 1, unit: .serving, meal: .lunch, day: "2026-10-12", language: .en)]
        try FoodHistory.remember(original, in: &state, barcode: false)
        // Real cache inserts evict the initial item from both bounded caches.
        for index in 0..<1000 {
            try FoodHistory.remember(Food(catalogID: "cache:\(index)", name: "Product \(index)"), in: &state, barcode: false)
        }
        XCTAssertFalse(state.products.contains { $0.id == original.id })
        XCTAssertFalse(state.searchHistory.contains { $0.id == original.id })
        XCTAssertEqual(state.customFoods?.first?.source, MealPhotoEstimate.source)
        XCTAssertEqual(state.customFoods?.first?.id, original.id)
        let restored = try Backup.decode(Backup.encode(state))
        let lists = FoodHistory.lists(in: restored)
        let recent = try XCTUnwrap(lists.recent.first)
        XCTAssertEqual(recent.id, original.id)
        XCTAssertEqual(recent.source, MealPhotoEstimate.source)
        XCTAssertEqual(lists.personal.first?.id, original.id)
        XCTAssertTrue(FoodSearch.availableForAdding(recent))
        XCTAssertFalse(FoodSearch.isCatalogFood(recent))
        let reused = try DiaryEntry(food: recent, amount: 0.5, unit: .serving, meal: .dinner, day: "2026-10-12", language: .ar)
        XCTAssertEqual(reused.kcal, 150, accuracy: 0.000001)
        XCTAssertEqual(reused.foodID, original.id)
    }

    func testCorrectedEstimateMetadataAndIdentityRoundTripWithoutChangingOldDiaryTotals() throws {
        let initial = try food()
        let correctedNutrition = Nutrition(kcal: 350, protein: 25, carbs: 45, fat: 8)
        let corrected = try estimate(nutrition: correctedNutrition).food(name: initial.name, nameEn: initial.nameEn, identity: identity, language: .en)
        var state = DiarySnapshot()
        state.entries = [try DiaryEntry(food: initial, amount: 1, unit: .serving, meal: .lunch, day: "2026-10-12", language: .en)]
        try FoodHistory.remember(initial, in: &state, barcode: false)
        try FoodHistory.remember(corrected, in: &state, barcode: false)
        let restored = try Backup.decode(Backup.encode(state))
        XCTAssertEqual(restored.customFoods?.count, 1)
        let saved = try XCTUnwrap(restored.customFoods?.first)
        XCTAssertEqual(saved.id, initial.id)
        XCTAssertEqual(saved.source, MealPhotoEstimate.source)
        XCTAssertEqual(saved.sourceDescription, corrected.sourceDescription)
        XCTAssertTrue(MealPhotoEstimate.isValidPhotoEstimate(saved))
        XCTAssertEqual(try saved.total(1, unit: .serving), correctedNutrition)
        XCTAssertEqual(restored.entries.first?.kcal, 300)
        XCTAssertEqual(FoodHistory.lists(in: restored).recent.first?.kcal, 350)
    }

    func testMalformedPhotoSourcesAreRejectedInEveryBackupCollection() throws {
        let original = try food()
        var invalid = original
        invalid.sourceDescription = "not-estimate-metadata"
        XCTAssertFalse(MealPhotoEstimate.isValidPhotoEstimate(invalid))
        XCTAssertFalse(FoodSearch.availableForAdding(invalid))
        for collection in 0..<4 {
            var state = DiarySnapshot()
            switch collection {
            case 0: state.products = [invalid]
            case 1: state.searchHistory = [invalid]
            case 2: state.barcodeHistory = [invalid]
            default: state.customFoods = [invalid]
            }
            XCTAssertThrowsError(try Backup.encode(state), "Collection \(collection)")
            // Bypass the writer to exercise validation of imported JSON too.
            let data = try JSONEncoder().encode(state)
            XCTAssertThrowsError(try Backup.decode(data), "Collection \(collection)")
            XCTAssertTrue(FoodHistory.yourFoods(in: state).isEmpty)
            XCTAssertTrue(FoodHistory.candidates(in: state).isEmpty)
        }
    }

    func testPhotoSourceAndIdentitySpoofsCannotBeRememberedOrAcceptedAsCatalogFoods() throws {
        let original = try food()
        var wrongID = original; wrongID.catalogID = "off:" + (original.sourceId ?? "")
        var wrongQuantity = original; wrongQuantity.servingQuantity = 500
        var wrongNutrition = original; wrongNutrition.kcal = 1
        var branded = original; branded.brand = "Pretend verified brand"
        var barcode = original; barcode.barcode = "12345678"
        for invalid in [wrongID, wrongQuantity, wrongNutrition, branded, barcode] {
            var state = DiarySnapshot(); state.customFoods = [original]
            let before = try Backup.encode(state)
            XCTAssertFalse(FoodSearch.availableForAdding(invalid))
            XCTAssertFalse(FoodSearch.isCatalogFood(invalid))
            XCTAssertThrowsError(try FoodHistory.remember(invalid, in: &state, barcode: false))
            XCTAssertEqual(try Backup.encode(state), before)
        }
        var sourceSpoof = original; sourceSpoof.source = "OpenFoodFacts"
        XCTAssertFalse(FoodSearch.isOpenFoodFacts(sourceSpoof))
        XCTAssertFalse(FoodSearch.availableForAdding(sourceSpoof))
    }

    func testFullPrivateCollectionRejectsNewEstimateAtomicallyAndAllowsExistingEstimateUpdates() throws {
        let original = try food()
        var state = DiarySnapshot()
        state.customFoods = [original] + (0..<999).map { Food(catalogID: "personal:\($0)", name: "Food \($0)", source: "Your food") }
        let before = try Backup.encode(state)
        let extra = try estimate().food(name: "وجبة جديدة", identity: UUID())
        XCTAssertThrowsError(try FoodHistory.remember(extra, in: &state, barcode: false))
        XCTAssertEqual(try Backup.encode(state), before)
        let edited = try estimate().scaled(toGrams: 250).food(name: original.name, identity: identity, language: .en)
        XCTAssertNoThrow(try FoodHistory.remember(edited, in: &state, barcode: false))
        XCTAssertEqual(state.customFoods?.count, 1000)
        XCTAssertEqual(state.customFoods?.last?.id, original.id)
        XCTAssertEqual(state.customFoods?.last?.kcal, 375)
        XCTAssertNoThrow(try Backup.encode(state))
    }
}
