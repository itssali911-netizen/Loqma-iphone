import XCTest
@testable import LuqmaCore

final class FoodAdditionTests:XCTestCase {
    func testServingDefaultKeepsMissingSourcePortionUnknown() {
        let food=Food(catalogID:"off:123",name:"Product",nutrition:Nutrition(kcal:120,protein:3,carbs:20,fat:3),source:"OpenFoodFacts")
        XCTAssertEqual(food.defaultAdditionUnit,.serving)
        XCTAssertEqual(food.additionUnits,[.serving,.g])
        XCTAssertNil(food.values(for:.serving))
        XCTAssertNil(food.servingQuantity)
        XCTAssertThrowsError(try food.total(1,unit:.serving))
    }
    func testUserServingSizeUsesTheDeclaredBasisWithoutDensityConversion() throws {
        let nutrition=Nutrition(kcal:60,protein:3,carbs:5,fat:3)
        let milk=Food(name:"Milk",unit:.ml,nutrition:nutrition,source:"OpenFoodFacts")
        let serving=try milk.definingServing(quantity:250,unit:.ml,label:"250 ml")
        XCTAssertEqual(try serving.total(0.5,unit:.serving).kcal,75,accuracy:1e-9)
        XCTAssertEqual(serving.per100,nutrition)
        XCTAssertEqual(serving.servingUnit,"ml")
        XCTAssertThrowsError(try milk.definingServing(quantity:250,unit:.g,label:"250 g"))
        for invalid in [0.0,-1,10001,.infinity,.nan] {
            XCTAssertThrowsError(try milk.definingServing(quantity:invalid,unit:.ml,label:"Serving"))
        }
        XCTAssertThrowsError(try milk.definingServing(quantity:250,unit:.ml,label:" "))
        XCTAssertThrowsError(try Food(name:"Missing").definingServing(quantity:50,unit:.g,label:"50 g"))
    }
    func testRecognitionOnlyLabelsNeverBecomeNutritionalFoodRecords() throws {
        let data=Data(#"{"id":"172816","name":"خبز","nameEn":"Bread","grams":40}"#.utf8)
        let label=try JSONDecoder().decode(PhotoFood.self,from:data)
        XCTAssertEqual(label.nameEn,"Bread")
        XCTAssertNil(label.food.per100)
        XCTAssertNil(label.food.servingNutrition)
        XCTAssertEqual(label.food.source,"Image label")
        XCTAssertFalse(FoodSearch.availableForAdding(label.food))
        let encoded=try XCTUnwrap(JSONSerialization.jsonObject(with:JSONEncoder().encode(label)) as? [String:Any])
        for key in ["kcal","protein","carbs","fat"] {XCTAssertNil(encoded[key])}
    }
}
