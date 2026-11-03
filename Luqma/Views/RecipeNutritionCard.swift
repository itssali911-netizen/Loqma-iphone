import SwiftUI
import UIKit

/// Native, data-bound implementation of recipe-card-edit-package.zip.
/// Its component-local fonts/colors intentionally do not replace LUQMA's theme.
struct RecipeNutritionCard:View {
    let recipe:Recipe
    let language:AppLanguage
    let onDetails:()->Void
    let onEdit:()->Void
    let onDelete:()->Void
    let onAdd:()->Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo:.headline) private var headerHeight:CGFloat=52
    @ScaledMetric(relativeTo:.caption) private var summaryHeight:CGFloat=26
    @ScaledMetric(relativeTo:.caption) private var macroHeight:CGFloat=56
    @ScaledMetric(relativeTo:.headline) private var actionHeight:CGFloat=48
    private var perServing:Nutrition {recipe.total.scaled(1/recipe.portions)}
    private func t(_ ar:String,_ en:String)->String {language.text(ar,en)}
    private var kind:String {
        switch recipe.type {
        case "meal":return t("وجبة محفوظة","Saved meal")
        case "prep":return t("تحضير وجبات","Meal prep")
        default:return t("وصفة","Recipe")
        }
    }
    var body:some View {
        VStack(alignment:.leading,spacing:16){
            header
            summary
            macros
            Button(action:onAdd){
                HStack(spacing:8){
                    Image("RecipeCardPlus").resizable().scaledToFit().frame(width:20,height:20)
                        .accessibilityHidden(true)
                    Text(t("إضافة حصة","Log serving"))
                        .modifier(RecipeCardTypography(face:"Changa-SemiBold",size:15,lineHeight:26,relativeTo:.headline))
                        .fixedSize(horizontal:false,vertical:true)
                }.foregroundStyle(RecipeCardStyle.buttonText)
                    .frame(maxWidth:.infinity,minHeight:actionHeight)
                    .contentShape(RoundedRectangle(cornerRadius:12))
            }.buttonStyle(RecipeCardAddStyle())
                .accessibilityIdentifier("recipeCard.add."+recipe.id.uuidString)
        }.padding(.horizontal,20).padding(.top,20).padding(.bottom,22)
            .frame(maxWidth:.infinity,minHeight:272,alignment:.topLeading)
            .foregroundStyle(RecipeCardStyle.text)
            .background(RecipeCardStyle.surface,in:RoundedRectangle(cornerRadius:16,style:.circular))
            .accessibilityElement(children:.contain)
            .accessibilityIdentifier("recipeCard."+recipe.id.uuidString)
    }
    private var header:some View {
        HStack(alignment:.center,spacing:12){
            VStack(alignment:.leading,spacing:0){
                Text(DisplayFormat.westernDigits(recipe.name))
                    .modifier(RecipeCardTypography(face:"Changa-Bold",size:18,lineHeight:30,relativeTo:.headline))
                    .frame(minHeight:30,alignment:.leading)
                    .fixedSize(horizontal:false,vertical:true)
                    .accessibilityAddTraits(.isHeader)
                Text(kind).modifier(RecipeCardTypography(face:"Changa-Regular",size:12,lineHeight:22,relativeTo:.caption))
                    .foregroundStyle(RecipeCardStyle.secondary).frame(minHeight:22)
            }.frame(maxWidth:.infinity,minHeight:headerHeight,alignment:.leading)
            HStack(spacing:8){
                Button(action:onDetails){
                    Image("RecipeCardChevron").resizable().scaledToFit().frame(width:20,height:20)
                        // Only this directional chevron mirrors in English.
                        .scaleEffect(x:language == .ar ? 1:-1,y:1)
                        .frame(width:44,height:44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(t("تفاصيل الوصفة","Recipe details"))
                    .accessibilityHint(t("عرض المكونات والتفاصيل وخطوات التحضير","View ingredients, details and preparation steps"))
                    .accessibilityIdentifier("recipeCard.details."+recipe.id.uuidString)
                Menu{
                    Button(t("تعديل","Edit"),action:onEdit)
                    Button(t("حذف","Delete"),role:.destructive,action:onDelete)
                }label:{
                    Image("RecipeCardMore").resizable().scaledToFit().frame(width:20,height:20)
                        .frame(width:44,height:44).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(RecipeCardStyle.text)
                    .accessibilityLabel(t("خيارات ","Options for ")+recipe.name)
                    .accessibilityIdentifier("recipeCard.more."+recipe.id.uuidString)
            }.fixedSize()
        }.frame(minHeight:headerHeight,alignment:.top)
    }
    private var summary:some View {
        ViewThatFits(in:.horizontal){
            HStack(spacing:8){
                calorieLine.accessibilityElement(children:.combine)
                    .accessibilityIdentifier("recipeCard.energy."+recipe.id.uuidString)
                Spacer(minLength:8)
                servingLine.foregroundStyle(RecipeCardStyle.secondary).accessibilityElement(children:.combine)
            }
            VStack(alignment:.leading,spacing:8){calories;servings}
        }.frame(maxWidth:.infinity,minHeight:summaryHeight,alignment:.leading)
    }
    private var calorieLine:some View {
        HStack(alignment:.center,spacing:8){calorieIcon;calorieAmount;calorieUnit}.fixedSize()
    }
    private var calories:some View {
        ViewThatFits(in:.horizontal){
            calorieLine
            VStack(alignment:.leading,spacing:4){
                HStack(spacing:8){calorieIcon;calorieAmount}
                calorieUnit
            }
        }.accessibilityElement(children:.combine)
            .accessibilityIdentifier("recipeCard.energy."+recipe.id.uuidString)
    }
    private var calorieIcon:some View {
        Image("RecipeCardCalories").resizable().scaledToFit().frame(width:20,height:20)
            .foregroundStyle(RecipeCardStyle.calories).accessibilityHidden(true)
    }
    private var calorieAmount:some View {
        Text(decimal(perServing.kcal,0))
            .modifier(RecipeCardTypography(face:"WorkSans-SemiBold",size:20,lineHeight:26,relativeTo:.caption))
            .environment(\.layoutDirection,.leftToRight)
            .fixedSize(horizontal:false,vertical:true)
            .accessibilityIdentifier("recipeCard.calories."+recipe.id.uuidString)
    }
    private var calorieUnit:some View {
        Text(t("سعرة للحصة","kcal per serving"))
            .modifier(RecipeCardTypography(face:"Changa-Regular",size:12,lineHeight:22,relativeTo:.caption))
            .foregroundStyle(RecipeCardStyle.secondary)
            .fixedSize(horizontal:false,vertical:true)
    }
    private var servingLine:some View {
        HStack(spacing:4){servingAmount;servingUnit}.fixedSize()
    }
    private var servings:some View {
        ViewThatFits(in:.horizontal){
            servingLine
            VStack(alignment:.leading,spacing:0){servingAmount;servingUnit}
        }.foregroundStyle(RecipeCardStyle.secondary)
            .accessibilityElement(children:.combine)
    }
    private var servingAmount:some View {
        Text(decimal(recipe.portions,1))
            .modifier(RecipeCardTypography(face:"WorkSans-Medium",size:14,lineHeight:22,relativeTo:.caption))
            .environment(\.layoutDirection,.leftToRight)
            .fixedSize(horizontal:false,vertical:true)
    }
    private var servingUnit:some View {
        Text(t("حصة","servings"))
            .modifier(RecipeCardTypography(face:"Changa-Regular",size:12,lineHeight:22,relativeTo:.caption))
            .fixedSize(horizontal:false,vertical:true)
    }
    @ViewBuilder private var macros:some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing:16){ForEach(MacroKey.allCases){macro($0)}}
        }else{
            HStack(spacing:12){
                macro(.protein)
                separator
                macro(.carbs)
                separator
                macro(.fat)
            }.frame(minHeight:macroHeight)
        }
    }
    private var separator:some View {
        Rectangle().fill(RecipeCardStyle.divider).frame(width:1,height:30).accessibilityHidden(true)
    }
    private func macro(_ key:MacroKey)->some View {
        VStack(spacing:4){
            HStack(spacing:4){
                LuqmaMacroIcon(key:key,size:20)
                Text(key.label(language))
                    .modifier(RecipeCardTypography(face:"Changa-Medium",size:13,lineHeight:24,relativeTo:.caption))
                    .foregroundStyle(RecipeCardStyle.secondary)
                    .fixedSize(horizontal:false,vertical:true)
            }.frame(minHeight:24)
            ViewThatFits(in:.horizontal){
                macroAmount(key)
                VStack(spacing:0){amount(key);unit}
            }.frame(minHeight:27)
        }.frame(maxWidth:.infinity,minHeight:macroHeight,alignment:.top)
            .accessibilityElement(children:.combine)
            .accessibilityIdentifier("recipeCard.macro."+key.rawValue+"."+recipe.id.uuidString)
    }
    private func macroAmount(_ key:MacroKey)->some View {
        HStack(alignment:.firstTextBaseline,spacing:4){amount(key);unit}.fixedSize()
    }
    private func amount(_ key:MacroKey)->some View {
        Text(decimal(perServing[key],1))
            .modifier(RecipeCardTypography(face:"WorkSans-SemiBold",size:20,lineHeight:26,relativeTo:.caption))
            .environment(\.layoutDirection,.leftToRight)
    }
    private var unit:some View {
        Text(t("جم","g")).modifier(RecipeCardTypography(face:"Changa-Regular",size:12,lineHeight:22,relativeTo:.caption))
            .foregroundStyle(RecipeCardStyle.secondary)
    }
}

/// Figma's explicit line boxes are shorter than Changa's default ascender/
/// descender box. Adjust only layout leading, never glyph size or clipping.
/// For n lines: n * native + (n-1) * correction + correction = n * target.
private struct RecipeCardTypography:ViewModifier {
    let face:String
    @ScaledMetric private var size:CGFloat
    @ScaledMetric private var lineHeight:CGFloat
    init(face:String,size:CGFloat,lineHeight:CGFloat,relativeTo:Font.TextStyle){
        self.face=face
        _size=ScaledMetric(wrappedValue:size,relativeTo:relativeTo)
        _lineHeight=ScaledMetric(wrappedValue:lineHeight,relativeTo:relativeTo)
    }
    func body(content:Content)->some View {
        let natural=UIFont(name:face,size:size)?.lineHeight ?? lineHeight
        content.font(.custom(face,fixedSize:size))
            .lineSpacing(lineHeight-natural)
            .padding(.vertical,(lineHeight-natural)/2)
    }
}

private enum RecipeCardStyle {
    static let surface=Color(red:36/255,green:38/255,blue:43/255)
    static let divider=Color(red:57/255,green:60/255,blue:67/255)
    static let text=Color(red:243/255,green:243/255,blue:244/255)
    static let secondary=Color(red:186/255,green:187/255,blue:190/255)
    static let button=Color(red:249/255,green:115/255,blue:22/255)
    static let buttonPressed=Color(red:234/255,green:88/255,blue:12/255)
    static let buttonText=Color(red:17/255,green:18/255,blue:20/255)
    static let calories=Color(red:225/255,green:148/255,blue:92/255)
}
private struct RecipeCardAddStyle:ButtonStyle {
    func makeBody(configuration:Configuration)->some View {
        configuration.label.background(configuration.isPressed ? RecipeCardStyle.buttonPressed:RecipeCardStyle.button,
                                       in:RoundedRectangle(cornerRadius:12,style:.circular))
    }
}

#if DEBUG
/// Disposable review data only: never inserted into a user's diary or catalog.
/// Native tests exercise the same card and the existing real destination views.
struct RecipeCardReviewView:View {
    @StateObject private var store=DiaryStore(previewSnapshot:RecipeCardReviewData.snapshot)
    var body:some View {
        RecipeCardReviewContent().environmentObject(store)
            .environment(\.layoutDirection,store.language == .ar ? .rightToLeft:.leftToRight)
            .environment(\.locale,DisplayFormat.locale(store.language))
            .environment(\.calendar,DisplayFormat.calendar(store.language))
    }
}
private enum RecipeCardReviewData {
    static let id=UUID(uuidString:"9A7949BB-87ED-47FD-9FB3-B833B6927986")!
    static var snapshot:DiarySnapshot {
        var value=DiarySnapshot()
        value.language=ProcessInfo.processInfo.arguments.contains("-loqma-recipe-card-en") ? .en:.ar
        let long=ProcessInfo.processInfo.arguments.contains("-loqma-recipe-card-long")
        let large=ProcessInfo.processInfo.arguments.contains("-loqma-recipe-card-large")
        let title=long ? value.language.text("صوص رانش دايت منزلي مع الأعشاب والخضار الطازجة لوصفة طويلة للتأكد من التفاف النص دون قص","Homemade diet ranch sauce with fresh herbs and vegetables — a long recipe title for layout validation"):value.language.text("صوص رانش دايت","Diet ranch sauce")
        value.recipes=[Recipe(id:id,name:title,type:"recipe",
            ingredients:[Ingredient(id:id,name:value.language.text("مكونات معاينة التصميم","Design review ingredients"),amount:1,unit:.serving,kcal:large ? 99999:588,protein:large ? 99999.9:35.9,carbs:large ? 88888.8:26,fat:large ? 77777.7:36.5)],portions:1,cookedWeight:nil,notes:"")]
        return value
    }
}
private struct RecipeCardReviewContent:View {
    @EnvironmentObject private var diary:DiaryStore
    @State private var selected:Food?
    @State private var details:Recipe?
    @State private var editing:Recipe?
    @State private var deleting:Recipe?
    private var width:CGFloat {ProcessInfo.processInfo.arguments.contains("-loqma-recipe-card-320") ? 320:390}
    var body:some View {
        NavigationStack{
            ScrollView{
                ForEach(diary.state.recipes){recipe in
                    RecipeNutritionCard(recipe:recipe,language:diary.language,
                        onDetails:{guard details == nil else{return};details=recipe},
                        onEdit:{guard editing == nil else{return};editing=recipe},onDelete:{deleting=recipe},
                        onAdd:{guard selected == nil else{return};selected=try? recipe.food()})
                        .frame(maxWidth:width).padding(.vertical,24)
                }
                if ProcessInfo.processInfo.arguments.contains("-loqma-recipe-card-interactions") {
                    Text("Review diary entries: \(diary.state.entries.count)")
                        .accessibilityIdentifier("recipeCard.review.entries")
                }
            }.background(Theme.background)
                .sheet(item:$details){recipe in RecipeDetailView(recipeID:recipe.id)}
                .sheet(item:$editing){RecipeEditor(recipe:$0)}
                .sheet(item:$selected){food in FoodPortionView(food:food){food,amount,unit,meal in
                    do{return diary.add([try DiaryEntry(food:food,amount:amount,unit:unit,meal:meal,day:DayKey.today,language:diary.language)],foods:[food])}
                    catch{diary.report(error);return false}
                }}
                .confirmationDialog(diary.t("حذف الوصفة؟","Delete recipe?"),isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}}),titleVisibility:.visible){
                    Button(diary.t("حذف","Delete"),role:.destructive){if let recipe=deleting{diary.removeRecipe(recipe.id)};deleting=nil}
                }
        }.accessibilityIdentifier("recipeCard.review")
    }
}
#endif
