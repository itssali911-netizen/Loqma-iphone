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
    /// Only native controls on an initially empty disposable diary. The test
    /// opens the real importer but deliberately makes no remote request.
    func testKitchenCategoriesSearchAndActionsRemainUsable() {
        app.buttons["nav.kitchen"].tap()
        let create=app.buttons["kitchen.create"]
        let search=app.textFields["Search your recipes and meals"]
        XCTAssertTrue(create.waitForExistence(timeout:10));XCTAssertTrue(create.isHittable)
        XCTAssertTrue(search.waitForExistence(timeout:10));XCTAssertTrue(search.isHittable)
        let controls:[(String,XCUIElement)]=[
            ("search",search),("create",create),("import",app.buttons["Import link"]),
            ("all",app.buttons["All"]),("recipes",app.buttons["Recipes"]),
            ("meals",app.buttons["Meals"]),("prep",app.buttons["Meal prep"]),
            ("tab.kitchen",app.buttons["nav.kitchen"]),("tab.add",app.buttons["nav.add"])]
        var geometry:[[String:Any]]=[]
        for (name,control) in controls {
            XCTAssertTrue(control.exists && control.isEnabled && control.isHittable,"Unusable Kitchen control: \(name)")
            geometry.append(["control":name,"x":control.frame.minX,"y":control.frame.minY,
                             "width":control.frame.width,"height":control.frame.height])
        }
        if let bytes=try? JSONSerialization.data(withJSONObject:geometry,options:[.sortedKeys]),let json=String(data:bytes,encoding:.utf8) {
            print("LUQMA_KITCHEN_ACTUAL_CONTROL_FRAMES "+json)
            let item=XCTAttachment(data:bytes,uniformTypeIdentifier:"public.json");item.name="Actual Kitchen control geometry";item.lifetime = .keepAlways;add(item)
        }
        for label in ["Recipes","Meals","Meal prep","All"] {
            let segment=app.buttons[label];segment.tap();XCTAssertTrue(segment.isSelected)
        }
        let mealSegment=app.buttons["Meals"];mealSegment.tap();XCTAssertTrue(mealSegment.isSelected)
        search.tap();search.typeText("Kitchen query")
        XCTAssertEqual(search.value as? String,"Kitchen query")
        let clear=app.buttons["Clear search"]
        XCTAssertTrue(clear.waitForExistence(timeout:5));XCTAssertTrue(clear.isHittable);clear.tap()
        XCTAssertNotEqual(search.value as? String,"Kitchen query")
        search.tap();search.typeText("Draft filter")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout:5))
        XCTAssertTrue(create.isHittable,"The decorative background must not intercept the action while typing")
        create.tap()
        let nameField=app.textFields["recipe.name"]
        let name=nameField.waitForExistence(timeout:3) ? nameField:app.textViews["recipe.name"]
        XCTAssertTrue(name.waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["Cancel"].isHittable);app.buttons["Cancel"].tap()
        XCTAssertTrue(create.waitForExistence(timeout:10))
        XCTAssertEqual(search.value as? String,"Draft filter","Presenting and cancelling a recipe must preserve the real search state")
        XCTAssertTrue(mealSegment.isSelected)
        let importer=app.buttons["Import link"]
        XCTAssertTrue(importer.isHittable);importer.tap()
        let link=app.textFields["Recipe link"]
        XCTAssertTrue(link.waitForExistence(timeout:10));link.tap();link.typeText("https://example.invalid/recipe")
        XCTAssertEqual(link.value as? String,"https://example.invalid/recipe")
        let close=app.buttons["Close"]
        XCTAssertTrue(close.isHittable);close.tap()
        XCTAssertTrue(create.waitForExistence(timeout:10));XCTAssertTrue(create.isHittable)
        XCTAssertEqual(search.value as? String,"Draft filter")
        XCTAssertTrue(mealSegment.isSelected)
        XCTAssertTrue(clear.isHittable);clear.tap()
        app.buttons["All"].tap()
        for identifier in ["nav.today","nav.kitchen"] {
            let tab=app.buttons[identifier];XCTAssertTrue(tab.isHittable);tab.tap();XCTAssertTrue(tab.isSelected)
        }
        XCTAssertTrue(create.waitForExistence(timeout:10));XCTAssertTrue(create.isHittable)
        XCTAssertTrue(app.buttons["All"].isSelected)
        let item=XCTAttachment(screenshot:app.screenshot());item.name="Actual Kitchen after native controls and cancellations";item.lifetime = .keepAlways;add(item)
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
