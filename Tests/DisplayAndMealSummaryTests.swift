import Foundation
import XCTest
@testable import LuqmaCore

final class DisplayAndMealSummaryTests: XCTestCase {
    func testArabicLocaleKeepsArabicWordsAndWesternNumbers() throws {
        let formatter = NumberFormatter()
        formatter.locale = DisplayFormat.locale(.ar)
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        XCTAssertEqual(formatter.string(from: 123), "123")
        XCTAssertEqual(AppLanguage.ar.text("لكل ١٠٠ جم", "per 100 g"), "لكل 100 جم")
        XCTAssertEqual(DisplayFormat.westernDigits("١٢٣ / ۱۲۳ / 123"), "123 / 123 / 123")
        XCTAssertEqual(DisplayFormat.decimal(123.5), "123.5")
        XCTAssertEqual(DisplayFormat.decimal(.nan), "—")
        // Pasted Arabic decimal quantities still parse in every quantity field.
        XCTAssertEqual(TextSearch.number("١٢٣٫٥"), 123.5)

        let calendar = DisplayFormat.calendar(.ar)
        XCTAssertEqual(calendar.identifier, .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 12)))
        let label = DisplayFormat.date(date, template: "d MMMM yyyy", language: .ar)
        XCTAssertTrue(label.contains("13"))
        XCTAssertTrue(label.contains("2026"))
        XCTAssertTrue(label.unicodeScalars.contains { (0x0621...0x064A).contains($0.value) })
        XCTAssertFalse(label.unicodeScalars.contains { (0x0660...0x0669).contains($0.value) || (0x06F0...0x06F9).contains($0.value) })
    }

    func testDisplayConversionDoesNotModifySourceFoodOrStoredServing() throws {
        let food = Food(name: "حليب ٢٪", nutrition: Nutrition(kcal: 60, protein: 3, carbs: 4, fat: 2), serving: "كوب ٢٥٠ مل", servingNutrition: Nutrition(kcal: 150, protein: 7.5, carbs: 10, fat: 5))
        let entry = try DiaryEntry(food: food, amount: 1, unit: .serving, meal: .breakfast, day: "2026-10-13", language: .ar)
        XCTAssertEqual(food.label(.ar), "حليب 2٪")
        XCTAssertEqual(food.name, "حليب ٢٪")
        XCTAssertEqual(food.serving, "كوب ٢٥٠ مل")
        XCTAssertEqual(entry.unitLabel(.ar), "كوب 250 مل")
        XCTAssertEqual(entry.servingLabel, "كوب ٢٥٠ مل")
    }

    func testFourMealTotalsUseEatenNutritionForExactlyTheSelectedDay() throws {
        let food = Food(name: "Test food", nutrition: Nutrition(kcal: 200, protein: 10, carbs: 20, fat: 8))
        let day = "2026-10-13"
        var entries = [
            try DiaryEntry(food: food, amount: 50, unit: .g, meal: .breakfast, day: day, language: .en),
            try DiaryEntry(food: food, amount: 25, unit: .g, meal: .breakfast, day: day, language: .en),
            try DiaryEntry(food: food, amount: 150, unit: .g, meal: .lunch, day: day, language: .en),
            try DiaryEntry(food: food, amount: 300, unit: .g, meal: .dinner, day: "2026-10-12", language: .en)
        ]
        let summaries = MealDiarySummary.forDay(day, entries: entries)
        XCTAssertEqual(summaries.map(\.meal), Meal.allCases)
        XCTAssertEqual(summaries[0].nutrition, Nutrition(kcal: 150, protein: 7.5, carbs: 15, fat: 6))
        XCTAssertEqual(summaries[1].nutrition, Nutrition(kcal: 300, protein: 15, carbs: 30, fat: 12))
        XCTAssertEqual(summaries[2].nutrition, .zero)
        XCTAssertEqual(summaries[3].nutrition, .zero)
        XCTAssertEqual(summaries.flatMap(\.entries).map(\.id), Array(entries.prefix(3)).map(\.id))
        XCTAssertEqual(summaries.reduce(Nutrition.zero) { $0 + $1.nutrition }, Nutrition(kcal: 450, protein: 22.5, carbs: 45, fat: 18))

        try entries[0].resize(100)
        let edited = MealDiarySummary.forDay(day, entries: entries)
        XCTAssertEqual(edited[0].nutrition, Nutrition(kcal: 250, protein: 12.5, carbs: 25, fat: 10))
        XCTAssertEqual(edited[1].nutrition, summaries[1].nutrition)
        XCTAssertTrue(MealDiarySummary.forDay("2026-10-14", entries: entries).allSatisfy { $0.entries.isEmpty && $0.nutrition == .zero })
    }
}
