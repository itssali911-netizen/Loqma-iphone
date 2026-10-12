import Foundation
import XCTest
@testable import LuqmaCore

final class MyFitnessPalCatalogTests: XCTestCase {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent() }
    private func foods() throws -> [Food] {
        try JSONDecoder().decode([Food].self, from: Data(contentsOf: root.appendingPathComponent("Luqma/Resources/mfp-foods-data.json")))
    }

    func testAll744SuppliedRegionalRecordsRemainAvailableWithExplicitProvenance() throws {
        let rows = try foods()
        XCTAssertEqual(rows.count, 744)
        XCTAssertEqual(Set(rows.map(\.id)).count, 744)
        XCTAssertEqual(rows.filter { $0.servingNutrition != nil }.count, 713)
        XCTAssertEqual(rows.flatMap(\.portionChoices).count, 3830)
        XCTAssertEqual(rows.flatMap(\.portionChoices).filter { $0.nutrition != nil }.count, 3736)
        for food in rows {
            XCTAssertTrue(FoodSearch.isMyFitnessPalBundled(food), food.id)
            XCTAssertTrue(FoodSearch.isCatalogFood(food), food.id)
            XCTAssertTrue(FoodSearch.availableForAdding(food), food.id)
            XCTAssertFalse(FoodSearch.isOpenFoodFacts(food), food.id)
            XCTAssertEqual(food.unit, .serving, food.id)
            XCTAssertFalse(food.portionChoices.isEmpty, food.id)
            XCTAssertEqual(food.portionChoices.count, food.portions?.count, food.id)
            XCTAssertEqual(food.selectedPortionID, food.portionChoices.first?.id, food.id)
        }
        var snapshot = DiarySnapshot(); snapshot.products = rows
        XCTAssertNoThrow(try DiaryValidation.check(snapshot))
    }

    func testEveryDeclaredChoiceScalesAsAServingAndNeverInfersWeightDensity() throws {
        for food in try foods() {
            for choice in food.portionChoices {
                let selected = try food.selectingPortion(choice)
                XCTAssertEqual(selected.servingQuantity, choice.quantity)
                XCTAssertEqual(selected.servingUnit, choice.unit)
                XCTAssertEqual(selected.serving, choice.label)
                XCTAssertEqual(selected.selectedPortionID, choice.id)
                XCTAssertThrowsError(try selected.total(choice.quantity, unit: .g))
                XCTAssertThrowsError(try selected.total(choice.quantity, unit: .ml))
                if let n = choice.nutrition {
                    let half = try selected.total(0.5, unit: .serving)
                    XCTAssertEqual(half.kcal, n.kcal / 2, accuracy: 0.000001)
                    XCTAssertEqual(half.protein, n.protein / 2, accuracy: 0.000001)
                    XCTAssertEqual(half.carbs, n.carbs / 2, accuracy: 0.000001)
                    XCTAssertEqual(half.fat, n.fat / 2, accuracy: 0.000001)
                } else {
                    XCTAssertNil(selected.kcal); XCTAssertNil(selected.protein)
                    XCTAssertNil(selected.carbs); XCTAssertNil(selected.fat)
                    XCTAssertThrowsError(try selected.total(1, unit: .serving))
                }
            }
        }
    }

    func testIncompleteSourceDataIsVisibleButCannotProduceAZeroNutritionDiaryEntry() throws {
        let rows = try foods().filter { $0.servingNutrition == nil }
        XCTAssertEqual(rows.count, 31)
        for food in rows {
            XCTAssertFalse(food.name.isEmpty)
            XCTAssertNil(food.per100)
            XCTAssertTrue(FoodSearch.results(food.name, in: [food]).contains { $0.id == food.id })
            XCTAssertThrowsError(try DiaryEntry(food: food, amount: 1, unit: .serving, meal: .lunch, day: "2026-10-12", language: .en))
        }
    }

    func testExplicitNutritionRepairAndSelectedChoiceSurviveBackupRoundTrip() throws {
        var food = try XCTUnwrap(foods().first { $0.servingNutrition == nil })
        let choice = try XCTUnwrap(food.portionChoices.first)
        food = try food.selectingPortion(choice)
        let corrected = Nutrition(kcal: 150, protein: 10, carbs: 20, fat: 3)
        food = try food.withReference(corrected, unit: .serving)
        XCTAssertEqual(food.portionChoices.first { $0.id == choice.id }?.nutrition, corrected)
        var state = DiarySnapshot(); state.products = [food]
        let restored = try Backup.decode(Backup.encode(state))
        let saved = try XCTUnwrap(restored.products.first)
        XCTAssertEqual(saved.selectedPortionID, choice.id)
        let declared = try XCTUnwrap(saved.portionChoices.first { $0.id == choice.id })
        XCTAssertEqual(try saved.selectingPortion(declared).total(2, unit: .serving), corrected.scaled(2))
    }

    func testCorruptPortionsAndUnknownSelectedIDsAreRejectedFromBackups() throws {
        let food = try XCTUnwrap(foods().first)
        var state = DiarySnapshot(); state.products = [food]
        state.products[0].selectedPortionID = "not-a-declared-choice"
        XCTAssertThrowsError(try DiaryValidation.check(state))
        state.products = [food]
        state.products[0].portions?[0].nutritionMultiplier = -1
        XCTAssertThrowsError(try DiaryValidation.check(state))
        state.products = [food]
        state.products[0].portions?[0].quantity = 0
        XCTAssertThrowsError(try DiaryValidation.check(state))
        let fake = FoodPortionChoice(id: "invented", label: "1 cup", quantity: 1, unit: "cup", nutritionMultiplier: 1, nutrition: .zero)
        XCTAssertThrowsError(try food.selectingPortion(fake))
    }

    func testMixedCatalogSearchAndSuggestionsPreserveSourcesWithoutAResultCap() throws {
        let mfp = try foods()
        let off = try JSONDecoder().decode([Food].self, from: Data(contentsOf: root.appendingPathComponent("Luqma/Resources/foods-data.json")))
        XCTAssertEqual(mfp.count + off.count, 750)
        for query in ["milk", "rice", "chicken", "حليب", "Nutella"] {
            let all = mfp + off
            let matches = FoodSearch.results(query, in: all)
            XCTAssertEqual(Set(matches.map(\.id)), Set(all.filter { FoodSearch.matches($0, query: query) }.map(\.id)))
        }
        let item = try XCTUnwrap(mfp.first)
        let suggestions = FoodSuggestions.suggestions(query: "", foods: [item], language: .en)
        XCTAssertTrue(suggestions.contains { $0.kind == .local && $0.label == item.name })
        var falseSource = item; falseSource.source = "OpenFoodFacts"
        XCTAssertFalse(FoodSearch.availableForAdding(falseSource))
        falseSource = item; falseSource.sourceId = "different-id"
        XCTAssertFalse(FoodSearch.availableForAdding(falseSource))
    }

    func testIndependentArabicFoodWordsSearchOriginalNamesWithoutTranslatingBrands() throws {
        let catalog = try foods()
        let milk = try XCTUnwrap(catalog.first { $0.name.lowercased().split(separator: " ").contains("milk") })
        XCTAssertTrue(FoodSearch.matches(milk, query: "حليب"))
        XCTAssertTrue(FoodSearch.results("حليب", in: catalog).contains { $0.id == milk.id })
        XCTAssertTrue(FoodSearch.results("دجاج", in: catalog).contains { $0.name.lowercased().contains("chicken") })
        let steak = catalog.filter { $0.name.lowercased().contains("steak") && !$0.name.lowercased().split(separator: " ").contains("tea") }
        XCTAssertFalse(steak.contains { ($0.aliases ?? "").components(separatedBy: ";").contains("شاي") })
    }
}
