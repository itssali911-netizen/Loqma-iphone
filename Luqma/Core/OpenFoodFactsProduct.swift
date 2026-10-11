import Foundation
import CoreFoundation

/// Product details use OFF's versioned nutrition schema. Search summaries are
/// deliberately incomplete and must be resolved before a diary entry is added.
enum OpenFoodFactsProduct {
    static func parse(_ product: [String: Any]) -> Food? {
        func text(_ key: String) -> String? {
            let value = (product[key] as? String) ?? (product[key] as? [String])?.joined(separator: ", ")
            guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return String(value.prefix(180))
        }
        guard let code = text("code"), !code.isEmpty,
              code.allSatisfy({ "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ-_".contains($0) }),
              let name = text("product_name_ar") ?? text("product_name") ?? text("product_name_en") else { return nil }
        let barcode = (8...14).contains(code.count) && code.allSatisfy { "0123456789".contains($0) } ? code : nil
        let serving = text("serving_size")
        var portion = portionSize(serving)
        if portion == nil, let quantity = number(product["serving_quantity"]), quantity > 0, quantity <= 10_000,
           let unit = text("serving_quantity_unit"), ["g", "ml"].contains(unit) { portion = (quantity, unit) }
        let declared = text("nutrition_data_per")?.lowercased().replacingOccurrences(of: " ", with: "")
        var base: FoodUnit = declared == "100ml" ? .ml : declared == "100g" ? .g :
            (text("product_quantity_unit") == "ml" || portion?.unit == "ml" ? .ml : .g)
        var per100: Nutrition?, direct: Nutrition?, origin: String?
        var label = serving
        if let nutrition = product["nutrition"] as? [String: Any] {
            // Use label/manufacturer data only. OFF can also contain USDA and
            // model estimate sets; those are not this app's nutrient sources.
            let sets = (nutrition["input_sets"] as? [[String: Any]] ?? []).enumerated().compactMap { offset, raw -> NutrientSet? in
                guard ["manufacturer", "packaging"].contains(raw["source"] as? String ?? ""),
                      raw["preparation"] as? String == "as_sold", let set = NutrientSet(raw, offset: offset) else { return nil }
                return set
            }.sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                if (lhs.unit == base.rawValue) != (rhs.unit == base.rawValue) { return lhs.unit == base.rawValue }
                if lhs.isServing != rhs.isServing { return !lhs.isServing }
                return lhs.offset < rhs.offset
            }
            if let selected = sets.first {
                origin = selected.source
                if let unit = selected.unit { base = unit == "ml" ? .ml : .g }
                else { base = .serving }
                per100 = selected.per100
                let declaredServing = sets.first { $0.isServing && $0.source == selected.source && $0.unit == selected.unit }
                if let declaredServing {
                    direct = declaredServing.values
                    if let quantity = declaredServing.quantity, let unit = declaredServing.unit {
                        if portion?.quantity != quantity || portion?.unit != unit { label = amountLabel(quantity, unit: unit) }
                        portion = (quantity, unit)
                    }
                }
                if direct == nil, let portion, portion.unit == base.rawValue { direct = per100?.scaled(portion.quantity / 100) }
            } else if let aggregated = nutrition["aggregated_set"] as? [String: Any],
                      aggregated["preparation"] as? String == "as_sold",
                      ["100g", "100ml"].contains(aggregated["per"] as? String ?? ""),
                      let nutrients = aggregated["nutrients"] as? [String: Any],
                      let values = structuredNutrition(nutrients, requireLabelSource: true) {
                base = aggregated["per"] as? String == "100ml" ? .ml : .g
                per100 = values; origin = "label/manufacturer aggregate"
                if let portion, portion.unit == base.rawValue { direct = per100?.scaled(portion.quantity / 100) }
            }
        } else {
            // OFF's search index still returns the legacy flat nutriments map.
            // Its unit metadata is not authoritative; the service marks these
            // rows as summaries and loads current v3.6 details before adding.
            let nutrients = product["nutriments"] as? [String: Any] ?? [:]
            func legacy(_ suffix: String) -> Nutrition? {
                guard let kcal = number(nutrients["energy-kcal_" + suffix]) ??
                        ((number(nutrients["energy-kj_" + suffix]) ?? number(nutrients["energy_" + suffix])).map { $0 / 4.184 }),
                      let protein = number(nutrients["proteins_" + suffix]),
                      let carbs = number(nutrients["carbohydrates_" + suffix]), let fat = number(nutrients["fat_" + suffix]) else { return nil }
                return Nutrition(kcal: kcal, protein: protein, carbs: carbs, fat: fat)
            }
            per100 = legacy("100g"); direct = legacy("serving")
            if direct == nil, let portion, portion.unit == base.rawValue { direct = per100?.scaled(portion.quantity / 100) }
        }
        if per100 == nil && direct != nil { base = .serving }
        var food = Food(catalogID: "off:" + code, name: name, nameEn: text("product_name_en"), brand: text("brands"),
                        barcode: barcode, unit: base, nutrition: per100, serving: label,
                        servingQuantity: portion?.quantity, servingUnit: portion?.unit, servingNutrition: direct, source: "OpenFoodFacts")
        food.sourceId = code
        food.sourceDescription = origin.map { "Open Food Facts · " + $0 + " · as sold" }
        food.aliases = [text("product_name_ar"), text("product_name_en"), text("product_name")]
            .compactMap { $0 }.filter { $0 != name && $0 != food.nameEn }.joined(separator: " | ")
        return food
    }

    private struct NutrientSet {
        let values: Nutrition; let source: String; let unit: String?; let quantity: Double?
        let isServing: Bool; let offset: Int
        var priority: Int { source == "manufacturer" ? 0 : 1 }
        var per100: Nutrition? {
            guard let quantity, quantity > 0, unit != nil else { return nil }
            let normalized = values.scaled(100 / quantity)
            return normalized.valid ? normalized : nil
        }
        init?(_ raw: [String: Any], offset: Int) {
            guard let nutrients = raw["nutrients"] as? [String: Any], let values = OpenFoodFactsProduct.structuredNutrition(nutrients),
                  let per = raw["per"] as? String, ["100g", "100ml", "serving"].contains(per) else { return nil }
            self.values = values; self.source = raw["source"] as? String ?? ""; self.offset = offset
            isServing = per == "serving"
            if per == "100g" { unit = "g"; quantity = 100 }
            else if per == "100ml" { unit = "ml"; quantity = 100 }
            else {
                let value = OpenFoodFactsProduct.number(raw["per_quantity"])
                quantity = value.flatMap { $0 > 0 && $0 <= 10_000 ? $0 : nil }
                let supplied = raw["per_unit"] as? String
                unit = supplied.flatMap { ["g", "ml"].contains($0) ? $0 : nil }
            }
        }
    }

    private static func structuredNutrition(_ nutrients: [String: Any], requireLabelSource: Bool = false) -> Nutrition? {
        func nutrient(_ key: String, energy: Bool = false) -> Double? {
            guard let row = nutrients[key] as? [String: Any], let value = number(row["value"]),
                  let unit = row["unit"] as? String else { return nil }
            if requireLabelSource && !["manufacturer", "packaging"].contains(row["source"] as? String ?? "") { return nil }
            if energy {
                if unit.lowercased() == "kcal" { return value }
                if unit.lowercased() == "kj" { return value / 4.184 }
                return nil
            }
            switch unit.lowercased() {
            case "g": return value
            case "mg": return value / 1000
            case "µg", "μg", "ug": return value / 1_000_000
            default: return nil
            }
        }
        guard let kcal = nutrient("energy-kcal", energy: true) ?? nutrient("energy-kj", energy: true) ?? nutrient("energy", energy: true),
              let protein = nutrient("proteins"), let carbs = nutrient("carbohydrates"), let fat = nutrient("fat") else { return nil }
        let value = Nutrition(kcal: kcal, protein: protein, carbs: carbs, fat: fat)
        return value.valid ? value : nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() { return nil }
        let number = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
        return number.flatMap { $0.isFinite && $0 >= 0 && $0 <= 100_000 ? $0 : nil }
    }

    private static func portionSize(_ text: String?) -> (quantity: Double, unit: String)? {
        guard let text, let regex = try? NSRegularExpression(pattern: "([0-9]+(?:[.,][0-9]+)?)\\s*(g|ml|gr|gram|grams)\\b", options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let value = Range(match.range(at: 1), in: text), let unit = Range(match.range(at: 2), in: text),
              let amount = Double(text[value].replacingOccurrences(of: ",", with: ".")), amount > 0, amount <= 10_000 else { return nil }
        return (amount, text[unit].lowercased() == "ml" ? "ml" : "g")
    }

    private static func amountLabel(_ amount: Double, unit: String) -> String {
        "\(amount.rounded() == amount ? String(Int(amount)) : String(amount)) \(unit)"
    }
}
