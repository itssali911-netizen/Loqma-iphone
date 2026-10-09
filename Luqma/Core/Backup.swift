import Foundation

enum DiaryValidation {
    static func check(_ s: DiarySnapshot) throws {
        func require(_ ok: Bool) throws { if !ok { throw AppError.invalid("راجع البيانات والكميات؛ توجد قيم غير صالحة ولم يُغيّر سجلك.", "Check the data and quantities. Some values are invalid; your diary was not changed.") } }
        try require(s.app == "luqma" && s.version == 2 && s.entries.count <= 50000 && s.recipes.count <= 50000 && s.weights.count <= 50000 && s.products.count <= 1000 && s.searchHistory.count <= 30 && s.barcodeHistory.count <= 30)
        try require(s.goals.valid && (500...10000).contains(s.goals.kcal))
        try require(Set(s.entries.map(\.id)).count == s.entries.count && Set(s.recipes.map(\.id)).count == s.recipes.count && Set(s.weights.map(\.day)).count == s.weights.count)
        for e in s.entries { try require(DayKey.valid(e.day) && !e.name.trimmingCharacters(in: .whitespaces).isEmpty && e.name.count <= 180 && e.amount.isFinite && e.amount > 0 && e.amount <= 10000 && e.nutrition.valid && (e.barcode?.count ?? 0) <= 20) }
        for r in s.recipes {
            try require(!r.name.trimmingCharacters(in: .whitespaces).isEmpty && r.name.count <= 180 && ["recipe", "meal", "prep"].contains(r.type) && (1...80).contains(r.ingredients.count) && Set(r.ingredients.map(\.id)).count == r.ingredients.count && r.portions.isFinite && r.portions > 0 && r.portions <= 1000 && r.notes.count <= 2000 && r.total.valid)
            try require(r.cookedWeight.map { $0.isFinite && $0 > 0 && $0 <= 100000 } ?? true)
            for i in r.ingredients { try require(!i.name.isEmpty && i.name.count <= 180 && i.amount.isFinite && i.amount > 0 && i.amount <= 10000 && i.nutrition.valid) }
        }
        for w in s.weights { try require(DayKey.valid(w.day) && w.kg.isFinite && (35...300).contains(w.kg) && (w.timestamp?.isFinite ?? true)) }
        for f in s.products + s.searchHistory + s.barcodeHistory {
            try require(!f.name.isEmpty && f.name.count <= 180 && (f.barcode?.count ?? 0) <= 20)
            try require([f.kcal,f.protein,f.carbs,f.fat].allSatisfy { $0.map { $0.isFinite && $0 >= 0 && $0 <= 100000 } ?? true })
            try require(f.servingNutrition?.valid ?? true)
        }
        if let p = s.weightPlan { try p.validate() }
    }
    static func average(_ weights: [WeightReading], ending: String, days: Int = 7) -> (count: Int, kg: Double?) {
        let range = weights.filter { let n = WeightModel.days($0.day, ending); return n >= 0 && n < days }
        return (range.count, range.isEmpty ? nil : range.reduce(0) { $0 + $1.kg } / Double(range.count))
    }
}

enum Backup {
    static func encode(_ snapshot: DiarySnapshot) throws -> Data {
        try DiaryValidation.check(snapshot)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        return try encoder.encode(snapshot)
    }
    static func decode(_ data: Data) throws -> DiarySnapshot {
        guard data.count <= 50 * 1024 * 1024, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["app"] as? String == "luqma" else { throw AppError.invalid("اختر نسخة JSON من لُقمة.", "Choose a Luqma JSON backup.") }
        let decoder = JSONDecoder()
        func decode<T: Decodable>(_ type: T.Type, _ value: Any) throws -> T { try decoder.decode(type, from: JSONSerialization.data(withJSONObject: value)) }
        var result: DiarySnapshot
        if object["version"] as? Int == 2 { result = try decoder.decode(DiarySnapshot.self, from: data) }
        else if object["version"] as? Int == 1 {
            result = DiarySnapshot()
            guard let entries = object["entries"], let resources = object["resources"] as? [[String: Any]], let products = object["products"], let history = object["history"] as? [String: Any], let search = history["search"], let barcode = history["barcode"] else { throw AppError.invalid("نسخة الموقع غير مكتملة.", "The website backup is incomplete.") }
            result.entries = try decode([DiaryEntry].self, entries)
            if let goals = object["goals"], !(goals is NSNull) { result.goals = try decode(Nutrition.self, goals) }
            result.products = try decode([Food].self, products)
            result.searchHistory = try decode([Food].self, search); result.barcodeHistory = try decode([Food].self, barcode)
            for item in resources {
                guard let kind = item["kind"] as? String, var payload = item["data"] as? [String: Any] else { throw AppError.invalid("تعذّر قراءة السجل.", "The resource could not be read.") }
                switch kind {
                case "recipe": payload["id"] = item["id"]; result.recipes.append(try decode(Recipe.self, payload))
                case "weight": result.weights.append(try decode(WeightReading.self, payload))
                case "weight-plan": result.weightPlan = try decode(WeightPlan.self, payload)
                case "preferences": result.adaptive = payload["adaptive"] as? Bool ?? false
                case "person": break // Old static profile is superseded by the NIDDK plan.
                default: throw AppError.invalid("نوع بيانات غير مدعوم.", "Unsupported resource type.")
                }
            }
        } else { throw AppError.invalid("إصدار النسخة غير مدعوم.", "Unsupported backup version.") }
        try DiaryValidation.check(result); result.goals = result.goals.balanced(); return result
    }
    static func merge(_ incoming: DiarySnapshot, into current: DiarySnapshot) throws -> DiarySnapshot {
        try DiaryValidation.check(incoming); var result = current
        func combine<T, ID: Hashable>(_ a: [T], _ b: [T], id: (T) -> ID) -> [T] { var output = a; for item in b { if let index = output.firstIndex(where: { id($0) == id(item) }) { output[index] = item } else { output.append(item) } }; return output }
        result.entries = combine(result.entries, incoming.entries, id: { $0.id })
        result.recipes = combine(result.recipes, incoming.recipes, id: { $0.id })
        result.weights = combine(result.weights, incoming.weights, id: { $0.day }).sorted { $0.day < $1.day }
        result.products = Array(combine(result.products,incoming.products,id: { $0.id }).suffix(1000))
        result.searchHistory = Array(combine(result.searchHistory,incoming.searchHistory,id: { $0.id }).suffix(30))
        result.barcodeHistory = Array(combine(result.barcodeHistory,incoming.barcodeHistory,id: { $0.id }).suffix(30))
        result.goals = incoming.goals.balanced(); result.weightPlan = incoming.weightPlan ?? current.weightPlan
        result.adaptive = incoming.adaptive && result.weightPlan != nil
        try DiaryValidation.check(result); return result
    }
}
