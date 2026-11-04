import SwiftUI
import Charts
import UIKit

struct DiaryView:View {
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var date=Date()
    @State private var goals=false
    @State private var selectingDate=false
    @State private var showingCalorieIntake=false
    @State private var showingNotifications=false
    @State private var editing:DiaryEntry?
    private struct FoodSearchPresentation: Identifiable {
        let id = UUID()
        let query: String
        let meal: Meal?
        let focus: Bool
    }
    @State private var foodSearch: FoodSearchPresentation?
    @State private var expandedMeals:Set<Meal>=[]
    private var day:String {DayKey.string(date)}
    var body:some View {diaryScroll}
    private var diaryScroll:some View {
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
            .fullScreenCover(item:$foodSearch) { request in
                FoodAddView(initialQuery:request.query,initialMeal:request.meal,onPhotoCommit:{ foods,meal in
                    do {
                        let entries = try foods.map {
                            try DiaryEntry(food:$0.0,amount:$0.1,unit:$0.2,meal:meal,day:day,language:diary.language)
                        }
                        guard diary.add(entries,foods:foods.map { $0.0 }) else { return false }
                        showMealSaved()
                        return true
                    } catch {
                        diary.report(error)
                        return false
                    }
                },autoFocusSearch:request.focus) { food,amount,unit,meal in
                    do {
                        let entry = try DiaryEntry(food:food,amount:amount,unit:unit,meal:meal,day:day,language:diary.language)
                        guard diary.add([entry],foods:[food]) else { return false }
                        showMealSaved()
                        return true
                    } catch {
                        diary.report(error)
                        return false
                    }
                }
            }
            .sheet(item:$editing){EntryEditor(entry:$0)}
            .sheet(isPresented:$goals){GoalEditor()}
            .sheet(isPresented:$showingCalorieIntake){
                CalorieIntakeDetailView(selectedDate:$date)
            }
            .sheet(isPresented:$showingNotifications){NavigationStack{NotificationsView()}}
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
            summary
            mealList(meals)
        }.padding(.top,16)
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
            HStack(alignment:.top,spacing:12){
                Image("LuqmaMark").resizable().scaledToFit().frame(width:38,height:38)
                    .padding(4).background(Theme.background,in:RoundedRectangle(cornerRadius:12)).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:2){
                    Button{selectingDate=true}label:{
                        HStack(spacing:4){Text(localizedDate(date,"d MMMM yyyy")).luqmaFont(size:11,weight:.medium,relativeTo:.caption2);Image(systemName:"chevron.down").font(.system(size:8,weight:.semibold))}
                            .foregroundStyle(Theme.text.opacity(0.82))
                    }.buttonStyle(LuqmaPressStyle()).accessibilityLabel(diary.t("اختيار التاريخ","Choose date"))
                        .accessibilityValue(localizedDate(date,"EEEE, d MMMM yyyy"))
                    Text(diary.t("يومك مع لُقمة","Your day with Luqma"))
                        .luqmaFont(size:19,weight:.bold,relativeTo:.headline).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
                }
                Spacer(minLength:0)
                HStack(spacing:8){
                    Button{showingNotifications=true}label:{
                        Image(systemName:"bell").font(.system(size:15,weight:.medium)).frame(width:38,height:38)
                            .foregroundStyle(Theme.text).background(Theme.text.opacity(0.08),in:RoundedRectangle(cornerRadius:12))
                    }.buttonStyle(LuqmaPressStyle()).accessibilityLabel(diary.t("الإشعارات","Notifications"))
                    Button{goals=true}label:{
                        Image(systemName:"gearshape").font(.system(size:16,weight:.medium)).frame(width:38,height:38)
                            .foregroundStyle(Theme.text).background(Theme.text.opacity(0.08),in:RoundedRectangle(cornerRadius:12))
                    }.buttonStyle(LuqmaPressStyle()).accessibilityLabel(diary.t("أهداف السعرات والماكروز","Calorie and macro goals")).accessibilityIdentifier("diary.goals")
                }
            }
            HStack{Spacer(minLength:0);compactPersonalizedPlanBadge}
            Button{openSearch(focus:true)}label:{
                Image(systemName:"magnifyingglass").font(.system(size:16))
                    .foregroundStyle(Theme.text.opacity(0.85)).frame(width:44,height:44)
                    .background(Theme.background,in:Circle())
                    .overlay{Circle().strokeBorder(Theme.stroke,lineWidth:1)}
            }.buttonStyle(LuqmaPressStyle(scale:0.96))
                .accessibilityLabel(diary.t("بحث عن طعام","Search for food")).accessibilityIdentifier("diary.search")
        }.padding(16).background{Theme.surface.clipShape(UnevenRoundedRectangle(bottomLeadingRadius:24,bottomTrailingRadius:24,style:.continuous)).ignoresSafeArea(edges:.top)}
    }
    private var compactPersonalizedPlanBadge:some View {
        NavigationLink{FitnessProfileView()}label:{
            HStack(spacing:6){
                Image(systemName:diary.state.fitnessProfile == nil ? "sparkles":"checkmark.seal.fill").font(.system(size:11,weight:.bold)).foregroundStyle(Theme.accent)
                Text(diary.t(diary.state.fitnessProfile == nil ? "خطتك الشخصية · التقييم":"خطتك الشخصية",diary.state.fitnessProfile == nil ? "Personal plan · Assessment":"Personal plan")).luqmaFont(size:11,weight:.bold,relativeTo:.caption2).foregroundStyle(Theme.text).lineLimit(1)
                Image(systemName:"chevron.forward").font(.system(size:9,weight:.bold)).foregroundStyle(Theme.accent)
            }.padding(.horizontal,10).padding(.vertical,6).background(Theme.background.opacity(0.88),in:Capsule())
                .overlay{Capsule().strokeBorder(Theme.accent.opacity(0.55),lineWidth:1)}
        }.buttonStyle(LuqmaPressStyle()).accessibilityIdentifier("diary.fitnessProfile")
            .accessibilityLabel(diary.t("خطتك الشخصية — ملف اللياقة","Personal plan — Fitness profile"))
    }
    private func openSearch(_ query: String = "", meal: Meal? = nil, focus: Bool = false) {
        guard foodSearch == nil else { return }
        foodSearch = FoodSearchPresentation(query:query,meal:meal,focus:focus)
    }
    private func showMealSaved(){LuqmaFeedbackCenter.shared.saved(diary.t("تمت إضافة الوجبة","Meal added"))}
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
                Button{selectingDate=true}label:{HStack(spacing:7){Text(day.replacingOccurrences(of:"-",with:"/")).luqmaFont(size:12,weight:.light,relativeTo:.caption).monospacedDigit();Image(systemName:"calendar").luqmaFont(size:15)}.foregroundStyle(Theme.muted).frame(minHeight:44)}.buttonStyle(LuqmaPressStyle()).accessibilityLabel(diary.t("اختيار التاريخ","Choose date"))
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
            .luqmaFeedback(.selection,trigger:day)
    }
    private func dayPill(_ value:Date)->some View {
        let selected=DayKey.string(value)==day
        return Button{date=value}label:{VStack(spacing:7){
            Text(localizedDate(value,"EEEEE")).luqmaFont(size:11,relativeTo:.caption).foregroundStyle(selected ? Theme.background:Theme.muted)
            Text(localizedDate(value,"d")).luqmaFont(size:15,weight:.semibold,relativeTo:.subheadline).monospacedDigit().foregroundStyle(selected ? Theme.background:Theme.text)
        }.frame(maxWidth:.infinity,minHeight:48).background(selected ? Theme.accent:Theme.surface,in:RoundedRectangle(cornerRadius:12,style:.continuous))
            .luqmaMotion(.selection,value:selected)}.buttonStyle(LuqmaPressStyle(feedback:nil))
            .accessibilityLabel(localizedDate(value,"EEEE, d MMMM"))
            .accessibilityAddTraits(selected ? .isSelected:[])
    }
    private var summary:some View {
        dailySummary(diary.total(day),diary.dailyGoals(day))
    }
    private func dailySummary(_ consumed:Nutrition,_ goals:Nutrition,showHistory:Bool=true)->some View {
        DailyCalorieCard(consumed:consumed,goals:goals,language:diary.language,
                         isLoading:diary.waitingForUnlock,showHistory:showHistory,
                         onHistory:{showingCalorieIntake=true},onEditGoal:{self.goals=true})
    }
    private func mealList(_ summaries:[MealDiarySummary],showEntries:Bool=true)->some View {
        VStack(alignment:.leading,spacing:12){
            LuqmaSectionHeader(title:diary.t("وجبات اليوم","Today's meals"),detail:diary.t("سجل اليوم","Daily diary"))
            ForEach(summaries){summary in mealSection(summary,showEntries:showEntries)}
        }
    }
    private func mealSection(_ summary:MealDiarySummary,showEntries:Bool)->some View {
        VStack(alignment:.leading,spacing:10){
            DailyMealCard(summary:summary,language:diary.language,onAdd:{openSearch(meal:summary.meal)})
            if showEntries && !summary.entries.isEmpty{
                mealEntryDetails(summary).padding(.horizontal,14).padding(.bottom,12)
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
            .background(Theme.card,in:RoundedRectangle(cornerRadius:18,style:.continuous))
    }
    private func mealEntryDetails(_ summary:MealDiarySummary)->some View {
        DisclosureGroup(isExpanded:Binding(get:{expandedMeals.contains(summary.meal)},set:{
            guard $0 != expandedMeals.contains(summary.meal) else{return}
            LuqmaHapticManager.play(.light)
            if $0{expandedMeals.insert(summary.meal)}else{expandedMeals.remove(summary.meal)}
        })){
            // CI95's expanded meal exposes 200 eagerly created row buttons.
            // Keep stable entry identities and identical row layout, but build
            // offscreen rows on demand in the containing diary ScrollView.
            LazyVStack(spacing:0){
                ForEach(summary.entries){entry in
                    Button{editing=entry}label:{HStack(spacing:12){
                        VStack(alignment:.leading,spacing:5){Text(DisplayFormat.westernDigits(entry.name)).luqmaFont(.subheadline).foregroundStyle(Theme.text);Text("\(decimal(entry.amount)) × \(entry.unitLabel(diary.language))").luqmaFont(.caption).foregroundStyle(Theme.muted)}
                        Spacer(minLength:8)
                        Text(decimal(entry.kcal,0)).luqmaFont(size:15,weight:.heavy,relativeTo:.subheadline).monospacedDigit().foregroundStyle(Theme.text)
                            .luqmaNumericMotion(value:entry.kcal)
                        Image(systemName:"chevron.forward").luqmaFont(.caption2).foregroundStyle(Theme.muted)
                    }.padding(.vertical,12).contentShape(Rectangle())}.buttonStyle(LuqmaPressStyle()).accessibilityHint(diary.t("تعديل الكمية","Edit quantity"))
                        .accessibilityIdentifier("diary.entry."+entry.id.uuidString).accessibilityLabel(DisplayFormat.westernDigits(entry.name))
                        .luqmaMotionTransition()
                    if entry.id != summary.entries.last?.id{Divider()}
                }
            }.padding(.top,6).luqmaMotion(.content,value:summary.entries.count)
        }label:{
            HStack(spacing:8){Text(diary.t("تفاصيل الأطعمة","Food details")).luqmaFont(size:13,weight:.medium,relativeTo:.subheadline);Spacer(minLength:0);Text(decimal(Double(summary.entries.count),0)).luqmaFont(.caption).monospacedDigit().foregroundStyle(Theme.muted).luqmaNumericMotion(value:Double(summary.entries.count))}
                .foregroundStyle(Theme.text).frame(minHeight:30)
        }.tint(Theme.accent)
            // Keep the disclosure and each real row as separate AX actions.
            // Without containment the expanded header's AX button includes
            // the lazy rows, obscuring otherwise visible entry hit targets.
            .accessibilityElement(children:.contain)
            .accessibilityIdentifier("diary.details."+summary.meal.rawValue)
            .luqmaMotion(.content,value:expandedMeals.contains(summary.meal))
    }

}
struct CalorieIntakeDetailView: View {
    @Binding var selectedDate: Date
    @EnvironmentObject var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var activeDayKey: String?
    @State private var windowEnd: Date?
    @State private var showingGoals = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showingMonthPicker: Bool = false

    private struct DayIntakeItem: Identifiable {
        let dayKey: String
        let date: Date
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let targetKcal: Double
        var id: String { dayKey }
    }

    private var sevenDayItems: [DayIntakeItem] {
        let calendar = DisplayFormat.calendar(diary.language)
        let end = calendar.startOfDay(for: min(windowEnd ?? selectedDate, Date()))
        return (0..<7).compactMap { offset -> DayIntakeItem? in
            guard let dateValue = calendar.date(byAdding: .day, value: offset - 6, to: end) else { return nil }
            let key = DayKey.string(dateValue)
            let totals = diary.total(key)
            let target = diary.dailyGoals(key)
            return DayIntakeItem(
                dayKey: key,
                date: dateValue,
                kcal: totals.kcal,
                protein: totals.protein,
                carbs: totals.carbs,
                fat: totals.fat,
                targetKcal: target.kcal
            )
        }
    }

    private var selectedItem: DayIntakeItem {
        if let found = sevenDayItems.first(where: { $0.dayKey == (activeDayKey ?? DayKey.string(selectedDate)) }) {
            return found
        }
        return sevenDayItems.last ?? DayIntakeItem(
            dayKey: DayKey.string(selectedDate),
            date: selectedDate,
            kcal: diary.total(DayKey.string(selectedDate)).kcal,
            protein: diary.total(DayKey.string(selectedDate)).protein,
            carbs: diary.total(DayKey.string(selectedDate)).carbs,
            fat: diary.total(DayKey.string(selectedDate)).fat,
            targetKcal: diary.dailyGoals(DayKey.string(selectedDate)).kcal
        )
    }

    var body: some View {
        let chartItems = sevenDayItems
        let item = selectedItem
        let goals = diary.dailyGoals(item.dayKey)
        let remaining = goals.kcal - item.kcal

        GeometryReader { geometry in
            ScrollView {
        ZStack {
            Color(hex: 0x111214).ignoresSafeArea()

            VStack(spacing: 0) {
                // 1:1 Reference Top Bar (48x48 #393C43 rounded-18 buttons + centered "Calorie Intake")
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(hex: 0x393C43))
                                .frame(width: 48, height: 48)
                            CFACrescentChevron()
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                                .frame(width: 10, height: 18).scaleEffect(x:-1,y:1)
                        }
                    }
                    .buttonStyle(LuqmaPressStyle())
                    .accessibilityLabel(diary.t("رجوع", "Back")).accessibilityIdentifier("calorie.back")

                    Spacer()

                    Text(diary.t("استهلاك السعرات", "Calorie Intake"))
                        .luqmaFont(size: 18, weight: .bold, relativeTo: .headline)
                        .foregroundStyle(Color.white)

                    Spacer()

                    Button {
                        showingGoals = true
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color(hex: 0x393C43))
                                .frame(width: 48, height: 48)
                            Image(systemName: "gearshape")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Color.white)
                        }
                    }
                    .buttonStyle(LuqmaPressStyle())
                    .accessibilityLabel(diary.t("إعدادات هدف السعرات", "Calorie Goal Settings"))
                }
                .environment(\.layoutDirection,.leftToRight)
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // Hero Calorie Readout + Subtitle + Date Pill (Exact dnm_03.png Hierarchy)
                VStack(spacing: 8) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Color(hex: 0xF97316))
                        Text(decimal(item.kcal, 0))
                            .accessibilityIdentifier("calorie.consumed")
                            .luqmaNumericMotion(value:item.kcal)
                            .luqmaFont(size: 64, weight: .heavy, relativeTo: .largeTitle)
                            .monospacedDigit()
                            .foregroundStyle(Color.white)
                        Text("kcal")
                            .luqmaFont(size: 30, weight: .bold, relativeTo: .title2)
                            .foregroundStyle(Color(hex: 0x9EA0A5))
                    }.environment(\.layoutDirection,.leftToRight)

                    Text(
                        remaining >= 0
                        ? diary.t("متبقي \(decimal(remaining, 0)) سعرة لهدف اليوم.", "Eat \(decimal(remaining, 0)) calorie left.")
                        : diary.t("أعلى من الهدف بـ \(decimal(abs(remaining), 0)) سعرة.", "\(decimal(abs(remaining), 0)) calorie above goal.")
                    )
                    .luqmaFont(size: 16, weight: .semibold, relativeTo: .body)
                    .accessibilityIdentifier("calorie.remaining")
                    .luqmaNumericMotion(value:abs(remaining))
                    .foregroundStyle(Color(hex: 0xD7D8D9))

                    Button {
                        showingMonthPicker.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color(hex: 0x9EA0A5))
                            Text(DisplayFormat.date(item.date, template: "MMMM yyyy", language: diary.language))
                                .luqmaFont(size: 14, weight: .semibold, relativeTo: .subheadline)
                                .foregroundStyle(Color(hex: 0xD7D8D9))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color(hex: 0x9EA0A5))
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(hex: 0x24262B))
                        )
                    }
                    .buttonStyle(LuqmaPressStyle())
                    .accessibilityIdentifier("calorie.date")
                    .padding(.top, 6)
                }
                .padding(.top, 24)

                Spacer(minLength: 12)

                // Full-Bleed Chart + Overlapping Bottom 3-Column Macro Card (Exact dnm_03.png Layout)
                ZStack(alignment: .bottom) {
                    VStack(spacing: 0) {
                        Chart {
                            ForEach(chartItems) { point in
                                AreaMark(
                                    x: .value("Day", point.dayKey),
                                    y: .value("Calories", point.kcal)
                                )
                                .interpolationMethod(.catmullRom)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color(hex: 0xF97316).opacity(0.45), Color(hex: 0xF97316).opacity(0.05)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                                LineMark(
                                    x: .value("Day", point.dayKey),
                                    y: .value("Calories", point.kcal)
                                )
                                .interpolationMethod(.catmullRom)
                                .lineStyle(StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                                .foregroundStyle(Color(hex: 0xF97316))

                                if point.dayKey == item.dayKey {
                                    RuleMark(x: .value("Selected", point.dayKey))
                                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                                        .foregroundStyle(Color(hex: 0xF97316))

                                    PointMark(
                                        x: .value("Day", point.dayKey),
                                        y: .value("Calories", point.kcal)
                                    )
                                    .symbol {
                                        ZStack {
                                            Circle()
                                                .fill(Color(hex: 0x111214))
                                                .frame(width: 20, height: 20)
                                            Circle()
                                                .fill(Color(hex: 0xF97316))
                                                .frame(width: 12, height: 12)
                                        }
                                    }
                                    .annotation(position: .top, spacing: 10, overflowResolution: .init(x:.fit(to:.chart),y:.disabled)) {
                                        VStack(spacing: -2) {
                                            Text("\(decimal(point.kcal, 0))" + diary.t(" سعرة", "kcal"))
                                                .luqmaFont(size: 13, weight: .bold, relativeTo: .caption)
                                                .monospacedDigit()
                                                .foregroundStyle(Color.white)
                                                .padding(.horizontal, 14)
                                                .frame(height: 34)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                                        .fill(Color(hex: 0xF97316))
                                                )
                                            Image(systemName: "arrowtriangle.down.fill")
                                                .font(.system(size: 9))
                                                .foregroundStyle(Color(hex: 0xF97316))
                                        }
                                    }
                                }
                            }
                        }
                        .environment(\.layoutDirection,.leftToRight)
                        .chartLegend(.hidden)
                        .chartYAxis {
                            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { axis in
                                AxisGridLine()
                                    .foregroundStyle(Color(hex: 0x24262B))
                                AxisValueLabel {
                                    if let v = axis.as(Double.self) {
                                        Text(decimal(v, 0))
                                            .luqmaFont(size: 11, weight: .semibold, relativeTo: .caption2)
                                            .foregroundStyle(Color(hex: 0x676C75))
                                    }
                                }
                            }
                        }
                        .chartXAxis(.hidden)
                        .frame(height: 360)
                        .contentShape(Rectangle())
                        .chartXSelection(value: $activeDayKey)
                        .luqmaMotion(.content,value:chartItems.map(\.kcal))
                        .accessibilityIdentifier("calorie.chart")
                    }
                    .padding(.bottom, 54)

                    // Bottom Floating 3-Column Macro Card (Carbs | Protein | Fat) Matching dnm_03.png 1:1
                    HStack(spacing: 0) {
                        intakeMacroColumn(
                            key: .carbs,
                            grams: item.carbs,
                            title: diary.t("الكارب", "Carbs")
                        )
                        intakeMacroColumn(
                            key: .protein,
                            grams: item.protein,
                            title: diary.t("البروتين", "Protein")
                        )
                        intakeMacroColumn(
                            key: .fat,
                            grams: item.fat,
                            title: diary.t("الدهون", "Fat")
                        )
                    }
                    .environment(\.layoutDirection,.leftToRight)
                    .frame(height: 138)
                    .background(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color(hex: 0x393C43))
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 22)
                }
            }
        }
        .frame(minHeight:geometry.size.height)
            }.scrollBounceBehavior(.basedOnSize)
        }
        .accessibilityIdentifier("diary.calorieHistory")
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            if windowEnd == nil {windowEnd = selectedDate}
            activeDayKey = DayKey.string(selectedDate)
        }
        .onChange(of:activeDayKey){_,key in
            if let key,let point=sevenDayItems.first(where:{$0.dayKey==key}){selectedDate=point.date}
        }
        .sheet(isPresented:$showingGoals){GoalEditor()}
        .sheet(isPresented:$showingMonthPicker,onDismiss:{windowEnd=selectedDate;activeDayKey=DayKey.string(selectedDate)}){
            NavigationStack{
                DatePicker(diary.t("اختيار التاريخ","Choose date"),selection:$selectedDate,in:...Date(),displayedComponents:.date)
                    .datePickerStyle(.graphical).accessibilityIdentifier("calorie.datePicker").padding(16).appBackground()
                    .sandowNavigation(diary.t("اختيار التاريخ","Choose date"),backLabel:diary.t("تم","Done"),onBack:{windowEnd=selectedDate;activeDayKey=DayKey.string(selectedDate);showingMonthPicker=false})
            }.presentationDetents([.medium,.large])
        }
    }

    private func intakeMacroColumn(key: MacroKey, grams: Double, title: String) -> some View {
        VStack(spacing: 6) {
            LuqmaMacroIcon(key:key,size:22)
            Text("\(decimal(grams, 0))" + diary.t("جم", "g"))
                .luqmaFont(size: 28, weight: .heavy, relativeTo: .title)
                .accessibilityIdentifier("calorie.macro." + key.rawValue)
                .monospacedDigit().luqmaNumericMotion(value:grams)
                .foregroundStyle(Color.white)
            Text(title)
                .luqmaFont(size: 13, weight: .medium, relativeTo: .caption)
                .foregroundStyle(Color(hex: 0x9EA0A5))
        }
        .frame(maxWidth: .infinity)
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
            Section{Text(DisplayFormat.westernDigits(entry.name)).luqmaFont(.headline);TextField(diary.t("الكمية","Amount"),text:$amount,prompt:Text(diary.t("الكمية","Amount")).foregroundColor(Theme.muted)).keyboardType(.decimalPad).accessibilityIdentifier("entry.amount");Text(entry.unitLabel(diary.language)).foregroundStyle(Theme.muted)}.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            Section(diary.t("إجمالي هذه الكمية","Nutrition for this amount")){NutritionView(value:total)}.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            Section{Button(diary.t("حذف الطعام","Delete food"),role:.destructive){LuqmaHapticManager.play(.light);deleting=true}.accessibilityIdentifier("entry.delete")}.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
        }.sandowForm().sandowNavigation(diary.t("تعديل الطعام","Edit food"),backLabel:diary.t("إلغاء","Cancel"),onBack:{dismiss()},
            actionLabel:diary.t("حفظ التعديل","Save changes"),actionEnabled:!(value == nil || (value ?? 0)<=0 || (value ?? 0)>10000),actionIdentifier:"entry.save",actionFeedback:nil,
            onAction:{if let value,diary.resize(entry.id,value){LuqmaFeedbackCenter.shared.saved(diary.t("تم حفظ التعديلات","Changes saved"));dismiss()}})
            .confirmationDialog(diary.t("حذف الطعام من اليوم؟","Delete this diary entry?"),isPresented:$deleting,titleVisibility:.visible){
                Button(diary.t("حذف","Delete"),role:.destructive){
                    let existed=diary.state.entries.contains{$0.id==entry.id}
                    diary.remove(entry.id)
                    if existed,!diary.state.entries.contains(where:{$0.id==entry.id}){LuqmaFeedbackCenter.shared.saved(diary.t("تم حذف الطعام","Food deleted"))}
                    dismiss()
                }
            }
        }.onAppear{amount=decimal(entry.amount,entry.amount.rounded()==entry.amount ? 0:2)}
    }
}
