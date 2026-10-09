import SwiftUI

enum Theme {
    static let background=Color(red:0.025,green:0.055,blue:0.105)
    static let card=Color(red:0.075,green:0.13,blue:0.20)
    static let accent=Color(red:0.22,green:0.80,blue:0.93)
    static let muted=Color(red:0.59,green:0.68,blue:0.78)
}
extension View {
    func luqmaCard() -> some View {padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Theme.card,in:RoundedRectangle(cornerRadius:22))}
    func appBackground() -> some View {background(Theme.background.ignoresSafeArea()).scrollContentBackground(.hidden)}
}
func decimal(_ value:Double,_ digits:Int=1) -> String {value.isFinite ? String(format:"%.*f",digits,value):"—"}
struct NumericInput:View {
    var title:String;@Binding var value:Double;var suffix:String=""
    @State private var text=""
    @FocusState private var focused:Bool
    var body:some View {
        HStack{Text(title);Spacer();TextField(title,text:$text).keyboardType(.decimalPad).focused($focused).multilineTextAlignment(.trailing).frame(minWidth:65,maxWidth:120).accessibilityLabel(title);if !suffix.isEmpty{Text(suffix).foregroundStyle(.secondary)}}
            .onAppear{text=decimal(value,value.rounded()==value ? 0:1)}
            .onChange(of:text){_,s in
                guard focused else{return} // Formatting another macro must not edit its value.
                if s.isEmpty{value=0}
                else if let number=TextSearch.number(s),number.isFinite{if abs(value-number)>0.000001{value=number};if abs(value-number)>0.000001{text=decimal(value,value.rounded()==value ? 0:2)}}
                else{value=0}
            }
            .onChange(of:value){_,v in if (!focused || !text.isEmpty),abs((TextSearch.number(text) ?? .infinity)-v)>0.000001 {text=decimal(v,v.rounded()==v ? 0:2)}}
            .onChange(of:focused){_,active in if !active{text=decimal(value,value.rounded()==value ? 0:2)}}
    }
}
struct NutritionView:View {
    var value:Nutrition;var large=false
    @EnvironmentObject var diary:DiaryStore
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            HStack(alignment:.firstTextBaseline){Text(decimal(value.kcal,0)).font(large ? .system(size:46,weight:.bold,design:.rounded):.title.bold()).foregroundStyle(Theme.accent);Text(diary.t("سعرة","kcal")).foregroundStyle(Theme.muted)}
            HStack(spacing:8){macro("البروتين","Protein",value.protein);macro("الكارب","Carbs",value.carbs);macro("الدهون","Fat",value.fat)}
        }
    }
    private func macro(_ ar:String,_ en:String,_ n:Double) -> some View {VStack(alignment:.leading,spacing:6){Text(diary.t(ar,en)).font(.caption).foregroundStyle(Theme.muted);Text(decimal(n)+" "+diary.t("جم","g")).font(.subheadline.bold()).monospacedDigit()}.frame(maxWidth:.infinity,alignment:.leading)}
}
struct FoodRow:View {
    var food:Food;var action:()->Void
    @EnvironmentObject var diary:DiaryStore
    var body:some View {
        Button(action:action){HStack(spacing:14){
            Image(systemName:"plus.circle.fill").font(.title2).foregroundStyle(Theme.accent)
            VStack(alignment:.leading,spacing:6){Text(food.label(diary.language)).font(.headline).foregroundStyle(.primary);if let brand=food.brand{Text(brand).font(.caption).foregroundStyle(Theme.muted)}
                if let n=food.values(for:food.unit){Text("\(decimal(n.kcal,0)) \(diary.t("سعرة","kcal")) · \(food.unit == .serving ? diary.t("للحصة","per serving"):diary.t("لكل ١٠٠","per 100")+" "+food.unit.label(diary.language))").font(.subheadline).foregroundStyle(Theme.accent);Text("P \(decimal(n.protein)) · C \(decimal(n.carbs)) · F \(decimal(n.fat))").font(.caption).foregroundStyle(Theme.muted).environment(\.layoutDirection,.leftToRight)}
                else{Text(diary.t("بيانات غذائية غير مكتملة","Incomplete nutrition data")).font(.caption).foregroundStyle(.orange)}
            };Spacer(minLength:0)
        }.padding(.vertical,8)}.buttonStyle(.plain)
    }
}
struct Notice:View {var text:String;var body:some View {Text(text).font(.footnote).foregroundStyle(Theme.muted).frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true)}}
