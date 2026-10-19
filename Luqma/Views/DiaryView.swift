import SwiftUI
import Charts
import UIKit

struct DiaryView:View {
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var date=Date()
    @State private var adding=false
    @State private var goals=false
    @State private var selectingDate=false
    @State private var editing:DiaryEntry?
    @State private var chosenMeal:Meal?
    @State private var searchQuery=""
    @State private var category="meat"
    @State private var expandedMeals:Set<Meal>=[]
    @State private var expandedRoutine=false
    #if DEBUG
    @State private var routineCapturePosition:Meal? = {
        if CommandLine.arguments.contains("-loqma-preview-routine-dinner"){return .dinner}
        if CommandLine.arguments.contains("-loqma-preview-routine-snack"){return .snack}
        return nil
    }()
    #endif
    private var day:String {DayKey.string(date)}
    var body:some View {
        ScrollView{diaryContent.padding(.horizontal,16).padding(.bottom,24)}.appBackground()
            .navigationTitle(diary.t("اليوم","Today"))
            .toolbar(.hidden,for:.navigationBar)
            .safeAreaInset(edge:.top,spacing:0){
                // Keep the header outside ScrollView clipping, like Settings.
                #if DEBUG
                if !CommandLine.arguments.contains("-loqma-preview-meals"){header}
                #else
                header
                #endif
            }
            .fullScreenCover(isPresented:$adding){FoodAddView(initialQuery:searchQuery,initialMeal:chosenMeal,onPhotoCommit:{foods,meal in do{let entries=try foods.map{try DiaryEntry(food:$0.0,amount:$0.1,unit:$0.2,meal:meal,day:day,language:diary.language)};return diary.add(entries,foods:foods.map{$0.0})}catch{diary.report(error);return false}}){food,amount,unit,meal in do{let entry=try DiaryEntry(food:food,amount:amount,unit:unit,meal:meal,day:day,language:diary.language);return diary.add([entry],foods:[food])}catch{diary.report(error);return false}}}
            .sheet(item:$editing){EntryEditor(entry:$0)}
            .sheet(isPresented:$goals){GoalEditor()}
            .sheet(isPresented:$selectingDate){
                NavigationStack{
                    VStack(spacing:12){
                    weekSelector.padding(.horizontal,16)
                    DatePicker(diary.t("اختيار التاريخ","Choose date"),selection:$date,displayedComponents:.date)
                        .datePickerStyle(.graphical).tint(Theme.accent).padding(20).appBackground()
                    }
                        .sandowNavigation(diary.t("اختيار التاريخ","Choose date"),backLabel:diary.t("تم","Done"),onBack:{selectingDate=false})
            }.presentationDetents([.medium,.large])
            }
            #if DEBUG
            .allowsHitTesting(routinePreviewMeal == nil)
            #endif
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
        let meals=MealDiarySummary.forDay(day,entries:diary.state.entries)
        return VStack(alignment:.leading,spacing:20){
            foodCategories
            dailyRoutine(meals)
            summary
            fitnessSummary
            mealList(meals)
        }.padding(.top,16)
    }
    @ViewBuilder private var fitnessSummary:some View {
        if diary.state.fitnessProfile != nil || diary.state.fitnessDraft != nil || diary.state.fitnessOnboardingDismissed != true {
            VStack(alignment:.leading,spacing:12){
                HStack{
                    Text(diary.t("خطتك الشخصية","Your personal plan")).luqmaFont(.sectionTitle).accessibilityAddTraits(.isHeader)
                    Spacer()
                    if diary.state.fitnessProfile == nil && diary.state.fitnessDraft == nil{
                        Button(diary.t("لاحقًا","Later")){_ = diary.deferFitnessAssessment()}.luqmaFont(.helper).foregroundStyle(Theme.link).frame(minHeight:44).accessibilityIdentifier("diary.deferFitness")
                    }
                }
                if let plan=diary.state.appliedFitnessPlan,FitnessAssessmentState.hasAppliedGoals(diary.state){
                    Text(diary.t("\(plan.activity.trainingDays) أيام تدريب أسبوعيًا · \(plan.activity.stepsPerDay) خطوة مقترحة يوميًا","\(plan.activity.trainingDays) training days / week · \(plan.activity.stepsPerDay) suggested daily steps"))
                        .luqmaFont(.helper).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true)
                    if let target=diary.state.fitnessProfile?.answers.targetWeightKG{
                        Text(diary.t("وزن الهدف: \(decimal(target)) كجم","Target weight: \(decimal(target)) kg")).luqmaFont(.helper).foregroundStyle(Theme.muted)
                    }
                }else{
                    Text(diary.t("تقديرات للتغذية والنشاط بحسب إجاباتك، مع مراجعة قبل اعتماد الأهداف.","Nutrition and activity estimates from your answers, with a review before you apply any targets.")).luqmaFont(.helper).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true)
                }
                NavigationLink{FitnessProfileView()}label:{HStack{
                    Text(diary.t(diary.state.fitnessDraft != nil ? "متابعة التقييم":"عرض ملف اللياقة",diary.state.fitnessDraft != nil ? "Continue assessment":"Open fitness profile"))
                    Spacer();Image(systemName:"chevron.forward")
                }.luqmaFont(.button).foregroundStyle(Theme.link).frame(minHeight:44)}.accessibilityIdentifier("diary.fitnessProfile")
            }.luqmaCard()
        }
    }
    #if DEBUG
    private var mealPreviewContent:some View {
        VStack(alignment:.leading,spacing:20){
            Text(diary.t("مثال للعرض فقط","Preview example only")).luqmaFont(.caption).foregroundStyle(Theme.muted)
            mealList(MealDiarySummary.forDay(DayKey.today,entries:mealPreviewEntries),showEntries:false)
        }.allowsHitTesting(false)
    }
    private var overviewPreviewContent:some View {
        VStack(alignment:.leading,spacing:20){
            foodCategories
            dailyRoutine(MealDiarySummary.forDay(DayKey.today,entries:mealPreviewEntries))
            dailySummary(mealPreviewEntries.reduce(.zero){$0+$1.nutrition},diary.dailyGoals(day),showHistory:false)
            mealList(MealDiarySummary.forDay(DayKey.today,entries:mealPreviewEntries),showEntries:false)
        }.padding(.top,16).allowsHitTesting(false)
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
        VStack(alignment:.leading,spacing:12){
            HStack(spacing:10){
                Image("LuqmaMark").resizable().scaledToFit().frame(width:36,height:36)
                    .padding(4).background(Theme.background,in:RoundedRectangle(cornerRadius:12,style:.continuous)).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:5){
                    Button{selectingDate=true}label:{HStack(spacing:5){Text(localizedDate(date,"d MMMM yyyy")).luqmaFont(size:10,weight:.medium,relativeTo:.caption2);Image(systemName:"chevron.down").font(.system(size:8,weight:.semibold))}.foregroundStyle(Theme.text.opacity(0.8))}.buttonStyle(.plain).accessibilityLabel(diary.t("اختيار التاريخ","Choose date")).accessibilityValue(localizedDate(date,"EEEE, d MMMM yyyy"))
                    Text(diary.t("يومك مع لُقمة","Your day with Luqma")).luqmaFont(size:18,weight:.bold,relativeTo:.headline).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength:0)
                Button{goals=true}label:{Image(systemName:"gearshape").font(.system(size:17,weight:.medium)).frame(width:40,height:40).foregroundStyle(Theme.text).background(Theme.text.opacity(0.06),in:RoundedRectangle(cornerRadius:12,style:.continuous))}.buttonStyle(.plain).accessibilityLabel(diary.t("أهداف السعرات والماكروز","Calorie and macro goals")).accessibilityIdentifier("diary.goals")
            }
            Button{openSearch()}label:{HStack(spacing:10){Text(diary.t("ابحث في قاعدة الطعام…","Search our food database…")).luqmaFont(size:13,relativeTo:.subheadline);Spacer(minLength:0);Image(systemName:"magnifyingglass").font(.system(size:16))}.foregroundStyle(Theme.text.opacity(0.85)).padding(.horizontal,14).frame(minHeight:44).background(Theme.background,in:RoundedRectangle(cornerRadius:12,style:.continuous))}.buttonStyle(.plain)
        }.padding(16).background{Theme.surface.clipShape(UnevenRoundedRectangle(bottomLeadingRadius:24,bottomTrailingRadius:24,style:.continuous)).ignoresSafeArea(edges:.top)}
    }
    private func openSearch(_ query:String="",meal:Meal?=nil){searchQuery=query;chosenMeal=meal;adding=true}
    private var foodCategories:some View {
        VStack(alignment:.leading,spacing:10){
            HStack{Text(diary.t("بحث سريع","Quick search")).luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline);Spacer();Button{openSearch()}label:{Text(diary.t("عرض الكل","See all")).luqmaFont(size:11,weight:.medium,relativeTo:.caption).foregroundStyle(Theme.link)}.buttonStyle(.plain)}
            ScrollView(.horizontal,showsIndicators:false){HStack(spacing:6){
                categoryChip("vegetables",ar:"خيار",en:"Cucumber",symbol:"carrot",query:diary.t("خيار","cucumber"))
                categoryChip("meat",ar:"دجاج",en:"Chicken",symbol:"fork.knife",query:diary.t("دجاج","chicken"))
                categoryChip("fruit",ar:"تفاح",en:"Apple",symbol:"leaf",query:diary.t("تفاح","apple"))
                categoryChip("grains",ar:"أرز",en:"Rice",symbol:"takeoutbag.and.cup.and.straw",query:diary.t("أرز","rice"))
            }}
        }
    }
    private func categoryChip(_ id:String,ar:String,en:String,symbol:String,query:String)->some View {
        Button{category=id;openSearch(query)}label:{Label(diary.t(ar,en),systemImage:symbol).luqmaFont(size:11,weight:.semibold,relativeTo:.caption).foregroundStyle(Theme.text).padding(.horizontal,10).frame(minHeight:36).background(category == id ? Theme.secondaryAccent:Theme.card,in:RoundedRectangle(cornerRadius:9,style:.continuous))}.buttonStyle(.plain)
    }
    private func dailyRoutine(_ summaries:[MealDiarySummary])->some View {
        VStack(alignment:.leading,spacing:10){
            HStack{Text(diary.t("وجبات اليوم","Daily routine")).luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline);Spacer();Text(diary.t("اختر وجبتك","Choose a meal")).luqmaFont(size:11,relativeTo:.caption).foregroundStyle(Theme.accent)}
            if typeSize.isAccessibilitySize{
                DisclosureGroup(diary.t("عرض الوجبات الأربع","Show the four meals"),isExpanded:$expandedRoutine){
                    VStack(spacing:10){ForEach(summaries){routineCard($0)}}.padding(.top,10)
                }.luqmaFont(.subheadline).tint(Theme.accent)
            }else{
                #if DEBUG
                if routinePreviewMeal != nil{
                    ScrollView(.horizontal,showsIndicators:false){
                        LazyHStack(spacing:12){
                            ForEach(summaries){summary in
                                routineCard(summary)
                                    .containerRelativeFrame(.horizontal){width,_ in width*0.72}
                                    .id(summary.meal)
                            }
                        }.scrollTargetLayout()
                    }.scrollTargetBehavior(.viewAligned)
                        .scrollPosition(id:$routineCapturePosition,anchor:.leading)
                        .transaction{$0.animation=nil;$0.disablesAnimations=true}
                }else{
                    ScrollView(.horizontal,showsIndicators:false){
                        HStack(spacing:12){
                            ForEach(summaries){summary in
                                routineCard(summary)
                                    .containerRelativeFrame(.horizontal){width,_ in width*0.72}
                            }
                        }.scrollTargetLayout()
                    }.scrollTargetBehavior(.viewAligned)
                }
                #else
                ScrollView(.horizontal,showsIndicators:false){
                    HStack(spacing:12){
                        ForEach(summaries){summary in
                            routineCard(summary)
                                .containerRelativeFrame(.horizontal){width,_ in width*0.72}
                        }
                    }.scrollTargetLayout()
                }.scrollTargetBehavior(.viewAligned)
                #endif
            }
        }
        #if DEBUG
        .onAppear{if CommandLine.arguments.contains("-loqma-preview-editorial-expanded"){expandedRoutine=true}}
        .allowsHitTesting(!CommandLine.arguments.contains("-loqma-preview-editorial-expanded"))
        #endif
    }
    private func routineCard(_ summary:MealDiarySummary)->some View {
        Button{openSearch(meal:summary.meal)}label:{
            VStack(alignment:.leading,spacing:9){
                    HStack{
                        Image(systemName:"fork.knife").font(.system(size:13,weight:.semibold))
                            .foregroundStyle(Theme.onAccent).frame(width:30,height:30)
                            .background(Theme.accent,in:RoundedRectangle(cornerRadius:9))
                        Spacer(minLength:0)
                        Image(systemName:"plus").font(.system(size:12,weight:.semibold))
                            .frame(width:28,height:28).background(Theme.background.opacity(0.55),in:Circle())
                    }
                    Spacer(minLength:12)
                    Text(summary.meal.label(diary.language))
                        .luqmaFont(size:17,weight:.bold,relativeTo:.headline)
                    if summary.entries.isEmpty{
                        Text(diary.t("صورة توضيحية","Illustrative photo"))
                            .luqmaFont(size:10,weight:.medium,relativeTo:.caption2)
                            .foregroundStyle(Theme.text.opacity(0.8))
                        Label(diary.t("سجّل وجبتك","Log your meal"),systemImage:"plus")
                            .luqmaFont(size:11,weight:.medium,relativeTo:.caption)
                            .foregroundStyle(Theme.text.opacity(0.8))
                    }else{
                        if let first=summary.entries.first{
                            Text(DisplayFormat.westernDigits(first.name))
                                .luqmaFont(size:11,relativeTo:.caption).lineLimit(1)
                                .foregroundStyle(Theme.text.opacity(0.8))
                        }
                        Label(decimal(summary.nutrition.kcal,0)+" "+diary.t("سعرة","kcal"),systemImage:"flame.fill")
                            .luqmaFont(size:11,weight:.medium,relativeTo:.caption)
                            .foregroundStyle(Theme.text.opacity(0.8))
                    }
            }.padding(14).frame(maxWidth:.infinity,minHeight:164,alignment:.leading)
                .frame(height:typeSize.isAccessibilitySize ? nil:164)
                .foregroundStyle(Theme.text)
                .background{
                    if summary.entries.isEmpty{
                        ZStack{
                            EditorialFill(artwork:routineArtwork(summary.meal))
                            LinearGradient(colors:[.black.opacity(0.12),.black.opacity(0.45),.black.opacity(0.92)],startPoint:.top,endPoint:.bottom)
                        }
                    }else{Theme.card}
                }.clipShape(RoundedRectangle(cornerRadius:18,style:.continuous))
        }.buttonStyle(.plain).accessibilityLabel(diary.t("إضافة إلى ","Add to ")+summary.meal.label(diary.language))
            .accessibilityValue(summary.entries.isEmpty ? diary.t("صورة توضيحية. سجّل وجبتك.","Illustrative photo. Log your meal."):decimal(summary.nutrition.kcal,0)+" "+diary.t("سعرة","kcal"))
    }
    private func routineArtwork(_ meal:Meal)->EditorialArtwork {
        switch meal{
        case .breakfast:return .breakfast
        case .lunch:return .lunch
        case .dinner:return .dinner
        case .snack:return .snack
        }
    }
    #if DEBUG
    private var routinePreviewMeal:Meal? {
        if CommandLine.arguments.contains("-loqma-preview-routine-dinner"){return .dinner}
        if CommandLine.arguments.contains("-loqma-preview-routine-snack"){return .snack}
        return nil
    }
    #endif
    private var weekDates:[Date] {
        let calendar=DisplayFormat.calendar(diary.language)
        let start=calendar.dateInterval(of:.weekOfYear,for:date)?.start ?? calendar.startOfDay(for:date)
        return (0..<7).compactMap{calendar.date(byAdding:.day,value:$0,to:start)}
    }
    private func localizedDate(_ value:Date,_ template:String)->String {
        DisplayFormat.date(value,template:template,language:diary.language)
    }
    private var weekSelector:some View {
        VStack(alignment:.leading,spacing:8){
            HStack(spacing:12){
                Text(diary.t("اليوم المختار","Selected day")).luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline).foregroundStyle(Theme.text)
                Spacer(minLength:0)
                Button{selectingDate=true}label:{HStack(spacing:7){Text(day.replacingOccurrences(of:"-",with:"/")).luqmaFont(size:12,weight:.light,relativeTo:.caption).monospacedDigit();Image(systemName:"calendar").luqmaFont(size:15)}.foregroundStyle(Theme.muted).frame(minHeight:44)}.buttonStyle(.plain).accessibilityLabel(diary.t("اختيار التاريخ","Choose date"))
                    .accessibilityValue(localizedDate(date,"EEEE, d MMMM yyyy"))
            }
            if typeSize.isAccessibilitySize{
                LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:4),spacing:8){
                    ForEach(weekDates,id:\.self){dayPill($0)}
                }
            }else{
                HStack(spacing:6){ForEach(weekDates,id:\.self){dayPill($0)}}
            }
        }.padding(12).background(Theme.card,in:RoundedRectangle(cornerRadius:20,style:.continuous))
    }
    private func dayPill(_ value:Date)->some View {
        let selected=DayKey.string(value)==day
        return Button{date=value}label:{VStack(spacing:7){
            Text(localizedDate(value,"EEEEE")).luqmaFont(size:11,relativeTo:.caption).foregroundStyle(selected ? Theme.background:Theme.muted)
            Text(localizedDate(value,"d")).luqmaFont(size:15,weight:.semibold,relativeTo:.subheadline).monospacedDigit().foregroundStyle(selected ? Theme.background:Theme.text)
        }.frame(maxWidth:.infinity,minHeight:48).background(selected ? Theme.accent:Theme.surface,in:RoundedRectangle(cornerRadius:12,style:.continuous))}.buttonStyle(.plain)
            .accessibilityLabel(localizedDate(value,"EEEE, d MMMM"))
            .accessibilityAddTraits(selected ? .isSelected:[])
    }
    private var summary:some View {
        dailySummary(diary.total(day),diary.dailyGoals(day))
    }
    private func dailySummary(_ consumed:Nutrition,_ goals:Nutrition,showHistory:Bool=true)->some View {
        let history=showHistory ? intakeHistory:[]
        return VStack(alignment:.leading,spacing:12){
            VStack(alignment:.leading,spacing:10){
                Text(diary.t("هدف السعرات","Calorie goal")).luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline).foregroundStyle(Theme.text)
                calorieGoal(consumed:consumed.kcal,goal:goals.kcal)
            }
            macroSummary(consumed,goals).padding(16).background(Theme.card,in:RoundedRectangle(cornerRadius:20,style:.continuous))
            if history.count>=2{
                DisclosureGroup(diary.t("السعرات خلال آخر 7 أيام","Calories over the last 7 days")){
                    intakeChart(history).padding(.top,12)
                }.luqmaFont(.caption).foregroundStyle(Theme.muted).padding(16).background(Theme.card,in:RoundedRectangle(cornerRadius:20,style:.continuous))
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
        return VStack(alignment:.leading,spacing:12){
            HStack(alignment:.center,spacing:12){
                VStack(alignment:.leading,spacing:4){
                    HStack(alignment:.firstTextBaseline,spacing:6){
                        Text(decimal(goal,0)).luqmaFont(size:34,weight:.bold,relativeTo:.largeTitle).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                        Text(diary.t("سعرة","kcal")).luqmaFont(size:13,relativeTo:.caption)
                    }
                }
                Spacer(minLength:0)
                Button{goals=true}label:{Image(systemName:"gearshape").font(.system(size:18,weight:.medium)).frame(width:40,height:40).overlay(RoundedRectangle(cornerRadius:12).strokeBorder(Theme.onAccent,lineWidth:1))}.buttonStyle(.plain).accessibilityLabel(diary.t("تعديل هدف السعرات","Edit calorie goal"))
            }
            if typeSize.isAccessibilitySize{
                VStack(alignment:.leading,spacing:8){
                    consumedCalories(consumed,goal)
                    Text(decimal(abs(remaining),0)+" "+(remaining >= 0 ? diary.t("متبقية","left"):diary.t("فوق الهدف","above goal"))).luqmaFont(.footnote)
                }
            }else{
                HStack(alignment:.firstTextBaseline,spacing:8){
                    consumedCalories(consumed,goal)
                    Spacer(minLength:0)
                    Text(decimal(abs(remaining),0)+" "+(remaining >= 0 ? diary.t("متبقية","left"):diary.t("فوق الهدف","above goal"))).luqmaFont(size:12,relativeTo:.caption).lineLimit(1).minimumScaleFactor(0.8)
                }
            }
            GeometryReader{geometry in
                ZStack(alignment:.leading){Capsule().fill(Theme.onAccent.opacity(0.18));Capsule().fill(Theme.onAccent).frame(width:geometry.size.width*progress)}
            }.frame(height:8).accessibilityElement(children:.ignore)
                .accessibilityLabel(diary.t("التقدّم نحو هدف السعرات","Progress toward your calorie goal")).accessibilityValue(decimal(progress*100,0)+"%")
        }.foregroundStyle(Theme.onAccent).padding(16).frame(maxWidth:.infinity,alignment:.leading).background(Theme.accent,in:RoundedRectangle(cornerRadius:20,style:.continuous))
            .accessibilityIdentifier("diary.calorieGoal").accessibilityValue(decimal(goal,0))
    }
    private func consumedCalories(_ consumed:Double,_ goal:Double)->some View {
        HStack(alignment:.firstTextBaseline,spacing:5){
            Text(decimal(consumed,0)+" / "+decimal(goal,0)).luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline).monospacedDigit().environment(\.layoutDirection,.leftToRight)
            Text(diary.t("مستهلكة","consumed")).luqmaFont(size:12,relativeTo:.caption)
        }.accessibilityElement(children:.combine)
    }
    private func macroProgress(_ key:MacroKey,_ current:Nutrition,_ goal:Nutrition) -> some View {
        let color=key == .protein ? Theme.secondaryAccent:key == .carbs ? Theme.accent:Theme.text
        let symbolColor=key == .protein ? Theme.secondaryAccentText:key == .carbs ? Theme.accentText:Theme.text
        let symbol=key == .carbs ? "leaf.fill":key == .protein ? "fish.fill":"drop.fill"
        let progress=goal[key]>0 ? min(1,max(0,current[key]/goal[key])):0
        return VStack(alignment:.leading,spacing:6){
            HStack(spacing:5){Text(key.label(diary.language)).luqmaFont(size:11,relativeTo:.caption).foregroundStyle(Theme.muted);Spacer(minLength:0);Image(systemName:symbol).luqmaFont(size:12).foregroundStyle(symbolColor).accessibilityHidden(true)}
            HStack(alignment:.firstTextBaseline,spacing:3){
                Text(decimal(current[key],0)).luqmaFont(size:17,weight:.heavy,relativeTo:.headline).foregroundStyle(Theme.text)
                Text("/ "+decimal(goal[key],0)+" "+diary.t("جم","g")).luqmaFont(size:10,relativeTo:.caption2).foregroundStyle(Theme.muted)
            }.monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).environment(\.layoutDirection,.leftToRight)
            ProgressView(value:progress).tint(color)
                .accessibilityLabel(key.label(diary.language)+" "+diary.t("التقدّم اليومي","daily progress"))
        }.frame(maxWidth:.infinity,alignment:.leading).accessibilityElement(children:.combine)
    }
    private struct IntakePoint:Identifiable{var day:String;var date:Date;var kcal:Double;var id:String{day}}
    private var intakeHistory:[IntakePoint]{
        let calendar=DisplayFormat.calendar(diary.language),end=calendar.startOfDay(for:min(date,Date()))
        let dates=(0..<7).compactMap{offset -> (String,Date)? in
            guard let value=calendar.date(byAdding:.day,value:offset-6,to:end) else{return nil}
            return (DayKey.string(value),value)
        }
        let days=Set(dates.map{$0.0})
        var calories:[String:Double]=[:]
        // One pass over the diary, retaining each day's original addition order.
        for entry in diary.state.entries where days.contains(entry.day){calories[entry.day,default:0]+=entry.kcal}
        return dates.compactMap{key,value in calories[key].map{IntakePoint(day:key,date:value,kcal:$0)}}
    }
    @ViewBuilder private func intakeChart(_ points:[IntakePoint])->some View {
        if points.count>=2{
            Chart(points){point in
                AreaMark(x:.value("Day",point.date),y:.value("Logged calories",point.kcal)).foregroundStyle(LinearGradient(colors:[Theme.accent.opacity(0.35),Theme.accent.opacity(0.025)],startPoint:.top,endPoint:.bottom))
                LineMark(x:.value("Day",point.date),y:.value("Logged calories",point.kcal)).lineStyle(StrokeStyle(lineWidth:2.5)).foregroundStyle(Theme.accent)
                PointMark(x:.value("Day",point.date),y:.value("Logged calories",point.kcal)).symbolSize(20).foregroundStyle(Theme.accent)
            }.chartLegend(.hidden).chartYAxis{AxisMarks(values:.automatic(desiredCount:3)){axis in
                AxisGridLine().foregroundStyle(Theme.stroke)
                AxisValueLabel{if let value=axis.as(Double.self){Text(decimal(value,0)).luqmaFont(.caption2)}}.foregroundStyle(Theme.muted)
            }}.chartXAxis{AxisMarks(values:.automatic(desiredCount:4)){axis in
                AxisValueLabel{if let value=axis.as(Date.self){Text(localizedDate(value,"d MMM")).luqmaFont(.caption2)}}.foregroundStyle(Theme.muted)
            }}.frame(height:135).accessibilityLabel(diary.t("السعرات المسجلة خلال آخر سبعة أيام","Calories logged over the last seven days"))
        }
    }
    private func mealList(_ summaries:[MealDiarySummary],showEntries:Bool=true)->some View {
        VStack(alignment:.leading,spacing:12){
            LuqmaSectionHeader(title:diary.t("وجباتي","My meals"),detail:diary.t("سجل اليوم","Daily diary"))
            ForEach(summaries){summary in mealSection(summary,showEntries:showEntries)}
        }
    }
    private func mealSection(_ summary:MealDiarySummary,showEntries:Bool)->some View {
        let meal=summary.meal,total=summary.nutrition
        return VStack(alignment:.leading,spacing:12){
            HStack(spacing:12){
                Image(systemName:meal == .snack ? "carrot":meal.symbol).font(.system(size:20,weight:.medium)).foregroundStyle(Theme.accent).frame(width:40,height:40).background(Theme.surface,in:RoundedRectangle(cornerRadius:12,style:.continuous)).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:4){
                    Text(meal.label(diary.language)).luqmaFont(size:16,weight:.semibold,relativeTo:.headline).foregroundStyle(Theme.text).fixedSize(horizontal:false,vertical:true)
                    Text(mealCount(summary.entries.count)).luqmaFont(size:11,relativeTo:.caption).foregroundStyle(Theme.muted).accessibilityIdentifier("diary.mealCount."+summary.meal.rawValue)
                }
                Spacer(minLength:0)
                VStack(alignment:.trailing,spacing:3){
                    Text(decimal(total.kcal,0)).luqmaFont(size:22,weight:.bold,relativeTo:.title3).monospacedDigit().foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.7)
                    Text(diary.t("سعرة","kcal")).luqmaFont(size:11,relativeTo:.caption).foregroundStyle(Theme.muted)
                }
                Button{openSearch(meal:meal)}label:{Image(systemName:"plus").font(.system(size:17,weight:.medium)).frame(width:44,height:44).foregroundStyle(Theme.accent).background(Theme.accent.opacity(0.1),in:Circle())}.buttonStyle(.plain).accessibilityLabel(diary.t("إضافة إلى ","Add to ")+meal.label(diary.language))
            }
            mealMacros(total)
            if showEntries && !summary.entries.isEmpty{
                Divider().overlay(Theme.stroke)
                mealEntryDetails(summary)
            }
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
            .background(Theme.card,in:RoundedRectangle(cornerRadius:20,style:.continuous))
    }
    private func mealCount(_ count:Int)->String {
        if count==0{return diary.t("أضف أول طعام","Add your first food")}
        if count==1{return "1 "+diary.t("طعام مسجل","food logged")}
        return decimal(Double(count),0)+" "+diary.t("أطعمة مسجلة","foods logged")
    }
    private func mealEntryDetails(_ summary:MealDiarySummary)->some View {
        DisclosureGroup(isExpanded:Binding(get:{expandedMeals.contains(summary.meal)},set:{if $0{expandedMeals.insert(summary.meal)}else{expandedMeals.remove(summary.meal)}})){
            VStack(spacing:0){
                ForEach(summary.entries){entry in
                    Button{editing=entry}label:{HStack(spacing:12){
                        VStack(alignment:.leading,spacing:5){Text(DisplayFormat.westernDigits(entry.name)).luqmaFont(.subheadline).foregroundStyle(Theme.text);Text("\(decimal(entry.amount)) × \(entry.unitLabel(diary.language))").luqmaFont(.caption).foregroundStyle(Theme.muted)}
                        Spacer(minLength:8)
                        Text(decimal(entry.kcal,0)).luqmaFont(size:15,weight:.heavy,relativeTo:.subheadline).monospacedDigit().foregroundStyle(Theme.text)
                        Image(systemName:"chevron.forward").luqmaFont(.caption2).foregroundStyle(Theme.muted)
                    }.padding(.vertical,12).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityHint(diary.t("تعديل الكمية","Edit quantity"))
                        .accessibilityIdentifier("diary.entry."+entry.id.uuidString).accessibilityLabel(DisplayFormat.westernDigits(entry.name))
                    if entry.id != summary.entries.last?.id{Divider()}
                }
            }.padding(.top,6)
        }label:{
            HStack(spacing:8){Text(diary.t("تفاصيل الأطعمة","Food details")).luqmaFont(size:13,weight:.medium,relativeTo:.subheadline);Spacer(minLength:0);Text(decimal(Double(summary.entries.count),0)).luqmaFont(.caption).monospacedDigit().foregroundStyle(Theme.muted)}
                .foregroundStyle(Theme.text).frame(minHeight:30)
        }.tint(Theme.accent).accessibilityIdentifier("diary.details."+summary.meal.rawValue)
    }
    private func mealMacros(_ total:Nutrition)->some View {
        Group{
            if typeSize.isAccessibilitySize{
                VStack(alignment:.leading,spacing:12){mealMacro(.protein,value:total.protein,color:Theme.secondaryAccent);mealMacro(.carbs,value:total.carbs,color:Theme.accent);mealMacro(.fat,value:total.fat,color:Theme.text)}
            }else{
                HStack(spacing:12){mealMacro(.protein,value:total.protein,color:Theme.secondaryAccent);Divider().frame(height:26);mealMacro(.carbs,value:total.carbs,color:Theme.accent);Divider().frame(height:26);mealMacro(.fat,value:total.fat,color:Theme.text)}
            }
        }.padding(10).background(Theme.surface,in:RoundedRectangle(cornerRadius:12,style:.continuous))
    }
    private func mealMacro(_ key:MacroKey,value:Double,color:Color)->some View {
        VStack(alignment:.leading,spacing:4){
            HStack(spacing:5){Circle().fill(color).frame(width:5,height:5).accessibilityHidden(true);Text(key.label(diary.language)).luqmaFont(size:11,relativeTo:.caption).foregroundStyle(Theme.text.opacity(0.85))}
            Text(mealGrams(value)+" "+diary.t("جم","g")).luqmaFont(size:13,weight:.semibold,relativeTo:.subheadline).monospacedDigit().foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.8)
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
            Section{Text(DisplayFormat.westernDigits(entry.name)).luqmaFont(.headline);TextField(diary.t("الكمية","Amount"),text:$amount).keyboardType(.decimalPad).accessibilityIdentifier("entry.amount");Text(entry.unitLabel(diary.language)).foregroundStyle(Theme.muted)}.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            Section(diary.t("إجمالي هذه الكمية","Nutrition for this amount")){NutritionView(value:total)}.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            Section{Button(diary.t("حذف الطعام","Delete food"),role:.destructive){deleting=true}.accessibilityIdentifier("entry.delete")}.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
        }.sandowForm().sandowNavigation(diary.t("تعديل الطعام","Edit food"),backLabel:diary.t("إلغاء","Cancel"),onBack:{dismiss()},
            actionLabel:diary.t("حفظ التعديل","Save changes"),actionEnabled:!(value == nil || (value ?? 0)<=0 || (value ?? 0)>10000),actionIdentifier:"entry.save",
            onAction:{if let value,diary.resize(entry.id,value){dismiss()}})
            .confirmationDialog(diary.t("حذف الطعام من اليوم؟","Delete this diary entry?"),isPresented:$deleting,titleVisibility:.visible){Button(diary.t("حذف","Delete"),role:.destructive){diary.remove(entry.id);dismiss()}}
        }.onAppear{amount=decimal(entry.amount,entry.amount.rounded()==entry.amount ? 0:2)}
    }
}
