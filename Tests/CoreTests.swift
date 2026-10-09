import XCTest
@testable import LuqmaCore

final class CoreTests: XCTestCase {
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
