import SwiftUI
import UniformTypeIdentifiers

@MainActor struct HealthImportView: View {
    @EnvironmentObject var diary: DiaryStore
    @Environment(\.dismiss) var dismiss
    @State private var choosing = false
    @State private var busy = false
    @State private var result: HealthImportResult?
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(diary.t("استيراد يدوي من صحتي", "Manual Health import")).font(.headline)
                    Notice(text: diary.t("ينقل الوزن من ملف فقط. لا يفعّل الربط أو التحديث التلقائي.", "Imports weight from a file. It does not enable Health access or automatic updates."))
                    Text(diary.t("١. افتح صحتي ← صورة حسابك ← تصدير جميع البيانات الصحية، واحفظ ملف ZIP في «الملفات».\n٢. في «الملفات»، اضغط ملف ZIP لفك ضغطه.\n٣. اختر ملف apple_health_export/export.xml من الزر أدناه.", "1. Open Health → your profile → Export All Health Data. Save the ZIP to Files.\n2. In Files, tap the ZIP to unzip it.\n3. Choose apple_health_export/export.xml below."))
                    Button(diary.t("اختيار export.xml", "Choose export.xml")) { choosing = true }.disabled(busy)
                    if busy { ProgressView(diary.t("قراءة سجل الوزن…", "Reading weight records…")) }
                    if let error { Text(error).foregroundStyle(.orange) }
                }
                if let result {
                    Section(diary.t("معاينة الاستيراد", "Import preview")) {
                        LabeledContent(diary.t("أيام الوزن", "Weight days"), value: String(result.weights.count))
                        if let first = result.weights.first, let last = result.weights.last { Text(first.day + " — " + last.day).font(.caption) }
                        if let latest = result.weights.last { LabeledContent(diary.t("آخر وزن", "Latest weight"), value: decimal(latest.kg, 1) + " kg") }
                        if let height = result.heightCM { LabeledContent(diary.t("آخر طول (للمراجعة)", "Latest height (for review)"), value: decimal(height, 1) + " cm") }
                        Notice(text: diary.t("سيُدمج الوزن فقط، ولن تُستبدل قراءاتك اليدوية. الطول للعرض ويمكنك إدخاله في خطة الوزن. الاستيراد محلي؛ حدّث الملف عند إضافة قراءات جديدة لصحتي.", "Only weight is merged; manual readings take priority. Height is shown for use in your weight plan. Import stays on-device; re-export to include new Health readings."))
                        Button(diary.t("تأكيد استيراد الوزن", "Confirm weight import")) {
                            if diary.importHealthWeights(result.weights) { dismiss() }
                        }.disabled(result.weights.isEmpty)
                    }
                }
            }.appBackground().navigationTitle(diary.t("بيانات صحتي", "Health data"))
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button(diary.t("إغلاق", "Close")) { task?.cancel(); dismiss() } } }
                .fileImporter(isPresented: $choosing, allowedContentTypes: [.xml], allowsMultipleSelection: false) { value in
                    switch value { case .success(let urls): if let url = urls.first { read(url) }; case .failure(let error): self.error = error.localizedDescription }
                }
                .onDisappear { task?.cancel() }
        }
    }
    private func read(_ url: URL) {
        busy = true; error = nil; result = nil
        task = Task {
            let worker = Task.detached {
                let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return try HealthImport.read(url)
            }
            do {
                let parsed = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation(); result = parsed
            } catch is CancellationError {} catch { self.error = (error as? AppError)?.message(diary.language) ?? error.localizedDescription }
            busy = false
        }
    }
}
