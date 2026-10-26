import SwiftUI
import UIKit

/// Approved assessment visuals over the existing eleven-page, saved flow.
struct FitnessAssessmentView: View {
    @EnvironmentObject private var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var answers = FitnessAnswers()
    @State private var inputs: [String: String] = [:]
    @State private var page: FitnessAssessmentPage = .goal
    @State private var loaded = false
    @State private var validation: String?
    @State private var showingPlan = false
    @State private var reviewed = false
    @State private var actionBusy = false
    @State private var leaving = false
    @State private var pickerInteraction = false
    private let previewPage: Int?

    init(previewPage: Int? = nil) {
        #if DEBUG
        self.previewPage = previewPage
        #else
        self.previewPage = nil
        #endif
    }
    private var optional: Bool { [.targetPace, .training, .details].contains(page) }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
              ScrollViewReader { scroll in
                ScrollView {
                    VStack(spacing: 0) {
                        if previewPage != nil && !ProcessInfo.processInfo.arguments.contains("-loqma-approved-capture") { Notice(text: diary.t("مثال للعرض فقط؛ لا تُحفظ هذه الإجابات في ملفك.", "Display example only; these answers are not saved to your profile.")) }
                        Text(question).luqmaFont(size: page == .targetPace || page == .height ? 28 : 30, weight: .heavy, relativeTo: .largeTitle)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("assessment.question").id("assessment.top")
                            .padding(.bottom, page == .goal ? 34 : 28)
                        pageContent.id(page.rawValue).disabled(actionBusy)
                            .frame(minHeight: max(0, geometry.size.height - 140), alignment: .top)
                        if let validation {
                            SandowStateAlert(text: validation).accessibilityIdentifier("assessment.validation")
                                // Include clearance in the scroll target. The
                                // alert's half-point stroke extends its AX
                                // frame beyond the layout rect at the footer.
                                .padding(.bottom,12).id("assessment.validation")
                        }
                    }.padding(.horizontal, 16).padding(.top, 28).padding(.bottom, 20)
                }.scrollDismissesKeyboard(.interactively).scrollDisabled(pickerInteraction).appBackground()
                    .accessibilityIdentifier("assessment.form")
                    .onChange(of: validation) { _, message in
                        if message != nil { DispatchQueue.main.async { scroll.scrollTo("assessment.validation", anchor: .bottom) } }
                    }
                    .onChange(of: page) { _, _ in pickerInteraction = false; scroll.scrollTo("assessment.top", anchor: .top) }
              }
            }
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            .toolbar(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(diary.t("تم", "Done")) { endEditing() }
                        .luqmaFont(.button).foregroundStyle(Theme.accentText)
                        .accessibilityIdentifier("assessment.keyboardDone")
                }
            }
            .navigationDestination(isPresented: $showingPlan) { FitnessPlanReviewView() }
            .onAppear { load() }
            .onChange(of: answers) { _, _ in reviewed = false }
            .onDisappear {
                // Interactive dismissal still saves. Explicit exits already saved
                // transactionally and do not issue another full diary write.
                guard !leaving, !reviewed, loaded, previewPage == nil else { return }
                let snapshot = draft
                Task { await diary.saveFitnessDraftInBackground(snapshot) }
            }
        }.foregroundStyle(Color.white).interactiveDismissDisabled(actionBusy)
    }
    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { perform { await back() } } label: {
                    CFACrescentChevron().stroke(Color.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                        .frame(width: 10, height: 18).scaleEffect(x: diary.language == .ar ? 1 : -1, y: 1)
                        .frame(width: 48, height: 48)
                        .background(Color(hex: 0x393C43), in: RoundedRectangle(cornerRadius: 18))
                }.buttonStyle(.plain).disabled(actionBusy)
                    .accessibilityLabel(diary.t(page == .goal ? "إغلاق وحفظ المسودة" : "السابق", page == .goal ? "Close and save draft" : "Back"))
                    .accessibilityIdentifier("assessment.back")
                Text(diary.t("تقييم اللياقة", "Assessment")).luqmaFont(size: 20, weight: .bold, relativeTo: .headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Text(diary.t("\(page.index + 1) من \(FitnessAssessmentPage.allCases.count)", "\(page.index + 1) of \(FitnessAssessmentPage.allCases.count)"))
                    .luqmaFont(size: 14, weight: .semibold, relativeTo: .subheadline).monospacedDigit()
                    .foregroundStyle(Color(hex: 0x2563EB)).padding(.horizontal, 12).frame(height: 32)
                    .background(Color(hex: 0x172554), in: RoundedRectangle(cornerRadius: 11))
                    .accessibilityIdentifier("assessment.step")
            }
        }.padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8).background(Color(hex: 0x111214))
    }
    private var footer: some View {
        VStack(spacing: 8) {
            if optional {
                Button(diary.t("تخطّي الآن", "Skip for now")) { perform { await next() } }
                    .luqmaFont(.button).foregroundStyle(Theme.accentText).frame(maxWidth: .infinity, minHeight: 44)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16)).accessibilityIdentifier("assessment.skip")
            }
            Button { perform { await next() } } label: {
                HStack(spacing: 12) {
                    if actionBusy { ProgressView().tint(Theme.onAccent).accessibilityLabel(diary.t("جارٍ الحفظ", "Saving")) }
                    Text(diary.t(page == .review ? "معاينة الخطة" : "متابعة", page == .review ? "Preview plan" : "Continue"))
                    Image(systemName: diary.language == .ar ? "arrow.left" : "arrow.right").font(.system(size: 16, weight: .bold))
                }
            }.buttonStyle(ApprovedAssessmentButtonStyle()).accessibilityIdentifier(page == .review ? "assessment.review" : "assessment.next")
            Button(diary.t("حفظ وإكمال لاحقًا", "Save and finish later")) {
                perform {
                    endEditing()
                    if await persist(deferAssessment: true) { leaving = true; dismiss() }
                }
            }.luqmaFont(.helper).foregroundStyle(Theme.muted).frame(minHeight: 44).accessibilityIdentifier("assessment.saveDraft")
        }.disabled(actionBusy).padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12).background(Color(hex: 0x111214))
    }
    @ViewBuilder private var pageContent: some View {
        switch page {
        case .goal:
            choices(FitnessGoal.approvedPresentationOrder, selection: $answers.goal, prefix: "goal", icons: FitnessGoal.approvedPresentationOrder.map(\.approvedIconName))
        case .suitability:
            VStack(spacing: 16) {
                choices(FitnessSafety.allCases, selection: $answers.safety, prefix: "safety")
                helper("لا ينشئ هذا التقدير خطة للحمل أو الرضاعة أو الحالات والحمية الطبية الخاصة. تبقى أهدافك الحالية وتسجيل الطعام متاحين.", "This estimator does not create plans for pregnancy, breastfeeding, medical conditions or therapeutic diets. Your existing goals and food logging remain available.")
            }
        case .sex: gender
        case .age:
            VStack(spacing: 16) {
                number(.age, title: diary.t("العمر بالسنوات", "Age in years"), suffix: diary.t("سنة", "years"), id: "age", style: .age)
            }
        case .height:
            VStack(spacing: 16) {
                number(.height, title: diary.t("الطول", "Height"), suffix: diary.t("سم", "cm"), id: "height", style: .height)
            }
        case .weight:
            VStack(spacing: 16) {
                number(.weight, title: diary.t("الوزن الحالي", "Current weight"), suffix: diary.t("كجم", "kg"), id: "weight", style: .weight)
            }
        case .targetPace:
            targetAndPace
        case .activity:
            activityArc
        case .training:
            VStack(spacing: 20) {
                Text(diary.t("ما خبرتك في التدريب؟", "What is your training experience?")).luqmaFont(.label)
                choices(FitnessExperience.allCases, selection: $answers.experience, prefix: "experience")
                number(.trainingDays, title: diary.t("أيام التدريب في الأسبوع — اختياري", "Training days per week — optional"), suffix: diary.t("أيام", "days"), id: "days")
                number(.sessionMinutes, title: diary.t("مدة الحصة — اختياري", "Session duration — optional"), suffix: diary.t("دقيقة", "minutes"), id: "minutes")
                helper("تُستخدم هذه الإجابات لاقتراح نشاط يناسب وقتك وخبرتك. يمكنك تركها فارغة.", "These answers help suggest activity that fits your time and experience. You may leave them blank.")
            }
        case .details:
            VStack(spacing: 20) {
                number(.sleepHours, title: diary.t("متوسط ساعات النوم — اختياري", "Average sleep hours — optional"), suffix: diary.t("ساعة", "hours"), id: "sleepHours")
                helper("تساعد ساعات النوم في اقتراح وقت الراحة؛ لا تغيّر تقدير السعرات.", "Sleep hours help suggest rest time; they do not change the calorie estimate.")
                DisclosureGroup(diary.t("تفضيلات غذائية للمراجعة — اختياري", "Food preferences for reference — optional")) {
                    VStack(spacing: 20) {
                        diet
                        number(.meals, title: diary.t("عدد الوجبات", "Meals per day"), suffix: diary.t("وجبات", "meals"), id: "meals")
                        notes(diary.t("أطعمة لا تفضلها", "Disliked foods"), text: $answers.dislikedFoods, id: "dislikes")
                        notes(diary.t("حساسيات غذائية", "Food allergies"), text: $answers.allergies, id: "allergies")
                        notes(diary.t("قيود أو تفضيلات أخرى", "Other restrictions or preferences"), text: $answers.restrictions, id: "restrictions")
                        helper("ملاحظات محفوظة للرجوع إليها. لا تُصفّى المنتجات والوصفات تلقائيًا بحسبها.", "Saved notes for reference. Products and recipes are not automatically filtered by them.")
                    }.padding(.top, 16)
                }.luqmaFont(.label).tint(Theme.secondaryAccent)
                    .accessibilityElement(children:.contain).accessibilityIdentifier("assessment.foodPreferences")
            }
        case .review: review
        }
    }
    private var question: String {
        let ar = ["ما هو هدفك\nالرياضي الرئيسي؟", "هل يناسبك هذا التقدير؟", "ما الجنس المستخدم في\nالحساب؟", "كم عمرك؟", "ما هو طولك الحالي؟", "ما هو وزنك الحالي؟", "هل تريد تخصيص هدف الوزن؟", "كيف تقيّم مستوى\nنشاطك الحالي؟", "ما التدريب الذي يناسبك؟", "هل تريد إضافة تفاصيل؟", "راجع إجاباتك"]
        let en = ["What’s your fitness\ngoal/target?", "Is this estimate suitable?", "Which sex should the\nequation use?", "What is your age?", "What is your height?", "What is your weight?", "Would you like to customize your target weight?", "How would you rate\nyour daily activity?", "What training fits your routine?", "Would you like to add details?", "Review your answers"]
        return diary.t(ar[page.index], en[page.index])
    }
    private func choices<T:FitnessOption & Equatable>(_ options:[T],selection:Binding<T?>,prefix:String,icons:[String]=[])->some View {
        VStack(spacing:8){ForEach(Array(options.enumerated()),id:\.element.id){index,option in
            Button{selection.wrappedValue=option;validation=nil}label:{HStack(spacing:12){
                if icons.indices.contains(index){Image(icons[index]).renderingMode(.template).resizable().scaledToFit().frame(width:20,height:20).foregroundStyle(selection.wrappedValue == option ? Theme.text:Theme.muted).frame(width:28,height:28).accessibilityHidden(true)}
                Text(option.title(diary.language)).luqmaFont(size:16,weight:.semibold,relativeTo:.body).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                CFARadioIndicator(isSelected: selection.wrappedValue == option)
            }.padding(.horizontal,18).padding(.vertical, prefix == "goal" ? 0 : 12).frame(minHeight:56)
                .background(selection.wrappedValue == option ? Color(hex:0x393C43):Color(hex:0x24262B),in:RoundedRectangle(cornerRadius:18))
                .overlay{RoundedRectangle(cornerRadius:20).stroke(selection.wrappedValue == option ? Color(hex:0x81858D).opacity(0.28):Color.clear,lineWidth:4).padding(-2)}}
                .buttonStyle(.plain).accessibilityAddTraits(selection.wrappedValue == option ? .isSelected:[])
                .accessibilityIdentifier("assessment.\(prefix).\(option.rawValue)")
        }}
    }
    private var gender:some View {
        VStack(spacing:12){ForEach(FitnessSex.allCases){sex in
            Button{answers.sex=sex;validation=nil}label:{
                ZStack(alignment:.leading){
                    Color(hex:0x24262B)
                    HStack(spacing:0){Spacer(minLength:0)
                        Image(sex == .male ? "CFAMaleFitnessIllustration":"CFAFemaleFitnessIllustration").resizable().scaledToFill()
                            .frame(width:220,height:140).scaleEffect(x:diary.language == .ar ? -1:1,y:1).clipped()
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }.allowsHitTesting(false)
                    VStack(alignment:.leading){
                        HStack(spacing:8){
                            Text(sex == .male ? "♂":"♀").font(.system(size:18,weight:.bold))
                            Text(sex.title(diary.language)).luqmaFont(size:16,weight:.bold,relativeTo:.body)
                        }
                        Spacer()
                        CFARadioIndicator(isSelected:answers.sex == sex)
                    }.padding(18)
                }.frame(height:140).clipShape(RoundedRectangle(cornerRadius:24))
                    .contentShape(RoundedRectangle(cornerRadius:24))
                    .overlay{RoundedRectangle(cornerRadius:24).stroke(answers.sex == sex ? Color(hex:0xF97316):Color.clear,lineWidth:1.5)}
                    .overlay{RoundedRectangle(cornerRadius:27).stroke(answers.sex == sex ? Color(hex:0x7C2D12).opacity(0.65):Color.clear,lineWidth:4).padding(-2)}
            }.buttonStyle(.plain).accessibilityLabel(sex.title(diary.language))
                .accessibilityIdentifier("assessment.sex.\(sex.rawValue)").accessibilityAddTraits(answers.sex == sex ? .isSelected:[])
        }
            Spacer(minLength:20)
            Button {
                if answers.sex != nil { perform { await next() } }
                else { validation = diary.t("تحتاج معادلة الطاقة اختيار الجنس للحساب. يمكنك حفظ التقييم وإكماله لاحقًا؛ لن نفترض إجابة بدلاً منك.", "The energy equation requires a sex input. You can save and finish later; an answer will not be assumed for you.") }
            } label: {
                HStack(spacing:10){Text(diary.t("أفضل التخطي، شكراً!","Prefer to skip, thanks!"));Image(systemName:"xmark").font(.system(size:13,weight:.bold))}
                    .luqmaFont(size:16,weight:.semibold,relativeTo:.body).foregroundStyle(Color(hex:0xF97316))
                    .frame(maxWidth:.infinity,minHeight:52).background(Color(hex:0x431407),in:RoundedRectangle(cornerRadius:18))
            }.buttonStyle(.plain).accessibilityIdentifier("assessment.sex.skip")
        }
    }

    private var targetAndPace: some View {
        VStack(alignment:.leading,spacing:18){
            Text(diary.t("وزن الهدف — اختياري","Target weight — optional")).luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline)
                .foregroundStyle(Color(hex:0xD7D8D9)).frame(maxWidth:.infinity,alignment:.leading)
            HStack(spacing:12){
                TextField("",text:input(.targetWeight),prompt:Text("—").foregroundColor(Color(hex:0x9EA0A5)))
                    .keyboardType(.decimalPad).luqmaFont(size:36,weight:.heavy,relativeTo:.title)
                    .multilineTextAlignment(diary.language == .ar ? .trailing:.leading).monospacedDigit().environment(\.layoutDirection,.leftToRight)
                    .accessibilityLabel(diary.t("وزن الهدف — اختياري","Target weight — optional")).accessibilityIdentifier("assessment.target")
                Text(diary.t("كجم","kg")).luqmaFont(size:15,weight:.semibold,relativeTo:.subheadline).foregroundStyle(Color(hex:0x9EA0A5))
            }.padding(.horizontal,16).frame(minHeight:74)
                .background(Color(hex:0x24262B),in:RoundedRectangle(cornerRadius:20))
                .overlay{RoundedRectangle(cornerRadius:20).stroke(Color.white.opacity(0.08),lineWidth:1)}
            Text(diary.t("كيف تفضل تعديل السعرات؟","How do you prefer to adjust your daily calories?"))
                .luqmaFont(size:15,weight:.bold,relativeTo:.subheadline).frame(maxWidth:.infinity).padding(.top,6)
            VStack(spacing:12){ForEach(FitnessPace.allCases){pace in
                let selected = (answers.pace ?? .gentle) == pace
                Button{answers.pace=pace;validation=nil}label:{
                    HStack(alignment:.top,spacing:14){
                        VStack(alignment:.leading,spacing:6){
                            Text(pace.approvedTitle(diary.language)).luqmaFont(size:17,weight:.bold,relativeTo:.headline)
                            Text(pace.approvedSubtitle(diary.language)).luqmaFont(size:13,relativeTo:.caption)
                                .foregroundStyle(Color(hex:0x9EA0A5)).fixedSize(horizontal:false,vertical:true)
                        }.frame(maxWidth:.infinity,alignment:.leading)
                        CFARadioIndicator(isSelected:selected).padding(.top,4)
                    }.padding(18).frame(minHeight:90)
                        .background(selected ? Color(hex:0x393C43):Color(hex:0x24262B),in:RoundedRectangle(cornerRadius:20))
                        .overlay{RoundedRectangle(cornerRadius:20).stroke(selected ? Color.white:Color.clear,lineWidth:2)}
                        .overlay{RoundedRectangle(cornerRadius:22).stroke(selected ? Color(hex:0x81858D).opacity(0.5):Color.clear,lineWidth:3).padding(-2)}
                }.buttonStyle(.plain).accessibilityIdentifier("assessment.pace.\(pace.rawValue)").accessibilityAddTraits(selected ? .isSelected:[])
            }}
            Text(diary.t("التعديل البسيط هو الافتراضي. يمكنك ترك وزن الهدف فارغًا؛ لا نحدد موعدًا مضمونًا للوصول إليه.","Smaller adjustment is the default. You can leave target weight blank; we do not promise a date to reach it."))
                .luqmaFont(size:12,relativeTo:.caption).foregroundStyle(Color(hex:0x9EA0A5)).fixedSize(horizontal:false,vertical:true)
        }
    }
    private var activityArc:some View {
        VStack(spacing:16){
            HStack(spacing:8){
                Text("?").luqmaFont(size:11,weight:.bold,relativeTo:.caption2).foregroundStyle(Color(hex:0x111214))
                    .frame(width:18,height:18).background(Color(hex:0x50535B),in:Circle())
                Text(diary.t("اسحب للتعديل","Drag to adjust")).luqmaFont(size:14,weight:.medium,relativeTo:.subheadline).foregroundStyle(Color(hex:0xD7D8D9))
                    .environment(\.layoutDirection,diary.language == .ar ? .rightToLeft:.leftToRight)
                Spacer()
            }.environment(\.layoutDirection,.leftToRight)
            SandowFitnessArcSlider(level:Binding(get:{answers.activity.flatMap{FitnessActivity.allCases.firstIndex(of:$0)}.map{$0+1} ?? 3},set:{level in
                answers.activity=FitnessActivity.allCases[min(4,max(0,level-1))];validation=nil
            }),label:activityArcLabel,hasSelection:answers.activity != nil,onInteractionChanged:{pickerInteraction=$0})
                .frame(height:360)
            DisclosureGroup(diary.t("تفاصيل النشاط والخطوات — اختياري","Activity details and steps — optional")){
                VStack(spacing:16){
                    choices(FitnessActivity.allCases,selection:$answers.activity,prefix:"activity")
                    number(.steps,title:diary.t("متوسط الخطوات — اختياري","Average daily steps — optional"),suffix:diary.t("خطوة","steps"),id:"steps")
                    helper("اختر الحركة خلال يومك المعتاد. أدخل الخطوات فقط إن كنت تعرف متوسطها.","Choose the movement in your usual day. Enter steps only if you know your average.")
                }.padding(.top,12)
            }.luqmaFont(size:13,relativeTo:.caption).tint(Color(hex:0xF97316))
                // Keep the disclosure's identifier on its own AX container;
                // its choices and manual steps field retain their own IDs.
                .accessibilityElement(children:.contain).accessibilityIdentifier("assessment.activity.details")
        }
    }
    private var activityArcLabel:String {
        guard let activity=answers.activity else { return diary.t("اختر مستوى نشاطك","Choose your activity") }
        let index=FitnessActivity.allCases.firstIndex(of:activity) ?? 0
        let ar=["نشاط قليل","نشاط خفيف","نشاط متوسط","نشاط مرتفع","نشاط مكثف"]
        let en=["Sedentary","Lightly active","Moderately active","Very active","Highly active"]
        return diary.t(ar[index],en[index])
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
    private var review: some View {
        VStack(spacing: 16) {
            helper("راجع القيم قبل المعاينة. لا تتغير أهدافك حتى تعتمد الخطة.", "Review the values before previewing. Your goals change only when you apply the plan.")
            reviewRow(diary.t("الهدف", "Goal"), answers.goal?.title(diary.language) ?? "—", page: .goal)
            reviewRow(diary.t("الملاءمة", "Suitability"), answers.safety?.title(diary.language) ?? "—", page: .suitability)
            reviewRow(diary.t("الجنس المستخدم للحساب", "Sex used for equation"), answers.sex?.title(diary.language) ?? "—", page: .sex)
            reviewRow(diary.t("العمر", "Age"), raw(.age) + diary.t(" سنة", " years"), page: .age)
            reviewRow(diary.t("الطول", "Height"), raw(.height) + diary.t(" سم", " cm"), page: .height)
            reviewRow(diary.t("الوزن", "Weight"), raw(.weight) + diary.t(" كجم", " kg"), page: .weight)
            reviewRow(diary.t("وزن الهدف والوتيرة", "Target weight and adjustment"), [optionalValue(.targetWeight), answers.pace?.title(diary.language) ?? diary.t("افتراضي: تدريجي", "Default: gentle")].joined(separator: " · "), page: .targetPace)
            reviewRow(diary.t("النشاط", "Activity"), answers.activity?.title(diary.language) ?? "—", page: .activity)
            reviewRow(diary.t("التدريب", "Training"), [answers.experience?.title(diary.language) ?? diary.t("افتراضي: مبتدئ", "Default: beginner"), optionalValue(.trainingDays) + diary.t(" أيام", " days"), optionalValue(.sessionMinutes) + diary.t(" دقيقة", " min")].joined(separator: " · "), page: .training)
            reviewRow(diary.t("النوم والتفضيلات الغذائية", "Sleep and food preferences"), optionalValue(.sleepHours) + diary.t(" ساعة", " hours"), page: .details)
            if !legacySummary.isEmpty {
                DisclosureGroup(diary.t("إجابات إضافية محفوظة سابقًا", "Previously saved additional answers")) {
                    Text(legacySummary).luqmaFont(.helper).foregroundStyle(Theme.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }.luqmaFont(.label).tint(Theme.secondaryAccent)
            }
            helper("إجاباتك محفوظة محليًا. يمكنك تعديل ملف اللياقة أو حذفه من الإعدادات؛ النسخة الاحتياطية تتضمنه.", "Answers are stored locally. Edit or delete your fitness profile in Settings; backups include it.")
        }
    }
    private var legacySummary: String {
        var rows: [String] = []
        if let place = answers.trainingPlace { rows.append(place.title(diary.language)) }
        rows += answers.exercise.map { $0.title(diary.language) }
        if let quality = answers.sleepQuality { rows.append(quality.title(diary.language)) }
        rows += [answers.bedtime, answers.wakeTime].compactMap { $0 }
        if let stress = answers.stress { rows.append(diary.t("الإجهاد: ", "Stress: ") + String(stress)) }
        if let diet = answers.diet { rows.append(diet.title(diary.language)) }
        if let meals = answers.mealsPerDay { rows.append(String(meals) + diary.t(" وجبات", " meals")) }
        rows += [answers.dislikedFoods, answers.allergies, answers.restrictions].filter { !$0.isEmpty }
        return rows.joined(separator: " · ")
    }
    private func reviewRow(_ title: String, _ value: String, page target: FitnessAssessmentPage) -> some View {
        Button { perform { await move(to: target) } } label: {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).luqmaFont(.helper).foregroundStyle(Theme.muted)
                    Text(value).luqmaFont(.button).foregroundStyle(Theme.text)
                }
                Spacer()
                Text(diary.t("تعديل", "Edit")).luqmaFont(.helper).foregroundStyle(Theme.link)
            }
        }.buttonStyle(.plain).luqmaCard().disabled(actionBusy)
            .accessibilityIdentifier("assessment.edit.\(target.rawValue)")
    }
    private func number(_ field: FitnessAssessmentNumberField, title: String, suffix: String, id: String, style: AssessmentNumberPicker.Style? = nil) -> some View {
        FitnessNumberField(title: title, text: input(field), suffix: suffix, identifier: "assessment.\(id)", field: field, pickerStyle: style,
            displayUnit:Binding(get:{ApprovedMeasurementUnit(rawValue:inputs["unit.\(field.rawValue)"] ?? "") ?? .metric},set:{inputs["unit.\(field.rawValue)"]=$0.rawValue}),
            alternateText:Binding(get:{inputs["input.imperial.\(field.rawValue)"] ?? ""},set:{inputs["input.imperial.\(field.rawValue)"]=$0}),
            onInteractionChanged:{pickerInteraction=$0})
    }
    private func raw(_ field: FitnessAssessmentNumberField) -> String { inputs[field.rawValue] ?? "" }
    private func optionalValue(_ field: FitnessAssessmentNumberField) -> String {
        raw(field).isEmpty ? diary.t("غير محدد", "Not set") : raw(field)
    }
    private func input(_ field: FitnessAssessmentNumberField) -> Binding<String> {
        Binding(get: { raw(field) }, set: { new in
            let normalized = String(DisplayFormat.westernDigits(new).prefix(64))
            guard raw(field) != normalized else { return }
            inputs[field.rawValue] = normalized
            field.setValue(field.parse(normalized), in: &answers)
            reviewed = false
            validation = nil
        })
    }
    @ViewBuilder private func dietIcon(_ option:FitnessDietPreference)->some View {
        switch option {
        case .vegan,.vegetarian:Image("CFADietVegan").renderingMode(.template).resizable().scaledToFit().frame(width:24,height:24).accessibilityHidden(true)
        case .balanced:Image("CFADietCarbo").renderingMode(.template).resizable().scaledToFit().frame(width:24,height:24).accessibilityHidden(true)
        case .pescatarian:Image(systemName:"fish.fill").font(.system(size:23)).frame(width:24,height:24).accessibilityHidden(true)
        case .halal:Image("CFADietTraditional").renderingMode(.template).resizable().scaledToFit().frame(width:24,height:24).accessibilityHidden(true)
        }
    }
    private func helper(_ ar:String,_ en:String)->some View {Text(diary.t(ar,en)).luqmaFont(.helper).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)}
    private func notes(_ title:String,text:Binding<String>,id:String)->some View {
        VStack(alignment:.leading,spacing:8){Text(title).luqmaFont(.label);TextField(title,text:text,prompt:Text(title).foregroundColor(Theme.muted),axis:.vertical).lineLimit(2...5).padding(16).background(Theme.card,in:RoundedRectangle(cornerRadius:19)).accessibilityIdentifier("assessment.\(id)")}
    }
    private func load() {
        guard !loaded else { return }
        loaded = true
        #if DEBUG
        if let previewPage {
            answers = FitnessPreviewData.answers
            page = FitnessAssessmentPage.allCases[min(FitnessAssessmentPage.allCases.count - 1, max(0, previewPage))]
            populateInputs()
            return
        }
        #endif
        if let saved = diary.state.fitnessDraft {
            answers = saved.answers
            page = saved.resolvedPage
            populateInputs()
            for (key, value) in saved.numericInputs ?? [:] {
                inputs[key] = value
                if let field = FitnessAssessmentNumberField(rawValue: key) { field.setValue(field.parse(value), in: &answers) }
            }
        } else {
            if let profile = diary.state.fitnessProfile { answers = profile.answers }
            populateInputs()
        }
    }
    private func populateInputs() {
        for field in FitnessAssessmentNumberField.allCases { inputs[field.rawValue] = field.value(in: answers).map { field.displayText($0) } ?? "" }
    }
    private var draft: FitnessAssessmentDraft {
        FitnessAssessmentDraft(answers: answers, step: page.group, updatedDay: DayKey.today, pageIndex: page.legacyIndex, pageID: page.rawValue, numericInputs: inputs)
    }
    @discardableResult private func persist(deferAssessment: Bool = false) async -> Bool {
        guard previewPage == nil, loaded, !reviewed else { return true }
        let saved = await diary.saveFitnessDraftInBackground(draft, deferAssessment: deferAssessment)
        if !saved { showOperationError("تعذّر حفظ الإجابات. حاول مرة أخرى.", "Could not save your answers. Try again.") }
        return saved
    }
    private func showOperationError(_ ar: String, _ en: String) {
        validation = diary.error ?? diary.t(ar, en)
        diary.error = nil
    }
    private func perform(_ action: @escaping @MainActor () async -> Void) {
        guard !actionBusy else { return }
        actionBusy = true
        endEditing()
        Task { @MainActor in
            await action()
            // Navigation happens immediately after saving. A brief tap gate
            // absorbs queued double taps without animating the entire form.
            try? await Task.sleep(for: .milliseconds(250))
            actionBusy = false
        }
    }
    private func back() async {
        if page == .goal {
            if await persist() { leaving = true; dismiss() }
        } else { await move(to: FitnessAssessmentPage.allCases[page.index - 1]) }
    }
    private func move(to target: FitnessAssessmentPage) async {
        let previous = page
        reviewed = false
        page = target
        validation = nil
        if !(await persist()) { page = previous }
    }
    private var fieldsOnPage: [FitnessAssessmentNumberField] {
        switch page {
        case .age: return [.age]
        case .height: return [.height]
        case .weight: return [.weight]
        case .targetPace: return [.targetWeight]
        case .activity: return [.steps]
        case .training: return [.trainingDays, .sessionMinutes]
        case .details: return [.sleepHours, .meals]
        case .review: return FitnessAssessmentNumberField.allCases
        default: return []
        }
    }
    private func next() async {
        validation = nil
        for field in fieldsOnPage {
            if let message = field.validationMessage(for: raw(field), language: diary.language) { validation = message; return }
        }
        let valid: Bool
        switch page {
        case .goal: valid = answers.goal != nil
        case .suitability:
            guard answers.safety == nil || answers.safety == .generalAdult else {
                validation = diary.t("لا تُنشئ هذه الحاسبة خطة للحمل أو الرضاعة أو الحالات والخطط الطبية الخاصة. احتفظ بأهداف يحددها مختص.", "This estimator does not create plans for pregnancy, breastfeeding, or specific medical conditions or diets. Keep goals set with a qualified professional.")
                return
            }
            valid = answers.safety != nil
        case .sex: valid = answers.sex != nil
        case .activity: valid = answers.activity != nil
        default: valid = true
        }
        guard valid else { validation = diary.t("اختر إجابة قبل المتابعة.", "Choose an answer before continuing."); return }
        do { try answers.validate() }
        catch { validation = (error as? AppError)?.message(diary.language) ?? error.localizedDescription; return }
        if page == .review {
            if previewPage == nil {
                if await diary.previewFitnessPlanInBackground(answers) { reviewed = true; showingPlan = true }
                else { showOperationError("تعذّرت معاينة الخطة. راجع الإجابات وحاول مرة أخرى.", "Could not preview the plan. Review your answers and try again.") }
            }
        } else { await move(to: FitnessAssessmentPage.allCases[page.index + 1]) }
    }
    private func endEditing() {
        _ = UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Raw text lives in the form/draft, not in view-local state. Changing pages or
/// dismissing the keyboard therefore cannot reset or round an entered answer.
private struct FitnessNumberField: View {
    let title: String
    @Binding var text: String
    let suffix: String
    let identifier: String
    let field: FitnessAssessmentNumberField
    var pickerStyle: AssessmentNumberPicker.Style?
    @Binding var displayUnit: ApprovedMeasurementUnit
    @Binding var alternateText:String
    var onInteractionChanged:(Bool)->Void = {_ in}
    @FocusState private var focused: Bool
    var body: some View {
        if let pickerStyle {
            AssessmentNumberPicker(title: title, text: $text, unit: suffix, field: field, identifier: identifier, style: pickerStyle, displayUnit:$displayUnit,alternateText:$alternateText,onInteractionChanged:onInteractionChanged)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).luqmaFont(.label).fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    TextField("", text: $text, prompt: Text("…").foregroundColor(Theme.muted))
                        .keyboardType(field.integer ? .numberPad : .decimalPad).focused($focused)
                        .luqmaFont(size: 32, weight: .bold, relativeTo: .largeTitle).monospacedDigit()
                        .environment(\.layoutDirection, .leftToRight).accessibilityLabel(title).accessibilityIdentifier(identifier)
                    Text(suffix).luqmaFont(.label).foregroundStyle(Theme.muted)
                }.padding(16).background(Theme.card, in: RoundedRectangle(cornerRadius: 24))
            }
        }
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
