import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor FoodDatabase {
    static let shared = FoodDatabase()
    static let searchSummarySourceDescription = "openfoodfacts-search-summary"
    private var catalog = FoodSearch.Index([])
    private var catalogReady = false
    private var cachedFoods: [Food] = []
    private var localIndex = FoodSearch.Index([])
    private var suggestionIndex = FoodSuggestions.Index([])
    private var suggestionHistory: [Food] = []
    private var historySuggestionIndex = FoodSuggestions.Index([])
    private var indexesReady = false
    private var resolvedQueries: [String: String] = [:]
    private var searchStarts: [TimeInterval] = []
    private var barcodeStarts: [TimeInterval] = []
    private var searchBlockedUntil: TimeInterval = 0
    private var barcodeBlockedUntil: TimeInterval = 0
    private var pages: [String: (saved: TimeInterval, page: FoodSearchPage)] = [:]
    private static let pageSize = 50
    private static let fields = ["code", "product_name", "product_name_ar", "product_name_en", "brands", "nutriments", "nutrition", "nutrition_data_per", "serving_size", "serving_quantity", "serving_quantity_unit", "product_quantity_unit"]

    init() {}

    /// Constructing `shared` on a UI task stays cheap. File reads and preparing
    /// the bundled index happen only inside the actor's first isolated call.
    private func ensureCatalog() {
        guard !catalogReady else { return }
        var foods: [Food] = []
        for name in ["foods-data", "mfp-foods-data"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "json"), let data = try? Data(contentsOf: url) {
                foods += (try? JSONDecoder().decode([Food].self, from: data)) ?? []
            }
        }
        catalog = FoodSearch.Index(foods.filter(FoodSearch.isCatalogFood))
        catalogReady = true
    }

    func local(_ query: String, cached: [Food]) -> [Food] {
        prepareIndexes(cached)
        return localIndex.results(query)
    }

    struct Presentation {
        var exact: [Food]
        var nearby: [Food]
        var suggestions: [FoodSuggestion]
    }

    private func prepareIndexes(_ cached: [Food]) {
        ensureCatalog()
        guard !indexesReady || cached != cachedFoods else { return }
        cachedFoods = cached; indexesReady = true
        let values = (Array(cached.reversed()) + catalog.foods).filter(FoodSearch.availableForAdding)
        localIndex = FoodSearch.Index(values)
        suggestionIndex = FoodSuggestions.Index(values)
    }

    /// All normalization, fuzzy matching and suggestions run on this actor,
    /// away from the main actor that handles keyboard events and SwiftUI.
    func presentation(_ query: String, cached: [Food], history: [Food], personal: [Food]? = nil,
                      language: AppLanguage, catalogOnly: Bool) -> Presentation {
        prepareIndexes(cached)
        if history != suggestionHistory {
            suggestionHistory = history; historySuggestionIndex = FoodSuggestions.Index(history)
        }
        let term = FoodSearch.normalized(query)
        let found: FoodSearch.Matches
        if let personal {
            let allowed = personal.filter { FoodSearch.availableForAdding($0) && (!catalogOnly || FoodSearch.isCatalogFood($0)) }
            found = term.isEmpty ? FoodSearch.Matches(exact: allowed) : FoodSearch.Index(allowed).matches(query, nearbyLimit: 0)
        } else {
            found = localIndex.matches(query)
        }
        let exact = catalogOnly ? found.exact.filter(FoodSearch.isCatalogFood) : found.exact
        let nearby = catalogOnly ? found.nearby.filter(FoodSearch.isCatalogFood) : found.nearby
        return Presentation(exact: exact, nearby: nearby,
                            suggestions: suggestionIndex.suggestions(query: query, language: language,
                                                                    history: historySuggestionIndex, limit: 6))
    }

    func suggestionCandidates(cached: [Food]) -> [Food] {
        ensureCatalog()
        var seen = Set<String>()
        return (Array(cached.reversed()) + catalog.foods).filter {
            FoodSearch.availableForAdding($0) && seen.insert($0.id).inserted
        }
    }

    func historyFoods(_ entries: [DiaryEntry]) -> [Food] { ensureCatalog(); return catalog.historyCandidates(entries) }
    func historyLists(_ state: DiarySnapshot) -> (recent: [Food], frequent: [Food], personal: [Food]) {
        ensureCatalog()
        var filtered = state
        filtered.products = state.products.filter(FoodSearch.availableForAdding)
        filtered.searchHistory = state.searchHistory.filter(FoodSearch.availableForAdding)
        filtered.barcodeHistory = state.barcodeHistory.filter(FoodSearch.availableForAdding)
        return FoodHistory.lists(in: filtered, catalog: catalog.historyCandidates(state.entries))
    }

    func combined(_ query: String, local: [Food], remote: [Food]) -> [Food] {
        FoodSearch.results(query, in: (local + remote).filter(FoodSearch.availableForAdding))
    }

    func combinedMatches(_ query: String, local: [Food], remote: [Food], catalogOnly: Bool) -> FoodSearch.Matches {
        let values = (local + remote).filter { FoodSearch.availableForAdding($0) && (!catalogOnly || FoodSearch.isCatalogFood($0)) }
        return FoodSearch.Index(values).matches(query)
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
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.5"
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
        if let saved = cached.last(where: { $0.barcode == code && FoodSearch.isOpenFoodFacts($0) }) {
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
        url.path = "/api/v3.6/product/\(code).json"
        url.queryItems = [URLQueryItem(name: "fields", value: Self.fields.joined(separator: ","))]
        let json = try await request(URLRequest(url: url.url!), allowMissing: true)
        guard json["status"] as? String == "success", let product = json["product"] as? [String: Any] else { return nil }
        return OpenFoodFactsProduct.parse(product)
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
        let variants = page == 1 ? FoodSearch.onlineQueries(query) : [resolvedQueries[term] ?? FoodSearch.onlineQueries(query).first ?? query]
        var selected: FoodSearchPage?
        var selectedScore = -1
        var collected: [Food] = []
        var seen = Set<String>()
        // Extra spelling/brand requests happen only after an explicit Search.
        // Return source products unchanged and let exact/nearby matching label
        // them; a brand-only fallback is never declared an exact chest product.
        for variant in variants {
            try Task.checkCancellation()
            let result: FoodSearchPage
            do { result = try await remotePage(variant, page: page) }
            catch {
                try Task.checkCancellation()
                if !collected.isEmpty { break }
                throw error
            }
            collected += result.foods.filter { seen.insert($0.id).inserted }
            let matches = FoodSearch.Index(result.foods).matches(query)
            let score = matches.exact.count * 1000 + matches.nearby.count
            if score > selectedScore {
                selected = result; selectedScore = score; resolvedQueries[term] = variant
            }
            if !matches.exact.isEmpty { break }
        }
        var result = selected ?? FoodSearchPage(foods: [], nextPage: nil, sourceTotal: 0)
        result.foods = collected
        try Task.checkCancellation()
        pages[key] = (ProcessInfo.processInfo.systemUptime, result)
        if pages.count > 24, let oldest = pages.min(by: { $0.value.saved < $1.value.saved })?.key {
            pages.removeValue(forKey: oldest)
            resolvedQueries.removeValue(forKey: String(oldest.split(separator: "|").first ?? ""))
        }
        return result
    }

    private func remotePage(_ query: String, page: Int) async throws -> FoodSearchPage {
        try reserveSearch()
        var req = URLRequest(url: URL(string: "https://search.openfoodfacts.org/search")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "q": query, "page": page, "page_size": Self.pageSize, "langs": ["ar", "en"],
            "fields": Self.fields, "boost_phrase": true
        ])
        let json = try await request(req, searching: true)
        guard let hits = json["hits"] as? [[String: Any]],
              let pagination = FoodSearchPage.pagination(json, requestedPage: page, pageSize: Self.pageSize) else {
            throw AppError.invalid("لم تكتمل نتائج البحث. جرّب مرة أخرى؛ الأطعمة المحفوظة متاحة الآن.", "The search did not complete. Retry; saved foods are available now.")
        }
        let summaries = hits.compactMap(OpenFoodFactsProduct.parse).map { product -> Food in
            var summary = product
            summary.sourceDescription = Self.searchSummarySourceDescription
            return summary
        }
        let result = FoodSearchPage(foods: summaries,
                                    nextPage: pagination.nextPage, sourceTotal: pagination.sourceTotal,
                                    reachedSourceWindow: pagination.reachedSourceWindow)
        try Task.checkCancellation()
        return result
    }

}
