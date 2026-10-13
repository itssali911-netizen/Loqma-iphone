import SwiftUI
import UIKit

struct HealthConnectionView: View {
    @EnvironmentObject var diary: DiaryStore
    var body: some View {
        ScrollView { HealthPanel().padding(20) }
            .appBackground()
            .navigationTitle(diary.t("مزامنة النشاط", "Activity sync"))
    }
}

struct HealthPanel: View {
    @EnvironmentObject var diary: DiaryStore
    @EnvironmentObject var health: HealthService
    @State private var importingHealth = false
    @State private var showingHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            connectionCard
            if diary.state.healthEnabled && !health.signingBlocked {
                DailyActivitySummaryView()
                activityAdjustment
                readingsCard
            }
            VStack(alignment: .leading, spacing: 14) {
                Button { showingHelp = true } label: {
                    Label(diary.t("طريقة الربط وحل المشكلات", "Connection help"), systemImage: "questionmark.circle")
                }
                Divider()
                Button { importingHealth = true } label: {
                    Label(diary.t("استيراد ملف الوزن", "Import weight file"), systemImage: "square.and.arrow.down")
                }
                Text(diary.t("الاستيراد اليدوي لا يفعّل المزامنة.", "Manual import does not enable sync."))
                    .font(.caption).foregroundStyle(Theme.muted)
            }.luqmaCard()
        }
        .onAppear { health.checkInstallation(diary) }
        .sheet(isPresented: $showingHelp) { HealthConnectionHelpView() }
        .sheet(isPresented: $importingHealth) { HealthImportView() }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Apple Health", systemImage: "heart.fill").font(.headline).foregroundStyle(.pink)
            Text(diary.t("مزامنة نشاطك اليومي", "Sync your daily activity")).font(.title3.bold())
            if !health.available {
                Notice(text: diary.t("صحتي غير متاح على هذا الجهاز.", "Health is unavailable on this device."))
            } else if health.signingBlocked {
                Label(diary.t("يلزم إصلاح توقيع التطبيق", "App signing needs attention"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Notice(text: health.message ?? diary.t("النسخة المثبتة لا تحمل صلاحية صحتي.", "This installation lacks Health access."))
                Button(diary.t("خطوات تفعيل صحتي", "Health setup steps")) { showingHelp = true }
                    .buttonStyle(.borderedProminent)
            } else {
                Text(diary.t("تابع خطوات الآيفون والساعة، المسافة، دقائق التمرين وسعرات النشاط، مع الوزن والطول. اسمح بقراءة الأنواع التي تريدها؛ بياناتك تبقى على جهازك.", "Track iPhone and Watch steps, distance, exercise minutes and active calories, alongside weight and height. Allow the data types you want to read; your data stays on this device."))
                    .font(.subheadline).foregroundStyle(Theme.muted)
                if diary.state.healthEnabled {
                    Label(diary.t("التحديث التلقائي قيد التشغيل", "Automatic updates are on"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                    Button(diary.t("تحديث الآن", "Refresh now")) { Task { await health.sync(diary) } }
                        .buttonStyle(.borderedProminent).disabled(health.busy)
                    Button(diary.t("تحديث أذونات النشاط", "Update activity permissions")) { Task { await health.connect(diary) } }
                        .font(.footnote).disabled(health.busy)
                    Text(diary.t("اسمح بأنواع النشاط الجديدة. لتغيير إذن سابق: صحتي ← صورتك ← التطبيقات ← لقمة.", "Allow the new activity types. To change earlier permission: Health → your profile → Apps → Luqma."))
                        .font(.caption).foregroundStyle(Theme.muted)
                } else {
                    Button(diary.t("ربط صحتي ومزامنة النشاط", "Connect Health and sync activity")) { Task { await health.connect(diary) } }
                        .buttonStyle(.borderedProminent).disabled(health.busy)
                }
                if let message = health.message { Notice(text: message) }
            }
            if health.busy { ProgressView(diary.t("جارٍ التحديث…", "Updating…")) }
        }.luqmaCard()
    }

    private var activityAdjustment: some View {
        VStack(alignment: .leading, spacing: 14) {
            let baseline = HealthActivity.plannedCalories(diary.state, day: DayKey.today)
            Toggle(diary.t("تعديل هدف اليوم بالنشاط الزائد", "Adjust today's goal for extra activity"), isOn: Binding(
                get: { diary.state.healthSync?.adjustmentEnabled == true && baseline != nil },
                set: { enabled in
                    guard !enabled || baseline != nil else { return }
                    diary.change { state in
                        var cache = state.healthSync ?? HealthSyncState()
                        cache.adjustmentEnabled = enabled; state.healthSync = cache
                    }
                }
            )).disabled(baseline == nil)
            if let baseline {
                Text(diary.t("تتضمن خطتك بالفعل", "Your plan already includes") + " " + decimal(baseline, 0) + " " + diary.t("سعرة نشاط يوميًا. نضيف فقط ما يزيد عنها، دون جمع سعرات الخطوات والتمارين مرة ثانية.", "active calories per day. Only the excess is added; steps and workouts are not counted again."))
                    .font(.footnote).foregroundStyle(Theme.muted)
                if diary.state.healthSync?.adjustmentEnabled == true {
                    LabeledContent(diary.t("تعديل اليوم", "Today's adjustment"), value: "+" + decimal(HealthActivity.adjustment(diary.state, day: DayKey.today), 0) + " kcal")
                    LabeledContent(diary.t("هدف اليوم بعد النشاط", "Today's goal after activity"), value: decimal(diary.dailyGoals(DayKey.today).kcal, 0) + " kcal")
                }
            } else {
                Text(diary.t("افتح خطة الوزن واحفظها لحساب هدف مرتبط بمستوى نشاطك. بعد تعديل الهدف يدويًا أو استيراده، يلزم حفظ الخطة مجددًا؛ لا نفترض أن الهدف اليدوي يتضمن نشاط الخطة السابقة.", "Open and save your weight plan to calculate a goal tied to its activity level. After editing or importing a goal, save the plan again; a manual goal is not assumed to include the earlier plan's activity."))
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            Text(diary.t("اختياري، ومتوقف افتراضيًا. لا يغيّر الهدف المحفوظ أو سجل الأيام السابقة.", "Optional and off by default. Your saved goal and earlier diary days remain unchanged."))
                .font(.caption).foregroundStyle(Theme.muted)
        }.luqmaCard()
    }

    private var readingsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(diary.t("القراءات المحفوظة", "Saved readings")).font(.headline)
            if let date = health.lastSync {
                HStack {
                    Text(diary.t("آخر تحديث", "Last refreshed"))
                    Spacer()
                    Text(date, style: .relative)
                }.font(.caption).foregroundStyle(Theme.muted)
            }
            if let height = health.heightCM { LabeledContent(diary.t("الطول", "Height"), value: decimal(height) + " cm") }
            if health.readings > 0 { LabeledContent(diary.t("أيام الوزن من صحتي", "Health weight days"), value: String(health.readings)) }
            if health.lastSync == nil {
                Notice(text: diary.t("اسمح بالقراءة، ثم حدّث البيانات. إذا لم تصل قراءات، راجع الأذونات داخل صحتي.", "Allow read access, then refresh. If no readings arrive, check permissions in Health."))
            }
            if health.waitingForUnlock {
                Notice(text: diary.t("افتح قفل الآيفون لاستكمال التحديث.", "Unlock your iPhone to finish updating."))
            } else if health.backgroundStatus == .enabled {
                Text(diary.t("تحديث الخلفية مسجّل؛ يحدد iOS وقت وصوله.", "Background updates are registered; iOS controls their timing."))
                    .font(.caption).foregroundStyle(Theme.muted)
            } else if health.backgroundStatus == .limited || health.backgroundStatus == .unavailable {
                Text(diary.t("تحديث الخلفية محدود. افتح التطبيق للتحديث، وراجع المساعدة إذا استمر ذلك.", "Background updates are limited. Open the app to refresh; see Help if this persists."))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Text(diary.t("المزامنة تقرأ البيانات فقط ولا تكتب أو تحذف داخل صحتي.", "Sync only reads data; it does not write or delete Health records."))
                .font(.caption).foregroundStyle(Theme.muted)
            Button(diary.t("إيقاف التحديث التلقائي", "Stop automatic updates")) { Task { await health.disconnect(diary) } }
                .font(.footnote).disabled(health.busy)
        }.luqmaCard()
    }
}

struct DailyActivitySummaryView: View {
    @EnvironmentObject var diary: DiaryStore
    @EnvironmentObject var health: HealthService
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(diary.t("نشاط اليوم", "Today's activity"), systemImage: "figure.walk").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 16) {
                metric(diary.t("الخطوات", "Steps"), value: health.steps, suffix: "", digits: 0, symbol: "shoeprints.fill")
                metric(diary.t("المشي والجري", "Walking and running"), value: health.distanceKM, suffix: diary.t("كم", "km"), digits: 2, symbol: "point.bottomleft.forward.to.point.topright.scurvepath")
                metric(diary.t("سعرات النشاط", "Active calories"), value: health.activeCalories, suffix: "kcal", digits: 0, symbol: "flame.fill")
                metric(diary.t("دقائق التمرين", "Exercise minutes"), value: health.exerciseMinutes, suffix: diary.t("دقيقة", "min"), digits: 0, symbol: "timer")
            }
            if let count = health.workoutCount {
                LabeledContent(diary.t("التمارين المسجلة اليوم", "Workouts recorded today"), value: String(count)).font(.footnote)
            }
            if health.steps == nil && health.activeCalories == nil && health.distanceKM == nil && health.exerciseMinutes == nil {
                Text(diary.t("لم تصل بيانات نشاط اليوم. قد لا توجد قراءات أو تحتاج إلى السماح بها داخل صحتي.", "No activity readings for today have arrived. Data may be absent or need read permission in Health."))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            Text(diary.t("الآيفون والساعة عبر صحتي · يتحدث تلقائيًا عند وصول قراءات جديدة", "iPhone and Watch via Health · Updates when new readings arrive"))
                .font(.caption).foregroundStyle(Theme.muted)
        }.luqmaCard()
    }
    private func metric(_ title: String, value: Double?, suffix: String, digits: Int, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value.map { decimal($0, digits) } ?? "—").font(.title2.bold()).monospacedDigit()
                Text(suffix).font(.caption).foregroundStyle(Theme.muted)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HealthConnectionHelpView: View {
    @EnvironmentObject var diary: DiaryStore
    @EnvironmentObject var health: HealthService
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            Form {
                if health.signingBlocked {
                    Section {
                        Text(diary.t("الخطأ في توقيع النسخة المثبتة. تكرار زر الربط أو تغيير أذونات صحتي لا يمنح التطبيق صلاحية HealthKit.", "The installed app's signature lacks HealthKit. Repeated connection attempts or permission changes cannot grant that entitlement."))
                    }
                }
                Section(diary.t("١. احفظ سجلك", "1. Save your diary")) {
                    Text(diary.t("صدّر نسخة احتياطية من الإعدادات قبل إعادة التثبيت. احتفظ بنفس حساب Apple ومعرّف التطبيق لتحديث النسخة الحالية دون حذفها.", "Export a backup in Settings before reinstalling. Keep the same Apple account and app identifier to update the existing installation without deleting it."))
                    Text(health.installedIdentifier).font(.caption.monospaced()).textSelection(.enabled)
                    Button(diary.t(copied ? "نُسخ المعرّف" : "نسخ معرّف التطبيق", copied ? "Identifier copied" : "Copy app identifier")) {
                        UIPasteboard.general.string = health.installedIdentifier; copied = true
                    }
                }
                Section(diary.t("٢. وقّع بصلاحية صحتي", "2. Sign with Health access")) {
                    Text(diary.t("على ويندوز، يمكن تجربة Impactor: أضف حساب Apple نفسه، اختر ملف IPA وحدّد المعرّف المنسوخ في Identifier. الأداة تطلب الصلاحيات من Apple؛ يلزم أن يسمح بها التوقيع النهائي.", "On Windows, you can try Impactor: add the same Apple account, select the IPA and enter the copied identifier under Identifier. It requests capabilities from Apple; the final signature must allow them."))
                    Link(diary.t("تحميل Impactor من مصدره", "Download Impactor"), destination: URL(string: "https://github.com/claration/impactor/releases")!)
                    Text(diary.t("الإمكانية متاحة بحسب حساب Apple وأداة التوقيع. نجاح التثبيت وحده لا يثبت عمل صحتي.", "Availability depends on your Apple account and signing tool. Successful installation alone does not prove Health access works."))
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                Section(diary.t("٣. اسمح بالقراءة", "3. Allow read access")) {
                    Text(diary.t("بعد التثبيت، افتح لقمة ← الإعدادات ← صحتي ← ربط صحتي ومزامنة النشاط. اسمح بالخطوات والمسافة وسعرات النشاط ودقائق التمرين والتمارين والوزن والطول. إذا سبق الربط، اضغط «تحديث أذونات النشاط» للأنواع الجديدة. ثم راجع بطاقة «نشاط اليوم» واضغط «تحديث الآن».", "After installing, open Luqma → Settings → Health → Connect Health and sync activity. Allow steps, distance, active calories, exercise minutes, workouts, weight and height. If already connected, tap Update activity permissions for the new types. Review Today's activity, then tap Refresh now."))
                    Text(diary.t("الأذونات: صحتي ← صورتك ← التطبيقات ← لقمة. يقرأ لقمة فقط؛ لا يكتب أو يحذف بيانات صحتي. الوزن اليدوي المسجّل في لقمة له الأولوية في اليوم نفسه.", "Permissions: Health → your profile → Apps → Luqma. Luqma only reads; it does not write or delete Health data. A manual Luqma weight takes priority on the same day."))
                }
                Section(diary.t("إذا لم تصل البيانات", "If no data arrives")) {
                    Text(diary.t("قد تكون البيانات غير موجودة أو إذن القراءة موقوفًا؛ Apple لا يكشف رفض القراءة للتطبيق. قد تتأخر الخلفية بسبب iOS أو قفل الجهاز. استيراد ملف الوزن خيار يدوي، وليس ربطًا تلقائيًا.", "Data may be absent or read access disabled; Apple does not disclose read denial to the app. iOS and a locked device can delay background updates. Weight file import is a manual option, not an automatic connection."))
                    Link(diary.t("دليل أذونات صحتي من Apple", "Apple Health permissions guide"), destination: URL(string: "https://support.apple.com/en-us/108779")!)
                }
            }
            .appBackground()
            .navigationTitle(diary.t("تفعيل صحتي", "Health setup"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(diary.t("إغلاق", "Close")) { dismiss() } } }
        }
    }
}
