import Foundation
import XCTest
@testable import LuqmaCore

final class FoodCatalogConfigurationTests: XCTestCase {
    private func food() -> Food {
        var value = Food(catalogID: "off:00123456", name: "حليب Milk", brand: "Example",
                         barcode: "00123456", unit: .ml, nutrition: Nutrition(kcal: 62, protein: 3.04, carbs: 0, fat: 3.28),
                         serving: "250 ml", servingQuantity: 250, servingUnit: "ml",
                         servingNutrition: Nutrition(kcal: 155, protein: 7.6, carbs: 0, fat: 8.2), source: "OpenFoodFacts")
        value.sourceId = "00123456"
        value.sourceMetadata = FoodSourceMetadata(url: "https://world.openfoodfacts.org/product/00123456",
            databaseLicense: "ODbL-1.0", contentsLicense: "DbCL-1.0", exportID: "unit-test-only")
        return value
    }

    private func response(foods: [Food], page: Int = 1, next: Int? = 2) throws -> FoodCatalogConfiguration.SearchResponse {
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(foods))
        var payload: [String: Any] = ["format": "luqma-off-catalog", "version": 1, "page": page, "page_size": 50, "foods": encoded]
        if let next { payload["next_page"] = next }
        return try JSONDecoder().decode(FoodCatalogConfiguration.SearchResponse.self, from: JSONSerialization.data(withJSONObject: payload))
    }

    func testOnlyAnExplicitSafeHTTPSDeploymentCanBeConfigured() throws {
        XCTAssertNil(FoodCatalogConfiguration.baseURL(nil))
        for invalid in ["http://example.org", "https://user:secret@example.org", "https://example.org?q=x", "https://example.org/#token", "not-a-url", ""] {
            XCTAssertNil(FoodCatalogConfiguration.baseURL(invalid), invalid)
        }
        let base = try XCTUnwrap(FoodCatalogConfiguration.baseURL("https://example.org/catalogue/"))
        let url = try XCTUnwrap(FoodCatalogConfiguration.searchURL(base: base, query: "حليب & milk", page: 300, pageSize: 50))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.path, "/catalogue/v1/products")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "q" })?.value, "حليب & milk")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "page" })?.value, "300")
        XCTAssertNil(FoodCatalogConfiguration.productURL(base: base, code: "../other"))
        XCTAssertNil(FoodCatalogConfiguration.searchURL(base: base, query: "milk", page: Int.max, pageSize: 50))
    }

    func testCatalogHasNoExternalTenThousandResultWindowAndKeepsLeadingZero() throws {
        let result = try XCTUnwrap(response(foods: [food()], page: 300, next: 301).validated(requestedPage: 300, size: 50))
        XCTAssertEqual(result.nextPage, 301)
        XCTAssertFalse(result.reachedSourceWindow)
        XCTAssertEqual(result.foods[0].sourceId, "00123456")
        XCTAssertEqual(result.foods[0].barcode, "00123456")
        XCTAssertEqual(try result.foods[0].total(1, unit: .serving).kcal, 155)
        XCTAssertThrowsError(try result.foods[0].total(250, unit: .g))
    }

    func testPartialAndExplicitZeroNutritionStayDifferent() throws {
        var partial = food()
        partial.protein = nil
        partial.servingNutrition = nil
        let result = try XCTUnwrap(response(foods: [partial]).validated(requestedPage: 1, size: 50))
        XCTAssertNil(result.foods[0].protein)
        XCTAssertEqual(result.foods[0].carbs, 0)
        XCTAssertNil(result.foods[0].per100)
        XCTAssertThrowsError(try result.foods[0].total(100, unit: .ml))
    }

    func testInvalidPaginationDuplicatesAndIdentityAreRejected() throws {
        XCTAssertNil(try response(foods: [food()], next: 3).validated(requestedPage: 1, size: 50))
        XCTAssertNil(try response(foods: []).validated(requestedPage: 1, size: 50))
        XCTAssertNil(try response(foods: [food(), food()]).validated(requestedPage: 1, size: 50))
        XCTAssertNil(try response(foods: [food()], page: Int.max, next: nil).validated(requestedPage: Int.max, size: 50))
        var invalid = food()
        invalid.source = "Your food"
        XCTAssertNil(try response(foods: [invalid]).validated(requestedPage: 1, size: 50))
        invalid = food()
        invalid.kcal = -1
        XCTAssertNil(try response(foods: [invalid]).validated(requestedPage: 1, size: 50))
        invalid = food()
        invalid.barcode = "00999999"
        XCTAssertNil(try response(foods: [invalid]).validated(requestedPage: 1, size: 50))
    }

    func testProductResponseCannotReplaceTheRequestedProduct() throws {
        let bytes = try JSONEncoder().encode(food())
        let encoded = try JSONSerialization.jsonObject(with: bytes)
        let data = try JSONSerialization.data(withJSONObject: ["format": "luqma-off-catalog", "version": 1, "food": encoded])
        let response = try JSONDecoder().decode(FoodCatalogConfiguration.ProductResponse.self, from: data)
        XCTAssertEqual(try response.validated(code: "00123456"), food())
        XCTAssertThrowsError(try response.validated(code: "other-product"))
    }

    func testOldSavedFoodsDecodeAndCatalogRefreshDoesNotChangeDiarySnapshots() throws {
        var original = food()
        let entry = try DiaryEntry(food: original, amount: 1, unit: .serving, meal: .breakfast, day: "2026-11-03", language: .en)
        var state = DiarySnapshot()
        state.entries = [entry]
        state.products = [original]
        original.kcal = 90
        original.servingNutrition?.kcal = 225
        state.products = [original]
        XCTAssertEqual(state.entries[0].kcal, 155)
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(food())) as! [String: Any]
        old.removeValue(forKey: "sourceMetadata")
        let restored = try JSONDecoder().decode(Food.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertNil(restored.sourceMetadata)
        XCTAssertEqual(restored.id, food().id)
        let roundTrip = try JSONDecoder().decode(Food.self, from: JSONEncoder().encode(food()))
        XCTAssertEqual(roundTrip.sourceMetadata, food().sourceMetadata)
    }

    func testLiveParserKeepsActualProvenanceWithoutInventingRetrievalOrUpdateDates() throws {
        let bare = try XCTUnwrap(OpenFoodFactsProduct.parse(["code": "00123456", "product_name": "Milk"]))
        XCTAssertEqual(bare.sourceMetadata?.databaseLicense, "ODbL-1.0")
        XCTAssertNil(bare.sourceMetadata?.retrievedAt)
        XCTAssertNil(bare.sourceMetadata?.lastModified)
        let dated = try XCTUnwrap(OpenFoodFactsProduct.parse(["code": "00123456", "product_name": "Milk", "last_modified_t": 1700000000,
            "countries_tags": ["en:japan"], "allergens_tags": ["en:milk"], "ingredients_text": "Milk"]))
        XCTAssertEqual(dated.sourceMetadata?.lastModified, 1700000000)
        XCTAssertEqual(dated.sourceMetadata?.countries, ["en:japan"])
        XCTAssertEqual(dated.sourceMetadata?.allergens, ["en:milk"])
    }
}
