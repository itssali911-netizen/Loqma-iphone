import SwiftUI
import Charts

struct ProgressViewScreen:View {
    @EnvironmentObject var diary:DiaryStore
    @State private var range=90
    @State private var adding=false
    @State private var adaptiveDetails=false
    @State private var deleting:WeightReading?
    var body:some View {
        let snapshot=WeightProgressSnapshot.make(diary.state.weights,ending:DayKey.today,range:range)
        return ScrollView{VStack(alignment:.leading,spacing:18){
            weightSummary
            AppleHealthProgressCard()
            Text(diary.t("اتجاه الوزن","Weight trend")).luqmaFont(size:13,weight:.semibold,relativeTo:.subheadline)
                .accessibilityAddTraits(.isHeader)
            weightChart(snapshot)
            fitnessProfile
            weightPlan
            weightHistory(snapshot.readings)
        }.padding(16).padding(.bottom,10)}.appBackground().navigationTitle(diary.t("تقدّمي","My progress"))
            .toolbar(.hidden,for:.navigationBar)
            .safeAreaInset(edge:.top,spacing:0){LuqmaCompactTitle(title:diary.t("تقدّمي","My progress")).background(Theme.background)}
            .sheet(isPresented:$adding){WeightEditor()}
            .confirmationDialog(diary.t("حذف قراءة الوزن؟","Delete weight reading?"),isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}}),titleVisibility:.visible){Button(diary.t("حذف","Delete"),role:.destructive){if let w=deleting{diary.removeWeight(w.day)};deleting=nil}}
    }
    private var fitnessProfile:some View {
        NavigationLink{FitnessProfileView()}label:{VStack(alignment:.leading,spacing:10){
            HStack(spacing:10){
                Image(systemName:"figure.strengthtraining.traditional").font(.system(size:19,weight:.regular))
                    .foregroundStyle(Theme.accentText).frame(width:36,height:36).background(Theme.surface,in:RoundedRectangle(cornerRadius:11)).accessibilityHidden(true)
                Text(diary.t("خطة اللياقة الشخصية","Personal fitness plan")).luqmaFont(.headline).foregroundStyle(Theme.text)
                Spacer(minLength:8)
                Image(systemName:"chevron.forward").font(.system(size:13,weight:.medium)).foregroundStyle(Theme.muted)
            }
            if let profile=diary.state.fitnessProfile{
                Text(profile.answers.goal?.title(diary.language) ?? "—").luqmaFont(.footnote).foregroundStyle(Theme.muted)
                if diary.state.proposedFitnessPlan != nil{
                    Text(diary.t("لديك معاينة جديدة للمراجعة؛ لم تتغير أهدافك الحالية.","A new preview is ready for review. Your current targets are unchanged.")).luqmaFont(.footnote).foregroundStyle(Theme.accentText)
                }
            }else{
                Text(diary.t("تقييم قصير لتقدير التغذية والنشاط","A short assessment for nutrition and activity estimates")).luqmaFont(.footnote).foregroundStyle(Theme.muted)
            }
        }.luqmaCard()}.buttonStyle(LuqmaPressStyle()).accessibilityIdentifier("progress.fitnessProfile")
    }
    private var weightSummary:some View {VStack(alignment:.leading,spacing:16){
        if let latest=diary.state.weights.last {
            HStack(alignment:.center,spacing:12){
                VStack(alignment:.leading,spacing:8){
                    Text(diary.t("آخر وزن","Latest weight")).luqmaFont(size:12,relativeTo:.caption).foregroundStyle(Theme.muted)
                    HStack(alignment:.firstTextBaseline,spacing:6){Text(decimal(latest.kg)).luqmaFont(size:34,weight:.bold,relativeTo:.largeTitle).monospacedDigit().luqmaNumericMotion(value:latest.kg);Text(diary.t("كجم","kg")).luqmaFont(size:12,relativeTo:.caption).foregroundStyle(Theme.muted)}
                    if let average=DiaryValidation.average(diary.state.weights,ending:DayKey.today).kg{
                        Text(diary.t("متوسط الأسبوع: ","Weekly average: ")+decimal(average)+" "+diary.t("كجم","kg"))
                            .luqmaFont(.caption).foregroundStyle(Theme.muted)
                    }
                    Text(latest.day).luqmaFont(size:10,relativeTo:.caption2).monospacedDigit().foregroundStyle(Theme.muted).padding(.horizontal,8).padding(.vertical,4).background(Theme.surface,in:Capsule())
                }
                Spacer(minLength:0)
                Image(systemName:"scalemass").font(.system(size:22,weight:.regular)).foregroundStyle(Theme.text).frame(width:44,height:44).background(Theme.surface,in:RoundedRectangle(cornerRadius:13,style:.continuous)).accessibilityHidden(true)
            }
        } else {
            Image(systemName:"scalemass").font(.system(size:24,weight:.regular)).foregroundStyle(Theme.accentText)
                .frame(width:48,height:48).background(Theme.surface,in:RoundedRectangle(cornerRadius:14)).accessibilityHidden(true)
            Text(diary.t("ابدأ بتسجيل وزنك","Start with your weight")).luqmaFont(.headline)
            Notice(text:diary.t("تابع تغيّر وزنك ومتوسط الأسبوع هنا.","Track your weight trend and weekly average here."))
        }
        Button{adding=true}label:{Label(diary.t("تسجيل وزن","Log weight"),systemImage:"plus")}
            .buttonStyle(LuqmaPrimaryButtonStyle()).accessibilityIdentifier("progress.logWeight")
    }.luqmaCard()}
    private var weightPlan:some View {VStack(alignment:.leading,spacing:12){
        NavigationLink{PlanView()}label:{HStack(spacing:10){
            Image(systemName:"target").font(.system(size:19)).foregroundStyle(Theme.text).frame(width:36,height:36).background(Theme.surface,in:RoundedRectangle(cornerRadius:11))
            VStack(alignment:.leading,spacing:4){
                Text(diary.t("خطة الوزن","Weight plan")).luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline).foregroundStyle(Theme.text)
                if let plan=diary.state.weightPlan{Text("\(diary.t("الهدف","Goal")): \(decimal(plan.targetWeight)) \(diary.t("كجم","kg"))").luqmaFont(size:11,relativeTo:.caption).foregroundStyle(Theme.muted)}
                else{Text(diary.t("حدد هدفك والسعرات المناسبة","Set your goal and calorie target")).luqmaFont(size:11,relativeTo:.caption).foregroundStyle(Theme.muted)}
            }
            Spacer(minLength:0)
            Image(systemName:"chevron.forward").font(.caption).foregroundStyle(Theme.muted)
        }}.buttonStyle(LuqmaPressStyle())
        if diary.state.weightPlan != nil {
            Divider().overlay(Theme.stroke)
            Toggle(diary.t("تحديث السعرات مع الوزن","Update calories with weight"),isOn:Binding(get:{diary.state.adaptive},set:{value in diary.change{$0.adaptive=value};diary.adapt()})).luqmaFont(size:14,relativeTo:.body).luqmaFeedback(.selection,trigger:diary.state.adaptive)
            let average=DiaryValidation.average(diary.state.weights,ending:DayKey.today)
            if let kg=average.kg{Text("\(diary.t("متوسط الأسبوع","Weekly average")): \(decimal(kg)) \(diary.t("كجم","kg"))").luqmaFont(.footnote).foregroundStyle(Theme.muted).luqmaNumericMotion(value:kg)}
            DisclosureGroup(diary.t("كيف يعمل التحديث؟","How does it work?"),isExpanded:$adaptiveDetails){
                Notice(text:diary.adaptiveMessage ?? diary.t("يتطلب ٣ قراءات خلال أسبوع. يستخدم متوسط الوزن لتحديث السعرات حتى موعد الهدف.","Requires three readings this week. Uses your average weight to update calories through your target date.")).padding(.top,8)
            }.luqmaFont(.footnote).luqmaMotion(.content,value:adaptiveDetails)
        }
    }.luqmaCard()}
    @ViewBuilder private func weightHistory(_ readings:[WeightReading])->some View {
        if !readings.isEmpty{VStack(alignment:.leading,spacing:10){
            Text(diary.t("سجل الوزن","Weight history")).luqmaFont(size:13,weight:.semibold,relativeTo:.subheadline).accessibilityAddTraits(.isHeader)
            if readings.count>30{Text(diary.t("آخر ٣٠ قراءة في المدة المختارة","Latest 30 readings in the selected range")).luqmaFont(.caption).foregroundStyle(Theme.muted)}
            ForEach(Array(readings.reversed().prefix(30))){w in HStack(spacing:12){
                VStack(alignment:.leading,spacing:4){Text(w.day).luqmaFont(size:13,relativeTo:.subheadline).monospacedDigit();if let source=w.source{Text(source=="Manual" ? diary.t("إدخال يدوي","Manual entry"):source).luqmaFont(size:10,relativeTo:.caption2).foregroundStyle(Theme.muted)}}
                Spacer(minLength:0)
                Text(decimal(w.kg)+" "+diary.t("كجم","kg")).luqmaFont(size:14,weight:.semibold,relativeTo:.body).monospacedDigit().luqmaNumericMotion(value:w.kg)
                Button(role:.destructive){deleting=w}label:{Image(systemName:"trash").font(.system(size:16)).frame(minWidth:44,minHeight:44)}.accessibilityLabel(diary.t("حذف قراءة الوزن","Delete weight reading"))
            }.padding(.leading,2).padding(.trailing,0).padding(.vertical,3)
                .overlay(alignment:.bottom){Rectangle().fill(Theme.stroke).frame(height:1)}.luqmaMotionTransition()}
        }.luqmaCard().luqmaMotion(.content,value:readings.suffix(30).map(\.id))}
    }
    private func weightChart(_ snapshot:WeightProgressSnapshot)->some View {VStack(alignment:.leading,spacing:16){
        LuqmaReviewSegments(options:[7,30,90,0],selection:$range,label:rangeTitle)
            .accessibilityLabel(diary.t("مدة الرسم","Chart range"))
        if snapshot.points.isEmpty{
            VStack(spacing:8){
                Image(systemName:"chart.xyaxis.line").font(.system(size:24,weight:.regular)).accessibilityHidden(true)
                Notice(text:diary.t("لا توجد قراءات في هذه المدة.","No readings in this range."))
            }.foregroundStyle(Theme.muted).padding(.vertical,16)
        }
        else{Chart{
            ForEach(snapshot.points){point in
                AreaMark(x:.value("Date",point.date),yStart:.value("Lower bound",snapshot.lowerBound),yEnd:.value("Weight",point.reading.kg)).foregroundStyle(LinearGradient(colors:[Theme.accent.opacity(0.28),Theme.accent.opacity(0.015)],startPoint:.top,endPoint:.bottom))
                LineMark(x:.value("Date",point.date),y:.value("Weight",point.reading.kg)).lineStyle(StrokeStyle(lineWidth:2.5)).foregroundStyle(Theme.accent)
                PointMark(x:.value("Date",point.date),y:.value("Weight",point.reading.kg)).symbolSize(25).foregroundStyle(Theme.accent)
            }
            if let target=diary.state.weightPlan?.targetWeight{RuleMark(y:.value("Goal",target)).lineStyle(StrokeStyle(lineWidth:1,dash:[5])).foregroundStyle(Theme.muted)}
        }.chartYScale(domain:.automatic(includesZero:false)).chartLegend(.hidden)
            .chartXAxis{AxisMarks(values:.automatic(desiredCount:4)){tick in
                AxisGridLine().foregroundStyle(Theme.stroke)
                AxisValueLabel{if let date=tick.as(Date.self){Text(date,format:.dateTime.day().month(.abbreviated)).luqmaFont(.caption2).foregroundStyle(Theme.muted)}}
            }}
            .chartYAxis{AxisMarks{tick in
                AxisGridLine().foregroundStyle(Theme.stroke)
                AxisValueLabel{if let weight=tick.as(Double.self){Text(decimal(weight)).luqmaFont(.caption2).foregroundStyle(Theme.muted)}}
            }}.frame(height:225)
            .luqmaMotion(.content,value:snapshot.readings.count)
            .luqmaMotion(.content,value:snapshot.readings.last)
            .accessibilityLabel(diary.t("رسم تغيّر الوزن بالكيلوجرام","Weight trend in kilograms"))}
    }.luqmaCard()}
    private func rangeTitle(_ value:Int)->String {switch value{case 7:return diary.t("أسبوع","7d");case 30:return diary.t("شهر","30d");case 90:return diary.t("٣ شهور","90d");default:return diary.t("الكل","All")}}
}
struct WeightEditor:View {
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dismiss) var dismiss
    @State private var date=Date()
    @State private var kg:Double=0
    @State private var initialized=false
    @State private var saving=false
    @State private var saved=false
    private var valid:Bool {kg.isFinite && (35...300).contains(kg) && DayKey.string(date)<=DayKey.today}
    var body:some View {NavigationStack{
        ScrollView{VStack(alignment:.leading,spacing:16){
            LuqmaReviewSection(title:diary.t("قراءة الوزن","Weight reading")){
                DatePicker(diary.t("التاريخ","Date"),selection:$date,in:...Date(),displayedComponents:.date)
                    .datePickerStyle(.compact).luqmaFont(.subheadline)
                LuqmaReviewNumber(title:diary.t("الوزن","Weight"),value:$kg,suffix:diary.t("كجم","kg"),identifier:"weight.value",prominent:true)
            }
            Label(diary.t("تُحفظ قراءة واحدة لكل يوم. تسجيل قراءة جديدة في اليوم نفسه يحدّث القراءة السابقة.","One reading is saved per day. Logging again on the same date updates the previous reading."),systemImage:"info.circle")
                .luqmaFont(.footnote).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true)
            if saved{SandowSavedConfirmation(text:diary.t("تم حفظ الوزن","Weight saved"))}
        }.padding(LuqmaReviewStyle.margin)}.appBackground().luqmaReviewKeyboard()
            .sandowNavigation(diary.t("تسجيل الوزن","Log weight"),backLabel:diary.t("إلغاء","Cancel"),onBack:{dismiss()})
            .safeAreaInset(edge:.bottom,spacing:0){
                Button{save()}label:{HStack(spacing:8){if saving{ProgressView().tint(Theme.onAccent)};Text(saved ? diary.t("تم الحفظ","Saved"):diary.t("حفظ","Save"))}}
                    .buttonStyle(LuqmaPrimaryButtonStyle()).disabled(!valid || saving || saved).accessibilityIdentifier("weight.save")
                    .padding(16).background(Theme.background)
            }
            .luqmaFeedback(.success,trigger:saved){_,value in value}
    }.onAppear{guard !initialized else{return};initialized=true;kg=diary.state.weights.last?.kg ?? diary.state.weightPlan?.weight ?? 0}}
    private func save(){
        guard valid,!saving,!saved else{return}
        saving=true
        saved=diary.saveWeight(WeightReading(day:DayKey.string(date),kg:kg,source:"Manual",timestamp:Date().timeIntervalSince1970))
        saving=false
        if saved{dismiss()}
    }
}
