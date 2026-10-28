import XCTest

/// Performance infrastructure, separate from the functional regression suite.
/// Run Release/-O with DEBUG explicitly enabled only for the isolated fixture.
/// These are real production views and controls, not screenshot preview routes.
/// No result from this Simulator suite verifies physical-device 60/120 Hz.
final class LuqmaPerformanceTests: XCTestCase {
    private let app = XCUIApplication()
    private let fixtureIdentity = "v1|entries=5000|days=7|today=800|seed=20261021"

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["-loqma-ui-test-en", "-AppleLanguages", "(en)",
                               "-AppleLocale", "en_US", "-loqma-performance-fixture",
                               "-loqma-performance-entries", "5000"]
    }

    override func tearDownWithError() throws {
        if let testRun, testRun.failureCount > 0, app.state == .runningForeground {
            print("LUQMA_PERFORMANCE_FAILED_HIERARCHY\n" + app.debugDescription)
            let evidence = XCTAttachment(screenshot: app.screenshot())
            evidence.name = "Actual performance-scenario failure"
            evidence.lifetime = .keepAlways
            add(evidence)
        }
        app.terminate()
    }

    func testResponsiveProcessLaunch() {
        // Launch once separately to validate the fixture and warm only the OS's
        // caches. Every measured sample launches a terminated process. This is
        // not a reboot-cold physical-device or empty-file-cache measurement.
        launchFixture()
        app.terminate()
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true), XCTClockMetric()],
                options: options(iterations: 5)) {
            app.terminate()
            startMeasuring()
            app.launch()
            assertFixture()
            stopMeasuring()
        }
    }

    func testWarmForegroundResume() {
        launchFixture()
        measure(metrics: resourceMetrics(), options: options()) {
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
            startMeasuring()
            app.activate()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            XCTAssertTrue(app.buttons["nav.today"].waitForExistence(timeout: 10))
            stopMeasuring()
        }
    }

    func testTabRoundTrip() {
        launchFixture()
        measure(metrics: resourceMetrics(), options: options()) {
            startMeasuring()
            for identifier in ["nav.kitchen", "nav.progress", "nav.settings", "nav.today"] {
                let button = app.buttons[identifier]
                XCTAssertTrue(button.waitForExistence(timeout: 10))
                XCTAssertTrue(button.isHittable)
                button.tap()
                XCTAssertTrue(button.isSelected, "A tap must actually select the requested tab")
            }
            stopMeasuring()
        }
    }

    func testHomeFoodLoggingRoundTrip() {
        launchFixture()
        measure(metrics: resourceMetrics(), options: options()) {
            startMeasuring()
            tap("nav.add")
            XCTAssertTrue(app.textFields["search.query"].waitForExistence(timeout: 10))
            tap("search.close")
            XCTAssertTrue(app.buttons["nav.today"].waitForExistence(timeout: 10))
            stopMeasuring()
        }
    }

    func testFoodSearchToQuantity() {
        measure(metrics: resourceMetrics(), options: options()) {
            launchFixture()
            tap("nav.add")
            tap("search.filter.3")
            let product = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Luqma Performance Oats")).firstMatch
            reveal(product)
            startMeasuring()
            product.tap()
            // The approved design opens quantity in its own real sheet. This
            // scenario includes that explicit tap; do not compare its timing
            // directly with the older inline-amount presentation.
            let quantity = app.buttons["portion.quantity"]
            XCTAssertTrue(quantity.waitForExistence(timeout: 10))
            quantity.tap()
            XCTAssertTrue(app.textFields["portion.amount"].waitForExistence(timeout: 10))
            XCTAssertEqual(app.textFields["portion.amount"].value as? String, "1")
            stopMeasuring()
        }
    }

    func testHomeToSevenDayCalorieDetails() {
        measure(metrics: resourceMetrics(), options: options()) {
            launchFixture()
            let details = app.buttons["diary.calorieDetails"]
            reveal(details)
            startMeasuring()
            details.tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "diary.calorieHistory").firstMatch.waitForExistence(timeout: 10))
            stopMeasuring()
        }
    }

    func testHomeFitnessProfileAssessmentEntry() {
        measure(metrics: resourceMetrics(), options: options()) {
            launchFixture()
            startMeasuring()
            openProfile()
            let edit = app.buttons["fitness.edit"]
            reveal(edit)
            edit.tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "assessment.form").firstMatch.waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["assessment.next"].waitForExistence(timeout: 10))
            stopMeasuring()
        }
    }

    func testFitnessProfileToPersonalizedPlan() {
        measure(metrics: resourceMetrics(), options: options()) {
            launchFixture()
            openProfile()
            let review = app.buttons["fitness.reviewPlan"]
            reveal(review)
            startMeasuring()
            review.tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "fitness.review").firstMatch.waitForExistence(timeout: 10))
            XCTAssertTrue(app.staticTexts["fitness.plan.calories"].waitForExistence(timeout: 10))
            stopMeasuring()
        }
    }

    func testExpandedDiaryScroll() {
        var metrics = resourceMetrics()
        metrics.append(XCTOSSignpostMetric.scrollingAndDecelerationMetric)
        measure(metrics: metrics, options: options()) {
            launchFixture()
            let details = app.descendants(matching: .any).matching(identifier: "diary.details.breakfast").firstMatch
            reveal(details)
            let chevron = details.images["collapsed"]
            if chevron.exists {
                XCTAssertTrue(chevron.isHittable)
                chevron.tap()
            } else {
                details.tap()
            }
            // The disclosure owns an AX container; its row buttons retain
            // independent actions. Require the real expanded state and actual
            // stored fixture food before measuring the same scrolling block.
            let expandedDetails = app.descendants(matching: .any).matching(identifier: "diary.details.breakfast").firstMatch
            XCTAssertTrue(expandedDetails.images["expanded"].waitForExistence(timeout: 5), "The actual breakfast disclosure must be expanded before measuring")
            let actualEntry = app.buttons.matching(NSPredicate(format: "label == %@", "Luqma Performance Oats")).firstMatch
            XCTAssertTrue(actualEntry.waitForExistence(timeout: 5), "The expanded meal must expose real persisted diary rows before measuring")
            let scroll = app.scrollViews.firstMatch
            XCTAssertTrue(scroll.waitForExistence(timeout: 5))
            startMeasuring()
            // Public XCUITest gestures with identical velocities/counts on both
            // revisions; real hitch/scroll metrics, never a synthetic FPS timer.
            scroll.swipeUp(velocity: .fast)
            scroll.swipeUp(velocity: .fast)
            scroll.swipeDown(velocity: .fast)
            scroll.swipeDown(velocity: .fast)
            stopMeasuring()
        }
    }

    private func options(iterations: Int = 3) -> XCTMeasureOptions {
        let result = XCTMeasureOptions()
        result.iterationCount = iterations
        result.invocationOptions = [.manuallyStart, .manuallyStop]
        return result
    }

    private func resourceMetrics() -> [XCTMetric] {
        var result: [XCTMetric] = [XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)]
        if #available(iOS 26.0, *) { result.append(XCTHitchMetric(application: app)) }
        return result
    }

    private func launchFixture() {
        app.terminate()
        app.launch()
        assertFixture()
    }

    private func assertFixture() {
        XCTAssertTrue(app.buttons["nav.today"].waitForExistence(timeout: 20))
        let marker = app.descendants(matching: .any).matching(identifier: "performance.fixture.ready").firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 5), "The performance fixture must exist; an empty diary is not an acceptable benchmark")
        XCTAssertEqual(marker.value as? String, fixtureIdentity)
    }

    private func openProfile() {
        tap("nav.settings")
        let link = app.buttons["settings.fitness"]
        reveal(link)
        link.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "fitness.profile").firstMatch.waitForExistence(timeout: 10))
    }

    private func tap(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 10), identifier, file: file, line: line)
        XCTAssertTrue(button.isHittable, identifier, file: file, line: line)
        button.tap()
    }

    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<8 {
            if element.exists, element.isHittable {
                let frame = element.frame
                let window = app.windows.firstMatch.frame
                if !frame.isEmpty, frame.minY >= window.minY + 80, frame.maxY <= window.maxY - 100 { return }
            }
            let scroll = app.scrollViews.firstMatch
            XCTAssertTrue(scroll.exists, "Expected an actual scroll container", file: file, line: line)
            scroll.swipeUp(velocity: .slow)
        }
        XCTFail("Required real control could not be revealed", file: file, line: line)
    }
}
