import XCTest

/// Actual native navigation and typing. No analysis responses, permission
/// grants or user data are injected. Reduced mode is enabled through the real
/// Simulator Settings UI, never an app override or a private preferences API.
final class MotionInteractionTests:XCTestCase {
    private let app=XCUIApplication()
    override func setUpWithError() throws {
        continueAfterFailure=false
        #if !targetEnvironment(simulator)
        throw XCTSkip("Requires a disposable Simulator with an empty diary")
        #endif
    }
    override func tearDownWithError() throws {
        if let testRun,testRun.failureCount>0 {print("LUQMA_MOTION_FAILED_HIERARCHY\n"+app.debugDescription)}
        capture("motion-final-"+name.components(separatedBy:CharacterSet.alphanumerics.inverted).filter{!$0.isEmpty}.joined(separator:"-"))
        app.terminate()
    }
    func testNativeTabsSearchAndDismissal() {exercise(reduced:false)}
    func testReduceMotionTabsSearchAndDismissal() throws {
        try MotionSystemSettingsTests.enableReduceMotion()
        exercise(reduced:true)
    }
    private func exercise(reduced:Bool) {
        app.launchArguments=["-loqma-ui-test-en","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["nav.today"].waitForExistence(timeout:20))
        for _ in 0..<2 {
            for identifier in ["nav.kitchen","nav.progress","nav.settings","nav.today"] {
                let button=app.buttons[identifier]
                XCTAssertTrue(button.waitForExistence(timeout:10));XCTAssertTrue(button.isHittable)
                button.tap();XCTAssertTrue(button.isSelected)
            }
        }
        for query in ["milk","rice"] {
            app.buttons["nav.add"].tap()
            let field=app.textFields["search.query"]
            XCTAssertTrue(field.waitForExistence(timeout:10));field.tap();field.typeText(query)
            XCTAssertEqual(field.value as? String,query,"Animation must not swallow keyboard input")
            capture(reduced ? "motion-reduced-search":"motion-standard-search")
            let close=app.buttons["search.close"]
            XCTAssertTrue(close.isHittable);close.tap()
            XCTAssertTrue(app.buttons["nav.today"].waitForExistence(timeout:10))
            XCTAssertTrue(app.buttons["nav.today"].isSelected)
        }
        app.buttons["nav.settings"].tap()
        let health=app.buttons["settings.health"]
        for _ in 0..<6 {
            if health.exists && health.isHittable {break}
            app.swipeUp()
        }
        XCTAssertTrue(health.isHittable);health.tap()
        let manage=app.buttons["health.manageAccess"]
        XCTAssertTrue(manage.waitForExistence(timeout:10))
        capture(reduced ? "motion-reduced-health":"motion-standard-health")
        manage.tap()
        let done=app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout:10));done.tap()
        // This exercises a real native guide sheet, not an authorization grant.
        XCTAssertTrue(manage.waitForExistence(timeout:10))
        app.buttons["navigation.back"].tap()
        XCTAssertTrue(app.buttons["settings.health"].waitForExistence(timeout:10))
    }
    private func capture(_ name:String) {
        let item=XCTAttachment(screenshot:app.screenshot());item.name=name;item.lifetime = .keepAlways;add(item)
    }
}
