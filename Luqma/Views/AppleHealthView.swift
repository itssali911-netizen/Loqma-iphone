import SwiftUI

enum HealthCopy {
    static func issue(_ issue: HealthReadIssue, _ language: AppLanguage) -> String {
        switch issue {
        case .unavailable:
            return language.text("صحتي غير متاح على هذا الجهاز. يمكنك متابعة استخدام لقمة وإدخال بياناتك يدويًا.", "HealthKit is unavailable on this device. You can keep using Luqma and manual entries.")
        case .missingEntitlement:
            return language.text("توقيع هذه النسخة لا يتضمن صلاحية HealthKit. يلزم تثبيت نسخة بملف توقيع يسمح بها؛ تغيير أذونات صحتي وحده لا يصلح التوقيع.", "This build's provisioning profile does not allow HealthKit. Install a build signed with the capability; changing Health permissions cannot fix its signature.")
        case .deviceLocked:
            return language.text("افتح قفل الآيفون ثم اضغط تحديث لقراءة بيانات صحتي المحمية.", "Unlock your iPhone, then refresh to read protected Health data.")
        case .restricted:
            return language.text("تعذر الوصول إلى صحتي. راجع خيارات لقمة وقيود الجهاز وإعدادات توقيع النسخة. لا يمكن تحديد أذونات القراءة من هذه الرسالة.", "Health access is unavailable. Review Luqma's Health options, device restrictions and build signing. This message cannot determine individual read permissions.")
        case .queryFailed:
            return language.text("تعذّر إكمال القراءة. حاول التحديث مجددًا. لم تُستبدل البيانات المفقودة بأصفار.", "Could not finish reading. Try refreshing again. Missing readings have not been replaced with zeros.")
        case .cancelled:
            return language.text("أُلغي التحديث.", "Refresh cancelled.")
        }
    }
    static func date(_ value: Date, _ language: AppLanguage) -> String {
        let formatter = DateFormatter()
        formatter.locale = DisplayFormat.locale(language); formatter.calendar = .autoupdatingCurrent
        formatter.timeZone = .autoupdatingCurrent; formatter.dateStyle = .short; formatter.timeStyle = .short
        return DisplayFormat.westernDigits(formatter.string(from: value))
    }
}

struct HealthMetricRow: View {
    let title: String
    let unit: String
    let field: HealthReadField
    let identifier: String
    let language: AppLanguage
    var dated = false
    var digits = 1
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).luqmaFont(size: 13, weight: .semibold, relativeTo: .subheadline).foregroundStyle(Theme.text)
            if let reading = field.measurement {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(DisplayFormat.decimal(reading.value, digits: digits)).monospacedDigit().luqmaFont(size: 22, weight: .bold, relativeTo: .title2)
                        .luqmaNumericMotion(value:reading.value)
                    Text(unit).luqmaFont(size: 12, relativeTo: .caption).foregroundStyle(Theme.muted)
                }.environment(\.layoutDirection, .leftToRight).accessibilityElement(children: .combine)
                    .accessibilityIdentifier(identifier)
                if dated { Text(HealthCopy.date(reading.date, language)).luqmaFont(size: 11, relativeTo: .caption).foregroundStyle(Theme.muted) }
            } else {
                Text(unavailableText).luqmaFont(size: 13, relativeTo: .body).foregroundStyle(Theme.muted)
                    .accessibilityIdentifier(identifier)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).privacySensitive()
    }
    private var unavailableText: String {
        if case let .failed(issue) = field { return HealthCopy.issue(issue, language) }
        return language.text("لا توجد قراءة متاحة", "No available reading")
    }
}

struct HealthSettingsView: View {
    @EnvironmentObject private var diary: DiaryStore
    @EnvironmentObject private var health: AppleHealthService
    @State private var showingAccessGuide = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                explanation
                actions.luqmaMotion(.content,value:health.isWorking)
                if let issue = health.availabilityIssue ?? health.issue {
                    SandowStateAlert(text: HealthCopy.issue(issue, diary.language)).accessibilityIdentifier("health.issue")
                }
                readings
                HealthExtendedReadingsView()
                accessGuide
            }.padding(16).padding(.bottom, 20)
        }.background(HealthPalette.background.ignoresSafeArea()).sandowNavigation(diary.t("صحتي", "Apple Health"), backLabel: diary.t("رجوع", "Back"))
            .accessibilityIdentifier("health.screen")
            .luqmaFeedback(.success,trigger:health.lastSuccessfulSync){_,date in date != nil && health.snapshot?.hasReadableData == true}
            .luqmaFeedback(.error,trigger:health.issue){_,issue in issue != nil && issue != .cancelled}
            .sheet(isPresented: $showingAccessGuide) {
                NavigationStack {
                    ScrollView { accessGuide.padding(16) }
                        .background(HealthPalette.background.ignoresSafeArea())
                        .navigationTitle(diary.t("إدارة أذونات صحتي", "Manage Health access"))
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(diary.t("تم", "Done")) { showingAccessGuide = false } } }
                }
            }
    }
    private var explanation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Apple Health", systemImage: "heart.fill").luqmaFont(size: 20, weight: .bold, relativeTo: .title3).foregroundStyle(HealthPalette.accent)
            Text(diary.t("تابع الخطوات والمسافة وطاقة النشاط والراحة، والوزن والطول ونسبة الدهون والنبض والتمارين والنوم. تختار بنفسك الأنواع التي تسمح بقراءتها في نافذة صحتي الرسمية.", "Follow steps, distance, active and resting energy, weight, height, body fat, heart rate, workouts and sleep. Choose each data type yourself in Apple's native Health permission sheet."))
                .luqmaFont(size: 14, relativeTo: .body)
            Text(diary.t("قراءة فقط. لا نكتب في صحتي، ولا نغيّر إدخالاتك اليدوية أو أهداف السعرات تلقائيًا. تبقى القراءات في ذاكرة التطبيق على جهازك، ولا تدخل النسخ الاحتياطية أو التحليل أو أي خادم.", "Read only. Luqma does not write to Health or automatically change manual entries or calorie targets. Readings stay in app memory on this device, outside backups, analysis requests and servers."))
                .luqmaFont(size: 12, relativeTo: .footnote).foregroundStyle(Theme.muted)
        }.healthCard().accessibilityElement(children: .combine).accessibilityIdentifier("health.explanation")
    }
    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button { Task { await health.connect() } } label: {
                Label(diary.t(health.refreshEnabled ? "طلب الوصول مرة أخرى" : "ربط Apple Health", health.refreshEnabled ? "Request access again" : "Connect Apple Health"), systemImage: "heart.text.square")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(HealthPrimaryButtonStyle()).disabled(health.isWorking || health.availabilityIssue != nil)
                .accessibilityIdentifier("health.connect")
            Button { Task { await health.refresh() } } label: {
                Label(diary.t("تحديث القراءات", "Refresh readings"), systemImage: "arrow.clockwise").frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(LuqmaSecondaryButtonStyle()).disabled(!health.refreshEnabled || health.isWorking || health.availabilityIssue != nil)
                .accessibilityIdentifier("health.refresh")
            Button { showingAccessGuide = true } label: {
                Label(diary.t("إدارة أذونات صحتي", "Manage Health access"), systemImage: "hand.raised").frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(LuqmaSecondaryButtonStyle()).accessibilityIdentifier("health.manageAccess")
            if health.isWorking {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(diary.t(health.isAuthorizing ? "بانتظار نافذة صحتي…" : "قراءة البيانات المتاحة…", health.isAuthorizing ? "Waiting for Health…" : "Reading available data…")).luqmaFont(.footnote)
                }.accessibilityIdentifier("health.working")
                if health.isRefreshing {
                    Button(diary.t("إلغاء التحديث", "Cancel refresh")) { health.cancelRefresh() }.frame(minHeight: 44)
                }
            }
            if health.refreshEnabled {
                Text(diary.t("يُعاد فحص القراءات عند فتح التطبيق، ويتوفر التحديث اليدوي. هذا الخيار ليس تأكيدًا للسماح بجميع أنواع البيانات.", "Readings are checked when the app becomes active, with manual refresh available. This preference does not confirm access to every data type."))
                    .luqmaFont(.footnote).foregroundStyle(Theme.muted)
                Button(diary.t("إيقاف التحديث ومسح القراءات المعروضة", "Stop refresh and clear displayed readings")) { health.disconnect() }
                    .buttonStyle(LuqmaSecondaryButtonStyle()).disabled(health.isAuthorizing).accessibilityIdentifier("health.disconnect")
            }
        }.healthCard()
    }
    private var readings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(diary.t("القراءات المتاحة", "Available readings")).luqmaFont(.headline).accessibilityAddTraits(.isHeader)
            HealthMetricRow(title: diary.t("خطوات اليوم", "Today's steps"), unit: diary.t("خطوة", "steps"), field: dailyField(\.steps), identifier: "health.steps.value", language: diary.language, digits: 0)
            Divider().overlay(Theme.stroke)
            HealthMetricRow(title: diary.t("طاقة النشاط اليوم", "Today's active energy"), unit: diary.t("سعرة", "kcal"), field: dailyField(\.activeEnergy), identifier: "health.energy.value", language: diary.language)
            Divider().overlay(Theme.stroke)
            HealthMetricRow(title: diary.t("آخر وزن من صحتي", "Latest Health weight"), unit: diary.t("كجم", "kg"), field: health.snapshot?.bodyMass.sanitized(allowZero: false, now: health.referenceDate) ?? .noData, identifier: "health.weight.value", language: diary.language, dated: true)
            Divider().overlay(Theme.stroke)
            HealthMetricRow(title: diary.t("آخر طول من صحتي", "Latest Health height"), unit: diary.t("سم", "cm"), field: health.snapshot?.height.sanitized(allowZero: false, now: health.referenceDate) ?? .noData, identifier: "health.height.value", language: diary.language, dated: true)
            Text(lastCheck).luqmaFont(.footnote).foregroundStyle(Theme.muted).accessibilityIdentifier("health.lastCheck")
            if health.isRefreshing, health.snapshot != nil {
                Text(diary.t("القراءات الظاهرة من آخر فحص حتى يكتمل التحديث.", "Displayed readings are from the previous check until refresh finishes.")).luqmaFont(.footnote).foregroundStyle(Theme.muted)
            }
            Text(diary.t("القراءة الفارغة قد تعني عدم وجود سجلات أو عدم السماح بقراءتها؛ لا يكشف صحتي للتطبيق أيهما السبب. يمكنك مشاركة بعض الأنواع فقط. القيم غير المتاحة لا تُعرض كصفر.", "An empty read can mean no records or no read access; Health does not tell Luqma which. You may share only some types. Unavailable values are never displayed as zero."))
                .luqmaFont(.footnote).foregroundStyle(Theme.muted)
        }.healthCard()
    }
    private func dailyField(_ key: KeyPath<HealthReadSnapshot, HealthReadField>) -> HealthReadField {
        guard let snapshot = health.snapshot, snapshot.dailyReadingsAreCurrent(at: health.referenceDate, calendar: .autoupdatingCurrent) else { return .noData }
        return snapshot[keyPath: key]
    }
    private var lastCheck: String {
        if let value = health.snapshot?.refreshedAt { return diary.t("آخر فحص مكتمل: ", "Last completed check: ") + HealthCopy.date(value, diary.language) }
        if let value = health.lastAttempt { return diary.t("آخر محاولة تحديث: ", "Last refresh attempt: ") + HealthCopy.date(value, diary.language) }
        return diary.t("لم تُفحص القراءات بعد", "No check yet")
    }
    private var accessGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(diary.t("إدارة الوصول", "Manage access")).luqmaFont(.headline).accessibilityAddTraits(.isHeader)
            Text(diary.t("في صحتي، اضغط صورة حسابك ثم ابحث عن لقمة ضمن التطبيقات أو التطبيقات والخدمات، واختر البيانات المسموح بها. أو افتح إعدادات الآيفون > التطبيقات > صحتي > الوصول إلى البيانات والأجهزة. قد تختلف أسماء القوائم حسب إصدار iOS.", "In Health, tap your profile and find Luqma under Apps or Apps and Services, then choose the allowed data. You can also use iPhone Settings > Apps > Health > Data Access & Devices. Menu names vary by iOS version."))
                .luqmaFont(.footnote).foregroundStyle(Theme.muted)
            Text(diary.t("قد لا تظهر نافذة الأذونات مجددًا إذا سبق أن أجبت عنها. إيقاف التحديث في لقمة يمسح القراءات المعروضة فقط؛ سحب الأذونات يتم من صحتي. لا توجد مزامنة مستمرة في الخلفية.", "The permission sheet may not appear again after you have answered it. Stopping refresh in Luqma clears displayed readings only; revoke permissions in Health. No continuous background sync is promised."))
                .luqmaFont(.footnote).foregroundStyle(Theme.muted)
        }.healthCard().accessibilityIdentifier("health.accessGuide")
    }
}
