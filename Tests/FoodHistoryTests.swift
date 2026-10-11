import XCTest
@testable import LuqmaCore

final class FoodHistoryTests: XCTestCase {
    private let nutrition = Nutrition(kcal: 120, protein: 3, carbs: 25, fat: 1)

    private func entry(_ food: Food, created: String? = "2026-10-11T12:00:00Z", day: String = "2026-10-11") throws -> DiaryEntry {
        var result = try DiaryEntry(food: food, amount: 100, unit: food.unit, meal: .lunch, day: day, language: .en)
        result.created = created
        return result
    }

    func testOpeningSearchAndBarcodeResultsDoesNotCreateRecentOrFrequentUsage() throws {
        let rice = Food(catalogID: "rice", name: "Rice", nutrition: nutrition)
        let milk = Food(name: "Milk", barcode: "12345678", unit: .ml, nutrition: nutrition)
        var state = DiarySnapshot()
        try FoodHistory.remember(rice, in: &state, barcode: false)
        try FoodHistory.remember(milk, in: &state, barcode: true)
        let foods = FoodHistory.candidates(in: state)
        XCTAssertEqual(state.searchHistory.map(\.id), [rice.id])
        XCTAssertEqual(state.barcodeHistory.map(\.id), [milk.id])
        XCTAssertTrue(FoodHistory.recent(entries: state.entries, foods: foods).isEmpty)
        XCTAssertTrue(FoodHistory.frequent(entries: state.entries, foods: foods).isEmpty)
        state.entries = [try entry(rice)]
        XCTAssertEqual(FoodHistory.recent(entries: state.entries, foods: foods).map(\.id), [rice.id])
        state.entries.removeAll()
        XCTAssertTrue(FoodHistory.frequent(entries: state.entries, foods: foods).isEmpty)
    }

    func testFrequencyCountsLogsAndKeepsDistinctBrandsWithDeterministicTies() throws {
        let first = Food(catalogID: "brand:a", name: "Rice", brand: "A", nutrition: nutrition)
        let second = Food(catalogID: "brand:b", name: "Rice", brand: "B", nutrition: nutrition)
        let third = Food(catalogID: "brand:c", name: "Rice", brand: "C", nutrition: nutrition)
        var entries = [try entry(first, created: "2026-10-09T10:00:00Z"),
                       try entry(first, created: "2026-10-10T10:00:00Z"),
                       try entry(second, created: "2026-10-11T10:00:00Z"),
                       try entry(third, created: "2026-10-11T10:00:00Z")]
        let foods = [third, second, first]
        XCTAssertEqual(FoodHistory.frequent(entries: entries, foods: foods).map(\.id), [first.id, second.id, third.id])
        XCTAssertEqual(FoodHistory.recent(entries: entries, foods: foods).map(\.id), [second.id, third.id, first.id])
        let summaries = FoodHistory.usage(entries: entries, foods: foods)
        XCTAssertEqual(summaries.first { $0.id == first.id }?.count, 2)
        var state = DiarySnapshot()
        state.entries = entries
        let lists = FoodHistory.lists(in: state, catalog: foods)
        XCTAssertEqual(lists.recent.map(\.id), [second.id, third.id, first.id])
        XCTAssertEqual(lists.frequent.map(\.id), [first.id, second.id, third.id])
        XCTAssertTrue(lists.personal.isEmpty)
        entries.removeFirst()
        XCTAssertEqual(FoodHistory.frequent(entries: entries, foods: foods).map(\.id), [second.id, third.id, first.id])
        XCTAssertEqual(FoodHistory.frequent(entries: Array(entries.reversed()), foods: Array(foods.reversed())).map(\.id),
                       FoodHistory.frequent(entries: entries, foods: foods).map(\.id))
    }

    func testLegacyLabelsMatchBothLanguagesButAmbiguousBrandsAreExcluded() throws {
        let apple = Food(catalogID: "apple", name: "تفاح", nameEn: "Apple", nutrition: nutrition)
        let first = Food(catalogID: "brand:a", name: "أرز", nameEn: "Rice", brand: "A", nutrition: nutrition)
        let second = Food(catalogID: "brand:b", name: "أرز", nameEn: "Rice", brand: "B", nutrition: nutrition)
        var arabic = try entry(apple)
        arabic.foodID = nil
        arabic.name = "تُفّاح"
        var english = try entry(apple)
        english.foodID = nil
        var ambiguous = try entry(first)
        ambiguous.foodID = nil
        let summaries = FoodHistory.usage(entries: [arabic, english, ambiguous], foods: [first, apple, second])
        XCTAssertEqual(summaries.map(\.id), [apple.id])
        XCTAssertEqual(summaries.first?.count, 2)
    }

    func testLegacyBarcodeResolvesRenamedFoodAndExplicitUnknownIDNeverUsesName() throws {
        let milk = Food(name: "Milk", barcode: "12345678", nutrition: nutrition)
        var old = try entry(milk)
        old.foodID = nil
        old.name = "Old milk name"
        var missing = try entry(milk)
        missing.foodID = "missing:another-brand"
        XCTAssertEqual(FoodHistory.usage(entries: [old, missing], foods: [milk]).first?.count, 1)
        XCTAssertTrue(FoodHistory.recent(entries: [missing], foods: [milk]).isEmpty)
    }

    func testDatesUseCreationTimestampWithDayFallbackAndFractionalSeconds() throws {
        let first = Food(catalogID: "a", name: "A", nutrition: nutrition)
        let second = Food(catalogID: "b", name: "B", nutrition: nutrition)
        let third = Food(catalogID: "c", name: "C", nutrition: nutrition)
        let entries = [try entry(first, created: nil, day: "2026-10-10"),
                       try entry(second, created: "2026-10-11T11:00:00.500Z", day: "2026-10-09"),
                       try entry(third, created: "2026-10-11T14:00:00+03:00", day: "2026-10-11")]
        XCTAssertEqual(FoodHistory.recent(entries: entries, foods: [first, second, third]).map(\.id), [second.id, third.id, first.id])
    }

    func testPersonalFoodsSurviveCacheEvictionAndLatestSavedValuesOverrideCatalog() throws {
        let personal = Food(catalogID: "personal:one", name: "My rice", nutrition: nutrition, source: "Your food")
        var state = DiarySnapshot()
        try FoodHistory.remember(personal, in: &state, barcode: false)
        state.products = (0..<1000).map { Food(catalogID: "cache:\($0)", name: "Food \($0)") }
        state.searchHistory = []
        XCTAssertEqual(FoodHistory.yourFoods(in: state).map(\.id), [personal.id])
        var updated = personal
        updated.kcal = 150
        try FoodHistory.remember(updated, in: &state, barcode: false)
        let candidates = FoodHistory.candidates(in: state, catalog: [personal])
        XCTAssertEqual(candidates.filter { $0.id == personal.id }.count, 1)
        XCTAssertEqual(candidates.first { $0.id == personal.id }?.kcal, 150)
        XCTAssertEqual(state.products.count, 1000)
        XCTAssertEqual(state.customFoods?.first?.kcal, 150)
    }

    func testFullPersonalCollectionRejectsNewFoodAtomicallyButAllowsEditing() throws {
        var state = DiarySnapshot()
        state.customFoods = (0..<1000).map {
            Food(catalogID: "personal:\($0)", name: "Food \($0)", nutrition: nutrition, source: "Your food")
        }
        let before = try Backup.encode(state)
        let extra = Food(catalogID: "personal:extra", name: "Extra", nutrition: nutrition, source: "Your food")
        XCTAssertThrowsError(try FoodHistory.remember(extra, in: &state, barcode: false))
        XCTAssertEqual(try Backup.encode(state), before)
        var edit = try XCTUnwrap(state.customFoods?.first)
        edit.name = "Updated name"
        try FoodHistory.remember(edit, in: &state, barcode: false)
        XCTAssertEqual(state.customFoods?.count, 1000)
        XCTAssertEqual(state.customFoods?.last?.name, "Updated name")
    }

    func testLegacyPersonalFoodsMigrateWithoutDuplicateIdentifiers() throws {
        let original = Food(catalogID: "personal:one", name: "Old name", nutrition: nutrition, source: "Your food")
        var updated = original
        updated.name = "New name"
        var state = DiarySnapshot()
        state.products = [original]
        state.searchHistory = [original]
        try FoodHistory.remember(updated, in: &state, barcode: false)
        XCTAssertEqual(state.customFoods?.map(\.id), [original.id])
        XCTAssertEqual(FoodHistory.yourFoods(in: state).map(\.name), ["New name"])
        let restored = try Backup.decode(Backup.encode(state))
        XCTAssertEqual(FoodHistory.yourFoods(in: restored).map(\.id), [original.id])
    }

    func testUnrelatedCacheInsertMigratesLegacyNameBasedPersonalIDBeforeEviction() throws {
        let legacy = Food(name: "My old rice", nutrition: nutrition, source: "Your food")
        var state = DiarySnapshot()
        state.entries = [try entry(legacy)]
        state.products = [legacy] + (0..<999).map { Food(catalogID: "cache:\($0)", name: "Food \($0)") }
        let incoming = Food(catalogID: "cache:new", name: "New food", nutrition: nutrition)
        try FoodHistory.remember(incoming, in: &state, barcode: false)
        XCTAssertFalse(state.products.contains { $0.id == legacy.id })
        XCTAssertEqual(state.customFoods?.first?.id, legacy.id)
        let restored = try Backup.decode(Backup.encode(state))
        XCTAssertEqual(restored.entries.first?.foodID, legacy.id)
        XCTAssertEqual(FoodHistory.lists(in: restored).recent.map(\.id), [legacy.id])
    }

    func testVersion13ManualFoodWithoutSourceMigratesAndExcludesCatalogRecipePhotoFoods() throws {
        let manual = Food(name: "أرزي الخاص", nameEn: "My rice", nutrition: nutrition)
        let usda = Food(catalogID: "usda:rice", name: "Rice", nutrition: nutrition, source: "USDA FoodData Central")
        let off = Food(name: "Milk", barcode: "12345678", nutrition: nutrition, source: "OpenFoodFacts")
        let recipe = Food(catalogID: UUID().uuidString, name: "My recipe", unit: .serving, nutrition: nutrition)
        let photo = Food(name: "Photo meal", nutrition: nutrition, source: "Photo estimate")
        var state = DiarySnapshot()
        state.products = [manual, usda, off, recipe, photo]
        state.entries = [try entry(manual)]
        let personal = FoodHistory.yourFoods(in: state)
        XCTAssertEqual(personal.map(\.id), [manual.id])
        XCTAssertEqual(personal.first?.source, "Your food")
        XCTAssertEqual(personal.first?.nameEn, manual.nameEn)
        try FoodHistory.remember(usda, in: &state, barcode: false)
        XCTAssertEqual(state.customFoods?.map(\.id), [manual.id])
        var edited = manual
        edited.kcal = 150
        try FoodHistory.remember(edited, in: &state, barcode: false)
        XCTAssertEqual(state.customFoods?.first?.kcal, 150)
        XCTAssertEqual(state.customFoods?.first?.id, manual.id)
        let restored = try Backup.decode(Backup.encode(state))
        XCTAssertEqual(FoodHistory.lists(in: restored).recent.map(\.id), [manual.id])
    }
}
