import Foundation

enum AppLanguage: String, Codable, CaseIterable { case ar, en
    func text(_ ar: String, _ en: String) -> String { DisplayFormat.westernDigits(self == .ar ? ar : en) }
}
enum AppError: LocalizedError {
    case invalid(String, String)
    var errorDescription: String? { if case let .invalid(ar, _) = self { return ar }; return nil }
    func message(_ language: AppLanguage) -> String { if case let .invalid(ar, en) = self { return language.text(ar, en) }; return "" }
}
enum FoodUnit: String, Codable, CaseIterable { case g, ml, serving
    func label(_ l: AppLanguage) -> String { switch self { case .g: return l.text("جم", "g"); case .ml: return l.text("مل", "ml"); case .serving: return l.text("حصة", "serving") } }
}
enum Meal: String, Codable, CaseIterable, Identifiable { case breakfast, lunch, dinner, snack
    var id: String { rawValue }
    var symbol: String { switch self { case .breakfast: return "sun.max"; case .lunch: return "sun.haze"; case .dinner: return "moon"; case .snack: return "apple.logo" } }
    func label(_ l: AppLanguage) -> String { switch self { case .breakfast: return l.text("الفطور", "Breakfast"); case .lunch: return l.text("الغداء", "Lunch"); case .dinner: return l.text("العشاء", "Dinner"); case .snack: return l.text("سناك", "Snack") } }
}
struct Nutrition: Codable, Equatable {
    var kcal: Double; var protein: Double; var carbs: Double; var fat: Double
    static let zero = Nutrition(kcal: 0, protein: 0, carbs: 0, fat: 0)
    static let initial = Nutrition(kcal: 2000, protein: 125, carbs: 225, fat: 600 / 9)
    var valid: Bool { [kcal,protein,carbs,fat].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 100000 } }
    var macroCalories: Double { protein * 4 + carbs * 4 + fat * 9 }
    func scaled(_ scale: Double) -> Nutrition { Nutrition(kcal:kcal*scale,protein:protein*scale,carbs:carbs*scale,fat:fat*scale) }
    static func + (a: Nutrition, b: Nutrition) -> Nutrition { Nutrition(kcal:a.kcal+b.kcal,protein:a.protein+b.protein,carbs:a.carbs+b.carbs,fat:a.fat+b.fat) }
}
struct FoodServing: Codable, Equatable, Identifiable {
    var id: String; var label: String; var grams: Double
    var valid: Bool { !id.isEmpty && id.count <= 100 && !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && label.count <= 240 && grams.isFinite && grams > 0 && grams <= 10000 }
}
/// A declared portion can be a cup, slice or another source label; it is not
/// interchangeable with a gram weight. Missing source nutrition stays unknown.
struct FoodPortionChoice: Codable, Equatable, Identifiable {
    var id: String; var label: String; var quantity: Double; var unit: String
    var nutritionMultiplier: Double; var nutrition: Nutrition?
    var valid: Bool {
        !id.isEmpty && id.count <= 100 && !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && label.count <= 240 &&
        !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && unit.count <= 240 &&
        quantity.isFinite && quantity > 0 && quantity <= 10000 &&
        nutritionMultiplier.isFinite && nutritionMultiplier > 0 && nutritionMultiplier <= 100000 &&
        (nutrition == nil || nutrition?.valid == true)
    }
}
struct Food: Codable, Equatable, Identifiable {
    var catalogID: String?; var name: String; var nameEn: String?; var aliases: String?; var brand: String?; var barcode: String?
    var unit: FoodUnit; var kcal: Double?; var protein: Double?; var carbs: Double?; var fat: Double?
    var serving: String?; var servingQuantity: Double?; var servingUnit: String?; var servingNutrition: Nutrition?
    var servings: [FoodServing]?
    var portions: [FoodPortionChoice]?
    var selectedPortionID: String?
    var source: String?; var sourceId: String?; var sourceDescription: String?
    var id: String { barcode.map { "barcode:"+$0 } ?? catalogID ?? TextSearch.normalized(name + (brand ?? "")) }
    var per100: Nutrition? { guard let k=kcal,let p=protein,let c=carbs,let f=fat else { return nil }; let v=Nutrition(kcal:k,protein:p,carbs:c,fat:f); return v.valid ? v : nil }
    func label(_ l: AppLanguage) -> String { DisplayFormat.westernDigits(l == .en ? nameEn ?? name : name) }
    var servingChoices: [FoodServing] { unit == .g && per100 != nil ? (servings ?? []).filter(\.valid) : [] }
    var portionChoices: [FoodPortionChoice] { (portions ?? []).filter(\.valid) }
    func values(for u: FoodUnit) -> Nutrition? { u == .serving ? servingNutrition ?? (unit == .serving ? per100 : servingChoices.first.flatMap { per100?.scaled($0.grams / 100) }) : (u == unit ? per100 : nil) }
    var units: [FoodUnit] { [unit] + (unit != .serving && values(for: .serving) != nil ? [.serving] : []) }
    var additionUnits: [FoodUnit] { [.serving] + (unit == .serving ? [] : [unit]) }
    var defaultAdditionUnit: FoodUnit { .serving }
    func selectingPortion(_ choice: FoodPortionChoice) throws -> Food {
        guard choice.valid, portionChoices.contains(choice) else {
            throw AppError.invalid("اختر حصة من حصص هذا الطعام.", "Choose a portion declared for this food.")
        }
        var result = self
        result.unit = .serving; result.serving = choice.label
        result.selectedPortionID = choice.id
        result.servingQuantity = choice.quantity; result.servingUnit = choice.unit
        result.servingNutrition = choice.nutrition
        result.kcal = choice.nutrition?.kcal; result.protein = choice.nutrition?.protein
        result.carbs = choice.nutrition?.carbs; result.fat = choice.nutrition?.fat
        return result
    }
    func definingServing(quantity: Double, unit servingBasis: FoodUnit, label: String) throws -> Food {
        guard servingBasis != .serving, servingBasis == unit, quantity.isFinite, quantity > 0, quantity <= 10000,
              let reference = per100, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              label.count <= 240 else { throw AppError.invalid("حدد وزن أو حجم الحصة بوحدة المنتج.", "Set the serving weight or volume in the product's unit.") }
        var result = self
        result.serving = label; result.servingQuantity = quantity; result.servingUnit = servingBasis.rawValue
        result.servingNutrition = reference.scaled(quantity / 100)
        return result
    }
    func selecting(_ choice: FoodServing) throws -> Food {
        guard choice.valid, unit == .g, let nutrition = per100, servingChoices.contains(choice) else { throw AppError.invalid("اختر حصة صالحة من حصص الطعام.", "Choose a valid serving from this food.") }
        var result = self; result.serving = choice.label; result.servingQuantity = choice.grams; result.servingUnit = "g"; result.servingNutrition = nutrition.scaled(choice.grams / 100)
        return result
    }
    func withReference(_ nutrition: Nutrition, unit referenceUnit: FoodUnit) throws -> Food {
        if source == MealPhotoEstimate.source {
            guard referenceUnit == .serving else { throw AppError.invalid("عدّل قيم الحصة التقديرية.", "Edit the estimated serving values.") }
            return try MealPhotoEstimate.correctedFood(self, nutrition: nutrition)
        }
        guard nutrition.valid else { throw AppError.invalid("أدخل قيمًا غذائية صحيحة.", "Enter valid nutrition values.") }
        var result = self
        if referenceUnit == .serving {
            result.servingNutrition = nutrition
            if let selected = result.selectedPortionID,
               let index = result.portions?.firstIndex(where: { $0.id == selected }) {
                result.portions?[index].nutrition = nutrition
            }
            if result.unit != .serving { return result }
        } else {
            if let grams = servingQuantity, servingUnit == referenceUnit.rawValue, grams.isFinite, grams > 0, grams <= 10000 {
                result.servingNutrition = nutrition.scaled(grams / 100)
            } else { result.servingNutrition = nil }
        }
        result.unit = referenceUnit; result.kcal = nutrition.kcal; result.protein = nutrition.protein; result.carbs = nutrition.carbs; result.fat = nutrition.fat
        return result
    }
    func total(_ amount: Double, unit u: FoodUnit) throws -> Nutrition {
        guard amount.isFinite,amount>0,amount<=10000,let values=values(for:u),values.valid else { throw AppError.invalid("أكمل القيم الغذائية وأدخل كمية صحيحة.","Complete nutrition and enter a valid amount.") }
        return values.scaled(u == .serving ? amount : amount/100)
    }
    enum CodingKeys: String, CodingKey { case catalogID="id", name,nameEn,aliases,brand,barcode,unit,kcal,protein,carbs,fat,serving,servingQuantity,servingUnit,servingNutrition,servings,portions,selectedPortionID,source,sourceId,sourceDescription }
    init(catalogID:String?=nil,name:String,nameEn:String?=nil,aliases:String?=nil,brand:String?=nil,barcode:String?=nil,unit:FoodUnit = .g,nutrition:Nutrition?=nil,serving:String?=nil,servingQuantity:Double?=nil,servingUnit:String?=nil,servingNutrition:Nutrition?=nil,source:String?=nil) {
        self.catalogID=catalogID;self.name=name;self.nameEn=nameEn;self.aliases=aliases;self.brand=brand;self.barcode=barcode;self.unit=unit;self.kcal=nutrition?.kcal;self.protein=nutrition?.protein;self.carbs=nutrition?.carbs;self.fat=nutrition?.fat;self.serving=serving;self.servingQuantity=servingQuantity;self.servingUnit=servingUnit;self.servingNutrition=servingNutrition;self.source=source
    }
}
struct DiaryEntry: Codable, Identifiable, Equatable {
    var id: UUID;var day: String;var meal: Meal;var name: String;var amount: Double;var unit: FoodUnit;var kcal: Double;var protein: Double;var carbs: Double;var fat: Double;var barcode: String?;var created: String?;var foodID: String?;var servingLabel: String?
    var nutrition: Nutrition { Nutrition(kcal:kcal,protein:protein,carbs:carbs,fat:fat) }
    func unitLabel(_ language: AppLanguage) -> String { DisplayFormat.westernDigits(unit == .serving ? servingLabel ?? unit.label(language) : unit.label(language)) }
    init(food: Food,amount: Double,unit: FoodUnit,meal: Meal,day: String,language:AppLanguage) throws { let n=try food.total(amount,unit:unit);self.id=UUID();self.day=day;self.meal=meal;self.name=food.label(language);self.amount=amount;self.unit=unit;self.kcal=n.kcal;self.protein=n.protein;self.carbs=n.carbs;self.fat=n.fat;self.barcode=food.barcode;self.created=ISO8601DateFormatter().string(from:Date());self.foodID=food.id;self.servingLabel=unit == .serving ? food.serving ?? food.servingChoices.first?.label : nil }
    mutating func resize(_ newAmount:Double) throws { guard amount>0,newAmount.isFinite,newAmount>0,newAmount<=10000 else { throw AppError.invalid("أدخل كمية صحيحة.","Enter a valid amount.") };let n=nutrition.scaled(newAmount/amount);amount=newAmount;kcal=n.kcal;protein=n.protein;carbs=n.carbs;fat=n.fat }
}
struct Ingredient: Codable, Identifiable, Equatable { var id:UUID;var name:String;var amount:Double;var unit:FoodUnit;var kcal:Double;var protein:Double;var carbs:Double;var fat:Double
    var nutrition:Nutrition { Nutrition(kcal:kcal,protein:protein,carbs:carbs,fat:fat) }
}
struct Recipe: Codable, Identifiable, Equatable { var id:UUID;var name:String;var type:String;var ingredients:[Ingredient];var portions:Double;var cookedWeight:Double?;var notes:String
    var importInfo:RecipeImportMetadata?=nil
    var total:Nutrition { ingredients.reduce(.zero){$0+$1.nutrition} }
    func food(byWeight:Bool=false) throws -> Food { guard !ingredients.isEmpty,portions.isFinite,portions>0,portions<=1000 else { throw AppError.invalid("أضف مكونات وعدد حصص صحيحًا.","Add ingredients and a valid yield.") };if byWeight { guard let w=cookedWeight,w.isFinite,w>0 else { throw AppError.invalid("أدخل وزن الوصفة النهائي.","Enter the final cooked weight.") };return Food(catalogID:id.uuidString,name:name,unit:.g,nutrition:total.scaled(100/w)) };return Food(catalogID:id.uuidString,name:name,unit:.serving,nutrition:total.scaled(1/portions),servingNutrition:total.scaled(1/portions)) }
}
struct WeightReading: Codable, Identifiable, Equatable { var day:String;var kg:Double;var source:String?;var timestamp:Double?
    var id:String { day }
}
struct DiarySnapshot: Codable {
    var version=2;var app="luqma";var entries:[DiaryEntry]=[];var goals:Nutrition = .initial;var recipes:[Recipe]=[];var weights:[WeightReading]=[];var products:[Food]=[];var searchHistory:[Food]=[];var barcodeHistory:[Food]=[];var customFoods:[Food]?;var weightPlan:WeightPlan?;var adaptive=false;var language:AppLanguage = .ar;var healthEnabled=false;var healthSync:HealthSyncState?
}
enum DayKey {
    static func string(_ date:Date) -> String { let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.calendar=Calendar(identifier:.gregorian);f.dateFormat="yyyy-MM-dd";return f.string(from:date) }
    static func date(_ value:String) -> Date? { let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.calendar=Calendar(identifier:.gregorian);f.timeZone=TimeZone(secondsFromGMT:0);f.dateFormat="yyyy-MM-dd";f.isLenient=false;return f.date(from:value) }
    static func valid(_ value:String) -> Bool { guard value.count==10,let d=date(value) else{return false};let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.timeZone=TimeZone(secondsFromGMT:0);f.dateFormat="yyyy-MM-dd";return f.string(from:d)==value }
    static var today:String { string(Date()) }
    static func localDate(_ value:String) -> Date? {let f=DateFormatter();f.locale=Locale(identifier:"en_US_POSIX");f.calendar=Calendar(identifier:.gregorian);f.timeZone = .current;f.dateFormat="yyyy-MM-dd";f.isLenient=false;return f.date(from:value)}
}
enum TextSearch {
    static func normalized(_ text:String) -> String { var s=text.lowercased().folding(options:[.diacriticInsensitive,.widthInsensitive],locale:Locale(identifier:"en"));for (a,b) in [("أ","ا"),("إ","ا"),("آ","ا"),("ٱ","ا"),("ى","ي"),("ة","ه"),("ـ","")] { s=s.replacingOccurrences(of:a,with:b) };for (i,c) in "٠١٢٣٤٥٦٧٨٩".enumerated(){s=s.replacingOccurrences(of:String(c),with:String(i))};return s }
    static func number(_ text:String) -> Double? { Double(normalized(text).replacingOccurrences(of:"٫",with:".").replacingOccurrences(of:",",with:".").trimmingCharacters(in:.whitespaces)) }
}
