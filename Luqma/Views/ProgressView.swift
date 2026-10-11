import SwiftUI
import Charts

struct ProgressViewScreen:View {
    @EnvironmentObject var diary:DiaryStore
    @EnvironmentObject var health:HealthService
    @State private var range=90
    @State private var adding=false
    @State private var adaptiveDetails=false
    @State private var deleting:WeightReading?
    private var readings:[WeightReading] {diary.state.weights.filter{let days=WeightModel.days($0.day,DayKey.today);return days>=0 && (range==0 || days<range)}}
    var body:some View {
        ScrollView{VStack(alignment:.leading,spacing:18){
            weightSummary
            weightChart
            weightPlan
            healthConnection
            weightHistory
        }.padding(20)}.appBackground().navigationTitle(diary.t("تقدّمي","My progress"))
            .sheet(isPresented:$adding){WeightEditor()}
            .confirmationDialog(diary.t("حذف قراءة الوزن؟","Delete weight reading?"),isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}}),titleVisibility:.visible){Button(diary.t("حذف","Delete"),role:.destructive){if let w=deleting{diary.removeWeight(w.day)};deleting=nil}}
    }
    private var weightSummary:some View {VStack(alignment:.leading,spacing:14){
        if let latest=diary.state.weights.last {
            Text(diary.t("آخر وزن","Latest weight")).font(.subheadline).foregroundStyle(Theme.muted)
            HStack(alignment:.firstTextBaseline,spacing:8){
                Text(decimal(latest.kg)).font(.largeTitle.bold()).monospacedDigit().foregroundStyle(Theme.accent)
                Text(diary.t("كجم","kg")).foregroundStyle(Theme.muted)
                Spacer(minLength:0)
            }
            Text(latest.day).font(.caption).monospacedDigit().foregroundStyle(Theme.muted)
        } else {
            Text(diary.t("ابدأ بتسجيل وزنك","Start with your weight")).font(.headline)
            Notice(text:diary.t("تابع تغيّر وزنك ومتوسط الأسبوع هنا.","Track your weight trend and weekly average here."))
        }
        Button{adding=true}label:{Label(diary.t("تسجيل وزن","Log weight"),systemImage:"plus")}.buttonStyle(.borderedProminent)
    }.luqmaCard()}
    private var weightPlan:some View {VStack(alignment:.leading,spacing:14){
        NavigationLink{PlanView()}label:{HStack(spacing:12){
            Image(systemName:"target").foregroundStyle(Theme.accent)
            VStack(alignment:.leading,spacing:4){
                Text(diary.t("خطة الوزن","Weight plan")).font(.headline).foregroundStyle(.primary)
                if let plan=diary.state.weightPlan{Text("\(diary.t("الهدف","Goal")): \(decimal(plan.targetWeight)) \(diary.t("كجم","kg"))").font(.subheadline).foregroundStyle(Theme.muted)}
                else{Text(diary.t("حدد هدفك والسعرات المناسبة","Set your goal and calorie target")).font(.subheadline).foregroundStyle(Theme.muted)}
            }
            Spacer(minLength:0)
            Image(systemName:"chevron.forward").font(.caption).foregroundStyle(Theme.muted)
        }}.buttonStyle(.plain)
        if diary.state.weightPlan != nil {
            Divider()
            Toggle(diary.t("تحديث السعرات مع الوزن","Update calories with weight"),isOn:Binding(get:{diary.state.adaptive},set:{value in diary.change{$0.adaptive=value};diary.adapt()}))
            let average=DiaryValidation.average(diary.state.weights,ending:DayKey.today)
            if let kg=average.kg{Text("\(diary.t("متوسط الأسبوع","Weekly average")): \(decimal(kg)) \(diary.t("كجم","kg"))").font(.footnote).foregroundStyle(Theme.muted)}
            DisclosureGroup(diary.t("كيف يعمل التحديث؟","How does it work?"),isExpanded:$adaptiveDetails){
                Notice(text:diary.adaptiveMessage ?? diary.t("يتطلب ٣ قراءات خلال أسبوع. يستخدم متوسط الوزن لتحديث السعرات حتى موعد الهدف.","Requires three readings this week. Uses your average weight to update calories through your target date.")).padding(.top,8)
            }.font(.footnote)
        }
    }.luqmaCard()}
    private var healthConnection:some View {NavigationLink{HealthConnectionView()}label:{HStack(spacing:12){
        Image(systemName:"heart.fill").foregroundStyle(.pink).font(.title2)
        VStack(alignment:.leading,spacing:4){
            Text("Apple Health").font(.headline).foregroundStyle(.primary)
            Text(health.signingBlocked ? diary.t("يحتاج إعداد الربط","Connection setup needed") : (diary.state.healthEnabled ? diary.t("الربط مفعّل","Connection enabled") : diary.t("اربط الوزن والخطوات","Connect weight and steps"))).font(.subheadline).foregroundStyle(Theme.muted)
        }
        Spacer(minLength:0)
        Image(systemName:"chevron.forward").font(.caption).foregroundStyle(Theme.muted)
    }.luqmaCard()}.buttonStyle(.plain)}
    @ViewBuilder private var weightHistory:some View {
        if !readings.isEmpty{VStack(alignment:.leading,spacing:14){
            Text(diary.t("سجل الوزن","Weight history")).font(.headline)
            if readings.count>30{Text(diary.t("آخر ٣٠ قراءة في المدة المختارة","Latest 30 readings in the selected range")).font(.caption).foregroundStyle(Theme.muted)}
            ForEach(Array(readings.reversed().prefix(30))){w in HStack(spacing:12){
                VStack(alignment:.leading,spacing:4){Text(w.day).font(.subheadline).monospacedDigit();if let source=w.source{Text(source=="Manual" ? diary.t("إدخال يدوي","Manual entry"):source).font(.caption).foregroundStyle(Theme.muted)}}
                Spacer(minLength:0)
                Text(decimal(w.kg)+" "+diary.t("كجم","kg")).monospacedDigit()
                Button(role:.destructive){deleting=w}label:{Image(systemName:"trash").frame(minWidth:44,minHeight:44)}.accessibilityLabel(diary.t("حذف قراءة الوزن","Delete weight reading"))
            }}
        }.luqmaCard()}
    }
    private var weightChart:some View {VStack(alignment:.leading,spacing:18){
        Picker(diary.t("مدة الرسم","Chart range"),selection:$range){Text(diary.t("أسبوع","7d")).tag(7);Text(diary.t("شهر","30d")).tag(30);Text(diary.t("٣ شهور","90d")).tag(90);Text(diary.t("الكل","All")).tag(0)}.pickerStyle(.segmented)
        if readings.isEmpty{Notice(text:diary.t("لا توجد قراءات في هذه المدة.","No readings in this range."))}
        else{Chart{ForEach(readings){w in if let date=DayKey.localDate(w.day){LineMark(x:.value("Date",date),y:.value("Weight",w.kg)).foregroundStyle(Theme.accent);PointMark(x:.value("Date",date),y:.value("Weight",w.kg)).foregroundStyle(Theme.accent)}};if let target=diary.state.weightPlan?.targetWeight{RuleMark(y:.value("Goal",target)).lineStyle(StrokeStyle(lineWidth:1,dash:[5])).foregroundStyle(.orange)}}.chartYScale(domain:.automatic(includesZero:false)).frame(height:230).accessibilityLabel(diary.t("رسم تغيّر الوزن بالكيلوجرام","Weight trend in kilograms"))}
    }.luqmaCard()}
}
struct WeightEditor:View {
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dismiss) var dismiss
    @State private var date=Date()
    @State private var kg:Double=0
    var body:some View {NavigationStack{Form{DatePicker(diary.t("التاريخ","Date"),selection:$date,in:...Date(),displayedComponents:.date);NumericInput(title:diary.t("الوزن","Weight"),value:$kg,suffix:diary.t("كجم","kg"));Notice(text:diary.t("تُحفظ قراءة واحدة لكل يوم. الإدخال اليدوي له أولوية على قراءات صحتي.","One reading is kept per day. Manual entries take priority over Health readings."))}.appBackground().navigationTitle(diary.t("تسجيل الوزن","Log weight")).toolbar{ToolbarItem(placement:.cancellationAction){Button(diary.t("إلغاء","Cancel")){dismiss()}};ToolbarItem(placement:.confirmationAction){Button(diary.t("حفظ","Save")){if diary.saveWeight(WeightReading(day:DayKey.string(date),kg:kg,source:"Manual",timestamp:Date().timeIntervalSince1970)){dismiss()}}.disabled(!(35...300).contains(kg))}}}.onAppear{kg=diary.state.weights.last?.kg ?? diary.state.weightPlan?.weight ?? 0}}
}
