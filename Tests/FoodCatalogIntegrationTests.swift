import Foundation
import XCTest
@testable import LuqmaCore

final class FoodCatalogIntegrationTests: XCTestCase {
    private func catalog() throws -> [Food] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try JSONDecoder().decode([Food].self, from: Data(contentsOf: root.appendingPathComponent("Luqma/Resources/foods-data.json")))
    }

    func testRealCatalogDecodesAndEveryNamedPortionKeepsItsSourceWeightAndNutrition() throws {
        let foods = try catalog()
        XCTAssertEqual(foods.count, 13224)
        XCTAssertEqual(Set(foods.map(\.id)).count, foods.count)
        XCTAssertEqual(foods.reduce(0) { $0 + $1.servingChoices.count }, 31253)
        for food in foods {
            XCTAssertNotNil(food.per100, food.id)
            var state = DiarySnapshot(); state.products = [food]
            XCTAssertNoThrow(try DiaryValidation.check(state), food.id)
            for portion in food.servingChoices {
                let selected = try food.selecting(portion)
                XCTAssertEqual(selected.id, food.id)
                let count = try selected.total(0.5, unit: .serving)
                let grams = try selected.total(portion.grams * 0.5, unit: .g)
                XCTAssertEqual(count.kcal, grams.kcal, accuracy: 0.000001)
                XCTAssertEqual(count.protein, grams.protein, accuracy: 0.000001)
                XCTAssertEqual(count.carbs, grams.carbs, accuracy: 0.000001)
                XCTAssertEqual(count.fat, grams.fat, accuracy: 0.000001)
            }
        }
    }

    func testRealCatalogSearchReturnsAllMatchingNamesAliasesAndBrandTokens() throws {
        let foods = try catalog(), index = FoodSearch.Index(foods)
        for query in ["rice", "دجاج", "ارز", "milk", "شاورما", "chicken cooked", "مطبوخ دجاج"] {
            let actual = index.results(query)
            let expected = foods.filter { FoodSearch.matches($0, query: query) }
            XCTAssertEqual(Set(actual.map(\.id)), Set(expected.map(\.id)), query)
            if query != "شاورما" { XCTAssertFalse(actual.isEmpty, query) }
            XCTAssertEqual(actual.count, Set(actual.map(\.id)).count)
            print("CATALOG_SEARCH \(query)=\(actual.count)")
        }
        XCTAssertGreaterThan(index.results("rice").count, 40)
        XCTAssertEqual(Set(index.results("chicken cooked").map(\.id)), Set(index.results("cooked chicken").map(\.id)))
    }
}
