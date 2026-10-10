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
    /// Keep the persisted Food identifiers unchanged. These normalization rules
    /// belong to searching only, so old diary entries and saved products retain
    /// their identity when a spelling is normalized differently.
    static func normalized(_ text: String) -> String {
        var value = TextSearch.normalized(text)
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

    /// The catalog can contain thousands of foods. Build its text once, rather
    /// than repeatedly normalizing every name on each keystroke.
    struct Index {
        private let entries: [Entry]
        init(_ foods: [Food]) { entries = foods.map(Entry.init) }

        func results(_ query: String, additional: [Food] = []) -> [Food] {
            let term = Query(query)
            guard !term.words.isEmpty else { return [] }
            var seen = Set<String>()
            let candidates = (additional.map(Entry.init) + entries).enumerated().compactMap { offset, entry -> Ranked? in
                guard entry.matches(term), seen.insert(entry.food.id).inserted else { return nil }
                return Ranked(entry: entry, rank: entry.rank(term), offset: offset)
            }
            return candidates.sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                if lhs.entry.complete != rhs.entry.complete { return lhs.entry.complete }
                if lhs.entry.nameWords != rhs.entry.nameWords { return lhs.entry.nameWords < rhs.entry.nameWords }
                if lhs.entry.names[0] != rhs.entry.names[0] { return lhs.entry.names[0] < rhs.entry.names[0] }
                if lhs.entry.food.id != rhs.entry.food.id { return lhs.entry.food.id < rhs.entry.food.id }
                return lhs.offset < rhs.offset
            }.map { $0.entry.food }
        }
    }

    private struct Query {
        let text: String
        let words: [String]
        init(_ query: String) {
            text = normalized(query)
            var seen = Set<String>()
            words = text.split(separator: " ").map(String.init).filter { seen.insert($0).inserted }
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
        let nameWords: Int
        let complete: Bool

        init(_ food: Food) {
            self.food = food
            names = [normalized(food.name)] + (food.nameEn.map { [normalized($0)] } ?? [])
            aliases = (food.aliases ?? "").components(separatedBy: CharacterSet(charactersIn: ",،;؛|\n")).map(normalized).filter { !$0.isEmpty }
            text = (names + aliases + [normalized(food.brand ?? "")]).joined(separator: " ")
            nameWords = names.map { $0.split(separator: " ").count }.min() ?? 0
            complete = food.per100 != nil || food.servingNutrition?.valid == true
        }

        func matches(_ query: Query) -> Bool {
            query.words.allSatisfy { text.contains($0) }
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
}
