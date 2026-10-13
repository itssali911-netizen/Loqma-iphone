import XCTest
@testable import LuqmaCore

final class RecipeGroundingTests: XCTestCase {
    private func row(_ name: String, quantity: Double, unit: String = "g", label: String = "g", quote: String,
                     kcal: Double = 44, protein: Double = 0, carbs: Double = 0, fat: Double = 5) -> [String: Any] {
        ["name": name, "quantity": quantity, "unit": unit, "unitLabel": label, "sourceQuantityText": quote,
         "kcal": kcal, "protein": protein, "carbs": carbs, "fat": fat, "assumption": "Typical nutrition; amount must be declared in the source."]
    }
    private func response(_ rows: [[String: Any]], servings: Any = 2, yieldQuote: String = "Makes 2 servings.") throws -> Data {
        let payload = try JSONSerialization.data(withJSONObject: ["isRecipe": true, "sourceAvailable": true, "title": "Test recipe",
            "servings": servings, "sourceServingsText": yieldQuote, "ingredients": rows, "steps": ["Mix and cook."], "assumptions": []])
        return try JSONSerialization.data(withJSONObject: ["candidates": [["finishReason": "STOP", "content": ["parts": [["text": String(data: payload, encoding: .utf8)!]]]]]])
    }

    func testMissingMushroomButterAmountsAndYieldStayUnknownDespitePlausibleModelGuesses() throws {
        let caption = "المقادير: نصف كيلو لحم مفروم. ٢ حبة بصل. مشروم بني مقطع شرائح. الطريقة: نشوح اللحم بالزبدة ثم نضيف البصل والمشروم."
        let url = URL(string: "https://www.instagram.com/reel/own-example/")!
        let input = try RecipeImport.input(url: url.absoluteString, pastedText: "").withCapturedSource(
            RecipeSourceContent(text: caption, kind: .publicCaption), finalURL: url)
        let rows = [row("لحم مفروم", quantity: 500, quote: "نصف كيلو لحم مفروم", kcal: 1000, protein: 100, fat: 65),
                    row("بصل", quantity: 2, unit: "serving", label: "حبة", quote: "٢ حبة بصل", kcal: 90, protein: 2, carbs: 20, fat: 0.2),
                    row("مشروم بني", quantity: 1, unit: "serving", label: "كوب", quote: "", kcal: 20, protein: 3, carbs: 3, fat: 0),
                    row("زبدة", quantity: 2, unit: "serving", label: "ملعقة كبيرة", quote: "2 tablespoons butter", kcal: 200, fat: 22)]
        let draft = try RecipeImport.parseResponse(response(rows, servings: 4, yieldQuote: ""), input: input, language: .ar)
        XCTAssertEqual(draft.ingredients[0].quantity, 500)
        XCTAssertEqual(draft.ingredients[1].quantity, 2)
        for ingredient in draft.ingredients.suffix(2) { XCTAssertNil(ingredient.quantity); XCTAssertNil(ingredient.nutrition) }
        XCTAssertNil(draft.servings); XCTAssertNil(draft.total); XCTAssertNil(draft.perServing)
        XCTAssertFalse(draft.readyToSave)
        XCTAssertTrue(draft.assumptions.contains { $0.contains("الكميات") })
    }

    func testQuoteCannotChangeHouseholdUnitToInventedGramsOrInventAMissingPhrase() throws {
        let input = try RecipeImport.input(url: "", pastedText: "Ingredients: 1 cup rice and 5 g olive oil. Mix and cook. Makes 2 servings.")
        let rows = [row("Rice", quantity: 200, quote: "1 cup rice", kcal: 260, protein: 5, carbs: 56, fat: 0.5),
                    row("Olive oil", quantity: 5, quote: "5 g olive oil")]
        let draft = try RecipeImport.parseResponse(response(rows), input: input, language: .en)
        XCTAssertNil(draft.ingredients[0].quantity); XCTAssertNil(draft.ingredients[0].nutrition)
        XCTAssertEqual(draft.ingredients[1].quantity, 5)
        XCTAssertEqual(draft.servings, 2)
        var forged = rows; forged[0]["sourceQuantityText"] = "200 g rice"
        XCTAssertNil(try RecipeImport.parseResponse(response(forged), input: input, language: .en).ingredients[0].quantity)
    }

    func testNetworkResponseWithLegacyMissingEvidenceCannotBecomeACompleteSavedRecipe() throws {
        let input = try RecipeImport.input(url: "", pastedText: "Ingredients: 5 g olive oil. Mix and cook. Makes 2 servings.")
        var legacy = row("Olive oil", quantity: 5, quote: "5 g olive oil")
        legacy.removeValue(forKey: "sourceQuantityText")
        let draft = try RecipeImport.parseResponse(response([legacy]), input: input, language: .en)
        XCTAssertNil(draft.ingredients[0].quantity); XCTAssertNil(draft.total)
        XCTAssertFalse(draft.readyToSave)
    }

    func testSourceAmountsAcceptExactArabicFractionsDualCountsAndExplicitMeasuresOnly() {
        let examples: [(String, Double, FoodUnit, String)] = [
            ("نصف كيلو لحم", 500, .g, "جم"), ("٢٥٠ جرام دجاج", 250, .g, "جرام"), ("نصف لتر حليب", 500, .ml, "مل"),
            ("ملعقتان كبيرتان سكر", 2, .serving, "ملعقة كبيرة"), ("ملعقتين صغيرتين نشا", 2, .serving, "ملعقة صغيرة"),
            ("كوبين دقيق", 2, .serving, "كوب"), ("كوبان ماء", 2, .serving, "كوب"), ("نصف كوب كريمة", 0.5, .serving, "كوب"),
            ("ربع كوب ماء", 0.25, .serving, "كوب"), ("كوب زيت", 1, .serving, "كوب"), ("٥ ملاعق سكر", 5, .serving, "ملعقة"),
            ("١٦ فص ثوم", 16, .serving, "فص"), ("1 1/2 cups oats", 1.5, .serving, "cup"), ("½ cup oats", 0.5, .serving, "cup"),
            ("2 large eggs", 2, .serving, "egg")]
        for (phrase, amount, unit, label) in examples {
            XCTAssertEqual(RecipeSourceQuantity.quantity(amount, unit: unit, unitLabel: label, quote: phrase, source: phrase), amount, phrase)
        }
        XCTAssertNil(RecipeSourceQuantity.quantity(1, unit: .serving, unitLabel: "cup", quote: "كوبين دقيق", source: "كوبين دقيق"))
        XCTAssertNil(RecipeSourceQuantity.quantity(1, unit: .serving, unitLabel: "cup", quote: "نصف كوب كريمة", source: "نصف كوب كريمة"))
        XCTAssertNil(RecipeSourceQuantity.quantity(1, unit: .serving, unitLabel: "ملعقة كبيرة", quote: "اثنتان ملعقة كبيرة سكر", source: "اثنتان ملعقة كبيرة سكر"))
        XCTAssertEqual(RecipeSourceQuantity.quantity(2, unit: .serving, unitLabel: "ملعقة كبيرة", quote: "اثنتان ملعقة كبيرة سكر", source: "اثنتان ملعقة كبيرة سكر"), 2)
        XCTAssertNil(RecipeSourceQuantity.quantity(100, unit: .g, unitLabel: "g", quote: "mushrooms sliced", source: "mushrooms sliced"))
    }

    func testYieldQuoteMustMatchExplicitSourceServingsAndNotSocialCounters() {
        let source = "24K likes, 197 comments. Ingredients: 2 eggs. Mix and cook. Makes 2 servings."
        XCTAssertEqual(RecipeSourceQuantity.servings(2, quote: "Makes 2 servings.", source: source), 2)
        XCTAssertNil(RecipeSourceQuantity.servings(4, quote: "Makes 4 servings.", source: source))
        XCTAssertNil(RecipeSourceQuantity.servings(197, quote: "197 comments", source: source))
        XCTAssertNil(RecipeSourceQuantity.servings(2, quote: nil, source: source))
        XCTAssertEqual(RecipeSourceQuantity.servings(4, quote: "عدد الحصص: ٤", source: "عدد الحصص: ٤"), 4)
    }

    func testExplicitUsedButOmittedButterGetsAnUnknownRowWithoutNegatedOptionalFat() throws {
        let source = "Ingredients: 100 g beef. Fry the beef in butter. Makes 2 servings."
        let input = try RecipeImport.input(url: "", pastedText: source)
        let draft = try RecipeImport.parseResponse(response([row("Beef", quantity: 100, quote: "100 g beef", kcal: 200, protein: 20, fat: 13)]),
            input: input, language: .en)
        XCTAssertEqual(draft.ingredients.count, 2)
        XCTAssertEqual(draft.ingredients.last?.name, "Butter for cooking")
        XCTAssertNil(draft.ingredients.last?.quantity); XCTAssertNil(draft.ingredients.last?.nutrition)
        XCTAssertNil(draft.total); XCTAssertFalse(draft.readyToSave)
        XCTAssertEqual(RecipeSourceQuantity.omittedCookingFats(in: "نشوحه بالزبدة في طاوه", ingredientNames: []).count, 1)
        for negative in ["Fry without butter.", "Do not fry in butter.", "Fry in optional butter if desired.", "نقلي بدون زبدة.", "نشوحه بزبدة حسب الرغبة."] {
            XCTAssertTrue(RecipeSourceQuantity.omittedCookingFats(in: negative, ingredientNames: []).isEmpty, negative)
        }
        XCTAssertTrue(RecipeSourceQuantity.omittedCookingFats(in: "Fry in butter.", ingredientNames: ["Butter"]).isEmpty)
    }
}
