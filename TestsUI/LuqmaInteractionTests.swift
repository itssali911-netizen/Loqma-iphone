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
        XCTAssertTrue(app.buttons["portion.unit.serving"].isSelected)
        XCTAssertEqual(app.textFields["portion.amount"].value as? String,"1")
        replace(app.textFields["portion.kcal"],with:"100")
        replace(app.textFields["portion.protein"],with:"10")
        replace(app.textFields["portion.carbs"],with:"15")
        replace(app.textFields["portion.fat"],with:"0")
        let save=app.buttons["portion.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.buttons["nav.today"].waitForExistence(timeout:10))
        let target=try XCTUnwrap(numeric(readCalorieGoal()))
        let details=app.buttons["diary.calorieDetails"]
        reveal(details);details.tap()
        let consumed=app.staticTexts["calorie.consumed"]
        XCTAssertTrue(consumed.waitForExistence(timeout:10))
        XCTAssertEqual(numeric(consumed.label),100)
        XCTAssertTrue(app.staticTexts["calorie.remaining"].label.contains(String(Int(target-100))))
        for (key,value) in [("carbs","15g"),("protein","10g"),("fat","0g")] {
            let macro=app.staticTexts["calorie.macro."+key]
            reveal(macro)
            XCTAssertEqual(macro.label,value)
        }
        let date=app.buttons["calorie.date"]
        reveal(date);date.tap()
        XCTAssertTrue(app.datePickers["calorie.datePicker"].waitForExistence(timeout:5))
        app.buttons["navigation.back"].tap()
        XCTAssertEqual(numeric(consumed.label),100,"Dismissing the calendar must retain the chosen day")
        app.buttons["calorie.back"].tap()
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
        // Unsuitable cases stop at the real early safety question and never
        // create a plan. The normal diary remains available after this error.
        tapAssessmentOption("assessment.safety.medicalDiet")
        tapAssessmentNextExpectingError(at:2)
        let eligibilityError=app.descendants(matching:.any).matching(identifier:"assessment.validation").firstMatch
        XCTAssertTrue(eligibilityError.label.contains("This estimator does not create plans"),"Unsuitable assessment answers must explain why the plan cannot be previewed")
        XCTAssertFalse(app.alerts["Notice"].exists,"The inline assessment message must not compete with the root alert")
        XCTAssertFalse(app.scrollViews["fitness.review"].exists,"A rejected assessment must not create or apply a plan")
        tapAssessmentOption("assessment.safety.generalAdult")
        advanceAssessment(to:3)
        tapAssessmentOption("assessment.sex.male")
        advanceAssessment(to:4)

        // Exercise the actual controls from an empty answer: no fake default
        // is inserted into storage, and an unanswered step cannot advance.
        tapAssessmentNextExpectingError(at:4)
        let age=app.textFields["assessment.age"]
        let increaseAge=app.buttons["assessment.age.increase"]
        revealAssessmentControl(increaseAge);increaseAge.tap()
        XCTAssertEqual(numeric(age.value as? String ?? ""),31,"The first + must bootstrap an empty age using the stated suggestion")
        exerciseAssessmentPicker("assessment.age.slider",field:age,range:18...100,vertical:true)
        replace(age,with:"17")
        tapAssessmentNextExpectingError(at:4)
        XCTAssertEqual(age.value as? String,"17","Invalid input must remain editable instead of disappearing")
        replace(age,with:"30")
        advanceAssessment(to:5)
        saveAndResumeFitnessDraft(expectedStep:5)
        XCTAssertTrue(app.textFields["assessment.height"].exists,"The real saved page identifier must resume at height")
        backAssessment(to:4)
        XCTAssertEqual(app.textFields["assessment.age"].value as? String,"30","The typed age must survive a cold launch")
        advanceAssessment(to:5)

        let height=app.textFields["assessment.height"]
        tapAssessmentNextExpectingError(at:5)
        let increaseHeight=app.buttons["assessment.height.increase"]
        revealAssessmentControl(increaseHeight);increaseHeight.tap()
        XCTAssertEqual(numeric(height.value as? String ?? ""),170.5,"The first + must make an empty height usable")
        let decreaseHeight=app.buttons["assessment.height.decrease"]
        revealAssessmentControl(decreaseHeight);decreaseHeight.tap()
        XCTAssertEqual(numeric(height.value as? String ?? ""),170)
        exerciseAssessmentPicker("assessment.height.slider",field:height,range:120...230,vertical:false)
        replace(height,with:"999")
        tapAssessmentNextExpectingError(at:5)
        XCTAssertEqual(height.value as? String,"999","Out-of-range manual input must stay visible for correction")
        saveAndResumeFitnessDraft(expectedStep:5)
        XCTAssertEqual(height.value as? String,"999","Save/resume must retain invalid raw input without treating it as a valid measurement")
        backAssessment(to:4)
        XCTAssertEqual(age.value as? String,"30")
        advanceAssessment(to:5)
        XCTAssertEqual(height.value as? String,"999","Back/forward must not discard an unfinished answer")
        replace(height,with:"175")
        finishAssessmentEditing()
        XCTAssertEqual(numeric(height.value as? String ?? ""),175,"Closing the keyboard must preserve the typed measurement")
        revealAssessmentControl(increaseHeight);increaseHeight.tap()
        XCTAssertEqual(numeric(height.value as? String ?? ""),175.5,"Buttons, manual entry and the slider must edit the same value")
        backAssessment(to:4)
        advanceAssessment(to:5)
        XCTAssertEqual(numeric(height.value as? String ?? ""),175.5,"The visible chosen height must match the retained answer")
        advanceAssessment(to:6)
        replace(app.textFields["assessment.weight"],with:"80")
        finishAssessmentEditing()
        exerciseAssessmentPicker("assessment.weight.slider",field:app.textFields["assessment.weight"],range:35...300,vertical:false)
        replace(app.textFields["assessment.weight"],with:"80")
        finishAssessmentEditing()
        let repeatedNext=app.buttons["assessment.next"]
        reveal(repeatedNext);waitUntilEnabled(repeatedNext);repeatedNext.doubleTap()
        assertAssessmentStep(7)
        XCTAssertTrue(app.textFields["assessment.target"].exists,"Rapid repeated Continue taps must advance only once, rather than skipping an optional question")
        replace(app.textFields["assessment.target"],with:"999")
        tapAssessmentNextExpectingError(at:7)
        replace(app.textFields["assessment.target"],with:"70")
        finishAssessmentEditing()
        skipAssessment(to:8)
        backAssessment(to:7)
        XCTAssertEqual(numeric(app.textFields["assessment.target"].value as? String ?? ""),70,"Optional skip must preserve an answer already supplied")
        advanceAssessment(to:8)
        let activityDetails=app.descendants(matching:.any).matching(identifier:"assessment.activity.details").firstMatch
        revealAssessmentControl(activityDetails)
        let activityDisclosure=activityDetails.images["collapsed"]
        XCTAssertTrue(activityDisclosure.waitForExistence(timeout:5) && activityDisclosure.isHittable,"The activity choices must open through their actual disclosure control")
        activityDisclosure.tap()
        tapAssessmentOption("assessment.activity.light")
        advanceAssessment(to:9)
        tapAssessmentOption("assessment.experience.beginner")
        replace(app.textFields["assessment.days"],with:"3")
        replace(app.textFields["assessment.minutes"],with:"30")
        finishAssessmentEditing()
        skipAssessment(to:10)
        backAssessment(to:9)
        XCTAssertEqual(numeric(app.textFields["assessment.days"].value as? String ?? ""),3)
        XCTAssertEqual(numeric(app.textFields["assessment.minutes"].value as? String ?? ""),30,"Grouped training answers must survive optional skip and Back")
        advanceAssessment(to:10)
        replace(app.textFields["assessment.sleepHours"],with:"7.5")
        finishAssessmentEditing()
        skipAssessment(to:11)
        backAssessment(to:10)
        XCTAssertEqual(numeric(app.textFields["assessment.sleepHours"].value as? String ?? ""),7.5)
        advanceAssessment(to:11)
        recordFitnessScreen("Fitness compact review after manual and slider edits")
        let review=app.buttons["assessment.review"]
        reveal(review);waitUntilEnabled(review);review.tap()
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
        revealFitnessDelete(removeProfile)
        recordFitnessScreen("Fitness profile before delete confirmation")
        removeProfile.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        recordFitnessScreen("Fitness delete confirmation after real tap")
        // Native alerts may expose a non-interactive accessibility wrapper
        // around the action. Require the titled alert and tap only a real,
        // enabled, hittable button with the destructive action's exact label.
        let confirmation=app.alerts["Delete fitness assessment data?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout:5),app.debugDescription)
        let confirmButtons=confirmation.buttons.matching(NSPredicate(format:"label == %@","Delete fitness profile"))
        let confirmReady=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in
            confirmation.exists && confirmButtons.allElementsBoundByIndex.contains { $0.exists && $0.isEnabled && $0.isHittable }
        },object:confirmation)
        XCTAssertEqual(XCTWaiter.wait(for:[confirmReady],timeout:5),.completed,app.debugDescription)
        let confirm=try XCTUnwrap(confirmButtons.allElementsBoundByIndex.first { $0.exists && $0.isEnabled && $0.isHittable },
            "The actual native destructive action must be reachable inside its confirmation alert.\n"+app.debugDescription)
        confirm.tap()
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
    private func recordFitnessScreen(_ name:String) {
        print("LUQMA_FITNESS_CHECKPOINT \(name)\n"+app.debugDescription)
        let attachment=XCTAttachment(screenshot:app.screenshot())
        attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }
    private func revealFitnessDelete(_ button:XCUIElement,file:StaticString=#filePath,line:UInt=#line) {
        let profile=app.scrollViews["fitness.profile"]
        XCTAssertTrue(profile.exists,file:file,line:line)
        for _ in 0..<12 {
            let viewport=profile.frame.intersection(app.frame)
            let nav=app.buttons["nav.today"]
            let top=max(viewport.minY,app.frame.minY+100)
            let bottom=min(viewport.maxY,nav.exists ? nav.frame.minY:app.frame.maxY)-12
            if button.exists && button.isHittable && button.frame.minY>=top+8 && button.frame.maxY<=bottom {
                print("LUQMA_FITNESS_DELETE_FRAME \(button.frame) viewport \(viewport) safeY \(top)...\(bottom)")
                return
            }
            XCTAssertGreaterThan(bottom-top,80,file:file,line:line)
            let origin=app.coordinate(withNormalizedOffset:CGVector(dx:0,dy:0))
            let x=viewport.midX-app.frame.minX
            origin.withOffset(CGVector(dx:x,dy:bottom-25-app.frame.minY))
                .press(forDuration:0.05,thenDragTo:origin.withOffset(CGVector(dx:x,dy:top+25-app.frame.minY)))
        }
        XCTFail("Delete must be fully inside the visible profile, above the app navigation.\n"+app.debugDescription,file:file,line:line)
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
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == true AND label == %@","\(number) of 11"),object:step)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:10),.completed,app.debugDescription,file:file,line:line)
    }

    private func waitUntilEnabled(_ control:XCUIElement,file:StaticString=#filePath,line:UInt=#line) {
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == true AND enabled == true"),object:control)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:10),.completed,"The actual control must finish its current action before receiving another tap.\n"+app.debugDescription,file:file,line:line)
    }

    private func tapAssessmentNextExpectingError(at step:Int,file:StaticString=#filePath,line:UInt=#line) {
        let next=app.buttons["assessment.next"]
        reveal(next);waitUntilEnabled(next);next.tap()
        let error=app.descendants(matching:.any).matching(identifier:"assessment.validation").firstMatch
        // SandowStateAlert combines static text for accessibility; it has no
        // tap action. Require a readable message fully in the foreground form,
        // rather than a hit target that iOS need not expose for StaticText.
        let visible=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in
            guard error.exists,!error.label.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {return false}
            let frame=error.frame
            return !frame.isEmpty && self.assessmentVisibleArea().contains(frame)
        },object:error)
        XCTAssertEqual(XCTWaiter.wait(for:[visible],timeout:5),.completed,"The rejected step must bring its reason into view.\n"+app.debugDescription,file:file,line:line)
        assertAssessmentStep(step,file:file,line:line)
    }

    private func exerciseAssessmentPicker(_ identifier:String,field:XCUIElement,range:ClosedRange<Double>,vertical:Bool,file:StaticString=#filePath,line:UInt=#line) {
        let picker=app.descendants(matching:.any).matching(identifier:identifier).firstMatch
        revealAssessmentControl(picker,file:file,line:line)
        let original=numeric(field.value as? String ?? "")
        var previous=original
        // The approved controls are a five-row vertical wheel and horizontal
        // ruler, not UISliders. Drag the visible real controls three times,
        // without injected state, private gesture APIs or artificial waits.
        for (from,to) in [(CGFloat(0.70),CGFloat(0.30)),(CGFloat(0.30),CGFloat(0.70)),(CGFloat(0.65),CGFloat(0.40))] {
            XCTAssertTrue(assessmentControlIsVisible(picker,in:assessmentVisibleArea()),"The entire actual picker must remain in the foreground before each drag",file:file,line:line)
            let start=picker.coordinate(withNormalizedOffset:CGVector(dx:vertical ? 0.5:from,dy:vertical ? from:0.5))
            let end=picker.coordinate(withNormalizedOffset:CGVector(dx:vertical ? 0.5:to,dy:vertical ? to:0.5))
            start.press(forDuration:0.05,thenDragTo:end)
            guard let displayed=numeric(field.value as? String ?? "") else {
                XCTFail("Dragging must always leave a visible numeric measurement.\n"+app.debugDescription,file:file,line:line);return
            }
            XCTAssertTrue(displayed.isFinite && range.contains(displayed),"The actual value must remain in the displayed supported range",file:file,line:line)
            XCTAssertTrue(assessmentControlIsVisible(field,in:assessmentVisibleArea()),"The value read after dragging must be visible above the footer",file:file,line:line)
            XCTAssertNotEqual(displayed,previous,"Each real wheel/ruler drag must update the editable answer",file:file,line:line)
            previous=displayed
        }
        XCTAssertNotEqual(numeric(field.value as? String ?? ""),original,"Consecutive wheel/ruler drags must update the actual editable answer",file:file,line:line)
        recordFitnessScreen("Fitness approved wheel/ruler interaction "+identifier)
    }

    private func finishAssessmentEditing(file:StaticString=#filePath,line:UInt=#line) {
        let done=app.buttons["assessment.keyboardDone"]
        XCTAssertTrue(done.waitForExistence(timeout:5) && done.isHittable,"Numeric entry must expose a real keyboard Done action",file:file,line:line)
        done.tap()
        let dismissed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for:[dismissed],timeout:5),.completed,"Done must dismiss the actual numeric keyboard",file:file,line:line)
    }

    private func saveAndResumeFitnessDraft(expectedStep:Int) {
        let save=app.buttons["assessment.saveDraft"]
        reveal(save);waitUntilEnabled(save);save.tap()
        // The profile remains underneath the sheet throughout assessment, so
        // its existence alone cannot establish that async saving has finished.
        let dismissed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:app.scrollViews["assessment.form"])
        XCTAssertEqual(XCTWaiter.wait(for:[dismissed],timeout:10),.completed,"Save-and-later must finish and dismiss the actual assessment before terminating the app.\n"+app.debugDescription)
        XCTAssertTrue(app.scrollViews["fitness.profile"].waitForExistence(timeout:10),app.debugDescription)
        app.terminate();app.launch()
        XCTAssertTrue(app.buttons["nav.today"].waitForExistence(timeout:15))
        openFitnessProfile()
        let resume=app.buttons["fitness.edit"]
        reveal(resume);resume.tap()
        assertAssessmentStep(expectedStep)
    }

    private func tapAssessmentOption(_ identifier:String) {
        let option=app.buttons[identifier]
        revealAssessmentControl(option);waitUntilEnabled(option);option.tap()
        XCTAssertTrue(option.isSelected,"The real choice must become selected")
    }

    private func revealAssessmentControl(_ control:XCUIElement,file:StaticString=#filePath,line:UInt=#line) {
        let form=app.scrollViews["assessment.form"]
        XCTAssertTrue(form.exists,file:file,line:line)
        for _ in 0..<10 {
            let viewport=form.frame.intersection(app.frame)
            let visible=assessmentVisibleArea()
            let top=visible.minY
            let bottom=visible.maxY
            if assessmentControlIsVisible(control,in:visible) {return}
            XCTAssertGreaterThan(bottom-top,80,file:file,line:line)
            // AX can report fields behind Skip/Continue or the keyboard as
            // hittable. Restrict every real gesture to the foreground form.
            let upward = !control.exists || control.frame.maxY>bottom
            let origin=app.coordinate(withNormalizedOffset:CGVector(dx:0,dy:0))
            // The real 16pt outer gutter is outside the approved full-width
            // ruler/wheel. Scrolling there must not change a measurement.
            let x=viewport.minX+8-app.frame.minX
            let start=upward ? bottom-20:top+20
            let end=upward ? top+20:bottom-20
            origin.withOffset(CGVector(dx:x,dy:start-app.frame.minY))
                .press(forDuration:0.05,thenDragTo:origin.withOffset(CGVector(dx:x,dy:end-app.frame.minY)))
        }
        XCTFail("The real assessment control must be fully visible between its header, first footer action and keyboard.\n"+app.debugDescription,file:file,line:line)
    }

    private func assessmentVisibleArea()->CGRect {
        let viewport=app.scrollViews["assessment.form"].frame.intersection(app.frame)
        let top=max(viewport.minY,app.buttons["assessment.back"].frame.maxY)+24
        var lowerEdges=[viewport.maxY]
        for identifier in ["assessment.skip","assessment.next","assessment.review","assessment.saveDraft"] {
            let control=app.buttons[identifier]
            if control.exists {lowerEdges.append(control.frame.minY)}
        }
        let keyboard=app.keyboards.firstMatch
        if keyboard.exists {
            lowerEdges.append(keyboard.frame.minY)
            let done=app.buttons["assessment.keyboardDone"]
            if done.exists {lowerEdges.append(done.frame.minY)}
        }
        let bottom=(lowerEdges.min() ?? viewport.maxY)-8
        return CGRect(x:viewport.minX,y:top,width:viewport.width,height:max(0,bottom-top))
    }

    private func assessmentControlIsVisible(_ control:XCUIElement,in visible:CGRect)->Bool {
        control.exists && control.isHittable && !control.frame.isEmpty && visible.contains(control.frame)
    }

    private func focusAssessmentField(_ field:XCUIElement,file:StaticString=#filePath,line:UInt=#line) {
        // Switching from one numeric field to a lower field must not tap the
        // pinned Continue action occupying its old off-screen AX coordinates.
        if app.keyboards.firstMatch.exists {finishAssessmentEditing(file:file,line:line)}
        for attempt in 0..<3 {
            revealAssessmentControl(field,file:file,line:line)
            waitUntilEnabled(field,file:file,line:line)
            if attempt == 0 && field.identifier == "assessment.minutes" {
                print("LUQMA_ASSESSMENT_INPUT_FRAME \(field.identifier) \(field.frame) visible \(assessmentVisibleArea())")
                recordFitnessScreen("Fitness training minutes before real field focus")
            }
            field.tap()
            // Opening the keyboard can move both the field and the footer.
            // Recheck actual geometry before any caret tap or typing.
            revealAssessmentControl(field,file:file,line:line)
            if app.keyboards.firstMatch.exists && assessmentControlIsVisible(field,in:assessmentVisibleArea()) {return}
            // Interactive scrolling may dismiss the keyboard while revealing
            // a field. The next bounded attempt focuses that visible field.
        }
        XCTFail("The real assessment field must remain visible and focused after the keyboard opens.\n"+app.debugDescription,file:file,line:line)
    }

    private func advanceAssessment(to step:Int) {
        let next=app.buttons["assessment.next"]
        reveal(next);waitUntilEnabled(next);next.tap();assertAssessmentStep(step)
    }

    private func backAssessment(to step:Int) {
        let back=app.buttons["assessment.back"]
        waitUntilEnabled(back);back.tap();assertAssessmentStep(step)
    }

    private func skipAssessment(to step:Int) {
        let skip=app.buttons["assessment.skip"]
        reveal(skip);waitUntilEnabled(skip);skip.tap();assertAssessmentStep(step)
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
        if field.identifier.hasPrefix("assessment.") {focusAssessmentField(field)}
        else if field.identifier.hasPrefix("portion."){focusPortionField(field)}
        else {reveal(field);field.tap()}
        let previous=field.value as? String ?? ""
        if !previous.isEmpty {
            // These numeric fields are trailing aligned. A center tap may leave
            // the caret inside 2000, so backspacing alone can produce 21002000.
            if field.identifier.hasPrefix("assessment.") {
                XCTAssertTrue(assessmentControlIsVisible(field,in:assessmentVisibleArea()),"The actual caret target must remain clear of the pinned footer and keyboard.\n"+app.debugDescription)
            }
            if field.identifier.hasPrefix("portion."){
                XCTAssertTrue(assessmentControlIsVisible(field,in:portionVisibleArea(containing:field)),"The actual portion caret target must remain inside its visible scroll area.\n"+app.debugDescription)
            }
            field.coordinate(withNormalizedOffset:CGVector(dx:0.98,dy:0.5)).tap()
            field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:previous.count))
        }
        field.typeText(text)
        XCTAssertEqual(field.value as? String,text,"The real field must contain the requested replacement before continuing.\n"+app.debugDescription)
    }

    private func portionVisibleArea(containing field:XCUIElement)->CGRect {
        let content=app.scrollViews.containing(.textField,identifier:field.identifier).firstMatch
        let viewport=content.frame.intersection(app.frame)
        var bottom=viewport.maxY
        let save=app.buttons["portion.save"]
        if save.exists{bottom=min(bottom,save.frame.minY)}
        let keyboard=app.keyboards.firstMatch
        if keyboard.exists{bottom=min(bottom,keyboard.frame.minY)}
        return CGRect(x:viewport.minX,y:viewport.minY+8,width:viewport.width,height:max(0,bottom-viewport.minY-16))
    }

    private func revealPortionField(_ field:XCUIElement,file:StaticString=#filePath,line:UInt=#line){
        let content=app.scrollViews.containing(.textField,identifier:field.identifier).firstMatch
        XCTAssertTrue(content.exists,"The actual portion editor must contain its numeric field",file:file,line:line)
        for _ in 0..<12{
            let visible=portionVisibleArea(containing:field)
            if assessmentControlIsVisible(field,in:visible){return}
            XCTAssertGreaterThan(visible.height,60,file:file,line:line)
            let upward = !field.exists || field.frame.maxY>visible.maxY
            let origin=app.coordinate(withNormalizedOffset:CGVector(dx:0,dy:0))
            let x=visible.minX+8-app.frame.minX
            let start=upward ? visible.maxY-12:visible.minY+12
            let end=upward ? visible.minY+12:visible.maxY-12
            origin.withOffset(CGVector(dx:x,dy:start-app.frame.minY))
                .press(forDuration:0.05,thenDragTo:origin.withOffset(CGVector(dx:x,dy:end-app.frame.minY)))
        }
        XCTFail("The actual portion field must be fully visible above the pinned Add food action and keyboard.\n"+app.debugDescription,file:file,line:line)
    }

    private func focusPortionField(_ field:XCUIElement,file:StaticString=#filePath,line:UInt=#line){
        for _ in 0..<3{
            revealPortionField(field,file:file,line:line);waitUntilEnabled(field,file:file,line:line);field.tap()
            revealPortionField(field,file:file,line:line)
            if app.keyboards.firstMatch.exists && assessmentControlIsVisible(field,in:portionVisibleArea(containing:field)){return}
        }
        XCTFail("The actual portion field must remain visible and focused when its keyboard opens.\n"+app.debugDescription,file:file,line:line)
    }
}
