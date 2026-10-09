import SwiftUI

struct GoalEditor:View {
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dismiss) var dismiss
    @State private var goals=Nutrition.initial,percent=false
    var body:some View {
        NavigationStack{Form{
            Section(diary.t("هدف السعرات","Calorie goal")){NumericInput(title:diary.t("السعرات","Calories"),value:Binding(get:{goals.kcal},set:{goals = $0>0 ? goals.settingCalories($0):Nutrition(kcal:$0,protein:0,carbs:0,fat:0)}),suffix:"kcal");if !(500...10000).contains(goals.kcal){Text(diary.t("أدخل هدفًا بين ٥٠٠ و١٠٠٠٠ سعرة.","Enter a goal from 500 to 10,000 kcal.")).font(.footnote).foregroundStyle(.orange)}}
            Section{
                Picker(diary.t("عرض الماكروز","Macro units"),selection:$percent){Text(diary.t("جرامات","Grams")).tag(false);Text(diary.t("نسبة مئوية","Percent")).tag(true)}.pickerStyle(.segmented)
                ForEach(MacroKey.allCases){key in NumericInput(title:key.label(diary.language),value:Binding(get:{percent ? goals[key]*key.energy/max(1,goals.kcal)*100:goals[key]},set:{goals=percent ? goals.editingPercent(key,value:$0):goals.editing(key,value:$0)}),suffix:percent ? "%":diary.t("جم","g"))}
                Notice(text:diary.t("تعديل أي ماكرو يوزّع السعرات المتبقية على الاثنين الآخرين مع الحفاظ على إجمالي السعرات. التعديل اليدوي يوقف تحديث الهدف من الوزن.", "Editing a macro distributes the remaining calories between the other two. Manual edits pause weight-based goal updates."))
            }.disabled(!(500...10000).contains(goals.kcal))
            Section{NutritionView(value:goals);Text("4P + 4C + 9F = \(decimal(goals.macroCalories,0)) kcal").font(.caption).foregroundStyle(.secondary).environment(\.layoutDirection,.leftToRight)}
        }.appBackground().navigationTitle(diary.t("أهداف الماكروز","Macro goals"))
            .toolbar{ToolbarItem(placement:.cancellationAction){Button(diary.t("إلغاء","Cancel")){dismiss()}};ToolbarItem(placement:.confirmationAction){Button(diary.t("حفظ","Save")){if diary.setGoals(goals){dismiss()}}.disabled(!goals.valid || !(500...10000).contains(goals.kcal))}}
        }.onAppear{goals=diary.state.goals.balanced()}
    }
}
