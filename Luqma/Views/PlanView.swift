import SwiftUI
import Charts

struct PlanView:View {
    @EnvironmentObject var diary:DiaryStore
    @State private var plan=WeightPlan()
    @State private var result:WeightResult?
    @State private var advanced=false
    @State private var bodyFat=false
    @State private var resting=false
    @State private var calculating=false
    @State private var applied=false
    private func dateBinding(_ key:WritableKeyPath<WeightPlan,String>) -> Binding<Date> {Binding(get:{DayKey.localDate(plan[keyPath:key]) ?? Date()},set:{plan[keyPath:key]=DayKey.string($0)})}
    var body:some View {
        Form{
            Section(diary.t("بياناتك","Your profile")){
                Picker(diary.t("الجنس المستخدم في المعادلة","Sex used by the model"),selection:$plan.sex){Text(diary.t("ذكر","Male")).tag("male");Text(diary.t("أنثى","Female")).tag("female")}
                NumericInput(title:diary.t("العمر","Age"),value:$plan.age)
                NumericInput(title:diary.t("الطول","Height"),value:$plan.height,suffix:diary.t("سم","cm"))
                NumericInput(title:diary.t("الوزن الحالي","Current weight"),value:$plan.weight,suffix:diary.t("كجم","kg"))
            }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            Section(diary.t("الهدف والنشاط","Goal and activity")){
                NumericInput(title:diary.t("وزن الهدف","Goal weight"),value:$plan.targetWeight,suffix:diary.t("كجم","kg"))
                DatePicker(diary.t("بداية الخطة","Start date"),selection:dateBinding(\.startDay),displayedComponents:.date)
                DatePicker(diary.t("موعد الهدف","Goal date"),selection:dateBinding(\.targetDay),displayedComponents:.date)
                NumericInput(title:"PAL",value:$plan.pal)
                Notice(text:diary.t("معامل النشاط: نحو ١٫٤ قليل النشاط، ١٫٦ نشاط خفيف، ١٫٨ متوسط، ٢٫٢ مرتفع. يشمل نشاط اليوم كله.","Activity factor: about 1.4 sedentary, 1.6 light, 1.8 moderate, 2.2 high. Includes total daily activity."))
                HStack{Text(diary.t("تغيير النشاط","Activity change"));Spacer();Text("\(decimal(plan.activityChange,0))%")};Slider(value:$plan.activityChange,in:-50...100,step:5)
            }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            Section{DisclosureGroup(diary.t("قياسات متقدمة (اختياري)","Advanced measurements (optional)"),isExpanded:$advanced){
                Toggle(diary.t("لدي نسبة دهون مقاسة","Measured body fat"),isOn:$bodyFat)
                if bodyFat{NumericInput(title:diary.t("نسبة الدهون","Body fat"),value:Binding(get:{plan.bodyFat ?? 25},set:{plan.bodyFat=$0}),suffix:"%")}
                Toggle(diary.t("لدي معدل حرق راحة مقاس","Measured resting energy"),isOn:$resting)
                if resting{NumericInput(title:diary.t("حرق الراحة","Resting energy"),value:Binding(get:{plan.restingCalories ?? 1600},set:{plan.restingCalories=$0}),suffix:"kcal")}
                NumericInput(title:diary.t("الكارب في نموذج الوزن","Carbs in weight model"),value:$plan.carbPercent,suffix:"%")
                NumericInput(title:diary.t("صوديوم البداية","Baseline sodium"),value:$plan.sodium,suffix:"mg")
                Notice(text:diary.t("إذا كانت القياسات غير متوفرة، تُقدَّر حسب معادلات النموذج. نسبة الكارب هنا تخص محاكاة الوزن؛ أهداف الماكروز تُعدّل من إعداداتها.","Without measurements, the model estimates these values. This carb percentage belongs to the weight simulation; macro targets have their own editor."))
            };Toggle(diary.t("حمل، رضاعة أو خطة طبية خاصة","Pregnancy, breastfeeding or medical diet"),isOn:$plan.specialCase)}.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            Section{Button{calculate()}label:{HStack{Text(diary.t("حساب الخطة","Calculate plan"));if calculating{ProgressView().tint(Theme.background)}}}.buttonStyle(LuqmaPrimaryButtonStyle()).disabled(calculating)}.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top:0,leading:0,bottom:0,trailing:0))
            if let result{planResult(result)}
            Section(diary.t("المنهج العلمي","Scientific model")){
                Notice(text:diary.t("تطبيق مستقل لمعادلات Hall المستخدمة في NIDDK Body Weight Planner، يشمل تغير استهلاك الطاقة والدهون والكتلة الخالية من الدهون والسوائل. مطابق حسابيًا ضمن اختبارات مرجعية، وليس ضمانًا لمسار وزن الفرد. للبالغين فقط.","Independent implementation of the Hall equations used by NIDDK Body Weight Planner, including changing energy expenditure, fat, lean mass and fluid. Checked against reference scenarios, not a guarantee of individual weight change. Adults only."))
                Link("NIDDK Body Weight Planner",destination:URL(string:"https://www.niddk.nih.gov/bwp")!)
                Link("Hall et al. • Lancet 2011",destination:URL(string:"https://pmc.ncbi.nlm.nih.gov/articles/PMC3880593/")!)
            }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
        }.sandowForm().sandowNavigation(diary.t("خطة الوزن","Weight plan"),backLabel:diary.t("رجوع","Back"))
            .onAppear{if let saved=diary.state.weightPlan{plan=saved}else{plan.weight=diary.state.weights.last?.kg ?? 0};bodyFat=plan.bodyFat != nil;resting=plan.restingCalories != nil}
            .onChange(of:plan){_,_ in result=nil;applied=false}
    }
    @ViewBuilder private func planResult(_ r:WeightResult) -> some View {
        Section(diary.t("الخطة المقترحة","Suggested plan")){
            NutritionView(value:r.goals,large:true)
            HStack{Text(diary.t("الثبات حاليًا","Current maintenance"));Spacer();Text("\(decimal(r.maintenance,0)) kcal")}
            HStack{Text(diary.t("الثبات عند الهدف","Maintenance at goal"));Spacer();Text("\(decimal(r.maintenanceAtGoal,0)) kcal")}
            Chart(r.points){p in LineMark(x:.value("Day",p.day),y:.value("Weight",p.kg)).lineStyle(StrokeStyle(lineWidth:2.5)).foregroundStyle(Theme.accent)}.chartYScale(domain:.automatic(includesZero:false)).frame(height:200)
            if r.lowCalories{Text(diary.t("السعرات منخفضة؛ زد المدة أو راجع مختصًا قبل اعتمادها.","Calories are low. Extend the timeline or seek professional review before applying.")).luqmaFont(.footnote).foregroundStyle(.orange)}
            Button(applied ? diary.t("تم اعتماد الخطة","Plan applied"):diary.t("اعتماد الخطة والأهداف","Apply plan and targets")){applied=diary.applyPlan(plan,r)}.buttonStyle(LuqmaPrimaryButtonStyle()).disabled(applied)
        }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
    }
    private func calculate(){if !bodyFat{plan.bodyFat=nil}else if plan.bodyFat==nil{plan.bodyFat=25};if !resting{plan.restingCalories=nil}else if plan.restingCalories==nil{plan.restingCalories=1600};calculating=true;let input=plan
        Task{do{let computed=try await Task.detached{try WeightModel.calculate(input)}.value;if plan==input{result=computed;applied=false}}catch{diary.report(error)};calculating=false}
    }
}
