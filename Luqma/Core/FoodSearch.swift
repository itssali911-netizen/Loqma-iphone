import Foundation

/// The source count includes products matching categories or ingredients, so it
/// must not be presented as the count of the name-filtered foods below.
struct FoodSearchPage {
    var foods: [Food]
    var nextPage: Int?
    var sourceTotal: Int?
    var reachedSourceWindow = false
    var hasMore: Bool { nextPage != nil }

    struct Pagination {
        let nextPage: Int?
        let sourceTotal: Int?
        let reachedSourceWindow: Bool
    }

    /// Search-a-licious counts source hits, before the app filters product names.
    /// A page of unrelated names can therefore still have a following page.
    static func pagination(_ json: [String: Any], requestedPage: Int, pageSize: Int) -> Pagination? {
        guard requestedPage > 0, pageSize > 0, json["errors"] == nil, json["timed_out"] as? Bool != true,
              let hits = json["hits"] as? [Any], (json["page"] as? Int) == requestedPage,
              (json["page_size"] as? Int) == pageSize,
              let pageCount = json["page_count"] as? Int, pageCount >= 0,
              let count = json["count"] as? Int, count >= 0,
              let exact = json["is_count_exact"] as? Bool else { return nil }
        let maximumPages = 10_000 / pageSize
        guard maximumPages > 0, requestedPage <= maximumPages else { return nil }
        let lastPage = min(pageCount, maximumPages)
        let reached = requestedPage == maximumPages && !hits.isEmpty &&
            (pageCount > maximumPages || count > 10_000 || (!exact && count >= 10_000))
        return Pagination(nextPage: requestedPage < lastPage && !hits.isEmpty ? requestedPage + 1 : nil,
                          sourceTotal: exact ? count : nil, reachedSourceWindow: reached)
    }
}

enum FoodSearch {
    static func isMyFitnessPalBundled(_ food: Food) -> Bool {
        food.source == "MyFitnessPal supplied IPA" && food.catalogID?.hasPrefix("mfp-bundled:") == true &&
            food.sourceId.map { !$0.isEmpty && food.catalogID == "mfp-bundled:" + $0 } == true
    }

    static func isCatalogFood(_ food: Food) -> Bool { isOpenFoodFacts(food) || isMyFitnessPalBundled(food) }

    static func isOpenFoodFacts(_ food: Food) -> Bool {
        food.source == "OpenFoodFacts" && food.catalogID?.hasPrefix("off:") == true &&
            food.sourceId.map { !$0.isEmpty && food.catalogID == "off:" + $0 } == true
    }

    static func isPersonalFood(_ food: Food) -> Bool {
        food.source == "Your food" || MealPhotoEstimate.isValidPhotoEstimate(food) ||
            (food.source == nil && food.catalogID == nil && food.barcode == nil)
    }

    /// Old catalog caches and recognition-only labels stay excluded. A checked
    /// private photo estimate can be reused without becoming a catalog record.
    static func availableForAdding(_ food: Food) -> Bool { isCatalogFood(food) || isPersonalFood(food) }

    /// Keep the persisted Food identifiers unchanged. These normalization rules
    /// belong to searching only, so old diary entries and saved products retain
    /// their identity when a spelling is normalized differently.
    static func normalized(_ text: String) -> String {
        // Foundation can preserve a hamza when another Arabic mark follows it.
        // Decompose first so all combining marks are removed by the scalar pass.
        var value = TextSearch.normalized(text).decomposedStringWithCanonicalMapping
        for (original, replacement) in [("ؤ", "و"), ("ئ", "ي"), ("ی", "ي"), ("ک", "ك")] {
            value = value.replacingOccurrences(of: original, with: replacement)
        }
        for (index, digit) in "۰۱۲۳۴۵۶۷۸۹".enumerated() {
            value = value.replacingOccurrences(of: String(digit), with: String(index))
        }
        var result = ""
        result.reserveCapacity(value.utf8.count)
        var separating = false
        for scalar in value.unicodeScalars {
            if CharacterSet.nonBaseCharacters.contains(scalar) { continue }
            if CharacterSet.alphanumerics.contains(scalar) {
                if separating && !result.isEmpty { result.append(" ") }
                result.unicodeScalars.append(scalar)
                separating = false
            } else {
                separating = true
            }
        }
        return result
    }

    static func matches(_ food: Food, query: String) -> Bool {
        let term = Query(query)
        return !term.words.isEmpty && Entry(food).matches(term)
    }

    static func results(_ query: String, in foods: [Food]) -> [Food] {
        Index(foods).results(query)
    }

    /// Search spelling is deliberately separate from persisted names and IDs.
    /// Small, inspectable word equivalents help Arabic singular/plural queries;
    /// they never assign a brand or nutrition to a different product.
    static func token(_ word: String) -> String {
        var value = word
        if value.hasPrefix("ال"), value.count > 4 { value = String(value.dropFirst(2)) }
        switch value {
        case "tanmiah": return "تنميه"
        case "chicken": return "دجاج"
        case "breast", "breasts": return "صدر"
        case "rice": return "ارز"
        case "milk": return "حليب"
        case "egg", "eggs": return "بيض"
        case "صدور": return "صدر"
        case "افخاذ": return "فخذ"
        case "اجنحه": return "جناح"
        default: return value
        }
    }

    /// OFF's Arabic index distinguishes ة from ه. Never send our local
    /// identity-insensitive spelling to that service as its only query.
    static func onlineQueries(_ query: String) -> [String] {
        let typed = query.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard !normalized(typed).isEmpty else { return [] }
        let words = normalized(typed).split(separator: " ").map { token(String($0)) }
        var values = [typed]
        if words.contains("تنميه") || words.contains("tanmiah") {
            let arabic = typed.replacingOccurrences(of: "التنميه", with: "التنمية")
                .replacingOccurrences(of: "تنميه", with: "تنمية")
            if normalized(arabic) == normalized(typed), arabic != typed { values.append(arabic) }
            values.append(contentsOf: ["التنمية", "Tanmiah"])
        }
        var seen = Set<String>()
        return values.filter { seen.insert($0.lowercased()).inserted }
    }

    struct Matches {
        var exact: [Food] = []
        var nearby: [Food] = []
    }

    /// The catalog can contain thousands of foods. Build its text once, rather
    /// than repeatedly normalizing every name on each keystroke.
    struct Index {
        private let entries: [Entry]
        init(_ foods: [Food]) {
            var seen = Set<String>()
            entries = foods.filter { seen.insert($0.id).inserted }.map(Entry.init)
        }
        var foods: [Food] { entries.map(\.food) }

        func historyCandidates(_ diary: [DiaryEntry]) -> [Food] {
            let ids = Set(diary.compactMap(\.foodID))
            let codes = Set(diary.filter { $0.foodID == nil }.compactMap(\.barcode))
            let names = Set(diary.filter { $0.foodID == nil && $0.barcode == nil }.map { FoodSearch.normalized($0.name) })
            return entries.filter { ids.contains($0.food.id) || ($0.food.barcode.map(codes.contains) ?? false) || $0.names.contains(where: names.contains) }.map(\.food)
        }

        func results(_ query: String, additional: [Food] = []) -> [Food] {
            matches(query, additional: additional, nearbyLimit: 0).exact
        }

        func matches(_ query: String, additional: [Food] = [], nearbyLimit: Int = 20) -> Matches {
            let term = Query(query)
            guard !term.words.isEmpty else { return Matches() }
            var seen = Set<String>()
            var exact: [Ranked] = [], nearby: [Ranked] = []
            for (offset, entry) in (additional.map(Entry.init) + entries).enumerated() {
                if offset.isMultiple(of: 64), Task.isCancelled { return Matches() }
                guard seen.insert(entry.food.id).inserted else { continue }
                if entry.matches(term) {
                    exact.append(Ranked(entry: entry, rank: entry.rank(term), offset: offset))
                } else if nearbyLimit > 0, let score = entry.nearbyRank(term) {
                    nearby.append(Ranked(entry: entry, rank: score, offset: offset))
                }
            }
            func ordered(_ candidates: [Ranked]) -> [Food] { candidates.sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                if lhs.entry.complete != rhs.entry.complete { return lhs.entry.complete }
                if lhs.entry.nameWords != rhs.entry.nameWords { return lhs.entry.nameWords < rhs.entry.nameWords }
                if lhs.entry.names[0] != rhs.entry.names[0] { return lhs.entry.names[0] < rhs.entry.names[0] }
                if lhs.entry.food.id != rhs.entry.food.id { return lhs.entry.food.id < rhs.entry.food.id }
                return lhs.offset < rhs.offset
            }.map { $0.entry.food } }
            return Matches(exact: ordered(exact), nearby: Array(ordered(nearby).prefix(max(0, nearbyLimit))))
        }
    }

    private struct Query {
        let text: String
        let words: [String]
        let tokens: [String]
        init(_ query: String) {
            text = normalized(query)
            var seen = Set<String>()
            words = text.split(separator: " ").map(String.init).filter { seen.insert($0).inserted }
            tokens = words.map(FoodSearch.token)
        }
    }

    private struct Ranked {
        let entry: Entry
        let rank: Int
        let offset: Int
    }

    private struct Entry {
        let food: Food
        let names: [String]
        let aliases: [String]
        let text: String
        let tokens: [String]
        let nameTokens: [String]
        let nameWords: Int
        let complete: Bool

        init(_ food: Food) {
            self.food = food
            names = [normalized(food.name)] + (food.nameEn.map { [normalized($0)] } ?? [])
            aliases = (food.aliases ?? "").components(separatedBy: CharacterSet(charactersIn: ",،;؛|\n")).map(normalized).filter { !$0.isEmpty }
            text = (names + aliases + [normalized(food.brand ?? "")]).joined(separator: " ")
            let words = text.split(separator: " ").map(String.init)
            tokens = Array(Set(words + words.map(FoodSearch.token)))
            let namedWords = (names + aliases).joined(separator: " ").split(separator: " ").map(String.init)
            nameTokens = Array(Set(namedWords + namedWords.map(FoodSearch.token)))
            nameWords = names.map { $0.split(separator: " ").count }.min() ?? 0
            complete = food.per100 != nil || food.servingNutrition?.valid == true
        }

        func matches(_ query: Query) -> Bool {
            query.words.enumerated().allSatisfy { position, word in
                text.contains(word) || tokens.contains(where: { $0.hasPrefix(query.tokens[position]) })
            }
        }

        /// Approximate products are returned separately, never promoted to an
        /// exact branded match. Short/number-only typos and unrelated names
        /// cannot create an approximate match.
        func nearbyRank(_ query: Query) -> Int? {
            let exactWords = query.tokens.filter { candidate in tokens.contains(where: { $0.hasPrefix(candidate) }) }
            let missing = query.tokens.filter { candidate in !tokens.contains(where: { $0.hasPrefix(candidate) }) }
            if missing.count == 1, let candidate = missing.first,
               candidate.count >= 4, !candidate.allSatisfy(\.isNumber),
               tokens.contains(where: { FoodSearch.oneEditApart(candidate, $0) }) {
                return 21
            }
            guard query.tokens.count >= 2, !exactWords.isEmpty,
                  exactWords.count * 2 >= query.tokens.count,
                  exactWords.contains(where: { $0.count >= 3 && !$0.allSatisfy(\.isNumber) }),
                  exactWords.contains(where: { candidate in nameTokens.contains(where: { $0.hasPrefix(candidate) }) }) else { return nil }
            return 40 + missing.count * 10 - exactWords.count
        }

        func rank(_ query: Query) -> Int {
            if names.contains(query.text) { return 0 }
            if aliases.contains(query.text) { return 1 }
            if names.contains(where: { $0.hasPrefix(query.text) }) { return 2 }
            if aliases.contains(where: { $0.hasPrefix(query.text) }) { return 3 }
            if names.contains(where: { $0.contains(query.text) }) { return 4 }
            if aliases.contains(where: { $0.contains(query.text) }) { return 5 }
            if names.contains(where: { field in query.words.allSatisfy { field.contains($0) } }) { return 6 }
            if aliases.contains(where: { field in query.words.allSatisfy { field.contains($0) } }) { return 7 }
            return 8
        }
    }

    private static func oneEditApart(_ lhs: String, _ rhs: String) -> Bool {
        let a = Array(lhs), b = Array(rhs)
        guard min(a.count, b.count) >= 4, abs(a.count - b.count) <= 1 else { return false }
        if a.count == b.count {
            let differences = a.indices.filter { a[$0] != b[$0] }
            if differences.count == 1 { return true }
            if differences.count == 2 {
                let first = differences[0], second = differences[1]
                return second == first + 1 && a[first] == b[second] && a[second] == b[first]
            }
            return false
        }
        let short = a.count < b.count ? a : b, long = a.count < b.count ? b : a
        var i = 0, j = 0, edits = 0
        while i < short.count && j < long.count {
            if short[i] == long[j] { i += 1; j += 1 }
            else { edits += 1; j += 1; if edits > 1 { return false } }
        }
        return true
    }
}
