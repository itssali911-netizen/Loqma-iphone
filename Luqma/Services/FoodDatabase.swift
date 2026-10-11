import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor FoodDatabase {
    static let shared = FoodDatabase()
    static let searchSummarySourceDescription = "openfoodfacts-search-summary"
    private let catalog: FoodSearch.Index
    private var searchStarts: [TimeInterval] = []
    private var barcodeStarts: [TimeInterval] = []
    private var searchBlockedUntil: TimeInterval = 0
    private var barcodeBlockedUntil: TimeInterval = 0
    private var pages: [String: (saved: TimeInterval, page: FoodSearchPage)] = [:]
    private static let pageSize = 50
    private static let fields = ["code", "product_name", "product_name_ar", "product_name_en", "brands", "nutriments", "nutrition_data_per", "serving_size", "serving_quantity", "serving_quantity_unit", "product_quantity_unit"]

    init() {
        var foods: [Food] = []
        if let url = Bundle.main.url(forResource: "foods-data", withExtension: "json"), let data = try? Data(contentsOf: url) {
            foods = (try? JSONDecoder().decode([Food].self, from: data)) ?? []
        }
        catalog = FoodSearch.Index(foods)
    }

    func local(_ query: String, cached: [Food]) -> [Food] {
        catalog.results(query, additional: Array(cached.reversed()))
    }

    func historyFoods(_ entries: [DiaryEntry]) -> [Food] { catalog.historyCandidates(entries) }
    func historyLists(_ state: DiarySnapshot) -> (recent: [Food], frequent: [Food], personal: [Food]) { FoodHistory.lists(in: state, catalog: catalog.historyCandidates(state.entries)) }

    func combined(_ query: String, local: [Food], remote: [Food]) -> [Food] {
        remote.isEmpty ? local : FoodSearch.results(query, in: local + remote)
    }

    /// OFF asks apps not to search online on every keystroke. The UI submits a
    /// query or explicitly requests a page; cached pages need no network slot.
    private func reserveSearch() throws {
        let now = ProcessInfo.processInfo.systemUptime
        searchStarts.removeAll { now - $0 >= 60 }
        let quota = searchStarts.count >= 10 ? max(0, 60 - (now - searchStarts[0])) : 0
        let wait = max(quota, searchBlockedUntil - now)
        guard wait <= 0 else {
            let seconds = Int(ceil(wait))
            throw AppError.invalid("انتظر \(seconds) ثانية ثم أعد البحث. النتائج المحفوظة متاحة الآن.", "Wait \(seconds) seconds before searching again. Saved results are available now.")
        }
        searchStarts.append(now)
    }

    private func reserveBarcode() throws {
        let now = ProcessInfo.processInfo.systemUptime
        barcodeStarts.removeAll { now - $0 >= 60 }
        let quota = barcodeStarts.count >= 15 ? max(0, 60 - (now - barcodeStarts[0])) : 0
        let wait = max(quota, barcodeBlockedUntil - now)
        guard wait <= 0 else {
            let seconds = Int(ceil(wait))
            throw AppError.invalid("انتظر \(seconds) ثانية قبل البحث عن باركود آخر.", "Wait \(seconds) seconds before looking up another barcode.")
        }
        barcodeStarts.append(now)
    }

    private func request(_ request: URLRequest, allowMissing: Bool = false, searching: Bool = false) async throws -> [String: Any] {
        try Task.checkCancellation()
        var req = request
        req.timeoutInterval = 18
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3"
        req.setValue("LuqmaIOS/\(version) (https://github.com/itssali911-netizen/Loqma-iphone)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        try Task.checkCancellation()
        if allowMissing, (response as? HTTPURLResponse)?.statusCode == 404 { return ["status": 0] }
        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            let header = http.value(forHTTPHeaderField: "Retry-After")
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            let supplied = header.flatMap(Double.init) ?? header.flatMap { formatter.date(from: $0)?.timeIntervalSinceNow }
            let retry = supplied.map { $0.isFinite ? min(3600, max(1, $0)) : 60 } ?? 60
            if searching { searchBlockedUntil = ProcessInfo.processInfo.systemUptime + retry }
            else { barcodeBlockedUntil = ProcessInfo.processInfo.systemUptime + retry }
            throw AppError.invalid("قاعدة المنتجات مشغولة. انتظر قليلًا ثم أعد المحاولة؛ الأطعمة المحفوظة متاحة الآن.", "The product database is busy. Wait a little and retry; saved foods are available now.")
        }
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode), data.count < 15 * 1024 * 1024,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AppError.invalid("تعذّر الاتصال بقاعدة المنتجات. الأطعمة المحفوظة متاحة دون إنترنت.", "The product database could not be reached. Saved foods remain available offline.")
        }
        return json
    }

    func barcode(_ raw: String, cached: [Food]) async throws -> Food? {
        let code = TextSearch.normalized(raw).filter { $0.isNumber }
        guard (8...14).contains(code.count), TextSearch.normalized(raw).trimmingCharacters(in: .whitespacesAndNewlines) == code else {
            throw AppError.invalid("أدخل رقم باركود من ٨ إلى ١٤ رقمًا.", "Enter a barcode of 8 to 14 digits.")
        }
        if let saved = cached.last(where: { $0.barcode == code }) {
            if saved.sourceDescription == Self.searchSummarySourceDescription { return try await details(for: saved) }
            if saved.per100 != nil || saved.servingNutrition != nil { return saved }
        }
        return try await loadProduct(code)
    }

    /// The search index can omit liquid units and serving information. Resolve
    /// those fields from the authoritative product endpoint before using its
    /// nutrition in the diary; old saved foods remain usable offline.
    func details(for food: Food) async throws -> Food {
        try Task.checkCancellation()
        guard food.sourceDescription == Self.searchSummarySourceDescription else { return food }
        guard food.source == "OpenFoodFacts", let code = food.sourceId ?? food.barcode,
              let resolved = try await loadProduct(code) else {
            throw AppError.invalid("تعذّر تحميل تفاصيل المنتج. أعد المحاولة أو أدخل بيانات ملصقه يدويًا.", "Product details could not be loaded. Retry or enter its label nutrition manually.")
        }
        try Task.checkCancellation()
        return resolved
    }

    private func loadProduct(_ code: String) async throws -> Food? {
        try Task.checkCancellation()
        // OFF also assigns internal codes that are not EAN barcodes. Restrict
        // path characters, without applying the scanner's 8–14-digit limit.
        guard !code.isEmpty, code.count <= 180,
              code.allSatisfy({ "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_".contains($0) }) else {
            throw AppError.invalid("تعذّر قراءة معرّف المنتج. أدخل بيانات ملصقه يدويًا.", "The product identifier could not be read. Enter its label nutrition manually.")
        }
        try reserveBarcode()
        var url = URLComponents(string: "https://world.openfoodfacts.org")!
        url.path = "/api/v2/product/\(code).json"
        url.queryItems = [URLQueryItem(name: "fields", value: Self.fields.joined(separator: ","))]
        let json = try await request(URLRequest(url: url.url!), allowMissing: true)
        guard (json["status"] as? Int) == 1, let product = json["product"] as? [String: Any] else { return nil }
        return Self.product(product)
    }

    func remote(_ query: String, page: Int = 1) async throws -> FoodSearchPage {
        let term = FoodSearch.normalized(query)
        guard !term.isEmpty else { return FoodSearchPage(foods: [], nextPage: nil, sourceTotal: 0) }
        // Search-a-licious exposes an explicit 10,000-result window. Local
        // catalog matches are not subject to this external API limit.
        guard term.count <= 180, page >= 1, page <= 10_000 / Self.pageSize else {
            throw AppError.invalid("اختصر كلمات البحث لتظهر نتائج أدق.", "Use a more specific search to find the relevant foods.")
        }
        try Task.checkCancellation()
        let key = "\(term)|\(page)"
        let now = ProcessInfo.processInfo.systemUptime
        pages = pages.filter { now - $0.value.saved < 300 }
        if let cached = pages[key] { return cached.page }
        try reserveSearch()
        var req = URLRequest(url: URL(string: "https://search.openfoodfacts.org/search")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "q": term, "page": page, "page_size": Self.pageSize, "langs": ["ar", "en"],
            "fields": Self.fields, "boost_phrase": true
        ])
        let json = try await request(req, searching: true)
        guard let hits = json["hits"] as? [[String: Any]],
              let pagination = FoodSearchPage.pagination(json, requestedPage: page, pageSize: Self.pageSize) else {
            throw AppError.invalid("لم تكتمل نتائج البحث. جرّب مرة أخرى؛ الأطعمة المحفوظة متاحة الآن.", "The search did not complete. Retry; saved foods are available now.")
        }
        let summaries = hits.compactMap(Self.product).map { product -> Food in
            var summary = product
            summary.sourceDescription = Self.searchSummarySourceDescription
            return summary
        }
        let result = FoodSearchPage(foods: FoodSearch.results(term, in: summaries),
                                    nextPage: pagination.nextPage, sourceTotal: pagination.sourceTotal,
                                    reachedSourceWindow: pagination.reachedSourceWindow)
        try Task.checkCancellation()
        pages[key] = (ProcessInfo.processInfo.systemUptime, result)
        if pages.count > 24, let oldest = pages.min(by: { $0.value.saved < $1.value.saved })?.key { pages.removeValue(forKey: oldest) }
        return result
    }

    private static func product(_ product: [String: Any]) -> Food? {
        func text(_ key: String) -> String? {
            let value = (product[key] as? String) ?? (product[key] as? [String])?.joined(separator: ", ")
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return String(value.prefix(180))
        }
        guard let code = text("code"), let name = text("product_name_ar") ?? text("product_name") ?? text("product_name_en") else { return nil }
        let barcode = (8...14).contains(code.count) && code.allSatisfy { "0123456789".contains($0) } ? code : nil
        let nutriments = product["nutriments"] as? [String: Any] ?? [:]
        func number(_ key: String) -> Double? {
            let value = (nutriments[key] as? NSNumber)?.doubleValue ?? (nutriments[key] as? String).flatMap(Double.init)
            return value.flatMap { $0.isFinite && $0 >= 0 && $0 <= 100_000 ? $0 : nil }
        }
        func nutrition(_ suffix: String) -> Nutrition? {
            guard let kcal = number("energy-kcal_" + suffix) ?? ((number("energy-kj_" + suffix) ?? number("energy_" + suffix)).map { $0 / 4.184 }),
                  let protein = number("proteins_" + suffix), let carbs = number("carbohydrates_" + suffix), let fat = number("fat_" + suffix) else { return nil }
            return Nutrition(kcal: kcal, protein: protein, carbs: carbs, fat: fat)
        }
        let serving = text("serving_size")
        let match = serving.flatMap { try? NSRegularExpression(pattern: "([0-9]+(?:[.,][0-9]+)?)\\s*(g|ml|gr|gram|grams)\\b", options: .caseInsensitive).firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) }
        var quantity: Double?, servingUnit: String?
        if let serving, let match, let value = Range(match.range(at: 1), in: serving), let unit = Range(match.range(at: 2), in: serving) {
            if let parsed = Double(serving[value].replacingOccurrences(of: ",", with: ".")), parsed.isFinite, parsed > 0, parsed <= 10_000 {
                quantity = parsed
                servingUnit = serving[unit].lowercased() == "ml" ? "ml" : "g"
            }
        }
        if quantity == nil,
           let value = (product["serving_quantity"] as? NSNumber)?.doubleValue,
           value.isFinite, value > 0, value <= 10_000,
           let unit = text("serving_quantity_unit"), ["g", "ml"].contains(unit) {
            quantity = value
            servingUnit = unit
        }
        let declaredBasis = text("nutrition_data_per")?.lowercased().replacingOccurrences(of: " ", with: "")
        let base: FoodUnit
        if declaredBasis == "100ml" { base = .ml }
        else if declaredBasis == "100g" { base = .g }
        else { base = text("product_quantity_unit") == "ml" || servingUnit == "ml" ? .ml : .g }
        let per100 = nutrition("100g"), direct = nutrition("serving")
        let calculated = quantity.flatMap { value in value > 0 && servingUnit == base.rawValue ? per100?.scaled(value / 100) : nil }
        var food = Food(catalogID: "off:" + code, name: name, nameEn: text("product_name_en"), brand: text("brands"), barcode: barcode, unit: base,
                        nutrition: per100, serving: serving, servingQuantity: quantity, servingUnit: servingUnit,
                        servingNutrition: direct ?? calculated, source: "OpenFoodFacts")
        food.sourceId = code
        // Preserve the alternate language and original product label in the
        // searchable aliases even when an Arabic label is chosen for display.
        food.aliases = [text("product_name_ar"), text("product_name_en"), text("product_name")].compactMap { $0 }.filter { $0 != name && $0 != food.nameEn }.joined(separator: " | ")
        if per100 == nil && food.servingNutrition != nil { food.unit = .serving }
        return food
    }
}
