import XCTest
@testable import LuqmaCore

final class AnalysisModelTests: XCTestCase {
    func testBackupUsesSupportedRequestWithoutLeakingCredential() throws {
        let key="offline_test_private_key_1234567890"
        let request=try GeminiMeal.request(imageData:Data([0xFF,0xD8,0xFF]),context:"",language:.ar,key:key,model:.backup)
        XCTAssertEqual(request.url?.absoluteString,"https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash-lite:generateContent")
        let body=try XCTUnwrap(JSONSerialization.jsonObject(with:try XCTUnwrap(request.httpBody)) as? [String:Any])
        let config=try XCTUnwrap(body["generationConfig"] as? [String:Any])
        XCTAssertNil(config["candidateCount"]);XCTAssertNil(config["responseMimeType"])
        let format=try XCTUnwrap(config["responseFormat"] as? [String:Any])
        let text=try XCTUnwrap(format["text"] as? [String:Any])
        XCTAssertEqual(text["mimeType"] as? String,"APPLICATION_JSON")
        XCTAssertFalse(String(decoding:request.httpBody!,as:UTF8.self).contains(key))
    }

    func testFallbackIsBoundedAndNeverRepeatsQuotaAuthenticationOrUserFailure() {
        for status in [404,500,502,503,504] {
            XCTAssertTrue(AnalysisAttemptPolicy.shouldFallback(status:status,attempt:0))
            XCTAssertFalse(AnalysisAttemptPolicy.shouldFallback(status:status,attempt:1))
        }
        for status in [200,400,401,403,408,429] {XCTAssertFalse(AnalysisAttemptPolicy.shouldFallback(status:status,attempt:0))}
        XCTAssertTrue(AnalysisAttemptPolicy.shouldFallback(error:URLError(.timedOut),attempt:0))
        XCTAssertFalse(AnalysisAttemptPolicy.shouldFallback(error:URLError(.timedOut),attempt:1))
        for code in [URLError.Code.cancelled,.notConnectedToInternet,.networkConnectionLost,.cannotFindHost] {
            XCTAssertFalse(AnalysisAttemptPolicy.shouldFallback(error:URLError(code),attempt:0))
        }
    }

    func testCapturedFastResponseHasCompleteEditableServingNutrition() throws {
        let url=try XCTUnwrap(Bundle.module.url(forResource:"gemini-fast-response",withExtension:"json"))
        let result=try GeminiMeal.parseResponse(Data(contentsOf:url))
        XCTAssertEqual(result.parts.count,4)
        let total=try MealPhotoEstimate.total(result.parts.compactMap(\.mealEstimate))
        XCTAssertEqual(total.nutrition.kcal,1265,accuracy:0.001)
        XCTAssertEqual(total.nutrition.protein,79,accuracy:0.001)
        XCTAssertEqual(total.nutrition.carbs,106,accuracy:0.001)
        XCTAssertEqual(total.nutrition.fat,55,accuracy:0.001)
        for part in result.parts {
            let estimate=try XCTUnwrap(part.mealEstimate)
            let food=try estimate.food(name:part.food.name,nameEn:part.food.nameEn,identity:part.id)
            XCTAssertEqual(food.defaultAdditionUnit,.serving)
            XCTAssertEqual(try food.total(1,unit:.serving),estimate.nutrition)
            XCTAssertEqual(try estimate.scaled(toGrams:estimate.grams*0.5).nutrition.kcal,estimate.nutrition.kcal*0.5,accuracy:0.001)
        }
    }
}
