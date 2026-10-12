import XCTest
@testable import LuqmaCore

final class FoodSuggestionsTests: XCTestCase {
    private func product(_ id: String, _ name: String, nameEn: String? = nil,
                         brand: String? = nil, aliases: String? = nil) -> Food {
        var food = Food(catalogID: "off:" + id, name: name, nameEn: nameEn,
                        aliases: aliases, brand: brand, source: "OpenFoodFacts")
        food.sourceId = id
        return food
    }

    func testPrefixCompletionPrecedesSubstringAndPreservesExplicitFullSearch() {
        let foods = [product("1", "Buttermilk"), product("2", "Milk powder"), product("3", "Whole milk")]
        let rows = FoodSuggestions.suggestions(query: "  mil  ", foods: foods, language: .en)
        let completed = rows.filter { $0.kind == .local }
        XCTAssertEqual(completed.map(\.query), ["Milk powder", "Whole milk", "Buttermilk"])
        XCTAssertEqual(rows.last?.kind, .searchAll)
        XCTAssertEqual(rows.last?.query, "mil")
        XCTAssertTrue(rows.last?.label.contains("Search all for") == true)
    }

    func testArabicMarksAndWordPrefixesCompleteKnownAliasesAndBrands() {
        let milk = product("1", "حليب كامل الدسم", nameEn: "Full fat milk", brand: "Almarai", aliases: "المراعي;حليب المراعي")
        let rows = FoodSuggestions.suggestions(query: "حَلِيب المَرَا", foods: [milk], language: .ar)
        XCTAssertTrue(rows.contains { $0.kind == .local && $0.query == "حليب المراعي" })
        let brandRows = FoodSuggestions.suggestions(query: "ALMA", foods: [milk], language: .en)
        XCTAssertTrue(brandRows.contains { $0.kind == .brand && $0.query == "Almarai" })
        XCTAssertEqual(brandRows.last?.query, "ALMA")
    }

    func testEmptySearchPreservesHistoryOrderAndFiltersHistoricalOrImageSources() {
        let recent = product("2", "Recent food")
        let local = product("1", "Local food")
        let old = Food(catalogID: "usda:12", name: "Old USDA", source: "USDA")
        let image = Food(catalogID: "image:1", name: "Image meal", source: "AI nutrition estimate")
        let privateFood = Food(name: "My homemade meal", source: "Your food")
        let rows = FoodSuggestions.suggestions(query: "", foods: [old, image, local], language: .en,
                                               history: [old, recent, privateFood, image])
        XCTAssertEqual(rows.prefix(2).map(\.query), ["Recent food", "My homemade meal"])
        XCTAssertEqual(rows.prefix(2).map(\.kind), [.history, .history])
        XCTAssertTrue(rows.contains { $0.query == "Local food" })
        XCTAssertFalse(rows.contains { $0.query.contains("USDA") || $0.query.contains("Image") })
        XCTAssertFalse(rows.contains { $0.kind == .searchAll })
    }

    func testNormalizedQueriesDeduplicateAndIDsAreStableAcrossRecomputation() {
        let foods = [product("1", "Milk"), product("2", "MILK"), product("3", "Milk", brand: "Dairy")]
        let rows = FoodSuggestions.suggestions(query: "mi", foods: foods, language: .en, history: [foods[0]])
        XCTAssertEqual(rows.filter { FoodSearch.normalized($0.query) == "milk" }.count, 1)
        XCTAssertEqual(rows.first?.kind, .history)
        XCTAssertEqual(Set(rows.map { FoodSearch.normalized($0.query) }).count, rows.count)
        XCTAssertEqual(rows, FoodSuggestions.suggestions(query: "mi", foods: foods, language: .en, history: [foods[0]]))
        XCTAssertEqual(rows.map(\.id), FoodSuggestions.suggestions(query: "MI", foods: foods, language: .en, history: [foods[0]]).map(\.id))
    }

    func testLimitsOnlySuggestionsAndNeverTruncatesFoodSearchMatches() {
        let foods = (1...12).map { product(String($0), "Milk product \($0)") }
        let rows = FoodSuggestions.suggestions(query: "milk", foods: foods, language: .en, limit: 3)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.last?.kind, .searchAll)
        XCTAssertEqual(FoodSearch.results("milk", in: foods).count, 12)
        XCTAssertEqual(FoodSuggestions.suggestions(query: "milk", foods: foods, language: .en, limit: 1).map(\.kind), [.searchAll])
        XCTAssertTrue(FoodSuggestions.suggestions(query: "milk", foods: foods, language: .en, limit: 0).isEmpty)
        XCTAssertTrue(FoodSuggestions.suggestions(query: "milk", foods: foods, language: .en, limit: -1).isEmpty)
    }

    func testUnknownAndChangedQueryCannotShowStaleProductCompletions() {
        let milk = product("1", "Milk powder")
        XCTAssertTrue(FoodSuggestions.suggestions(query: "mil", foods: [milk], language: .en).contains { $0.query == "Milk powder" })
        let updated = FoodSuggestions.suggestions(query: "xyz", foods: [milk], language: .en)
        XCTAssertEqual(updated.map(\.kind), [.searchAll])
        XCTAssertEqual(updated.first?.query, "xyz")
        let cleared = FoodSuggestions.suggestions(query: " \n ", foods: [], language: .ar)
        XCTAssertTrue(cleared.allSatisfy { $0.kind == .popular })
        XCTAssertEqual(cleared.first?.query, "حليب")
    }

    func testMissingNutritionDoesNotTurnAQuerySuggestionIntoAFoodSelection() {
        let incomplete = product("1", "Milk label only")
        let rows = FoodSuggestions.suggestions(query: "mil", foods: [incomplete], language: .en)
        XCTAssertTrue(rows.contains { $0.query == "Milk label only" && $0.kind == .local })
        XCTAssertNil(incomplete.per100)
        XCTAssertThrowsError(try incomplete.total(1, unit: .serving))
    }
}
