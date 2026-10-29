import XCTest

/// Real controls and persistence in a disposable Simulator. Test readings are
/// entered through the UI; production data and preview screenshots are separate.
final class EightScreenReviewTests:XCTestCase {
    private let app=XCUIApplication()
    override func setUpWithError() throws {
        continueAfterFailure=false
        #if !targetEnvironment(simulator)
        throw XCTSkip("Run only on a disposable Simulator")
        #endif
        app.launchArguments=["-loqma-ui-test-en","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["nav.progress"].waitForExistence(timeout:20))
    }
    override func tearDownWithError() throws {
        if let testRun,testRun.failureCount>0{print(app.debugDescription)}
        let capture=XCTAttachment(screenshot:app.screenshot());capture.name="Actual eight-screen review test";capture.lifetime = .keepAlways;add(capture)
        app.terminate()
    }
    func testWeightValidationSameDayReplacementAndRelaunch() {
        app.buttons["nav.progress"].tap()
        openWeight()
        let field=app.textFields["weight.value"],save=app.buttons["weight.save"]
        XCTAssertTrue(field.waitForExistence(timeout:10))
        for invalid in ["0","301","34"]{replace(field,invalid);XCTAssertFalse(save.isEnabled)}
        replace(field,"82.4");XCTAssertTrue(save.isEnabled);save.tap()
        XCTAssertTrue(app.buttons["progress.logWeight"].waitForExistence(timeout:10))
        openWeight();replace(app.textFields["weight.value"],"82.6");app.buttons["weight.save"].tap()
        XCTAssertTrue(app.buttons["progress.logWeight"].waitForExistence(timeout:10))
        app.terminate();app.launch();app.buttons["nav.progress"].tap();openWeight()
        let restored=app.textFields["weight.value"]
        XCTAssertTrue(restored.waitForExistence(timeout:10))
        let restoredNumber=Double(restored.value as? String ?? "")
        XCTAssertNotNil(restoredNumber)
        XCTAssertEqual(restoredNumber ?? 0,82.6,accuracy:0.0001,"Compare the persisted number; the approved formatter may display 82.60")
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.staticTexts["82.4 kg"].exists,"The earlier same-day reading must be replaced")
    }
    func testArabicRecipeDraftReturnsFromIngredientSearch() {
        app.buttons["nav.settings"].tap();app.buttons["settings.language"].tap()
        app.buttons["language.option.ar"].tap();XCTAssertTrue(app.buttons["language.option.ar"].isSelected)
        app.buttons["language.back"].tap();app.buttons["nav.kitchen"].tap()
        app.buttons["kitchen.create"].tap()
        let field=app.textFields["recipe.name"]
        // Multiline SwiftUI fields may be exposed as text views by UIKit.
        let name=field.waitForExistence(timeout:3) ? field:app.textViews["recipe.name"]
        XCTAssertTrue(name.waitForExistence(timeout:10));name.tap();name.typeText("Review recipe")
        let ingredient=app.buttons["recipe.addIngredient"]
        if !ingredient.isHittable{app.swipeUp()};ingredient.tap()
        XCTAssertTrue(app.buttons["search.close"].waitForExistence(timeout:15));app.buttons["search.close"].tap()
        XCTAssertTrue(name.waitForExistence(timeout:10));XCTAssertEqual(name.value as? String,"Review recipe")
    }
    func testRecipeDetailsIngredientDisclosureAndBothQuantityModes() {
        app.buttons["nav.kitchen"].tap();app.buttons["kitchen.create"].tap()
        let field=app.textFields["recipe.name"]
        let name=field.waitForExistence(timeout:3) ? field:app.textViews["recipe.name"]
        XCTAssertTrue(name.waitForExistence(timeout:10));name.tap();name.typeText("Recipe review")
        reveal(app.buttons["recipe.addIngredient"]);app.buttons["recipe.addIngredient"].tap()
        let personal=app.buttons["search.filter.3"]
        XCTAssertTrue(personal.waitForExistence(timeout:15));personal.tap()
        reveal(app.buttons["search.manual"]);app.buttons["search.manual"].tap()
        let foodName=app.textFields["portion.name"]
        XCTAssertTrue(foodName.waitForExistence(timeout:10));foodName.tap();foodName.typeText("Review ingredient")
        for (key,value) in [("kcal","200"),("protein","10"),("carbs","30"),("fat","4")]{
            reveal(app.textFields["portion."+key]);replace(app.textFields["portion."+key],value)
        }
        reveal(app.buttons["portion.save"]);app.buttons["portion.save"].tap()
        XCTAssertTrue(app.buttons["recipe.addIngredient"].waitForExistence(timeout:15))
        let toggle=app.switches["recipe.byWeight"]
        reveal(toggle);toggle.switches.firstMatch.tap()
        let cooked=app.textFields["Cooked weight"]
        reveal(cooked);replace(cooked,"100")
        app.buttons["navigation.primaryAction"].tap()
        XCTAssertTrue(app.buttons["kitchen.create"].waitForExistence(timeout:15))
        let recipe=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Recipe review")).firstMatch
        reveal(recipe);recipe.tap()
        let details=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","recipeDetail.nutrition.")).firstMatch
        reveal(details);XCTAssertEqual(details.value as? String,"Collapsed");details.tap()
        XCTAssertEqual(details.value as? String,"Expanded")
        XCTAssertTrue(app.staticTexts["For the quantity shown above"].exists)
        let check=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","recipeDetail.check.")).firstMatch
        reveal(check);check.tap();XCTAssertTrue(check.isSelected)
        let screenshot=XCTAttachment(screenshot:app.screenshot());screenshot.name="Recipe ingredient expanded actual controls";screenshot.lifetime = .keepAlways;add(screenshot)
        app.buttons["recipeDetail.logServing"].tap()
        XCTAssertTrue(app.buttons["portion.quantity"].waitForExistence(timeout:10));app.buttons["portion.quantity"].tap()
        XCTAssertTrue(app.buttons["portion.unit.serving"].isSelected)
        app.buttons["portion.quantity.confirm"].tap();app.buttons["portion.back"].tap()
        XCTAssertTrue(app.buttons["recipeDetail.logGrams"].waitForExistence(timeout:10));app.buttons["recipeDetail.logGrams"].tap()
        XCTAssertTrue(app.buttons["portion.quantity"].waitForExistence(timeout:10));app.buttons["portion.quantity"].tap()
        XCTAssertTrue(app.buttons["portion.unit.g"].isSelected)
    }
    private func reveal(_ element:XCUIElement){
        for _ in 0..<5{if element.exists && element.isHittable{return};app.swipeUp()}
        XCTAssertTrue(element.exists && element.isHittable,app.debugDescription)
    }
    private func openWeight(){
        let button=app.buttons["progress.logWeight"]
        XCTAssertTrue(button.waitForExistence(timeout:10));if !button.isHittable{app.swipeDown()};button.tap()
    }
    private func replace(_ field:XCUIElement,_ text:String){
        XCTAssertTrue(field.waitForExistence(timeout:10))
        field.tap();let current=field.value as? String ?? ""
        if !current.isEmpty,current != "—"{
            // Reuse the existing native-test caret policy. Tapping a centered
            // numeric field can leave the caret inside the previous number.
            field.coordinate(withNormalizedOffset:CGVector(dx:0.98,dy:0.5)).tap()
            field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:current.count))
        }
        field.typeText(text)
        XCTAssertEqual(field.value as? String,text,"Verify the real field contains the intended input before asserting validation")
    }
}
