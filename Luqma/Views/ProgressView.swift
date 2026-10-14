import SwiftUI
import Charts

struct ProgressViewScreen:View {
    @EnvironmentObject var diary:DiaryStore
    @State private var range=90
    @State private var adding=false
    @State private var adaptiveDetails=false
    @State private var deleting:WeightReading?
    private var readings:[WeightReading] {diary.state.weights.filter{let days=WeightModel.days($0.day,DayKey.today);return days>=0 && (range==0 || days<range)}}
    var body:some View {
        ScrollView{VStack(alignment:.leading,spacing:24){
            LuqmaPageHeader(title:diary.t("تقدّمي","My progress"),subtitle:diary.t("خطوات صغيرة، أثر واضح","Small steps, visible progress"),symbol:"chart.xyaxis.line")
            weightSummary
            LuqmaSectionHeader(title:diary.t("اتجاه الوزن","Weight trend"))
            weightChart
            weightPlan
            weightHistory
        }.padding(24).padding(.bottom,10)}.appBackground().navigationTitle(diary.t("تقدّمي","My progress"))
            .toolbar(.hidden,for:.navigationBar)
            .sheet(isPresented:$adding){WeightEditor()}
            .confirmationDialog(diary.t("حذف قراءة الوزن؟","Delete weight reading?"),isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}}),titleVisibility:.visible){Button(diary.t("حذف","Delete"),role:.destructive){if let w=deleting{diary.removeWeight(w.day)};deleting=nil}}
    }
    private var weightSummary:some View {VStack(alignment:.leading,spacing:20){
        if let latest=diary.state.weights.last {
            HStack(alignment:.center,spacing:18){
                VStack(alignment:.leading,spacing:10){
                    Text(diary.t("آخر وزن","Latest weight")).luqmaFont(.subheadline).foregroundStyle(Theme.muted)
                    HStack(alignment:.firstTextBaseline,spacing:8){Text(decimal(latest.kg)).luqmaFont(size:42,weight:.bold,relativeTo:.largeTitle).monospacedDigit();Text(diary.t("كجم","kg")).foregroundStyle(Theme.muted)}
                    Text(latest.day).luqmaFont(.caption).monospacedDigit().foregroundStyle(Theme.muted).padding(.horizontal,10).padding(.vertical,6).background(Theme.surface,in:Capsule())
                }
                Spacer(minLength:0)
                Image(systemName:"scalemass").font(.system(size:29,weight:.regular)).foregroundStyle(Theme.accent).frame(width:64,height:64).background(Theme.surface,in:RoundedRectangle(cornerRadius:20,style:.continuous)).accessibilityHidden(true)
            }
        } else {
            Text(diary.t("ابدأ بتسجيل وزنك","Start with your weight")).luqmaFont(.headline)
            Notice(text:diary.t("تابع تغيّر وزنك ومتوسط الأسبوع هنا.","Track your weight trend and weekly average here."))
        }
        Button{adding=true}label:{Label(diary.t("تسجيل وزن","Log weight"),systemImage:"plus")}.buttonStyle(LuqmaPrimaryButtonStyle())
    }.luqmaCard()}
    private var weightPlan:some View {VStack(alignment:.leading,spacing:14){
        NavigationLink{PlanView().toolbar(.visible,for:.navigationBar)}label:{HStack(spacing:12){
            Image(systemName:"target").font(.system(size:24)).foregroundStyle(Theme.accent).frame(width:46,height:46).background(Theme.surface,in:RoundedRectangle(cornerRadius:15))
            VStack(alignment:.leading,spacing:4){
                Text(diary.t("خطة الوزن","Weight plan")).luqmaFont(.headline).foregroundStyle(.primary)
                if let plan=diary.state.weightPlan{Text("\(diary.t("الهدف","Goal")): \(decimal(plan.targetWeight)) \(diary.t("كجم","kg"))").luqmaFont(.subheadline).foregroundStyle(Theme.muted)}
                else{Text(diary.t("حدد هدفك والسعرات المناسبة","Set your goal and calorie target")).luqmaFont(.subheadline).foregroundStyle(Theme.muted)}
            }
            Spacer(minLength:0)
            Image(systemName:"chevron.forward").font(.caption).foregroundStyle(Theme.muted)
        }}.buttonStyle(.plain)
        if diary.state.weightPlan != nil {
            Divider().overlay(Theme.stroke)
            Toggle(diary.t("تحديث السعرات مع الوزن","Update calories with weight"),isOn:Binding(get:{diary.state.adaptive},set:{value in diary.change{$0.adaptive=value};diary.adapt()}))
            let average=DiaryValidation.average(diary.state.weights,ending:DayKey.today)
            if let kg=average.kg{Text("\(diary.t("متوسط الأسبوع","Weekly average")): \(decimal(kg)) \(diary.t("كجم","kg"))").luqmaFont(.footnote).foregroundStyle(Theme.muted)}
            DisclosureGroup(diary.t("كيف يعمل التحديث؟","How does it work?"),isExpanded:$adaptiveDetails){
                Notice(text:diary.adaptiveMessage ?? diary.t("يتطلب ٣ قراءات خلال أسبوع. يستخدم متوسط الوزن لتحديث السعرات حتى موعد الهدف.","Requires three readings this week. Uses your average weight to update calories through your target date.")).padding(.top,8)
            }.luqmaFont(.footnote)
        }
    }.luqmaCard()}
    @ViewBuilder private var weightHistory:some View {
        if !readings.isEmpty{VStack(alignment:.leading,spacing:14){
            Text(diary.t("سجل الوزن","Weight history")).luqmaFont(.headline).accessibilityAddTraits(.isHeader)
            if readings.count>30{Text(diary.t("آخر ٣٠ قراءة في المدة المختارة","Latest 30 readings in the selected range")).luqmaFont(.caption).foregroundStyle(Theme.muted)}
            ForEach(Array(readings.reversed().prefix(30))){w in HStack(spacing:12){
                VStack(alignment:.leading,spacing:4){Text(w.day).luqmaFont(.subheadline).monospacedDigit();if let source=w.source{Text(source=="Manual" ? diary.t("إدخال يدوي","Manual entry"):source).luqmaFont(.caption).foregroundStyle(Theme.muted)}}
                Spacer(minLength:0)
                Text(decimal(w.kg)+" "+diary.t("كجم","kg")).luqmaFont(size:16,weight:.semibold,relativeTo:.body).monospacedDigit()
                Button(role:.destructive){deleting=w}label:{Image(systemName:"trash").font(.system(size:16)).frame(minWidth:44,minHeight:44)}.accessibilityLabel(diary.t("حذف قراءة الوزن","Delete weight reading"))
            }.padding(.leading,12).padding(.trailing,4).padding(.vertical,8).background(Theme.surface,in:RoundedRectangle(cornerRadius:14))}
        }.luqmaCard()}
    }
    private var weightChart:some View {VStack(alignment:.leading,spacing:18){
        HStack(spacing:4){ForEach([7,30,90,0],id:\.self){value in
            Button{range=value}label:{Text(rangeTitle(value)).luqmaFont(size:12,weight:.semibold,relativeTo:.caption).frame(maxWidth:.infinity,minHeight:40).foregroundStyle(range == value ? Theme.background:Theme.muted).background(range == value ? Theme.text:Theme.surface,in:Capsule())}.buttonStyle(.plain).accessibilityAddTraits(range == value ? .isSelected:[])
        }}.padding(4).background(Theme.surface,in:Capsule()).accessibilityLabel(diary.t("مدة الرسم","Chart range"))
        if readings.isEmpty{Notice(text:diary.t("لا توجد قراءات في هذه المدة.","No readings in this range."))}
        else{Chart{
            ForEach(readings){w in if let date=DayKey.localDate(w.day){
                AreaMark(x:.value("Date",date),yStart:.value("Lower bound",(readings.map{$0.kg}.min() ?? w.kg)-1),yEnd:.value("Weight",w.kg)).foregroundStyle(LinearGradient(colors:[Theme.accent.opacity(0.28),Theme.accent.opacity(0.015)],startPoint:.top,endPoint:.bottom))
                LineMark(x:.value("Date",date),y:.value("Weight",w.kg)).lineStyle(StrokeStyle(lineWidth:2.5)).foregroundStyle(Theme.accent)
                PointMark(x:.value("Date",date),y:.value("Weight",w.kg)).symbolSize(25).foregroundStyle(Theme.accent)
            }}
            if let target=diary.state.weightPlan?.targetWeight{RuleMark(y:.value("Goal",target)).lineStyle(StrokeStyle(lineWidth:1,dash:[5])).foregroundStyle(Theme.secondaryAccent)}
        }.chartYScale(domain:.automatic(includesZero:false)).chartLegend(.hidden).frame(height:225).accessibilityLabel(diary.t("رسم تغيّر الوزن بالكيلوجرام","Weight trend in kilograms"))}
    }.luqmaCard()}
    private func rangeTitle(_ value:Int)->String {switch value{case 7:return diary.t("أسبوع","7d");case 30:return diary.t("شهر","30d");case 90:return diary.t("٣ شهور","90d");default:return diary.t("الكل","All")}}
}
struct WeightEditor:View {
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dismiss) var dismiss
    @State private var date=Date()
    @State private var kg:Double=0
    var body:some View {NavigationStack{Form{
        Section(diary.t("قراءة الوزن","Weight reading")){
            DatePicker(diary.t("التاريخ","Date"),selection:$date,in:...Date(),displayedComponents:.date)
            NumericInput(title:diary.t("الوزن","Weight"),value:$kg,suffix:diary.t("كجم","kg"))
        }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
        Section{Notice(text:diary.t("تُحفظ قراءة واحدة لكل يوم. يمكنك تعديل وزن اليوم بتسجيله من جديد.","One reading is kept per day. Log it again to update that day's weight."))}.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
    }.sandowForm().navigationTitle(diary.t("تسجيل الوزن","Log weight")).navigationBarTitleDisplayMode(.inline).toolbar{ToolbarItem(placement:.cancellationAction){Button(diary.t("إلغاء","Cancel")){dismiss()}};ToolbarItem(placement:.confirmationAction){Button(diary.t("حفظ","Save")){if diary.saveWeight(WeightReading(day:DayKey.string(date),kg:kg,source:"Manual",timestamp:Date().timeIntervalSince1970)){dismiss()}}.disabled(!(35...300).contains(kg))}}}.onAppear{kg=diary.state.weights.last?.kg ?? diary.state.weightPlan?.weight ?? 0}}
}
