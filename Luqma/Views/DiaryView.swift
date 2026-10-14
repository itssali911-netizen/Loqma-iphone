import SwiftUI
import Charts

struct DiaryView:View {
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var date=Date()
    @State private var adding=false
    @State private var goals=false
    @State private var selectingDate=false
    @State private var editing:DiaryEntry?
    @State private var chosenMeal:Meal?
    @State private var expandedMeals:Set<Meal>=[]
    private var day:String {DayKey.string(date)}
    var body:some View {
        ScrollView{diaryContent.padding(.horizontal,30).padding(.top,16).padding(.bottom,24)}.appBackground().navigationTitle(diary.t("اليوم","Today"))
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
        }else if CommandLine.arguments.contains("-loqma-preview-overview"){
            overviewPreviewContent
        } else { normalDiaryContent }
        #else
        normalDiaryContent
        #endif
    }
    private var normalDiaryContent:some View {
        VStack(alignment:.leading,spacing:24){
            header
            weekSelector
            summary
            mealGrid(MealDiarySummary.forDay(day,entries:diary.state.entries))
        }
    }
    #if DEBUG
    private var mealPreviewContent:some View {
        VStack(alignment:.leading,spacing:24){
            Text(diary.t("مثال للعرض فقط","Preview example only")).font(LTypography.caption).foregroundStyle(Theme.muted)
            mealGrid(MealDiarySummary.forDay(DayKey.today,entries:mealPreviewEntries),showEntries:false)
        }.allowsHitTesting(false)
    }
    private var overviewPreviewContent:some View {
        VStack(alignment:.leading,spacing:24){
            header
            weekSelector
            dailySummary(mealPreviewEntries.reduce(.zero){$0+$1.nutrition},diary.dailyGoals(day),showHistory:false)
            mealGrid(MealDiarySummary.forDay(DayKey.today,entries:mealPreviewEntries),showEntries:false)
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
        VStack(alignment:.leading,spacing:20){
            HStack(spacing:12){
                VStack(alignment:.leading,spacing:5){
                    Text(diary.t("يومك مع لُقمة","Your day with Luqma")).font(LTypography.font(size:22,weight:.heavy,relativeTo:.title2)).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
                    Text(diary.t("كل لقمة تقرّبك من هدفك","Every bite brings you closer")).font(LTypography.font(size:16,weight:.light,relativeTo:.subheadline)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength:0)
                Button{goals=true}label:{Image(systemName:"slider.horizontal.3").font(LTypography.font(size:19,weight:.medium)).frame(width:44,height:44).foregroundStyle(Theme.accent).background(Theme.card,in:RoundedRectangle(cornerRadius:15,style:.continuous))}.buttonStyle(.plain).accessibilityLabel(diary.t("أهداف السعرات والماكروز","Calorie and macro goals"))
            }
            Button{chosenMeal=nil;adding=true}label:{HStack(spacing:12){Image(systemName:"magnifyingglass").font(LTypography.font(size:19));Text(diary.t("ابحث عن طعام أو صوّر وجبتك","Search food or scan your meal")).font(LTypography.font(size:14,weight:.light,relativeTo:.subheadline));Spacer(minLength:0)}.foregroundStyle(Theme.muted).padding(.horizontal,18).frame(minHeight:54).background(Theme.card,in:RoundedRectangle(cornerRadius:15,style:.continuous))}.buttonStyle(.plain)
        }
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
        VStack(alignment:.leading,spacing:14){
            HStack(spacing:12){
                Text(diary.t("اليوم المختار","Selected day")).font(LTypography.font(size:16,weight:.heavy,relativeTo:.headline)).foregroundStyle(Theme.text)
                Spacer(minLength:0)
                Button{selectingDate=true}label:{HStack(spacing:7){Text(day.replacingOccurrences(of:"-",with:"/")).font(LTypography.font(size:12,weight:.light,relativeTo:.caption)).monospacedDigit();Image(systemName:"calendar").font(LTypography.font(size:15))}.foregroundStyle(Theme.muted).frame(minHeight:44)}.buttonStyle(.plain).accessibilityLabel(diary.t("اختيار التاريخ","Choose date"))
                    .accessibilityValue(localizedDate(date,"EEEE, d MMMM yyyy"))
            }
            HStack(spacing:6){ForEach(weekDates,id:\.self){value in
                let selected=DayKey.string(value)==day
                Button{date=value}label:{VStack(spacing:7){
                    Text(localizedDate(value,"EEEEE")).font(LTypography.font(size:11,weight:.light,relativeTo:.caption)).foregroundStyle(selected ? Theme.text:Theme.muted)
                    Text(localizedDate(value,"d")).font(LTypography.font(size:18,weight:.heavy,relativeTo:.headline)).monospacedDigit().foregroundStyle(Theme.text)
                }.frame(maxWidth:.infinity,minHeight:63).background(selected ? Theme.accent:Theme.card,in:RoundedRectangle(cornerRadius:15,style:.continuous))}.buttonStyle(.plain)
                    .accessibilityLabel(localizedDate(value,"EEEE, d MMMM"))
                    .accessibilityAddTraits(selected ? .isSelected:[])
            }}
        }
    }
    private var summary:some View {
        dailySummary(diary.total(day),diary.dailyGoals(day))
    }
    private func dailySummary(_ consumed:Nutrition,_ goals:Nutrition,showHistory:Bool=true)->some View {
        return VStack(alignment:.leading,spacing:14){
            calorieGoal(consumed:consumed.kcal,goal:goals.kcal)
            macroSummary(consumed,goals).padding(16).background(Theme.card,in:RoundedRectangle(cornerRadius:20,style:.continuous))
            if showHistory && intakeHistory.count>=2{
                DisclosureGroup(diary.t("السعرات خلال آخر 7 أيام","Calories over the last 7 days")){
                    intakeChart.padding(.top,12)
                }.font(LTypography.caption).foregroundStyle(Theme.muted).padding(16).background(Theme.card,in:RoundedRectangle(cornerRadius:20,style:.continuous))
            }
        }
    }
    @ViewBuilder private func macroSummary(_ consumed:Nutrition,_ goals:Nutrition)->some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing:16){macroProgress(.protein,consumed,goals);macroProgress(.carbs,consumed,goals);macroProgress(.fat,consumed,goals)}
        }else{
            HStack(spacing:12){macroProgress(.protein,consumed,goals);Divider().frame(height:42);macroProgress(.carbs,consumed,goals);Divider().frame(height:42);macroProgress(.fat,consumed,goals)}
        }
    }
    private func calorieGoal(consumed:Double,goal:Double)->some View {
        let remaining=goal-consumed,progress=goal>0 ? min(1,max(0,consumed/goal)):0
        let ring=ZStack{
                Circle().stroke(Theme.surface,lineWidth:10)
                Circle().trim(from:0,to:progress).stroke(Theme.accent,style:StrokeStyle(lineWidth:10,lineCap:.round)).rotationEffect(.degrees(-90))
                VStack(spacing:4){
                    Text(decimal(consumed,0)).font(LTypography.font(size:28,weight:.heavy,relativeTo:.title2)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
                    Text(diary.t("سعرة مسجلة","kcal logged")).font(LTypography.font(size:10,weight:.light,relativeTo:.caption2)).foregroundStyle(Theme.muted).lineLimit(1)
                }.padding(12)
            }.frame(width:119,height:119)
                .accessibilityElement(children:.ignore)
                .accessibilityLabel(diary.t("السعرات المسجلة","Logged calories"))
                .accessibilityValue(decimal(consumed,0)+" / "+decimal(goal,0)+" "+diary.t("سعرة","kcal"))
        let detail=VStack(alignment:.leading,spacing:10){
                HStack(spacing:8){
                    Text(diary.t("هدف السعرات","Calorie goal")).font(LTypography.font(size:16,weight:.heavy,relativeTo:.headline))
                    Spacer(minLength:0)
                    Button{goals=true}label:{Image(systemName:"slider.horizontal.3").font(.system(size:15)).foregroundStyle(Theme.muted).frame(width:44,height:44)}.buttonStyle(.plain).accessibilityLabel(diary.t("تعديل هدف السعرات","Edit calorie goal"))
                }
                HStack(alignment:.firstTextBaseline,spacing:5){Text(decimal(goal,0)).font(LTypography.font(size:26,weight:.heavy,relativeTo:.title2)).monospacedDigit();Text(diary.t("سعرة","kcal")).font(LTypography.caption).foregroundStyle(Theme.muted)}
                Text(decimal(abs(remaining),0)+" "+(remaining >= 0 ? diary.t("متبقية","left"):diary.t("فوق الهدف","above goal"))).font(LTypography.font(size:12,weight:.light,relativeTo:.caption)).foregroundStyle(Theme.muted)
                ProgressView(value:progress).tint(Theme.accent)
                    .accessibilityLabel(diary.t("التقدّم نحو هدف السعرات","Progress toward your calorie goal"))
            }
        return Group{
            if typeSize.isAccessibilitySize{
                VStack(alignment:.leading,spacing:20){ring.frame(maxWidth:.infinity);detail}
            }else{
                HStack(spacing:20){ring;detail}
            }
        }.foregroundStyle(Theme.text).padding(20).frame(maxWidth:.infinity,alignment:.leading).background(Theme.card,in:RoundedRectangle(cornerRadius:20,style:.continuous))
    }
    private func macroProgress(_ key:MacroKey,_ current:Nutrition,_ goal:Nutrition) -> some View {
        let color=key == .protein ? Theme.accent:key == .carbs ? Theme.secondaryAccent:Theme.text
        let symbol=key == .carbs ? "leaf.fill":key == .protein ? "fish.fill":"drop.fill"
        let progress=goal[key]>0 ? min(1,max(0,current[key]/goal[key])):0
        return VStack(alignment:.leading,spacing:6){
            HStack(spacing:5){Text(key.label(diary.language)).font(LTypography.font(size:11,weight:.light,relativeTo:.caption)).foregroundStyle(Theme.muted);Spacer(minLength:0);Image(systemName:symbol).font(LTypography.font(size:12)).foregroundStyle(color).accessibilityHidden(true)}
            HStack(alignment:.firstTextBaseline,spacing:3){
                Text(decimal(current[key],0)).font(LTypography.font(size:17,weight:.heavy,relativeTo:.headline)).foregroundStyle(Theme.text)
                Text("/ "+decimal(goal[key],0)+" "+diary.t("جم","g")).font(LTypography.font(size:10,weight:.light,relativeTo:.caption2)).foregroundStyle(Theme.muted)
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
    private var mealColumns:[GridItem] {
        Array(repeating:GridItem(.flexible(minimum:0),spacing:24,alignment:.top),count:typeSize.isAccessibilitySize ? 1:2)
    }
    private func mealGrid(_ summaries:[MealDiarySummary],showEntries:Bool=true)->some View {
        VStack(alignment:.leading,spacing:20){
            LuqmaSectionHeader(title:diary.t("وجباتي","My meals"),detail:diary.t("سجل اليوم","Daily diary"))
            LazyVGrid(columns:mealColumns,alignment:.center,spacing:24){
                ForEach(summaries){summary in mealSection(summary)}
            }
            if showEntries {
                ForEach(summaries.filter{!$0.entries.isEmpty}){summary in mealEntryDetails(summary)}
            }
        }
    }
    private func mealSection(_ summary:MealDiarySummary)->some View {
        let meal=summary.meal,total=summary.nutrition
        return VStack(alignment:.leading,spacing:8){
            HStack(spacing:8){
                Text(meal.label(diary.language)).font(LTypography.font(size:16,weight:.heavy,relativeTo:.headline)).foregroundStyle(Theme.text).lineLimit(2).fixedSize(horizontal:false,vertical:true)
                Spacer(minLength:0)
                Button{chosenMeal=meal;adding=true}label:{Image(systemName:"plus").font(.system(size:17,weight:.medium)).frame(width:44,height:44).foregroundStyle(Theme.accent)}.buttonStyle(.plain).accessibilityLabel(diary.t("إضافة إلى ","Add to ")+meal.label(diary.language))
            }
            HStack(spacing:6){VStack(alignment:.leading,spacing:4){
                Text(decimal(total.kcal,0)).font(LTypography.font(size:30,weight:.heavy,relativeTo:.title)).monospacedDigit().foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.75)
                Text(diary.t("سعرة مسجلة","kcal logged")).font(LTypography.font(size:12,weight:.light,relativeTo:.caption)).foregroundStyle(Theme.muted)
            };Spacer(minLength:0);Image(systemName:meal == .snack ? "carrot":meal.symbol).font(.system(size:20)).foregroundStyle(Theme.accent).accessibilityHidden(true)}
            Spacer(minLength:4)
            mealMacros(total)
            Text(summary.entries.isEmpty ? diary.t("جاهزة لأول لقمة","Ready for your first bite"):decimal(Double(summary.entries.count),0)+" "+diary.t("أطعمة مسجلة","foods logged"))
                .font(LTypography.font(size:11,weight:.light,relativeTo:.caption)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.75)
        }.padding(16).frame(maxWidth:.infinity,minHeight:225,alignment:.leading)
            .background(Theme.card,in:RoundedRectangle(cornerRadius:20,style:.continuous))
    }
    private func mealEntryDetails(_ summary:MealDiarySummary)->some View {
        DisclosureGroup(isExpanded:Binding(get:{expandedMeals.contains(summary.meal)},set:{if $0{expandedMeals.insert(summary.meal)}else{expandedMeals.remove(summary.meal)}})){
            VStack(spacing:0){
                ForEach(summary.entries){entry in
                    Button{editing=entry}label:{HStack(spacing:12){
                        VStack(alignment:.leading,spacing:5){Text(DisplayFormat.westernDigits(entry.name)).font(LTypography.subheadline).foregroundStyle(Theme.text);Text("\(decimal(entry.amount)) × \(entry.unitLabel(diary.language))").font(LTypography.caption).foregroundStyle(Theme.muted)}
                        Spacer(minLength:8)
                        Text(decimal(entry.kcal,0)).font(LTypography.font(size:15,weight:.heavy,relativeTo:.subheadline)).monospacedDigit().foregroundStyle(Theme.text)
                        Image(systemName:"chevron.forward").font(LTypography.caption2).foregroundStyle(Theme.muted)
                    }.padding(.vertical,12).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityHint(diary.t("تعديل الكمية","Edit quantity"))
                    if entry.id != summary.entries.last?.id{Divider()}
                }
            }.padding(.top,6)
        }label:{
            HStack(spacing:8){Text(diary.t("أطعمة ","Foods in ")+summary.meal.label(diary.language)).font(LTypography.font(size:14,weight:.heavy,relativeTo:.subheadline));Spacer(minLength:0);Text(decimal(Double(summary.entries.count),0)).font(LTypography.caption).monospacedDigit().foregroundStyle(Theme.muted)}
                .foregroundStyle(Theme.text).frame(minHeight:30)
        }.tint(Theme.accent).padding(18).background(Theme.card,in:RoundedRectangle(cornerRadius:20,style:.continuous))
    }
    private func mealMacros(_ total:Nutrition)->some View {
        VStack(spacing:5){
            mealMacro(.protein,value:total.protein,color:Theme.accent)
            mealMacro(.carbs,value:total.carbs,color:Theme.secondaryAccent)
            mealMacro(.fat,value:total.fat,color:Theme.text)
        }.padding(8).background(Theme.background.opacity(0.6),in:RoundedRectangle(cornerRadius:12,style:.continuous))
    }
    private func mealMacro(_ key:MacroKey,value:Double,color:Color)->some View {
        HStack(alignment:.firstTextBaseline,spacing:6){
            Text(key.label(diary.language)).font(LTypography.font(size:11,weight:.light,relativeTo:.caption)).foregroundStyle(Theme.muted)
            Spacer(minLength:0)
            Text(mealGrams(value)+" "+diary.t("جم","g")).font(LTypography.font(size:11,weight:.heavy,relativeTo:.caption)).monospacedDigit().foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth:.infinity,alignment:.leading).accessibilityElement(children:.combine)
    }
    private func mealGrams(_ value:Double)->String {
        let formatted=decimal(value)
        return formatted.hasSuffix(".0") ? String(formatted.dropLast(2)):formatted
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
            Section{Text(DisplayFormat.westernDigits(entry.name)).font(LTypography.headline);TextField(diary.t("الكمية","Amount"),text:$amount).keyboardType(.decimalPad);Text(entry.unitLabel(diary.language)).foregroundStyle(.secondary)}
            Section(diary.t("إجمالي هذه الكمية","Nutrition for this amount")){NutritionView(value:total)}
            Section{Button(diary.t("حفظ التعديل","Save changes")){if let value,diary.resize(entry.id,value){dismiss()}}.disabled(value == nil || (value ?? 0)<=0 || (value ?? 0)>10000);Button(diary.t("حذف الطعام","Delete food"),role:.destructive){deleting=true}}
        }.appBackground().navigationTitle(diary.t("تعديل الطعام","Edit food"))
            .toolbar{ToolbarItem(placement:.cancellationAction){Button(diary.t("إلغاء","Cancel")){dismiss()}}}
            .confirmationDialog(diary.t("حذف الطعام من اليوم؟","Delete this diary entry?"),isPresented:$deleting,titleVisibility:.visible){Button(diary.t("حذف","Delete"),role:.destructive){diary.remove(entry.id);dismiss()}}
        }.onAppear{amount=decimal(entry.amount,entry.amount.rounded()==entry.amount ? 0:2)}
    }
}
