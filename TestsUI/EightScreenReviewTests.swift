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
    private func openWeight(){
        let button=app.buttons["progress.logWeight"]
        XCTAssertTrue(button.waitForExistence(timeout:10));if !button.isHittable{app.swipeDown()};button.tap()
    }
    private func replace(_ field:XCUIElement,_ text:String){
        field.tap();let current=field.value as? String ?? ""
        field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:current == "—" ? 0:current.count)+text)
    }
}
