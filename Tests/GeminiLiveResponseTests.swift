import XCTest
@testable import LuqmaCore

final class GeminiLiveResponseTests:XCTestCase {
    // Public USDA/Wikimedia meal fixture returned by the production request.
    // This checks the real response-to-serving path, not true calorie accuracy.
    func testCapturedMealResponseProducesCompleteLoggablePortions() throws {
        let url=try XCTUnwrap(Bundle.module.url(forResource:"gemini-calorie-response",withExtension:"json"))
        let result=try GeminiMeal.parseResponse(Data(contentsOf:url))
        XCTAssertEqual(result.parts.count,4)
        let total=try MealPhotoEstimate.total(result.parts.compactMap(\.mealEstimate))
        XCTAssertEqual(total.nutrition.kcal,1330,accuracy:0.001)
        XCTAssertEqual(total.nutrition.protein,86,accuracy:0.001)
        XCTAssertEqual(total.nutrition.carbs,112,accuracy:0.001)
        XCTAssertEqual(total.nutrition.fat,59,accuracy:0.001)
        for part in result.parts {
            let estimate=try XCTUnwrap(part.mealEstimate)
            let food=try estimate.food(name:part.food.name,nameEn:part.food.nameEn,identity:part.id)
            XCTAssertTrue(MealPhotoEstimate.isValidPhotoEstimate(food))
            XCTAssertTrue(FoodSearch.availableForAdding(food))
            XCTAssertEqual(food.defaultAdditionUnit,.serving)
            XCTAssertEqual(try food.total(1,unit:.serving),estimate.nutrition)
            let entry=try DiaryEntry(food:food,amount:1,unit:.serving,meal:.lunch,day:"2026-10-13",language:.ar)
            XCTAssertEqual(entry.nutrition,estimate.nutrition)
        }
    }
}
