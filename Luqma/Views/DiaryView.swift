import SwiftUI
import Charts

struct DiaryView:View {
    @EnvironmentObject var diary:DiaryStore
    @EnvironmentObject var health:HealthService
    @State private var date=Date()
    @State private var adding=false
    @State private var goals=false
    @State private var editing:DiaryEntry?
    @State private var chosenMeal:Meal?
    @State private var selectedMeal:Meal = .breakfast
    private var day:String {DayKey.string(date)}
    var body:some View {
        ScrollView{VStack(alignment:.leading,spacing:20){
            header
            weekSelector
            summary
            activity
            LuqmaSectionHeader(title:diary.t("وجباتي","My meals"),detail:diary.t("سجل اليوم","Daily diary"))
            mealSelector
            mealSection(selectedMeal)
        }.padding(20).padding(.bottom,10)}.appBackground().navigationTitle(diary.t("اليوم","Today"))
            .toolbar(.hidden,for:.navigationBar)
            .sheet(isPresented:$adding){FoodAddView(initialMeal:chosenMeal,onPhotoCommit:{foods,meal in do{let entries=try foods.map{try DiaryEntry(food:$0.0,amount:$0.1,unit:$0.2,meal:meal,day:day,language:diary.language)};return diary.add(entries,foods:foods.map{$0.0})}catch{diary.report(error);return false}}){food,amount,unit,meal in do{let entry=try DiaryEntry(food:food,amount:amount,unit:unit,meal:meal,day:day,language:diary.language);return diary.add([entry],foods:[food])}catch{diary.report(error);return false}}}
            .sheet(item:$editing){EntryEditor(entry:$0)}
            .sheet(isPresented:$goals){GoalEditor()}
    }
    private var header:some View {
        VStack(spacing:16){
            HStack(spacing:12){
                Image("LuqmaMark").resizable().scaledToFit().frame(width:42,height:42)
                    .background(Theme.background,in:RoundedRectangle(cornerRadius:14,style:.continuous)).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:5){
                    Text(localizedDate(date,"EEEE, d MMMM")).font(.system(size:10,weight:.medium)).foregroundStyle(Theme.muted)
                    Text(diary.t("يومك مع لُقمة","Your day with Luqma")).font(.system(size:22,weight:.bold)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength:0)
                Button{goals=true}label:{Image(systemName:"slider.horizontal.3").font(.system(size:18,weight:.medium)).frame(width:42,height:42).foregroundStyle(Theme.text).background(Theme.card,in:RoundedRectangle(cornerRadius:14,style:.continuous))}.buttonStyle(.plain).accessibilityLabel(diary.t("أهداف السعرات والماكروز","Calorie and macro goals"))
            }
            Button{chosenMeal=nil;adding=true}label:{HStack(spacing:10){Image(systemName:"magnifyingglass").font(.system(size:18));Text(diary.t("ابحث عن طعام أو صوّر وجبتك","Search food or scan your meal")).font(.subheadline);Spacer(minLength:0)}.foregroundStyle(Theme.text).padding(14).background(Theme.background,in:RoundedRectangle(cornerRadius:15,style:.continuous))}.buttonStyle(.plain)
        }.padding(16).background(Theme.surface,in:RoundedRectangle(cornerRadius:26,style:.continuous)).padding(.top,6)
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
        VStack(spacing:12){
            HStack{
                Text(diary.t("اليوم المختار","Selected day")).font(.subheadline.bold())
                Spacer()
                DatePicker(diary.t("اختيار التاريخ","Choose date"),selection:$date,displayedComponents:.date).labelsHidden().datePickerStyle(.compact).tint(Theme.accent)
            }
            HStack(spacing:6){ForEach(weekDates,id:\.self){value in
                let selected=DayKey.string(value)==day
                Button{date=value}label:{VStack(spacing:5){
                    Text(localizedDate(value,"EEEEE")).font(.system(size:10,weight:.medium)).foregroundStyle(selected ? Theme.text:Theme.muted)
                    Text(localizedDate(value,"d")).font(.system(size:16,weight:.bold)).foregroundStyle(Theme.text)
                    Circle().fill(selected ? Theme.text:Color.clear).frame(width:3,height:3)
                }.frame(maxWidth:.infinity,minHeight:58).background(selected ? Theme.accent:Theme.background,in:RoundedRectangle(cornerRadius:15,style:.continuous))}.buttonStyle(.plain)
                    .accessibilityLabel(localizedDate(value,"EEEE, d MMMM"))
                    .accessibilityAddTraits(selected ? .isSelected:[])
            }}
        }.padding(14).background(Theme.card,in:RoundedRectangle(cornerRadius:24,style:.continuous))
    }
    private var summary:some View {
        let consumed=diary.total(day),goals=diary.state.goals
        let remaining=goals.kcal-consumed.kcal
        return VStack(alignment:.leading,spacing:16){
            LuqmaSectionHeader(title:diary.t("هدف السعرات","Calorie goal"))
            calorieGoal(consumed:consumed.kcal,goal:goals.kcal)
            VStack(spacing:10){
                Text(diary.t("السعرات المسجلة","Calorie intake")).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
                HStack(alignment:.firstTextBaseline,spacing:7){Image(systemName:"flame.fill").font(.system(size:21)).foregroundStyle(Theme.accent);Text(decimal(consumed.kcal,0)).font(.system(size:42,weight:.bold)).monospacedDigit();Text(diary.t("سعرة","kcal")).font(.subheadline).foregroundStyle(Theme.muted)}
                Text("\(decimal(abs(remaining),0)) "+(remaining >= 0 ? diary.t("سعرة متبقية","kcal left"):diary.t("سعرة فوق الهدف","kcal above goal"))).font(.caption.weight(.medium)).foregroundStyle(Theme.text)
                intakeChart
            }.frame(maxWidth:.infinity).padding(.top,8)
            HStack(spacing:12){macroProgress(.carbs,consumed,goals);macroProgress(.protein,consumed,goals);macroProgress(.fat,consumed,goals)}.padding(18).background(Theme.surface,in:RoundedRectangle(cornerRadius:24,style:.continuous))
            Button{chosenMeal=selectedMeal;adding=true}label:{Label(diary.t("إضافة طعام","Add food"),systemImage:"plus")}.buttonStyle(LuqmaPrimaryButtonStyle())
        }
    }
    private func calorieGoal(consumed:Double,goal:Double)->some View {
        VStack(alignment:.leading,spacing:16){
            HStack(alignment:.center){HStack(alignment:.firstTextBaseline,spacing:7){Text(decimal(goal,0)).font(.system(size:31,weight:.bold)).monospacedDigit();Text(diary.t("سعرة","kcal")).font(.subheadline)};Spacer();Button{goals=true}label:{Image(systemName:"gearshape").font(.system(size:18)).frame(width:42,height:42).background(Color.white.opacity(0.12),in:RoundedRectangle(cornerRadius:13,style:.continuous)).overlay{RoundedRectangle(cornerRadius:13,style:.continuous).stroke(Color.white.opacity(0.35),lineWidth:1)}}.buttonStyle(.plain).accessibilityLabel(diary.t("تعديل هدف السعرات","Edit calorie goal"))}
            ProgressView(value:goal>0 ? min(1,max(0,consumed/goal)):0).tint(Theme.text)
                .accessibilityLabel(diary.t("التقدّم نحو هدف السعرات","Progress toward your calorie goal"))
        }.foregroundStyle(Theme.text).padding(18).frame(maxWidth:.infinity,alignment:.leading).background(Theme.accent,in:RoundedRectangle(cornerRadius:24,style:.continuous))
    }
    private func macroProgress(_ key:MacroKey,_ current:Nutrition,_ goal:Nutrition) -> some View {
        let color=key == .carbs ? Theme.accent:key == .protein ? Theme.secondaryAccent:Theme.text
        let symbol=key == .carbs ? "leaf.fill":key == .protein ? "fish.fill":"drop.fill"
        return VStack(spacing:6){
            Image(systemName:symbol).font(.system(size:17)).foregroundStyle(color).accessibilityHidden(true)
            Text(decimal(current[key],0)+" "+diary.t("جم","g")).font(.system(size:19,weight:.bold)).monospacedDigit().minimumScaleFactor(0.7).lineLimit(1)
            Text(key.label(diary.language)).font(.caption).foregroundStyle(Theme.muted)
            Text(diary.t("من ","of ")+decimal(goal[key],0)+" "+diary.t("جم","g")).font(.system(size:10)).foregroundStyle(Theme.muted)
        }.frame(maxWidth:.infinity).accessibilityElement(children:.combine)
    }
    private struct IntakePoint:Identifiable{var day:String;var date:Date;var kcal:Double;var id:String{day}}
    private var intakeHistory:[IntakePoint]{
        let calendar=Calendar.current,end=calendar.startOfDay(for:min(date,Date()))
        return (0..<7).compactMap{offset in
            guard let value=calendar.date(byAdding:.day,value:offset-6,to:end) else{return nil}
            let key=DayKey.string(value)
            guard diary.state.entries.contains(where:{$0.day==key}) else{return nil}
            return IntakePoint(day:key,date:value,kcal:diary.total(key).kcal)
        }
    }
    @ViewBuilder private var intakeChart:some View {
        let points=intakeHistory
        if points.count>=2{
            Chart(points){point in
                AreaMark(x:.value("Day",point.date),y:.value("Logged calories",point.kcal)).foregroundStyle(LinearGradient(colors:[Theme.accent.opacity(0.35),Theme.accent.opacity(0.025)],startPoint:.top,endPoint:.bottom))
                LineMark(x:.value("Day",point.date),y:.value("Logged calories",point.kcal)).lineStyle(StrokeStyle(lineWidth:2.5)).foregroundStyle(Theme.accent)
                PointMark(x:.value("Day",point.date),y:.value("Logged calories",point.kcal)).symbolSize(20).foregroundStyle(Theme.accent)
            }.chartLegend(.hidden).chartYAxis{AxisMarks(values:.automatic(desiredCount:3)){AxisGridLine().foregroundStyle(Theme.stroke);AxisValueLabel().foregroundStyle(Theme.muted)}}.chartXAxis{AxisMarks(values:.automatic(desiredCount:4)){AxisValueLabel(format:.dateTime.day().month()).foregroundStyle(Theme.muted)}}.frame(height:135).accessibilityLabel(diary.t("السعرات المسجلة خلال آخر سبعة أيام","Calories logged over the last seven days"))
        }
    }
    private var mealSelector:some View {
        HStack(spacing:4){ForEach(Meal.allCases){meal in
            Button{selectedMeal=meal}label:{Text(meal.label(diary.language)).font(.system(size:12,weight:.semibold)).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth:.infinity,minHeight:44).foregroundStyle(selectedMeal == meal ? Theme.text:Theme.muted).background(selectedMeal == meal ? Theme.surface:Color.clear,in:RoundedRectangle(cornerRadius:13,style:.continuous))}.buttonStyle(.plain).accessibilityAddTraits(selectedMeal == meal ? .isSelected:[])
        }}.padding(4).background(Theme.card,in:RoundedRectangle(cornerRadius:17,style:.continuous)).accessibilityLabel(diary.t("الوجبة المعروضة","Displayed meal"))
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
