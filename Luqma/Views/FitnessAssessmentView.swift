import SwiftUI

/// The original assessment's header, question hierarchy and selection surfaces.
/// Additional questions reuse those patterns; see Docs/FitnessAssessmentDesign.
struct FitnessAssessmentView:View {
    @EnvironmentObject private var diary:DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var answers=FitnessAnswers()
    @State private var page=0
    @State private var loaded=false
    @State private var validation:String?
    @State private var showingPlan=false
    @State private var reviewed=false
    @FocusState private var fieldFocused:Bool
    private let previewPage:Int?
    private let total=17

    init(previewPage:Int?=nil){
        #if DEBUG
        self.previewPage=previewPage
        #else
        self.previewPage=nil
        #endif
    }
    private var optional:Bool{[5,6,8,9,10,11,12,13,14].contains(page)}
    private var group:FitnessAssessmentStep {
        switch page{case 0,5,6:return .goal;case 1...4,15:return .basics;case 7...10:return .activity;case 11,12:return .recovery;case 13,14:return .nutrition;default:return .review}
    }
    var body:some View {
        NavigationStack {
            ScrollViewReader{scroll in
              ScrollView {
                VStack(spacing:32){
                    if previewPage != nil{Notice(text:diary.t("مثال للعرض فقط؛ لا تُحفظ هذه الإجابات في ملفك.","Display example only; these answers are not saved to your profile."))}
                    Text(question).luqmaFont(size:30,weight:.heavy,relativeTo:.title)
                        .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                        .frame(maxWidth:.infinity).accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("assessment.question")
                    pageContent
                    if let validation{SandowStateAlert(text:validation).accessibilityIdentifier("assessment.validation").id("assessment.validation")}
                }.padding(.horizontal,16).padding(.top,28).padding(.bottom,24)
              }.scrollDismissesKeyboard(.interactively).appBackground()
                .onChange(of:validation){_,message in
                    if message != nil{DispatchQueue.main.async{scroll.scrollTo("assessment.validation",anchor:.bottom)}}
                }
            }
                .safeAreaInset(edge:.top,spacing:0){header}
                .safeAreaInset(edge:.bottom,spacing:0){footer}
                .toolbar(.hidden,for:.navigationBar)
                .navigationDestination(isPresented:$showingPlan){FitnessPlanReviewView()}
                .onAppear{load()}
                .onChange(of:answers){_,_ in reviewed=false}
                .onDisappear{if !reviewed{_ = persist(reportInline:false)}}
        }.foregroundStyle(Theme.text)
    }
    private var header:some View {
        HStack(spacing:12){
            Button{back()}label:{Image("AssessmentBack").renderingMode(.template).frame(width:24,height:24)
                .scaleEffect(x:diary.language == .ar ? -1:1,y:1)
                .foregroundStyle(Theme.text).frame(width:48,height:48).background(Theme.surface,in:RoundedRectangle(cornerRadius:18))}
                .buttonStyle(.plain).accessibilityLabel(diary.t(page == 0 ? "إغلاق وحفظ المسودة":"السابق",page == 0 ? "Close and save draft":"Back"))
                .accessibilityIdentifier("assessment.back")
            Text(diary.t("تقييم اللياقة","Assessment")).luqmaFont(size:20,weight:.bold,relativeTo:.headline)
                .fixedSize(horizontal:false,vertical:true)
            Spacer(minLength:0)
            Text(diary.t("\(page+1) من \(total)","\(page+1) of \(total)"))
                .luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline).monospacedDigit()
                .foregroundStyle(Theme.secondaryAccentText).padding(.horizontal,12).padding(.vertical,8)
                .background(Theme.secondaryAccent.opacity(0.22),in:RoundedRectangle(cornerRadius:11))
                .accessibilityIdentifier("assessment.step")
        }.padding(.horizontal,16).padding(.top,16).padding(.bottom,8).background(Theme.background)
    }
    private var footer:some View {
        VStack(spacing:8){
            if optional{
                Button(diary.t("تخطّي الآن","Skip for now")){clearOptional();advance()}
                    .luqmaFont(.button).foregroundStyle(Theme.accentText).frame(maxWidth:.infinity,minHeight:44)
                    .background(Theme.card,in:RoundedRectangle(cornerRadius:16)).accessibilityIdentifier("assessment.skip")
            }
            Button{next()}label:{HStack(spacing:12){
                Text(diary.t(page == 16 ? "معاينة الخطة":"متابعة",page == 16 ? "Preview plan":"Continue"))
                Image("AssessmentNext").renderingMode(.template).frame(width:24,height:24)
                    .scaleEffect(x:diary.language == .ar ? -1:1,y:1)
            }}.buttonStyle(LuqmaPrimaryButtonStyle()).accessibilityIdentifier(page == 16 ? "assessment.review":"assessment.next")
            Button(diary.t("حفظ وإكمال لاحقًا","Save and finish later")){
                fieldFocused=false
                if persist(){_ = diary.deferFitnessAssessment();dismiss()}
            }.luqmaFont(.helper).foregroundStyle(Theme.muted).frame(minHeight:44).accessibilityIdentifier("assessment.saveDraft")
        }.padding(.horizontal,16).padding(.top,8).padding(.bottom,8).background(Theme.background)
    }
    @ViewBuilder private var pageContent:some View {
        switch page {
        case 0:choices(FitnessGoal.allCases,selection:$answers.goal,prefix:"goal",icons:["CFAGoalScale","CFAGoalDumbbell","CFAGoalDumbbell","CFAGoalScale","CFAGoalEndurance"])
        case 1:gender
        case 2:VStack(spacing:16){
            FitnessNumberField(title:diary.t("العمر بالسنوات","Age in years"),value:Binding(get:{answers.age.map(Double.init)},set:{answers.age=$0.flatMap{v in v.isFinite && (0...120).contains(v) && v.rounded()==v ? Int(v):nil}}),suffix:diary.t("سنة","years"),identifier:"assessment.age",integer:true,pickerStyle:.age,pickerRange:18...100)
            helper("يُستخدم العمر لحساب احتياج الطاقة. هذه الحاسبة للبالغين من 18 إلى 100 سنة.","Age is used in the energy equation. This estimator supports adults aged 18 to 100.")
        }
        case 3:measurement(diary.t("الطول","Height"),value:$answers.heightCM,suffix:diary.t("سم","cm"),id:"height",note:diary.t("أدخل طولك بالسنتيمتر. نطاق هذه الحاسبة 120–230 سم.","Enter your height in centimetres. This estimator supports 120–230 cm."))
        case 4:measurement(diary.t("الوزن الحالي","Current weight"),value:$answers.weightKG,suffix:diary.t("كجم","kg"),id:"weight",note:diary.t("نطاق هذه الحاسبة 35–300 كجم. يبقى سجل الأوزان السابق محفوظًا؛ هذه القيمة للحساب فقط.","This estimator supports 35–300 kg. Your weight history stays saved; this value is for the estimate only."))
        case 5:measurement(diary.t("وزن الهدف — اختياري","Target weight — optional"),value:$answers.targetWeightKG,suffix:diary.t("كجم","kg"),id:"target",note:diary.t("لن نحدد موعدًا مضمونًا للوصول إلى هذا الوزن.","This does not promise a date for reaching that weight."))
        case 6:VStack(spacing:16){choices(FitnessPace.allCases,selection:$answers.pace,prefix:"pace");helper("تدرّجية هي الافتراضية. يتغير تقدير الطاقة بخطوة صغيرة بحسب هدفك؛ راجع الأرقام قبل اعتمادها.","Gentle is the default. Your goal determines a small estimated energy adjustment; review the numbers before applying them.")}
        case 7:VStack(spacing:16){choices(FitnessActivity.allCases,selection:$answers.activity,prefix:"activity");FitnessNumberField(title:diary.t("متوسط الخطوات — اختياري","Average daily steps — optional"),value:intBinding(\.stepsPerDay),suffix:diary.t("خطوة","steps"),identifier:"assessment.steps",integer:true);helper("اختر نشاط يومك المعتاد. لا تتم مزامنة خطوات من جهاز أو ساعة.","Choose your usual daily activity. Steps are not synced from a device or watch.")}
        case 8:VStack(spacing:24){
            Image("CFAGymEquipment").resizable().scaledToFit().frame(maxWidth:343,maxHeight:280).blendMode(.lighten).accessibilityHidden(true)
            choices(FitnessExperience.allCases,selection:$answers.experience,prefix:"experience")
        }
        case 9:VStack(spacing:20){
            FitnessNumberField(title:diary.t("أيام التدريب في الأسبوع","Training days per week"),value:intBinding(\.trainingDays),suffix:diary.t("أيام","days"),identifier:"assessment.days",integer:true)
            trainingDays
            FitnessNumberField(title:diary.t("مدة الحصة","Session duration"),value:intBinding(\.sessionMinutes),suffix:diary.t("دقيقة","minutes"),identifier:"assessment.minutes",integer:true)
            choices(FitnessTrainingPlace.allCases,selection:$answers.trainingPlace,prefix:"place")
            helper("اختر ما تستطيع الالتزام به. الاقتراح النهائي يراعي خبرتك ولا ينشئ تمارين أو حجوزات.","Choose what fits your routine. The suggestion accounts for experience and does not create workouts or bookings.")
        }
        case 10:exercise
        case 11:VStack(spacing:20){
            FitnessNumberField(title:diary.t("متوسط ساعات النوم","Average sleep hours"),value:$answers.sleepHours,suffix:diary.t("ساعة","hours"),identifier:"assessment.sleepHours")
            sleepQuality
        }
        case 12:VStack(spacing:20){
            timeField(diary.t("موعد النوم — اختياري","Bedtime — optional"),value:$answers.bedtime,id:"bedtime")
            timeField(diary.t("موعد الاستيقاظ — اختياري","Wake time — optional"),value:$answers.wakeTime,id:"wakeTime")
            FitnessNumberField(title:diary.t("الإجهاد من 1 إلى 5 — اختياري","Stress from 1 to 5 — optional"),value:intBinding(\.stress),suffix:"",identifier:"assessment.stress",integer:true)
            helper("للمراجعة الشخصية؛ لا نستنتج تشخيصًا أو نغيّر السعرات بسبب هذه الإجابات.","For personal review; these answers do not diagnose a condition or change your calorie estimate.")
        }
        case 13:diet
        case 14:VStack(spacing:20){
            FitnessNumberField(title:diary.t("عدد الوجبات في اليوم","Meals per day"),value:intBinding(\.mealsPerDay),suffix:diary.t("وجبات","meals"),identifier:"assessment.meals",integer:true)
            notes(diary.t("أطعمة لا تفضلها — اختياري","Disliked foods — optional"),text:$answers.dislikedFoods,id:"dislikes")
            notes(diary.t("حساسيات غذائية — اختياري","Food allergies — optional"),text:$answers.allergies,id:"allergies")
            notes(diary.t("قيود أو تفضيلات أخرى — اختياري","Other restrictions or preferences — optional"),text:$answers.restrictions,id:"restrictions")
            helper("تُحفظ هذه الملاحظات للمراجعة. لا تُصفّى المنتجات أو الوصفات تلقائيًا بحسب الحساسية.","These notes are saved for review. Products and recipes are not automatically filtered for allergies.")
        }
        case 15:VStack(spacing:16){choices(FitnessSafety.allCases,selection:$answers.safety,prefix:"safety");helper("لا ينشئ هذا التقدير خطة للحمل أو الرضاعة أو الحالات والحمية الطبية الخاصة. تبقى أهدافك الحالية وتسجيل الطعام متاحين.","This estimator does not create plans for pregnancy, breastfeeding, medical conditions or therapeutic diets. Your existing goals and food logging remain available.")}
        default:review
        }
    }
    private var question:String {
        let ar=["ما هدفك الأساسي؟","ما الجنس المستخدم في الحساب؟","كم عمرك؟","كم طولك؟","كم وزنك الحالي؟","ما وزن الهدف؟","ما الوتيرة التي تناسبك؟","كيف يبدو نشاط يومك؟","ما خبرتك في التدريب؟","كيف تفضل تنظيم تدريبك؟","ما الأنشطة التي تفضلها؟","كيف هو نومك؟","ما روتين راحتك؟","ما نمط غذائك؟","ما تفضيلاتك الغذائية؟","هل يناسبك هذا التقدير العام؟","راجع إجاباتك"]
        let en=["What is your main goal?","Which sex should the equation use?","How old are you?","What is your height?","What is your current weight?","What is your target weight?","Which pace suits you?","How active is your usual day?","What is your training experience?","What fits your training routine?","Which activities do you enjoy?","How is your sleep?","What is your recovery routine?","What is your dietary preference?","What are your food preferences?","Is this general estimate suitable?","Review your answers"]
        return diary.t(ar[page],en[page])
    }
    private func choices<T:FitnessOption & Equatable>(_ options:[T],selection:Binding<T?>,prefix:String,icons:[String]=[])->some View {
        VStack(spacing:8){ForEach(Array(options.enumerated()),id:\.element.id){index,option in
            Button{selection.wrappedValue=option;validation=nil}label:{HStack(spacing:8){
                if icons.indices.contains(index){Image(icons[index]).renderingMode(.template).resizable().scaledToFit().frame(width:20,height:20).foregroundStyle(selection.wrappedValue == option ? Theme.text:Theme.muted).frame(width:28,height:28).accessibilityHidden(true)}
                Text(option.title(diary.language)).luqmaFont(.button).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                Image(selection.wrappedValue == option ? "AssessmentChecked":"AssessmentUnchecked").frame(width:24,height:24).accessibilityHidden(true)
            }.padding(16).frame(minHeight:56).background(selection.wrappedValue == option ? Theme.surface:Theme.card,in:RoundedRectangle(cornerRadius:19))
                .overlay{RoundedRectangle(cornerRadius:19).stroke(selection.wrappedValue == option ? Theme.controlBorder:Color.clear,lineWidth:2)}}
                .buttonStyle(.plain).accessibilityAddTraits(selection.wrappedValue == option ? .isSelected:[])
                .accessibilityIdentifier("assessment.\(prefix).\(option.rawValue)")
        }}
    }
    private var gender:some View {
        VStack(spacing:8){ForEach(FitnessSex.allCases){sex in
            Button{answers.sex=sex;validation=nil}label:{
                ZStack(alignment:.leading){
                    Theme.card
                    // The supplied 2669a71 card uses a 220×140 photo slot.
                    // HStack mirrors the slot in RTL; the portrait stays natural.
                    HStack(spacing:0){Spacer(minLength:0)
                        Image(sex == .male ? "CFAMaleAthlete":"CFAFemaleAthlete").resizable().scaledToFill()
                            .frame(width:220,height:140).clipped().blendMode(.lighten).allowsHitTesting(false).accessibilityHidden(true)
                    }.allowsHitTesting(false)
                    VStack(alignment:.leading,spacing:32){
                        Text(sex.title(diary.language)).luqmaFont(.button).padding(.horizontal,4).background(Theme.card.opacity(0.9),in:Capsule())
                        Image(answers.sex == sex ? "AssessmentChecked":"AssessmentUnchecked").frame(width:24,height:24).accessibilityHidden(true)
                    }.padding(16)
                }.frame(minHeight:140).clipShape(RoundedRectangle(cornerRadius:24))
                    .contentShape(RoundedRectangle(cornerRadius:24))
                    .overlay{RoundedRectangle(cornerRadius:24).stroke(answers.sex == sex ? Theme.accent:Color.clear,lineWidth:1.5)}
            }.buttonStyle(.plain).accessibilityLabel(sex.title(diary.language))
                .accessibilityIdentifier("assessment.sex.\(sex.rawValue)").accessibilityAddTraits(answers.sex == sex ? .isSelected:[])
        }
        helper("تحتاج معادلة الطاقة هذا الاختيار ولا يُستخدم لإثبات هويتك. لا نطلب اسمك أو تاريخ ميلادك الكامل.","The energy equation needs this input; it is not an identity check. We do not ask for your name or full date of birth.")}
    }
    private var diet:some View {
        LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8){ForEach(Array(FitnessDietPreference.allCases.enumerated()),id:\.element.id){index,option in
            Button{answers.diet=option}label:{VStack(alignment:.leading,spacing:24){
                Text(option.title(diary.language)).luqmaFont(.button).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,minHeight:44,alignment:.topLeading)
                HStack{dietIcon(option);Spacer();Image(answers.diet == option ? "AssessmentChecked":"AssessmentUnchecked").frame(width:24,height:24)}
            }.padding(16).background(answers.diet == option ? Theme.surface:Theme.card,in:RoundedRectangle(cornerRadius:24))
                .overlay{RoundedRectangle(cornerRadius:24).stroke(answers.diet == option ? Theme.controlBorder:Color.clear,lineWidth:2)}}
                .buttonStyle(.plain).accessibilityIdentifier("assessment.diet.\(option.rawValue)").accessibilityAddTraits(answers.diet == option ? .isSelected:[])
        }}
    }
    private var exercise:some View {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:100),spacing:8)],spacing:8){ForEach(Array(FitnessExercise.allCases.enumerated()),id:\.element.id){index,option in
            let selected=answers.exercise.contains(option)
            Button{if selected{answers.exercise.removeAll{$0 == option}}else{answers.exercise.append(option)}}label:{VStack(spacing:16){
                if option == .swimming{Image(systemName:"figure.pool.swim").font(.system(size:38,weight:.regular)).frame(width:48,height:48).accessibilityHidden(true)}
                else{Image(["CFAExWalking","CFAExWeightlift","CFAExCardio","CFAExBiking","CFAExYoga"][index]).renderingMode(.template).resizable().scaledToFit().frame(width:48,height:48).foregroundStyle(selected ? Theme.text:Theme.muted).accessibilityHidden(true)}
                Text(option.title(diary.language)).luqmaFont(.button).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,minHeight:44)
            }.padding(12).background(selected ? Theme.surface:Theme.card,in:RoundedRectangle(cornerRadius:24))
                .overlay{RoundedRectangle(cornerRadius:24).stroke(selected ? Theme.controlBorder:Color.clear,lineWidth:2)}}
                .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected:[]).accessibilityIdentifier("assessment.exercise.\(option.rawValue)")
        }}
    }
    private var sleepQuality:some View {
        VStack(spacing:8){ForEach(Array(FitnessSleepQuality.allCases.enumerated()),id:\.element.id){index,quality in
            Button{answers.sleepQuality=quality}label:{HStack(spacing:16){Image(["CFASleepBad","CFASleepNormal","CFASleepExcellent"][index]).renderingMode(.template).resizable().scaledToFit().frame(width:48,height:48).foregroundStyle(answers.sleepQuality == quality ? Theme.text:Theme.muted).accessibilityHidden(true)
                Text(quality.title(diary.language)).luqmaFont(size:18,weight:.semibold,relativeTo:.headline).frame(maxWidth:.infinity,alignment:.leading)
                Image(answers.sleepQuality == quality ? "AssessmentChecked":"AssessmentUnchecked").frame(width:24,height:24)
            }.padding(.horizontal,16).padding(.vertical,12).frame(minHeight:72)
                .background(answers.sleepQuality == quality ? Theme.surface:Theme.card,in:RoundedRectangle(cornerRadius:24))
                .overlay{RoundedRectangle(cornerRadius:24).stroke(answers.sleepQuality == quality ? Theme.controlBorder:Color.clear,lineWidth:2)}}
                .buttonStyle(.plain).accessibilityIdentifier("assessment.sleep.\(quality.rawValue)").accessibilityAddTraits(answers.sleepQuality == quality ? .isSelected:[])
        }}
    }
    private var review:some View {
        VStack(spacing:16){
            helper("راجع ما أدخلته. المعاينة التالية تقدّر الطاقة والماكروز والنشاط المقترح؛ لا تتغير أهدافك حتى تضغط اعتماد الخطة.","Review your answers. The next preview estimates energy, macros and suggested activity; your goals change only when you apply the plan.")
            reviewRow(diary.t("الهدف","Goal"),answers.goal?.title(diary.language) ?? "—",page:0)
            reviewRow(diary.t("الجنس المستخدم للحساب","Sex used for equation"),answers.sex?.title(diary.language) ?? "—",page:1)
            reviewRow(diary.t("العمر","Age"),answers.age.map{String($0)} ?? "—",page:2)
            reviewRow(diary.t("الطول","Height"),answers.heightCM.map{decimal($0,0)+" cm"} ?? "—",page:3)
            reviewRow(diary.t("الوزن","Weight"),answers.weightKG.map{decimal($0)+" kg"} ?? "—",page:4)
            reviewRow(diary.t("وزن الهدف","Target weight"),answers.targetWeightKG.map{decimal($0)+" kg"} ?? diary.t("غير محدد","Not set"),page:5)
            reviewRow(diary.t("النشاط","Activity"),answers.activity?.title(diary.language) ?? "—",page:7)
            reviewRow(diary.t("الوتيرة","Pace"),answers.pace?.title(diary.language) ?? diary.t("افتراضي: تدريجية","Default: gentle"),page:6)
            reviewRow(diary.t("التدريب","Training"),answers.experience?.title(diary.language) ?? diary.t("افتراضي: مبتدئ","Default: beginner"),page:8)
            reviewRow(diary.t("أيام التدريب ومدة الحصة","Training days and session length"),"\(answers.trainingDays.map(String.init) ?? "—") / \(answers.sessionMinutes.map(String.init) ?? "—") " + diary.t("دقيقة","min"),page:9)
            reviewRow(diary.t("المكان والأنشطة","Place and activities"),([answers.trainingPlace?.title(diary.language)].compactMap{$0}+answers.exercise.map{$0.title(diary.language)}).joined(separator:" · "),page:10)
            reviewRow(diary.t("النوم","Sleep"),answers.sleepHours.map{decimal($0)+diary.t(" ساعة"," hours")} ?? diary.t("اقتراح افتراضي","Default suggestion"),page:11)
            reviewRow(diary.t("مواعيد النوم والإجهاد","Sleep times and stress"),[answers.bedtime,answers.wakeTime,answers.stress.map(String.init)].compactMap{$0}.joined(separator:" · "),page:12)
            reviewRow(diary.t("الغذاء والحساسية","Diet and allergies"),answers.diet?.title(diary.language) ?? diary.t("غير محدد","Not set"),page:13)
            reviewRow(diary.t("الوجبات والتفضيلات","Meals and preferences"),([answers.mealsPerDay.map{String($0)+diary.t(" وجبات"," meals")}].compactMap{$0}+[answers.dislikedFoods,answers.allergies,answers.restrictions].filter{!$0.isEmpty}).joined(separator:" · "),page:14)
            reviewRow(diary.t("الملاءمة","Suitability"),answers.safety?.title(diary.language) ?? "—",page:15)
            helper("تُحفظ الإجابات محليًا داخل ملف السجل المحمي على الآيفون. يمكنك تعديلها أو حذف ملف اللياقة من الإعدادات؛ النسخ الاحتياطية المصدّرة تتضمنها.","Answers are stored locally in the protected diary file on iPhone. Edit or delete your fitness profile in Settings; exported backups include this information.")
        }
    }
    private func reviewRow(_ title:String,_ value:String,page target:Int)->some View {
        Button{page=target;validation=nil;_ = persist()}label:{HStack(alignment:.top,spacing:16){VStack(alignment:.leading,spacing:6){Text(title).luqmaFont(.helper).foregroundStyle(Theme.muted);Text(value).luqmaFont(.button).foregroundStyle(Theme.text)};Spacer();Text(diary.t("تعديل","Edit")).luqmaFont(.helper).foregroundStyle(Theme.link)}}.buttonStyle(.plain).luqmaCard()
    }
    @ViewBuilder private func dietIcon(_ option:FitnessDietPreference)->some View {
        switch option {
        case .vegan,.vegetarian:Image("CFADietVegan").renderingMode(.template).resizable().scaledToFit().frame(width:24,height:24).accessibilityHidden(true)
        case .balanced:Image("CFADietCarbo").renderingMode(.template).resizable().scaledToFit().frame(width:24,height:24).accessibilityHidden(true)
        case .pescatarian:Image(systemName:"fish.fill").font(.system(size:23)).frame(width:24,height:24).accessibilityHidden(true)
        case .halal:Image("CFADietTraditional").renderingMode(.template).resizable().scaledToFit().frame(width:24,height:24).accessibilityHidden(true)
        }
    }
    private func measurement(_ title:String,value:Binding<Double?>,suffix:String,id:String,note:String)->some View {
        VStack(spacing:20){FitnessNumberField(title:title,value:value,suffix:suffix,identifier:"assessment.\(id)",pickerStyle:id == "height" ? .height:.weight,pickerRange:id == "height" ? 120...230:35...300);Text(note).luqmaFont(.helper).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true)}
    }
    private var trainingDays:some View {
        LazyVGrid(columns:[GridItem(.adaptive(minimum:44),spacing:8)],spacing:8){ForEach(0...7,id:\.self){day in
            Button{answers.trainingDays=day;validation=nil}label:{Text(String(day)).luqmaFont(size:20,weight:.heavy,relativeTo:.title3).monospacedDigit().frame(maxWidth:.infinity,minHeight:56)
                .foregroundStyle(answers.trainingDays == day ? Theme.onSecondaryAccent:Theme.muted)
                .background(answers.trainingDays == day ? Theme.secondaryAccent:Theme.card,in:RoundedRectangle(cornerRadius:18))}
                .buttonStyle(.plain).accessibilityLabel(diary.t("\(day) أيام أسبوعيًا","\(day) days per week")).accessibilityIdentifier("assessment.days.choice.\(day)")
                .accessibilityAddTraits(answers.trainingDays == day ? .isSelected:[])
        }}
    }
    private func helper(_ ar:String,_ en:String)->some View {Text(diary.t(ar,en)).luqmaFont(.helper).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)}
    private func notes(_ title:String,text:Binding<String>,id:String)->some View {
        VStack(alignment:.leading,spacing:8){Text(title).luqmaFont(.label);TextField(title,text:text,prompt:Text(title).foregroundColor(Theme.muted),axis:.vertical).lineLimit(2...5).padding(16).background(Theme.card,in:RoundedRectangle(cornerRadius:19)).accessibilityIdentifier("assessment.\(id)")}
    }
    private func timeField(_ title:String,value:Binding<String?>,id:String)->some View {
        VStack(alignment:.leading,spacing:8){Text(title).luqmaFont(.label);TextField("HH:mm",text:Binding(get:{value.wrappedValue ?? ""},set:{value.wrappedValue=$0.isEmpty ? nil:DisplayFormat.westernDigits($0)}),prompt:Text("HH:mm").foregroundColor(Theme.muted)).keyboardType(.numbersAndPunctuation).environment(\.layoutDirection,.leftToRight).padding(16).background(Theme.card,in:RoundedRectangle(cornerRadius:19)).accessibilityIdentifier("assessment.\(id)")}
    }
    private func intBinding(_ key:WritableKeyPath<FitnessAnswers,Int?>)->Binding<Double?> {
        Binding(get:{answers[keyPath:key].map(Double.init)},set:{answers[keyPath:key]=$0.flatMap{v in v.isFinite && (0...100000).contains(v) && v.rounded()==v ? Int(v):nil}})
    }
    private func load(){
        guard !loaded else{return};loaded=true
        #if DEBUG
        if let previewPage{answers=FitnessPreviewData.answers;page=min(16,max(0,previewPage));return}
        #endif
        if let draft=diary.state.fitnessDraft{answers=draft.answers;page=min(16,max(0,draft.pageIndex ?? (draft.step == .review ? 16:0)))}
        else if let profile=diary.state.fitnessProfile{answers=profile.answers}
    }
    @discardableResult private func persist(reportInline:Bool=true)->Bool {
        guard previewPage == nil,loaded,!reviewed else{return true}
        let saved=diary.saveFitnessDraft(FitnessAssessmentDraft(answers:answers,step:group,updatedDay:DayKey.today,pageIndex:page))
        if !saved,reportInline{showOperationError("تعذّر حفظ الإجابات. حاول مرة أخرى.","Could not save your answers. Try again.")}
        return saved
    }
    private func showOperationError(_ ar:String,_ en:String){
        validation=diary.error ?? diary.t(ar,en)
        // This form owns the visible error; do not also request the root alert.
        diary.error=nil
    }
    private func back(){
        if page>0{page-=1;validation=nil;_ = persist()}
        else if persist(){dismiss()}
    }
    private func next(){
        fieldFocused=false;validation=nil
        let valid:Bool
        switch page {
        case 0:valid=answers.goal != nil
        case 1:valid=answers.sex != nil
        case 2:valid=answers.age.map{(18...100).contains($0)} ?? false
        case 3:valid=answers.heightCM.map{(120...230).contains($0)} ?? false
        case 4:valid=answers.weightKG.map{(35...300).contains($0)} ?? false
        case 7:valid=answers.activity != nil
        case 15:valid=answers.safety != nil
        default:valid=true
        }
        guard valid else{validation=diary.t("أكمل الاختيار أو أدخل قيمة ضمن النطاق الموضح قبل المتابعة.","Complete the selection or enter a value within the stated range before continuing.");return}
        do{try answers.validate()}catch{validation=(error as? AppError)?.message(diary.language) ?? error.localizedDescription;return}
        if page == 16{
            if previewPage == nil{
                if diary.previewFitnessPlan(answers){reviewed=true;showingPlan=true}
                else{showOperationError("تعذّرت معاينة الخطة. راجع الإجابات وحاول مرة أخرى.","Could not preview the plan. Review your answers and try again.")}
            }
        }else{advance()}
    }
    private func advance(){page=min(total-1,page+1);validation=nil;_ = persist()}
    private func clearOptional(){
        switch page{case 5:answers.targetWeightKG=nil;case 6:answers.pace=nil;case 8:answers.experience=nil;case 9:answers.trainingDays=nil;answers.sessionMinutes=nil;answers.trainingPlace=nil;case 10:answers.exercise=[];case 11:answers.sleepHours=nil;answers.sleepQuality=nil;case 12:answers.bedtime=nil;answers.wakeTime=nil;answers.stress=nil;case 13:answers.diet=nil;case 14:answers.mealsPerDay=nil;answers.dislikedFoods="";answers.allergies="";answers.restrictions="";default:break}
    }
}

private struct FitnessNumberField:View {
    let title:String
    @Binding var value:Double?
    var suffix:String
    var identifier:String
    var integer=false
    var pickerStyle:AssessmentNumberPicker.Style?=nil
    var pickerRange:ClosedRange<Double> = 0...300
    @State private var text=""
    @State private var pickerEditing=false
    @FocusState private var focused:Bool
    private var isEditing:Bool{pickerStyle == nil ? focused:pickerEditing}
    var body:some View {
        Group{if let pickerStyle{
            AssessmentNumberPicker(title:title,text:Binding(get:{text},set:{new in
                text=new
                value=TextSearch.number(new).flatMap{$0.isFinite ? $0:nil}
            }),unit:suffix,range:pickerRange,step:integer ? 1:0.5,identifier:identifier,style:pickerStyle,onEditingChanged:{pickerEditing=$0})
        }else{VStack(alignment:.leading,spacing:12){
            Text(title).luqmaFont(.label).fixedSize(horizontal:false,vertical:true)
            HStack(alignment:.firstTextBaseline,spacing:12){
                TextField("—",text:$text,prompt:Text("—").foregroundColor(Theme.muted)).keyboardType(integer ? .numberPad:.decimalPad).focused($focused)
                    .luqmaFont(size:40,weight:.bold,relativeTo:.largeTitle).monospacedDigit()
                    .environment(\.layoutDirection,.leftToRight).accessibilityLabel(title).accessibilityIdentifier(identifier)
                Text(suffix).luqmaFont(.label).foregroundStyle(Theme.muted)
            }.padding(20).background(Theme.card,in:RoundedRectangle(cornerRadius:24))
        }}}.onAppear{text=value.map{decimal($0,integer ? 0:1)} ?? ""}
            .onChange(of:text){_,new in if focused && pickerStyle == nil{value=TextSearch.number(new).flatMap{$0.isFinite ? $0:nil}}}
            .onChange(of:focused){_,active in if !active{text=value.map{decimal($0,integer ? 0:1)} ?? ""}}
            .onChange(of:pickerEditing){_,active in if !active{text=value.map{decimal($0,integer ? 0:1)} ?? ""}}
            .onChange(of:value){_,new in if !isEditing{text=new.map{decimal($0,integer ? 0:1)} ?? ""}}
    }
}

#if DEBUG
enum FitnessPreviewData {
    static var answers:FitnessAnswers {
        var result=FitnessAnswers()
        result.sex = .female;result.age=30;result.heightCM=168;result.weightKG=74;result.targetWeightKG=68
        result.goal = .fatLoss;result.pace = .gentle;result.activity = .light;result.safety = .generalAdult
        result.experience = .beginner;result.trainingDays=3;result.sessionMinutes=30;result.trainingPlace = .home
        result.exercise=[.walking,.strength];result.stepsPerDay=5000;result.sleepHours=7.5;result.sleepQuality = .fair
        result.bedtime="23:00";result.wakeTime="06:30";result.diet = .balanced;result.mealsPerDay=3
        return result
    }
    static var snapshot:DiarySnapshot {
        var result=DiarySnapshot()
        try? FitnessAssessmentState.preview(answers,in:&result)
        return result
    }
}
#endif
