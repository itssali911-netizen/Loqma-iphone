import Foundation

struct FoodUsage: Identifiable {
    let food: Food
    let count: Int
    let lastLogged: Date
    var id: String { food.id }
}

/// Diary usage is independent of opening a search result or scanning a barcode.
/// Rebuilding from entries also removes a food after its last log is deleted.
enum FoodHistory {
    static func usage(entries: [DiaryEntry], foods: [Food]) -> [FoodUsage] {
        let available = deduplicated(foods)
        let byID = Dictionary(uniqueKeysWithValues: available.map { ($0.id, $0) })
        var byName: [String: Set<String>] = [:]
        var byBarcode: [String: Set<String>] = [:]
        for food in available {
            for label in [food.name, food.nameEn].compactMap({ $0 }) {
                let name = FoodSearch.normalized(label)
                if !name.isEmpty { byName[name, default: []].insert(food.id) }
            }
            if let barcode = food.barcode, !barcode.isEmpty {
                byBarcode[barcode, default: []].insert(food.id)
            }
        }
        let standard = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var counts: [String: Int] = [:]
        var latest: [String: Date] = [:]
        for entry in entries {
            let identifier: String?
            if let foodID = entry.foodID, !foodID.isEmpty {
                // An unresolved explicit ID must not become a similarly named
                // product from another brand after the cached item is evicted.
                identifier = byID[foodID] == nil ? nil : foodID
            } else if let barcode = entry.barcode, !barcode.isEmpty {
                identifier = unique(byBarcode[barcode])
            } else {
                identifier = unique(byName[FoodSearch.normalized(entry.name)])
            }
            guard let identifier else { continue }
            let logged = entry.created.flatMap { standard.date(from: $0) ?? fractional.date(from: $0) }
                ?? DayKey.date(entry.day) ?? .distantPast
            counts[identifier, default: 0] += 1
            if latest[identifier].map({ logged > $0 }) ?? true { latest[identifier] = logged }
        }
        return counts.compactMap { identifier, count in
            guard let food = byID[identifier], let logged = latest[identifier] else { return nil }
            return FoodUsage(food: food, count: count, lastLogged: logged)
        }.sorted(by: moreRecent)
    }

    static func recent(entries: [DiaryEntry], foods: [Food]) -> [Food] {
        usage(entries: entries, foods: foods).map(\.food)
    }

    static func frequent(entries: [DiaryEntry], foods: [Food]) -> [Food] {
        usage(entries: entries, foods: foods).sorted(by: moreFrequent).map(\.food)
    }

    /// Resolve and parse diary timestamps once when preparing all three lists.
    /// Callers can run this on the food database actor and retain the result for UI.
    static func lists(in state: DiarySnapshot, catalog: [Food] = []) -> (recent: [Food], frequent: [Food], personal: [Food]) {
        let summaries = usage(entries: state.entries, foods: candidates(in: state, catalog: catalog))
        return (recent: summaries.map(\.food),
                frequent: summaries.sorted(by: moreFrequent).map(\.food),
                personal: yourFoods(in: state))
    }

    /// Old personal foods can live in the cache. New foods have their own
    /// persistent collection, so normal cache eviction cannot remove them.
    static func yourFoods(in state: DiarySnapshot) -> [Food] {
        let legacy = (state.barcodeHistory + state.searchHistory + state.products)
            .compactMap(personalFood)
        return Array(deduplicated(legacy + (state.customFoods ?? []).compactMap(personalFood)).reversed())
    }

    static func candidates(in state: DiarySnapshot, catalog: [Food] = []) -> [Food] {
        deduplicated(catalog + state.barcodeHistory + state.searchHistory + state.products + yourFoods(in: state))
            .filter { $0.source != MealPhotoEstimate.source || MealPhotoEstimate.isValidPhotoEstimate($0) }
    }

    /// Mutate a copy first, so a full personal collection leaves both the cache
    /// and personal foods untouched when the caller reports the error.
    static func remember(_ food: Food, in state: inout DiarySnapshot, barcode: Bool) throws {
        if food.source == MealPhotoEstimate.source && !MealPhotoEstimate.isValidPhotoEstimate(food) {
            throw AppError.invalid("بيانات تقدير الصورة غير متماسكة. راجع الوجبة قبل حفظها.", "The photo estimate is inconsistent. Review the meal before saving it.")
        }
        var next = state
        let remembered = personalFood(food) ?? food
        var custom = Array(yourFoods(in: next).reversed())
        guard custom.count <= 1000 else { throw personalCapacityError }
        if FoodSearch.isPersonalFood(remembered) {
            let existing = custom.contains { $0.id == remembered.id }
            guard existing || custom.count < 1000 else { throw personalCapacityError }
            custom.removeAll { $0.id == remembered.id }
            custom.append(remembered)
        }
        // Preserve old personal foods before any unrelated cache insert can
        // evict them, while keeping their original stable identifiers.
        if !custom.isEmpty || next.customFoods != nil { next.customFoods = custom }
        next.products.removeAll { $0.id == remembered.id }
        next.products.append(remembered)
        next.products = Array(next.products.suffix(1000))
        if barcode {
            next.barcodeHistory.removeAll { $0.id == remembered.id }
            next.barcodeHistory.append(remembered)
            next.barcodeHistory = Array(next.barcodeHistory.suffix(30))
        } else {
            next.searchHistory.removeAll { $0.id == remembered.id }
            next.searchHistory.append(remembered)
            next.searchHistory = Array(next.searchHistory.suffix(30))
        }
        state = next
    }

    private static func deduplicated(_ foods: [Food]) -> [Food] {
        var identifiers: [String] = []
        var latest: [String: Food] = [:]
        for food in foods {
            if latest[food.id] == nil { identifiers.append(food.id) }
            latest[food.id] = food
        }
        return identifiers.compactMap { latest[$0] }
    }

    private static func unique(_ identifiers: Set<String>?) -> String? {
        guard let identifiers, identifiers.count == 1 else { return nil }
        return identifiers.first
    }

    private static func personalFood(_ food: Food) -> Food? {
        if MealPhotoEstimate.isValidPhotoEstimate(food) { return food }
        // Version 1.3 manual foods had no source or external identifier.
        // Catalog items, recipes and legacy photo labels keep their origins.
        guard food.source == "Your food" || (food.source == nil && food.catalogID == nil && food.barcode == nil) else { return nil }
        var result = food
        result.source = "Your food"
        return result
    }

    private static func moreRecent(_ left: FoodUsage, _ right: FoodUsage) -> Bool {
        left.lastLogged == right.lastLogged ? left.id < right.id : left.lastLogged > right.lastLogged
    }

    private static func moreFrequent(_ left: FoodUsage, _ right: FoodUsage) -> Bool {
        left.count == right.count ? moreRecent(left, right) : left.count > right.count
    }

    private static var personalCapacityError: AppError {
        AppError.invalid("وصلت أطعمتك المحفوظة إلى ١٬٠٠٠ طعام. عدّل طعامًا موجودًا أو احذف أحدها قبل إضافة طعام جديد.",
                         "Your saved foods have reached 1,000 items. Edit or remove an existing food before adding another.")
    }
}
