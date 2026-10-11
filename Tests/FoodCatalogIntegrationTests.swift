import Foundation
import XCTest
@testable import LuqmaCore

final class FoodCatalogIntegrationTests: XCTestCase {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent() }
    private func catalog() throws -> [Food] {
        try JSONDecoder().decode([Food].self, from: Data(contentsOf: root.appendingPathComponent("Luqma/Resources/foods-data.json")))
    }

    func testRealOFFCatalogDecodesAndKeepsDeclaredServingsWithoutUnitConversion() throws {
        let foods = try catalog()
        XCTAssertEqual(foods.count, 6)
        XCTAssertEqual(Set(foods.map(\.id)).count, foods.count)
        XCTAssertEqual(foods.filter { $0.servingNutrition != nil }.count, 5)
        for food in foods {
            XCTAssertTrue(FoodSearch.isOpenFoodFacts(food), food.id)
            XCTAssertNotNil(food.per100, food.id)
            var state = DiarySnapshot(); state.products = [food]
            XCTAssertNoThrow(try DiaryValidation.check(state), food.id)
            if let serving = food.servingNutrition {
                let half = try food.total(0.5, unit: .serving)
                XCTAssertEqual(half.kcal, serving.kcal / 2, accuracy: 0.000001)
                XCTAssertEqual(half.protein, serving.protein / 2, accuracy: 0.000001)
            }
        }
        let milk = try XCTUnwrap(foods.first { $0.sourceId == "6281007032261" })
        XCTAssertEqual(milk.unit, .ml)
        XCTAssertEqual(milk.servingQuantity, 250)
        XCTAssertEqual(try milk.total(1, unit: .serving).kcal, 155)
        XCTAssertThrowsError(try milk.total(250, unit: .g))
    }

    func testAllPinnedSourceResponsesMatchTheNativeParserAndSeedSearch() throws {
        let foods = try catalog()
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Scripts/Data/off-products-snapshot.json"))) as! [String: Any]
        for row in raw["responses"] as! [[String: Any]] where row["included"] as? Bool == true {
            let response = try JSONSerialization.jsonObject(with: Data((row["raw"] as! String).utf8)) as! [String: Any]
            let parsed = try XCTUnwrap(OpenFoodFactsProduct.parse(response["product"] as! [String: Any]))
            XCTAssertEqual(parsed, foods.first { $0.id == parsed.id }, parsed.id)
        }
        let index = FoodSearch.Index(foods)
        for query in ["milk", "حليب", "Almarai", "nutella", "pesto"] {
            let actual = index.results(query)
            XCTAssertEqual(Set(actual.map(\.id)), Set(foods.filter { FoodSearch.matches($0, query: query) }.map(\.id)), query)
            XCTAssertFalse(actual.isEmpty, query)
            print("OFF_CATALOG_SEARCH \(query)=\(actual.count)")
        }
    }
}
