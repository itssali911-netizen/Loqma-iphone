import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Reads only numeric weight/height records. Other health and personal data are ignored.
struct HealthImportResult {
    var weights: [WeightReading]
    var heightCM: Double?
}

enum HealthImport {
    static func read(_ url: URL, now: Date = Date()) throws -> HealthImportResult {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 1_000_000_000 else {
            throw AppError.invalid("اختر ملف export.xml من تصدير صحتي، بحجم أقل من ١ جيجابايت.", "Choose Health's export.xml, smaller than 1 GB.")
        }
        guard let parser = XMLParser(contentsOf: url) else { throw invalid }
        return try parse(parser, now: now)
    }
    static func read(_ data: Data, now: Date = Date()) throws -> HealthImportResult {
        guard !data.isEmpty, data.count <= 1_000_000_000 else { throw invalid }
        return try parse(XMLParser(data: data), now: now)
    }
    private static var invalid: AppError { .invalid("هذا ليس ملف تصدير صالحًا من صحتي. فك ضغط التصدير واختر export.xml.", "Invalid Health export. Unzip the export and choose export.xml.") }
    private static func parse(_ parser: XMLParser, now: Date) throws -> HealthImportResult {
        let delegate = Reader(now: now)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), delegate.healthRoot else { throw delegate.failure ?? invalid }
        let weights = delegate.daily.values.sorted { $0.day < $1.day }
        guard !weights.isEmpty || delegate.height != nil else {
            throw AppError.invalid("لا يحتوي التصدير على قراءات وزن أو طول صالحة لنطاق التطبيق.", "No weight or height readings within the app's supported range were found.")
        }
        return HealthImportResult(weights: weights, heightCM: delegate.height?.value)
    }
    private final class Reader: NSObject, XMLParserDelegate {
        let now: Date
        let formatter: DateFormatter
        var healthRoot = false
        var daily: [String: WeightReading] = [:]
        var height: (date: Date, value: Double)?
        var count = 0
        var failure: AppError?
        init(now: Date) {
            self.now = now
            formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        }
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
            if elementName == "HealthData" { healthRoot = true }
            guard elementName == "Record", healthRoot else { return }
            count += 1
            if count % 1024 == 0, Task.isCancelled { failure = .invalid("أُلغي الاستيراد.", "Import cancelled."); parser.abortParsing(); return }
            guard let type = attributes["type"], type == "HKQuantityTypeIdentifierBodyMass" || type == "HKQuantityTypeIdentifierHeight",
                  let raw = attributes["value"], let value = Double(raw), value.isFinite,
                  let unit = attributes["unit"], let dateString = attributes["endDate"],
                  let date = formatter.date(from: dateString), date <= now,
                  date.timeIntervalSince1970 > 0 else { return }
            if type == "HKQuantityTypeIdentifierBodyMass" {
                let scale: Double
                switch unit { case "kg": scale = 1; case "g": scale = 0.001; case "lb": scale = 0.45359237; case "oz": scale = 0.028349523125; default: return }
                let kg = value * scale, day = DayKey.string(date)
                guard (35...300).contains(kg), (daily[day]?.timestamp ?? 0) < date.timeIntervalSince1970 else { return }
                daily[day] = WeightReading(day: day, kg: kg, source: "Apple Health", timestamp: date.timeIntervalSince1970)
            } else {
                let scale: Double
                switch unit { case "cm": scale = 1; case "m": scale = 100; case "in": scale = 2.54; case "ft": scale = 30.48; default: return }
                let cm = value * scale
                guard (120...240).contains(cm), height == nil || height!.date < date else { return }
                height = (date, cm)
            }
        }
        func parser(_ parser: XMLParser, resolveExternalEntityName name: String, systemID: String?) -> Data? { Data() }
    }
}

/// A profile without HealthKit cannot be fixed by an in-app permission request.
enum HealthSigning {
    static func profileSupportsHealth(_ data: Data) -> Bool? {
        entitlement("com.apple.developer.healthkit", in: data)
    }
    static func profileSupportsBackgroundHealth(_ data: Data) -> Bool? {
        guard profileSupportsHealth(data) != false else { return false }
        return entitlement("com.apple.developer.healthkit.background-delivery", in: data)
    }
    private static func entitlement(_ key: String, in data: Data) -> Bool? {
        guard data.count <= 5_000_000,
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any] else { return nil }
        return entitlements[key] as? Bool ?? false
    }
}
