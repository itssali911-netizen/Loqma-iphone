import Foundation

/// A suggested query is a search action, never a food or nutrition selection.
struct FoodSuggestion: Identifiable, Equatable {
    enum Kind: String { case history, local, brand, popular, searchAll }
    let id: String
    let label: String
    let query: String
    let kind: Kind
}

enum FoodSuggestions {
    /// Local-only suggestions keep typing immediate without issuing OFF requests.
    /// The caller supplies history in its preferred recent/frequent order.
    static func suggestions(query: String, foods: [Food], language: AppLanguage,
                            history: [Food] = [], limit: Int = 6) -> [FoodSuggestion] {
        Index(foods).suggestions(query: query, language: language, history: Index(history), limit: limit)
    }

    /// The UI keeps this prepared index outside its body. Both languages,
    /// brands and aliases are normalized once when catalog/history changes.
    struct Index {
        private let entries: [Entry]
        init(_ foods: [Food]) {
            var seen = Set<String>()
            entries = foods.filter { FoodSearch.availableForAdding($0) && seen.insert($0.id).inserted }.map(Entry.init)
        }
        func suggestions(query: String, language: AppLanguage, history: Index = Index([]), limit: Int = 6) -> [FoodSuggestion] {
        guard limit > 0 else { return [] }
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = FoodSearch.normalized(typed)
        let words = normalized.split(separator: " ").map(String.init)
        let hasQuery = !words.isEmpty
        var candidates: [Candidate] = []
        var position = 0

        func append(_ label: String, query phrase: String, kind: FoodSuggestion.Kind,
                    sourcePriority: Int, rank: Int) {
            let value = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = FoodSearch.normalized(value)
            guard !key.isEmpty, !hasQuery || key != normalized else { return }
            candidates.append(Candidate(label: label, query: value, normalized: key,
                                        kind: kind, rank: rank, priority: sourcePriority,
                                        position: position))
            position += 1
        }

        func addFoods(_ values: [Entry], kind: FoodSuggestion.Kind, priority: Int) {
            for (position, entry) in values.enumerated() {
                if position.isMultiple(of: 64), Task.isCancelled { return }
                let preferred = language == .ar ? entry.ar : entry.en
                guard !preferred.isEmpty else { continue }
                let fields = language == .ar ? entry.arFields : entry.enFields
                let combined = language == .ar ? entry.arQuery : entry.enQuery
                if !hasQuery {
                    append(preferred, query: combined, kind: kind, sourcePriority: priority, rank: 0)
                } else {
                    let matches = fields.enumerated().compactMap { offset, field -> (String, Int, Int)? in
                        guard let rank = matchRank(field, query: normalized, words: words) else { return nil }
                        return (field.value, rank, offset)
                    }.sorted { lhs, rhs in lhs.1 == rhs.1 ? lhs.2 < rhs.2 : lhs.1 < rhs.1 }
                    if let best = matches.first {
                        // Complete names preserve brand specificity; aliases stay useful
                        // when an alternate spelling is what the user is completing.
                        let phrase = best.2 < 3 ? combined : best.0
                        append(preferred, query: phrase, kind: kind, sourcePriority: priority, rank: best.1)
                    } else if words.allSatisfy({ word in entry.text.contains(word) || entry.tokens.contains(where: { $0.hasPrefix(FoodSearch.token(word)) }) }) {
                        // A query may span the product title, its brand and aliases.
                        append(preferred, query: combined, kind: kind, sourcePriority: priority, rank: 3)
                    }
                }
                for brand in entry.brands {
                    if !hasQuery {
                        append(brand.value, query: brand.value, kind: .brand, sourcePriority: priority + 2, rank: 0)
                    } else if let rank = matchRank(brand, query: normalized, words: words) {
                        append(brand.value, query: brand.value, kind: .brand, sourcePriority: priority + 2, rank: rank)
                    }
                }
            }
        }

        addFoods(history.entries, kind: .history, priority: 0)
        addFoods(entries, kind: .local, priority: 1)
        // These are independently chosen search terms, with no nutrient values
        // or proprietary product IDs. A category opens the ordinary OFF search.
        for (ar, en) in [("حليب", "Milk"), ("خبز", "Bread"), ("زبادي", "Yogurt"),
                         ("أرز", "Rice"), ("دجاج", "Chicken"), ("فاكهة", "Fruit")] {
            let label = language.text(ar, en)
            if !hasQuery {
                append(label, query: label, kind: .popular, sourcePriority: 4, rank: 0)
            } else {
                let ranks = [ar, en].compactMap { matchRank(Field($0), query: normalized, words: words) }
                if let rank = ranks.min() {
                    append(label, query: label, kind: .popular, sourcePriority: 4, rank: rank)
                }
            }
        }
        candidates.sort { lhs, rhs in
            if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            return lhs.position < rhs.position
        }
        let suggestionLimit = hasQuery ? limit - 1 : limit
        var seen = Set<String>()
        var result: [FoodSuggestion] = []
        for item in candidates where result.count < suggestionLimit {
            guard seen.insert(item.normalized).inserted else { continue }
            result.append(FoodSuggestion(id: "query:" + item.normalized, label: item.label,
                                         query: item.query, kind: item.kind))
        }
        if hasQuery {
            result.append(FoodSuggestion(id: "all:" + normalized,
                label: language.text("البحث عن «\(typed)»", "Search all for “\(typed)”"),
                query: typed, kind: .searchAll))
        }
        return result
        }
    }

    private struct Field {
        let value: String
        let normalized: String
        let tokens: [String]
        init(_ value: String) {
            self.value = value; normalized = FoodSearch.normalized(value)
            tokens = normalized.split(separator: " ").map { FoodSearch.token(String($0)) }
        }
    }
    private struct Entry {
        let ar: String; let en: String; let arQuery: String; let enQuery: String
        let arFields: [Field]; let enFields: [Field]; let brands: [Field]
        let text: String; let tokens: [String]
        init(_ food: Food) {
            ar = food.label(.ar).trimmingCharacters(in: .whitespacesAndNewlines)
            en = food.label(.en).trimmingCharacters(in: .whitespacesAndNewlines)
            arQuery = queryForFood(food, language: .ar); enQuery = queryForFood(food, language: .en)
            let aliases = split(food.aliases ?? "")
            arFields = ([ar, food.name, food.nameEn ?? ""] + aliases).map(Field.init)
            enFields = ([en, food.name, food.nameEn ?? ""] + aliases).map(Field.init)
            brands = split(food.brand ?? "").map(Field.init)
            text = (arFields + brands).map(\.normalized).joined(separator: " ")
            tokens = Array(Set(text.split(separator: " ").map { FoodSearch.token(String($0)) }))
        }
    }

    private struct Candidate {
        let label: String; let query: String; let normalized: String
        let kind: FoodSuggestion.Kind; let rank: Int; let priority: Int; let position: Int
    }

    private static func split(_ text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: ",،;؛|\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func queryForFood(_ food: Food, language: AppLanguage) -> String {
        let label = food.label(language).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let brand = split(food.brand ?? "").first,
              !FoodSearch.normalized(label).contains(FoodSearch.normalized(brand)) else { return label }
        return label + " " + brand
    }

    private static func matchRank(_ field: Field, query: String, words: [String]) -> Int? {
        let value = field.normalized
        guard !value.isEmpty else { return nil }
        if value.hasPrefix(query) { return 0 }
        if words.allSatisfy({ word in field.tokens.contains(where: { $0.hasPrefix(FoodSearch.token(word)) }) }) { return 1 }
        if words.allSatisfy({ value.contains($0) }) { return 2 }
        return nil
    }
}
