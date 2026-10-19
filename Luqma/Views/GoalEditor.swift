import SwiftUI

struct GoalEditor:View {
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dismiss) var dismiss
    @State private var goals=Nutrition.initial
    @State private var percent=false
    @State private var editingCalories=false
    @State private var editingMacro:MacroKey?
    private var canSave:Bool {goals.valid && (500...10000).contains(goals.kcal)}
    private var calorieBinding:Binding<Double> {
        Binding(get:{goals.kcal},set:{goals = $0>0 ? goals.settingCalories($0):Nutrition(kcal:$0,protein:0,carbs:0,fat:0)})
    }
    var body:some View {
        NavigationStack{
            ScrollView{VStack(spacing:24){
                calorieHero
                calorieSlider
                macroTiles
                goalStatus
                DisclosureGroup(diary.t("تفاصيل الهدف","Goal details")){
                    VStack(alignment:.leading,spacing:12){
                        Notice(text:balancingMessage)
                        Text("4P + 4C + 9F = \(decimal(goals.macroCalories,0)) kcal")
                            .luqmaFont(.caption).foregroundStyle(Theme.muted).environment(\.layoutDirection,.leftToRight)
                    }.padding(.top,10)
                }.luqmaFont(size:12,relativeTo:.caption).tint(Theme.muted)
            }.padding(.horizontal,16).padding(.top,28).padding(.bottom,24)}.appBackground()
                .sandowNavigation(diary.t("هدف السعرات","Calorie goal"),backLabel:diary.t("إلغاء","Cancel"),onBack:{dismiss()})
                .safeAreaInset(edge:.bottom,spacing:0){saveButton.padding(.horizontal,16).padding(.top,12).padding(.bottom,20).background(Theme.background)}
                .sheet(isPresented:$editingCalories){calorieEditor}
                .sheet(item:$editingMacro){key in macroEditor(key)}
        }.onAppear{goals=diary.state.goals.balanced()}
    }
    private var calorieHero:some View {
        VStack(spacing:12){
            Image(systemName:"flame.fill").font(.system(size:23)).foregroundStyle(Theme.accent).accessibilityHidden(true)
            Button{editingCalories=true}label:{
                VStack(spacing:6){
                    Text(decimal(goals.kcal,0)).luqmaFont(size:44,weight:.bold,relativeTo:.largeTitle).monospacedDigit()
                    Text(diary.t("سعرة حرارية","kilo calories")).luqmaFont(size:18,relativeTo:.title3).foregroundStyle(Theme.muted)
                }.foregroundStyle(Theme.text).frame(maxWidth:.infinity,minHeight:92)
            }.buttonStyle(.plain).accessibilityLabel(diary.t("تعديل هدف السعرات","Edit calorie goal"))
                .accessibilityValue(decimal(goals.kcal,0)).accessibilityIdentifier("goals.editCalories")
        }.frame(maxWidth:.infinity)
    }
    private var calorieSlider:some View {
        Slider(value:Binding(get:{min(10000,max(500,goals.kcal.isFinite ? goals.kcal:500))},set:{calorieBinding.wrappedValue=$0}),in:500...10000,step:10)
            .tint(Theme.accent).padding(.horizontal,18).frame(minHeight:64)
            .background(LinearGradient(colors:[Theme.accent.opacity(0.45),Theme.accent.opacity(0.75),Theme.accent.opacity(0.4)],startPoint:.leading,endPoint:.trailing),in:RoundedRectangle(cornerRadius:18,style:.continuous))
            .accessibilityLabel(diary.t("هدف السعرات","Calorie goal"))
            .accessibilityValue(decimal(goals.kcal,0)).accessibilityIdentifier("goals.slider")
    }
    @ViewBuilder private var macroTiles:some View {
        ViewThatFits(in:.horizontal){
            HStack(spacing:12){ForEach(MacroKey.allCases){key in macroTile(key)}}
            VStack(spacing:12){ForEach(MacroKey.allCases){key in macroTile(key)}}
        }.disabled(!(500...10000).contains(goals.kcal))
    }
    private func macroTile(_ key:MacroKey)->some View {
        Button{editingMacro=key}label:{
            VStack(spacing:10){
                VStack(spacing:5){
                    Text(decimal(goals[key])+" "+diary.t("جم","g"))
                        .luqmaFont(size:18,weight:.bold,relativeTo:.headline).monospacedDigit()
                    Text(key.label(diary.language)).luqmaFont(size:11,relativeTo:.caption)
                }.foregroundStyle(Theme.text).frame(maxWidth:.infinity,minHeight:94)
                    .background(Theme.card,in:RoundedRectangle(cornerRadius:20,style:.continuous))
                RoundedRectangle(cornerRadius:5).fill(macroColor(key)).frame(width:15,height:15)
                    .overlay{RoundedRectangle(cornerRadius:5).strokeBorder(Theme.background,lineWidth:2)}
            }.contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(diary.t("تعديل ","Edit ")+key.label(diary.language))
            .accessibilityValue(decimal(goals[key])+" "+diary.t("جم","g"))
            .accessibilityIdentifier("goals.macro."+key.rawValue)
    }
    private func macroColor(_ key:MacroKey)->Color {key == .protein ? Theme.accent:key == .carbs ? Theme.secondaryAccent:Theme.text}
    private var goalStatus:some View {
        Label(canSave ? diary.t("هدفك جاهز للحفظ","Your goal is ready to save"):diary.t("أدخل هدفًا بين 500 و10000 سعرة","Enter a goal from 500 to 10,000 kcal"),systemImage:canSave ? "checkmark.circle.fill":"exclamationmark.circle")
            .luqmaFont(size:12,weight:.medium,relativeTo:.caption)
            .foregroundStyle(canSave ? Theme.success:Theme.warning)
            .padding(.horizontal,12).padding(.vertical,10).frame(maxWidth:.infinity,alignment:.leading)
            .background(canSave ? Theme.success.opacity(0.08):Theme.card,in:RoundedRectangle(cornerRadius:12,style:.continuous))
            .overlay{RoundedRectangle(cornerRadius:12).strokeBorder(canSave ? Theme.success:Theme.warning,lineWidth:1)}
    }
    private var saveButton:some View {
        Button{if diary.setGoals(goals){dismiss()}}label:{
            HStack(spacing:12){Text(diary.t("حفظ هدف السعرات","Set calorie goal"));Image(systemName:"checkmark").font(.system(size:15,weight:.medium))}
                .luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline).foregroundStyle(Theme.background)
                .frame(maxWidth:.infinity,minHeight:56).background(Theme.text,in:RoundedRectangle(cornerRadius:12,style:.continuous))
        }.buttonStyle(.plain).disabled(!canSave).opacity(canSave ? 1:0.4).accessibilityIdentifier("goals.save")
    }
    private var calorieEditor:some View {
        NavigationStack{Form{
            Section(diary.t("هدف السعرات","Calorie goal")){
                NumericInput(title:diary.t("السعرات","Calories"),value:calorieBinding,suffix:"kcal",identifier:"goals.calories")
                if !(500...10000).contains(goals.kcal){Notice(text:diary.t("أدخل هدفًا بين 500 و10000 سعرة.","Enter a goal from 500 to 10,000 kcal."))}
            }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
        }.sandowForm().sandowNavigation(diary.t("تعديل السعرات","Edit calories"),backLabel:diary.t("تم","Done"),onBack:{editingCalories=false})}
            .presentationDetents([.medium,.large])
    }
    private func macroEditor(_ key:MacroKey)->some View {
        NavigationStack{Form{
            Section{
                Picker(diary.t("عرض الماكروز","Macro units"),selection:$percent){Text(diary.t("جرامات","Grams")).tag(false);Text(diary.t("نسبة مئوية","Percent")).tag(true)}.pickerStyle(.segmented)
                NumericInput(title:key.label(diary.language),value:Binding(get:{percent ? goals[key]*key.energy/max(1,goals.kcal)*100:goals[key]},set:{goals=percent ? goals.editingPercent(key,value:$0):goals.editing(key,value:$0)}),suffix:percent ? "%":diary.t("جم","g"))
                    .accessibilityIdentifier("goals.input."+key.rawValue)
            }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            Section{Notice(text:balancingMessage);NutritionView(value:goals)}.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
        }.sandowForm().sandowNavigation(key.label(diary.language),backLabel:diary.t("تم","Done"),onBack:{editingMacro=nil})}
            .presentationDetents([.medium,.large])
    }
    private var balancingMessage:String {diary.t("تعديل أي ماكرو يوزّع السعرات المتبقية على الاثنين الآخرين مع الحفاظ على إجمالي السعرات. التعديل اليدوي يوقف تحديث الهدف من الوزن.","Editing a macro distributes the remaining calories between the other two. Manual edits pause weight-based goal updates.")}
}
