import Foundation

/// Arabic labels and reading direction remain Arabic; every displayed number
/// uses the same 0...9 digits regardless of the device's regional settings.
enum DisplayFormat {
    static func locale(_ language: AppLanguage) -> Locale {
        Locale(identifier: language == .ar ? "ar_SA@numbers=latn" : "en_US@numbers=latn")
    }

    static func calendar(_ language: AppLanguage) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale(language)
        calendar.timeZone = .current
        return calendar
    }

    static func westernDigits(_ text: String) -> String {
        guard text.unicodeScalars.contains(where: { (0x0660...0x0669).contains($0.value) || (0x06F0...0x06F9).contains($0.value) }) else { return text }
        return String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            let value = scalar.value
            if (0x0660...0x0669).contains(value) { return UnicodeScalar(0x0030 + value - 0x0660)! }
            if (0x06F0...0x06F9).contains(value) { return UnicodeScalar(0x0030 + value - 0x06F0)! }
            return scalar
        }))
    }

    static func decimal(_ value: Double, digits: Int = 1) -> String {
        guard value.isFinite else { return "—" }
        return String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), min(6, max(0, digits)), value)
    }

    static func date(_ value: Date, template: String, language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale(language)
        formatter.calendar = calendar(language)
        formatter.setLocalizedDateFormatFromTemplate(template)
        return westernDigits(formatter.string(from: value))
    }
}
