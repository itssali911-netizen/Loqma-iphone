import SwiftUI
import UIKit

// Scoped to the eight-screen review. Existing approved screens keep their
// drawing instructions. Geometry is reused from Common.swift, KitchenView and
// LTypography; macro colors/icons come from the approved DailyCalorieCard.
enum LuqmaReviewStyle {
    static let margin:CGFloat=16
    static let gap:CGFloat=16
    static let rowGap:CGFloat=12
    static let controlRadius:CGFloat=12
    static let controlHeight:CGFloat=44
    static func macroColor(_ key:MacroKey)->Color {
        switch key {
        case .protein:return Color(red:239/255.0,green:121/255.0,blue:142/255.0)
        case .carbs:return Color(red:232/255.0,green:179/255.0,blue:76/255.0)
        case .fat:return Color(red:143/255.0,green:190/255.0,blue:99/255.0)
        }
    }
    static func macroIcon(_ key:MacroKey)->String {
        switch key {case .protein:return "CalorieCardProtein";case .carbs:return "CalorieCardCarbs";case .fat:return "CalorieCardFat"}
    }
}

struct LuqmaCompactTitle:View {
    let title:String
    var body:some View {
        Text(title).luqmaFont(.headline).foregroundStyle(Theme.text)
            .multilineTextAlignment(.center).frame(maxWidth:.infinity,minHeight:Theme.navigationHeight)
            .accessibilityAddTraits(.isHeader)
    }
}

struct LuqmaReviewSection<Content:View>:View {
    let title:String
    let content:Content
    init(title:String,@ViewBuilder content:()->Content){self.title=title;self.content=content()}
    var body:some View {
        VStack(alignment:.leading,spacing:LuqmaReviewStyle.rowGap){
            LuqmaSectionHeader(title:title)
            VStack(alignment:.leading,spacing:LuqmaReviewStyle.rowGap){content}.luqmaCard()
        }
    }
}

struct LuqmaReviewFormSection<Content:View>:View {
    let title:String
    let content:Content
    init(title:String,@ViewBuilder content:()->Content){self.title=title;self.content=content()}
    var body:some View {
        Section{content}header:{Text(title).luqmaFont(.caption).foregroundStyle(Theme.muted)}
    }
}

struct LuqmaReviewSegments<Value:Hashable>:View {
    let options:[Value]
    @Binding var selection:Value
    let label:(Value)->String
    @Environment(\.dynamicTypeSize) private var typeSize
    var body:some View {
        Group {
            if typeSize.isAccessibilitySize {
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:4){items}
            }else{HStack(spacing:4){items}}
        }.padding(4).background(Theme.card,in:RoundedRectangle(cornerRadius:14,style:.continuous))
            .luqmaMotion(.selection,value:selection).luqmaFeedback(.selection,trigger:selection)
    }
    private var items:some View {
        ForEach(options,id:\.self){value in
            Button{selection=value}label:{
                Text(label(value)).luqmaFont(.caption).multilineTextAlignment(.center)
                    .foregroundStyle(selection == value ? Theme.background:Theme.textSecondary)
                    .padding(.horizontal,6).padding(.vertical,4)
                    .frame(maxWidth:.infinity,minHeight:LuqmaReviewStyle.controlHeight)
                    .background(selection == value ? Theme.text:Color.clear,in:RoundedRectangle(cornerRadius:10,style:.continuous))
            }.buttonStyle(LuqmaPressStyle()).accessibilityAddTraits(selection == value ? .isSelected:[])
        }
    }
}

struct LuqmaReviewNumber:View {
    let title:String
    @Binding var value:Double
    var suffix:String=""
    var identifier:String?=nil
    var prominent=false
    var emptyWhenZero=true
    @State private var text=""
    @FocusState private var focused:Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    private var formatted:String {emptyWhenZero && value == 0 ? "":decimal(value,value.rounded()==value ? 0:2)}
    var body:some View {
        Group {
            if prominent || typeSize.isAccessibilitySize {
                VStack(alignment:prominent ? .center:.leading,spacing:12){label;field}
                    .frame(maxWidth:.infinity).padding(.vertical,prominent ? 16:0)
            }else{HStack(spacing:12){label;Spacer(minLength:8);field}}
        }.onAppear{text=formatted}
            .onChange(of:text){_,input in
                guard focused else{return}
                value=TextSearch.number(input).flatMap{$0.isFinite ? $0:nil} ?? 0
            }
            .onChange(of:value){_,number in
                if !focused || abs((TextSearch.number(text) ?? .infinity)-number)>0.000001{text=formatted}
            }
            .onChange(of:focused){_,active in if !active{text=formatted}}
    }
    private var label:some View {
        Text(title).luqmaFont(prominent ? .subheadline:.body).foregroundStyle(prominent ? Theme.muted:Theme.text)
            .fixedSize(horizontal:false,vertical:true)
    }
    private var field:some View {
        HStack(alignment:.firstTextBaseline,spacing:6){
            TextField(title,text:$text,prompt:Text("—").foregroundColor(Theme.muted))
                .keyboardType(.decimalPad).focused($focused).multilineTextAlignment(prominent ? .center:.trailing)
                .luqmaFont(prominent ? .display:.headline).monospacedDigit().foregroundStyle(Theme.text)
                .accessibilityLabel(title).accessibilityIdentifier(identifier ?? title)
                .frame(minWidth:64,maxWidth:prominent ? 180:110,minHeight:LuqmaReviewStyle.controlHeight)
            if !suffix.isEmpty{Text(DisplayFormat.westernDigits(suffix)).luqmaFont(.caption).foregroundStyle(Theme.muted)}
        }.padding(.horizontal,12).padding(.vertical,prominent ? 8:0)
            .background(Theme.input,in:RoundedRectangle(cornerRadius:LuqmaReviewStyle.controlRadius,style:.continuous))
            .overlay{RoundedRectangle(cornerRadius:LuqmaReviewStyle.controlRadius).strokeBorder(focused ? Theme.accent:Theme.stroke,lineWidth:1)}
            .environment(\.layoutDirection,.leftToRight)
            .luqmaMotion(.selection,value:focused)
    }
}

struct LuqmaReviewMacro:View {
    let key:MacroKey
    let amount:Double
    @EnvironmentObject var diary:DiaryStore
    var body:some View {
        VStack(alignment:.leading,spacing:6){
            HStack(spacing:6){
                Image(LuqmaReviewStyle.macroIcon(key)).renderingMode(.template).resizable().scaledToFit()
                    .frame(width:20,height:20).foregroundStyle(LuqmaReviewStyle.macroColor(key)).accessibilityHidden(true)
                Text(key.label(diary.language)).luqmaFont(.caption).foregroundStyle(Theme.muted)
            }
            Text(decimal(amount)+" "+diary.t("جم","g")).luqmaFont(.subheadline).monospacedDigit().luqmaNumericMotion(value:amount)
        }.frame(maxWidth:.infinity,alignment:.leading).accessibilityElement(children:.combine)
    }
}

struct LuqmaReviewNutrition:View {
    let value:Nutrition
    var detail:String?=nil
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dynamicTypeSize) private var typeSize
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            HStack(alignment:.firstTextBaseline,spacing:8){
                Image("CalorieCardFlame").renderingMode(.template).resizable().scaledToFit().frame(width:24,height:24)
                    .foregroundStyle(Theme.accentText).accessibilityHidden(true)
                Text(decimal(value.kcal,0)).luqmaFont(.metric).foregroundStyle(Theme.text).monospacedDigit().luqmaNumericMotion(value:value.kcal)
                Text(diary.t("سعرة","kcal")).luqmaFont(.caption).foregroundStyle(Theme.muted)
            }
            if let detail{Text(detail).luqmaFont(.caption).foregroundStyle(Theme.muted)}
            if typeSize.isAccessibilitySize{VStack(spacing:12){macros}}
            else{HStack(alignment:.top,spacing:12){macros}}
        }
    }
    private var macros:some View {ForEach(MacroKey.allCases){key in LuqmaReviewMacro(key:key,amount:value[key])}}
}

private struct LuqmaReviewKeyboard:ViewModifier {
    @EnvironmentObject var diary:DiaryStore
    func body(content:Content)->some View {
        content.scrollDismissesKeyboard(.interactively).toolbar{
            ToolbarItemGroup(placement:.keyboard){
                Spacer()
                Button{UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)}label:{
                    Text(diary.t("تم","Done")).luqmaFont(.caption)
                }.accessibilityLabel(diary.t("إخفاء لوحة المفاتيح","Dismiss keyboard"))
            }
        }
    }
}
extension View {
    func luqmaReviewKeyboard()->some View {modifier(LuqmaReviewKeyboard())}
}
