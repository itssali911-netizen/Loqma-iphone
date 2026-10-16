import XCTest

/// Real production controls on a newly created, disposable CI Simulator.
/// No screenshot fixtures, service stubs or private connection credentials.
final class LuqmaInteractionTests:XCTestCase {
    private let app=XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure=false
        app.launchArguments=["-loqma-ui-test-en","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["nav.today"].waitForExistence(timeout:20))
    }

    override func tearDownWithError() throws {
        if let testRun, testRun.failureCount>0 {
            // Keep the actual failed screen and hierarchy, including field values.
            print("LUQMA_FAILED_HIERARCHY\n"+app.debugDescription)
            let attachment=XCTAttachment(screenshot:app.screenshot())
            attachment.name="Actual failed application screen"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testFoodAddResizePersistenceAndDelete() throws {
        app.buttons["nav.add"].tap()
        // The initial catalog load can move rows. Use the real empty personal list
        // before opening manual entry rather than tapping a moving results footer.
        let personal=app.buttons["search.filter.3"]
        XCTAssertTrue(personal.waitForExistence(timeout:10))
        personal.tap()
        XCTAssertTrue(personal.isSelected)
        let manual=app.buttons["search.manual"]
        reveal(manual)
        manual.tap()
        XCTAssertTrue(app.textFields["portion.name"].waitForExistence(timeout:10),app.debugDescription)
        replace(app.textFields["portion.name"],with:"UI Test Oats")
        XCTAssertTrue(app.segmentedControls.buttons["serving"].isSelected)
        XCTAssertEqual(app.textFields["portion.amount"].value as? String,"1")
        replace(app.textFields["portion.kcal"],with:"100")
        replace(app.textFields["portion.protein"],with:"10")
        replace(app.textFields["portion.carbs"],with:"15")
        replace(app.textFields["portion.fat"],with:"0")
        let save=app.buttons["portion.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.buttons["nav.today"].waitForExistence(timeout:10))
        openBreakfastEntry()
        replace(app.textFields["entry.amount"],with:"2")
        XCTAssertTrue(app.staticTexts["200"].waitForExistence(timeout:5),"Resizing must recalculate actual displayed energy")
        app.buttons["entry.save"].tap()

        // Cold relaunch must read the actual persisted entry, not a preview fixture.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["nav.today"].waitForExistence(timeout:15))
        openBreakfastEntry()
        XCTAssertEqual(app.textFields["entry.amount"].value as? String,"2")
        XCTAssertTrue(app.staticTexts["200"].exists)
        let remove=app.buttons["entry.delete"]
        reveal(remove)
        remove.tap()
        let confirm=app.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout:5))
        confirm.tap()
        XCTAssertTrue(app.buttons["nav.today"].waitForExistence(timeout:10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["nav.today"].waitForExistence(timeout:15))
        let breakfastCount=app.staticTexts["diary.mealCount.breakfast"]
        reveal(breakfastCount)
        XCTAssertEqual(breakfastCount.label,"Add your first food","The actual persisted meal count must be empty after deletion")
        XCTAssertFalse(app.buttons["UI Test Oats"].exists,"Deleted entry must remain absent after relaunch")
    }

    func testRecipeDraftSurvivesIngredientSearch() throws {
        app.buttons["nav.kitchen"].tap()
        app.buttons["kitchen.create"].tap()
        let weighted=app.switches["recipe.byWeight"]
        XCTAssertTrue(weighted.waitForExistence(timeout:10))
        reveal(weighted)
        XCTAssertEqual(weighted.value as? String,"0")
        weighted.tap()
        XCTAssertEqual(weighted.value as? String,"1")
        let ingredient=app.buttons["recipe.addIngredient"]
        reveal(ingredient)
        ingredient.tap()
        let close=app.buttons["search.close"]
        XCTAssertTrue(close.waitForExistence(timeout:10))
        close.tap()
        XCTAssertTrue(weighted.waitForExistence(timeout:10))
        XCTAssertEqual(weighted.value as? String,"1","Returning from full-screen ingredient search must preserve the draft's cooked-weight choice")
        app.buttons["navigation.back"].tap()
        XCTAssertTrue(app.buttons["kitchen.create"].waitForExistence(timeout:10))
    }

    func testLanguageSelectionPersistsAfterRelaunch() throws {
        app.buttons["nav.settings"].tap()
        app.buttons["settings.language"].tap()
        app.buttons["language.option.ar"].tap()
        XCTAssertTrue(app.buttons["language.option.ar"].isSelected)
        app.terminate()
        // Remove the test-only English initialization; persistence must supply Arabic.
        app.launchArguments=["-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["nav.settings"].waitForExistence(timeout:15))
        app.buttons["nav.settings"].tap()
        app.buttons["settings.language"].tap()
        XCTAssertTrue(app.buttons["language.option.ar"].isSelected)
        app.buttons["language.option.en"].tap()
        XCTAssertTrue(app.buttons["language.option.en"].isSelected)
        app.buttons["language.back"].tap()
    }

    func testTabNavigationAndGoalsPersistAfterRelaunch() throws {
        for identifier in ["nav.kitchen","nav.progress","nav.settings","nav.today"] {
            app.buttons[identifier].tap()
            XCTAssertTrue(app.buttons[identifier].isSelected)
        }
        app.buttons["diary.goals"].tap()
        app.buttons["goals.editCalories"].tap()
        let calorieField=goalCalories()
        replace(calorieField,with:"2100")
        finishCalorieEditing()
        let save=app.buttons["goals.save"]
        XCTAssertTrue(save.waitForExistence(timeout:5))
        XCTAssertTrue(save.isEnabled,app.debugDescription)
        save.tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["diary.goals"].waitForExistence(timeout:15))
        app.buttons["diary.goals"].tap()
        app.buttons["goals.editCalories"].tap()
        XCTAssertEqual(goalCalories().value as? String,"2100")
        replace(goalCalories(),with:"2000")
        finishCalorieEditing()
        app.buttons["goals.save"].tap()
    }

    private func goalCalories()->XCUIElement {
        let direct=app.textFields["goals.calories"]
        if direct.waitForExistence(timeout:3) {return direct}
        return app.descendants(matching:.any).matching(identifier:"goals.calories").firstMatch.descendants(matching:.textField).firstMatch
    }

    private func finishCalorieEditing() {
        // The underlying goal sheet still exposes its Cancel control.
        // Scope to the actual Done action of the presented calorie form.
        let done=app.buttons.matching(identifier:"navigation.back")
            .matching(NSPredicate(format:"label == %@","Done")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout:5))
        done.tap()
        let dismissed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:done)
        XCTAssertEqual(XCTWaiter.wait(for:[dismissed],timeout:5),.completed,app.debugDescription)
    }

    private func openBreakfastEntry() {
        let details=app.descendants(matching:.any).matching(identifier:"diary.details.breakfast").firstMatch
        reveal(details)
        details.tap()
        let entry=app.buttons["UI Test Oats"]
        reveal(entry)
        entry.tap()
        XCTAssertTrue(app.textFields["entry.amount"].waitForExistence(timeout:5))
    }

    private func reveal(_ element:XCUIElement,file:StaticString=#filePath,line:UInt=#line) {
        for _ in 0..<8 {
            if element.exists && element.isHittable {return}
            scrollVisibleContentUp()
        }
        XCTAssertTrue(element.exists && element.isHittable,"Required real control is unreachable\n\(app.debugDescription)",file:file,line:line)
    }

    private func scrollVisibleContentUp() {
        // An app-wide swipe starts over the keyboard while editing a field.
        // Drag inside the actual visible form/scroll frame above that keyboard.
        let collection=app.collectionViews.firstMatch
        let content=collection.exists ? collection:app.scrollViews.firstMatch
        guard content.exists else{app.swipeUp();return}
        let frame=content.frame
        let keyboard=app.keyboards.firstMatch
        let top=max(frame.minY,app.frame.minY)
        let bottom=min(frame.maxY,keyboard.exists ? keyboard.frame.minY:app.frame.maxY)
        guard bottom-top>60 else{app.swipeUp();return}
        let origin=app.coordinate(withNormalizedOffset:CGVector(dx:0,dy:0))
        let x=frame.midX-app.frame.minX
        let start=origin.withOffset(CGVector(dx:x,dy:top+(bottom-top)*0.8-app.frame.minY))
        let end=origin.withOffset(CGVector(dx:x,dy:top+(bottom-top)*0.2-app.frame.minY))
        start.press(forDuration:0.05,thenDragTo:end)
    }

    private func replace(_ field:XCUIElement,with text:String) {
        XCTAssertTrue(field.waitForExistence(timeout:5),app.debugDescription)
        reveal(field)
        field.tap()
        let previous=field.value as? String ?? ""
        if !previous.isEmpty {
            // These numeric fields are trailing aligned. A center tap may leave
            // the caret inside 2000, so backspacing alone can produce 21002000.
            field.coordinate(withNormalizedOffset:CGVector(dx:0.98,dy:0.5)).tap()
            field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:previous.count))
        }
        field.typeText(text)
        XCTAssertEqual(field.value as? String,text,"The real field must contain the requested replacement before continuing.\n"+app.debugDescription)
    }
}
