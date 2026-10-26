import Foundation

/// Only actions that already exist in the diary can be the destination of a
/// reminder. These identifiers are shared by scheduling and notification taps.
enum ReminderKind: String, Codable, CaseIterable, Identifiable, Hashable {
    case breakfast, lunch, dinner, snack, nutritionReview

    static let notificationIdentifierPrefix = "app.luqma.reminder."

    var id: String { rawValue }
    var notificationIdentifier: String { Self.notificationIdentifierPrefix + rawValue }

    static func fromNotificationIdentifier(_ identifier: String) -> ReminderKind? {
        allCases.first { $0.notificationIdentifier == identifier }
    }

    var meal: Meal? {
        switch self {
        case .breakfast: return .breakfast
        case .lunch: return .lunch
        case .dinner: return .dinner
        case .snack: return .snack
        case .nutritionReview: return nil
        }
    }

    func label(_ language: AppLanguage) -> String {
        meal?.label(language) ?? language.text("مراجعة اليوم", "Daily review")
    }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .breakfast: return language.text("تذكير بتسجيل الفطور", "Log your breakfast")
        case .lunch: return language.text("تذكير بتسجيل الغداء", "Log your lunch")
        case .dinner: return language.text("تذكير بتسجيل العشاء", "Log your dinner")
        case .snack: return language.text("تذكير بتسجيل السناك", "Log your snack")
        case .nutritionReview: return language.text("راجع يومك مع لقمة", "Review your day with Luqma")
        }
    }

    func body(_ language: AppLanguage) -> String {
        switch self {
        case .breakfast: return language.text("أضف أطعمة الفطور وكمياتها إلى يومياتك.", "Add your breakfast foods and portions to your diary.")
        case .lunch: return language.text("أضف أطعمة الغداء وكمياتها إلى يومياتك.", "Add your lunch foods and portions to your diary.")
        case .dinner: return language.text("أضف أطعمة العشاء وكمياتها إلى يومياتك.", "Add your dinner foods and portions to your diary.")
        case .snack: return language.text("أضف أطعمة السناك وكمياتها إلى يومياتك.", "Add your snack foods and portions to your diary.")
        case .nutritionReview: return language.text("راجع الوجبات المسجلة وأهدافك الغذائية اليومية.", "Review your logged meals and daily nutrition goals.")
        }
    }
}

struct DailyReminder: Codable, Equatable, Identifiable {
    var kind: ReminderKind
    var hour: Int
    var minute: Int
    var isEnabled: Bool

    var id: ReminderKind { kind }
}

enum ReminderPreferencesError: Error, Equatable {
    case unsupportedVersion(Int)
    case missingKind(ReminderKind)
    case duplicateKind(ReminderKind)
    case invalidTime(ReminderKind)
}

/// Device-local preferences are deliberately separate from DiarySnapshot and
/// backups. Permission to deliver notifications is an OS setting, never a field
/// in this document. A damaged document must not silently enable/reset reminders.
struct ReminderPreferences: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var reminders: [DailyReminder]

    init(version: Int = Self.currentVersion, reminders: [DailyReminder]) {
        self.version = version
        self.reminders = reminders
    }

    static let defaults = ReminderPreferences(reminders: [
        DailyReminder(kind: .breakfast, hour: 8, minute: 0, isEnabled: false),
        DailyReminder(kind: .lunch, hour: 13, minute: 0, isEnabled: false),
        DailyReminder(kind: .dinner, hour: 19, minute: 0, isEnabled: false),
        DailyReminder(kind: .snack, hour: 16, minute: 0, isEnabled: false),
        DailyReminder(kind: .nutritionReview, hour: 21, minute: 0, isEnabled: false)
    ])

    func reminder(for kind: ReminderKind) -> DailyReminder? {
        reminders.first { $0.kind == kind }
    }

    /// Validation returns a canonical order without changing any enabled state
    /// or chosen time. Every kind is required in this version of the document.
    func validated() throws -> ReminderPreferences {
        guard version == Self.currentVersion else { throw ReminderPreferencesError.unsupportedVersion(version) }
        var seen = Set<ReminderKind>()
        for reminder in reminders {
            guard seen.insert(reminder.kind).inserted else { throw ReminderPreferencesError.duplicateKind(reminder.kind) }
            guard (0...23).contains(reminder.hour), (0...59).contains(reminder.minute) else {
                throw ReminderPreferencesError.invalidTime(reminder.kind)
            }
        }
        for kind in ReminderKind.allCases where !seen.contains(kind) {
            throw ReminderPreferencesError.missingKind(kind)
        }
        return ReminderPreferences(version: version, reminders: ReminderKind.allCases.compactMap { reminder(for: $0) })
    }

    private enum CodingKeys: String, CodingKey { case version, reminders }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let candidate = ReminderPreferences(
            version: try container.decode(Int.self, forKey: .version),
            reminders: try container.decode([DailyReminder].self, forKey: .reminders)
        )
        do { self = try candidate.validated() }
        catch {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid reminder preferences: \(error)"))
        }
    }

    func encode(to encoder: Encoder) throws {
        let value = try validated()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value.version, forKey: .version)
        try container.encode(value.reminders, forKey: .reminders)
    }
}
