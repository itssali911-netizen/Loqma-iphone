import SwiftUI

enum Theme {
    // Sandow Community dark file: Sandow Gray/100 and Pulse Orange/50.
    private static func color(_ value:VisualRGB)->Color {Color(.sRGB,red:value.red,green:value.green,blue:value.blue,opacity:1)}
    static let background=color(VisualDesignTokens.background)
    static let card=color(VisualDesignTokens.card)
    static let surface=color(VisualDesignTokens.surface)
    static let input=background
    static let accent=color(VisualDesignTokens.accent)
    static let secondaryAccent=color(VisualDesignTokens.secondaryAccent)
    static let text=color(VisualDesignTokens.text)
    static let textSecondary=color(VisualDesignTokens.textSecondary)
    static let muted=textSecondary
    static let onAccent=color(VisualDesignTokens.onAccent)
    static let onSecondaryAccent=color(VisualDesignTokens.onSecondaryAccent)
    static let accentText=color(VisualDesignTokens.accentText)
    static let secondaryAccentText=color(VisualDesignTokens.secondaryAccentText)
    static let link=accentText
    static let success=color(VisualDesignTokens.success)
    static let warning=color(VisualDesignTokens.warning)
    static let error=color(VisualDesignTokens.error)
    static let errorBackground=color(VisualDesignTokens.errorBackground)
    static let errorBorder=color(VisualDesignTokens.errorBorder)
    static let controlBorder=color(VisualDesignTokens.controlBorder)
    static let stroke=color(VisualDesignTokens.divider)
    static let cardRadius:CGFloat=20
    // Directly read instance heights: Top Nav 2:10015; Button Primary Icon 2:10013.
    // These values do not imply that the flattened target panels expose their child metrics.
    static let navigationHeight:CGFloat=48
    static let primaryButtonHeight:CGFloat=56
    static let bottomBarItemHeight:CGFloat=54
    static let bottomBarPadding:CGFloat=6
    static let bottomBarTopGap:CGFloat=6
    static let bottomBarBottomGap:CGFloat=4
    static let bottomBarHeight:CGFloat=bottomBarItemHeight+2*bottomBarPadding+bottomBarTopGap+bottomBarBottomGap
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
                Text(subtitle).luqmaFont(size:14,relativeTo:.caption).foregroundStyle(Theme.textSecondary)
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
        configuration.label.luqmaFont(.headline).foregroundStyle(Theme.onAccent)
            .frame(maxWidth:.infinity,minHeight:Theme.primaryButtonHeight)
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
    var identifier:String?=nil
    @State private var text=""
    @FocusState private var focused:Bool
    var body:some View {
        HStack{Text(title);Spacer();TextField(title,text:$text,prompt:Text(title).foregroundColor(Theme.muted)).keyboardType(.decimalPad).focused($focused).multilineTextAlignment(.trailing).frame(minWidth:65,maxWidth:120).accessibilityLabel(title).accessibilityIdentifier(identifier ?? title);if !suffix.isEmpty{Text(DisplayFormat.westernDigits(suffix)).foregroundStyle(Theme.textSecondary)}}
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
        case "OpenFoodFacts","Open Food Facts":return "Open Food Facts"
        default:return nil
        }
    }
    private var metadata:String{
        [food.brand.map(DisplayFormat.westernDigits),sourceTitle]
            .compactMap{$0}.filter{!$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}.joined(separator:" · ")
    }
    var body:some View {
        Button(action:action){HStack(spacing:10){
            Image(systemName:"fork.knife").font(.system(size:16,weight:.regular)).foregroundStyle(Theme.muted)
                .frame(width:40,height:40).background(Theme.surface,in:RoundedRectangle(cornerRadius:10,style:.continuous)).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:3){
                Text(food.label(diary.language)).luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline)
                    .foregroundStyle(Theme.text).multilineTextAlignment(.leading).lineLimit(2).fixedSize(horizontal:false,vertical:true)
                if let n=food.values(for:food.unit){Text("\(decimal(n.kcal,0)) \(diary.t("سعرة","kcal")) · \(reference)").luqmaFont(size:11,relativeTo:.caption).foregroundStyle(Theme.muted)}
                else{Text(diary.t("بيانات غذائية غير مكتملة","Incomplete nutrition data")).luqmaFont(size:11,relativeTo:.caption).foregroundStyle(Theme.warning)}
                if !metadata.isEmpty{Text(metadata).luqmaFont(size:10,relativeTo:.caption2).foregroundStyle(Theme.muted).lineLimit(2)}
            };Spacer(minLength:0)
            Image(systemName:"chevron.forward").font(.system(size:12,weight:.medium)).foregroundStyle(Theme.muted).frame(width:24,height:40).accessibilityHidden(true)
        }.padding(12).frame(maxWidth:.infinity,minHeight:64,alignment:.leading)
            .background(Theme.card,in:RoundedRectangle(cornerRadius:14,style:.continuous))
            .contentShape(RoundedRectangle(cornerRadius:14,style:.continuous))}.buttonStyle(.plain)
            .accessibilityHint(diary.t("اختيار الطعام والكمية","Choose food and quantity"))
            .accessibilityIdentifier("food.result."+food.id)
    }
}
struct Notice:View {var text:String;var body:some View {Text(DisplayFormat.westernDigits(text)).luqmaFont(.footnote).foregroundStyle(Theme.muted).frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true)}}

// Shared Sandow screen chrome keeps navigation independent of iOS toolbar glass.
private struct SandowNavigationChrome:ViewModifier {
    let title:String
    let backLabel:String
    var onBack:(()->Void)?
    var actionLabel:String?
    var actionEnabled:Bool
    var actionIdentifier:String?
    var onAction:(()->Void)?
    @Environment(\.dismiss) private var dismiss
    func body(content:Content)->some View {
        content.navigationTitle(title).toolbar(.hidden,for:.navigationBar)
            .safeAreaInset(edge:.top,spacing:0){
                ZStack{
                    Text(title).luqmaFont(size:14,weight:.semibold,relativeTo:.headline)
                        .multilineTextAlignment(.center).padding(.horizontal,54)
                        .frame(maxWidth:.infinity,minHeight:Theme.navigationHeight).accessibilityAddTraits(.isHeader)
                    HStack{
                        Button{if let onBack{onBack()}else{dismiss()}}label:{
                            Image(systemName:"chevron.backward").font(.system(size:12,weight:.semibold))
                                .frame(width:30,height:30).foregroundStyle(Theme.text)
                                .background(Theme.card,in:RoundedRectangle(cornerRadius:9))
                                .frame(width:44,height:44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(backLabel).accessibilityIdentifier("navigation.back")
                        Spacer(minLength:0)
                    }.padding(.horizontal,10)
                }.foregroundStyle(Theme.text).padding(.bottom,6).background(Theme.background.ignoresSafeArea(edges:.top))
            }
            .safeAreaInset(edge:.bottom,spacing:0){
                if let actionLabel,let onAction{
                    Button(actionLabel,action:onAction).buttonStyle(LuqmaPrimaryButtonStyle()).disabled(!actionEnabled)
                        .accessibilityIdentifier(actionIdentifier ?? "navigation.primaryAction")
                        .padding(.horizontal,16).padding(.top,10).padding(.bottom,8).background(Theme.background)
                }
            }
    }
}
extension View {
    func sandowNavigation(_ title:String,backLabel:String,onBack:(()->Void)?=nil,
                          actionLabel:String?=nil,actionEnabled:Bool=true,actionIdentifier:String?=nil,onAction:(()->Void)?=nil)->some View {
        modifier(SandowNavigationChrome(title:title,backLabel:backLabel,onBack:onBack,
                                        actionLabel:actionLabel,actionEnabled:actionEnabled,actionIdentifier:actionIdentifier,onAction:onAction))
    }
}
