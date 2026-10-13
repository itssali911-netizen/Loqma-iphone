import SwiftUI
import Charts

struct DiaryView:View {
    @EnvironmentObject var diary:DiaryStore
    @State private var date=Date()
    @State private var adding=false
    @State private var goals=false
    @State private var selectingDate=false
    @State private var editing:DiaryEntry?
    @State private var chosenMeal:Meal?
    private var day:String {DayKey.string(date)}
    var body:some View {
        ScrollView{diaryContent.padding(20).padding(.bottom,10)}.appBackground().navigationTitle(diary.t("اليوم","Today"))
            .toolbar(.hidden,for:.navigationBar)
            .sheet(isPresented:$adding){FoodAddView(initialMeal:chosenMeal,onPhotoCommit:{foods,meal in do{let entries=try foods.map{try DiaryEntry(food:$0.0,amount:$0.1,unit:$0.2,meal:meal,day:day,language:diary.language)};return diary.add(entries,foods:foods.map{$0.0})}catch{diary.report(error);return false}}){food,amount,unit,meal in do{let entry=try DiaryEntry(food:food,amount:amount,unit:unit,meal:meal,day:day,language:diary.language);return diary.add([entry],foods:[food])}catch{diary.report(error);return false}}}
            .sheet(item:$editing){EntryEditor(entry:$0)}
            .sheet(isPresented:$goals){GoalEditor()}
            .sheet(isPresented:$selectingDate){
                NavigationStack{
                    DatePicker(diary.t("اختيار التاريخ","Choose date"),selection:$date,displayedComponents:.date)
                        .datePickerStyle(.graphical).tint(Theme.accent).padding(20).appBackground()
                        .navigationTitle(diary.t("اختيار التاريخ","Choose date"))
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar{ToolbarItem(placement:.confirmationAction){Button(diary.t("تم","Done")){selectingDate=false}}}
            }.presentationDetents([.medium,.large])
            }
    }
    @ViewBuilder private var diaryContent:some View {
        #if DEBUG
        if CommandLine.arguments.contains("-loqma-preview-meals") {
            mealPreviewContent
        } else { normalDiaryContent }
        #else
        normalDiaryContent
        #endif
    }
    private var normalDiaryContent:some View {
        VStack(alignment:.leading,spacing:16){
            weekSelector
            header
            summary
            LuqmaSectionHeader(title:diary.t("وجباتي","My meals"),detail:diary.t("سجل اليوم","Daily diary"))
            ForEach(MealDiarySummary.forDay(day,entries:diary.state.entries)){mealSection($0)}
        }
    }
    #if DEBUG
    private var mealPreviewContent:some View {
        VStack(alignment:.leading,spacing:14){
            LuqmaSectionHeader(title:diary.t("وجباتي","My meals"),detail:diary.t("مثال للعرض فقط","Preview example only"))
            ForEach(MealDiarySummary.forDay(DayKey.today,entries:mealPreviewEntries)){mealSection($0,showEntries:false)}
        }.allowsHitTesting(false)
    }
    private var mealPreviewEntries:[DiaryEntry] {
        let values:[Nutrition]=[
            Nutrition(kcal:350,protein:25,carbs:35,fat:12),
            Nutrition(kcal:620,protein:45,carbs:70,fat:18),
            Nutrition(kcal:480,protein:35,carbs:40,fat:20),
            Nutrition(kcal:180,protein:12,carbs:15,fat:8)
        ]
        return zip(Meal.allCases,values).compactMap{meal,nutrition in
            let food=Food(name:meal.label(diary.language),unit:.serving,nutrition:nutrition,servingNutrition:nutrition)
            return try? DiaryEntry(food:food,amount:1,unit:.serving,meal:meal,day:DayKey.today,language:diary.language)
        }
    }
    #endif
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
        let calendar=DisplayFormat.calendar(diary.language)
        let start=calendar.dateInterval(of:.weekOfYear,for:date)?.start ?? calendar.startOfDay(for:date)
        return (0..<7).compactMap{calendar.date(byAdding:.day,value:$0,to:start)}
    }
    private func localizedDate(_ value:Date,_ template:String)->String {
        DisplayFormat.date(value,template:template,language:diary.language)
    }
    private var weekSelector:some View {
        HStack(spacing:10){
            HStack(spacing:4){ForEach(weekDates,id:\.self){value in
                let selected=DayKey.string(value)==day
                Button{date=value}label:{VStack(spacing:3){
                    Text(localizedDate(value,"EEEEE")).font(.system(size:9,weight:.medium)).foregroundStyle(selected ? Theme.text:Theme.muted)
                    Text(localizedDate(value,"d")).font(.system(size:13,weight:.semibold)).monospacedDigit().foregroundStyle(Theme.text)
                }.frame(maxWidth:.infinity,minHeight:38).background(selected ? Theme.accent:Theme.background,in:RoundedRectangle(cornerRadius:10,style:.continuous))}.buttonStyle(.plain)
                    .accessibilityLabel(localizedDate(value,"EEEE, d MMMM"))
                    .accessibilityAddTraits(selected ? .isSelected:[])
            }}
            Button{selectingDate=true}label:{
                VStack(spacing:3){
                    HStack(spacing:4){Image(systemName:"calendar");Text(diary.t("اليوم المختار","Selected day"))}.font(.system(size:9,weight:.medium)).foregroundStyle(Theme.muted)
                    Text(day.replacingOccurrences(of:"-",with:"/")).font(.system(size:11,weight:.semibold)).monospacedDigit().foregroundStyle(Theme.text)
                }.frame(width:96).frame(minHeight:38)
            }.buttonStyle(.plain).accessibilityLabel(diary.t("اختيار التاريخ","Choose date"))
                .accessibilityValue(localizedDate(date,"EEEE, d MMMM yyyy"))
        }.padding(10).background(Theme.card,in:RoundedRectangle(cornerRadius:16,style:.continuous))
    }
    private var summary:some View {
        let consumed=diary.total(day),goals=diary.dailyGoals(day)
        return VStack(alignment:.leading,spacing:10){
            LuqmaSectionHeader(title:diary.t("هدف السعرات","Calorie goal"))
            calorieGoal(consumed:consumed.kcal,goal:goals.kcal)
            HStack(spacing:12){
                macroProgress(.carbs,consumed,goals)
                Divider().frame(height:42)
                macroProgress(.protein,consumed,goals)
                Divider().frame(height:42)
                macroProgress(.fat,consumed,goals)
            }.padding(14).background(Theme.surface,in:RoundedRectangle(cornerRadius:18,style:.continuous))
            Button{chosenMeal=nil;adding=true}label:{Label(diary.t("إضافة طعام","Add food"),systemImage:"plus")}.buttonStyle(LuqmaPrimaryButtonStyle())
            if intakeHistory.count>=2{
                DisclosureGroup(diary.t("السعرات خلال آخر 7 أيام","Calories over the last 7 days")){
                    intakeChart.padding(.top,12)
                }.font(.caption).foregroundStyle(Theme.muted).padding(.top,4)
            }
        }
    }
    private func calorieGoal(consumed:Double,goal:Double)->some View {
        let remaining=goal-consumed
        return VStack(alignment:.leading,spacing:12){
            HStack(alignment:.center){HStack(alignment:.firstTextBaseline,spacing:7){Text(decimal(goal,0)).font(.system(size:31,weight:.bold)).monospacedDigit();Text(diary.t("سعرة","kcal")).font(.subheadline)};Spacer();Button{goals=true}label:{Image(systemName:"gearshape").font(.system(size:18)).frame(width:42,height:42).background(Color.white.opacity(0.12),in:RoundedRectangle(cornerRadius:13,style:.continuous)).overlay{RoundedRectangle(cornerRadius:13,style:.continuous).stroke(Color.white.opacity(0.35),lineWidth:1)}}.buttonStyle(.plain).accessibilityLabel(diary.t("تعديل هدف السعرات","Edit calorie goal"))}
            HStack(alignment:.firstTextBaseline,spacing:6){
                Text(decimal(consumed,0)+" / "+decimal(goal,0)).font(.system(size:16,weight:.semibold)).monospacedDigit()
                Text(diary.t("مستهلكة","consumed")).font(.caption)
                Spacer(minLength:8)
                Text(decimal(abs(remaining),0)+" "+(remaining >= 0 ? diary.t("متبقية","left"):diary.t("فوق الهدف","above goal"))).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            ProgressView(value:goal>0 ? min(1,max(0,consumed/goal)):0).tint(Theme.text)
                .accessibilityLabel(diary.t("التقدّم نحو هدف السعرات","Progress toward your calorie goal"))
        }.foregroundStyle(Theme.text).padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Theme.accent,in:RoundedRectangle(cornerRadius:20,style:.continuous))
    }
    private func macroProgress(_ key:MacroKey,_ current:Nutrition,_ goal:Nutrition) -> some View {
        let color=key == .carbs ? Theme.accent:key == .protein ? Theme.secondaryAccent:Theme.text
        let symbol=key == .carbs ? "leaf.fill":key == .protein ? "fish.fill":"drop.fill"
        let progress=goal[key]>0 ? min(1,max(0,current[key]/goal[key])):0
        return VStack(alignment:.leading,spacing:6){
            HStack(spacing:5){Text(key.label(diary.language)).font(.system(size:11,weight:.medium)).foregroundStyle(Theme.muted);Spacer(minLength:0);Image(systemName:symbol).font(.system(size:12)).foregroundStyle(color).accessibilityHidden(true)}
            HStack(alignment:.firstTextBaseline,spacing:3){
                Text(decimal(current[key],0)).font(.system(size:17,weight:.bold)).foregroundStyle(Theme.text)
                Text("/ "+decimal(goal[key],0)+" "+diary.t("جم","g")).font(.system(size:10,weight:.medium)).foregroundStyle(Theme.muted)
            }.monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            ProgressView(value:progress).tint(color)
                .accessibilityLabel(key.label(diary.language)+" "+diary.t("التقدّم اليومي","daily progress"))
        }.frame(maxWidth:.infinity,alignment:.leading).accessibilityElement(children:.combine)
    }
    private struct IntakePoint:Identifiable{var day:String;var date:Date;var kcal:Double;var id:String{day}}
    private var intakeHistory:[IntakePoint]{
        let calendar=DisplayFormat.calendar(diary.language),end=calendar.startOfDay(for:min(date,Date()))
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
            }.chartLegend(.hidden).chartYAxis{AxisMarks(values:.automatic(desiredCount:3)){axis in
                AxisGridLine().foregroundStyle(Theme.stroke)
                AxisValueLabel{if let value=axis.as(Double.self){Text(decimal(value,0))}}.foregroundStyle(Theme.muted)
            }}.chartXAxis{AxisMarks(values:.automatic(desiredCount:4)){axis in
                AxisValueLabel{if let value=axis.as(Date.self){Text(localizedDate(value,"d MMM"))}}.foregroundStyle(Theme.muted)
            }}.frame(height:135).accessibilityLabel(diary.t("السعرات المسجلة خلال آخر سبعة أيام","Calories logged over the last seven days"))
        }
    }
    private func mealSection(_ summary:MealDiarySummary,showEntries:Bool=true) -> some View {
        let meal=summary.meal,items=summary.entries,total=summary.nutrition
        return VStack(alignment:.leading,spacing:10){
            HStack(spacing:12){
                Image(systemName:meal == .snack ? "carrot":meal.symbol).font(.system(size:21)).foregroundStyle(Theme.accent).frame(width:44,height:44).background(Theme.surface,in:RoundedRectangle(cornerRadius:15)).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:4){Text(meal.label(diary.language)).font(.headline);Text("\(decimal(total.kcal,0)) \(diary.t("سعرة","kcal"))").font(.caption).foregroundStyle(Theme.muted)}
                Spacer()
                Button{chosenMeal=meal;adding=true}label:{Image(systemName:"plus").font(.system(size:18,weight:.medium)).frame(width:44,height:44).foregroundStyle(Theme.accent).background(Theme.surface,in:Circle())}.buttonStyle(.plain).accessibilityLabel(diary.t("إضافة إلى ","Add to ")+meal.label(diary.language))
            }
            mealMacros(total)
            if showEntries {
                if items.isEmpty{Text(diary.t("جاهزة لأول لقمة","Ready for your first bite")).font(.footnote).foregroundStyle(Theme.muted)}
                ForEach(items){entry in
                    Button{editing=entry}label:{HStack(spacing:12){
                        VStack(alignment:.leading,spacing:5){Text(DisplayFormat.westernDigits(entry.name)).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text);Text("\(decimal(entry.amount)) × \(entry.unitLabel(diary.language))").font(.caption).foregroundStyle(Theme.muted)}
                        Spacer(minLength:8)
                        Text(decimal(entry.kcal,0)).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.text)
                        Image(systemName:"chevron.forward").font(.caption2).foregroundStyle(Theme.muted)
                    }.padding(.vertical,6).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityHint(diary.t("تعديل الكمية","Edit quantity"))
                    if entry.id != items.last?.id{Divider()}
                }
            }
        }.padding(14).frame(maxWidth:.infinity,alignment:.leading)
            .background(Theme.card,in:RoundedRectangle(cornerRadius:20,style:.continuous))
            .overlay{RoundedRectangle(cornerRadius:20,style:.continuous).stroke(Theme.stroke,lineWidth:0.5)}
    }
    private func mealMacros(_ total:Nutrition)->some View {
        HStack(spacing:10){
            mealMacro(.protein,value:total.protein,color:Theme.secondaryAccent)
            mealMacro(.carbs,value:total.carbs,color:Theme.accent)
            mealMacro(.fat,value:total.fat,color:Theme.text)
        }.padding(.horizontal,10).padding(.vertical,8).background(Theme.surface,in:RoundedRectangle(cornerRadius:12,style:.continuous))
    }
    private func mealMacro(_ key:MacroKey,value:Double,color:Color)->some View {
        VStack(alignment:.leading,spacing:2){
            Text(key.label(diary.language)).font(.system(size:10,weight:.medium)).foregroundStyle(Theme.muted)
            Text(decimal(value)+" "+diary.t("جم","g")).font(.system(size:12,weight:.semibold)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth:.infinity,alignment:.leading).accessibilityElement(children:.combine)
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
            Section{Text(DisplayFormat.westernDigits(entry.name)).font(.headline);TextField(diary.t("الكمية","Amount"),text:$amount).keyboardType(.decimalPad);Text(entry.unitLabel(diary.language)).foregroundStyle(.secondary)}
            Section(diary.t("إجمالي هذه الكمية","Nutrition for this amount")){NutritionView(value:total)}
            Section{Button(diary.t("حفظ التعديل","Save changes")){if let value,diary.resize(entry.id,value){dismiss()}}.disabled(value == nil || (value ?? 0)<=0 || (value ?? 0)>10000);Button(diary.t("حذف الطعام","Delete food"),role:.destructive){deleting=true}}
        }.appBackground().navigationTitle(diary.t("تعديل الطعام","Edit food"))
            .toolbar{ToolbarItem(placement:.cancellationAction){Button(diary.t("إلغاء","Cancel")){dismiss()}}}
            .confirmationDialog(diary.t("حذف الطعام من اليوم؟","Delete this diary entry?"),isPresented:$deleting,titleVisibility:.visible){Button(diary.t("حذف","Delete"),role:.destructive){diary.remove(entry.id);dismiss()}}
        }.onAppear{amount=decimal(entry.amount,entry.amount.rounded()==entry.amount ? 0:2)}
    }
}
