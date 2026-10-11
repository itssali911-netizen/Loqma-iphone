import XCTest
@testable import LuqmaCore

final class FoodServingTests: XCTestCase {
    private let nutrition = Nutrition(kcal: 200, protein: 8, carbs: 30, fat: 5)
    private func food() -> Food {
        var result = Food(catalogID: "usda:example", name: "Rice", nutrition: nutrition, source: "USDA FoodData Central")
        result.servings = [FoodServing(id: "portion:cup", label: "1 cup", grams: 180), FoodServing(id: "portion:spoons", label: "2 tbsp", grams: 30)]
        return result
    }

    func testHouseholdPortionUsesWeightOfWholeLabeledChoiceAndFractionalCounts() throws {
        let original = food()
        let selected = try original.selecting(original.servings![1])
        XCTAssertEqual(selected.id, original.id)
        XCTAssertEqual(selected.per100, original.per100)
        XCTAssertEqual(selected.serving, "2 tbsp")
        XCTAssertEqual(selected.servingQuantity, 30)
        XCTAssertEqual(selected.servingUnit, "g")
        XCTAssertEqual(try selected.total(0.5, unit: .serving).kcal, 30, accuracy: 0.000001)
        XCTAssertEqual(try selected.total(15, unit: .g), try selected.total(0.5, unit: .serving))
        XCTAssertNil(original.servingNutrition)
    }

    func testPortionNeverInfersMillilitersOrAcceptsAnotherFoodsChoice() throws {
        let original = food()
        XCTAssertEqual(original.units, [.g, .serving])
        XCTAssertEqual(original.values(for: .serving)?.kcal, 360)
        XCTAssertThrowsError(try original.total(100, unit: .ml))
        XCTAssertThrowsError(try original.selecting(FoodServing(id: "other", label: "1 cup", grams: 180)))
        var liquid = original; liquid.unit = .ml
        XCTAssertTrue(liquid.servingChoices.isEmpty)
        XCTAssertThrowsError(try liquid.selecting(original.servings![0]))
        var missing = original; missing.fat = nil
        XCTAssertTrue(missing.servingChoices.isEmpty)
        XCTAssertNil(missing.values(for: .serving))
    }

    func testEditingReferenceRecalculatesKnownGramPortionWithoutRewritingIdentity() throws {
        let selected = try food().selecting(food().servings![1])
        let updated = try selected.withReference(Nutrition(kcal: 100, protein: 4, carbs: 15, fat: 2.5), unit: .g)
        XCTAssertEqual(updated.id, selected.id)
        XCTAssertEqual(updated.values(for: .serving)?.kcal, 30)
        let servingOnly = try updated.withReference(Nutrition(kcal: 35, protein: 1, carbs: 5, fat: 1), unit: .serving)
        XCTAssertEqual(servingOnly.per100?.kcal, 100)
        XCTAssertEqual(servingOnly.servingNutrition?.kcal, 35)
        var unknown = selected; unknown.servingQuantity = nil
        let corrected = try unknown.withReference(nutrition.scaled(0.5), unit: .g)
        XCTAssertNil(corrected.servingNutrition)
        XCTAssertEqual(corrected.values(for: .serving)?.kcal, 180)
    }

    func testDiaryKeepsFoodIdentityAndPortionLabelAfterResizeAndBackup() throws {
        let selected = try food().selecting(food().servings![0])
        var entry = try DiaryEntry(food: selected, amount: 0.5, unit: .serving, meal: .lunch, day: "2026-10-11", language: .en)
        XCTAssertEqual(entry.foodID, "usda:example")
        XCTAssertEqual(entry.servingLabel, "1 cup")
        XCTAssertEqual(entry.kcal, 180)
        try entry.resize(1.5)
        XCTAssertEqual(entry.kcal, 540)
        var state = DiarySnapshot(); state.entries = [entry]; state.products = [selected]
        let decoded = try Backup.decode(Backup.encode(state))
        XCTAssertEqual(decoded.entries, state.entries)
        XCTAssertEqual(decoded.products, state.products)
    }

    func testOldBackupDecodesWithoutAnyNewOptionalFields() throws {
        var state = DiarySnapshot()
        state.entries = [try DiaryEntry(food: food(), amount: 100, unit: .g, meal: .lunch, day: "2026-10-11", language: .en)]
        state.products = [food()]
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Backup.encode(state)) as? [String: Any])
        object.removeValue(forKey: "customFoods")
        var entries = try XCTUnwrap(object["entries"] as? [[String: Any]])
        entries[0].removeValue(forKey: "foodID"); entries[0].removeValue(forKey: "servingLabel"); object["entries"] = entries
        var products = try XCTUnwrap(object["products"] as? [[String: Any]])
        products[0].removeValue(forKey: "servings"); object["products"] = products
        let decoded = try Backup.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.customFoods); XCTAssertNil(decoded.entries[0].foodID); XCTAssertNil(decoded.products[0].servings)
        XCTAssertEqual(decoded.entries[0].nutrition, state.entries[0].nutrition)
    }

    func testBackupRejectsMalformedOrDuplicatePortionsWithoutChangingDiary() throws {
        var state = DiarySnapshot(); state.products = [food()]
        let before = try Backup.encode(state)
        let duplicate = state.products[0].servings![0]
        state.products[0].servings?.append(duplicate)
        XCTAssertThrowsError(try Backup.encode(state))
        state = try Backup.decode(before)
        state.products[0].servings?[0].grams = .nan
        XCTAssertThrowsError(try Backup.encode(state))
        state = try Backup.decode(before)
        state.products[0].servings?[0].label = ""
        XCTAssertThrowsError(try Backup.encode(state))
        XCTAssertEqual(try Backup.decode(before).products, [food()])
    }

    func testPersonalBackupMergePreservesRenamedIDsAndRejectsOverflow() throws {
        let original = Food(catalogID: "personal:one", name: "My rice", nutrition: nutrition, source: "Your food")
        var current = DiarySnapshot(); current.customFoods = [original]
        current.entries = [try DiaryEntry(food: original, amount: 100, unit: .g, meal: .lunch, day: "2026-10-11", language: .en)]
        var renamed = original; renamed.name = "My brown rice"
        var incoming = DiarySnapshot(); incoming.customFoods = [renamed]
        let merged = try Backup.merge(incoming, into: current)
        XCTAssertEqual(merged.customFoods?.count, 1)
        XCTAssertEqual(merged.customFoods?.first?.name, "My brown rice")
        XCTAssertEqual(merged.entries, current.entries)
        current.customFoods = (0..<1000).map { Food(catalogID: "personal:\($0)", name: "Food \($0)", nutrition: nutrition, source: "Your food") }
        let before = try Backup.encode(current)
        XCTAssertThrowsError(try Backup.merge(incoming, into: current))
        XCTAssertEqual(try Backup.encode(current), before)
    }
}
