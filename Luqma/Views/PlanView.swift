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
    @State private var initialized=false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private func dateBinding(_ key:WritableKeyPath<WeightPlan,String>) -> Binding<Date> {Binding(get:{DayKey.localDate(plan[keyPath:key]) ?? Date()},set:{plan[keyPath:key]=DayKey.string($0)})}
    var body:some View {
        ScrollViewReader{proxy in ScrollView{VStack(alignment:.leading,spacing:LuqmaReviewStyle.gap){
            LuqmaReviewSection(title:diary.t("المعلومات الشخصية","Personal information")){
                Text(diary.t("الجنس المستخدم في المعادلة","Sex used by the model")).luqmaFont(.caption).foregroundStyle(Theme.muted)
                LuqmaReviewSegments(options:["male","female"],selection:$plan.sex){$0 == "male" ? diary.t("ذكر","Male"):diary.t("أنثى","Female")}
                LuqmaReviewNumber(title:diary.t("العمر","Age"),value:$plan.age)
            }
            LuqmaReviewSection(title:diary.t("القياسات الحالية","Current measurements")){
                LuqmaReviewNumber(title:diary.t("الطول","Height"),value:$plan.height,suffix:diary.t("سم","cm"))
                LuqmaReviewNumber(title:diary.t("الوزن الحالي","Current weight"),value:$plan.weight,suffix:diary.t("كجم","kg"))
            }
            LuqmaReviewSection(title:diary.t("هدف الوزن","Weight objective")){
                LuqmaReviewNumber(title:diary.t("وزن الهدف","Goal weight"),value:$plan.targetWeight,suffix:diary.t("كجم","kg"))
            }
            LuqmaReviewSection(title:diary.t("مواعيد الخطة","Plan dates")){
                DatePicker(diary.t("بداية الخطة","Start date"),selection:dateBinding(\.startDay),displayedComponents:.date).datePickerStyle(.compact)
                DatePicker(diary.t("موعد الهدف","Goal date"),selection:dateBinding(\.targetDay),displayedComponents:.date).datePickerStyle(.compact)
            }
            LuqmaReviewSection(title:diary.t("النشاط البدني","Physical activity")){
                LuqmaReviewNumber(title:diary.t("معامل النشاط · PAL","Activity factor · PAL"),value:$plan.pal)
                // Presets are suggestions, never substituted for a saved custom PAL.
                LuqmaReviewSegments(options:[1.4,1.6,1.8,2.2],selection:$plan.pal){value in
                    switch value{case 1.4:return diary.t("قليل","Low");case 1.6:return diary.t("خفيف","Light");case 1.8:return diary.t("متوسط","Moderate");default:return diary.t("مرتفع","High")}
                }
                Notice(text:diary.t("يشمل معامل النشاط يومك كاملًا. يمكنك اختيار مستوى تقريبي أو إدخال معامل مخصص.","Includes your whole day. Choose an approximate level or enter a custom factor."))
                HStack{Text(diary.t("تغيير النشاط","Activity change")).luqmaFont(.subheadline);Spacer();Text("\(decimal(plan.activityChange,0))%")
                    .luqmaFont(.headline).foregroundStyle(Theme.accentText).monospacedDigit().luqmaNumericMotion(value:plan.activityChange)}
                Slider(value:$plan.activityChange,in:-50...100,step:5).tint(Theme.accent)
                    .accessibilityLabel(diary.t("تغيير النشاط","Activity change"))
                    .accessibilityValue("\(decimal(plan.activityChange,0))%")
            }
            VStack(alignment:.leading,spacing:12){DisclosureGroup(diary.t("قياسات متقدمة (اختياري)","Advanced measurements (optional)"),isExpanded:$advanced){
                Toggle(diary.t("لدي نسبة دهون مقاسة","Measured body fat"),isOn:$bodyFat)
                if bodyFat{LuqmaReviewNumber(title:diary.t("نسبة الدهون","Body fat"),value:Binding(get:{plan.bodyFat ?? 0},set:{plan.bodyFat=$0}),suffix:"%")}
                Toggle(diary.t("لدي معدل حرق راحة مقاس","Measured resting energy"),isOn:$resting)
                if resting{LuqmaReviewNumber(title:diary.t("حرق الراحة","Resting energy"),value:Binding(get:{plan.restingCalories ?? 0},set:{plan.restingCalories=$0}),suffix:"kcal")}
                LuqmaReviewNumber(title:diary.t("الكارب في نموذج الوزن","Carbs in weight model"),value:$plan.carbPercent,suffix:"%")
                LuqmaReviewNumber(title:diary.t("صوديوم البداية","Baseline sodium"),value:$plan.sodium,suffix:"mg")
                Notice(text:diary.t("إذا كانت القياسات غير متوفرة، تُقدَّر حسب معادلات النموذج. نسبة الكارب هنا تخص محاكاة الوزن؛ أهداف الماكروز تُعدّل من إعداداتها.","Without measurements, the model estimates these values. This carb percentage belongs to the weight simulation; macro targets have their own editor."))
            };Toggle(diary.t("حمل، رضاعة أو خطة طبية خاصة","Pregnancy, breastfeeding or medical diet"),isOn:$plan.specialCase)}.luqmaCard()
            if let result{planResult(result).id("weight.plan.result").luqmaMotionTransition()}
            DisclosureGroup(diary.t("المنهج العلمي","Scientific model")){
                Notice(text:diary.t("تطبيق مستقل لمعادلات Hall المستخدمة في NIDDK Body Weight Planner، يشمل تغير استهلاك الطاقة والدهون والكتلة الخالية من الدهون والسوائل. مطابق حسابيًا ضمن اختبارات مرجعية، وليس ضمانًا لمسار وزن الفرد. للبالغين فقط.","Independent implementation of the Hall equations used by NIDDK Body Weight Planner, including changing energy expenditure, fat, lean mass and fluid. Checked against reference scenarios, not a guarantee of individual weight change. Adults only."))
                Link("NIDDK Body Weight Planner",destination:URL(string:"https://www.niddk.nih.gov/bwp")!)
                Link("Hall et al. • Lancet 2011",destination:URL(string:"https://pmc.ncbi.nlm.nih.gov/articles/PMC3880593/")!)
            }.luqmaFont(.subheadline).luqmaCard()
        }.padding(LuqmaReviewStyle.margin)}.appBackground().luqmaReviewKeyboard()
            .sandowNavigation(diary.t("خطة الوزن","Weight plan"),backLabel:diary.t("رجوع","Back"))
            .safeAreaInset(edge:.bottom,spacing:0){
                Button{if let result{applied=diary.applyPlan(plan,result)}else{calculate()}}label:{
                    HStack(spacing:8){
                        if calculating{ProgressView().tint(Theme.onAccent)}
                        Text(applied ? diary.t("تم اعتماد الخطة","Plan applied"):calculating ? diary.t("جارٍ الحساب…","Calculating…"):result == nil ? diary.t("حساب الخطة","Calculate plan"):diary.t("اعتماد الخطة والأهداف","Apply plan and targets"))
                    }
                }.buttonStyle(LuqmaPrimaryButtonStyle()).disabled(calculating || applied)
                    .padding(16).background(Theme.background)
            }
            .luqmaMotion(.content,value:result != nil)
            .luqmaFeedback(.light,trigger:calculating){_,value in value}
            .luqmaFeedback(.success,trigger:applied){_,didApply in didApply}
            .onAppear{guard !initialized else{return};initialized=true;if let saved=diary.state.weightPlan{plan=saved}else{plan.sex="";plan.weight=diary.state.weights.last?.kg ?? 0};bodyFat=plan.bodyFat != nil;resting=plan.restingCalories != nil}
            .onChange(of:plan){_,_ in result=nil;applied=false}
            .onChange(of:bodyFat){_,_ in result=nil;applied=false}
            .onChange(of:resting){_,_ in result=nil;applied=false}
            .onChange(of:result != nil){_,available in
                if available{withAnimation(LuqmaMotion.animation(.content,reduceMotion:reduceMotion)){proxy.scrollTo("weight.plan.result",anchor:.top)}}
            }
        }
    }
    @ViewBuilder private func planResult(_ r:WeightResult) -> some View {
        LuqmaReviewSection(title:diary.t("الخطة المقترحة","Suggested plan")){
            LuqmaReviewNutrition(value:r.goals)
            HStack{Text(diary.t("الثبات حاليًا","Current maintenance"));Spacer();Text("\(decimal(r.maintenance,0)) kcal").luqmaNumericMotion(value:r.maintenance)}
            HStack{Text(diary.t("الثبات عند الهدف","Maintenance at goal"));Spacer();Text("\(decimal(r.maintenanceAtGoal,0)) kcal").luqmaNumericMotion(value:r.maintenanceAtGoal)}
            Chart(r.points){p in LineMark(x:.value("Day",p.day),y:.value("Weight",p.kg)).lineStyle(StrokeStyle(lineWidth:2.5)).foregroundStyle(Theme.accent)}.chartYScale(domain:.automatic(includesZero:false)).frame(height:200)
            if r.lowCalories{Text(diary.t("السعرات منخفضة؛ زد المدة أو راجع مختصًا قبل اعتمادها.","Calories are low. Extend the timeline or seek professional review before applying.")).luqmaFont(.footnote).foregroundStyle(Theme.warning)}
        }
    }

    private func calculate(){if !bodyFat{plan.bodyFat=nil}else if plan.bodyFat==nil{plan.bodyFat=0};if !resting{plan.restingCalories=nil}else if plan.restingCalories==nil{plan.restingCalories=0};calculating=true;let input=plan
        Task{do{let computed=try await Task.detached{try WeightModel.calculate(input)}.value;if plan==input{result=computed;applied=false}}catch{diary.report(error)};calculating=false}
    }
}
