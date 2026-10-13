import Foundation

struct PhotoFood: Codable, Identifiable {
    var id:String;var name:String;var nameEn:String;var grams:Double;var kcal:Double;var protein:Double;var carbs:Double;var fat:Double
    private var recognitionOnly=false
    var nutrition:Nutrition { Nutrition(kcal:kcal,protein:protein,carbs:carbs,fat:fat) }
    var food:Food { Food(catalogID:"photo:"+id,name:name,nameEn:nameEn,nutrition:recognitionOnly ? nil : nutrition,source:recognitionOnly ? "Image label" : id.hasPrefix("ai:") ? "AI nutrition estimate" : "Historical photo reference") }
    init(id:String,name:String,nameEn:String,grams:Double,kcal:Double,protein:Double,carbs:Double,fat:Double) {
        self.id=id;self.name=name;self.nameEn=nameEn;self.grams=grams;self.kcal=kcal;self.protein=protein;self.carbs=carbs;self.fat=fat
    }
    enum CodingKeys:String,CodingKey {case id,name,nameEn,grams,kcal,protein,carbs,fat}
    init(from decoder:Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        id=try c.decode(String.self,forKey:.id);name=try c.decode(String.self,forKey:.name);nameEn=try c.decode(String.self,forKey:.nameEn);grams=try c.decode(Double.self,forKey:.grams)
        let k=try c.decodeIfPresent(Double.self,forKey:.kcal),p=try c.decodeIfPresent(Double.self,forKey:.protein),b=try c.decodeIfPresent(Double.self,forKey:.carbs),f=try c.decodeIfPresent(Double.self,forKey:.fat)
        recognitionOnly=k==nil || p==nil || b==nil || f==nil
        kcal=k ?? 0;protein=p ?? 0;carbs=b ?? 0;fat=f ?? 0
    }
    func encode(to encoder:Encoder) throws {
        var c=encoder.container(keyedBy:CodingKeys.self)
        try c.encode(id,forKey:.id);try c.encode(name,forKey:.name);try c.encode(nameEn,forKey:.nameEn);try c.encode(grams,forKey:.grams)
        if !recognitionOnly {try c.encode(kcal,forKey:.kcal);try c.encode(protein,forKey:.protein);try c.encode(carbs,forKey:.carbs);try c.encode(fat,forKey:.fat)}
    }
}
struct PhotoPart:Identifiable { var id=UUID();var food:PhotoFood;var grams:Double;var low:Double;var high:Double;var basis:String;var tentative:Bool=false;var count:Double?=nil;var mealEstimate:MealPhotoEstimate?=nil
    var nutrition:Nutrition { food.nutrition.scaled(grams/100) }
    mutating func setGrams(_ value:Double) { guard value.isFinite else {return};if let estimate=mealEstimate{guard let scaled=try? estimate.scaled(toGrams:value) else{return};mealEstimate=scaled;grams=scaled.grams;low=scaled.low;high=scaled.high;basis="weight";return};grams=value;low=value;high=value;basis="weight" }
}
struct PhotoLabel:Decodable { var id:String;var food:Bool;var vector:[Double] }
struct PhotoLabels:Decodable { var modelId:String;var revision:String;var dimension:Int;var labels:[PhotoLabel];var regional:Regional
    struct Regional:Decodable { var modelId:String;var revision:String;var dimension:Int;var labels:[PhotoLabel] }
}
struct PhotoMatch { var id:String;var score:Double }
struct PhotoBox { var x:Double;var y:Double;var width:Double;var height:Double }
struct PhotoRegion { var box:PhotoBox;var isFood:Bool;var tentative:Bool;var candidates:[PhotoMatch] }
struct PhotoResult { var parts:[PhotoPart];var sauceSuggested:Bool;var unmatched:Bool }

enum PhotoMeal {
    static let aliases:[String:[String]] = [
        "chicken-shawarma":["شاورما دجاج عربي","شاورما عربي","شاورما دجاج","شاورما","chicken shawarma","arabic shawarma","shawarma","chicken wrap"],
        "beef-shawarma":["شاورما لحم عربي","شاورما لحم","beef shawarma","lamb shawarma"],
        "garlic-sauce":["صوص ثوم","صلصة ثوم","ثومية","ثوميه","ثوم","garlic sauce","garlic dip","toum"],
        "tahini-sauce":["صلصة طحينة","صوص طحينة","طحينة","tahini sauce","tahini dip","tahini"],
        "169836":["بطاطس مقلية","بطاطا مقلية","بطاطس","بطاطا","french fries","fries"],
        "chicken-rice":["كبسة","كبسه","مندي","برياني","kabsa","mandi","biryani"],
        "171477":["دجاج مشوي","دجاج","chicken"],"174031":["لحم بقري","لحم","beef","steak"],
        "169757":["رز ابيض","ارز ابيض","ارز","رز","white rice","rice"],"168928":["مكرونة","معكرونة","باستا","pasta"],
        "172454":["حمص بطحينة","حمص بالطحينة","حمص","hummus"],"173424":["بيض مسلوق","بيضة مسلوقة","بيض","boiled eggs","egg","eggs"],
        "173292":["بيتزا","pizza"],"170694":["برجر","برغر","burger","hamburger"],"172455":["فلافل","طعمية","falafel"],"172816":["خبز عربي","خبز","pita bread","bread"]
    ]
    static func family(_ id:String) -> String { if id.hasSuffix("shawarma"){return "wrap"};if ["garlic-sauce","tahini-sauce","172454"].contains(id){return "sauce"};if ["171534","171477"].contains(id){return "chicken"};if ["169757","169704","167668"].contains(id){return "rice"};if ["173424","172185","172187","173423"].contains(id){return "egg"};if ["170438","170093","168483","169836"].contains(id){return "potato"};return id }
    static func rank(_ embedding:[Float],labels:[PhotoLabel],box:PhotoBox) throws -> PhotoRegion {
        guard embedding.count==512,embedding.allSatisfy({$0.isFinite}),labels.allSatisfy({$0.vector.count==512}) else { throw AppError.invalid("بيانات نموذج الصورة غير صالحة.", "Invalid image model data.") }
        let norm=sqrt(embedding.reduce(0){$0+Double($1)*Double($1)});guard norm>0 else { throw AppError.invalid("تعذّر قراءة الصورة.", "The image could not be read.") }
        let scores=labels.map { label -> (PhotoMatch,Bool) in var score=0.0;for i in 0..<512 { score+=Double(embedding[i])/norm*label.vector[i] };return (PhotoMatch(id:label.id,score:score),label.food) }.sorted{$0.0.score>$1.0.score}
        let foods=scores.filter{$0.1}.map{$0.0},best=foods.first,nonFood=scores.first(where:{!$0.1})?.0.score ?? 0
        let isFood=(scores.first?.1 ?? false) && (best?.score ?? 0)>=0.20
        return PhotoRegion(box:box,isFood:isFood,tentative:!isFood || (best?.score ?? 0)<0.27 || (best?.score ?? 0)-nonFood<0.035 || (best?.score ?? 0)-(foods.dropFirst().first?.score ?? 0)<0.018,candidates:Array(foods.prefix(4)))
    }
    private struct Mention { var food:PhotoFood;var range:NSRange;var negative:Bool }
    private static func mentions(_ text:String,foods:[PhotoFood]) -> [Mention] {
        let ns=text as NSString; var candidates:[Mention]=[]
        for f in foods { for alias in [f.name,f.nameEn]+(aliases[f.id] ?? []) {
            let a=TextSearch.normalized(alias),pattern="(?<![\\p{L}\\p{N}])"+NSRegularExpression.escapedPattern(for:a)+"(?![\\p{L}\\p{N}])"
            guard let regex=try? NSRegularExpression(pattern:pattern) else{continue}
            for match in regex.matches(in:text,range:NSRange(location:0,length:ns.length)) {
                let before=ns.substring(with:NSRange(location:max(0,match.range.location-22),length:min(22,match.range.location)))
                let negative=before.range(of:"(?:بدون|بلا|لا يوجد|no|without)\\s+(?:اي\\s+|any\\s+)?$",options:.regularExpression) != nil
                candidates.append(Mention(food:f,range:match.range,negative:negative))
            }
        } }
        var result:[Mention]=[]
        for m in candidates.sorted(by:{$0.range.length>$1.range.length}) { if !result.contains(where:{NSIntersectionRange($0.range,m.range).length>0}) {result.append(m)} }
        return result.sorted{$0.range.location<$1.range.location}
    }
    static func quantity(_ raw:String,food:PhotoFood) throws -> (grams:Double,low:Double,high:Double,basis:String,count:Double?)? {
        var text=TextSearch.normalized(raw).replacingOccurrences(of:"٫",with:".")
        for (word,n) in ["عشره":"10","عشر":"10","خمسه":"5","خمس":"5","اربعه":"4","اربع":"4","ثلاثه":"3","ثلاث":"3","اثنين":"2","اثنتين":"2","واحده":"1","واحد":"1","ten":"10","two":"2","one":"1"] { text=text.replacingOccurrences(of:"(?<![\\p{L}\\p{N}])"+word+"(?![\\p{L}\\p{N}])",with:n,options:.regularExpression) }
        func match(_ pattern:String) -> [String]? { guard let re=try? NSRegularExpression(pattern:pattern),let m=re.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else{return nil};return (1..<m.numberOfRanges).compactMap{Range(m.range(at:$0),in:text).map{String(text[$0])}} }
        if text.range(of:"-\\s*\\d",options:.regularExpression) != nil { throw AppError.invalid("راجع الكمية في وصف الوجبة.", "Check the quantity in the description.") }
        if let m=match("([0-9]+(?:\\.[0-9]+)?)\\s*(كيلو(?:جرام|غرام)?|kg|جرام|غرام|قرام|جم|غم|grams?|g|مل|ml)(?![\\p{L}])"),let value=Double(m[0]) {
            let grams=value*(m[1].hasPrefix("كيلو") || m[1]=="kg" ? 1000:1);guard grams>0,grams<=3000 else{throw AppError.invalid("راجع الوزن المكتوب.","Check the supplied weight.")};return (grams,grams,grams,"weight",nil)
        }
        var count:Double?,unit=""
        if let m=match("([0-9]+(?:\\.[0-9]+)?)\\s*(قطعه|قطع|حبه|حبات|علبه|علب|كوب|اكواب|ملعقه|ملاعق|pieces?|pcs|slices?|cups?|containers?|wraps?|sandwiches?|tbsp|tablespoons?|tsp)(?![\\p{L}])") { count=Double(m[0]);unit=m[1] }
        else if let m=match("(قطعه|قطع|حبه|حبات|علبه|علب|كوب|pieces?|cups?)\\s*([0-9]+(?:\\.[0-9]+)?)") { count=Double(m[1]);unit=m[0] }
        else if text.range(of:"علبتين|علبتان|قطعتين|قطعتان|حبتين|حبتان|كوبين",options:.regularExpression) != nil {count=2;unit=family(food.id)=="sauce" ? "علبه":"قطعه"}
        else if text.range(of:"علبه|container|pot|كوب|cup",options:.regularExpression) != nil {count=1;unit=text.contains("cup") || text.contains("كوب") ? "cup":"علبه"}
        else if let m=match("(?:^|\\s)([0-9]+(?:\\.[0-9]+)?)(?=\\s|$)") {count=Double(m[0]);unit="قطعه"}
        guard let count else{return nil};guard count>0,count<=50 else{throw AppError.invalid("راجع عدد القطع.","Check the item count.")}
        var grams=food.grams
        if unit.range(of:"tbsp|tablespoon|ملعقه|ملاعق",options:.regularExpression) != nil {grams=15}
        else if unit=="tsp" {grams=5}
        else if unit.contains("cup") || unit.contains("كوب") {grams=family(food.id)=="sauce" ? 220:family(food.id)=="rice" ? 180:food.grams}
        else if family(food.id)=="wrap" {grams=unit.contains("wrap") || unit.contains("sandwich") ? 165:33}
        else if family(food.id)=="egg" {grams=50}
        else if family(food.id)=="sauce" {grams=35}
        grams *= count;guard grams<=3000 else{throw AppError.invalid("الكمية أكبر من نطاق التحليل.","The portion exceeds the analysis range.")};return (grams,grams*0.65,grams*1.5,"count",count)
    }
    static func estimate(_ regions:[PhotoRegion],description:String,foods:[PhotoFood],confirmedFood:Bool=false) throws -> PhotoResult {
        guard confirmedFood || regions.contains(where:{$0.isFood}) else { return PhotoResult(parts:[],sauceSuggested:false,unmatched:false) }
        let text=TextSearch.normalized(String(description.prefix(1000))).replacingOccurrences(of:"٫",with:".")
        let all=mentions(text,foods:foods),found=all.filter{!$0.negative},excluded=Set(all.filter{$0.negative}.map{family($0.food.id)})
        let ns=text as NSString;var parts:[PhotoPart]=[]
        func reference(_ food:PhotoFood,_ tentative:Bool=false) -> PhotoPart {
            let matching=regions.filter{$0.isFood && family($0.candidates.first?.id ?? "")==family(food.id) && $0.box.width<1 && ($0.candidates.first?.score ?? 0)>=0.27}
            let coverage=min(1,matching.reduce(0){$0+$1.box.width*$1.box.height}),scale=family(food.id)=="sauce" ? 1.0:coverage>0.6 ? 1.25:coverage>0 && coverage<0.2 ? 0.8:1
            let grams=max(5,(food.grams*scale/5).rounded()*5)
            return PhotoPart(food:food,grams:grams,low:grams*0.5,high:grams*1.8,basis:"reference",tentative:tentative)
        }
        let split="[,+،;؛]|\\s+(?:و|and|with|مع)\\s+|\\s+و(?=علب|كوب|ثوم|طحين|شاور)"
        func clauses(_ s:String) -> [String] { let re=try! NSRegularExpression(pattern:split);let ns=s as NSString;var values:[String]=[],start=0;for m in re.matches(in:s,range:NSRange(location:0,length:ns.length)){values.append(ns.substring(with:NSRange(location:start,length:m.range.location-start)));start=m.range.location+m.range.length};values.append(ns.substring(from:start));return values }
        for (i,m) in found.enumerated() {
            let start=i>0 ? NSMaxRange(found[i-1].range):0,end=i+1<found.count ? found[i+1].range.location:ns.length
            let before=clauses(ns.substring(with:NSRange(location:start,length:m.range.location-start))).last ?? "",after=clauses(ns.substring(with:NSRange(location:NSMaxRange(m.range),length:end-NSMaxRange(m.range)))).first ?? ""
            var part=reference(m.food);if let q=try quantity(before+" "+after,food:m.food){part.grams=q.grams;part.low=q.low;part.high=q.high;part.basis=q.basis;part.count=q.count}
            if let index=parts.firstIndex(where:{$0.food.id==part.food.id}) {parts[index].grams+=part.grams;parts[index].low+=part.low;parts[index].high+=part.high;if let a=parts[index].count,let b=part.count{parts[index].count=a+b}else{parts[index].count=nil}} else {parts.append(part)}
        }
        struct Vote { var food:PhotoFood;var score:Double;var count:Int;var tentative:Bool }
        var votes:[String:Vote]=[:]
        for r in regions {
            guard r.isFood,let best=r.candidates.first,let food=foods.first(where:{$0.id==best.id}),best.score>=0.275 else{continue}
            if let wrap=r.candidates.first(where:{$0.id.hasSuffix("shawarma") && $0.score>=0.30 && best.score-$0.score<=0.012}),let f=foods.first(where:{$0.id==wrap.id}),family(food.id) != "wrap" { let v=votes["wrap"];votes["wrap"]=Vote(food:f,score:max(wrap.score,v?.score ?? 0),count:(v?.count ?? 0)+1,tentative:true) }
            let f=family(food.id),competing=r.candidates.first(where:{family($0.id) != f})?.score ?? 0
            if best.score-competing<0.012 && !(f=="wrap" && best.score>=0.30){continue}
            let v=votes[f];votes[f]=Vote(food:v.map{best.score>$0.score ? food:$0.food} ?? food,score:max(best.score,v?.score ?? 0),count:(v?.count ?? 0)+1,tentative:r.tentative || (v?.tentative ?? false))
        }
        for v in votes.values.sorted(by:{$0.score>$1.score}) {
            let f=family(v.food.id)
            if excluded.contains(f) || parts.contains(where:{family($0.food.id)==f}) || parts.count>=8 || (v.count<2 && v.score<0.32 && !(f=="wrap" && v.score>=0.31)){continue}
            if f=="sauce"{continue} // White sauce identity requires confirmation.
            if parts.contains(where:{family($0.food.id)=="wrap"}) && ["chicken","172816","174031"].contains(f){continue}
            if parts.contains(where:{$0.food.id=="chicken-rice"}) && ["rice","chicken"].contains(f){continue}
            parts.append(reference(v.food,v.tentative))
        }
        if parts.isEmpty,let r=regions.first(where:{$0.isFood}),let id=r.candidates.first?.id,let f=foods.first(where:{$0.id==id}),!excluded.contains(family(id)),family(id) != "sauce" {parts.append(reference(f,true))}
        let suggestion=regions.contains {r in r.box.width<0.6 && r.isFood && ["garlic-sauce","tahini-sauce"].contains(r.candidates.first?.id ?? "") && (r.candidates.first?.score ?? 0)>=0.29} && !parts.contains{family($0.food.id)=="sauce"}
        let unmatched=clauses(text).contains{ !$0.trimmingCharacters(in:.whitespaces).isEmpty && mentions($0,foods:foods).isEmpty }
        return PhotoResult(parts:parts,sauceSuggested:suggestion,unmatched:unmatched)
    }
}
