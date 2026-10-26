import Foundation
import XCTest
@testable import LuqmaCore

final class ReminderTests: XCTestCase {
    private func persistedObject(_ preferences: ReminderPreferences = .defaults) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(preferences)) as? [String: Any])
    }

    private func decode(_ object: [String: Any]) throws -> ReminderPreferences {
        try JSONDecoder().decode(ReminderPreferences.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testFirstInstallDefaultsAreCompleteAndAllDisabled() throws {
        let defaults = try ReminderPreferences.defaults.validated()
        XCTAssertEqual(defaults.version, ReminderPreferences.currentVersion)
        XCTAssertEqual(defaults.reminders.map(\.kind), ReminderKind.allCases)
        XCTAssertTrue(defaults.reminders.allSatisfy { !$0.isEnabled })
        XCTAssertEqual(defaults.reminder(for: .breakfast)?.hour, 8)
        XCTAssertEqual(defaults.reminder(for: .lunch)?.hour, 13)
        XCTAssertEqual(defaults.reminder(for: .dinner)?.hour, 19)
        XCTAssertEqual(defaults.reminder(for: .snack)?.hour, 16)
        XCTAssertEqual(defaults.reminder(for: .nutritionReview)?.hour, 21)
    }

    func testPersistedRoundTripPreservesEveryEnabledStateAndChosenTime() throws {
        var preferences = ReminderPreferences.defaults
        for index in preferences.reminders.indices {
            preferences.reminders[index].isEnabled = index % 2 == 0
            preferences.reminders[index].hour = index * 4
            preferences.reminders[index].minute = index * 11
        }
        let data = try JSONEncoder().encode(preferences)
        XCTAssertEqual(try JSONDecoder().decode(ReminderPreferences.self, from: data), preferences)
        let object = try persistedObject(preferences)
        XCTAssertEqual(Set(object.keys), ["version", "reminders"])
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("authorization"))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("permission"))
    }

    func testIndependentChangesDoNotTurnOnOrRescheduleOtherReminders() throws {
        let defaults = ReminderPreferences.defaults
        var edited = defaults
        let index = try XCTUnwrap(edited.reminders.firstIndex { $0.kind == .lunch })
        edited.reminders[index].isEnabled = true
        edited.reminders[index].hour = 14
        edited.reminders[index].minute = 35
        let reloaded = try decode(persistedObject(edited))
        XCTAssertEqual(reloaded.reminder(for: .lunch), DailyReminder(kind: .lunch, hour: 14, minute: 35, isEnabled: true))
        for kind in ReminderKind.allCases where kind != .lunch {
            XCTAssertEqual(reloaded.reminder(for: kind), defaults.reminder(for: kind))
        }
        edited.reminders[index].isEnabled = false
        XCTAssertEqual(edited.reminders[index].hour, 14)
        XCTAssertEqual(edited.reminders[index].minute, 35)
        XCTAssertTrue(try decode(persistedObject(edited)).reminders.allSatisfy { !$0.isEnabled })
    }

    func testMidnightAndLastMinuteAreValidWithoutDateOrTimeZoneConversions() throws {
        for time in [(0, 0), (23, 59)] {
            var preferences = ReminderPreferences.defaults
            for index in preferences.reminders.indices {
                preferences.reminders[index].hour = time.0
                preferences.reminders[index].minute = time.1
                preferences.reminders[index].isEnabled = true
            }
            XCTAssertEqual(try decode(persistedObject(preferences)), preferences)
        }
    }

    func testInvalidTimesAreRejectedBeforePersistingOrScheduling() throws {
        for time in [(-1, 0), (24, 0), (0, -1), (0, 60), (Int.max, 0)] {
            var preferences = ReminderPreferences.defaults
            preferences.reminders[0].hour = time.0
            preferences.reminders[0].minute = time.1
            XCTAssertThrowsError(try preferences.validated()) {
                XCTAssertEqual($0 as? ReminderPreferencesError, .invalidTime(.breakfast))
            }
            XCTAssertThrowsError(try JSONEncoder().encode(preferences))

            var object = try persistedObject()
            var items = try XCTUnwrap(object["reminders"] as? [[String: Any]])
            items[0]["hour"] = time.0
            items[0]["minute"] = time.1
            object["reminders"] = items
            XCTAssertThrowsError(try decode(object))
        }
    }

    func testUnsupportedVersionRejectsStoredPreferencesWithoutReplacingThem() throws {
        for version in [0, -1, ReminderPreferences.currentVersion + 1] {
            var preferences = ReminderPreferences.defaults
            preferences.version = version
            preferences.reminders[0].isEnabled = true
            XCTAssertThrowsError(try preferences.validated()) {
                XCTAssertEqual($0 as? ReminderPreferencesError, .unsupportedVersion(version))
            }
            var object = try persistedObject()
            object["version"] = version
            XCTAssertThrowsError(try decode(object))
            XCTAssertTrue(preferences.reminders[0].isEnabled)
        }
    }

    func testMissingAndDuplicateKindsAreRejectedWithoutInventingDefaults() throws {
        var missing = ReminderPreferences.defaults
        missing.reminders.removeAll { $0.kind == .dinner }
        XCTAssertThrowsError(try missing.validated()) {
            XCTAssertEqual($0 as? ReminderPreferencesError, .missingKind(.dinner))
        }
        var duplicate = ReminderPreferences.defaults
        duplicate.reminders.append(DailyReminder(kind: .lunch, hour: 12, minute: 0, isEnabled: true))
        XCTAssertThrowsError(try duplicate.validated()) {
            XCTAssertEqual($0 as? ReminderPreferencesError, .duplicateKind(.lunch))
        }
        for items in [missing.reminders, duplicate.reminders] {
            var object = try persistedObject()
            object["reminders"] = try items.map { item -> [String: Any] in
                try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
            }
            XCTAssertThrowsError(try decode(object))
        }
    }

    func testMissingFieldsAndUnknownKindsDoNotSilentlyResetAnEnabledReminder() throws {
        var preferences = ReminderPreferences.defaults
        preferences.reminders[0].isEnabled = true
        let original = try persistedObject(preferences)
        for field in ["kind", "hour", "minute", "isEnabled"] {
            var object = original
            var items = try XCTUnwrap(object["reminders"] as? [[String: Any]])
            items[0].removeValue(forKey: field)
            object["reminders"] = items
            XCTAssertThrowsError(try decode(object))
        }
        for field in ["version", "reminders"] {
            var object = original
            object.removeValue(forKey: field)
            XCTAssertThrowsError(try decode(object))
        }
        var object = original
        var items = try XCTUnwrap(object["reminders"] as? [[String: Any]])
        items[0]["kind"] = "water"
        object["reminders"] = items
        XCTAssertThrowsError(try decode(object))
    }

    func testValidationCanonicalizesOrderWithoutChangingEnabledStatesOrTimes() throws {
        var preferences = ReminderPreferences.defaults
        preferences.reminders[1] = DailyReminder(kind: .lunch, hour: 12, minute: 17, isEnabled: true)
        let expected = preferences
        preferences.reminders.reverse()
        XCTAssertEqual(try preferences.validated(), expected)
        XCTAssertEqual(try decode(persistedObject(preferences)), expected)
    }

    func testNotificationIdentifiersAreUniqueAndTapParsingRequiresAnExactKnownID() {
        let identifiers = ReminderKind.allCases.map(\.notificationIdentifier)
        XCTAssertEqual(Set(identifiers).count, ReminderKind.allCases.count)
        for kind in ReminderKind.allCases {
            XCTAssertEqual(ReminderKind.fromNotificationIdentifier(kind.notificationIdentifier), kind)
            XCTAssertNil(ReminderKind.fromNotificationIdentifier(kind.rawValue))
            XCTAssertNil(ReminderKind.fromNotificationIdentifier(kind.notificationIdentifier + ".extra"))
            XCTAssertNil(ReminderKind.fromNotificationIdentifier(" " + kind.notificationIdentifier))
            XCTAssertNil(ReminderKind.fromNotificationIdentifier(kind.notificationIdentifier.uppercased()))
        }
        for invalid in ["", "app.luqma.reminder.", "app.luqma.reminder.water", "other.app.breakfast", "app.luqma.reminder.%62reakfast"] {
            XCTAssertNil(ReminderKind.fromNotificationIdentifier(invalid))
        }
    }

    func testEveryMealRoutesToTheExistingMealAndReviewHasNoInventedMeal() {
        XCTAssertEqual(ReminderKind.breakfast.meal, .breakfast)
        XCTAssertEqual(ReminderKind.lunch.meal, .lunch)
        XCTAssertEqual(ReminderKind.dinner.meal, .dinner)
        XCTAssertEqual(ReminderKind.snack.meal, .snack)
        XCTAssertNil(ReminderKind.nutritionReview.meal)
        XCTAssertEqual(ReminderKind.allCases.compactMap(\.meal), Meal.allCases)
    }

    func testLocalizedContentDescribesRealDiaryActionsWithoutInventedActivityData() {
        XCTAssertEqual(ReminderKind.breakfast.title(.en), "Log your breakfast")
        XCTAssertEqual(ReminderKind.breakfast.title(.ar), "تذكير بتسجيل الفطور")
        XCTAssertEqual(ReminderKind.nutritionReview.label(.en), "Daily review")
        for kind in ReminderKind.allCases {
            XCTAssertEqual(kind.label(.ar), kind.meal?.label(.ar) ?? "مراجعة اليوم")
            for language in AppLanguage.allCases {
                let title = kind.title(language)
                let body = kind.body(language)
                XCTAssertFalse(title.isEmpty)
                XCTAssertFalse(body.isEmpty)
                XCTAssertNotEqual(title, body)
                XCTAssertFalse((title + body).contains("250"))
                XCTAssertFalse((title + body).lowercased().contains("water"))
                XCTAssertFalse((title + body).lowercased().contains("workout"))
            }
        }
        XCTAssertEqual(Set(ReminderKind.allCases.map { $0.title(.en) }).count, ReminderKind.allCases.count)
        XCTAssertEqual(Set(ReminderKind.allCases.map { $0.title(.ar) }).count, ReminderKind.allCases.count)
    }
}
