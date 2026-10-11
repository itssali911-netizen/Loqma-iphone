import SwiftUI
import UniformTypeIdentifiers

struct BackupDocument:FileDocument {
    static var readableContentTypes:[UTType]{[.json]}
    var data:Data
    init(data:Data){self.data=data}
    init(configuration:ReadConfiguration) throws {guard let d=configuration.file.regularFileContents else{throw AppError.invalid("الملف غير صالح.","Invalid file.")};data=d}
    func fileWrapper(configuration:WriteConfiguration) throws -> FileWrapper {FileWrapper(regularFileWithContents:data)}
}
struct SettingsView:View {
    @EnvironmentObject var diary:DiaryStore
    @EnvironmentObject var health:HealthService
    @State private var goals=false
    var body:some View {
        Form{
            Section(diary.t("أهدافي","My goals")){
                Button{goals=true}label:{Label(diary.t("السعرات والماكروز","Calories and macros"),systemImage:"target")}
                NavigationLink{PlanView()}label:{Label(diary.t("خطة الوزن","Weight plan"),systemImage:"chart.line.uptrend.xyaxis")}
            }
            Section(diary.t("التفضيلات","Preferences")){
                Picker(diary.t("اللغة","Language"),selection:Binding(get:{diary.language},set:{value in diary.change{$0.language=value}})){Text("العربية").tag(AppLanguage.ar);Text("English").tag(AppLanguage.en)}.pickerStyle(.menu)
            }
            Section(diary.t("الربط والبيانات","Connections and data")){
                NavigationLink{HealthConnectionView()}label:{
                    HStack{Label(diary.t("صحتي","Apple Health"),systemImage:"heart");Spacer();Text(health.signingBlocked ? diary.t("يحتاج إعداد","Setup needed") : (diary.state.healthEnabled ? diary.t("مفعّل","Enabled"):diary.t("غير مربوط","Not connected"))).font(.caption).foregroundStyle(.secondary)}
                }
                NavigationLink{BackupSettingsView()}label:{Label(diary.t("النسخ الاحتياطي والنقل","Backup and transfer"),systemImage:"externaldrive")}
            }
            Section{
                NavigationLink{AboutLuqmaView()}label:{Label(diary.t("حول لُقمة والخصوصية","About Luqma and privacy"),systemImage:"info.circle")}
            }
        }.appBackground().navigationTitle(diary.t("الإعدادات","Settings"))
            .sheet(isPresented:$goals){GoalEditor()}
    }
}
private struct BackupSettingsView:View {
    @EnvironmentObject var diary:DiaryStore
    @State private var exporting=false
    @State private var importing=false
    @State private var document=BackupDocument(data:Data())
    @State private var pending:DiarySnapshot?
    @State private var importingBusy=false
    var body:some View {
        Form{
            Section(diary.t("بياناتي","My data")){
                Button{do{document=BackupDocument(data:try Backup.encode(diary.state));exporting=true}catch{diary.report(error)}}label:{Label(diary.t("تصدير نسخة احتياطية","Export backup"),systemImage:"square.and.arrow.up")}
                Button{importing=true}label:{Label(diary.t("استيراد نسخة من الموقع أو التطبيق","Import a website or app backup"),systemImage:"square.and.arrow.down")}.disabled(importingBusy)
                if importingBusy{ProgressView()}
            }
            Section{
                Notice(text:diary.t("صدّر نسخة لحفظ بياناتك أو نقلها إلى جهاز آخر. عند الاستيراد تُدمج البيانات، وتُحدَّث السجلات المطابقة دون حذف باقي سجلك.","Export a backup to save your data or move it to another device. Import merges the data and updates matching records without deleting the rest of your diary."))
            }
        }.appBackground().navigationTitle(diary.t("النسخ الاحتياطي","Backup"))
            .fileExporter(isPresented:$exporting,document:document,contentType:.json,defaultFilename:"luqma-backup-"+DayKey.today){if case let .failure(error)=$0{diary.report(error)}}
            .fileImporter(isPresented:$importing,allowedContentTypes:[.json],allowsMultipleSelection:false){result in
                switch result{case .success(let urls):if let url=urls.first{read(url)};case .failure(let error):diary.report(error)}
            }
            .sheet(isPresented:Binding(get:{pending != nil},set:{if !$0{pending=nil}})){if let snapshot=pending{ImportPreview(snapshot:snapshot){if diary.importBackup(snapshot){pending=nil;return true};return false}}}
    }
    private func read(_ url:URL){importingBusy=true
        Task{do{let snapshot=try await Task.detached{let scoped=url.startAccessingSecurityScopedResource();defer{if scoped{url.stopAccessingSecurityScopedResource()}};return try Backup.decode(Data(contentsOf:url,options:.mappedIfSafe))}.value;pending=snapshot}catch{diary.report(error)};importingBusy=false}
    }
}
private struct AboutLuqmaView:View {
    @EnvironmentObject var diary:DiaryStore
    var body:some View {
        Form{
            Section(diary.t("لُقمة","Luqma")){
                Text(diary.t("الإصدار ","Version ") + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.4"))
            }
            Section(diary.t("الخصوصية","Privacy")){
                Notice(text:diary.t("سجلك محفوظ على الجهاز. البحث الخارجي وتنزيل نماذج الصور أول مرة يحتاجان الإنترنت. الصور وبيانات صحتي لا تُرفع إلى خادم.","Your diary is stored on the device. Online search and initial image-model downloads need internet. Photos and Health data are not uploaded."))
            }
            Section(diary.t("مصادر الطعام","Food sources")){
                Link("Open Food Facts",destination:URL(string:"https://world.openfoodfacts.org")!)
            }
        }.appBackground().navigationTitle(diary.t("حول لُقمة","About Luqma"))
    }
}
struct ImportPreview:View {
    let snapshot:DiarySnapshot;let apply:()->Bool
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dismiss) var dismiss
    var body:some View {NavigationStack{Form{Section(diary.t("البيانات التي ستُدمج","Data to merge")){row(diary.t("الأطعمة المسجلة","Diary entries"),snapshot.entries.count);row(diary.t("الوصفات والوجبات","Recipes and meals"),snapshot.recipes.count);row(diary.t("قراءات الوزن","Weight readings"),snapshot.weights.count);row(diary.t("المنتجات المحفوظة","Saved products"),snapshot.products.count)};Section{Notice(text:diary.t("ستُعتمد أهداف السعرات من النسخة. السجل الحالي يبقى محفوظًا، والمطابق يُحدَّث. صلاحيات صحتي وإعداد اللغة الحالية لا تتغير.","Calorie goals will use the backup values. Existing records remain, matching records update. Health access and the current language stay as they are."));Button(diary.t("تأكيد الاستيراد","Confirm import")){if apply(){dismiss()}}}}.appBackground().navigationTitle(diary.t("استيراد النسخة","Import backup")).toolbar{ToolbarItem(placement:.cancellationAction){Button(diary.t("إلغاء","Cancel")){dismiss()}}}}}
    private func row(_ title:String,_ n:Int) -> some View {HStack{Text(title);Spacer();Text(String(n)).foregroundStyle(.secondary)}}
}
