import SwiftUI

enum Theme {
    // Sandow Community dark file: Sandow Gray/100 and Pulse Orange/50.
    static let background=Color(red:17.0/255,green:18.0/255,blue:20.0/255)
    static let card=Color(red:36.0/255,green:38.0/255,blue:43.0/255)
    static let surface=Color(red:57.0/255,green:60.0/255,blue:67.0/255)
    static let input=background
    static let accent=Color(red:249.0/255,green:115.0/255,blue:22.0/255)
    static let secondaryAccent=Color(red:37.0/255,green:99.0/255,blue:235.0/255)
    static let muted=Color(red:158.0/255,green:160.0/255,blue:165.0/255)
    static let text=Color.white
    static let stroke=Color.white.opacity(0.08)
    static let cardRadius:CGFloat=20
}
extension View {
    func luqmaCard() -> some View {padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Theme.card,in:RoundedRectangle(cornerRadius:Theme.cardRadius,style:.continuous))}
    func appBackground() -> some View {background(Theme.background.ignoresSafeArea()).scrollContentBackground(.hidden).luqmaFont(.body)}
    func sandowForm() -> some View {
        appBackground().listStyle(.insetGrouped).listSectionSpacing(16)
            .listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
    }
}

struct LuqmaPageHeader:View {
    var title:String
    var subtitle:String
    var symbol:String
    var body:some View {
        HStack(spacing:12){
            Image(systemName:symbol).font(.system(size:21,weight:.semibold))
                .foregroundStyle(Theme.text).frame(width:44,height:44)
                .background(Theme.card,in:RoundedRectangle(cornerRadius:16)).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:3){
                Text(subtitle).luqmaFont(size:14,weight:.light,relativeTo:.caption).foregroundStyle(Theme.muted)
                Text(title).luqmaFont(size:22,weight:.bold,relativeTo:.title2).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength:0)
        }.padding(.top,4)
    }
}

struct LuqmaSectionHeader:View {
    var title:String
    var detail:String?=nil
    var body:some View {
        HStack(alignment:.firstTextBaseline){
            Text(title).luqmaFont(size:17,weight:.bold,relativeTo:.headline).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
            Spacer(minLength:8)
            if let detail{Text(detail).luqmaFont(.caption).foregroundStyle(Theme.muted)}
        }
    }
}

struct LuqmaPrimaryButtonStyle:ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration:Configuration)->some View {
        configuration.label.luqmaFont(.headline).foregroundStyle(Theme.text)
            .frame(maxWidth:.infinity,minHeight:52)
            .background(Theme.accent,in:RoundedRectangle(cornerRadius:16,style:.continuous))
            .opacity(!isEnabled ? 0.4:configuration.isPressed ? 0.8:1)
    }
}

struct LuqmaSecondaryButtonStyle:ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration:Configuration)->some View {
        configuration.label.luqmaFont(.headline).foregroundStyle(Theme.text)
            .frame(maxWidth:.infinity,minHeight:48)
            .background(Theme.surface,in:RoundedRectangle(cornerRadius:16,style:.continuous))
            .opacity(!isEnabled ? 0.4:configuration.isPressed ? 0.75:1)
    }
}

struct LuqmaProgressRing:View {
    var progress:Double
    var color:Color=Theme.accent
    var lineWidth:CGFloat=7
    var body:some View {
        GeometryReader{_ in
            ZStack{
                Circle().stroke(Theme.background,lineWidth:lineWidth)
                Circle().trim(from:0,to:min(1,max(0,progress.isFinite ? progress:0)))
                    .stroke(color,style:StrokeStyle(lineWidth:lineWidth,lineCap:.round))
                    .rotationEffect(.degrees(-90))
            }
        }.accessibilityHidden(true)
    }
}

struct LuqmaMacroRings:View {
    var calorieProgress:Double
    var proteinProgress:Double
    var carbProgress:Double
    @EnvironmentObject var diary:DiaryStore
    var body:some View {
        ZStack{
            LuqmaProgressRing(progress:calorieProgress,color:Theme.accent,lineWidth:8)
            LuqmaProgressRing(progress:proteinProgress,color:Theme.muted,lineWidth:8).padding(15)
            LuqmaProgressRing(progress:carbProgress,color:Theme.secondaryAccent,lineWidth:8).padding(30)
            Image(systemName:"fork.knife").font(.system(size:20,weight:.medium)).foregroundStyle(Theme.text).accessibilityHidden(true)
        }.accessibilityElement(children:.ignore)
            .accessibilityLabel(diary.t("التقدّم في السعرات والبروتين والكارب","Calorie, protein and carbohydrate progress"))
            .accessibilityValue(diary.t("السعرات \(percentage(calorieProgress))٪، البروتين \(percentage(proteinProgress))٪، الكارب \(percentage(carbProgress))٪","Calories \(percentage(calorieProgress))%, protein \(percentage(proteinProgress))%, carbs \(percentage(carbProgress))%"))
    }
    private func percentage(_ value:Double)->String{decimal(min(1,max(0,value.isFinite ? value:0))*100,0)}
}

struct LuqmaPill:View {
    var title:String
    var selected:Bool
    var action:()->Void
    var body:some View {
        Button(action:action){Text(title).luqmaFont(size:15,weight:.medium,relativeTo:.subheadline)
            .padding(.horizontal,16).frame(minHeight:42)
            .foregroundStyle(selected ? Theme.background:Theme.muted)
            .background(selected ? Theme.text:Theme.card,in:Capsule())}
            .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected:[])
    }
}
func decimal(_ value:Double,_ digits:Int=1) -> String {DisplayFormat.decimal(value,digits:digits)}
struct NumericInput:View {
    var title:String;@Binding var value:Double;var suffix:String=""
    @State private var text=""
    @FocusState private var focused:Bool
    var body:some View {
        HStack{Text(title);Spacer();TextField(title,text:$text).keyboardType(.decimalPad).focused($focused).multilineTextAlignment(.trailing).frame(minWidth:65,maxWidth:120).accessibilityLabel(title);if !suffix.isEmpty{Text(DisplayFormat.westernDigits(suffix)).foregroundStyle(.secondary)}}
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
            HStack(alignment:.firstTextBaseline){Text(decimal(value.kcal,0)).luqmaFont(large ? LTypography.Descriptor(size:38,weight:.heavy,relativeTo:.largeTitle):.title).monospacedDigit().foregroundStyle(Theme.accent);Text(diary.t("سعرة","kcal")).foregroundStyle(Theme.muted)}
            HStack(spacing:8){macro("البروتين","Protein",value.protein);macro("الكارب","Carbs",value.carbs);macro("الدهون","Fat",value.fat)}
        }
    }
    private func macro(_ ar:String,_ en:String,_ n:Double) -> some View {VStack(alignment:.leading,spacing:6){Text(diary.t(ar,en)).luqmaFont(.caption).foregroundStyle(Theme.muted);Text(decimal(n)+" "+diary.t("جم","g")).luqmaFont(size:15,weight:.bold,relativeTo:.subheadline).monospacedDigit()}.frame(maxWidth:.infinity,alignment:.leading)}
}
struct FoodRow:View {
    var food:Food;var action:()->Void
    @EnvironmentObject var diary:DiaryStore
    private var reference:String {
        if food.sourceDescription==FoodDatabase.searchSummarySourceDescription {return diary.t("لكل ١٠٠","per 100")}
        return food.unit == .serving ? diary.t("للحصة","per serving"):diary.t("لكل ١٠٠","per 100")+" "+food.unit.label(diary.language)
    }
    private var sourceTitle:String? {
        switch food.source {
        case MealPhotoEstimate.source:return diary.t("تقديري","Estimated")
        case "Your food":return diary.t("طعامك الخاص","Your private food")
        case "MyFitnessPal supplied IPA":return diary.t("MyFitnessPal · ملفك","MyFitnessPal · your file")
        default:return nil
        }
    }
    var body:some View {
        Button(action:action){HStack(spacing:12){
            Image(systemName:"fork.knife").font(.system(size:16,weight:.medium)).foregroundStyle(Theme.accent).frame(width:38,height:38).background(Theme.accent.opacity(0.1),in:RoundedRectangle(cornerRadius:12)).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:4){Text(food.label(diary.language)).luqmaFont(size:15,weight:.bold,relativeTo:.subheadline).foregroundStyle(Theme.text).multilineTextAlignment(.leading).fixedSize(horizontal:false,vertical:true);if let brand=food.brand{Text(DisplayFormat.westernDigits(brand)).luqmaFont(.caption).foregroundStyle(Theme.muted)}
                if let sourceTitle{Text(sourceTitle).luqmaFont(.caption2).foregroundStyle(Theme.muted)}
                if let n=food.values(for:food.unit){Text("\(decimal(n.kcal,0)) \(diary.t("سعرة","kcal")) · \(reference)").luqmaFont(size:12,weight:.medium,relativeTo:.caption).foregroundStyle(Theme.accent)}
                else{Text(diary.t("بيانات غذائية غير مكتملة","Incomplete nutrition data")).luqmaFont(.caption).foregroundStyle(.orange)}
            };Spacer(minLength:0)
            Image(systemName:"plus").font(.system(size:16,weight:.semibold)).foregroundStyle(Theme.accent).frame(width:32,height:32).background(Theme.surface,in:Circle()).accessibilityHidden(true)
        }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
            .background(Theme.card,in:RoundedRectangle(cornerRadius:Theme.cardRadius,style:.continuous))
            .contentShape(RoundedRectangle(cornerRadius:Theme.cardRadius,style:.continuous))}.buttonStyle(.plain)
    }
}
struct Notice:View {var text:String;var body:some View {Text(DisplayFormat.westernDigits(text)).luqmaFont(.footnote).foregroundStyle(Theme.muted).frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true)}}
