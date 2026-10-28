import SwiftUI
import Charts

/// The release's V5 palette is scoped to Health; approved meal screens stay intact.
enum HealthPalette {
    static let background = Color(red: 17/255.0, green: 20/255.0, blue: 22/255.0)
    static let card = Color(red: 34/255.0, green: 40/255.0, blue: 43/255.0)
    static let accent = Color(red: 215/255.0, green: 137/255.0, blue: 87/255.0)
}
extension View {
    func healthCard() -> some View {
        padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(HealthPalette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
struct HealthPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.luqmaFont(.headline).frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, 12).foregroundStyle(HealthPalette.background)
            .background(HealthPalette.accent.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 14))
            .luqmaPressFeedback(configuration.isPressed)
    }
}

struct HealthExtendedReadingsView: View {
    @EnvironmentObject private var diary: DiaryStore
    @EnvironmentObject private var health: AppleHealthService
    private var details: HealthReadDetails { health.snapshot?.details ?? .empty }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(status).luqmaFont(.headline).accessibilityIdentifier("health.syncStatus")
                .contentTransition(.opacity).luqmaMotion(.content,value:status)
            if let date = health.lastSuccessfulSync {
                Text(diary.t("آخر مزامنة بها بيانات: ", "Last sync with readings: ") + HealthCopy.date(date, diary.language))
                    .luqmaFont(.footnote).foregroundStyle(Theme.muted).accessibilityIdentifier("health.lastSuccessfulSync")
            }
            HStack(spacing: 8) {
                ForEach(HealthHistoryRange.allCases, id: \.rawValue) { range in
                    Button { Task { await health.setHistoryDays(range.rawValue) } } label: {
                        Text("\(range.rawValue) " + diary.t("يوم", "days")).luqmaFont(.caption)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(health.historyDays == range.rawValue ? HealthPalette.accent : HealthPalette.background, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(health.historyDays == range.rawValue ? HealthPalette.background : Theme.text)
                    }.buttonStyle(LuqmaPressStyle()).disabled(health.isAuthorizing)
                        .accessibilityIdentifier("health.range.\(range.rawValue)")
                }
            }.luqmaMotion(.selection,value:health.historyDays).luqmaFeedback(.selection,trigger:health.historyDays)
            Text(diary.t("القراءات على جهازك فقط. تُراجع الفترة عند فتح التطبيق أو التحديث اليدوي؛ التغييرات أثناء الاستخدام تُحدّث تدريجيًا.", "Readings stay on your device. Opening the app or refreshing rechecks this range; changes while in use update incrementally."))
                .luqmaFont(.footnote).foregroundStyle(Theme.muted)
            HealthMetricRow(title: diary.t("مسافة اليوم", "Today's walking/running distance"), unit: diary.t("كم", "km"), field: scaled(daily(details.walkingDistance), by: 0.001), identifier: "health.distance.value", language: diary.language)
            HealthMetricRow(title: diary.t("طاقة الراحة اليوم", "Today's resting energy"), unit: diary.t("سعرة", "kcal"), field: daily(details.basalEnergy), identifier: "health.basal.value", language: diary.language)
            HealthMetricRow(title: diary.t("آخر نسبة دهون", "Latest body fat"), unit: "%", field: details.bodyFatPercentage, identifier: "health.bodyFat.value", language: diary.language, dated: true)
            HealthMetricRow(title: diary.t("آخر نبض", "Latest heart rate"), unit: diary.t("نبضة/دقيقة", "bpm"), field: details.heartRate, identifier: "health.heart.value", language: diary.language, dated: true, digits: 0)
            HealthMetricRow(title: diary.t("نوم اليوم", "Sleep during today's calendar day"), unit: diary.t("ساعة", "hours"), field: sleepField, identifier: "health.sleep.value", language: diary.language)
            if !details.queryIssues.isEmpty {
                Text(diary.t("تعذّرت بعض قراءات الفترة. القيم المفقودة لا تثبت رفض إذن القراءة.", "Some history queries could not complete. Missing values do not confirm read-permission denial."))
                    .luqmaFont(.footnote).foregroundStyle(Theme.muted)
            }
            Text(diary.t("مزامنة الواجهة الأمامية مفعّلة عند السماح بالقراءة. هذه النسخة لا تطلب صلاحية مزامنة الخلفية ولا تعد بتحديث فوري.", "Foreground refresh is used when readings are available. This build does not request background delivery or promise immediate updates."))
                .luqmaFont(.footnote).foregroundStyle(Theme.muted)
        }.healthCard().privacySensitive()
        HealthWeightHistoryView(weights: details.weights)
        HealthWorkoutListView(workouts: details.workouts)
        HealthDailyHistoryView(days: details.daily)
    }
    private func daily(_ field: HealthReadField) -> HealthReadField {
        health.snapshot?.dailyReadingsAreCurrent(at: health.referenceDate, calendar: .autoupdatingCurrent) == true ? field : .noData
    }
    private func scaled(_ field: HealthReadField, by factor: Double) -> HealthReadField {
        guard let value = field.measurement else { return field }
        return .value(HealthMeasurement(value: value.value * factor, date: value.date))
    }
    private var sleepField: HealthReadField {
        if let issue = details.sleepIssue { return .failed(issue) }
        guard let seconds = HealthSleepUnion.availableDuration(details.sleep, on: health.referenceDate,
            calendar: .autoupdatingCurrent, now: health.referenceDate) else { return .noData }
        return .value(HealthMeasurement(value: seconds/3600, date: health.referenceDate))
    }
    private var status: String {
        if health.isAuthorizing { return diary.t("طلب الأذونات", "Requesting permissions") }
        if health.isRefreshing { return diary.t("جارٍ استيراد البيانات", "Importing readings") }
        if health.availabilityIssue != nil || health.issue != nil { return diary.t("تعذّر الوصول للبيانات", "Readings unavailable") }
        if !health.refreshEnabled { return health.hasConfigured ? diary.t("توقفت المزامنة", "Sync stopped") : diary.t("غير مهيأ للربط", "Not configured") }
        if health.snapshot?.hasReadableData == true { return diary.t("تمت مزامنة بيانات متاحة", "Available readings synchronized") }
        return diary.t("لا توجد بيانات متاحة", "No available readings")
    }
}

struct HealthWeightHistoryView: View {
    @EnvironmentObject private var diary: DiaryStore
    let weights: [HealthWeightRecord]
    var body: some View {
        if !weights.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(diary.t("تغيّر الوزن من صحتي", "Health weight trend")).luqmaFont(.headline)
                if weights.count > 1 {
                    Chart(weights) { record in
                        LineMark(x: .value("Date", record.date), y: .value("kg", record.kg)).foregroundStyle(HealthPalette.accent)
                    }.frame(height: 140).luqmaMotion(.content,value:weights).accessibilityLabel(diary.t("اتجاه قراءات الوزن المتاحة من صحتي", "Trend of available Health weight readings"))
                }
                if let latest = weights.last {
                    Text(DisplayFormat.decimal(latest.kg, digits: 1) + " " + diary.t("كجم", "kg") + " · " + HealthCopy.date(latest.date, diary.language))
                        .luqmaFont(.subheadline).monospacedDigit()
                        .contentTransition(.opacity).luqmaMotion(.content,value:latest)
                }
                Text(diary.t("هذه قراءات صحتي؛ لا تستبدل سجل الوزن اليدوي أو تعدّل هدف السعرات.", "These Health readings do not replace manual weights or adjust calorie goals."))
                    .luqmaFont(.footnote).foregroundStyle(Theme.muted)
            }.healthCard().privacySensitive().accessibilityIdentifier("health.weightHistory")
        }
    }
}

struct HealthWorkoutListView: View {
    @EnvironmentObject private var diary: DiaryStore
    let workouts: [HealthWorkoutRecord]
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(diary.t("التمارين المسجلة", "Recorded workouts")).luqmaFont(.headline)
            if workouts.isEmpty {
                Text(diary.t("لا توجد قراءة متاحة", "No available reading")).luqmaFont(.footnote).foregroundStyle(Theme.muted)
            }
            ForEach(Array(workouts.suffix(20).reversed())) { record in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title(record.kind)).luqmaFont(.subheadline)
                        Spacer(minLength: 8)
                        Text(DisplayFormat.decimal(record.durationSeconds/60, digits: 0) + " " + diary.t("دقيقة", "min")).luqmaFont(.subheadline).monospacedDigit()
                            .luqmaNumericMotion(value:record.durationSeconds/60)
                    }
                    Text(HealthCopy.date(record.start, diary.language)).luqmaFont(.caption).foregroundStyle(Theme.muted)
                }.luqmaMotionTransition()
            }
            Text(diary.t("لا نضيف سعرات التمرين إلى طاقة النشاط مرة ثانية.", "Workout energy is not added again to active-energy totals."))
                .luqmaFont(.footnote).foregroundStyle(Theme.muted)
        }.healthCard().privacySensitive().accessibilityIdentifier("health.workouts")
            .luqmaMotion(.content,value:workouts.suffix(20).map(\.id))
    }
    private func title(_ kind: HealthWorkoutKind) -> String {
        switch kind {
        case .walking: return diary.t("مشي", "Walking")
        case .running: return diary.t("جري", "Running")
        case .cycling: return diary.t("دراجة", "Cycling")
        case .swimming: return diary.t("سباحة", "Swimming")
        case .strength: return diary.t("تمارين مقاومة", "Strength training")
        case .yoga: return diary.t("يوغا", "Yoga")
        case .other: return diary.t("تمرين", "Workout")
        }
    }
}

struct HealthDailyHistoryView: View {
    @EnvironmentObject private var diary: DiaryStore
    @State private var expanded = false
    let days: [HealthDailyActivity]
    var body: some View {
        DisclosureGroup(diary.t("سجل النشاط اليومي", "Daily activity history"),isExpanded:$expanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(days.reversed())) { day in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(DisplayFormat.westernDigits(day.idDate)).luqmaFont(.caption).monospacedDigit()
                        Text(diary.t("الخطوات: ", "Steps: ") + value(day.steps, digits: 0) + " · " + diary.t("طاقة النشاط: ", "Active kcal: ") + value(day.activeEnergy, digits: 0))
                            .luqmaFont(.footnote).foregroundStyle(Theme.muted)
                            .contentTransition(.opacity).luqmaMotion(.content,value:day)
                    }.luqmaMotionTransition()
                }
            }.padding(.top, 12).luqmaMotion(.content,value:days.map(\.id))
        }.luqmaFont(.headline).healthCard().privacySensitive().accessibilityIdentifier("health.dailyHistory")
            .luqmaMotion(.content,value:expanded)
    }
    private func value(_ field: HealthReadField, digits: Int) -> String {
        field.measurement.map { DisplayFormat.decimal($0.value, digits: digits) } ?? diary.t("غير متاح", "Unavailable")
    }
}

struct AppleHealthProgressCard: View {
    @EnvironmentObject private var health: AppleHealthService
    @EnvironmentObject private var diary: DiaryStore
    var body: some View {
        if health.refreshEnabled {
            VStack(alignment: .leading, spacing: 14) {
                NavigationLink { HealthSettingsView() } label: {
                    HStack { Label("Apple Health", systemImage: "heart.fill"); Spacer(); Image(systemName: "chevron.forward") }
                        .luqmaFont(.headline).foregroundStyle(HealthPalette.accent)
                }.buttonStyle(LuqmaPressStyle())
                HealthMetricRow(title: diary.t("خطوات اليوم", "Today's steps"), unit: diary.t("خطوة", "steps"), field: daily(health.snapshot?.steps), identifier: "progress.health.steps", language: diary.language, digits: 0)
                HealthMetricRow(title: diary.t("طاقة النشاط", "Active energy"), unit: diary.t("سعرة", "kcal"), field: daily(health.snapshot?.activeEnergy), identifier: "progress.health.energy", language: diary.language)
                if let value = daily(health.snapshot?.details.walkingDistance).measurement {
                    Text(diary.t("المسافة: ", "Distance: ") + DisplayFormat.decimal(value.value/1000, digits: 2) + " " + diary.t("كم", "km")).luqmaFont(.subheadline).monospacedDigit()
                        .luqmaNumericMotion(value:value.value/1000)
                }
                if let weight = health.snapshot?.bodyMass.measurement {
                    Text(diary.t("آخر وزن من صحتي: ", "Latest Health weight: ") + DisplayFormat.decimal(weight.value, digits: 1) + " " + diary.t("كجم", "kg")).luqmaFont(.subheadline).monospacedDigit()
                        .luqmaNumericMotion(value:weight.value)
                }
                Text(diary.t("الطاقة المحروقة مستقلة عن سعرات الطعام وهدفك اليومي.", "Energy burned is separate from food calories and your daily target."))
                    .luqmaFont(.footnote).foregroundStyle(Theme.muted)
                HealthWeightHistoryView(weights: health.snapshot?.details.weights ?? [])
                HealthWorkoutListView(workouts: Array((health.snapshot?.details.workouts ?? []).suffix(3)))
            }.healthCard().privacySensitive().accessibilityIdentifier("health.summary")
        }
    }
    private func daily(_ field: HealthReadField?) -> HealthReadField {
        health.snapshot?.dailyReadingsAreCurrent(at: health.referenceDate, calendar: .autoupdatingCurrent) == true ? field ?? .noData : .noData
    }
}
