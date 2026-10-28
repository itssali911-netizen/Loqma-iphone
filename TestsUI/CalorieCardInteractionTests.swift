import XCTest

/// Real production diary controls, run only on a caller-created, empty Simulator.
/// No calorie-card fixture is injected into the application and no Health data
/// or account is accessed. Component-harness captures are produced separately.
final class CalorieCardInteractionTests: XCTestCase {
    private let app = XCUIApplication()
    private let foodName = "Calorie Card QA Oats"

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        throw XCTSkip("The calorie-card review requires a new disposable Simulator, not a personal iPhone diary.")
        #endif
        launchEnglish()
    }

    override func tearDownWithError() throws {
        if let testRun, testRun.failureCount > 0 {
            capture("calorie-card-home-failed-" + name.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: "-"))
        }
        app.terminate()
    }

    func testARealHomeCardAndDiaryMutation() throws {
        assertCard(consumed: 0, protein: 0, carbs: 0, fat: 0)
        let target = try XCTUnwrap(number("diary.summary.target"))
        XCTAssertGreaterThan(target, 0)
        capture("calorie-card-home-en-zero")

        app.buttons["nav.add"].tap()
        let personal = app.buttons["search.filter.3"]
        XCTAssertTrue(personal.waitForExistence(timeout: 15))
        personal.tap()
        XCTAssertTrue(personal.isSelected)
        let manual = app.buttons["search.manual"]
        reveal(manual)
        manual.tap()
        replace(app.textFields["portion.name"], with: foodName)
        app.buttons["portion.quantity"].tap()
        XCTAssertTrue(app.buttons["portion.unit.serving"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["portion.unit.serving"].isSelected)
        XCTAssertEqual(app.textFields["portion.amount"].value as? String, "1")
        app.buttons["portion.quantity.confirm"].tap()
        for (identifier, value) in [("portion.kcal", "100"), ("portion.protein", "10"),
                                    ("portion.carbs", "15"), ("portion.fat", "0")] {
            replace(app.textFields[identifier], with: value)
        }
        let save = app.buttons["portion.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.buttons["nav.today"].waitForExistence(timeout: 15))
        assertCard(consumed: 100, protein: 10, carbs: 15, fat: 0)
        assertNumber("diary.summary.target", equals: target)
        assertNumber("diary.summary.remaining", equals: target - 100)
        capture("calorie-card-home-en-added")

        // Preserve the existing seven-day route while changing only its card.
        let history = app.buttons["diary.calorieDetails"]
        reveal(history)
        history.tap()
        XCTAssertTrue(element("diary.calorieHistory").waitForExistence(timeout: 10))
        XCTAssertEqual(numeric(element("calorie.consumed").label), 100)
        app.buttons["calorie.back"].tap()

        openEntry()
        replace(app.textFields["entry.amount"], with: "2")
        let entrySave = app.buttons["entry.save"]
        XCTAssertTrue(entrySave.isEnabled)
        entrySave.tap()
        assertCard(consumed: 200, protein: 20, carbs: 30, fat: 0)
        assertNumber("diary.summary.remaining", equals: target - 200)
        capture("calorie-card-home-en-edited")

        // A cold relaunch must load the saved diary rather than a display-only
        // state. Both the card and the unchanged entry editor must agree.
        app.terminate()
        launchEnglish()
        assertCard(consumed: 200, protein: 20, carbs: 30, fat: 0)
        openEntry()
        XCTAssertEqual(app.textFields["entry.amount"].value as? String, "2")
        let remove = app.buttons["entry.delete"]
        reveal(remove)
        remove.tap()
        let confirm = app.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        assertCard(consumed: 0, protein: 0, carbs: 0, fat: 0)
        assertNumber("diary.summary.remaining", equals: target)

        app.terminate()
        launchEnglish()
        assertCard(consumed: 0, protein: 0, carbs: 0, fat: 0)
        XCTAssertFalse(app.buttons[foodName].exists)
        capture("calorie-card-home-en-after-delete")
    }

    func testBArabicHome() throws {
        app.buttons["nav.settings"].tap()
        let language = element("settings.language")
        reveal(language)
        language.tap()
        let arabic = app.buttons["language.option.ar"]
        XCTAssertTrue(arabic.waitForExistence(timeout: 10))
        arabic.tap()
        XCTAssertTrue(arabic.isSelected)
        app.buttons["language.back"].tap()
        app.buttons["nav.today"].tap()
        let title = app.buttons["diary.calorieDetails"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(title.label.contains("السعرات"))
        assertCard(consumed: 0, protein: 0, carbs: 0, fat: 0)
        assertWesternDigits()
        capture("calorie-card-home-ar-zero")
    }

    func testCEnglishHome() throws {
        let title = app.buttons["diary.calorieDetails"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertFalse(title.label.isEmpty)
        XCTAssertFalse(title.label.contains("السعرات"))
        assertCard(consumed: 0, protein: 0, carbs: 0, fat: 0)
        assertWesternDigits()
        capture("calorie-card-home-en-overview")
    }

    func testDGoalEditorUpdatesCard() throws {
        let original = try XCTUnwrap(number("diary.summary.target"))
        XCTAssertGreaterThan(original, 0)
        setGoalCalories(1500)
        assertNumber("diary.summary.target", equals: 1500)
        assertNumber("diary.summary.remaining", equals: 1500)
        assertCard(consumed: 0, protein: 0, carbs: 0, fat: 0)
        capture("calorie-card-home-en-saved-target")
        app.terminate()
        launchEnglish()
        assertNumber("diary.summary.target", equals: 1500)
        setGoalCalories(original)
        assertNumber("diary.summary.target", equals: original)
        assertNumber("diary.summary.remaining", equals: original)
    }

    func testEComponentBoundaryStates() throws {
        app.terminate()
        let host = XCUIApplication(bundleIdentifier: "app.luqma.calorie-review")
        defer { host.terminate() }
        // Explicit synthetic inputs in a separate host, never in the user's app.
        for (state, consumed, target, remaining, progress) in [
            ("zero", "0", "1500", "1500", "0%"),
            ("partial", "600", "1500", "900", "40%"),
            ("met", "1500", "1500", "0", "100%"),
            ("exceeded", "1800", "1500", "300", "100%"),
            ("missing", "600", "—", "—", "—"),
            ("loading", "—", "—", "—", "—"),
            ("long", "50000", "100000", "50000", "50%")
        ] {
            host.launchArguments = ["--state",state,"--width","390","--language","ar","--dynamic-type","large"]
            host.launch()
            for (identifier, expected) in [("diary.summary.consumed",consumed), ("diary.summary.target",target), ("diary.summary.remaining",remaining)] {
                let node = host.descendants(matching:.any).matching(identifier:identifier).firstMatch
                XCTAssertTrue(node.waitForExistence(timeout:10), state+" "+identifier)
                XCTAssertEqual(node.label, expected, state+" "+identifier)
            }
            let bar = host.descendants(matching:.any).matching(identifier:"diary.summary.progress").firstMatch
            XCTAssertTrue(bar.exists)
            XCTAssertEqual(bar.value as? String, progress, state)
            if state == "exceeded" {
                XCTAssertTrue(host.staticTexts["متجاوز بـ"].exists)
            }
            if state == "zero" || state == "partial" || state == "exceeded" {
                let image = XCTAttachment(screenshot:host.screenshot())
                image.name = "calorie-card-component-tested-"+state;image.lifetime = .keepAlways;add(image)
            }
            host.terminate()
        }
    }

    func testFExtremeValuesRespectAccessibilityWidth() throws {
        app.terminate()
        let host = XCUIApplication(bundleIdentifier: "app.luqma.calorie-review")
        defer { host.terminate() }
        // Stress the exact production component in the separate native host.
        // These synthetic quantities never enter the production diary.
        let cases: [(language: String, width: CGFloat)] = [("ar", 320), ("ar", 390), ("en", 320)]
        for testCase in cases {
            host.launchArguments = ["--state", "extreme", "--width", String(Int(testCase.width)),
                                    "--language", testCase.language, "--dynamic-type", "accessibility3"]
            host.launch()
            let fixture = testCase.language + "-" + String(Int(testCase.width)) + "-ax3"
            let screen = host.frame
            XCTAssertGreaterThanOrEqual(screen.width, testCase.width, fixture)
            // The host centers a canvas padded16pt; the actual card adds13pt.
            // Check scalar text against its content bounds, not just the card's
            // outer background, which can conceal a child overflowing it.
            let left = screen.minX + (screen.width - testCase.width) / 2 + 16 + 13
            let right = screen.minX + (screen.width + testCase.width) / 2 - 16 - 13
            for (identifier, expected) in [("diary.summary.consumed", "500000000"),
                                           ("diary.summary.target", "1000000000"),
                                           ("diary.summary.remaining", "500000000")] {
                let node = host.descendants(matching: .any).matching(identifier: identifier).firstMatch
                XCTAssertTrue(node.waitForExistence(timeout: 10), fixture + " " + identifier)
                XCTAssertEqual(node.label, expected, "The complete quantity must remain accessible: " + fixture + " " + identifier)
                let frame = node.frame
                XCTAssertGreaterThan(frame.width, 0, fixture + " " + identifier)
                XCTAssertGreaterThan(frame.height, 0, fixture + " " + identifier)
                XCTAssertGreaterThanOrEqual(frame.minX, left - 1, "Text must stay inside the card content: " + fixture + " " + identifier)
                XCTAssertLessThanOrEqual(frame.maxX, right + 1, "Text must stay inside the card content: " + fixture + " " + identifier)
            }
            let bar = host.descendants(matching: .any).matching(identifier: "diary.summary.progress").firstMatch
            XCTAssertTrue(bar.waitForExistence(timeout: 10), fixture)
            XCTAssertEqual(bar.value as? String, "50%", fixture)
            let image = XCTAttachment(screenshot: host.screenshot())
            image.name = "calorie-card-component-tested-extreme-" + fixture
            image.lifetime = .keepAlways
            add(image)
            host.terminate()
        }
    }

    private func launchEnglish() {
        app.launchArguments = ["-loqma-ui-test-en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["nav.today"].waitForExistence(timeout: 25))
        XCTAssertTrue(element("diary.calorieGoal").waitForExistence(timeout: 10))
    }

    func testGFourMealCardsKeepTheirRealAddRoutes() throws {
        for (meal, label) in [("breakfast", "Breakfast"), ("lunch", "Lunch"),
                              ("dinner", "Dinner"), ("snack", "Snack")] {
            let card = app.buttons["diary.meal." + meal]
            reveal(card)
            XCTAssertTrue(card.isHittable)
            capture("calorie-card-home-meal-" + meal)
            card.tap()
            let personal = app.buttons["search.filter.3"]
            XCTAssertTrue(personal.waitForExistence(timeout: 10))
            personal.tap()
            let manual = app.buttons["search.manual"]
            reveal(manual)
            manual.tap()
            let selectedMeal = app.buttons["portion.meal"]
            XCTAssertTrue(selectedMeal.waitForExistence(timeout: 10))
            XCTAssertEqual(selectedMeal.value as? String, label,
                           "The category card must open the correct real meal")
            let back = app.buttons["portion.back"]
            back.tap()
            let close = app.buttons["search.close"]
            XCTAssertTrue(close.waitForExistence(timeout: 10))
            close.tap()
            XCTAssertTrue(app.buttons["nav.today"].waitForExistence(timeout: 10))
        }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func numeric(_ value: String) -> Double? {
        let text = value.replacingOccurrences(of: ",", with: "")
        guard let expression = try? NSRegularExpression(pattern: "[-+]?[0-9]+(?:\\.[0-9]+)?"),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        return Double(text[range])
    }

    private func number(_ identifier: String) -> Double? {
        let node = element(identifier)
        guard node.exists else { return nil }
        // StaticText may expose an empty AX value even when its label is the
        // complete number. Prefer a numeric value, then the actual text label.
        return numeric(node.value as? String ?? "") ?? numeric(node.label)
    }

    private func assertNumber(_ identifier: String, equals expected: Double,
                              file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard let actual = self.number(identifier) else { return false }
            return abs(actual - expected) < 0.01
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed,
                       "The native card must update from the saved diary: " + identifier, file: file, line: line)
        let node = element(identifier)
        reveal(node, file: file, line: line)
        XCTAssertEqual(number(identifier) ?? .nan, expected, accuracy: 0.01, file: file, line: line)
    }

    private func assertCard(consumed: Double, protein: Double, carbs: Double, fat: Double,
                            file: StaticString = #filePath, line: UInt = #line) {
        for (identifier, expected) in [("diary.summary.consumed", consumed),
                                       ("diary.summary.protein.consumed", protein),
                                       ("diary.summary.carbs.consumed", carbs),
                                       ("diary.summary.fat.consumed", fat)] {
            assertNumber(identifier, equals: expected, file: file, line: line)
        }
        if let target = number("diary.summary.target"), target > 0 {
            let percentage = (min(1, max(0, consumed / target)) * 100).rounded()
            assertNumber("diary.summary.progress", equals: percentage, file: file, line: line)
        }
        // SwiftUI exposes the history button as one accessible element; its title
        // is the button label, rather than a separately reachable child Text.
        reveal(app.buttons["diary.calorieDetails"], file: file, line: line)
    }

    private func assertWesternDigits(file: StaticString = #filePath, line: UInt = #line) {
        for identifier in ["diary.summary.consumed", "diary.summary.target", "diary.summary.remaining",
                           "diary.summary.protein.consumed", "diary.summary.carbs.consumed", "diary.summary.fat.consumed"] {
            let node = element(identifier)
            XCTAssertTrue(node.exists, file: file, line: line)
            let copy = (node.value as? String ?? "") + node.label
            XCTAssertFalse(copy.unicodeScalars.contains { (0x0660...0x0669).contains($0.value) || (0x06F0...0x06F9).contains($0.value) },
                           "Arabic interface numbers must remain 0...9", file: file, line: line)
        }
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openEntry() {
        let details = element("diary.details.breakfast")
        reveal(details)
        let collapsed = details.images["collapsed"]
        if collapsed.exists { reveal(collapsed); collapsed.tap() }
        let entry = app.buttons[foodName]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        reveal(entry)
        entry.tap()
        XCTAssertTrue(app.textFields["entry.amount"].waitForExistence(timeout: 10))
    }

    private func setGoalCalories(_ value: Double) {
        let goals = app.buttons["diary.goals"]
        reveal(goals)
        goals.tap()
        let edit = app.buttons["goals.editCalories"]
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        edit.tap()
        let direct = app.textFields["goals.calories"]
        let field = direct.waitForExistence(timeout: 3) ? direct
            : element("goals.calories").descendants(matching: .textField).firstMatch
        replace(field, with: String(Int(value)))
        let done = app.buttons.matching(identifier: "navigation.back")
            .matching(NSPredicate(format: "label == %@", "Done")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        let parentReady = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.buttons["goals.editCalories"].isHittable && self.app.buttons["goals.save"].isHittable
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [parentReady], timeout: 10), .completed)
        let save = app.buttons["goals.save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(app.buttons["diary.goals"].waitForExistence(timeout: 10))
    }

    private func replace(_ field: XCUIElement, with text: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        if field.identifier.hasPrefix("portion.") {
            focusPortion(field)
        } else {
            reveal(field)
            field.tap()
        }
        let previous = field.value as? String ?? ""
        if !previous.isEmpty {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count))
        }
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text, "Replace the actual field before saving")
    }

    private func visibleArea(_ content: XCUIElement) -> CGRect {
        let viewport = content.frame.intersection(app.frame)
        var top = viewport.minY + 8, bottom = viewport.maxY - 8
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists { bottom = min(bottom, keyboard.frame.minY - 8) }
        for identifier in ["diary.search", "navigation.back"] {
            let node = app.buttons.matching(identifier: identifier).allElementsBoundByIndex.first { $0.isHittable }
            if let node, node.frame.maxY < viewport.midY { top = max(top, node.frame.maxY + 8) }
        }
        for identifier in ["nav.today", "portion.save"] {
            let node = app.buttons.matching(identifier: identifier).allElementsBoundByIndex.first { $0.isHittable }
            if let node, node.frame.minY > viewport.midY { bottom = min(bottom, node.frame.minY - 8) }
        }
        return CGRect(x: viewport.minX, y: top, width: viewport.width, height: max(0, bottom - top))
    }

    private func fullyVisible(_ node: XCUIElement, in area: CGRect) -> Bool {
        node.exists && node.isHittable && !node.frame.isEmpty && area.minY <= node.frame.minY && node.frame.maxY <= area.maxY
    }

    private func reveal(_ node: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<12 {
            if node.exists && node.isHittable { return }
            let content = app.collectionViews.allElementsBoundByIndex.first { $0.isHittable }
                ?? app.scrollViews.allElementsBoundByIndex.first { $0.isHittable }
            guard let content else { break }
            drag(content, toward: node)
        }
        XCTAssertTrue(node.exists && node.isHittable, "Production control must be reachable: " + node.identifier, file: file, line: line)
    }

    private func drag(_ content: XCUIElement, toward node: XCUIElement) {
        let area = visibleArea(content)
        guard area.height > 60 else { return }
        let up = !node.exists || node.frame.isEmpty || node.frame.midY > area.midY
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let x = area.minX + 8 - app.frame.minX
        let start = up ? area.maxY - 12 : area.minY + 12
        let end = up ? area.minY + 12 : area.maxY - 12
        origin.withOffset(CGVector(dx: x, dy: start - app.frame.minY)).press(forDuration: 0.05,
            thenDragTo: origin.withOffset(CGVector(dx: x, dy: end - app.frame.minY)))
    }

    private func focusPortion(_ field: XCUIElement) {
        let content = app.scrollViews.containing(.textField, identifier: field.identifier).firstMatch
        XCTAssertTrue(content.exists)
        for _ in 0..<3 {
            for _ in 0..<12 {
                if fullyVisible(field, in: visibleArea(content)) { break }
                drag(content, toward: field)
            }
            XCTAssertTrue(fullyVisible(field, in: visibleArea(content)), "Portion field must clear the keyboard and pinned action")
            field.tap()
            for _ in 0..<12 {
                if fullyVisible(field, in: visibleArea(content)) { break }
                drag(content, toward: field)
            }
            if app.keyboards.firstMatch.exists && fullyVisible(field, in: visibleArea(content)) { return }
        }
        XCTFail("Portion field must stay visible and focused when its keyboard opens")
    }
}
