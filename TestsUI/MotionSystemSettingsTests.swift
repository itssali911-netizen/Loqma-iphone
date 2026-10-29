import XCTest

/// The caller must create a fresh, disposable Simulator for this scenario.
/// This changes the actual iOS setting through visible Settings controls only.
/// It never writes app defaults, a private preference, or a Health permission.
final class MotionSystemSettingsTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if !targetEnvironment(simulator)
        throw XCTSkip("System motion settings are tested only on a caller-created disposable Simulator.")
        #endif
    }

    func testEnableSystemReduceMotion() throws {
        try Self.enableReduceMotion()
    }

    /// Also used by the reduced-motion interaction case before launching Luqma.
    /// Leaves Reduce Motion enabled on this disposable device for later checks.
    static func enableReduceMotion() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Do not change motion preferences on a physical or personal iPhone.")
        #else
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        settings.launch()
        defer { settings.terminate() }
        guard settings.wait(for: .runningForeground, timeout: 20) else {
            XCTFail("The genuine iOS Settings application must be in the foreground.")
            throw SettingsNavigationError.settingsUnavailable
        }

        // An earlier enable-only case may already have left Settings on this
        // page. Reuse its visible switch without changing an enabled value.
        if !settings.switches.matching(NSPredicate(format: "label == %@ OR identifier == %@", "Reduce Motion", "Reduce Motion")).firstMatch.exists {
            if !settings.navigationBars["Accessibility"].exists {
                try tapSettingsRow("Accessibility", in: settings)
            }
            try tapSettingsRow("Motion", in: settings)
        }

        let reduceMotion = settings.switches.matching(NSPredicate(format: "label == %@ OR identifier == %@", "Reduce Motion", "Reduce Motion")).firstMatch
        guard reduceMotion.waitForExistence(timeout: 10) else {
            XCTFail("Accessibility > Motion must expose the actual Reduce Motion switch.\n" + settings.debugDescription)
            throw SettingsNavigationError.reduceMotionUnavailable
        }
        XCTAssertTrue(reduceMotion.isEnabled, "The real system switch must be enabled for interaction.")
        if reduceMotion.value as? String != "1" {
            // SwiftUI Settings can expose a full-row switch around its native
            // switch. Tap the native child when present, as a real user would.
            let nativeSwitch = reduceMotion.switches.firstMatch
            let control = nativeSwitch.exists ? nativeSwitch : reduceMotion
            XCTAssertTrue(control.isHittable, "The real Reduce Motion toggle must be visible.")
            control.tap()
        }
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND value == %@", "1"), object: reduceMotion)
        guard XCTWaiter.wait(for: [enabled], timeout: 10) == .completed else {
            XCTFail("iOS Settings must confirm Reduce Motion is actually enabled.\n" + settings.debugDescription)
            throw SettingsNavigationError.reduceMotionNotEnabled
        }
        XCTAssertEqual(reduceMotion.value as? String, "1")
        XCTContext.runActivity(named: "Genuine iOS Settings Reduce Motion enabled") { activity in
            let evidence = XCTAttachment(screenshot: settings.screenshot())
            evidence.name = "motion-system-settings-reduce-motion-enabled"
            evidence.lifetime = .keepAlways
            activity.add(evidence)
        }
        #endif
    }

    private enum SettingsNavigationError: Error {
        case settingsUnavailable, rowUnavailable(String), reduceMotionUnavailable, reduceMotionNotEnabled
    }

    private static func tapSettingsRow(_ title: String, in settings: XCUIApplication) throws {
        // Six bounded scroll gestures per page. Navigation uses exact visible
        // English row labels, never undocumented Settings URL schemes.
        for attempt in 0...6 {
            let named = NSPredicate(format: "label == %@ OR identifier == %@", title, title)
            let candidates = [settings.staticTexts.matching(named).firstMatch,
                              settings.cells.containing(.staticText, identifier: title).firstMatch,
                              settings.buttons.matching(named).firstMatch]
            if let row = candidates.first(where: { $0.exists && $0.isHittable }) {
                row.tap()
                return
            }
            guard attempt < 6 else { break }
            let containers = settings.collectionViews.allElementsBoundByIndex
                + settings.tables.allElementsBoundByIndex
                + settings.scrollViews.allElementsBoundByIndex
            guard let scroll = containers.first(where: { $0.exists && $0.isHittable && !$0.frame.isEmpty }) else {
                break
            }
            if let row = candidates.first(where: { $0.exists && !$0.frame.isEmpty }),
               row.frame.maxY < settings.navigationBars.firstMatch.frame.maxY {
                scroll.swipeDown()
            } else {
                scroll.swipeUp()
            }
        }
        XCTFail("The genuine Settings row must be reachable within six scroll gestures: " + title + "\n" + settings.debugDescription)
        throw SettingsNavigationError.rowUnavailable(title)
    }
}
