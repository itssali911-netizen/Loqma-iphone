import SwiftUI

struct GeminiSettingsView: View {
    @EnvironmentObject var diary: DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var configured = GeminiCredentialStore.isConfigured
    @State private var message: String?
    @State private var resetting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(diary.t("تحليل الوجبة", "Meal analysis"), systemImage: "sparkles").font(.headline)
                    Label(diary.t(configured ? "جاهز على هذا الجهاز" : "يحتاج تفعيلًا على هذا الجهاز",
                                  configured ? "Ready on this device" : "Activation needed on this device"),
                          systemImage: configured ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(configured ? Theme.accent : Theme.muted)
                    Text(diary.t("تظهر السعرات والماكروز بعد تحليل الصورة. يمكنك تعديل الكمية قبل حفظ الوجبة.",
                                 "Calories and macros appear after photo analysis. You can adjust the amount before saving the meal."))
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                if let message { Section { Text(message).font(.footnote) } }
                Section {
                    DisclosureGroup(diary.t("إعدادات متقدمة", "Advanced settings")) {
                        if !configured {
                            SecureField(diary.t("مفتاح الاتصال", "Connection key"), text: $key)
                                .keyboardType(.asciiCapable).textInputAutocapitalization(.never).autocorrectionDisabled().privacySensitive()
                            Button(diary.t("تفعيل الاتصال", "Activate connection")) { save() }
                                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Link(diary.t("إنشاء مفتاح اتصال", "Create a connection key"), destination: URL(string: "https://aistudio.google.com/api-keys")!)
                        } else {
                            Button(diary.t("إعادة ضبط الاتصال", "Reset connection"), role: .destructive) { resetting = true }
                        }
                    }
                }
                Section {
                    Text(diary.t("تُرسل صورة الوجبة والوصف فقط إلى خدمة التحليل. يبقى سجلك وبيانات صحتي على جهازك.",
                                 "Only the meal photo and description are sent to the analysis service. Your diary and Health data stay on your device."))
                        .font(.footnote).foregroundStyle(Theme.muted)
                    Link(diary.t("سياسة خدمة التحليل", "Analysis service policy"), destination: URL(string: "https://ai.google.dev/gemini-api/terms")!)
                }
            }.appBackground().navigationTitle(diary.t("تحليل الوجبة", "Meal analysis"))
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button(diary.t("تم", "Done")) { dismiss() } } }
        }
        .confirmationDialog(diary.t("إعادة ضبط اتصال التحليل؟", "Reset the analysis connection?"), isPresented: $resetting, titleVisibility: .visible) {
            Button(diary.t("إعادة ضبط", "Reset"), role: .destructive) {
                do { try GeminiCredentialStore.clear(); configured = false; message = nil }
                catch { diary.report(AppError.invalid("تعذّر إعادة ضبط الاتصال. افتح قفل الجهاز وحاول مجددًا.", "The connection could not be reset. Unlock the device and retry.")) }
            }
            Button(diary.t("إلغاء", "Cancel"), role: .cancel) {}
        } message: {
            Text(diary.t("ستحتاج إعادة تفعيل الاتصال على هذا الجهاز. يبقى سجلك محفوظًا.",
                         "You will need to reactivate the connection on this device. Your diary stays saved."))
        }
    }

    private func save() {
        do {
            try GeminiCredentialStore.save(key); key = ""; configured = true
            message = diary.t("التحليل جاهز. ارجع إلى صورة الوجبة وابدأ التحليل.", "Analysis is ready. Return to the meal photo and analyze.")
        } catch {
            message = diary.t("تعذّر تفعيل الاتصال. راجع مفتاح الاتصال وافتح قفل الجهاز ثم حاول مجددًا.", "The connection could not be activated. Check the connection key, unlock the device, and retry.")
        }
    }
}
