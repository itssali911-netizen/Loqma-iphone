import Foundation
import XCTest
@testable import LuqmaCore

final class FoodSearchAccuracyTests: XCTestCase {
    private func product(_ id: String, _ name: String, brand: String? = nil) -> Food {
        var value = Food(catalogID: "off:" + id, name: name, brand: brand, source: "OpenFoodFacts")
        value.sourceId = id
        return value
    }

    func testTanmiahArabicSpellingWordOrderAndChickenBreastPluralKeepTheSameRecord() {
        let breast = product("breast", "صدور دجاج", brand: "التنمية")
        let other = product("other", "صدور دجاج", brand: "علامة أخرى")
        let index = FoodSearch.Index([other, breast])
        for query in ["التنمية صدر دجاج", "التنميه صدر دجاج", "دجاج صدر التنميه",
                      "صدر دجاج تنمية", "Tanmiah chicken breast", "التَّنْمِيَة صدور الدجاج"] {
            XCTAssertEqual(index.results(query).map(\.id), [breast.id], query)
        }
        XCTAssertEqual(breast.name, "صدور دجاج")
        XCTAssertEqual(breast.brand, "التنمية")
        XCTAssertNil(breast.per100)
    }

    func testNearbyBreastIsSeparateWhenRequestedBrandIsAbsent() {
        let breast = product("generic", "صدر دجاج مشوي", brand: "Home")
        let milk = product("milk", "حليب كامل الدسم", brand: "التنمية")
        let found = FoodSearch.Index([milk, breast]).matches("التنمية صدر دجاج")
        XCTAssertTrue(found.exact.isEmpty)
        XCTAssertEqual(found.nearby.map(\.id), [breast.id])
        XCTAssertEqual(found.nearby[0].brand, "Home")
        XCTAssertNil(found.nearby[0].per100)
        XCTAssertThrowsError(try found.nearby[0].total(1, unit: .serving))
    }

    func testSingleEditAndTransposedLettersAreNearbyWithoutPollutingExactResults() {
        let breast = product("breast", "Chicken breast", brand: "Tanmiah")
        let index = FoodSearch.Index([breast, product("rice", "Rice")])
        for query in ["chiken breast", "chikcen breast", "chickenn breast"] {
            let found = index.matches(query)
            XCTAssertTrue(found.exact.isEmpty, query)
            XCTAssertEqual(found.nearby.map(\.id), [breast.id], query)
        }
        XCTAssertTrue(index.matches("zxqv").nearby.isEmpty)
        XCTAssertTrue(index.matches("12").nearby.isEmpty)
        XCTAssertTrue(index.matches("milk chocolate").nearby.isEmpty)
    }

    func testExactProductsRemainUncappedAndNearbyRowsAreDistinctBoundedAndStable() {
        let exact = product("exact", "صدر دجاج", brand: "التنمية")
        let partial = (0..<35).map { product("partial-\($0)", "صدر دجاج \($0)", brand: "Home") }
        let index = FoodSearch.Index([exact] + partial + [exact])
        let result = index.matches("التنمية صدر دجاج", nearbyLimit: 7)
        XCTAssertEqual(result.exact.map(\.id), [exact.id])
        XCTAssertEqual(result.nearby.count, 7)
        XCTAssertFalse(result.nearby.contains { $0.id == exact.id })
        XCTAssertEqual(result.nearby.map(\.id), FoodSearch.Index(Array(([exact] + partial).reversed())).matches("التنمية صدر دجاج", nearbyLimit: 7).nearby.map(\.id))
        XCTAssertEqual(index.results("صدر دجاج").count, 36)
        XCTAssertTrue(index.matches("", nearbyLimit: 7).nearby.isEmpty)
    }

    func testRemoteQueriesPreserveArabicTaMarbutaAndOnlyKnownBrandVariantsBroaden() {
        XCTAssertEqual(FoodSearch.onlineQueries("  جبنة  قريش "), ["جبنة قريش"])
        XCTAssertEqual(FoodSearch.onlineQueries("التنمية صدر دجاج"), ["التنمية صدر دجاج", "التنمية", "Tanmiah"])
        XCTAssertEqual(FoodSearch.onlineQueries("التنميه صدر دجاج"), ["التنميه صدر دجاج", "التنمية صدر دجاج", "التنمية", "Tanmiah"])
        XCTAssertTrue(FoodSearch.onlineQueries("   ").isEmpty)
    }

    func testPreparedSuggestionIndexMatchesPublicWrapperAndNeverSuggestsFalseBrand() {
        let breast = product("breast", "صدور دجاج", brand: "التنمية")
        let other = product("other", "صدر دجاج مشوي", brand: "Home")
        let values = [other, breast]
        let prepared = FoodSuggestions.Index(values)
        for language in AppLanguage.allCases {
            for query in ["", "صدر", "التنميه صدر", "Tanmiah chicken", "غير موجود"] {
                let actual = prepared.suggestions(query: query, language: language)
                XCTAssertEqual(actual, FoodSuggestions.suggestions(query: query, foods: values, language: language))
            }
        }
        let suggestions = prepared.suggestions(query: "التنميه صدر", language: .ar)
        XCTAssertTrue(suggestions.contains { $0.kind == .local && $0.query.contains("التنمية") })
        XCTAssertFalse(suggestions.contains { $0.kind == .local && $0.query.contains("Home") })
    }

    private func shippedFoods() throws -> [Food] {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        return try ["foods-data", "mfp-foods-data"].flatMap { name in
            try JSONDecoder().decode([Food].self, from: Data(contentsOf: root.appendingPathComponent("Luqma/Resources/\(name).json")))
        }
    }

    func testActualIPASampleReturnsHonestNearbyBreastForTheReportedMissingBrand() throws {
        let foods = try shippedFoods()
        XCTAssertEqual(foods.count, 750)
        let index = FoodSearch.Index(foods)
        let found = index.matches("التنمية صدر دجاج")
        XCTAssertTrue(found.exact.isEmpty, "The supplied IPA sample has no Tanmiah server product")
        XCTAssertTrue(found.nearby.contains { $0.name == "صدر دجاج مشوي" && $0.brand == "Home" })
        XCTAssertTrue(found.nearby.allSatisfy { food in foods.contains { $0 == food } })
    }

    func testPinnedLiveTanmiahDetailsKeepLabelValuesAndBrandSpecificity() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/search-off-tanmiah.json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let responses = try XCTUnwrap(fixture["responses"] as? [[String: Any]])
        let foods = try responses.map { row -> Food in
            let response = try XCTUnwrap(row["response"] as? [String: Any])
            return try XCTUnwrap(OpenFoodFactsProduct.parse(try XCTUnwrap(response["product"] as? [String: Any])))
        }
        XCTAssertEqual(foods.count, 3)
        let spicy = try XCTUnwrap(foods.first { $0.sourceId == "6281028102400" })
        XCTAssertEqual(spicy.per100, Nutrition(kcal: 134, protein: 20, carbs: 5, fat: 4))
        let arabic = try XCTUnwrap(foods.first { $0.sourceId == "6281028002915" })
        XCTAssertEqual(arabic.per100, Nutrition(kcal: 103, protein: 24, carbs: 0, fat: 1))
        let shish = try XCTUnwrap(foods.first { $0.sourceId == "7802040045972" })
        XCTAssertEqual(shish.servingNutrition, Nutrition(kcal: 103, protein: 20, carbs: 0, fat: 2))
        XCTAssertEqual(FoodSearch.Index(foods).results("التنميه").count, 3)
        let found = FoodSearch.Index(foods).matches("التنمية صدر دجاج")
        XCTAssertTrue(found.exact.isEmpty, "No fetched product declares chicken breast")
        XCTAssertEqual(Set(found.nearby.map(\.id)), Set([spicy.id, shish.id]))
        XCTAssertTrue(foods.allSatisfy(FoodSearch.isOpenFoodFacts))
    }

    func testPreparedIndexesRecordRealCatalogTypingWorkWithoutRebuildingPerKeystroke() throws {
        let foods = try shippedFoods()
        let index = FoodSearch.Index(foods), suggestions = FoodSuggestions.Index(foods)
        let queries = ["ت", "الت", "التن", "التنم", "التنمي", "التنمية", "التنمية ص", "التنمية صدر", "التنمية صدر د", "التنمية صدر دجاج", "milk", "chicken"]
        let start = ProcessInfo.processInfo.systemUptime
        var digest = 0
        for _ in 0..<4 {
            for query in queries {
                let matches = index.matches(query)
                digest += matches.exact.count + matches.nearby.count
                digest += suggestions.suggestions(query: query, language: .ar).count
            }
        }
        let milliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1000
        XCTAssertGreaterThan(digest, 0)
        print("FOOD_SEARCH_PREPARED_BENCHMARK products=\(foods.count) queries=\(queries.count * 4) total_ms=\(milliseconds) average_ms=\(milliseconds / Double(queries.count * 4)) digest=\(digest)")
    }

    func testCancelledIndexWorkCannotPublishOldResults() async {
        let values = (0..<1000).map { product(String($0), "Chicken breast \($0)") }
        let index = FoodSearch.Index(values)
        let task = Task { () -> FoodSearch.Matches in
            await Task.yield()
            return index.matches("chicken breast")
        }
        task.cancel()
        let result = await task.value
        XCTAssertTrue(result.exact.isEmpty)
        XCTAssertTrue(result.nearby.isEmpty)
    }
}
