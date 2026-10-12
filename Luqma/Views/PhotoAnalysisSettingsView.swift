import SwiftUI

struct PhotoAnalysisSettingsView: View {
    @EnvironmentObject var diary: DiaryStore
    @State private var key = ""
    @State private var hasKey = false
    @State private var checking = false
    @State private var message: String?
    @State private var connectionTask: Task<Void, Never>?
    var body: some View {
        Form {
            Section(diary.t("التحليل عبر الإنترنت", "Online analysis")) {
                Text(GeminiMeal.displayName).font(.headline)
                Notice(text: diary.t("عند الضغط على تحليل تُرسل صورة الوجبة ووصفها فقط إلى Google. تُحذف بيانات موقع الصورة قبل الإرسال. الكميات تقديرية؛ راجع الأصناف واختر منتجات الطعام قبل التسجيل.",
                                     "Tapping Analyze sends only the meal photo and description to Google. Photo location metadata is removed first. Portions are estimates; review foods and select food products before logging."))
            }
            Section(diary.t("مفتاح Gemini الشخصي", "Your personal Gemini key")) {
                if hasKey { Label(diary.t("مفتاح محفوظ على هذا الجهاز", "Key saved on this device"), systemImage: "key.fill") }
                SecureField(diary.t(hasKey ? "مفتاح جديد للاستبدال" : "ألصق مفتاح API هنا", hasKey ? "New replacement key" : "Paste API key here"), text: $key)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .privacySensitive().disabled(checking)
                Button(diary.t("حفظ المفتاح", "Save key")) { save() }.disabled(key.isEmpty || checking)
                if hasKey {
                    Button(diary.t("فحص الاتصال", "Check connection")) { check() }.disabled(checking || !key.isEmpty)
                    Button(diary.t("حذف المفتاح", "Remove key"), role: .destructive) {
                        do { try GeminiKeyStore.delete(); hasKey = false; key = ""; message = diary.t("حُذف المفتاح من الجهاز.", "Key removed from this device.") }
                        catch { report(error) }
                    }.disabled(checking)
                }
                if checking { ProgressView(diary.t("فحص الاتصال…", "Checking connection…")) }
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
            Section {
                Link(diary.t("إنشاء مفتاح في Google AI Studio", "Create a key in Google AI Studio"), destination: URL(string: "https://aistudio.google.com/apikey")!)
                Link(diary.t("أسعار Gemini وحدود الاستخدام", "Gemini pricing and usage limits"), destination: URL(string: "https://ai.google.dev/gemini-api/docs/pricing")!)
                Notice(text: diary.t("الاستخدام يتبع حصة حسابك وخطة Google وقد تترتب عليه رسوم. المفتاح محفوظ في Keychain لهذا الجهاز ولا يدخل في النسخة الاحتياطية. لا تحتاج إرساله لأحد. فحص الاتصال يتحقق من توفر النموذج فقط ولا يحلل صورة.",
                                     "Usage follows your Google quota and plan and may incur charges. The key is stored in this device's Keychain and excluded from backups. Keep it private. Connection check verifies model access only; it does not analyze a photo."))
            }
        }
        .appBackground().navigationTitle(diary.t("تحليل الصور", "Photo analysis"))
        .onAppear { do { hasKey = try GeminiKeyStore.read() != nil } catch { report(error) } }
        .onDisappear { connectionTask?.cancel(); key = "" }
    }
    private func report(_ error: Error) {
        message = (error as? AppError)?.message(diary.language) ?? diary.t("تعذّر إكمال الإعداد. حاول مجددًا.", "Setup could not be completed. Retry.")
    }
    private func save() {
        do {
            try GeminiKeyStore.save(key); key = ""; hasKey = true
            message = diary.t("حُفظ المفتاح. يمكنك فحص الاتصال ثم تحليل وجبة.", "Key saved. Check connection, then analyze a meal.")
        } catch { report(error) }
    }
    private func check() {
        checking = true; message = nil
        connectionTask = Task { @MainActor in
            defer { checking = false; connectionTask = nil }
            do {
                guard let saved = try GeminiKeyStore.read() else { return }
                try await CloudPhotoAnalyzer.client().checkConnection(key: saved)
                try Task.checkCancellation()
                message = diary.t("الاتصال متاح. جودة تحليل الوجبات تحتاج تجربة صورة.", "Connection available. Meal recognition quality still needs a photo test.")
            } catch is CancellationError {
            } catch { if !Task.isCancelled { report(error) } }
        }
    }
}
