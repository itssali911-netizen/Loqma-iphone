import XCTest

/// Runs only against a newly created, empty Simulator. No Health samples are
/// injected and no measurement values or application hierarchy are logged.
final class AppleHealthInteractionTests:XCTestCase {
    private let app=XCUIApplication()
    private let springboard=XCUIApplication(bundleIdentifier:"com.apple.springboard")
    private let metricIDs=["health.steps.value","health.energy.value","health.weight.value","health.height.value"]

    override func setUpWithError()throws {
        continueAfterFailure=false
        #if !targetEnvironment(simulator)
        throw XCTSkip("This evidence suite requires its own empty Simulator; it never operates on personal iPhone Health data.")
        #endif
    }
    override func tearDownWithError()throws {app.terminate()}
    private func element(_ identifier:String)->XCUIElement {
        app.descendants(matching:.any).matching(identifier:identifier).firstMatch
    }
    private func launch(_ language:String){
        app.launchArguments=["-AppleLanguages","("+language+")","-AppleLocale",language=="ar" ? "ar_SA":"en_US"]
        if language=="en" {app.launchArguments.append("-loqma-ui-test-en")}
        app.launch()
    }
    private func capture(_ name:String){
        let attachment=XCTAttachment(screenshot:app.screenshot())
        attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }
    private func tapVisible(_ target:XCUIElement,file:StaticString=#filePath,line:UInt=#line){
        for _ in 0..<9 {
            if target.exists && target.isHittable {target.tap();return}
            let start=app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.73))
            let finish=app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.45))
            start.press(forDuration:0.01,thenDragTo:finish)
        }
        XCTFail("The real Health navigation/control must be reachable by scrolling.",file:file,line:line)
    }
    private func openHealth(_ language:String,settingsCapture:Bool=false){
        launch(language)
        XCTAssertTrue(app.buttons["nav.settings"].waitForExistence(timeout:25))
        app.buttons["nav.settings"].tap()
        if language=="ar" {
            // Use the restored application's real language controls. No 114
            // startup hook or synthetic application state is introduced.
            tapVisible(element("settings.language"))
            let option=app.buttons["language.option.ar"]
            XCTAssertTrue(option.waitForExistence(timeout:10))
            option.tap()
            XCTAssertTrue(option.isSelected)
            app.buttons["language.back"].tap()
        }
        let route=element("settings.health")
        XCTAssertTrue(route.waitForExistence(timeout:10))
        if settingsCapture {
            for _ in 0..<7 where !route.isHittable {
                app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.73)).press(forDuration:0.01,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.45)))
            }
            XCTAssertTrue(route.isHittable)
            capture("health-"+language+"-settings")
        }
        tapVisible(route)
        XCTAssertTrue(element("health.explanation").waitForExistence(timeout:10))
        XCTAssertTrue(element("health.connect").exists)
        XCTAssertTrue(element("health.refresh").exists)
    }
    private func assertEmptySimulatorReadings(file:StaticString=#filePath,line:UInt=#line){
        for identifier in metricIDs {
            let value=element(identifier)
            XCTAssertTrue(value.waitForExistence(timeout:8),"Each Health type must expose its real reading/unknown presentation.",file:file,line:line)
            // An unexpected sample is not printed or captured. This assertion
            // also catches inventing zero when an empty store has no reading.
            XCTAssertTrue(!value.label.isEmpty && value.label.rangeOfCharacter(from:.decimalDigits)==nil,
                          "Empty-Simulator evidence requires unknown readings; measurement capture is withheld.",file:file,line:line)
        }
        XCTAssertTrue(!element("health.explanation").label.isEmpty,"Explain purpose and partial sharing without claiming read permission.",file:file,line:line)
    }
    private func calorieTarget(file:StaticString=#filePath,line:UInt=#line)->String {
        // The original 103 home card is a passive VStack, not a combined AX
        // element. Read its existing editor's explicit value, then Cancel;
        // observing the target must never save or rebalance the diary goals.
        let route=app.buttons["diary.goals"]
        XCTAssertTrue(route.waitForExistence(timeout:25),file:file,line:line)
        tapVisible(route,file:file,line:line)
        let goal=app.buttons["goals.editCalories"]
        XCTAssertTrue(goal.waitForExistence(timeout:10),file:file,line:line)
        let value=goal.value as? String ?? ""
        XCTAssertTrue(value.rangeOfCharacter(from:.decimalDigits) != nil,"Read the actual saved calorie target through its existing control.",file:file,line:line)
        let cancel=app.buttons.matching(identifier:"navigation.back")
            .matching(NSPredicate(format:"label IN %@",["Cancel","إلغاء"])).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout:5),file:file,line:line)
        cancel.tap()
        let dismissed=XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in
            !self.app.buttons["goals.editCalories"].exists && self.app.buttons["nav.today"].isHittable
        },object:app)
        XCTAssertEqual(XCTWaiter.wait(for:[dismissed],timeout:8),.completed,"Cancel must dismiss the actual goal sheet without saving.",file:file,line:line)
        return value
    }
    private func knownConsentButton(_ labels:[String])->XCUIElement? {
        for host in [app,springboard] {
            let healthContext=(host.staticTexts.matching(NSPredicate(format:"label IN %@",["Health Access","Health"])).firstMatch.exists || host.navigationBars["Health Access"].exists)
            guard healthContext else {continue}
            for label in labels {
                let button=host.buttons.matching(NSPredicate(format:"label == %@",label)).firstMatch
                if button.exists && button.isHittable{return button}
            }
        }
        return nil
    }
    func testARealNativeAuthorizationOrExplicitUnavailableKeepsGoals()throws {
        launch("en")
        let initialGoal=calorieTarget()
        capture("restored-en-home-before-health")
        app.buttons["nav.settings"].tap()
        tapVisible(element("settings.health"))
        XCTAssertTrue(element("health.explanation").waitForExistence(timeout:10))
        assertEmptySimulatorReadings()
        capture("health-en-before-authorization")
        let connect=element("health.connect"),issue=element("health.issue"),lastCheck=element("health.lastCheck")
        let issueBefore=issue.exists ? issue.label:nil
        let checkedBefore=lastCheck.exists ? lastCheck.label:nil
        if !connect.isEnabled {
            XCTAssertTrue(issue.exists && !issue.label.isEmpty,"Unavailable connection needs a concrete localized issue.")
            print("LUQMA_HEALTHKIT_VALIDATION:explicit_unavailable")
        } else {
            tapVisible(connect)
            let deadline=Date().addingTimeInterval(18)
            var outcome:String?
            while Date()<deadline && outcome==nil {
                if let decline=knownConsentButton(["Don’t Allow","Don't Allow","Do Not Allow"]){
                    capture("health-en-native-permission-sheet")
                    decline.tap();outcome="native_sheet_declined"
                } else if let allow=knownConsentButton(["Allow"]){
                    // Observe the native consent UI, leave every per-type read
                    // switch unchanged, and finish it. This is not a read-grant
                    // assertion; HealthKit does not disclose denied reads.
                    capture("health-en-native-permission-sheet")
                    allow.tap();outcome="native_sheet_completed_without_grant_claim"
                } else if issue.exists && !issue.label.isEmpty && issue.label != issueBefore {
                    outcome="explicit_unavailable"
                } else if lastCheck.exists && lastCheck.label != checkedBefore {
                    outcome="request_completed_without_observed_sheet"
                } else {Thread.sleep(forTimeInterval:0.3)}
            }
            if outcome==nil {capture("health-en-unrecognized-system-state")}
            XCTAssertTrue(outcome != nil,"Connect must present native consent or visibly report a completed request/concrete issue; an inert button fails.")
            if let outcome {print("LUQMA_HEALTHKIT_VALIDATION:"+outcome)}
        }
        XCTAssertTrue(element("health.explanation").waitForExistence(timeout:10))
        assertEmptySimulatorReadings()
        capture("health-en-after-authorization")
        XCTAssertTrue(app.buttons["nav.today"].exists)
        app.buttons["nav.today"].tap()
        XCTAssertEqual(calorieTarget(),initialGoal,"Apple Health must not change the saved calorie target.")
        capture("restored-en-home-after-health")
        print("LUQMA_HEALTHKIT_VALIDATION:calorie_target_unchanged")
    }
    private func verifyNavigationAndCapture(_ language:String){
        openHealth(language,settingsCapture:true)
        assertEmptySimulatorReadings()
        capture("health-"+language+"-overview")
        let refresh=element("health.refresh")
        if refresh.isEnabled {
            tapVisible(refresh)
            XCTAssertTrue(element("health.lastCheck").waitForExistence(timeout:12))
            assertEmptySimulatorReadings()
            print("LUQMA_HEALTHKIT_VALIDATION:manual_refresh_tapped")
        }
        app.buttons["nav.progress"].tap()
        XCTAssertTrue(app.buttons["nav.progress"].isSelected)
        // Progress keeps its original 103 layout: no inserted Health card.
        capture("health-"+language+"-progress")
        app.buttons["nav.settings"].tap()
        // The original TabView retains each tab's NavigationStack. Returning
        // to Settings can already show Health; do not look for its root row.
        if !element("health.explanation").exists {tapVisible(element("settings.health"))}
        XCTAssertTrue(element("health.explanation").waitForExistence(timeout:10))
        app.buttons["nav.today"].tap()
        XCTAssertFalse(calorieTarget().isEmpty,"The restored home stays usable independently of Health availability.")
    }
    func testBEnglishSettingsAndProgressAreUsable()throws {verifyNavigationAndCapture("en")}
    func testCArabicSettingsAndProgressAreUsable()throws {verifyNavigationAndCapture("ar")}
}
