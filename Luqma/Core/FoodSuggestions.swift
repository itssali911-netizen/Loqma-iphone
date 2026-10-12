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
        guard limit > 0 else { return [] }
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = FoodSearch.normalized(typed)
        let words = normalized.split(separator: " ").map(String.init)
        let hasQuery = !words.isEmpty
        // Suggestions must not reintroduce old USDA caches or image estimates.
        let allowedHistory = history.filter(FoodSearch.availableForAdding)
        let allowedFoods = foods.filter(FoodSearch.availableForAdding)
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

        func addFoods(_ values: [Food], kind: FoodSuggestion.Kind, priority: Int) {
            var seen = Set<String>()
            for food in values where seen.insert(food.id).inserted {
                let preferred = food.label(language).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !preferred.isEmpty else { continue }
                let nameFields = [preferred, food.name, food.nameEn ?? ""]
                let aliases = split(food.aliases ?? "")
                let fields = nameFields + aliases
                let combined = queryForFood(food, language: language)
                if !hasQuery {
                    append(preferred, query: combined, kind: kind, sourcePriority: priority, rank: 0)
                } else {
                    let matches = fields.enumerated().compactMap { offset, field -> (String, Int, Int)? in
                        guard let rank = matchRank(field, query: normalized, words: words) else { return nil }
                        return (field, rank, offset)
                    }.sorted { lhs, rhs in lhs.1 == rhs.1 ? lhs.2 < rhs.2 : lhs.1 < rhs.1 }
                    if let best = matches.first {
                        // Complete names preserve brand specificity; aliases stay useful
                        // when an alternate spelling is what the user is completing.
                        let phrase = best.2 < nameFields.count ? combined : best.0
                        append(preferred, query: phrase, kind: kind, sourcePriority: priority, rank: best.1)
                    } else if FoodSearch.matches(food, query: typed) {
                        // A query may span the product title, its brand and aliases.
                        append(preferred, query: combined, kind: kind, sourcePriority: priority, rank: 3)
                    }
                }
                for brand in split(food.brand ?? "") {
                    if !hasQuery {
                        append(brand, query: brand, kind: .brand, sourcePriority: priority + 2, rank: 0)
                    } else if let rank = matchRank(brand, query: normalized, words: words) {
                        append(brand, query: brand, kind: .brand, sourcePriority: priority + 2, rank: rank)
                    }
                }
            }
        }

        addFoods(allowedHistory, kind: .history, priority: 0)
        addFoods(allowedFoods, kind: .local, priority: 1)
        // These are independently chosen search terms, with no nutrient values
        // or proprietary product IDs. A category opens the ordinary OFF search.
        for (ar, en) in [("حليب", "Milk"), ("خبز", "Bread"), ("زبادي", "Yogurt"),
                         ("أرز", "Rice"), ("دجاج", "Chicken"), ("فاكهة", "Fruit")] {
            let label = language.text(ar, en)
            if !hasQuery {
                append(label, query: label, kind: .popular, sourcePriority: 4, rank: 0)
            } else {
                let ranks = [ar, en].compactMap { matchRank($0, query: normalized, words: words) }
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

    private static func matchRank(_ field: String, query: String, words: [String]) -> Int? {
        let value = FoodSearch.normalized(field)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix(query) { return 0 }
        let fieldWords = value.split(separator: " ").map(String.init)
        if words.allSatisfy({ word in fieldWords.contains(where: { $0.hasPrefix(word) }) }) { return 1 }
        if words.allSatisfy({ value.contains($0) }) { return 2 }
        return nil
    }
}
