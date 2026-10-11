import Foundation
import XCTest
@testable import LuqmaCore

final class OpenFoodFactsProductTests: XCTestCase {
    private func product(source: String = "packaging", per: String = "100g", unit: String = "g", quantity: Double = 100) -> [String: Any] {
        ["code": "12345678", "product_name": "Milk", "nutrition": ["input_sets": [
            ["source": source, "preparation": "as_sold", "per": per, "per_quantity": quantity, "per_unit": unit,
             "nutrients": ["energy-kcal": ["value": 125, "unit": "kcal"], "proteins": ["value": 2, "unit": "g"],
                           "carbohydrates": ["value": 0, "unit": "g"], "fat": ["value": 3, "unit": "g"]]]]]]
    }

    func testCurrentSchemaKeepsExplicitZeroAndLabelCalories() throws {
        let food = try XCTUnwrap(OpenFoodFactsProduct.parse(product()))
        XCTAssertEqual(food.per100, Nutrition(kcal: 125, protein: 2, carbs: 0, fat: 3))
        XCTAssertTrue(FoodSearch.isOpenFoodFacts(food))
        XCTAssertEqual(food.sourceDescription, "Open Food Facts · packaging · as sold")
    }

    func testServingSetKeepsLiquidBasisWithoutInferringGramDensity() throws {
        let food = try XCTUnwrap(OpenFoodFactsProduct.parse(product(per: "serving", unit: "ml", quantity: 250)))
        XCTAssertEqual(food.unit, .ml)
        XCTAssertEqual(food.servingQuantity, 250)
        XCTAssertEqual(food.serving, "250 ml")
        XCTAssertEqual(food.servingNutrition?.kcal, 125)
        XCTAssertEqual(food.per100?.kcal, 50)
        XCTAssertThrowsError(try food.total(250, unit: .g))
    }

    func testUSDAAndModelEstimateSetsNeverProvideActiveNutrition() throws {
        for source in ["usda", "estimate"] {
            let food = try XCTUnwrap(OpenFoodFactsProduct.parse(product(source: source)))
            XCTAssertNil(food.per100)
            XCTAssertNil(food.servingNutrition)
        }
    }

    func testIncompleteOrBooleanNutrientsAreNotReplacedByZero() throws {
        for bad in [true, "missing"] as [Any] {
            var raw = product()
            var nutrition = raw["nutrition"] as! [String: Any]
            var sets = nutrition["input_sets"] as! [[String: Any]]
            var nutrients = sets[0]["nutrients"] as! [String: Any]
            nutrients["proteins"] = ["value": bad, "unit": "g"]
            sets[0]["nutrients"] = nutrients; nutrition["input_sets"] = sets; raw["nutrition"] = nutrition
            let food = try XCTUnwrap(OpenFoodFactsProduct.parse(raw))
            XCTAssertNil(food.per100)
            XCTAssertNil(food.servingNutrition)
        }
    }

    func testKnownGramNutritionDoesNotInventAMillilitreServing() throws {
        var raw = product(); raw["serving_size"] = "200 ml"
        let food = try XCTUnwrap(OpenFoodFactsProduct.parse(raw))
        XCTAssertEqual(food.unit, .g)
        XCTAssertNil(food.servingNutrition)
        XCTAssertEqual(food.servingUnit, "ml")
    }

    func testSourceFilteringPreservesPrivateFoodsAndOriginalDiaryHistory() throws {
        let off = try XCTUnwrap(OpenFoodFactsProduct.parse(product()))
        var personal = Food(catalogID: "manual:one", name: "My recipe", nutrition: .initial, source: "Your food")
        personal.sourceId = "my-private-id"
        let legacyManual = Food(name: "My old food", nutrition: .initial)
        let oldUSDA = Food(catalogID: "usda:123", name: "Milk", nutrition: .initial, source: "USDA")
        let ai = Food(catalogID: "photo:ai:123", name: "Milk", nutrition: .initial, source: "AI nutrition estimate")
        let candidates = [oldUSDA, ai, off, personal, legacyManual].filter(FoodSearch.availableForAdding)
        XCTAssertEqual(Set(candidates.map(\.id)), Set([off.id, personal.id, legacyManual.id]))
        let entry = DiaryEntry(id: UUID(), day: "2026-10-11", meal: .breakfast, name: oldUSDA.name,
                              amount: 1, unit: .serving, kcal: 123, protein: 2, carbs: 3, fat: 4,
                              barcode: nil, created: nil, foodID: oldUSDA.id, servingLabel: "Old serving")
        var state = DiarySnapshot(); state.entries = [entry]; state.products = [oldUSDA, off]
        XCTAssertTrue(FoodHistory.usage(entries: state.entries, foods: candidates).isEmpty)
        XCTAssertEqual(state.entries, [entry])
        XCTAssertEqual(state.entries[0].kcal, 123)
        XCTAssertEqual(state.products[0], oldUSDA)
    }
}
