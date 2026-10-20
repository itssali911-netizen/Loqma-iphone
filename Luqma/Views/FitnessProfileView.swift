import SwiftUI

// Functional profile/plan-summary adaptations of the documented Sandow cards,
// 16-point gutters, dark surfaces and bundled typography. The available Figma
// evidence has no dedicated profile-summary or review-before-apply frame.
struct FitnessProfileView: View {
    @EnvironmentObject private var diary: DiaryStore
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var deleted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let profile = diary.state.fitnessProfile {
                    summary(profile)
                    planStatus
                    basics(profile.answers)
                    activity(profile.answers)
                    recovery(profile.answers)
                    nutrition(profile.answers)
                    privacy
                    Button(diary.t("حذف ملف اللياقة", "Delete fitness profile"), role: .destructive) {
                        confirmingDelete = true
                    }.buttonStyle(LuqmaSecondaryButtonStyle()).accessibilityIdentifier("fitness.delete")
                } else {
                    SandowEmptyState(title: diary.t("خطة تبدأ منك", "A plan that starts with you"),
                        message: diary.t("أكمل تقييمًا قصيرًا للحصول على تقديرات للتغذية والنشاط. يبقى سجل الطعام وأهدافك الحالية محفوظين.", "Complete a short assessment for nutrition and activity estimates. Your diary and current goals stay saved."))
                    Button(diary.t("بدء تقييم اللياقة", "Start fitness assessment")) { editing = true }
                        .buttonStyle(LuqmaPrimaryButtonStyle()).accessibilityIdentifier("fitness.edit")
                    if diary.state.fitnessDraft != nil {
                        Notice(text: diary.t("لديك إجابات محفوظة؛ يمكنك المتابعة من حيث توقفت.", "Your answers are saved. Continue where you left off."))
                    }
                    if deleted {
                        SandowSavedConfirmation(text: diary.t("حُذف ملف اللياقة. بقي سجل الطعام وأهداف التغذية الحالية محفوظين.", "Fitness profile deleted. Your food diary and current nutrition targets were kept."))
                            .accessibilityIdentifier("fitness.deletedConfirmation")
                    }
                    privacy
                }
                if let error = diary.error { SandowStateAlert(text: error) }
            }.padding(16).padding(.vertical, 8)
                // Pushed TabView destinations can extend behind the custom
                // bar. Let the final control scroll above its actual height.
                .padding(.bottom, Theme.bottomBarHeight)
        }.appBackground().accessibilityIdentifier("fitness.profile")
            .sandowNavigation(diary.t("ملف اللياقة", "Fitness profile"), backLabel: diary.t("رجوع", "Back"))
            .sheet(isPresented: $editing) { FitnessAssessmentView() }
            .alert(diary.t("حذف بيانات تقييم اللياقة؟", "Delete fitness assessment data?"), isPresented: $confirmingDelete) {
                Button(diary.t("حذف ملف اللياقة", "Delete fitness profile"), role: .destructive) {
                    deleted = diary.deleteFitnessProfile()
                }.accessibilityIdentifier("fitness.confirmDelete")
                Button(diary.t("إلغاء", "Cancel"), role: .cancel) {}
            } message: {
                Text(diary.t("سيُحذف ملفك وإجابات التقييم وخططه فقط. لن يُحذف سجل الطعام أو الوزن أو الوصفات، وستبقى أهداف التغذية وإعدادات خطة الوزن الحالية. النسخ التي صدّرتها سابقًا لا تتغير.", "Only your assessment answers, profile and its plans will be deleted. Food, weight history and recipes remain, along with current nutrition targets and weight-plan settings. Previously exported backups are not changed."))
            }
    }
    private func summary(_ profile: FitnessProfile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(diary.t("هدفك الحالي", "Your current goal")).luqmaFont(.footnote).foregroundStyle(Theme.muted)
            Text(profile.answers.goal?.title(diary.language) ?? "—").luqmaFont(size: 28, weight: .bold, relativeTo: .title)
                .foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
            if let weight = profile.answers.weightKG {
                Text(DisplayFormat.decimal(weight) + " " + diary.t("كجم في ملف التقييم", "kg in your assessment"))
                    .luqmaFont(.body).foregroundStyle(Theme.textSecondary)
            }
            Button(diary.t("تعديل بياناتي", "Edit my answers")) { editing = true }
                .buttonStyle(LuqmaPrimaryButtonStyle()).accessibilityIdentifier("fitness.edit")
        }.luqmaCard()
    }
    private var planStatus: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(diary.t("خطتك الشخصية", "Your personal plan")).luqmaFont(.headline).accessibilityAddTraits(.isHeader)
            Text(statusText).luqmaFont(.footnote).foregroundStyle(Theme.muted)
                .accessibilityIdentifier("fitness.profile.appliedStatus").accessibilityValue(statusValue)
            if diary.state.proposedFitnessPlan != nil {
                NavigationLink { FitnessPlanReviewView() } label: {
                    Text(diary.t("مراجعة الخطة المقترحة", "Review proposed plan"))
                }.buttonStyle(LuqmaPrimaryButtonStyle()).accessibilityIdentifier("fitness.reviewPlan")
            } else if diary.state.appliedFitnessPlan != nil {
                NavigationLink { FitnessPlanReviewView() } label: {
                    Text(diary.t("عرض تفاصيل الخطة", "View plan details"))
                }.buttonStyle(LuqmaSecondaryButtonStyle()).accessibilityIdentifier("fitness.reviewPlan")
            }
            if diary.state.fitnessDraft != nil && diary.state.proposedFitnessPlan == nil {
                Notice(text: diary.t("توجد إجابات قيد التعديل. راجعها وأعد حساب الخطة قبل اعتمادها.", "Some answers are being edited. Review and recalculate the plan before applying it."))
            }
        }.luqmaCard()
    }
    private var statusValue: String {
        diary.state.appliedFitnessPlan == nil ? "none" : (FitnessAssessmentState.hasAppliedGoals(diary.state) ? "active" : "manual")
    }
    private var statusText: String {
        if diary.state.appliedFitnessPlan == nil {
            return diary.t("لم تُعتمد خطة تقييم بعد. أهدافك الحالية هي المستخدمة في سجل الطعام.", "No assessment plan has been applied. Your current targets are used in the food diary.")
        }
        return FitnessAssessmentState.hasAppliedGoals(diary.state)
            ? diary.t("أهداف هذه الخطة مستخدمة حاليًا في سجل الطعام. أي تعديل جديد يحتاج مراجعتك قبل الاعتماد.", "These plan targets are currently used in your food diary. New changes need your review before applying.")
            : diary.t("أهدافك الحالية عُدّلت يدويًا أو بخطة أخرى. تفاصيل التقييم المحفوظة لا تستبدلها تلقائيًا.", "Your current targets were changed manually or by another plan. The saved assessment does not replace them automatically.")
    }
    private func basics(_ answers: FitnessAnswers) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(diary.t("بيانات الحساب", "Calculation inputs"))
            detail(diary.t("الجنس المستخدم للمعادلة", "Sex used for the equation"), answers.sex?.title(diary.language))
            detail(diary.t("العمر", "Age"), answers.age.map { String($0) + " " + diary.t("سنة", "years") })
            detail(diary.t("الطول", "Height"), answers.heightCM.map { DisplayFormat.decimal($0) + " " + diary.t("سم", "cm") })
            detail(diary.t("الوزن", "Weight"), answers.weightKG.map { DisplayFormat.decimal($0) + " " + diary.t("كجم", "kg") })
            detail(diary.t("وزن الهدف", "Target weight"), answers.targetWeightKG.map { DisplayFormat.decimal($0) + " " + diary.t("كجم", "kg") })
            detail(diary.t("الوتيرة", "Pace"), (answers.pace ?? .gentle).title(diary.language))
        }.luqmaCard()
    }
    private func activity(_ answers: FitnessAnswers) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                detail(diary.t("النشاط اليومي", "Daily activity"), answers.activity?.title(diary.language))
                detail(diary.t("متوسط الخطوات", "Average steps"), answers.stepsPerDay.map(String.init))
                detail(diary.t("الخبرة التدريبية", "Training experience"), answers.experience?.title(diary.language))
                detail(diary.t("أيام التدريب", "Training days"), answers.trainingDays.map(String.init))
                detail(diary.t("مدة الحصة", "Session length"), answers.sessionMinutes.map { String($0) + " " + diary.t("دقيقة", "min") })
                detail(diary.t("مكان التدريب", "Training location"), answers.trainingPlace?.title(diary.language))
                detail(diary.t("التمارين المفضلة", "Preferred activities"), answers.exercise.isEmpty ? nil : answers.exercise.map { $0.title(diary.language) }.joined(separator: diary.t("، ", ", ")))
            }.padding(.top, 12)
        } label: { sectionTitle(diary.t("النشاط والتدريب", "Activity and training")) }.tint(Theme.link).luqmaCard()
    }
    private func recovery(_ answers: FitnessAnswers) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                detail(diary.t("ساعات النوم", "Sleep hours"), answers.sleepHours.map { DisplayFormat.decimal($0) })
                detail(diary.t("جودة النوم", "Sleep quality"), answers.sleepQuality?.title(diary.language))
                detail(diary.t("وقت النوم", "Bedtime"), answers.bedtime)
                detail(diary.t("وقت الاستيقاظ", "Wake time"), answers.wakeTime)
                detail(diary.t("الإجهاد", "Stress"), answers.stress.map { String($0) + " / 5" })
            }.padding(.top, 12)
        } label: { sectionTitle(diary.t("النوم والاستشفاء", "Sleep and recovery")) }.tint(Theme.link).luqmaCard()
    }
    private func nutrition(_ answers: FitnessAnswers) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                detail(diary.t("التفضيل الغذائي", "Diet preference"), answers.diet?.title(diary.language))
                detail(diary.t("عدد الوجبات", "Meals per day"), answers.mealsPerDay.map(String.init))
                detail(diary.t("أطعمة لا تفضلها", "Disliked foods"), nonempty(answers.dislikedFoods))
                detail(diary.t("الحساسية", "Allergies"), nonempty(answers.allergies))
                detail(diary.t("ملاحظات أو قيود", "Notes or restrictions"), nonempty(answers.restrictions))
                Notice(text: diary.t("تُحفظ هذه التفضيلات للمراجعة. لا تُفلتر المنتجات أو الوصفات تلقائيًا للحساسية؛ راجع المكونات والملصق دائمًا.", "These preferences are saved for review. Products and recipes are not automatically filtered for allergies; always review ingredients and labels."))
            }.padding(.top, 12)
        } label: { sectionTitle(diary.t("التغذية والتفضيلات", "Nutrition preferences")) }.tint(Theme.link).luqmaCard()
    }
    private var privacy: some View {
        Notice(text: diary.t("هذا ملف محلي على هذا الآيفون، وليس حسابًا على خادم. تُحفظ الإجابات مع السجل في ملف محمي عند قفل الجهاز. يمكنك تعديلها أو حذفها؛ النسخة الاحتياطية التي تصدّرها تتضمن هذه البيانات الحساسة.", "This is a local profile on this iPhone, not a server account. Answers are stored with your diary in a file protected while the device is locked. You can edit or delete them; exported backups include this sensitive data."))
    }
    private func sectionTitle(_ value: String) -> some View {
        Text(value).luqmaFont(.headline).foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
    }
    private func nonempty(_ value: String) -> String? { value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value }
    private func detail(_ label: String, _ value: String?) -> some View {
        FitnessDetailRow(label: label, value: value ?? diary.t("غير محدد", "Not set"))
    }
}

struct FitnessPlanReviewView: View {
    @EnvironmentObject private var diary: DiaryStore
    @State private var applied = false
    @State private var assumptionsExpanded = false
    private var plan: FitnessPlan? { diary.state.proposedFitnessPlan ?? diary.state.appliedFitnessPlan }
    private var canApply: Bool {
        guard let proposed = diary.state.proposedFitnessPlan, let profile = diary.state.fitnessProfile else { return false }
        return proposed.profileID == profile.id && proposed.profileRevision == profile.revision && proposed.answers == profile.answers
            && (diary.state.fitnessDraft.map { $0.answers == proposed.answers } ?? true)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let plan {
                    if applied {
                        SandowSavedConfirmation(text: diary.t("حُفظت الخطة واعتُمدت أهدافها في سجل الطعام دون حذف أي سجل سابق.", "Plan saved. Its targets are now used in your food diary, with all previous entries preserved."))
                            .accessibilityIdentifier("fitness.appliedConfirmation")
                    }
                    planHeading(plan)
                    if plan.calorieFloorApplied {
                        SandowStateAlert(text: diary.t("رُفع اقتراح السعرات إلى حد التطبيق الاحتياطي؛ قد لا ينتج عجزًا لخسارة الوزن. راجع تفاصيل الحساب قبل الاعتماد.", "The calorie suggestion was raised to the app's precautionary floor and may not produce a weight-loss deficit. Review the calculation details before applying."))
                    }
                    if diary.state.proposedFitnessPlan != nil { changes(plan) }
                    else { savedTargets(plan) }
                    recommendations(plan)
                    assumptions(plan)
                    Notice(text: diary.t("هذه تقديرات عامة للبالغين وليست قياسات أو خطة علاجية. لا تناسب الحمل والرضاعة أو القاصرين أو الحالات التي تحتاج خطة طبية خاصة. لا تضمن موعدًا أو معدلًا لتغير الوزن.", "These are general adult estimates, not measurements or a medical plan. They do not cover pregnancy, breastfeeding, minors or conditions requiring a medical diet. No weight-change date or rate is promised."))
                    if diary.state.proposedFitnessPlan != nil {
                        if !canApply {
                            SandowStateAlert(text: diary.t("توجد إجابات أحدث في مسودة التقييم. ارجع لتعديلها ومراجعتها وإنشاء معاينة متطابقة قبل الاعتماد.", "Your assessment draft contains newer answers. Return to edit and review them, then create a matching preview before applying."))
                        }
                        Notice(text: diary.t("سيستبدل الاعتماد أهداف السعرات والماكروز الحالية، ويوقف تحديث السعرات التلقائي لخطة الوزن. ستبقى خطة الوزن وسجلاتك محفوظة.", "Applying replaces your current calorie and macro targets and turns off automatic calorie updates from the weight plan. Your weight plan and diary remain saved."))
                    }
                } else {
                    SandowEmptyState(title: diary.t("لا توجد خطة للمراجعة", "No plan to review"), message: diary.t("راجع إجابات التقييم وأنشئ معاينة جديدة أولًا. أهدافك الحالية لم تتغير.", "Review your assessment answers and create a fresh preview first. Your current targets are unchanged."))
                }
                if let error = diary.error { SandowStateAlert(text: error) }
            }.padding(16).padding(.vertical, 8)
        }.appBackground().accessibilityIdentifier("fitness.review")
            .sandowNavigation(diary.t("مراجعة الخطة", "Plan review"), backLabel: diary.t("رجوع", "Back"),
                actionLabel: diary.state.proposedFitnessPlan != nil ? diary.t("اعتماد هذه الأهداف", "Apply these targets") : nil,
                actionEnabled: canApply, actionIdentifier: "fitness.apply", onAction: { applied = diary.applyFitnessPlan() })
    }
    private func planHeading(_ plan: FitnessPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(diary.state.proposedFitnessPlan != nil ? diary.t("تقديراتك المقترحة", "Your proposed estimates") : diary.t("الخطة المحفوظة", "Saved plan"))
                .luqmaFont(.footnote).foregroundStyle(Theme.muted)
            Text(plan.answers.goal?.title(diary.language) ?? "—").luqmaFont(size: 28, weight: .bold, relativeTo: .title)
                .foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
            Text(DisplayFormat.decimal(plan.goals.kcal, digits: 0) + " " + diary.t("سعرة / يوم", "kcal / day"))
                .luqmaFont(size: 36, weight: .bold, relativeTo: .largeTitle).foregroundStyle(Theme.text).monospacedDigit()
                .accessibilityIdentifier("fitness.plan.calories")
            Text(diary.state.proposedFitnessPlan != nil
                 ? diary.t("تُحسب من بياناتك ونشاطك، ولا تُعتمد قبل موافقتك.", "Calculated from your inputs and activity. A preview needs your approval to become your targets.")
                 : diary.t("قيم محفوظة من آخر خطة اعتمدتها. تبقى الأهداف اليدوية أو أي خطة أحدث مستقلة عنها.", "Saved values from your last applied plan. Manual targets or a newer plan remain separate."))
                .luqmaFont(.footnote).foregroundStyle(Theme.muted)
        }.luqmaCard()
    }
    private func changes(_ plan: FitnessPlan) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(diary.t("قبل الاعتماد", "Before applying")).luqmaFont(.headline).accessibilityAddTraits(.isHeader)
            HStack {
                Text(diary.t("الهدف اليومي", "Daily target"))
                Spacer(minLength: 8)
                Text(diary.t("الحالي ← المقترح", "Current → Proposed"))
            }.luqmaFont(.footnote).foregroundStyle(Theme.muted)
            difference(diary.t("السعرات", "Calories"), key: "calories", current: diary.state.goals.kcal, proposed: plan.goals.kcal, unit: diary.t("سعرة", "kcal"), digits: 0)
            difference(diary.t("البروتين", "Protein"), key: "protein", current: diary.state.goals.protein, proposed: plan.goals.protein, unit: diary.t("جم", "g"))
            difference(diary.t("الكارب", "Carbs"), key: "carbs", current: diary.state.goals.carbs, proposed: plan.goals.carbs, unit: diary.t("جم", "g"))
            difference(diary.t("الدهون", "Fat"), key: "fat", current: diary.state.goals.fat, proposed: plan.goals.fat, unit: diary.t("جم", "g"))
        }.luqmaCard()
    }
    private func difference(_ label: String, key: String, current: Double, proposed: Double, unit: String, digits: Int = 1) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label).luqmaFont(.body)
                Spacer(minLength: 8)
                diffValues(key: key, current: current, proposed: proposed, unit: unit, digits: digits)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(label).luqmaFont(.body)
                diffValues(key: key, current: current, proposed: proposed, unit: unit, digits: digits)
            }
        }.foregroundStyle(Theme.text).accessibilityElement(children: .contain)
    }
    private func diffValues(key: String, current: Double, proposed: Double, unit: String, digits: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(DisplayFormat.decimal(current, digits: digits)).foregroundStyle(Theme.muted)
                .accessibilityIdentifier("fitness.review." + key + ".current")
            Image(systemName: "arrow.forward").font(.system(size: 12)).foregroundStyle(Theme.muted).accessibilityHidden(true)
            Text(DisplayFormat.decimal(proposed, digits: digits)).foregroundStyle(Theme.text)
                .accessibilityIdentifier("fitness.review." + key + ".proposed")
            Text(unit).foregroundStyle(Theme.muted)
        }.luqmaFont(.footnote).monospacedDigit()
    }
    private func savedTargets(_ plan: FitnessPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(diary.t("تفاصيل الأهداف المحفوظة", "Saved target details")).luqmaFont(.headline).accessibilityAddTraits(.isHeader)
            FitnessDetailRow(label: diary.t("البروتين", "Protein"), value: grams(plan.goals.protein))
            FitnessDetailRow(label: diary.t("الكارب", "Carbs"), value: grams(plan.goals.carbs))
            FitnessDetailRow(label: diary.t("الدهون", "Fat"), value: grams(plan.goals.fat))
            if !FitnessAssessmentState.hasAppliedGoals(diary.state) {
                Notice(text: diary.t("هذه تفاصيل خطة سابقة؛ أهداف سجل الطعام الحالية مختلفة ولم تتغير.", "These are details of a previous plan. Your current diary targets are different and have not been changed."))
            }
        }.luqmaCard()
    }
    private func recommendations(_ plan: FitnessPlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(diary.t("مقترحات للنشاط والاستشفاء", "Activity and recovery suggestions")).luqmaFont(.headline).accessibilityAddTraits(.isHeader)
            FitnessDetailRow(label: diary.t("جلسات التدريب", "Training sessions"), value: String(plan.activity.trainingDays) + " " + diary.t("أيام أسبوعيًا", "days / week"))
            FitnessDetailRow(label: diary.t("مدة الحصة المقترحة", "Suggested session length"), value: String(plan.activity.sessionMinutes) + " " + diary.t("دقيقة", "min"))
            FitnessDetailRow(label: diary.t("المقاومة", "Strength activity"), value: String(plan.activity.strengthDays) + " " + diary.t("أيام أسبوعيًا", "days / week"))
            FitnessDetailRow(label: diary.t("النشاط الهوائي المعتدل", "Moderate aerobic activity"), value: String(plan.activity.weeklyCardioMinutes) + " " + diary.t("دقيقة أسبوعيًا", "min / week"))
            FitnessDetailRow(label: diary.t("الخطوات المقترحة", "Suggested steps"), value: String(plan.activity.stepsPerDay) + " " + diary.t("يوميًا", "/ day"))
            FitnessDetailRow(label: diary.t("فرصة النوم", "Sleep opportunity"), value: DisplayFormat.decimal(plan.activity.sleepHours) + " " + diary.t("ساعات ليلًا", "hours / night"))
            Notice(text: diary.t("هذه مقترحات عامة وليست سجلًا لنشاط أُنجز أو جدول تمارين إلزاميًا. وزّع الحركة على الأسبوع وزدها تدريجيًا حسب قدرتك، واترك وقتًا للاستشفاء بين حصص المقاومة.", "These are general suggestions, not recorded activity or a mandatory workout schedule. Spread movement across the week, build gradually within your ability, and allow recovery between strength sessions."))
        }.luqmaCard()
    }
    private func assumptions(_ plan: FitnessPlan) -> some View {
        DisclosureGroup(isExpanded: $assumptionsExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                FitnessDetailRow(label: diary.t("الأيض في الراحة BMR / REE", "Resting estimate BMR / REE"), value: calories(plan.bmr))
                FitnessDetailRow(label: diary.t("الاحتياج التقديري TDEE", "Estimated TDEE"), value: calories(plan.tdee))
                FitnessDetailRow(label: diary.t("معامل النشاط المختار", "Selected activity factor"), value: DisplayFormat.decimal(plan.answers.activity?.multiplier ?? 1.4, digits: 1))
                FitnessDetailRow(label: diary.t("فرق الهدف عن الاحتياج", "Target minus estimated TDEE"), value: calories(plan.energyAdjustment))
                Notice(text: diary.t("Mifflin–St Jeor: 9.99 × الوزن + 6.25 × الطول − 4.92 × العمر، ثم +5 للذكور أو −161 للإناث. الجنس هنا مُدخل للمعادلة فقط. الاحتياج = تقدير الراحة × معامل النشاط؛ الخطوات وأيام التمرين لا تُضاف مرة ثانية إلى السعرات.", "Mifflin–St Jeor: 9.99 × kg + 6.25 × cm − 4.92 × age, then +5 for male or −161 for female. Sex is used only as an equation input. TDEE = resting estimate × activity factor; steps and training days are not added to calories a second time."))
                Notice(text: diary.t("فئات النشاط 1.4–2.2 افتراضات للتطبيق ضمن نطاق PAL العام. الخسارة التدريجية 10% والمعتدلة 15% بحد 500 سعرة؛ البناء 5% أو 7.5% بحد 250. باقي الأهداف تبدأ من المحافظة. تُقرّب السعرات إلى 10.", "Activity categories 1.4–2.2 are app assumptions within the general PAL range. Gentle/moderate loss uses 10%/15% capped at 500 kcal; gain uses 5%/7.5% capped at 250. Other goals start at maintenance. Calories are rounded to 10."))
                Notice(text: diary.t("للاحتياط لا يقترح التطبيق أقل من تقدير الراحة أو 1500 سعرة للذكور و1200 للإناث، أيهما أعلى. هذا قيد للتطبيق وليس حدًا طبيًا مناسبًا للجميع. البروتين 20% للمحافظة والصحة العامة و25% لباقي الأهداف، والدهون 30% والكارب هو الباقي.", "As a precaution, the app does not suggest less than the resting estimate or 1500 kcal for male / 1200 for female, whichever is higher. This is a product limit, not a medical minimum for everyone. Protein is 20% for maintenance/general fitness and 25% for other goals, fat 30%, and carbs the remainder."))
                if plan.calorieFloorApplied {
                    SandowStateAlert(text: diary.t("رُفع اقتراح السعرات إلى حد التطبيق الاحتياطي؛ قد لا ينتج عجزًا لخسارة الوزن. لم يُفرض هدف منخفض للوصول إلى وزن معين.", "The calorie suggestion was raised to the app's precautionary floor and may not produce a weight-loss deficit. A low target was not forced to reach a particular weight."))
                }
                Notice(text: diary.t("الخطوات ومدد التدريب اقتراحات بدء حسب إجاباتك، وليست قياسات. تفضيلات الغذاء والحساسية محفوظة، ولا تغيّر المعادلة أو تجعل الوصفات آمنة للحساسية تلقائيًا.", "Steps and session lengths are starting suggestions based on your answers, not measurements. Diet preferences and allergies are saved but do not change the equation or automatically make recipes allergy-safe."))
                sourceLinks
            }.padding(.top, 12)
        } label: { Text(diary.t("كيف حُسبت الخطة؟", "How was the plan calculated?")).luqmaFont(.headline).foregroundStyle(Theme.text) }
            .tint(Theme.link).luqmaCard()
    }
    private var sourceLinks: some View {
        VStack(alignment: .leading, spacing: 8) {
            source("Mifflin–St Jeor · 1990", "https://pubmed.ncbi.nlm.nih.gov/2305711/")
            source(diary.t("NIDDK · النشاط وحدود الاستخدام", "NIDDK · Activity and suitability"), "https://www.niddk.nih.gov/bwp")
            source(diary.t("Health Canada · نطاقات الماكروز", "Health Canada · Macro ranges"), "https://www.canada.ca/en/health-canada/services/food-nutrition/healthy-eating/dietary-reference-intakes/tables/reference-values-macronutrients.html")
            source(diary.t("CDC · نشاط البالغين", "CDC · Adult activity"), "https://www.cdc.gov/physical-activity-basics/guidelines/adults.html")
            source(diary.t("CDC · النوم", "CDC · Sleep"), "https://www.cdc.gov/sleep/about/index.html")
        }
    }
    @ViewBuilder private func source(_ title: String, _ url: String) -> some View {
        if let destination = URL(string: url) {
            Link(title, destination: destination).luqmaFont(.footnote).foregroundStyle(Theme.link).frame(minHeight: 44, alignment: .leading)
        }
    }
    private func grams(_ value: Double) -> String { DisplayFormat.decimal(value) + " " + diary.t("جم", "g") }
    private func calories(_ value: Double) -> String { DisplayFormat.decimal(value, digits: 0) + " " + diary.t("سعرة", "kcal") }
}

private struct FitnessDetailRow: View {
    let label: String
    let value: String
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label).foregroundStyle(Theme.muted)
                Spacer(minLength: 8)
                Text(value).foregroundStyle(Theme.text).multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(label).foregroundStyle(Theme.muted)
                Text(value).foregroundStyle(Theme.text)
            }
        }.luqmaFont(.footnote).fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
    }
}
