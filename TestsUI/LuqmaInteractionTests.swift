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

    func testFoodAddResizePersistenceAndDelete() throws {
        app.buttons["nav.add"].tap()
        let manual=app.buttons["search.manual"]
        reveal(manual)
        manual.tap()
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
        XCTAssertFalse(app.buttons["UI Test Oats"].exists,"Deleted entry must remain absent after relaunch")
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
        app.buttons["navigation.back"].tap()
        let save=app.buttons["goals.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["diary.goals"].waitForExistence(timeout:15))
        app.buttons["diary.goals"].tap()
        app.buttons["goals.editCalories"].tap()
        XCTAssertEqual(goalCalories().value as? String,"2100")
        replace(goalCalories(),with:"2000")
        app.buttons["navigation.back"].tap()
        app.buttons["goals.save"].tap()
    }

    private func goalCalories()->XCUIElement {
        let direct=app.textFields["goals.calories"]
        if direct.waitForExistence(timeout:3) {return direct}
        return app.descendants(matching:.any).matching(identifier:"goals.calories").firstMatch.descendants(matching:.textField).firstMatch
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
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable,"Required real control is unreachable",file:file,line:line)
    }

    private func replace(_ field:XCUIElement,with text:String) {
        reveal(field)
        field.tap()
        let previous=field.value as? String ?? ""
        field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:previous.count)+text)
    }
}
