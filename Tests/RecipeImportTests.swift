import XCTest
@testable import LuqmaCore

final class RecipeImportTests: XCTestCase {
    private let sampleKey = "test_Gemini_Key_For_Offline_Unit_Tests_12345"
    private let website = "https://extension.umd.edu/programs/family-consumer-sciences/snap-ed/eat-smart/recipes/banana-pancakes"
    private let pasted = "Cooked rice 200 g, cooked chicken 150 g. Mix and serve. Makes 2 servings."

    private func row(_ name: String = "Cooked rice", quantity: Any = 200, unit: String = "g",
                     kcal: Any = 260, protein: Any = 5.4, carbs: Any = 56, fat: Any = 0.6) -> [String: Any] {
        ["name": name, "quantity": quantity, "sourceQuantityText": "\(name) \(quantity) \(unit)", "unit": unit, "unitLabel": unit == "g" ? "g" : "cup",
         "kcal": kcal, "protein": protein, "carbs": carbs, "fat": fat, "assumption": "Typical cooked food profile; values are estimates."]
    }
    private func payload(rows: [[String: Any]]? = nil, servings: Any = 2, steps: [String] = ["Cook the rice.", "Mix with cooked chicken.", "Serve."],
                         assumptions: [String] = [], available: Bool = true) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["isRecipe": available, "sourceAvailable": available, "title": "Rice with chicken",
            "servings": servings, "sourceServingsText": "Makes \(servings) servings.", "ingredients": rows ?? [row(), row("Cooked chicken", quantity: 150, kcal: 250, protein: 46, carbs: 0, fat: 5.5)],
            "steps": steps, "assumptions": assumptions])
    }
    private func envelope(_ payload: Data, retrieved: String? = nil, retrievalStatus: String = "URL_RETRIEVAL_STATUS_SUCCESS",
                          modality: String? = nil, tokens: Int = 10, finish: String = "STOP", thought: Bool = false) throws -> Data {
        var parts: [[String: Any]] = [["text": try XCTUnwrap(String(data: payload, encoding: .utf8))]]
        if thought { parts.insert(["text": "This is internal thought, not recipe content.", "thought": true], at: 0) }
        var candidate: [String: Any] = ["content": ["parts": parts], "finishReason": finish]
        if let retrieved { candidate["urlContextMetadata"] = ["urlMetadata": [["retrievedUrl": retrieved, "urlRetrievalStatus": retrievalStatus]]] }
        var result: [String: Any] = ["candidates": [candidate]]
        if let modality { result["usageMetadata"] = ["promptTokensDetails": [["modality": modality, "tokenCount": tokens]]] }
        return try JSONSerialization.data(withJSONObject: result)
    }
    private func input(_ text: String? = nil) throws -> RecipeImport.Input {
        try RecipeImport.input(url: "", pastedText: text ?? pasted)
    }
    private func body(_ input: RecipeImport.Input) throws -> [String: Any] {
        let request = try RecipeImport.request(input, language: .en, key: sampleKey)
        XCTAssertEqual(request.url, AnalysisModel.fast.endpoint)
        XCTAssertNil(request.url?.query)
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), sampleKey)
        let bytes = try XCTUnwrap(request.httpBody)
        XCTAssertFalse(String(data: bytes, encoding: .utf8)!.contains(sampleKey))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }

    func testPublicURLNormalizationDropsTrackingAndPrivateFragments() throws {
        let value = try RecipeImport.canonicalURL(" HTTPS://WWW.INSTAGRAM.COM/reel/abc/?igsh=tracking&utm_source=share#private ")
        XCTAssertEqual(value.absoluteString, "https://www.instagram.com/reel/abc/")
        XCTAssertEqual(try RecipeImport.canonicalURL("https://www.instagram.com/reel/DP_xI84DBN0/?dlrf=MXhtc3RwaWUweXk4eg==").absoluteString,
                       "https://www.instagram.com/reel/DP_xI84DBN0/")
        XCTAssertEqual(try RecipeImport.canonicalURL("https://www.tt.site/t/ZSboQ9F2g/").absoluteString, "https://www.tt.site/t/ZSboQ9F2g/")
        XCTAssertEqual(try RecipeImport.canonicalURL("https://www.bbcgoodfood.com/recipes/soup?sort=popular&fbclid=tracking").query, "sort=popular")
        XCTAssertEqual(try RecipeImport.canonicalURL("https://www.example.com:443/recipe").absoluteString, "https://www.example.com/recipe")
    }

    func testRejectsPrivateHostsCredentialsAndUnsafeLinks() {
        for link in ["http://www.bbcgoodfood.com/recipe", "https://localhost/recipe", "https://meal.local/recipe", "https://10.0.0.1/recipe",
                     "https://127.0.0.1/recipe", "https://[::1]/recipe", "https://2130706433/recipe", "https://0x7f000001/recipe",
                     "https://user:password@www.example.com/recipe", "https://www.example.com:8080/recipe", "https://preview.ngrok.app/recipe",
                     "https://10.0.0.1.nip.io/recipe", "https://www.example.com/path?access_token=secret", "https://www.example.com/?api_key=secret",
                     "https://www.example.com/?customToken=secret", "https://www.example.com/?value=%0Aprivate", "https://www.example.com/line%0Afeed"] {
            XCTAssertThrowsError(try RecipeImport.canonicalURL(link), link)
        }
    }

    func testYouTubeLinksUseOneCanonicalVideoID() throws {
        for link in ["https://youtu.be/9hE5-98ZeCg?si=tracking", "https://m.youtube.com/shorts/9hE5-98ZeCg", "https://www.youtube.com/embed/9hE5-98ZeCg",
                     "https://www.youtube.com/watch?v=9hE5-98ZeCg&t=120&list=playlist"] {
            let source = try RecipeImport.input(url: link, pastedText: "")
            XCTAssertEqual(source.sourceKind, .youtube)
            XCTAssertEqual(source.sourceURL?.absoluteString, "https://www.youtube.com/watch?v=9hE5-98ZeCg")
        }
        for link in ["https://www.youtube.com/watch?v=short", "https://www.youtube.com/watch?v=9hE5-98ZeCg&v=9hE5-98ZeCg", "https://www.youtube.com/playlist?list=abc"] {
            XCTAssertThrowsError(try RecipeImport.canonicalURL(link))
        }
    }

    func testInputRequiresBoundedRecipeContentAndTextFallbackStaysHonest() throws {
        XCTAssertThrowsError(try RecipeImport.input(url: "", pastedText: ""))
        XCTAssertThrowsError(try RecipeImport.input(url: "", pastedText: "too short"))
        XCTAssertThrowsError(try RecipeImport.input(url: "", pastedText: String(repeating: "a", count: RecipeImport.maximumTextCharacters + 1)))
        let source = try RecipeImport.input(url: website, pastedText: pasted)
        XCTAssertEqual(source.sourceKind, .pastedText)
        XCTAssertTrue(source.sourceKind.isPastedText)
        let request = try body(source)
        XCTAssertNil(request["tools"])
        let contents = try XCTUnwrap(request["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        XCTAssertTrue(parts.allSatisfy { $0["fileData"] == nil })
        XCTAssertTrue((parts.last?["text"] as? String)?.contains("reference URL was not fetched") == true)
    }

    func testRequestChoosesActualURLToolOrBoundedVideoAndNullableNutrition() throws {
        let webBody = try body(RecipeImport.input(url: website, pastedText: ""))
        let tools = try XCTUnwrap(webBody["tools"] as? [[String: Any]])
        XCTAssertNotNil(tools.first?["urlContext"])
        let config = try XCTUnwrap(webBody["generationConfig"] as? [String: Any])
        XCTAssertEqual((config["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String, "MINIMAL")
        XCTAssertEqual(config["responseMimeType"] as? String, "application/json")
        let schema = try XCTUnwrap(config["responseJsonSchema"] as? [String: Any])
        let encoded = String(data: try JSONSerialization.data(withJSONObject: schema), encoding: .utf8)!
        XCTAssertTrue(encoded.contains("null")); XCTAssertFalse(encoded.contains("minimum"))
        let videoBody = try body(RecipeImport.input(url: "https://youtu.be/9hE5-98ZeCg", pastedText: ""))
        XCTAssertNil(videoBody["tools"])
        let contents = try XCTUnwrap(videoBody["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        XCTAssertEqual((parts.first?["fileData"] as? [String: Any])?["fileUri"] as? String, "https://www.youtube.com/watch?v=9hE5-98ZeCg")
        XCTAssertEqual((parts.first?["videoMetadata"] as? [String: Any])?["endOffset"] as? String, "600s")
    }

    func testCapturedPublicCaptionUsesSourceTextWithoutPretendingVideoWasProcessed() throws {
        let url = try RecipeImport.canonicalURL("https://www.instagram.com/reel/recipe123/")
        let content = RecipeSourceContent(text: "2 eggs, 5 g olive oil. Whisk eggs, fry in oil. Makes 2 servings.", kind: .publicCaption)
        let source = try RecipeImport.input(url: url.absoluteString, pastedText: "").withCapturedSource(content, finalURL: url)
        let request = try body(source)
        XCTAssertNil(request["tools"])
        let contents = try XCTUnwrap(request["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        XCTAssertTrue(parts.allSatisfy { $0["fileData"] == nil })
        XCTAssertTrue((parts.last?["text"] as? String)?.contains("not a transcript") == true)
        let draft = try RecipeImport.parseResponse(envelope(payload()), input: source, language: .en)
        XCTAssertEqual(draft.sourceKind, .website)
        XCTAssertEqual(draft.sourceURL, url.absoluteString)
        XCTAssertTrue(draft.assumptions.contains { $0.contains("public post description") })
        XCTAssertFalse(draft.assumptions.contains { $0.contains("ten minutes") })
        // Identical model output without captured source evidence remains invalid.
        XCTAssertThrowsError(try RecipeImport.parseResponse(envelope(payload()),
            input: RecipeImport.input(url: url.absoluteString, pastedText: ""), language: .en))
    }

    func testBackupRequestRetainsSchemaAndUsesShortSeparateDeadline() throws {
        let request = try RecipeImport.request(input(), language: .en, key: sampleKey, model: .backup)
        XCTAssertEqual(request.url, AnalysisModel.backup.endpoint)
        XCTAssertEqual(request.timeoutInterval, AnalysisAttemptPolicy.backupTimeout)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        let config = try XCTUnwrap(body["generationConfig"] as? [String: Any])
        let format = try XCTUnwrap(config["responseFormat"] as? [String: Any])
        XCTAssertNotNil((format["text"] as? [String: Any])?["schema"])
        XCTAssertNil(body["tools"])
    }

    func testWebsiteRequiresSuccessfulRetrievalOfThisExactSource() throws {
        let source = try RecipeImport.input(url: website, pastedText: "")
        let data = try payload()
        let draft = try RecipeImport.parseResponse(envelope(data, retrieved: website + "/", thought: true), input: source, language: .en)
        XCTAssertTrue(draft.readyToSave)
        XCTAssertEqual(draft.sourceURL, website)
        for response in [try envelope(data), try envelope(data, retrieved: "https://www.example.com/other"),
                         try envelope(data, retrieved: website, retrievalStatus: "URL_RETRIEVAL_STATUS_UNSAFE"),
                         try envelope(data, retrieved: website, finish: "MAX_TOKENS")] {
            XCTAssertThrowsError(try RecipeImport.parseResponse(response, input: source, language: .en))
        }
    }

    func testYouTubeRequiresProcessedVideoTokensNotJustModelClaim() throws {
        let source = try RecipeImport.input(url: "https://www.youtube.com/watch?v=9hE5-98ZeCg", pastedText: "")
        let data = try payload()
        XCTAssertTrue(try RecipeImport.parseResponse(envelope(data, modality: "VIDEO"), input: source, language: .en).readyToSave)
        for response in [try envelope(data), try envelope(data, modality: "TEXT"), try envelope(data, modality: "VIDEO", tokens: 0)] {
            XCTAssertThrowsError(try RecipeImport.parseResponse(response, input: source, language: .en))
        }
    }

    func testMissingAmountOrNutrientsAreUnknownUntilExplicitRepair() throws {
        let source = try input()
        var draft = try RecipeImport.parsePayload(payload(rows: [row(quantity: NSNull(), protein: NSNull())], servings: NSNull()), input: source, language: .en)
        XCTAssertNil(draft.ingredients[0].quantity)
        XCTAssertNil(draft.ingredients[0].nutrition)
        XCTAssertNil(draft.total); XCTAssertNil(draft.perServing); XCTAssertFalse(draft.readyToSave)
        draft.ingredients[0] = try draft.ingredients[0].changingQuantity(200)
        XCTAssertNil(draft.ingredients[0].nutrition)
        draft.ingredients[0].nutrition = Nutrition(kcal: 260, protein: 5.4, carbs: 56, fat: 0.6)
        draft.servings = 2
        XCTAssertTrue(draft.readyToSave)
        XCTAssertEqual(try XCTUnwrap(draft.perServing).kcal, 130, accuracy: 1e-9)
        let partial = try RecipeImport.parsePayload(payload(rows: [row(protein: NSNull())]), input: source, language: .en)
        XCTAssertNil(partial.ingredients[0].nutrition); XCTAssertNil(partial.total)
    }

    func testWholeIngredientTotalsPersistAsReviewedNativeRecipeAndBackup() throws {
        let draft = try RecipeImport.parseResponse(envelope(payload()), input: input(), language: .en)
        XCTAssertEqual(try XCTUnwrap(draft.total).kcal, 510, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(draft.perServing).kcal, 255, accuracy: 1e-9)
        let recipe = try draft.recipe(language: .en)
        XCTAssertEqual(recipe.total, draft.total)
        XCTAssertEqual(try recipe.food().total(1, unit: .serving).kcal, 255, accuracy: 1e-9)
        let metadata = try XCTUnwrap(recipe.importInfo)
        XCTAssertTrue(metadata.nutritionIsEstimated)
        XCTAssertEqual(metadata.sourceKind, .pastedText)
        XCTAssertEqual(metadata.ingredientUnitLabels[recipe.ingredients[0].id.uuidString], "g")
        var snapshot = DiarySnapshot(); snapshot.recipes = [recipe]
        XCTAssertEqual(try Backup.decode(Backup.encode(snapshot)).recipes, [recipe])
    }

    func testQuantityChangeScalesFullIngredientNutritionExactlyOnce() throws {
        let draft = try RecipeImport.parsePayload(payload(), input: input(), language: .en)
        let changed = try draft.ingredients[0].changingQuantity(100)
        XCTAssertEqual(changed.quantity, 100)
        XCTAssertEqual(try XCTUnwrap(changed.nutrition).kcal, 130, accuracy: 1e-9)
        XCTAssertEqual(changed.id, draft.ingredients[0].id)
        for amount in [0.0, -1, 10001, Double.infinity, Double.nan] { XCTAssertThrowsError(try changed.changingQuantity(amount)) }
    }

    func testRejectsImpossibleNutritionButDoesNotInferGramsForHouseholdUnits() throws {
        let source = try input()
        for values in [row(quantity: 1, kcal: 100000, protein: 0, carbs: 25000, fat: 0),
                       row(quantity: 10, kcal: 300, protein: 0, carbs: 75, fat: 0),
                       row(kcal: 900, protein: 0, carbs: 0, fat: 0)] {
            XCTAssertThrowsError(try RecipeImport.parsePayload(payload(rows: [values]), input: source, language: .en))
        }
        let household = try RecipeImport.parsePayload(payload(rows: [row(quantity: 1, unit: "serving")]), input: source, language: .en)
        XCTAssertTrue(household.readyToSave)
        XCTAssertEqual(household.ingredients[0].unit, .serving)
        var bad = household; bad.ingredients[0].nutrition = Nutrition(kcal: 1000, protein: 0, carbs: 0, fat: 0)
        XCTAssertFalse(bad.readyToSave)
    }

    func testTinyYieldAndMissingStepsCannotSaveUnloggableRecipe() throws {
        var draft = try RecipeImport.parsePayload(payload(), input: input(), language: .en)
        draft.servings = 0.000001
        XCTAssertNil(draft.perServing); XCTAssertFalse(draft.readyToSave)
        draft.servings = 2; draft.steps = []
        XCTAssertFalse(draft.readyToSave)
        var duplicate = try RecipeImport.parsePayload(payload(), input: input(), language: .en)
        duplicate.ingredients[1].id = duplicate.ingredients[0].id
        XCTAssertFalse(duplicate.readyToSave)
    }

    func testPartialVideoWarningsRemainBoundedAndNoSourceFabricationIsAccepted() throws {
        let source = try RecipeImport.input(url: "https://youtu.be/9hE5-98ZeCg", pastedText: "")
        let partial = try RecipeImport.parsePayload(payload(rows: [row(quantity: NSNull(), protein: NSNull())], servings: NSNull(), steps: [],
            assumptions: (1...12).map { "Source limitation \($0)" }), input: source, language: .en)
        XCTAssertLessThanOrEqual(partial.assumptions.count, 16)
        XCTAssertFalse(partial.readyToSave)
        XCTAssertThrowsError(try RecipeImport.parsePayload(payload(available: false), input: source, language: .en))
        XCTAssertThrowsError(try RecipeImport.parsePayload(Data(repeating: 32, count: 256 * 1024 + 1), input: source, language: .en))
        XCTAssertThrowsError(try RecipeImport.parseResponse(Data(repeating: 32, count: RecipeImport.maximumResponseBytes + 1), input: source, language: .en))
        XCTAssertThrowsError(try RecipeImport.parseResponse(Data(), input: source, language: .en, status: 429))
    }

    func testMetadataValidationRejectsPrivateSourceAndStaleIngredientIDs() throws {
        let recipe = try RecipeImport.parsePayload(payload(), input: input(), language: .en).recipe()
        var metadata = try XCTUnwrap(recipe.importInfo)
        metadata.sourceURL = "https://www.example.com/recipe?token=private"
        XCTAssertThrowsError(try metadata.validate(ingredients: recipe.ingredients))
        metadata.sourceURL = nil
        metadata.ingredientUnitLabels[UUID().uuidString] = "cup"
        XCTAssertThrowsError(try metadata.validate(ingredients: recipe.ingredients))
        let kept = Array(recipe.ingredients.prefix(1))
        let pruned = metadata.pruned(for: kept)
        XCTAssertEqual(pruned.ingredientUnitLabels.count, 1)
        XCTAssertNoThrow(try pruned.validate(ingredients: kept))
        metadata = try XCTUnwrap(recipe.importInfo)
        metadata.ingredientUnitLabels = [recipe.ingredients[0].id.uuidString.lowercased(): "g"]
        XCTAssertThrowsError(try metadata.validate(ingredients: recipe.ingredients))
    }
}
