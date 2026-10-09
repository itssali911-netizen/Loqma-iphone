import XCTest
@testable import LuqmaCore

final class CoreTests: XCTestCase {
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
        let rejected = try VisionMeal.decode(invalid, description: "", foods: foods)
        XCTAssertTrue(rejected.parts.isEmpty); XCTAssertTrue(rejected.unmatched)
        let inconsistent = json.replacingOccurrences(of: "\"kcal\":240", with: "\"kcal\":180")
        let repaired = try VisionMeal.decode(inconsistent, description: "", foods: foods)
        XCTAssertEqual(try XCTUnwrap(repaired.parts.first).food.nutrition.kcal, 240)
        XCTAssertTrue(try XCTUnwrap(repaired.parts.first).tentative)
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
