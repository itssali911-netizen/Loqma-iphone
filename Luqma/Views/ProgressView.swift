import SwiftUI
import Charts

struct ProgressViewScreen:View {
    @EnvironmentObject var diary:DiaryStore
    @EnvironmentObject var health:HealthService
    @State private var range=90
    @State private var adding=false
    @State private var plan=false
    @State private var deleting:WeightReading?
    private var readings:[WeightReading] {diary.state.weights.filter{let days=WeightModel.days($0.day,DayKey.today);return days>=0 && (range==0 || days<range)}}
    var body:some View {
        ScrollView{VStack(alignment:.leading,spacing:20){
            if let latest=diary.state.weights.last{HStack(alignment:.firstTextBaseline){Text(decimal(latest.kg)).font(.system(size:42,weight:.bold,design:.rounded)).foregroundStyle(Theme.accent);Text(diary.t("كجم","kg")).foregroundStyle(Theme.muted);Spacer();Button{adding=true}label:{Image(systemName:"plus.circle.fill").font(.title)}}.luqmaCard()}
            else{Button(diary.t("تسجيل أول وزن","Log your first weight")){adding=true}.buttonStyle(.borderedProminent)}
            weightChart
            HStack{Button{plan=true}label:{Label(diary.t("خطة الوزن","Weight plan"),systemImage:"target")};Spacer();Button(diary.t("تسجيل وزن","Log weight")){adding=true}}.buttonStyle(.bordered)
            VStack(alignment:.leading,spacing:14){
                Toggle(diary.t("تحديث السعرات مع الوزن","Update calories with weight"),isOn:Binding(get:{diary.state.adaptive},set:{value in diary.change{$0.adaptive=value};diary.adapt()})).disabled(diary.state.weightPlan==nil)
                let average=DiaryValidation.average(diary.state.weights,ending:DayKey.today)
                if let kg=average.kg{Text("\(diary.t("متوسط الأسبوع","Weekly average")): \(decimal(kg)) \(diary.t("كجم","kg")) · \(average.count) \(diary.t("قراءات","readings"))").font(.footnote).foregroundStyle(Theme.muted)}
                Notice(text:diary.adaptiveMessage ?? diary.t("يتطلب خطة محفوظة و٣ قراءات خلال أسبوع. يعتمد على متوسط الوزن لإعادة حساب الخطة حتى موعد الهدف.","Requires a saved plan and three readings this week. Average weight updates the plan through its target date."))
            }.luqmaCard()
            HealthPanel()
            if !readings.isEmpty{VStack(alignment:.leading,spacing:14){Text(diary.t("سجل الوزن","Weight history")).font(.headline);ForEach(Array(readings.reversed().prefix(30))){w in HStack{Text(w.day).font(.subheadline).monospacedDigit();Spacer();VStack(alignment:.trailing){Text(decimal(w.kg)+" kg");if let source=w.source{Text(source).font(.caption).foregroundStyle(Theme.muted)}};Button(role:.destructive){deleting=w}label:{Image(systemName:"trash")}.accessibilityLabel(diary.t("حذف قراءة الوزن","Delete weight reading"))}}}.luqmaCard()}
        }.padding(20)}.appBackground().navigationTitle(diary.t("تقدّمي","My progress"))
            .sheet(isPresented:$adding){WeightEditor()}
            .sheet(isPresented:$plan){NavigationStack{PlanView().toolbar{ToolbarItem(placement:.cancellationAction){Button(diary.t("إغلاق","Close")){plan=false}}}}}
            .confirmationDialog(diary.t("حذف قراءة الوزن؟","Delete weight reading?"),isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}}),titleVisibility:.visible){Button(diary.t("حذف","Delete"),role:.destructive){if let w=deleting{diary.removeWeight(w.day)};deleting=nil}}
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
struct HealthPanel:View {
    @EnvironmentObject var diary:DiaryStore
    @EnvironmentObject var health:HealthService
    @State private var importingHealth = false
    var body:some View {VStack(alignment:.leading,spacing:14){
        Label("Apple Health",systemImage:"heart.fill").font(.headline).foregroundStyle(.pink)
        if !diary.state.healthEnabled{Button(diary.t("ربط تطبيق صحتي","Connect Health")){Task{await health.connect(diary)}}.buttonStyle(.borderedProminent).disabled(health.busy)}
        else {
            Label(diary.t("المزامنة التلقائية مفعّلة", "Automatic sync is on"), systemImage: "arrow.triangle.2.circlepath").font(.subheadline)
            HStack {
                Button(diary.t("تحديث الآن", "Refresh now")) { Task { await health.sync(diary) } }.disabled(health.busy)
                Spacer()
                if let date = health.lastSync { VStack(alignment: .trailing) { Text(diary.t("آخر تحديث", "Last refreshed")); Text(date, style: .relative) }.font(.caption).foregroundStyle(Theme.muted) }
            }
            HStack {
                if let steps = health.steps { Label("\(decimal(steps,0))", systemImage: "figure.walk") }
                Spacer()
                if let calories = health.activeCalories { Label("\(decimal(calories,0)) kcal", systemImage: "flame") }
            }.font(.subheadline)
            if let height = health.heightCM { Text("\(diary.t("الطول", "Height")): \(decimal(height)) cm").font(.footnote).foregroundStyle(Theme.muted) }
            if health.backgroundStatus == .enabled { Notice(text: diary.t("تحديثات الخلفية مسجّلة. يحدد iOS توقيتها؛ قد يتأخر تحديث الخطوات.", "Background updates are registered. iOS controls timing; step updates can be delayed.")) }
            else if health.backgroundStatus == .limited || health.backgroundStatus == .unavailable { Notice(text: diary.t("المزامنة أثناء فتح التطبيق متاحة. تحديث الخلفية غير متاح لكل البيانات؛ يحتاج صلاحية HealthKit Background Delivery في التوقيع.", "Foreground sync is available. Background delivery is not available for all data; the signature needs HealthKit Background Delivery.")) }
            Button(diary.t("إيقاف الربط", "Disconnect")) { Task { await health.disconnect(diary) } }.font(.footnote)
        }
        if let message=health.message{Notice(text:message)}
        Button { importingHealth = true } label: { Label(diary.t("استيراد بيانات صحتي", "Import Health data"), systemImage: "square.and.arrow.down") }.buttonStyle(.bordered)
        if health.busy{ProgressView()}
        Notice(text:diary.t("بعد السماح مرة واحدة، تُراقَب تغييرات صحتي تلقائيًا. تحفظ القراءات على الجهاز وتُستكمل بعد فتح القفل. سعرات النشاط للعرض ولا تُضاف فوق خطة النشاط.","After one-time permission, Health changes are observed automatically. Readings stay on the device and updates resume after unlocking. Activity calories are informational and are not added again to your plan."))
        DisclosureGroup(diary.t("إعداد التوقيع والربط", "Signing and connection setup")) {
            VStack(alignment: .leading, spacing: 10) {
                Text(diary.t("صدّر نسخة احتياطية من لقمة أولًا. ثبّت ملف التحديث عبر Impactor على ويندوز بنفس حساب Apple. احتفظ بمعرّف التطبيق المثبت، ثم اسمح بقراءة البيانات عند الضغط على الربط.", "Export a Luqma backup first. Install the update through Impactor on Windows with the same Apple account. Keep the installed app identifier, then allow reads when you press Connect."))
                Link(diary.t("تحميل Impactor", "Download Impactor"), destination: URL(string: "https://github.com/claration/impactor/releases")!)
                Text(diary.t("معرّف النسخة المثبتة — انسخه عند الحاجة", "Installed identifier — copy if needed")).foregroundStyle(Theme.muted)
                Text(health.installedIdentifier).font(.caption.monospaced()).textSelection(.enabled)
            }.font(.footnote).padding(.top, 8)
        }
    }.luqmaCard().sheet(isPresented: $importingHealth) { HealthImportView() }}
}
