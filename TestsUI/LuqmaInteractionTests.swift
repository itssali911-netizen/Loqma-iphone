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
        // SwiftUI exposes a full-row Switch containing the actual UISwitch.
        // Its center is the label's empty space, not the toggle hit target.
        let weightControl=weighted.switches.firstMatch
        reveal(weightControl)
        weightControl.tap()
        XCTAssertEqual(weighted.value as? String,"1")
        let ingredient=app.buttons["recipe.addIngredient"]
        reveal(ingredient)
        ingredient.tap()
        let close=app.buttons["search.close"]
        XCTAssertTrue(close.waitForExistence(timeout:10))
        close.tap()
        let dismissed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:close)
        XCTAssertEqual(XCTWaiter.wait(for:[dismissed],timeout:5),.completed,app.debugDescription)
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

    func testFitnessDraftApplyAndDeletePreserveDiary() throws {
        let originalGoal=readCalorieGoal()
        let historyName="Fitness History Oats"
        addFitnessHistoryFood(named:historyName)
        openFitnessProfile()
        let edit=app.buttons["fitness.edit"]
        reveal(edit);edit.tap()
        assertAssessmentStep(1)
        tapAssessmentOption("assessment.goal.fatLoss")
        advanceAssessment(to:2)
        tapAssessmentOption("assessment.sex.male")
        advanceAssessment(to:3)

        // This is a real validation failure in the production form, not a
        // screenshot fixture or a prefilled answer injected into storage.
        replace(app.textFields["assessment.age"],with:"17")
        app.buttons["assessment.next"].tap()
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"assessment.validation").firstMatch.waitForExistence(timeout:5))
        assertAssessmentStep(3)
        replace(app.textFields["assessment.age"],with:"30")
        advanceAssessment(to:4)
        let saveDraft=app.buttons["assessment.saveDraft"]
        reveal(saveDraft);saveDraft.tap()
        XCTAssertTrue(app.scrollViews["fitness.profile"].waitForExistence(timeout:10),app.debugDescription)

        app.terminate();app.launch()
        XCTAssertTrue(app.buttons["nav.today"].waitForExistence(timeout:15))
        openFitnessProfile()
        let resume=app.buttons["fitness.edit"]
        reveal(resume);resume.tap()
        assertAssessmentStep(4)
        XCTAssertTrue(app.textFields["assessment.height"].exists,"The real saved page index must resume at height")
        app.buttons["assessment.back"].tap()
        assertAssessmentStep(3)
        XCTAssertEqual(app.textFields["assessment.age"].value as? String,"30","The typed age must survive a cold launch")
        advanceAssessment(to:4)
        replace(app.textFields["assessment.height"],with:"175")
        advanceAssessment(to:5)
        replace(app.textFields["assessment.weight"],with:"80")
        advanceAssessment(to:6)
        skipAssessment(to:7) // Target weight is optional.
        skipAssessment(to:8) // Pace uses its documented default.
        tapAssessmentOption("assessment.activity.light")
        advanceAssessment(to:9)
        for step in 10...16 {skipAssessment(to:step)}
        tapAssessmentOption("assessment.safety.generalAdult")
        advanceAssessment(to:17)
        let review=app.buttons["assessment.review"]
        reveal(review);review.tap()
        XCTAssertTrue(app.scrollViews["fitness.review"].waitForExistence(timeout:10),app.debugDescription)
        let current=app.staticTexts.matching(identifier:"fitness.review.calories.current").firstMatch
        let proposed=app.staticTexts.matching(identifier:"fitness.review.calories.proposed").firstMatch
        reveal(current)
        XCTAssertEqual(numeric(current.label),numeric(originalGoal),"Preview must leave the actual diary calorie target unchanged")
        let proposedGoal=proposed.label
        XCTAssertNotEqual(numeric(proposedGoal),numeric(originalGoal),"These adult inputs must produce a personalized target, not the unchanged default")
        XCTAssertTrue((numeric(proposedGoal) ?? 0)>0)
        let apply=app.buttons["fitness.apply"]
        reveal(apply);apply.tap()
        let applied=app.descendants(matching:.any).matching(identifier:"fitness.appliedConfirmation").firstMatch
        revealTowardTop(applied)
        XCTAssertTrue(applied.exists,"Success must follow an actual persisted plan application")

        app.terminate();app.launch()
        XCTAssertTrue(app.buttons["nav.today"].waitForExistence(timeout:15))
        XCTAssertEqual(numeric(readCalorieGoal()),numeric(proposedGoal),"Applied targets must feed the real diary and persist after relaunch")
        openFitnessProfile()
        let status=app.staticTexts["fitness.profile.appliedStatus"]
        reveal(status)
        XCTAssertEqual(status.value as? String,"active")
        let removeProfile=app.buttons["fitness.delete"]
        reveal(removeProfile);removeProfile.tap()
        let confirm=app.buttons["fitness.confirmDelete"]
        XCTAssertTrue(confirm.waitForExistence(timeout:5));confirm.tap()
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"fitness.deletedConfirmation").firstMatch.waitForExistence(timeout:10))
        app.terminate();app.launch()
        XCTAssertTrue(app.buttons["nav.today"].waitForExistence(timeout:15))
        XCTAssertEqual(numeric(readCalorieGoal()),numeric(proposedGoal),"Deleting fitness data must preserve the current diary targets as manual goals")
        openBreakfastEntry(named:historyName)
        XCTAssertEqual(app.textFields["entry.amount"].value as? String,"1")
        XCTAssertTrue(app.staticTexts["100"].exists,"The food logged before assessment must survive applying and deleting a fitness profile")

        // Remove only data created by this case, leaving subsequent existing
        // tests their original calorie target and empty breakfast diary.
        let removeEntry=app.buttons["entry.delete"]
        reveal(removeEntry);removeEntry.tap()
        XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout:5))
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.buttons["nav.today"].waitForExistence(timeout:10))
        app.buttons["diary.goals"].tap()
        app.buttons["goals.editCalories"].tap()
        replace(goalCalories(),with:originalGoal)
        finishCalorieEditing()
        app.buttons["goals.save"].tap()
        openFitnessProfile()
        XCTAssertTrue(app.buttons["fitness.edit"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["fitness.delete"].exists,"The deleted profile must remain absent after a cold launch")
    }

    private func openFitnessProfile() {
        app.buttons["nav.settings"].tap()
        let link=app.buttons["settings.fitness"]
        reveal(link);link.tap()
        XCTAssertTrue(app.scrollViews["fitness.profile"].waitForExistence(timeout:10),app.debugDescription)
    }

    private func addFitnessHistoryFood(named name:String) {
        app.buttons["nav.add"].tap()
        let personal=app.buttons["search.filter.3"]
        XCTAssertTrue(personal.waitForExistence(timeout:10));personal.tap()
        let manual=app.buttons["search.manual"]
        reveal(manual);manual.tap()
        replace(app.textFields["portion.name"],with:name)
        replace(app.textFields["portion.kcal"],with:"100")
        replace(app.textFields["portion.protein"],with:"10")
        replace(app.textFields["portion.carbs"],with:"15")
        replace(app.textFields["portion.fat"],with:"0")
        let save=app.buttons["portion.save"]
        reveal(save);XCTAssertTrue(save.isEnabled);save.tap()
        XCTAssertTrue(app.buttons["nav.today"].waitForExistence(timeout:10))
    }

    private func readCalorieGoal()->String {
        let goals=app.buttons["diary.goals"]
        reveal(goals);goals.tap()
        app.buttons["goals.editCalories"].tap()
        let value=goalCalories().value as? String ?? ""
        XCTAssertNotNil(numeric(value))
        finishCalorieEditing()
        app.buttons["goals.save"].tap()
        XCTAssertTrue(app.buttons["nav.today"].waitForExistence(timeout:10))
        return value
    }

    private func numeric(_ value:String)->Double? {Double(value.replacingOccurrences(of:",",with:"").replacingOccurrences(of:" ",with:""))}

    private func assertAssessmentStep(_ number:Int,file:StaticString=#filePath,line:UInt=#line) {
        let step=app.staticTexts["assessment.step"]
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == true AND label == %@","\(number) of 17"),object:step)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:10),.completed,app.debugDescription,file:file,line:line)
    }

    private func tapAssessmentOption(_ identifier:String) {
        let option=app.buttons[identifier]
        reveal(option);option.tap()
        XCTAssertTrue(option.isSelected,"The real choice must become selected")
    }

    private func advanceAssessment(to step:Int) {
        let next=app.buttons["assessment.next"]
        reveal(next);next.tap();assertAssessmentStep(step)
    }

    private func skipAssessment(to step:Int) {
        let skip=app.buttons["assessment.skip"]
        reveal(skip);skip.tap();assertAssessmentStep(step)
    }

    func testNotificationPermissionAndReminderPersistence() throws {
        // This case runs only on the first, newly created Simulator. No test flag
        // grants notification permission, enables a reminder, or inserts an inbox.
        app.buttons["nav.settings"].tap()
        let notifications=app.buttons["settings.notifications"]
        reveal(notifications)
        notifications.tap()
        XCTAssertTrue(app.staticTexts["No notifications here"].waitForExistence(timeout:10),app.debugDescription)
        let setup=app.buttons["Set up reminders"]
        reveal(setup)
        setup.tap()
        assertPermission("notDetermined")
        assertPendingCount("0")
        for kind in ["breakfast","lunch","dinner","snack","nutritionReview"] {
            let toggle=app.switches["reminders.toggle."+kind]
            XCTAssertTrue(toggle.exists,"Every supported reminder must be visible in the real settings hierarchy")
            XCTAssertEqual(toggle.value as? String,"0","A fresh install must not enable reminders")
        }

        let breakfastTime=app.buttons["reminders.time.breakfast"]
        reveal(breakfastTime)
        XCTAssertEqual(breakfastTime.value as? String,"08:00")
        breakfastTime.tap()
        let picker=app.descendants(matching:.any).matching(identifier:"reminders.timePicker").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout:10),app.debugDescription)
        XCTAssertEqual(picker.pickerWheels.count,2,"The production en_GB editor must expose actual hour and minute wheels")
        picker.pickerWheels.element(boundBy:1).adjust(toPickerWheelValue:"15")
        app.buttons["reminders.saveTime"].tap()
        XCTAssertTrue(breakfastTime.waitForExistence(timeout:10))
        XCTAssertEqual(breakfastTime.value as? String,"08:15","Saving the native editor must persist the selected minute")
        assertSavedConfirmation()

        setBreakfastReminder(enabled:true)
        assertSavedConfirmation()
        assertPermission("notDetermined")
        assertPendingCount("0")
        let springboard=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        XCTAssertFalse(springboard.alerts.firstMatch.waitForExistence(timeout:1),"Changing reminder preferences must not implicitly request notification permission")

        chooseNotificationPermission(allow:true)
        assertPermission("allowed")
        assertPendingCount("1")
        XCTAssertFalse(app.buttons["reminders.enablePermission"].exists)

        app.terminate()
        app.launch()
        openReminders()
        assertPermission("allowed")
        XCTAssertEqual(app.switches["reminders.toggle.breakfast"].value as? String,"1","Cold launch must reload the actual saved reminder choice")
        XCTAssertEqual(app.buttons["reminders.time.breakfast"].value as? String,"08:15","Cold launch must reload the actual saved time")
        assertPendingCount("1")
        setBreakfastReminder(enabled:false)
        assertSavedConfirmation()
        assertPendingCount("0")

        app.terminate()
        app.launch()
        openReminders()
        assertPermission("allowed")
        XCTAssertEqual(app.switches["reminders.toggle.breakfast"].value as? String,"0")
        assertPendingCount("0")
    }

    func testNotificationDeniedDoesNotClaimDelivery() throws {
        // The runner gives this case a second fresh Simulator because iOS has
        // no supported simctl notification-permission reset. This is a genuine
        // denial from the first-run system sheet, not a service stub.
        openReminders()
        assertPermission("notDetermined")
        assertPendingCount("0")
        setBreakfastReminder(enabled:true)
        assertSavedConfirmation()
        assertPermission("notDetermined")
        assertPendingCount("0")
        chooseNotificationPermission(allow:false)
        assertPermission("denied")
        assertPendingCount("0")
        XCTAssertEqual(app.switches["reminders.toggle.breakfast"].value as? String,"1","Denying OS permission must preserve the user's saved preference")
        XCTAssertTrue(app.buttons["reminders.openSettings"].exists,"Denied permission must expose the real iOS Settings recovery action")
        XCTAssertFalse(app.buttons["reminders.enablePermission"].exists,"The app cannot request a previously denied permission again")

        app.terminate()
        app.launch()
        openReminders()
        assertPermission("denied")
        XCTAssertEqual(app.switches["reminders.toggle.breakfast"].value as? String,"1")
        assertPendingCount("0")
        setBreakfastReminder(enabled:false)
        assertSavedConfirmation()
        assertPendingCount("0")
    }

    private func openReminders() {
        XCTAssertTrue(app.buttons["nav.settings"].waitForExistence(timeout:15))
        app.buttons["nav.settings"].tap()
        let link=app.buttons["settings.reminders"]
        reveal(link)
        link.tap()
        XCTAssertTrue(app.staticTexts["reminders.permissionStatus"].waitForExistence(timeout:10),app.debugDescription)
    }

    private func assertPermission(_ expected:String,file:StaticString=#filePath,line:UInt=#line) {
        let status=app.staticTexts["reminders.permissionStatus"]
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == true AND value == %@",expected),object:status)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:10),.completed,"Actual iOS permission status must become \(expected).\n"+app.debugDescription,file:file,line:line)
    }

    private func assertPendingCount(_ expected:String,file:StaticString=#filePath,line:UInt=#line) {
        let count=app.staticTexts["reminders.pendingCount"]
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == true AND label == %@",expected),object:count)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:10),.completed,"Actual system-scheduled request count must be \(expected).\n"+app.debugDescription,file:file,line:line)
    }

    private func assertSavedConfirmation(file:StaticString=#filePath,line:UInt=#line) {
        let confirmation=app.descendants(matching:.any).matching(identifier:"reminders.savedConfirmation").firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout:10),"A save confirmation must follow a successful production preference write.\n"+app.debugDescription,file:file,line:line)
    }

    private func setBreakfastReminder(enabled:Bool) {
        let row=app.switches["reminders.toggle.breakfast"]
        // The first row may be above the current offset after editing a time.
        revealTowardTop(row)
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:row)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:10),.completed,app.debugDescription)
        XCTAssertEqual(row.value as? String,enabled ? "0":"1")
        let control=row.switches.firstMatch
        (control.exists ? control:row).tap()
        let changed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@",enabled ? "1":"0"),object:row)
        XCTAssertEqual(XCTWaiter.wait(for:[changed],timeout:10),.completed,app.debugDescription)
    }

    private func chooseNotificationPermission(allow:Bool) {
        let request=app.buttons["reminders.enablePermission"]
        revealTowardTop(request)
        XCTAssertTrue(request.isEnabled)
        request.tap()
        let system=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        let alert=system.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout:10),"The production permission action must open the real iOS sheet")
        let text=alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator:" ").lowercased()
        XCTAssertTrue(text.contains("notifications"),"The observed system sheet must request notification access: "+text)
        let choice=allow ? alert.buttons["Allow"]:alert.buttons.matching(NSPredicate(format:"label == %@ OR label == %@","Don’t Allow","Don't Allow")).firstMatch
        XCTAssertTrue(choice.exists,"Required iOS notification permission choice is absent: "+alert.debugDescription)
        choice.tap()
    }

    private func revealTowardTop(_ element:XCUIElement) {
        for _ in 0..<8 {
            if element.exists && element.isHittable {return}
            let scroll=app.scrollViews.firstMatch
            if scroll.exists {scroll.swipeDown()}else{app.swipeDown()}
        }
        XCTAssertTrue(element.exists && element.isHittable,"Required real control is unreachable\n"+app.debugDescription)
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

    private func openBreakfastEntry(named name:String="UI Test Oats") {
        let details=app.descendants(matching:.any).matching(identifier:"diary.details.breakfast").firstMatch
        reveal(details)
        // The real DisclosureGroup chevron is the hit target. The button's
        // combined accessibility frame also includes the label's Spacer.
        let disclosure=details.images["collapsed"]
        reveal(disclosure)
        disclosure.tap()
        let entry=app.buttons[name]
        XCTAssertTrue(entry.waitForExistence(timeout:5),app.debugDescription)
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
