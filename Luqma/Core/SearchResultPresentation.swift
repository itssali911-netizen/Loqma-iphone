import Foundation

/// A textual similarity, not nutritional confidence or a product identity check.
/// Sorting by this score is opt-in; the database's Best match order stays intact.
enum SearchNameSimilarity {
    static func percent(query:String,food:Food)->Int? {
        let query=canonical(query)
        guard !query.isEmpty else{return nil}
        var names=[food.name]
        if let english=food.nameEn{names.append(english)}
        if let brand=food.brand{names += [brand]+names.map{brand+" "+$0}}
        names.append(contentsOf:(food.aliases ?? "").components(separatedBy:CharacterSet(charactersIn:",،;؛|\n")))
        return names.map{score(query,canonical($0))}.max() ?? 0
    }
    private static func canonical(_ value:String)->String {
        FoodSearch.normalized(value).split(separator:" ").sorted().joined(separator:" ")
    }
    private static func score(_ a:String,_ b:String)->Int {
        guard !b.isEmpty else{return 0}
        if a==b{return 100}
        let left=Array(a),right=Array(b)
        guard left.count>1,right.count>1 else{return 0}
        let lhs=Set(zip(left,left.dropFirst()).map{String([$0.0,$0.1])})
        let rhs=Set(zip(right,right.dropFirst()).map{String([$0.0,$0.1])})
        return Int((200*Double(lhs.intersection(rhs).count)/Double(lhs.count+rhs.count)).rounded())
    }
}

enum SearchResultOrder:String,CaseIterable {
    case bestMatch,similarityDescending,similarityAscending
    func arrange(_ foods:[Food],scores:[String:Int])->[Food] {
        guard self != .bestMatch else{return foods}
        return foods.enumerated().sorted { a,b in
            let first=scores[a.element.id] ?? 0,second=scores[b.element.id] ?? 0
            if first==second{return a.offset<b.offset}
            return self == .similarityDescending ? first>second:first<second
        }.map(\.element)
    }
}

enum SearchScreenPhase:Equatable {
    case idle,loading,results,empty,error
    static func resolve(resultCount:Int,isBusy:Bool,completed:Bool,hasError:Bool)->Self {
        if resultCount>0{return .results}
        if isBusy{return .loading}
        if hasError{return .error}
        return completed ? .empty:.idle
    }
}
