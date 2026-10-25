import XCTest
@testable import LuqmaCore

final class NutritionHomeDataTests:XCTestCase {
    private let day="2026-10-25"
    private var food:Food {Food(catalogID:"personal:home-test",name:"أرز ودجاج",nameEn:"Chicken rice",unit:.serving,nutrition:Nutrition(kcal:100,protein:10,carbs:15,fat:0),servingNutrition:Nutrition(kcal:100,protein:10,carbs:15,fat:0),source:"Your food")}
    private func entry(_ amount:Double=1,day:String="2026-10-25",meal:Meal = .breakfast)throws->DiaryEntry {try DiaryEntry(food:food,amount:amount,unit:.serving,meal:meal,day:day,language:.ar)}
    func testEmptyDiaryExamplesNeverBecomeNutritionOrFood(){
        let snapshot=NutritionHomeSnapshot(state:DiarySnapshot(),day:day)
        XCTAssertEqual(snapshot.consumed,.zero)
        XCTAssertEqual(snapshot.morning.count,2);XCTAssertEqual(snapshot.featured.count,2);XCTAssertEqual(snapshot.browse.count,3)
        for card in snapshot.morning+snapshot.featured+snapshot.browse{XCTAssertTrue(card.isExample);XCTAssertNil(card.food);XCTAssertNil(card.nutrition)}
    }
    func testActualDailyTotalHasNoReferenceBaseCalories()throws{
        var state=DiarySnapshot();state.entries=[try entry(),try entry(9,day:"2026-10-24")]
        let snapshot=NutritionHomeSnapshot(state:state,day:day)
        XCTAssertEqual(snapshot.consumed,Nutrition(kcal:100,protein:10,carbs:15,fat:0));XCTAssertEqual(snapshot.entries.count,1)
        XCTAssertFalse(snapshot.browse.first?.isExample ?? true)
    }
    func testSavedAmountIsAlreadyScaledAndNeverMultipliedTwice()throws{
        var state=DiarySnapshot();state.entries=[try entry(2.5)]
        let snapshot=NutritionHomeSnapshot(state:state,day:day)
        XCTAssertEqual(snapshot.consumed.kcal,250);XCTAssertEqual(snapshot.consumed.protein,25)
        XCTAssertEqual(snapshot.browse.first?.nutrition?.kcal,250)
    }
    func testBreakfastRoutineUsesOnlyBreakfastOnSelectedDay()throws{
        var state=DiarySnapshot();state.entries=[try entry(2,meal:.lunch),try entry(3,day:"2026-10-24"),try entry()]
        let snapshot=NutritionHomeSnapshot(state:state,day:day)
        XCTAssertEqual(snapshot.morning.count,1);XCTAssertEqual(snapshot.morning[0].nutrition?.kcal,100)
    }
    func testRecipeAndItsLoggedPortionDoNotDoubleCount()throws{
        let recipe=Recipe(id:UUID(),name:"دجاج مشوي",type:"recipe",ingredients:[Ingredient(id:UUID(),name:"دجاج",amount:200,unit:.g,kcal:400,protein:40,carbs:60,fat:0)],portions:2,cookedWeight:200,notes:"")
        let logged=try DiaryEntry(food:recipe.food(),amount:1,unit:.serving,meal:.lunch,day:day,language:.ar)
        var state=DiarySnapshot();state.recipes=[recipe];state.entries=[logged]
        let snapshot=NutritionHomeSnapshot(state:state,day:day)
        XCTAssertEqual(snapshot.consumed.kcal,200);XCTAssertEqual(snapshot.browse.count,1)
        XCTAssertEqual(snapshot.featured.first?.nutrition?.kcal,200)
        XCTAssertEqual(snapshot.featured.first?.matchingEntry(in:state.entries,day:day)?.id,logged.id)
    }
    func testMatchingSavedFoodNeverRemovesAnotherDay()throws{
        let card=NutritionHomeCard(origin:.saved(food)),old=try entry(day:"2026-10-24"),current=try entry()
        XCTAssertNil(card.matchingEntry(in:[old],day:day))
        XCTAssertEqual(card.matchingEntry(in:[old,current],day:day)?.id,current.id)
    }
    func testDuplicateHistoryProductsProduceOneSuggestion(){
        var state=DiarySnapshot();state.products=[food,food];state.searchHistory=[food];state.customFoods=[food]
        let snapshot=NutritionHomeSnapshot(state:state,day:day)
        XCTAssertEqual(snapshot.browse.count,1);XCTAssertEqual(snapshot.consumed,.zero)
    }
    func testDeclaredServingWinsOverPerHundredValues(){
        let serving=Nutrition(kcal:100,protein:4,carbs:20,fat:1)
        let product=Food(catalogID:"personal:serving",name:"منتج",unit:.g,nutrition:serving.scaled(2.5),serving:"40 g",servingQuantity:40,servingUnit:"g",servingNutrition:serving,source:"Your food")
        let card=NutritionHomeCard(origin:.saved(product))
        XCTAssertEqual(card.nutrition,serving)
    }
    func testUnknownNutritionAndUserRatingsStayUnknown(){
        let card=NutritionHomeCard(origin:.saved(Food(name:"غير مكتمل",source:"Your food")))
        XCTAssertNil(card.nutrition);XCTAssertNil(card.kcal);XCTAssertNil(card.rating);XCTAssertNil(card.preparationMinutes)
    }
    func testArabicSearchMatchesEveryWordInEitherOrder(){
        let cards=NutritionHomeExample.browse.map{NutritionHomeCard(origin:.example($0))}
        let index=NutritionHomeSearchIndex(cards:cards)
        XCTAssertEqual(index.results(category:.all,query:"سَلْمُون جواكامولي"),["example:salmon-meat"])
        XCTAssertEqual(index.results(category:.all,query:"جواكامولي سلمون"),["example:salmon-meat"])
        XCTAssertTrue(index.results(category:.all,query:"سلمون موز").isEmpty)
    }
    func testCategoriesActuallyFilterAndAllRestoresResults(){
        let index=NutritionHomeSearchIndex(cards:NutritionHomeExample.browse.map{NutritionHomeCard(origin:.example($0))})
        XCTAssertEqual(index.results(category:.vegetables,query:"بروكلي"),["example:fried-broccoli"])
        XCTAssertEqual(index.results(category:.meat,query:"").count,2)
        XCTAssertTrue(index.results(category:.fruit,query:"").isEmpty)
        XCTAssertEqual(index.results(category:.all,query:"").count,3)
        XCTAssertFalse(NutritionHomeCategory.fruit.matches("جبنة موزاريلا Mozzarella"))
        XCTAssertFalse(NutritionHomeCategory.fruit.matches("Updated recipe"))
        XCTAssertTrue(NutritionHomeCategory.fruit.matches("حليب بالموز"))
        XCTAssertTrue(NutritionHomeCategory.fruit.matches("Apples and berries"))
        XCTAssertTrue(NutritionHomeCategory.vegetables.matches("الخضروات Vegetables"))
    }
    func testStableEntryIdentifiersAcrossProjectionRebuilds()throws{
        var state=DiarySnapshot();state.entries=[try entry()]
        XCTAssertEqual(NutritionHomeSnapshot(state:state,day:day).browse.map(\.id),NutritionHomeSnapshot(state:state,day:day).browse.map(\.id))
    }
}
