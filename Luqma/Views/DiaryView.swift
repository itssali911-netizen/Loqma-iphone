import SwiftUI

struct DiaryView:View {
    @EnvironmentObject var diary:DiaryStore
    @EnvironmentObject var health:HealthService
    @State private var date=Date()
    @State private var adding=false
    @State private var goals=false
    @State private var editing:DiaryEntry?
    @State private var chosenMeal:Meal?
    private var day:String {DayKey.string(date)}
    var body:some View {
        ScrollView{VStack(alignment:.leading,spacing:24){
            header
            weekSelector
            summary
            activity
            LuqmaSectionHeader(title:diary.t("وجباتك","Your meals"),detail:diary.t("سجل اليوم","Daily diary"))
            ForEach(Meal.allCases){meal in mealSection(meal)}
        }.padding(20).padding(.bottom,10)}.appBackground().navigationTitle(diary.t("اليوم","Today"))
            .toolbar(.hidden,for:.navigationBar)
            .sheet(isPresented:$adding){FoodAddView(initialMeal:chosenMeal,onPhotoCommit:{foods,meal in do{let entries=try foods.map{try DiaryEntry(food:$0.0,amount:$0.1,unit:$0.2,meal:meal,day:day,language:diary.language)};return diary.add(entries,foods:foods.map{$0.0})}catch{diary.report(error);return false}}){food,amount,unit,meal in do{let entry=try DiaryEntry(food:food,amount:amount,unit:unit,meal:meal,day:day,language:diary.language);return diary.add([entry],foods:[food])}catch{diary.report(error);return false}}}
            .sheet(item:$editing){EntryEditor(entry:$0)}
            .sheet(isPresented:$goals){GoalEditor()}
    }
    private var header:some View {
        HStack(spacing:14){
            Image("LuqmaMark").resizable().scaledToFit().frame(width:52,height:52)
                .background(Theme.card,in:RoundedRectangle(cornerRadius:18)).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:5){
                Text(localizedDate(date,"EEEE, d MMMM")).font(.caption.weight(.medium)).foregroundStyle(Theme.muted)
                Text(diary.t("يومك مع لُقمة","Your day with Luqma")).font(.system(size:27,weight:.bold)).foregroundStyle(Theme.text)
            }
            Spacer(minLength:0)
            Button{goals=true}label:{Image(systemName:"target").font(.system(size:21)).frame(width:46,height:46).foregroundStyle(Theme.text).background(Theme.card,in:RoundedRectangle(cornerRadius:15))}.buttonStyle(.plain).accessibilityLabel(diary.t("أهداف السعرات والماكروز","Calorie and macro goals"))
        }.padding(.top,6)
    }
    private var weekDates:[Date] {
        let calendar=Calendar.current
        let start=calendar.dateInterval(of:.weekOfYear,for:date)?.start ?? calendar.startOfDay(for:date)
        return (0..<7).compactMap{calendar.date(byAdding:.day,value:$0,to:start)}
    }
    private func localizedDate(_ value:Date,_ template:String)->String {
        let formatter=DateFormatter();formatter.locale=Locale(identifier:diary.language == .ar ? "ar_SA":"en_US");formatter.setLocalizedDateFormatFromTemplate(template);return formatter.string(from:value)
    }
    private var weekSelector:some View {
        VStack(spacing:14){
            HStack{
                Text(diary.t("خطة اليوم","Today's plan")).font(.subheadline.bold())
                Spacer()
                DatePicker(diary.t("اختيار التاريخ","Choose date"),selection:$date,displayedComponents:.date).labelsHidden().datePickerStyle(.compact).tint(Theme.accent)
            }
            HStack(spacing:6){ForEach(weekDates,id:\.self){value in
                let selected=DayKey.string(value)==day
                Button{date=value}label:{VStack(spacing:8){
                    Text(localizedDate(value,"d")).font(.system(size:16,weight:.semibold)).frame(maxWidth:.infinity).frame(minHeight:42)
                        .foregroundStyle(selected ? Theme.card:Theme.text).background(selected ? Theme.text:Theme.card,in:Circle())
                    Text(localizedDate(value,"EEEEE")).font(.caption).foregroundStyle(selected ? Theme.text:Theme.muted)
                }.frame(maxWidth:.infinity)}.buttonStyle(.plain)
                    .accessibilityLabel(localizedDate(value,"EEEE, d MMMM"))
                    .accessibilityAddTraits(selected ? .isSelected:[])
            }}
        }
    }
    private var summary:some View {
        let consumed=diary.total(day),goals=diary.state.goals
        let remaining=goals.kcal-consumed.kcal
        return VStack(alignment:.leading,spacing:24){
            HStack(alignment:.center,spacing:20){
                VStack(alignment:.leading,spacing:9){
                    Label(diary.t("السعرات اليومية","Daily calories"),systemImage:"flame.fill").font(.subheadline.weight(.medium)).foregroundStyle(Theme.muted)
                    Text(decimal(abs(remaining),0)).font(.system(size:43,weight:.bold,design:.rounded)).monospacedDigit().foregroundStyle(Theme.text).minimumScaleFactor(0.6).lineLimit(1)
                    Text(remaining >= 0 ? diary.t("سعرة متبقية","kcal remaining"):diary.t("سعرة فوق الهدف","kcal above goal")).font(.subheadline).foregroundStyle(Theme.muted)
                }.frame(maxWidth:.infinity,alignment:.leading)
                ZStack{
                    LuqmaProgressRing(progress:goals.kcal>0 ? consumed.kcal/goals.kcal:0)
                    VStack(spacing:3){Text(decimal(consumed.kcal,0)).font(.system(size:22,weight:.bold,design:.rounded)).monospacedDigit();Text(diary.t("مستهلكة","eaten")).font(.caption2).foregroundStyle(Theme.muted)}.padding(16)
                }.frame(width:112,height:112)
            }
            HStack{Text(diary.t("هدفك اليومي","Daily target")).foregroundStyle(Theme.muted);Spacer();Text("\(decimal(goals.kcal,0)) \(diary.t("سعرة","kcal"))").foregroundStyle(Theme.text)}.font(.caption)
            Rectangle().fill(Theme.stroke).frame(height:1)
            HStack(spacing:16){macroProgress(.protein,consumed,goals);macroProgress(.carbs,consumed,goals);macroProgress(.fat,consumed,goals)}
            Button{chosenMeal=nil;adding=true}label:{Label(diary.t("إضافة طعام","Add food"),systemImage:"plus")}.buttonStyle(LuqmaPrimaryButtonStyle())
        }.luqmaCard()
    }
    private func macroProgress(_ key:MacroKey,_ current:Nutrition,_ goal:Nutrition) -> some View {
        let color=key == .protein ? Theme.accent:key == .carbs ? Theme.secondaryAccent:Theme.muted
        return VStack(alignment:.leading,spacing:8){
            Text(key.label(diary.language)).font(.caption).foregroundStyle(Theme.muted)
            Text("\(decimal(current[key],0)) / \(decimal(goal[key],0))").font(.system(size:13,weight:.semibold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
            ProgressView(value:goal[key]>0 ? min(1,max(0,current[key]/goal[key])):0).tint(color)
            Text(diary.t("جم","g")).font(.caption2).foregroundStyle(Theme.muted)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    @ViewBuilder private var activity:some View {
        if diary.state.healthEnabled && day == DayKey.today && (health.steps != nil || health.activeCalories != nil){
            LuqmaSectionHeader(title:diary.t("نشاطك","Your activity"),detail:"Apple Health")
            HStack(spacing:12){
                if let steps=health.steps{activityMetric(diary.t("الخطوات","Steps"),value:decimal(steps,0),symbol:"figure.walk")}
                if let calories=health.activeCalories{activityMetric(diary.t("سعرات النشاط","Active kcal"),value:decimal(calories,0),symbol:"flame")}
            }
        }
    }
    private func activityMetric(_ title:String,value:String,symbol:String)->some View {
        VStack(alignment:.leading,spacing:12){
            Image(systemName:symbol).font(.system(size:20)).foregroundStyle(Theme.accent).frame(width:38,height:38).background(Theme.surface,in:Circle())
            Text(title).font(.subheadline.weight(.medium))
            Text(value).font(.title3.bold()).monospacedDigit()
        }.luqmaCard()
    }
    private func mealSection(_ meal:Meal) -> some View {
        let items=diary.state.entries.filter{$0.day==day && $0.meal==meal},total=items.reduce(Nutrition.zero){$0+$1.nutrition}
        return VStack(alignment:.leading,spacing:14){
            HStack(spacing:12){
                Image(systemName:meal == .snack ? "carrot":meal.symbol).font(.system(size:21)).foregroundStyle(Theme.accent).frame(width:44,height:44).background(Theme.surface,in:RoundedRectangle(cornerRadius:15)).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:4){Text(meal.label(diary.language)).font(.headline);Text("\(decimal(total.kcal,0)) \(diary.t("سعرة","kcal"))").font(.caption).foregroundStyle(Theme.muted)}
                Spacer()
                Button{chosenMeal=meal;adding=true}label:{Image(systemName:"plus").font(.system(size:18,weight:.medium)).frame(width:44,height:44).foregroundStyle(Theme.accent).background(Theme.surface,in:Circle())}.buttonStyle(.plain).accessibilityLabel(diary.t("إضافة إلى ","Add to ")+meal.label(diary.language))
            }
            if items.isEmpty{Text(diary.t("جاهزة لأول لقمة","Ready for your first bite")).font(.footnote).foregroundStyle(Theme.muted)}
            ForEach(items){entry in
                Button{editing=entry}label:{HStack(spacing:12){
                    VStack(alignment:.leading,spacing:5){Text(entry.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text);Text("\(decimal(entry.amount)) × \(entry.unitLabel(diary.language))").font(.caption).foregroundStyle(Theme.muted)}
                    Spacer(minLength:8)
                    Text(decimal(entry.kcal,0)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.text)
                    Image(systemName:"chevron.forward").font(.caption2).foregroundStyle(Theme.muted)
                }.padding(.vertical,6).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityHint(diary.t("تعديل الكمية","Edit quantity"))
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
