import XCTest
@testable import LuqmaCore

final class CoreTests: XCTestCase {
    func testFoodSearchKeepsEveryMatchingVariantBeyondFortyResults() {
        let foods = (0..<125).map { index in
            Food(catalogID: "rice:\(index)", name: "أرز صنف \(index)", nameEn: "Rice variety \(index)",
                 nutrition: Nutrition(kcal: 120, protein: 3, carbs: 25, fat: 1))
        }
        let index = FoodSearch.Index(foods)
        XCTAssertEqual(index.results("أرز").count, 125)
        XCTAssertEqual(Set(index.results("rice").map(\.id)), Set(foods.map(\.id)))
        XCTAssertEqual(index.results("rice").map(\.id), FoodSearch.results("rice", in: Array(foods.reversed())).map(\.id))
        XCTAssertTrue(index.results("??? \n").isEmpty)
    }

    func testFoodSearchMatchesArabicDiacriticsPunctuationAliasesBrandsAndBothLanguages() {
        let milk = Food(catalogID: "milk", name: "حَليب قليل الدّسم", nameEn: "Low-fat milk",
                        aliases: "لبن، حليب بقري | Dairy drink", brand: "المراعي Almarai")
        for query in ["حليب", "حليب-قليل", "الدسم حليب", "MILK low", "milk almarai", "لبن", "dairy drink", "المراعي", "حليب MILK"] {
            XCTAssertTrue(FoodSearch.matches(milk, query: query), query)
        }
        XCTAssertFalse(FoodSearch.matches(milk, query: "milk chocolate"))
        XCTAssertFalse(FoodSearch.matches(milk, query: ""))
        XCTAssertEqual(FoodSearch.normalized("أَرْز… ١٠۰% / CＡＦÉ\n"), "ارز 100 cafe")
        XCTAssertEqual(FoodSearch.normalized("شـاورما، إِجّاص؛ جبنة"), "شاورما اجاص جبنه")
        XCTAssertTrue(FoodSearch.matches(Food(name: "أَرْز"), query: "ارز"))
        XCTAssertEqual(FoodSearch.normalized("ا\u{0654}رز"), FoodSearch.normalized("أرز"))
        XCTAssertEqual(FoodSearch.normalized("إِجّاص"), FoodSearch.normalized("اجاص"))
    }

    func testFoodSearchRanksExactNamesThenPrefixesAndKeepsDistinctBrandProducts() {
        let nutrition = Nutrition(kcal: 120, protein: 3, carbs: 25, fat: 1)
        let exact = Food(catalogID: "exact", name: "Rice", nutrition: nutrition)
        let incompleteExact = Food(catalogID: "missing", name: "Rice")
        let prefix = Food(catalogID: "prefix", name: "Rice cooked", nutrition: nutrition)
        let inside = Food(catalogID: "inside", name: "Brown rice cooked", nutrition: nutrition)
        let brand = Food(catalogID: "brand", name: "Cereal", brand: "Rice Farms", nutrition: nutrition)
        let results = FoodSearch.results("rice", in: [brand, inside, prefix, incompleteExact, exact])
        XCTAssertEqual(results.map(\.id), ["exact", "missing", "prefix", "inside", "brand"])
        let variants = [Food(name: "Rice", brand: "Brand A", barcode: "12345678"),
                        Food(name: "Rice", brand: "Brand B", barcode: "87654321")]
        XCTAssertEqual(FoodSearch.results("rice", in: variants).count, 2)
        XCTAssertEqual(FoodSearch.results("brand rice", in: variants).count, 2)
    }

    func testFoodSearchDeduplicatesIdentifiersAndUsesNewestSavedNutritionWithoutMutatingIDs() {
        let original = Food(catalogID: "usda:rice", name: "أرز", nameEn: "Rice",
                            nutrition: Nutrition(kcal: 100, protein: 2, carbs: 20, fat: 1))
        var edited = original
        edited.kcal = 130
        let index = FoodSearch.Index([original, original])
        let matches = index.results("ارز", additional: [edited])
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].kcal, 130)
        XCTAssertEqual(matches[0].id, "usda:rice")
        XCTAssertEqual(index.results("rice")[0].kcal, 100)
        let alias = Food(catalogID: "alias", name: "Oryza", aliases: "Rice, أرز")
        XCTAssertEqual(FoodSearch.results("rice", in: [alias, original]).map(\.id), ["usda:rice", "alias"])
    }

    func testFoodSearchSourcePaginationContinuesAfterFilteredPagesAndExposesSourceWindow() throws {
        // OFF's count/page_count describe source hits before the app excludes
        // category-only matches; the first displayed page can contain no foods.
        var response: [String: Any] = ["hits": [["product_name": "Unrelated category match"]],
                                      "page": 1, "page_size": 50, "page_count": 200,
                                      "count": 10_000, "is_count_exact": false, "timed_out": false]
        let first = try XCTUnwrap(FoodSearchPage.pagination(response, requestedPage: 1, pageSize: 50))
        XCTAssertEqual(first.nextPage, 2)
        XCTAssertNil(first.sourceTotal)
        XCTAssertFalse(first.reachedSourceWindow)
        XCTAssertTrue(FoodSearch.results("milk", in: [Food(name: "Unrelated category match")]).isEmpty)
        response["page"] = 200
        let boundary = try XCTUnwrap(FoodSearchPage.pagination(response, requestedPage: 200, pageSize: 50))
        XCTAssertNil(boundary.nextPage)
        XCTAssertTrue(boundary.reachedSourceWindow)
        response["count"] = 9_951
        response["is_count_exact"] = true
        let final = try XCTUnwrap(FoodSearchPage.pagination(response, requestedPage: 200, pageSize: 50))
        XCTAssertNil(final.nextPage)
        XCTAssertEqual(final.sourceTotal, 9_951)
        XCTAssertFalse(final.reachedSourceWindow)
    }

    func testFoodSearchPaginationRejectsStaleIncompleteAndErroredSourceResponses() {
        let response: [String: Any] = ["hits": [["code": "12345678"]], "page": 2, "page_size": 50,
                                     "page_count": 3, "count": 120, "is_count_exact": true, "timed_out": false]
        XCTAssertNil(FoodSearchPage.pagination(response, requestedPage: 1, pageSize: 50))
        let failures: [(String, Any)] = [("timed_out", true), ("errors", [] as [Any]), ("count", -1), ("page_size", 20)]
        for (key, value) in failures {
            var failed = response
            failed[key] = value
            XCTAssertNil(FoodSearchPage.pagination(failed, requestedPage: 2, pageSize: 50))
        }
        var empty = response
        empty["hits"] = [] as [Any]
        XCTAssertNil(FoodSearchPage.pagination(empty, requestedPage: 2, pageSize: 50)?.nextPage)
    }

    func testVisionUsesAppAllowanceAndCompactModelOnEightGBPhones() {
        let compact = 1_782_040_921, full = 3_093_767_283
        // An 8 GB phone can still give this app a much smaller allowance.
        XCTAssertEqual(VisionResources.choose(available: 3_300_000_000, physical: 8_000_000_000, mobile: true,
                                             compactWeights: compact, fullWeights: full), .compact)
        XCTAssertEqual(VisionResources.choose(available: 6_000_000_000, physical: 8_000_000_000, mobile: true,
                                             compactWeights: compact, fullWeights: full), .compact)
        XCTAssertNil(VisionResources.choose(available: 2_000_000_000, physical: 8_000_000_000, mobile: true,
                                            compactWeights: compact, fullWeights: full))
        XCTAssertNil(VisionResources.choose(available: 0, physical: 12_000_000_000, mobile: true,
                                            compactWeights: compact, fullWeights: full))
    }
    func testVisionAdmissionRechecksShrinkingBudgetAndKeepsSafetyReserve() {
        let compact = 1_782_040_921, full = 3_093_767_283
        let required = VisionResources.requiredBytes(weights: full, tier: .full)
        XCTAssertEqual(VisionResources.choose(available: required, physical: 12_000_000_000, mobile: true,
                                             compactWeights: compact, fullWeights: full), .full)
        XCTAssertEqual(VisionResources.choose(available: required - 1, physical: 12_000_000_000, mobile: true,
                                             compactWeights: compact, fullWeights: full), .compact)
        XCTAssertEqual(VisionResources.choose(available: required, physical: 12_000_000_000, mobile: true,
                                             compactWeights: compact, fullWeights: full, preferCompact: true), .compact)
        let minimum = VisionResources.requiredBytes(weights: compact, tier: .compact)
        XCTAssertNil(VisionResources.choose(available: minimum - 1, physical: 12_000_000_000, mobile: true,
                                            compactWeights: compact, fullWeights: full))
        XCTAssertGreaterThan(minimum - compact, VisionResources.stopHeadroom)
        XCTAssertLessThan(VisionResources.imagePixels(.compact), VisionResources.imagePixels(.full))
        XCTAssertLessThan(VisionResources.prefillStep(.compact), VisionResources.prefillStep(.full))
    }
    func testLiveHealthWeightDeletionFallsBackAndPreservesManual() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-08T12:00:00Z"))
        let earlier = HealthWeightSample(id: UUID(), kg: 81, end: date.timeIntervalSince1970)
        let later = HealthWeightSample(id: UUID(), kg: 80.5, end: date.addingTimeInterval(3600).timeIntervalSince1970)
        let now = date.addingTimeInterval(86400)
        let first = HealthSync.apply(added: [later, earlier], deleted: [], to: HealthSyncState(), weights: [], now: now)
        XCTAssertEqual(first.weights.count, 1)
        XCTAssertEqual(first.weights[0].kg, 80.5)
        let removedLatest = HealthSync.apply(added: [], deleted: [later.id], to: first.cache, weights: first.weights, now: now)
        XCTAssertEqual(removedLatest.weights[0].kg, 81)
        let removedAll = HealthSync.apply(added: [], deleted: [earlier.id], to: removedLatest.cache, weights: removedLatest.weights, now: now)
        XCTAssertTrue(removedAll.weights.isEmpty)
        let manual = WeightReading(day: earlier.day, kg: 79, source: "Manual", timestamp: now.timeIntervalSince1970)
        let keptManual = HealthSync.apply(added: [later], deleted: [earlier.id], to: first.cache, weights: [manual], now: now)
        XCTAssertEqual(keptManual.weights, [manual])
    }
    func testLiveHealthEmptyReadAndInvalidSamplesDoNotEraseHistory() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-08T12:00:00Z"))
        let valid = HealthWeightSample(id: UUID(), kg: 82, end: date.timeIntervalSince1970)
        let cache = HealthSyncState(records: [valid])
        let reading = WeightReading(day: valid.day, kg: 82, source: "Apple Health", timestamp: valid.end)
        let result = HealthSync.apply(added: [
            HealthWeightSample(id: UUID(), kg: .nan, end: valid.end),
            HealthWeightSample(id: UUID(), kg: 600, end: valid.end),
            HealthWeightSample(id: UUID(), kg: 80, end: valid.end + 864000)
        ], deleted: [UUID()], to: cache, weights: [reading], now: date.addingTimeInterval(3600))
        XCTAssertEqual(result.cache.records, cache.records)
        XCTAssertEqual(result.weights, [reading])
        let empty = HealthSync.apply(added: [], deleted: [], to: result.cache, weights: result.weights)
        XCTAssertEqual(empty.weights, [reading])
        let deletedInSameBatch = HealthSync.apply(added: [valid], deleted: [valid.id], to: cache, weights: [reading])
        XCTAssertTrue(deletedInSameBatch.cache.records.isEmpty)
        XCTAssertTrue(deletedInSameBatch.weights.isEmpty)
    }
    func testHealthCacheBackupMigrationValidationAndCursorIsolation() throws {
        var current = DiarySnapshot()
        current.healthEnabled = true
        current.healthSync = HealthSyncState(anchor: Data([1, 2]), activityDay: "2026-10-09", steps: 10000, activeCalories: 420, heightCM: 180, updatedAt: 1_792_000_000)
        let data = try Backup.encode(current)
        XCTAssertEqual(try Backup.decode(data).healthSync, current.healthSync)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "healthSync")
        XCTAssertNil(try Backup.decode(JSONSerialization.data(withJSONObject: legacy)).healthSync)
        var incoming = DiarySnapshot(); incoming.healthSync = HealthSyncState(anchor: Data([9]), steps: 2)
        XCTAssertEqual(try Backup.merge(incoming, into: current).healthSync, current.healthSync)
        current.healthSync?.steps = .infinity
        XCTAssertThrowsError(try Backup.encode(current))
    }
    func testHealthExportUnitsDailyPriorityAndFutureFiltering() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <HealthData locale="en_US">
        <Record type="HKQuantityTypeIdentifierBodyMass" unit="kg" value="89" endDate="2026-10-08 10:00:00 +0000"/>
        <Record type="HKQuantityTypeIdentifierBodyMass" unit="lb" value="200" endDate="2026-10-08 20:00:00 +0000"/>
        <Record type="HKQuantityTypeIdentifierBodyMass" unit="g" value="91000" endDate="2026-10-09 08:00:00 +0000"/>
        <Record type="HKQuantityTypeIdentifierBodyMass" unit="kg" value="92" endDate="2028-10-09 08:00:00 +0000"/>
        <Record type="HKQuantityTypeIdentifierBodyMass" unit="kg" value="NaN" endDate="2026-10-09 09:00:00 +0000"/>
        <Record type="HKQuantityTypeIdentifierBodyMass" unit="kg" value="500" endDate="2026-10-09 09:00:00 +0000"/>
        <Record type="HKQuantityTypeIdentifierHeight" unit="m" value="1.81" endDate="2026-10-08 12:00:00 +0000"/>
        <Record type="HKQuantityTypeIdentifierStepCount" unit="count" value="8000" endDate="2026-10-09 12:00:00 +0000"/>
        </HealthData>
        """
        let result = try HealthImport.read(Data(xml.utf8), now: Date(timeIntervalSince1970: 1_792_000_000))
        XCTAssertEqual(result.weights.count, 2)
        XCTAssertEqual(result.weights[0].kg, 90.718474, accuracy: 1e-8)
        XCTAssertEqual(result.weights[1].kg, 91)
        XCTAssertEqual(result.weights[0].source, "Apple Health")
        XCTAssertEqual(try XCTUnwrap(result.heightCM), 181, accuracy: 1e-8)
        XCTAssertThrowsError(try HealthImport.read(Data("<notHealth/>".utf8)))
        XCTAssertThrowsError(try HealthImport.read(Data("<HealthData><Record".utf8)))
    }
    func testProfileDetectsHealthCapabilityWithoutAssumingUnknown() throws {
        func profile(_ entitlements: [String: Any]) throws -> Data {
            let plist = try PropertyListSerialization.data(fromPropertyList: ["Entitlements": entitlements], format: .xml, options: 0)
            return Data([0x30, 0x81, 0]) + plist + Data([0, 0xff])
        }
        XCTAssertEqual(HealthSigning.profileSupportsHealth(try profile(["com.apple.developer.healthkit": true])), true)
        XCTAssertEqual(HealthSigning.profileSupportsHealth(try profile(["get-task-allow": true])), false)
        XCTAssertNil(HealthSigning.profileSupportsHealth(Data("not a profile".utf8)))
        XCTAssertEqual(HealthSigning.profileSupportsBackgroundHealth(try profile(["com.apple.developer.healthkit": true, "com.apple.developer.healthkit.background-delivery": true])), true)
        XCTAssertEqual(HealthSigning.profileSupportsBackgroundHealth(try profile(["com.apple.developer.healthkit": true])), false)
        XCTAssertEqual(HealthSigning.profileSupportsBackgroundHealth(try profile(["com.apple.developer.healthkit.background-delivery": true])), false)
        XCTAssertNil(HealthSigning.profileSupportsBackgroundHealth(Data("unknown".utf8)))
    }
    func testGenerativeMealPreservesShawarmaDipsCountAndCatalogNutrition() throws {
        let foods = try resource("photo-foods", [PhotoFood].self)
        let json = """
        {"food_present":true,"items":[
        {"id":"chicken-shawarma","grams":420,"min_grams":320,"max_grams":550,"confidence":0.8,"count":10,"nutrition_per_100g":{"kcal":99999,"protein":99999,"carbs":0,"fat":0}},
        {"id":"garlic-sauce","grams":45,"min_grams":25,"max_grams":65,"confidence":0.5},
        {"id":"tahini-sauce","grams":40,"min_grams":25,"max_grams":60,"confidence":0.55}]}
        """
        let result = try VisionMeal.decode("```json\n" + json + "\n```", description: "", foods: foods)
        XCTAssertEqual(result.parts.count, 3)
        XCTAssertEqual(result.parts[0].count, 10)
        XCTAssertEqual(result.parts[0].grams, 420)
        XCTAssertEqual(result.parts[0].nutrition.kcal, try XCTUnwrap(foods.first { $0.id == "chicken-shawarma" }).kcal * 4.2, accuracy: 1e-8)
        XCTAssertTrue(result.parts[1].tentative)
        XCTAssertLessThan(result.parts[0].low, result.parts[0].grams)
        XCTAssertGreaterThan(result.parts[0].high, result.parts[0].grams)
        let weighed = try VisionMeal.decode(json, description: "شاورما دجاج ٣٠٠ جم", foods: foods)
        XCTAssertEqual(weighed.parts[0].grams, 300)
        XCTAssertEqual(weighed.parts[0].low, 300)
        XCTAssertEqual(weighed.parts[0].high, 300)
    }
    func testVisionRejectsDuplicateAndImpossibleMassAndDoesNotInventFood() throws {
        let foods = try resource("photo-foods", [PhotoFood].self)
        let item = "{\"id\":\"169836\",\"grams\":120,\"min_grams\":80,\"max_grams\":180,\"confidence\":0.7}"
        XCTAssertThrowsError(try VisionMeal.decode("{\"food_present\":true,\"items\":[\(item),\(item)]}", description: "", foods: foods))
        XCTAssertThrowsError(try VisionMeal.decode("{\"food_present\":true,\"items\":[\(item.replacingOccurrences(of: "120", with: "6000"))]}", description: "", foods: foods))
        XCTAssertTrue(try VisionMeal.decode("{\"food_present\":false,\"items\":[]}", description: "شاورما", foods: foods).parts.isEmpty)
        let hinted = try VisionMeal.decode("{\"food_present\":true,\"items\":[\(item)]}", description: "شاورما عربي ١٠ قطع وعلبة ثوم وعلبة طحينة", foods: foods)
        XCTAssertTrue(hinted.parts.contains { $0.food.id == "chicken-shawarma" })
        XCTAssertTrue(try XCTUnwrap(hinted.parts.first { $0.food.id == "tahini-sauce" }).tentative)
    }
    func testUnknownFoodRequiresPlausibleNutritionAndIsMarkedAsAI() throws {
        let foods = try resource("photo-foods", [PhotoFood].self)
        let json = """
        {"food_present":true,"items":[{"id":null,"name_ar":"وجبة محلية","name_en":"Regional meal","grams":220,"min_grams":150,"max_grams":310,"confidence":0.8,"nutrition_per_100g":{"kcal":240,"protein":12,"carbs":30,"fat":8}}]}
        """
        let result = try VisionMeal.decode(json, description: "", foods: foods)
        XCTAssertEqual(result.parts.count, 1); XCTAssertTrue(result.parts[0].tentative)
        XCTAssertEqual(result.parts[0].food.food.source, "AI nutrition estimate")
        let invalid = json.replacingOccurrences(of: "\"fat\":8", with: "\"fat\":95")
        XCTAssertThrowsError(try VisionMeal.decode(invalid, description: "", foods: foods))
        let inconsistent = json.replacingOccurrences(of: "\"kcal\":240", with: "\"kcal\":180")
        let repaired = try VisionMeal.decode(inconsistent, description: "", foods: foods)
        XCTAssertEqual(try XCTUnwrap(repaired.parts.first).food.nutrition.kcal, 240)
        XCTAssertTrue(try XCTUnwrap(repaired.parts.first).tentative)
    }
    func testVisionDoesNotSilentlyLoseObservedGenericWrapDipsAndSides() throws {
        let foods = try resource("photo-foods", [PhotoFood].self)
        // The compact runtime recognized these six components but omitted
        // nutrition, previously leaving only chicken and plain bread in the UI.
        let incomplete = """
        {"food_present":true,"uncertain":false,"items":[
        {"name_en":"grilled chicken strips","grams":250,"min_grams":200,"max_grams":300,"count":8},
        {"name_en":"dip","grams":120,"min_grams":100,"max_grams":160,"count":1},
        {"name_en":"pita wrap","grams":120,"min_grams":100,"max_grams":160,"count":1},
        {"name_en":"pickled vegetables","grams":75,"min_grams":70,"max_grams":80,"count":2},
        {"name_en":"flatbread","grams":200,"min_grams":180,"max_grams":220,"count":3},
        {"name_en":"dip bowl","grams":120,"min_grams":100,"max_grams":160,"count":1}]}
        """
        XCTAssertThrowsError(try VisionMeal.decode(incomplete, description: "", foods: foods))
        XCTAssertEqual(try VisionMeal.nutritionRequests(incomplete, description: "", foods: foods), [
            VisionMeal.NutritionRequest(index: 1, name_en: "dip"),
            VisionMeal.NutritionRequest(index: 2, name_en: "pita wrap"),
            VisionMeal.NutritionRequest(index: 3, name_en: "pickled vegetables"),
            VisionMeal.NutritionRequest(index: 5, name_en: "dip bowl")
        ])
        var repaired = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(incomplete.utf8)) as? [String: Any])
        var items = try XCTUnwrap(repaired["items"] as? [[String: Any]])
        let estimates: [[String: Double]] = [
            ["kcal": 165, "protein": 31, "carbs": 0, "fat": 4.5],
            ["kcal": 195, "protein": 3, "carbs": 12, "fat": 15],
            ["kcal": 220, "protein": 8, "carbs": 29, "fat": 8],
            ["kcal": 28, "protein": 1, "carbs": 6, "fat": 0],
            ["kcal": 250, "protein": 8, "carbs": 50, "fat": 2],
            ["kcal": 170, "protein": 4, "carbs": 7, "fat": 14]
        ]
        for index in items.indices { items[index]["nutrition_per_100g"] = estimates[index] }
        repaired["items"] = items; repaired["uncertain"] = true
        let json = try XCTUnwrap(String(data: JSONSerialization.data(withJSONObject: repaired), encoding: .utf8))
        let result = try VisionMeal.decode(json, description: "", foods: foods)
        XCTAssertEqual(result.parts.count, 6)
        XCTAssertEqual(result.parts.reduce(0) { $0 + $1.grams }, 885)
        XCTAssertEqual(result.parts.first { $0.food.id == "171534" }?.grams, 250)
        XCTAssertEqual(result.parts.first { $0.food.id == "172816" }?.grams, 200)
        for name in ["dip", "pita wrap", "pickled vegetables", "dip bowl"] {
            let part = try XCTUnwrap(result.parts.first { $0.food.nameEn == name })
            XCTAssertTrue(part.food.id.hasPrefix("ai:")); XCTAssertTrue(part.tentative)
            XCTAssertEqual(part.food.food.source, "AI nutrition estimate")
            XCTAssertEqual(part.food.nutrition.kcal, part.food.nutrition.macroCalories, accuracy: 1e-8)
        }
        XCTAssertFalse(result.parts.contains { ["chicken-shawarma", "garlic-sauce", "tahini-sauce"].contains($0.food.id) })
        XCTAssertTrue(result.unmatched)
    }
    func testTextNutritionRepairPreservesAuditedIdentitiesQuantitiesAndCatalogNutrition() throws {
        let foods = try resource("photo-foods", [PhotoFood].self)
        let audited = """
        {"food_present":true,"items":[
        {"name_en":"grilled chicken strips","grams":250,"min_grams":200,"max_grams":300,"count":8},
        {"name_en":"pita wrap","grams":120,"min_grams":100,"max_grams":160,"count":1},
        {"name_en":"dip bowl","grams":20,"min_grams":18,"max_grams":22,"count":1},
        {"name_en":"plain flatbread","grams":200,"min_grams":180,"max_grams":220,"count":3}]}
        """
        let requests = try VisionMeal.nutritionRequests(audited, description: "", foods: foods)
        XCTAssertEqual(requests.map { $0.index }, [1, 2])
        // Fields attempting to rewrite the vision result have no merge path.
        let estimates = """
        {"items":[
        {"index":1,"kcal":220,"protein":8,"carbs":29,"fat":8,"name_en":"Beef shawarma","grams":9999,"count":100},
        {"index":2,"kcal":195,"protein":3,"carbs":12,"fat":15,"name_en":"Garlic sauce","grams":9999}]}
        """
        let overrides = try VisionMeal.nutritionOverrides(estimates, requests: requests)
        let result = try VisionMeal.decode(audited, description: "", foods: foods, nutritionOverrides: overrides)
        XCTAssertEqual(result.parts.count, 4)
        XCTAssertEqual(result.parts.reduce(0) { $0 + $1.grams }, 590)
        let wrap = try XCTUnwrap(result.parts.first { $0.food.id == "ai:pita wrap" })
        XCTAssertEqual(wrap.food.nameEn, "pita wrap"); XCTAssertEqual(wrap.grams, 120); XCTAssertEqual(wrap.count, 1)
        XCTAssertEqual(wrap.low, 60); XCTAssertEqual(wrap.high, 216); XCTAssertTrue(wrap.tentative)
        let dip = try XCTUnwrap(result.parts.first { $0.food.id == "ai:dip bowl" })
        XCTAssertEqual(dip.food.nameEn, "dip bowl"); XCTAssertEqual(dip.grams, 20); XCTAssertEqual(dip.count, 1)
        XCTAssertEqual(dip.food.nutrition.kcal, 195); XCTAssertTrue(dip.tentative)
        let chicken = try XCTUnwrap(result.parts.first { $0.food.id == "171534" })
        XCTAssertEqual(chicken.food.nutrition, try XCTUnwrap(foods.first { $0.id == "171534" }).nutrition)
        XCTAssertEqual(result.parts.first { $0.food.id == "172816" }?.grams, 200)
        XCTAssertFalse(result.parts.contains { ["chicken-shawarma", "beef-shawarma", "garlic-sauce"].contains($0.food.id) })
        XCTAssertTrue(result.unmatched)
        XCTAssertThrowsError(try VisionMeal.decode(audited, description: "", foods: foods, nutritionOverrides: [1: overrides[1]!]))
        XCTAssertThrowsError(try VisionMeal.decode(audited, description: "", foods: foods, nutritionOverrides: [0: overrides[1]!, 1: overrides[1]!, 2: overrides[2]!]))
    }
    func testTextNutritionRepairRejectsMissingDuplicateExtraAndImplausibleRecords() throws {
        let requests = [VisionMeal.NutritionRequest(index: 1, name_en: "pita wrap"), VisionMeal.NutritionRequest(index: 2, name_en: "dip")]
        let first = "{\"index\":1,\"kcal\":220,\"protein\":8,\"carbs\":29,\"fat\":8}"
        let second = "{\"index\":2,\"kcal\":195,\"protein\":3,\"carbs\":12,\"fat\":15}"
        for items in [first, first + "," + first, first + "," + second + "," + second,
                      first + "," + second.replacingOccurrences(of: "\"index\":2", with: "\"index\":99"),
                      first + "," + second.replacingOccurrences(of: "\"fat\":15", with: "\"fat\":95"),
                      first + "," + second.replacingOccurrences(of: "\"protein\":3", with: "\"protein\":null")] {
            XCTAssertThrowsError(try VisionMeal.nutritionOverrides("{\"items\":[\(items)]}", requests: requests))
        }
        XCTAssertThrowsError(try VisionMeal.nutritionOverrides(String(repeating: " ", count: 8_001), requests: requests))
    }
    func testBuild23AuditedFoodsKeepTheirNamesAndWeightsThroughTextNutritionRepair() throws {
        let foods = try resource("photo-foods", [PhotoFood].self)
        let audited = """
        {"food_present":true,"uncertain":false,"items":[
        {"name_en":"grilled chicken wrap","grams":125,"min_grams":120,"max_grams":130,"count":1},
        {"name_en":"chicken strips","grams":230,"min_grams":220,"max_grams":240,"count":6},
        {"name_en":"pickled vegetables","grams":70,"min_grams":65,"max_grams":75,"count":8},
        {"name_en":"dip in small bowl","grams":20,"min_grams":18,"max_grams":22,"count":1},
        {"name_en":"flatbread wraps","grams":100,"min_grams":95,"max_grams":105,"count":5}]}
        """
        let requests = try VisionMeal.nutritionRequests(audited, description: "", foods: foods)
        XCTAssertEqual(requests.map { $0.index }, [2, 3, 4])
        let response = """
        {"items":[
        {"index":2,"kcal":28,"protein":1,"carbs":6,"fat":0},
        {"index":3,"kcal":195,"protein":3,"carbs":12,"fat":15},
        {"index":4,"kcal":250,"protein":12,"carbs":28,"fat":10}]}
        """
        let overrides = try VisionMeal.nutritionOverrides(response, requests: requests)
        let result = try VisionMeal.decode(audited, description: "", foods: foods, nutritionOverrides: overrides)
        XCTAssertEqual(result.parts.count, 5)
        XCTAssertEqual(result.parts.reduce(0) { $0 + $1.grams }, 545)
        for (name, grams, count) in [("pickled vegetables", 70.0, 8.0), ("dip in small bowl", 20.0, 1.0), ("flatbread wraps", 100.0, 5.0)] {
            let part = try XCTUnwrap(result.parts.first { $0.food.id == "ai:" + name })
            XCTAssertEqual(part.food.nameEn, name); XCTAssertEqual(part.grams, grams); XCTAssertEqual(part.count, count)
            XCTAssertTrue(part.tentative)
        }
        // Nutrition repair does not relabel the wrongly named bread stack as
        // plain pita to satisfy a vision-category assertion.
        XCTAssertFalse(result.parts.contains { $0.food.id == "172816" })
    }
    func testNamedDishesRangesAndContradictoryIDs() throws {
        let foods = try resource("photo-foods", [PhotoFood].self)
        let numeric = """
        {"food_present":true,"items":[{"id":171534,"grams":150,"min_grams":100,"max_grams":230,"confidence":0.7}]}
        """
        XCTAssertEqual(try VisionMeal.decode(numeric, description: "", foods: foods).parts.first?.food.id, "171534")
        let named = """
        {"food_present":true,"items":[{"name_en":"Chicken wrap","grams":320,"min_grams":220,"max_grams":440,"count":2},{"name_en":"Tahini dip","min_grams":25,"max_grams":35,"count":1}]}
        """
        let result = try VisionMeal.decode(named, description: "", foods: foods)
        XCTAssertEqual(result.parts[0].food.id, "chicken-shawarma")
        XCTAssertEqual(result.parts[0].count, 2)
        XCTAssertEqual(result.parts[1].food.id, "tahini-sauce")
        XCTAssertEqual(result.parts[1].grams, 30)
        XCTAssertTrue(result.parts[1].tentative)
        let contradiction = numeric.replacingOccurrences(of: "\"id\":171534", with: "\"id\":171534,\"name_en\":\"Orange\"")
        XCTAssertThrowsError(try VisionMeal.decode(contradiction, description: "", foods: foods))
        XCTAssertNil(VisionMeal.matchName("orange plate", foods: foods))
        XCTAssertNil(VisionMeal.matchName("pita wrap with unknown filling", foods: foods))
        XCTAssertEqual(VisionMeal.matchName("Pita bread stack", foods: foods)?.id, "172816")
        XCTAssertEqual(VisionMeal.matchName("Stack of plain pita breads", foods: foods)?.id, "172816")
        XCTAssertEqual(VisionMeal.matchName("Stack of plain flatbreads", foods: foods)?.id, "172816")
        XCTAssertNil(VisionMeal.matchName("Flatbread with chicken and sauce", foods: foods))
        XCTAssertEqual(VisionMeal.matchName("Grilled chicken strips", foods: foods)?.id, "171534")
        XCTAssertTrue(VisionMeal.isDip("Creamy yogurt dip"))
        XCTAssertFalse(VisionMeal.isDip("Chicken strips with vegetable medley and yogurt dip"))
        XCTAssertFalse(VisionMeal.isDip("Pita with chicken and garlic sauce"))
        let generic = """
        {"food_present":true,"items":[
        {"name_en":"Wrapped flatbread with meat","grams":150,"min_grams":100,"max_grams":220,"count":1},
        {"name_en":"Pita bread topped with meat","grams":120,"min_grams":80,"max_grams":180,"count":1},
        {"name_en":"Creamy dip","grams":70,"min_grams":40,"max_grams":100,"count":2}]}
        """
        let context = try VisionMeal.decode(generic, description: "شاورما عربي ١٠ قطع وعلبة ثوم وعلبة طحينة", foods: foods)
        XCTAssertEqual(context.parts.count, 3)
        XCTAssertEqual(try XCTUnwrap(context.parts.first { $0.food.id == "chicken-shawarma" }).grams, 270)
        XCTAssertEqual(try XCTUnwrap(context.parts.first { $0.food.id == "chicken-shawarma" }).count, 10)
        XCTAssertEqual(try XCTUnwrap(context.parts.first { $0.food.id == "garlic-sauce" }).grams, 35)
        XCTAssertEqual(try XCTUnwrap(context.parts.first { $0.food.id == "tahini-sauce" }).grams, 35)
        XCTAssertEqual(context.parts.reduce(0) { $0 + $1.grams }, 340)
    }
    func resource<T: Decodable>(_ name:String,_ type:T.Type) throws -> T {
        let url=try XCTUnwrap(Bundle.module.url(forResource:name,withExtension:"json"));return try JSONDecoder().decode(type,from:Data(contentsOf:url))
    }
    func testOfficialNIDDKScenarios() throws {
        struct Golden: Decodable {var cases:[Scenario];struct Scenario:Decodable{var input:WeightPlan;var expected:Expected};struct Expected:Decodable{var calories:Double;var maintenance:Double;var maintenanceAtGoal:Double;var weight:Double}}
        let golden=try resource("niddk-weight-golden",Golden.self);XCTAssertEqual(golden.cases.count,6)
        for scenario in golden.cases {let result=try WeightModel.calculate(scenario.input);XCTAssertEqual(result.calories,scenario.expected.calories,accuracy:0.1);XCTAssertEqual(result.maintenance,scenario.expected.maintenance,accuracy:0.01);XCTAssertEqual(result.maintenanceAtGoal,scenario.expected.maintenanceAtGoal,accuracy:0.1);XCTAssertEqual(try XCTUnwrap(result.points.last).kg,scenario.expected.weight,accuracy:0.001)}
    }
    func testSixtyGramMacrosAndEditingInPlace() throws {
        let food=Food(name:"بيض",nutrition:Nutrition(kcal:147,protein:12.6,carbs:0.8,fat:9.9))
        var entry=try DiaryEntry(food:food,amount:60,unit:.g,meal:.breakfast,day:"2026-10-09",language:.ar);let id=entry.id
        XCTAssertEqual(entry.kcal,88.2,accuracy:1e-9);XCTAssertEqual(entry.protein,7.56,accuracy:1e-9);XCTAssertEqual(entry.carbs,0.48,accuracy:1e-9);XCTAssertEqual(entry.fat,5.94,accuracy:1e-9)
        try entry.resize(150);XCTAssertEqual(entry.id,id);XCTAssertEqual(entry.kcal,220.5,accuracy:1e-9);XCTAssertEqual(entry.protein,18.9,accuracy:1e-9)
        XCTAssertThrowsError(try entry.resize(0));XCTAssertEqual(entry.amount,150)
    }
    func testServingAndUnits() throws {
        let food=Food(name:"Milk",unit:.ml,nutrition:Nutrition(kcal:60,protein:3.2,carbs:4.7,fat:3.3),servingQuantity:250,servingUnit:"ml",servingNutrition:Nutrition(kcal:150,protein:8,carbs:11.75,fat:8.25))
        XCTAssertEqual(try food.total(2,unit:.serving).kcal,300)
        XCTAssertEqual(try food.total(50,unit:.ml).protein,1.6,accuracy:1e-9)
        XCTAssertThrowsError(try food.total(50,unit:.g))
        XCTAssertThrowsError(try Food(name:"Missing data").total(100,unit:.g))
        XCTAssertEqual(try Food(name:"Legacy serving",unit:.serving,nutrition:Nutrition(kcal:200,protein:10,carbs:20,fat:8)).total(2,unit:.serving).kcal,400)
    }
    func testMacroCaloriesConservedInGramsAndPercent() {
        let protein=Nutrition.initial.editing(.protein,value:200)
        XCTAssertEqual(protein.kcal,2000);XCTAssertEqual(protein.protein,200);XCTAssertLessThan(protein.carbs,Nutrition.initial.carbs);XCTAssertLessThan(protein.fat,Nutrition.initial.fat)
        for key in MacroKey.allCases {for value in [0.0,10,100,200,1000] {let n=protein.editing(key,value:value);XCTAssertEqual(n.macroCalories,n.kcal,accuracy:1e-8);XCTAssertTrue(n.valid)}}
        let percent=protein.editingPercent(.carbs,value:40);XCTAssertEqual(percent.carbs*4/percent.kcal*100,40,accuracy:1e-8);XCTAssertEqual(percent.macroCalories,2000,accuracy:1e-8)
        XCTAssertEqual(percent.settingCalories(1800).macroCalories,1800,accuracy:1e-8)
    }
    func testMealPrepByCookedWeight() throws {
        let ingredient=Ingredient(id:UUID(),name:"Rice",amount:100,unit:.g,kcal:400,protein:10,carbs:80,fat:4)
        let recipe=Recipe(id:UUID(),name:"Rice prep",type:"prep",ingredients:[ingredient],portions:4,cookedWeight:300,notes:"")
        XCTAssertEqual(try recipe.food().total(2,unit:.serving).kcal,200,accuracy:1e-9)
        XCTAssertEqual(try recipe.food(byWeight:true).total(150,unit:.g).kcal,200,accuracy:1e-9)
    }
    func testCatalogDecodesAndArabicSearchNormalizes() throws {
        let foods=try resource("foods-data",[Food].self);XCTAssertGreaterThan(foods.count,50);XCTAssertTrue(foods.allSatisfy{$0.per100 != nil})
        XCTAssertEqual(TextSearch.normalized("أرز ٦٠"),"ارز 60");XCTAssertEqual(TextSearch.number("٦٠٫٥"),60.5)
        XCTAssertEqual(foods.first(where:{$0.catalogID=="usda:171287"})?.servingNutrition?.kcal,71.5)
    }
    func testNativeBackupRoundTripMergeAndInvalidData() throws {
        let food=Food(name:"Egg",nutrition:Nutrition(kcal:147,protein:12.6,carbs:0.8,fat:9.9));var snapshot=DiarySnapshot();snapshot.entries=[try DiaryEntry(food:food,amount:60,unit:.g,meal:.breakfast,day:"2026-10-09",language:.en)];snapshot.weights=[WeightReading(day:"2026-10-09",kg:90,source:"Manual")]
        let decoded=try Backup.decode(Backup.encode(snapshot));XCTAssertEqual(decoded.entries,snapshot.entries);XCTAssertEqual(decoded.weights,snapshot.weights)
        var incoming=decoded;try incoming.entries[0].resize(100);let merged=try Backup.merge(incoming,into:snapshot);XCTAssertEqual(merged.entries.count,1);XCTAssertEqual(merged.entries[0].amount,100)
        var invalid=incoming;invalid.entries[0].amount = -1;XCTAssertThrowsError(try Backup.merge(invalid,into:snapshot));XCTAssertEqual(snapshot.entries[0].amount,60)
        invalid=incoming;invalid.entries += incoming.entries;XCTAssertThrowsError(try DiaryValidation.check(invalid))
    }
    func testWebsiteBackupMigration() throws {
        let ingredient=Ingredient(id:UUID(),name:"Rice",amount:100,unit:.g,kcal:400,protein:10,carbs:80,fat:4)
        let recipe=Recipe(id:UUID(),name:"Prep",type:"prep",ingredients:[ingredient],portions:4,cookedWeight:300,notes:"")
        var data=try JSONSerialization.jsonObject(with:JSONEncoder().encode(recipe)) as! [String:Any];data.removeValue(forKey:"id")
        let legacy:[String:Any]=["app":"luqma","version":1,"created":"2026-10-09T00:00:00Z","entries":[],"goals":["kcal":2000,"protein":200,"carbs":250,"fat":80],"resources":[["id":recipe.id.uuidString,"kind":"recipe","data":data],["id":"weight:2026-10-09","kind":"weight","data":["day":"2026-10-09","kg":90]]],"products":[],"history":["search":[],"barcode":[]]]
        let result=try Backup.decode(JSONSerialization.data(withJSONObject:legacy));XCTAssertEqual(result.recipes.first,recipe);XCTAssertEqual(result.weights.first?.kg,90);XCTAssertEqual(result.goals.macroCalories,2000,accuracy:1e-8)
    }
    func testWeightAverageAndPlanGuards() throws {
        let readings=[WeightReading(day:"2026-10-09",kg:90),WeightReading(day:"2026-10-08",kg:89),WeightReading(day:"2026-10-03",kg:88),WeightReading(day:"2026-10-02",kg:10)]
        let avg=DiaryValidation.average(readings,ending:"2026-10-09");XCTAssertEqual(avg.count,3);XCTAssertEqual(avg.kg,89)
        var p=WeightPlan();p.age=17;p.height=180;p.weight=90;p.targetWeight=80;XCTAssertThrowsError(try WeightModel.calculate(p));p.age=30;p.targetWeight=45;XCTAssertThrowsError(try WeightModel.calculate(p));p.targetWeight=80;p.specialCase=true;XCTAssertThrowsError(try WeightModel.calculate(p))
    }
    func testShawarmaDescriptionDoesNotCollapseToFries() throws {
        let foods=try resource("photo-foods",[PhotoFood].self)
        let region=PhotoRegion(box:PhotoBox(x:0,y:0,width:1,height:1),isFood:true,tentative:false,candidates:[PhotoMatch(id:"169836",score:0.34)])
        let result=try PhotoMeal.estimate([region],description:"شاورما عربي ١٠ قطع وعلبة ثوم وعلبة طحينة",foods:foods)
        let wrap=try XCTUnwrap(result.parts.first(where:{$0.food.id=="chicken-shawarma"}));XCTAssertEqual(wrap.grams,330);XCTAssertEqual(result.parts.first(where:{$0.food.id=="garlic-sauce"})?.grams,35);XCTAssertEqual(result.parts.first(where:{$0.food.id=="tahini-sauce"})?.grams,35)
        XCTAssertEqual(Set(result.parts.map{$0.food.id}).count,result.parts.count)
    }
    func testNegationAndSauceNeedsConfirmation() throws {
        let foods=try resource("photo-foods",[PhotoFood].self),box=PhotoBox(x:0,y:0,width:0.45,height:0.45)
        let r=PhotoRegion(box:box,isFood:true,tentative:false,candidates:[PhotoMatch(id:"garlic-sauce",score:0.35),PhotoMatch(id:"tahini-sauce",score:0.33)])
        let result=try PhotoMeal.estimate([r],description:"",foods:foods);XCTAssertTrue(result.parts.isEmpty);XCTAssertTrue(result.sauceSuggested)
        let wrap=PhotoRegion(box:box,isFood:true,tentative:false,candidates:[PhotoMatch(id:"chicken-shawarma",score:0.34)])
        let negated=try PhotoMeal.estimate([wrap],description:"شاورما عربي بدون ثوم",foods:foods);XCTAssertFalse(negated.parts.contains{$0.food.id=="garlic-sauce"})
        let egg=try XCTUnwrap(foods.first(where:{$0.id=="173424"}));XCTAssertThrowsError(try PhotoMeal.quantity("-2 قطع",food:egg))
        var part=PhotoPart(food:egg,grams:100,low:50,high:180,basis:"reference");part.setGrams(0);XCTAssertEqual(part.grams,0);XCTAssertEqual(part.nutrition.kcal,0);part.setGrams(3500);XCTAssertEqual(part.grams,3500) // Preserve input so the UI can reject it, rather than saving a stale portion.
    }
}
