import SwiftUI

struct DiaryView:View {
    @EnvironmentObject var diary:DiaryStore
    @EnvironmentObject var health:HealthService
    @State private var date=Date()
    @State private var adding=false
    @State private var goals=false
    @State private var editing:DiaryEntry?
    private var day:String {DayKey.string(date)}
    var body:some View {
        ScrollView{VStack(spacing:20){
            DatePicker(diary.t("اليوم","Day"),selection:$date,displayedComponents:.date).datePickerStyle(.compact)
            summary
            if diary.state.healthEnabled && day == DayKey.today && (health.steps != nil || health.activeCalories != nil) {
                HStack {
                    Label("Apple Health", systemImage: "heart.fill").foregroundStyle(.pink)
                    Spacer()
                    if let steps = health.steps { Label(decimal(steps, 0), systemImage: "figure.walk") }
                    if let calories = health.activeCalories { Label("\(decimal(calories,0)) kcal", systemImage: "flame") }
                }.font(.caption).luqmaCard()
            }
            Button{adding=true}label:{Label(diary.t("إضافة طعام","Add food"),systemImage:"plus").frame(maxWidth:.infinity).padding(10)}.buttonStyle(.borderedProminent)
            ForEach(Meal.allCases){meal in mealSection(meal)}
        }.padding(20)}.appBackground().navigationTitle(diary.t("لُقمة","Luqma"))
            .toolbar{ToolbarItem(placement:.topBarTrailing){Button{goals=true}label:{Image(systemName:"target")}.accessibilityLabel(diary.t("أهداف الماكروز","Macro goals"))}}
            .sheet(isPresented:$adding){FoodAddView(onPhotoCommit:{foods,meal in do{let entries=try foods.map{try DiaryEntry(food:$0.0,amount:$0.1,unit:$0.2,meal:meal,day:day,language:diary.language)};return diary.add(entries,foods:foods.map{$0.0})}catch{diary.report(error);return false}}){food,amount,unit,meal in do{let entry=try DiaryEntry(food:food,amount:amount,unit:unit,meal:meal,day:day,language:diary.language);return diary.add([entry],foods:[food])}catch{diary.report(error);return false}}}
            .sheet(item:$editing){EntryEditor(entry:$0)}
            .sheet(isPresented:$goals){GoalEditor()}
    }
    private var summary:some View {
        let consumed=diary.total(day),goals=diary.state.goals
        return VStack(alignment:.leading,spacing:18){
            HStack{Text(diary.t("المتبقي لليوم","Remaining today")).foregroundStyle(Theme.muted);Spacer();Text("\(decimal(goals.kcal,0)) \(diary.t("هدفك","goal"))").font(.caption).foregroundStyle(Theme.muted)}
            HStack(alignment:.firstTextBaseline){Text(decimal(goals.kcal-consumed.kcal,0)).font(.system(size:46,weight:.bold,design:.rounded)).foregroundStyle(Theme.accent);Text(diary.t("سعرة","kcal"))}
            ProgressView(value:min(1,max(0,consumed.kcal/goals.kcal))).tint(Theme.accent)
            Text("\(decimal(consumed.kcal,0)) "+diary.t("سعرة مستهلكة","kcal eaten")).font(.footnote).foregroundStyle(Theme.muted)
            HStack{macroProgress(.protein,consumed,goals);macroProgress(.carbs,consumed,goals);macroProgress(.fat,consumed,goals)}
        }.luqmaCard()
    }
    private func macroProgress(_ key:MacroKey,_ current:Nutrition,_ goal:Nutrition) -> some View {VStack(alignment:.leading,spacing:7){Text(key.label(diary.language)).font(.caption).foregroundStyle(Theme.muted);Text("\(decimal(current[key])) / \(decimal(goal[key],0))").font(.caption.bold()).monospacedDigit();ProgressView(value:goal[key]>0 ? min(1,current[key]/goal[key]):0)}.frame(maxWidth:.infinity,alignment:.leading)}
    private func mealSection(_ meal:Meal) -> some View {
        let items=diary.state.entries.filter{$0.day==day && $0.meal==meal},total=items.reduce(Nutrition.zero){$0+$1.nutrition}
        return VStack(alignment:.leading,spacing:14){
            HStack{Label(meal.label(diary.language),systemImage:meal.symbol).font(.headline);Spacer();Text("\(decimal(total.kcal,0))").foregroundStyle(Theme.muted)}
            if items.isEmpty{Text(diary.t("لم تضف طعامًا بعد","No food added yet")).font(.footnote).foregroundStyle(Theme.muted)}
            ForEach(items){entry in
                HStack{Button{editing=entry}label:{VStack(alignment:.leading,spacing:5){Text(entry.name).foregroundStyle(.primary);Text("\(decimal(entry.amount)) × \(entry.unitLabel(diary.language)) · \(decimal(entry.kcal,0)) \(diary.t("سعرة","kcal"))").font(.caption).foregroundStyle(Theme.muted)}}.buttonStyle(.plain);Spacer();Button{editing=entry}label:{Image(systemName:"pencil")}.accessibilityLabel(diary.t("تعديل الكمية","Edit quantity"))}
                if entry.id != items.last?.id{Divider()}
            }
        }.luqmaCard()
    }
}
struct EntryEditor:View {
    var entry:DiaryEntry
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var amount=""
    @State private var deleting=false
    private var value:Double? {TextSearch.number(amount)}
    private var total:Nutrition {entry.nutrition.scaled((value ?? 0)/max(entry.amount,0.001))}
    var body:some View {
        NavigationStack{Form{
            Section{Text(entry.name).font(.headline);TextField(diary.t("الكمية","Amount"),text:$amount).keyboardType(.decimalPad);Text(entry.unitLabel(diary.language)).foregroundStyle(.secondary)}
            Section(diary.t("إجمالي هذه الكمية","Nutrition for this amount")){NutritionView(value:total)}
            Section{Button(diary.t("حفظ التعديل","Save changes")){if let value,diary.resize(entry.id,value){dismiss()}}.disabled(value == nil || (value ?? 0)<=0 || (value ?? 0)>10000);Button(diary.t("حذف الطعام","Delete food"),role:.destructive){deleting=true}}
        }.appBackground().navigationTitle(diary.t("تعديل الطعام","Edit food"))
            .toolbar{ToolbarItem(placement:.cancellationAction){Button(diary.t("إلغاء","Cancel")){dismiss()}}}
            .confirmationDialog(diary.t("حذف الطعام من اليوم؟","Delete this diary entry?"),isPresented:$deleting,titleVisibility:.visible){Button(diary.t("حذف","Delete"),role:.destructive){diary.remove(entry.id);dismiss()}}
        }.onAppear{amount=decimal(entry.amount,entry.amount.rounded()==entry.amount ? 0:2)}
    }
}
