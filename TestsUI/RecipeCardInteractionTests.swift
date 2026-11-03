import XCTest

/// The package's synthetic recipe lives in a temporary DiaryStore. Destinations,
/// nutrition calculation and committing a serving use the real application code.
/// These are Simulator UI tests, not claims of physical-device validation.
final class RecipeCardInteractionTests:XCTestCase {
    private let app=XCUIApplication()
    private let id="9A7949BB-87ED-47FD-9FB3-B833B6927986"
    override func setUpWithError() throws {
        continueAfterFailure=false
        #if !targetEnvironment(simulator)
        throw XCTSkip("Run only on a disposable Simulator")
        #endif
    }
    override func tearDownWithError() throws {
        if let run=testRun,run.failureCount>0{print("LUQMA_RECIPE_CARD_FAILED_HIERARCHY "+app.debugDescription)}
        capture(name:"Actual native recipe card UI")
        app.terminate()
    }
    func testArabicReference390GeometryAndMacroValues() {
        launch()
        let card=element("recipeCard."+id)
        XCTAssertEqual(card.frame.width,390,accuracy:1)
        XCTAssertEqual(card.frame.height,272,accuracy:1)
        let add=app.buttons["recipeCard.add."+id]
        let details=app.buttons["recipeCard.details."+id]
        let more=app.buttons["recipeCard.more."+id]
        XCTAssertEqual(add.frame.height,48,accuracy:1)
        XCTAssertEqual(add.frame.width,350,accuracy:1)
        XCTAssertEqual(add.frame.minY-card.frame.minY,202,accuracy:1)
        XCTAssertEqual(details.frame.width,44,accuracy:1)
        XCTAssertEqual(details.frame.height,44,accuracy:1)
        XCTAssertEqual(more.frame.width,44,accuracy:1)
        let protein=element("recipeCard.macro.protein."+id)
        let carbs=element("recipeCard.macro.carbs."+id)
        let fat=element("recipeCard.macro.fat."+id)
        XCTAssertGreaterThan(protein.frame.midX,carbs.frame.midX)
        XCTAssertGreaterThan(carbs.frame.midX,fat.frame.midX)
        XCTAssertTrue(protein.label.contains("35.9"),protein.label)
        XCTAssertTrue(carbs.label.contains("26.0"),carbs.label)
        XCTAssertTrue(fat.label.contains("36.5"),fat.label)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","588")).firstMatch.exists,"The package's calorie fixture is not recalculated from its macros")
        recordGeometry([("card",card),("add",add),("details",details),("more",more),("protein",protein),("carbs",carbs),("fat",fat)])
        capture(name:"Recipe card — Arabic reference — native 390 points")
    }
    func testNarrow320LongEnglishContentAndActions() {
        launch(extra:["-loqma-recipe-card-320","-loqma-recipe-card-en","-loqma-recipe-card-long"])
        let card=element("recipeCard."+id)
        XCTAssertEqual(card.frame.width,320,accuracy:1)
        XCTAssertGreaterThan(card.frame.height,272,"Long titles should grow without reducing the approved font size")
        assertControlFrames(card:card)
        capture(name:"Recipe card — English long title — native 320 points")
        app.buttons["recipeCard.more."+id].tap()
        let edit=app.buttons["Edit"]
        XCTAssertTrue(edit.waitForExistence(timeout:5));edit.tap()
        let field=app.textFields["recipe.name"]
        let name=field.waitForExistence(timeout:3) ? field:app.textViews["recipe.name"]
        XCTAssertTrue(name.waitForExistence(timeout:8))
        XCTAssertTrue((name.value as? String ?? "").contains("Homemade diet ranch"))
    }
    func testDetailsAndSingleServingUseRealTemporaryDiary() {
        launch(extra:["-loqma-recipe-card-en","-loqma-recipe-card-interactions"])
        app.buttons["recipeCard.details."+id].tap()
        let log=app.buttons["recipeDetail.logServing"]
        XCTAssertTrue(log.waitForExistence(timeout:10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format:"label CONTAINS %@","588")).firstMatch.exists)
        app.buttons["navigation.back"].tap()
        let add=app.buttons["recipeCard.add."+id]
        XCTAssertTrue(add.waitForExistence(timeout:10));add.tap()
        let save=app.buttons["portion.save"]
        XCTAssertTrue(save.waitForExistence(timeout:10))
        let calorieText=app.staticTexts["portion.total.kcal"]
        XCTAssertTrue(calorieText.exists)
        XCTAssertEqual(calorieText.label,"588")
        reveal(save);save.tap()
        let entries=app.staticTexts["recipeCard.review.entries"]
        XCTAssertTrue(entries.waitForExistence(timeout:10))
        XCTAssertEqual(entries.label,"Review diary entries: 1","One committed serving must create exactly one entry")
    }
    func testAccessibilityArabicKeepsControlsInsideCard() {
        launch(extra:["-loqma-preview-accessibility","-loqma-recipe-card-320","-loqma-recipe-card-long"])
        let card=element("recipeCard."+id)
        XCTAssertEqual(card.frame.width,320,accuracy:1)
        XCTAssertGreaterThan(card.frame.height,272)
        // The entire card may scroll, but its content must remain horizontally
        // bounded. Inspect native frames without asserting everything is onscreen.
        assertControlFrames(card:card)
        assertNutritionFrames(card:card)
        for key in ["protein","carbs","fat"] {
            let macro=element("recipeCard.macro."+key+"."+id)
            XCTAssertGreaterThanOrEqual(macro.frame.minX,card.frame.minX)
            XCTAssertLessThanOrEqual(macro.frame.maxX,card.frame.maxX)
        }
        capture(name:"Recipe card — Arabic accessibility — native 320 points")
    }
    func testLargeValuesStayInsideNarrowCardWithoutShrinking() {
        launch(extra:["-loqma-recipe-card-320","-loqma-recipe-card-large"])
        let card=element("recipeCard."+id)
        XCTAssertEqual(card.frame.width,320,accuracy:1)
        assertControlFrames(card:card)
        assertNutritionFrames(card:card)
        XCTAssertTrue(element("recipeCard.macro.protein."+id).label.contains("99999.9"))
        let protein=element("recipeCard.macro.protein."+id)
        let carbs=element("recipeCard.macro.carbs."+id)
        let fat=element("recipeCard.macro.fat."+id)
        XCTAssertLessThan(protein.frame.midY,carbs.frame.midY,"Whole macro groups must stack when the decimal values do not fit columns")
        XCTAssertLessThan(carbs.frame.midY,fat.frame.midY)
        capture(name:"Recipe card — large values — native 320 points")
    }
    private func assertNutritionFrames(card:XCUIElement) {
        for role in ["energy","macro.protein","macro.carbs","macro.fat"] {
            let value=element("recipeCard."+role+"."+id)
            XCTAssertGreaterThanOrEqual(value.frame.minX,card.frame.minX+19)
            XCTAssertLessThanOrEqual(value.frame.maxX,card.frame.maxX-19)
            XCTAssertLessThanOrEqual(value.frame.maxY,card.frame.maxY)
        }
    }
    private func launch(extra:[String]=[]) {
        app.launchArguments=["-loqma-preview-template","recipeCard","-AppleLanguages","(ar)","-AppleLocale","ar_SA"]+extra
        app.launch()
        XCTAssertTrue(app.buttons["recipeCard.add."+id].waitForExistence(timeout:20))
    }
    private func element(_ identifier:String)->XCUIElement {
        let value=app.descendants(matching:.any).matching(identifier:identifier).firstMatch
        XCTAssertTrue(value.waitForExistence(timeout:10),identifier)
        return value
    }
    private func assertControlFrames(card:XCUIElement) {
        for role in ["add","details","more"] {
            let control=app.buttons["recipeCard."+role+"."+id]
            XCTAssertTrue(control.exists && control.isEnabled)
            // AX frames use floating-point transforms (e.g. 43.999999999999986).
            // A hundredth of a point is far below one Retina pixel.
            XCTAssertGreaterThanOrEqual(control.frame.width,44-0.01)
            XCTAssertGreaterThanOrEqual(control.frame.height,44-0.01)
            XCTAssertGreaterThanOrEqual(control.frame.minX,card.frame.minX)
            XCTAssertLessThanOrEqual(control.frame.maxX,card.frame.maxX)
            XCTAssertLessThanOrEqual(control.frame.maxY,card.frame.maxY)
        }
    }
    private func reveal(_ element:XCUIElement) {
        for _ in 0..<8 {if element.isHittable{return};app.swipeUp()}
        XCTAssertTrue(element.isHittable)
    }
    private func capture(name:String) {
        let attachment=XCTAttachment(screenshot:app.screenshot())
        attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }
    private func recordGeometry(_ elements:[(String,XCUIElement)]) {
        let frames=elements.map{name,element in ["name":name,"x":element.frame.minX,"y":element.frame.minY,"width":element.frame.width,"height":element.frame.height] as [String:Any]}
        if let data=try? JSONSerialization.data(withJSONObject:frames,options:[.sortedKeys]),let json=String(data:data,encoding:.utf8) {
            print("LUQMA_RECIPE_CARD_ACTUAL_GEOMETRY "+json)
            let attachment=XCTAttachment(data:data,uniformTypeIdentifier:"public.json")
            attachment.name="Actual native recipe card geometry";attachment.lifetime = .keepAlways;add(attachment)
        }
    }
}
