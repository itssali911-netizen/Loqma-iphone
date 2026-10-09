import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

actor FoodDatabase {
    static let shared = FoodDatabase()
    private var catalog: [Food] = []
    init() { if let url=Bundle.main.url(forResource:"foods-data",withExtension:"json"),let data=try? Data(contentsOf:url) { catalog=(try? JSONDecoder().decode([Food].self,from:data)) ?? [] } }
    func local(_ query:String, cached:[Food]) -> [Food] {
        let words=TextSearch.normalized(query).split(separator:" ").map(String.init); guard !words.isEmpty else { return [] }
        var seen=Set<String>()
        return (Array(cached.reversed())+catalog).filter { f in let text=TextSearch.normalized([f.name,f.nameEn,f.aliases,f.brand].compactMap{$0}.joined(separator:" "));return words.allSatisfy { text.contains($0) } && seen.insert(f.id).inserted }.prefix(40).map{$0}
    }
    private func request(_ url:URL,allowMissing:Bool=false) async throws -> [String:Any] {
        var req=URLRequest(url:url); req.timeoutInterval=18;req.setValue("LuqmaIOS/1.0 (native calorie diary)",forHTTPHeaderField:"User-Agent")
        let (data,response)=try await URLSession.shared.data(for:req)
        if allowMissing,(response as? HTTPURLResponse)?.statusCode==404{return ["status":0]}
        guard let http=response as? HTTPURLResponse,(200...299).contains(http.statusCode),data.count<15*1024*1024,let json=try JSONSerialization.jsonObject(with:data) as? [String:Any] else { throw AppError.invalid("تعذّر الاتصال بقاعدة المنتجات. الأطعمة المحفوظة متاحة دون إنترنت.", "The product database could not be reached. Saved foods remain available offline.") }; return json
    }
    func barcode(_ raw:String,cached:[Food]) async throws -> Food? {
        let code=TextSearch.normalized(raw).filter { $0.isNumber }
        guard (8...14).contains(code.count),TextSearch.normalized(raw).trimmingCharacters(in:.whitespacesAndNewlines)==code else { throw AppError.invalid("أدخل رقم باركود من ٨ إلى ١٤ رقمًا.", "Enter a barcode of 8 to 14 digits.") }
        if let saved=cached.last(where:{$0.barcode==code}),saved.per100 != nil || saved.servingNutrition != nil { return saved }
        var url=URLComponents(string:"https://world.openfoodfacts.org/api/v2/product/\(code).json")!
        url.queryItems=[URLQueryItem(name:"fields",value:"code,product_name,product_name_ar,product_name_en,brands,nutriments,serving_size,serving_quantity,product_quantity_unit")]
        let json=try await request(url.url!,allowMissing:true);guard (json["status"] as? Int)==1,let p=json["product"] as? [String:Any] else { return nil };return Self.product(p)
    }
    func remote(_ query:String) async throws -> [Food] {
        var url=URLComponents(string:"https://world.openfoodfacts.org/cgi/search.pl")!
        url.queryItems=[URLQueryItem(name:"search_terms",value:query),URLQueryItem(name:"search_simple",value:"1"),URLQueryItem(name:"action",value:"process"),URLQueryItem(name:"json",value:"1"),URLQueryItem(name:"page_size",value:"20"),URLQueryItem(name:"fields",value:"code,product_name,product_name_ar,product_name_en,brands,nutriments,serving_size,serving_quantity,product_quantity_unit")]
        let json=try await request(url.url!);let products=(json["products"] as? [[String:Any]] ?? []).compactMap(Self.product)
        return products.sorted { (($0.per100 != nil || $0.servingNutrition != nil) ? 1:0) > (($1.per100 != nil || $1.servingNutrition != nil) ? 1:0) }
    }
    private static func product(_ p:[String:Any]) -> Food? {
        func text(_ key:String) -> String? { guard let s=p[key] as? String,!s.trimmingCharacters(in:.whitespaces).isEmpty else { return nil }; return String(s.prefix(180)) }
        guard let name=text("product_name_ar") ?? text("product_name") ?? text("product_name_en") else { return nil }
        let n=p["nutriments"] as? [String:Any] ?? [:]
        func number(_ key:String) -> Double? { let v=(n[key] as? NSNumber)?.doubleValue ?? (n[key] as? String).flatMap(Double.init);return v.flatMap { $0.isFinite && $0>=0 && $0<=100000 ? $0:nil } }
        func nutrition(_ suffix:String) -> Nutrition? {
            guard let k=number("energy-kcal_"+suffix) ?? (number("energy_"+suffix).map{$0/4.184}),let pr=number("proteins_"+suffix),let c=number("carbohydrates_"+suffix),let f=number("fat_"+suffix) else { return nil };return Nutrition(kcal:k,protein:pr,carbs:c,fat:f)
        }
        let serving=text("serving_size")
        let match=serving.flatMap { try? NSRegularExpression(pattern:"([0-9]+(?:[.,][0-9]+)?)\\s*(g|ml|gr|gram|grams)\\b",options:.caseInsensitive).firstMatch(in:$0,range:NSRange($0.startIndex...,in:$0)) }
        var quantity:Double?,servingUnit:String?
        if let serving,let match,let a=Range(match.range(at:1),in:serving),let b=Range(match.range(at:2),in:serving) { quantity=Double(serving[a].replacingOccurrences(of:",",with:"."));servingUnit=serving[b].lowercased()=="ml" ? "ml":"g" }
        let base:FoodUnit=(p["product_quantity_unit"] as? String)=="ml" || servingUnit=="ml" ? .ml:.g
        let per100=nutrition("100g"),direct=nutrition("serving")
        let calculated=quantity.flatMap { q in q>0 && servingUnit==base.rawValue ? per100?.scaled(q/100):nil }
        var food=Food(name:name,nameEn:text("product_name_en"),brand:text("brands"),barcode:text("code"),unit:base,nutrition:per100,serving:serving,servingQuantity:quantity,servingUnit:servingUnit,servingNutrition:direct ?? calculated,source:"OpenFoodFacts")
        if per100==nil && food.servingNutrition != nil { food.unit = .serving }
        return food
    }
}
