import SwiftUI

enum Theme {
    // PowerPeak's black cards, orange focus, and soft charcoal canvas.
    static let background=Color(red:0.086,green:0.082,blue:0.114)
    static let card=Color(red:0.031,green:0.027,blue:0.035)
    static let surface=Color(red:0.13,green:0.12,blue:0.145)
    static let accent=Color(red:0.949,green:0.376,blue:0.153)
    static let secondaryAccent=Color(red:0.961,green:0.729,blue:0.345)
    static let muted=Color(red:0.65,green:0.64,blue:0.67)
    static let text=Color(red:0.976,green:0.965,blue:0.949)
    static let stroke=Color.white.opacity(0.075)
    static let cardRadius:CGFloat=24
}
extension View {
    func luqmaCard() -> some View {padding(20).frame(maxWidth:.infinity,alignment:.leading).background(Theme.card,in:RoundedRectangle(cornerRadius:Theme.cardRadius)).overlay{RoundedRectangle(cornerRadius:Theme.cardRadius).stroke(Theme.stroke,lineWidth:0.5)}}
    func appBackground() -> some View {background(Theme.background.ignoresSafeArea()).scrollContentBackground(.hidden)}
}

struct LuqmaPageHeader:View {
    var title:String
    var subtitle:String
    var symbol:String
    var body:some View {
        HStack(spacing:14){
            Image(systemName:symbol).font(.system(size:23,weight:.semibold))
                .foregroundStyle(Theme.accent).frame(width:52,height:52)
                .background(Theme.accent.opacity(0.12),in:RoundedRectangle(cornerRadius:18))
            VStack(alignment:.leading,spacing:5){
                Text(subtitle).font(.caption.weight(.medium)).foregroundStyle(Theme.muted)
                Text(title).font(.system(size:29,weight:.bold)).foregroundStyle(Theme.text)
            }
            Spacer(minLength:0)
        }.padding(.top,6)
    }
}

struct LuqmaSectionHeader:View {
    var title:String
    var detail:String?=nil
    var body:some View {
        HStack(alignment:.firstTextBaseline){
            Text(title).font(.title3.bold()).foregroundStyle(Theme.text)
            Spacer(minLength:8)
            if let detail{Text(detail).font(.caption).foregroundStyle(Theme.muted)}
        }
    }
}

struct LuqmaPrimaryButtonStyle:ButtonStyle {
    func makeBody(configuration:Configuration)->some View {
        configuration.label.font(.headline).foregroundStyle(Theme.card)
            .frame(maxWidth:.infinity,minHeight:52)
            .background(Theme.accent,in:RoundedRectangle(cornerRadius:16))
            .opacity(configuration.isPressed ? 0.8:1)
    }
}

struct LuqmaProgressRing:View {
    var progress:Double
    var color:Color=Theme.accent
    var lineWidth:CGFloat=7
    var body:some View {
        ZStack{
            Circle().stroke(Theme.surface,lineWidth:lineWidth)
            Circle().trim(from:0,to:min(1,max(0,progress.isFinite ? progress:0)))
                .stroke(color,style:StrokeStyle(lineWidth:lineWidth,lineCap:.round))
                .rotationEffect(.degrees(-90))
        }.accessibilityHidden(true)
    }
}

struct LuqmaPill:View {
    var title:String
    var selected:Bool
    var action:()->Void
    var body:some View {
        Button(action:action){Text(title).font(.subheadline.weight(.semibold))
            .padding(.horizontal,16).frame(minHeight:42)
            .foregroundStyle(selected ? Theme.card:Theme.muted)
            .background(selected ? Theme.text:Theme.card,in:Capsule())}
            .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected:[])
    }
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
    private var reference:String {
        if food.sourceDescription==FoodDatabase.searchSummarySourceDescription {return diary.t("لكل ١٠٠","per 100")}
        return food.unit == .serving ? diary.t("للحصة","per serving"):diary.t("لكل ١٠٠","per 100")+" "+food.unit.label(diary.language)
    }
    var body:some View {
        Button(action:action){HStack(spacing:14){
            Image(systemName:"fork.knife").font(.system(size:19,weight:.medium)).foregroundStyle(Theme.accent).frame(width:46,height:46).background(Theme.accent.opacity(0.1),in:RoundedRectangle(cornerRadius:14)).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:6){Text(food.label(diary.language)).font(.headline).foregroundStyle(.primary);if let brand=food.brand{Text(brand).font(.caption).foregroundStyle(Theme.muted)}
                if let source=food.source,source != "OpenFoodFacts" {Text(source=="Your food" ? diary.t("طعامك الخاص","Your private food"):source=="MyFitnessPal supplied IPA" ? diary.t("MyFitnessPal · ملفك","MyFitnessPal · your file"):source).font(.caption2).foregroundStyle(Theme.muted)}
                if let n=food.values(for:food.unit){Text("\(decimal(n.kcal,0)) \(diary.t("سعرة","kcal")) · \(reference)").font(.subheadline).foregroundStyle(Theme.accent)}
                else{Text(diary.t("بيانات غذائية غير مكتملة","Incomplete nutrition data")).font(.caption).foregroundStyle(.orange)}
            };Spacer(minLength:0)
            Image(systemName:"plus").font(.system(size:17,weight:.semibold)).foregroundStyle(Theme.accent).frame(width:36,height:36).background(Theme.surface,in:Circle()).accessibilityHidden(true)
        }.padding(.vertical,10)}.buttonStyle(.plain)
    }
}
struct Notice:View {var text:String;var body:some View {Text(text).font(.footnote).foregroundStyle(Theme.muted).frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true)}}
