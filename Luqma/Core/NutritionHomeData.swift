import Foundation

/// Presentation only: no extra diary, recommendation service or nutrition store.
enum NutritionHomeCategory:String,CaseIterable,Identifiable,Sendable {
    case vegetables,meat,fruit,all
    var id:String {rawValue}
    func label(_ language:AppLanguage)->String {
        switch self {
        case .vegetables:return language.text("خضروات","Vegetable")
        case .meat:return language.text("لحوم","Meat")
        case .fruit:return language.text("فواكه","Fruit")
        case .all:return language.text("مأكولات","Meals")
        }
    }
    func matches(_ text:String)->Bool {
        if self == .all{return true}
        let name=FoodSearch.normalized(text)
        let terms:[String]
        switch self {
        case .vegetables:terms=["خضار","خضروات","بروكلي","خيار","سلطه","جزر","vegetable","broccoli","salad","carrot","cucumber"]
        case .meat:terms=["دجاج","لحم","ديك","سلمون","سمك","تونه","chicken","beef","meat","salmon","fish","tuna","turkey"]
        case .fruit:terms=["فواكه","تفاح","موز","توت","برتقال","تمر","fruit","apple","banana","berry","orange","date"]
        case .all:terms=[]
        }
        // Categories describe whole ingredients. Substring matching classified
        // موزاريلا as موز and an English "update" as a date fruit.
        let words=name.split(separator:" ").map(String.init)
        return terms.contains { term in
            let normalized=FoodSearch.normalized(term)
            return words.contains { word in
                if word==normalized{return true}
                if word==normalized+"s" || (normalized.hasSuffix("y") && word==String(normalized.dropLast())+"ies"){return true}
                return ["ال","وال","بال"].contains{word==$0+normalized}
            }
        }
    }
}

/// Reference examples have only declared display metadata. They deliberately
/// cannot become a Food or enter the user's diary without complete input.
struct NutritionHomeExample:Identifiable {
    var id:String
    var nameAr:String
    var nameEn:String
    var kcal:Double
    var proteinLabel:String
    var preparationMinutes:Int?
    var rating:Double?
    var artwork:String
    static let morning:[Self]=[
        .init(id:"morning-broccoli",nameAr:"بروكلي وباستا",nameEn:"Broccoli & Pasta",kcal:181,proteinLabel:"5mg protein",preparationMinutes:nil,rating:nil,artwork:"LuqmaEditorialBreakfast"),
        .init(id:"morning-almond",nameAr:"وعاء اللوز",nameEn:"Almond Bowl",kcal:200,proteinLabel:"60mg protein",preparationMinutes:nil,rating:nil,artwork:"LuqmaEditorialSnack")
    ]
    static let featured:[Self]=[
        .init(id:"tokyo-ramen",nameAr:"رامن على الطريقة الطوكيوية",nameEn:"Tokyo Style Ramen",kcal:251,proteinLabel:"2g protein",preparationMinutes:30,rating:nil,artwork:"LuqmaEditorialLunch"),
        .init(id:"grilled-salmon-special",nameAr:"وعاء السلمون المشوي",nameEn:"Grilled Salmon Bowl",kcal:310,proteinLabel:"28g protein",preparationMinutes:20,rating:nil,artwork:"LuqmaEditorialDinner")
    ]
    static let browse:[Self]=[
        .init(id:"fried-broccoli",nameAr:"بروكلي مقلي ومكسرات مع جبنة موزاريلا",nameEn:"Fried Brocolli & Nuts With Cheese Mozarella",kcal:251,proteinLabel:"14g protein",preparationMinutes:30,rating:4.5,artwork:"LuqmaEditorialBreakfast"),
        .init(id:"salmon-meat",nameAr:"سلمون مع بيض عيون وجواكامولي",nameEn:"Salmon Meat with Sunny Side Egg & Guacamole",kcal:187,proteinLabel:"",preparationMinutes:15,rating:4.1,artwork:"LuqmaEditorialDinner"),
        .init(id:"meta-meat",nameAr:"وجبة ميتا لحم دايت مع الخضار الطازجة",nameEn:"Meta Meat Diet with Ox Skin & Fresh Sandalwood",kcal:351,proteinLabel:"",preparationMinutes:80,rating:4.8,artwork:"LuqmaEditorialLunch")
    ]
}

struct NutritionHomeCard:Identifiable {
    enum Origin {case entry(DiaryEntry),recipe(Recipe),saved(Food),example(NutritionHomeExample)}
    let origin:Origin
    var id:String {
        switch origin {case .entry(let e):return "entry:"+e.id.uuidString;case .recipe(let r):return "recipe:"+r.id.uuidString;case .saved(let f):return "food:"+f.id;case .example(let e):return "example:"+e.id}
    }
    var isExample:Bool {if case .example=origin{return true};return false}
    func name(_ language:AppLanguage)->String {
        switch origin {
        case .entry(let e):return DisplayFormat.westernDigits(e.name)
        case .recipe(let r):return DisplayFormat.westernDigits(r.name)
        case .saved(let f):return f.label(language)
        case .example(let e):return language.text(e.nameAr,e.nameEn)
        }
    }
    var nutrition:Nutrition? {
        switch origin {case .entry(let e):return e.nutrition;case .recipe(let r):return try? r.food().values(for:.serving);case .saved(let f):return f.values(for:.serving) ?? f.per100;case .example:return nil}
    }
    var kcal:Double? {if case .example(let e)=origin{return e.kcal};return nutrition?.kcal}
    var preparationMinutes:Int? {if case .example(let e)=origin{return e.preparationMinutes};return nil}
    var rating:Double? {if case .example(let e)=origin{return e.rating};return nil}
    var artwork:String {
        if case .example(let e)=origin{return e.artwork}
        if case .entry(let e)=origin {
            switch e.meal {case .breakfast:return "LuqmaEditorialBreakfast";case .lunch:return "LuqmaEditorialLunch";case .dinner:return "LuqmaEditorialDinner";case .snack:return "LuqmaEditorialSnack"}
        }
        return "LuqmaEditorialLunch"
    }
    /// Existing nutrition semantics own conversion and portion selection.
    var food:Food? {
        switch origin {
        case .saved(let f):return f
        case .recipe(let r):return try? r.food()
        case .entry(let e):return Food(catalogID:e.foodID ?? "home-entry:"+e.id.uuidString,name:e.name,unit:.serving,nutrition:e.nutrition,serving:e.servingLabel,servingNutrition:e.nutrition,source:"Saved diary entry")
        case .example:return nil
        }
    }
    func matchingEntry(in entries:[DiaryEntry],day:String)->DiaryEntry? {
        if case .entry(let original)=origin{return entries.first{$0.day==day && $0.id==original.id}}
        guard let food else{return nil}
        return entries.first{$0.day==day && $0.foodID==food.id}
    }
    func proteinLabel(_ language:AppLanguage)->String {
        if let nutrition{return DisplayFormat.decimal(nutrition.protein,digits:1)+language.text(" جم بروتين","g protein")}
        if case .example(let e)=origin,!e.proteinLabel.isEmpty{return e.proteinLabel}
        return "—"
    }
}

struct NutritionHomeSnapshot {
    let entries:[DiaryEntry]
    let consumed:Nutrition
    let morning:[NutritionHomeCard]
    let featured:[NutritionHomeCard]
    let browse:[NutritionHomeCard]
    let searchIndex:NutritionHomeSearchIndex
    init(state:DiarySnapshot,day:String) {
        entries=state.entries.filter{$0.day==day}
        consumed=entries.reduce(.zero){$0+$1.nutrition}
        let recorded=entries.reversed().map{NutritionHomeCard(origin:.entry($0))}
        let recipes=state.recipes.filter{(try? $0.food()) != nil}.map{NutritionHomeCard(origin:.recipe($0))}
        let recordedFoodIDs=Set(entries.compactMap(\.foodID))
        var seen=recordedFoodIDs
        let saved=((state.customFoods ?? [])+state.products+state.searchHistory).filter{FoodSearch.availableForAdding($0) && seen.insert($0.id).inserted}.map{NutritionHomeCard(origin:.saved($0))}
        let unloggedRecipes=recipes.filter{card in guard let food=card.food else{return false};return !recordedFoodIDs.contains(food.id)}
        let actual=recorded+unloggedRecipes+saved
        browse=actual.isEmpty ? NutritionHomeExample.browse.map{NutritionHomeCard(origin:.example($0))}:actual
        let breakfasts=entries.filter{$0.meal == .breakfast}.prefix(12).map{NutritionHomeCard(origin:.entry($0))}
        morning=breakfasts.isEmpty ? NutritionHomeExample.morning.map{NutritionHomeCard(origin:.example($0))}:breakfasts
        let available=recipes+saved+recorded
        featured=available.isEmpty ? NutritionHomeExample.featured.map{NutritionHomeCard(origin:.example($0))}:available
        searchIndex=NutritionHomeSearchIndex(cards:browse)
    }
    func filtered(category:NutritionHomeCategory,query:String,language:AppLanguage)->[NutritionHomeCard] {
        let words=FoodSearch.normalized(query).split(separator:" ").map(String.init)
        return browse.filter {card in
            let names=card.name(.ar)+" "+card.name(.en)
            let text=FoodSearch.normalized(names)
            return category.matches(names) && words.allSatisfy{text.contains($0)}
        }
    }
}

/// Only normalized strings/IDs cross the background filtering boundary. UI
/// state, DiaryStore and mutable persisted models never leave the main actor.
struct NutritionHomeSearchIndex:Sendable {
    struct Row:Sendable {let id:String;let normalized:String;let categories:Set<NutritionHomeCategory>}
    let rows:[Row]
    let revision:Int
    init(cards:[NutritionHomeCard]) {
        rows=cards.map{card in
            let name=card.name(.ar)+" "+card.name(.en)
            return Row(id:card.id,normalized:FoodSearch.normalized(name),categories:Set(NutritionHomeCategory.allCases.filter{$0.matches(name)}))
        }
        var hash=Hasher()
        for row in rows {hash.combine(row.id);hash.combine(row.normalized)}
        revision=hash.finalize()
    }
    func results(category:NutritionHomeCategory,query:String)->[String] {
        let words=FoodSearch.normalized(query).split(separator:" ").map(String.init)
        var matches:[String]=[]
        for row in rows {
            if Task.isCancelled{return []}
            if row.categories.contains(category) && words.allSatisfy({row.normalized.contains($0)}){matches.append(row.id)}
        }
        return matches
    }
}
