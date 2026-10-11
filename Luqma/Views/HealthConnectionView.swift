import SwiftUI
import UIKit

struct HealthConnectionView: View {
    @EnvironmentObject var diary: DiaryStore
    var body: some View {
        ScrollView { HealthPanel().padding(20) }
            .appBackground()
            .navigationTitle(diary.t("صحتي", "Apple Health"))
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
            if diary.state.healthEnabled && !health.signingBlocked { readingsCard }
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
            if !health.available {
                Notice(text: diary.t("صحتي غير متاح على هذا الجهاز.", "Health is unavailable on this device."))
            } else if health.signingBlocked {
                Label(diary.t("يلزم إصلاح توقيع التطبيق", "App signing needs attention"), systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Notice(text: health.message ?? diary.t("النسخة المثبتة لا تحمل صلاحية صحتي.", "This installation lacks Health access."))
                Button(diary.t("خطوات تفعيل صحتي", "Health setup steps")) { showingHelp = true }
                    .buttonStyle(.borderedProminent)
            } else {
                Text(diary.t("استيراد الوزن والطول والخطوات وسعرات النشاط. القراءة فقط؛ بياناتك تبقى على جهازك.", "Read weight, height, steps and active calories. Read-only; your data stays on this device."))
                    .font(.subheadline).foregroundStyle(Theme.muted)
                if diary.state.healthEnabled {
                    Label(diary.t("التحديث التلقائي قيد التشغيل", "Automatic updates are on"), systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                    Button(diary.t("تحديث الآن", "Refresh now")) { Task { await health.sync(diary) } }
                        .buttonStyle(.borderedProminent).disabled(health.busy)
                } else {
                    Button(diary.t("ربط صحتي", "Connect Health")) { Task { await health.connect(diary) } }
                        .buttonStyle(.borderedProminent).disabled(health.busy)
                }
                if let message = health.message { Notice(text: message) }
            }
            if health.busy { ProgressView(diary.t("جارٍ التحديث…", "Updating…")) }
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
            if let steps = health.steps { LabeledContent(diary.t("خطوات اليوم", "Today's steps"), value: decimal(steps, 0)) }
            if let calories = health.activeCalories { LabeledContent(diary.t("سعرات النشاط", "Active calories"), value: decimal(calories, 0) + " kcal") }
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
            Text(diary.t("سعرات النشاط للعرض ولا تُضاف مرة أخرى إلى الخطة.", "Active calories are informational and are not added again to your plan."))
                .font(.caption).foregroundStyle(Theme.muted)
            Button(diary.t("إيقاف التحديث التلقائي", "Stop automatic updates")) { Task { await health.disconnect(diary) } }
                .font(.footnote).disabled(health.busy)
        }.luqmaCard()
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
                    Text(diary.t("بعد التثبيت، افتح لقمة ← الإعدادات ← صحتي ← ربط صحتي. اسمح بقراءة الوزن والطول والخطوات وسعرات النشاط. ثم أضف قراءة وزن جديدة في صحتي واضغط «تحديث الآن» للتحقق.", "After installing, open Luqma → Settings → Health → Connect Health. Allow weight, height, steps and active calories. Add a new weight in Health, then tap Refresh now to check it arrives."))
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
