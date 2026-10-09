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
    @State private var goals=false,exporting=false,importing=false,document=BackupDocument(data:Data()),pending:DiarySnapshot?,importingBusy=false
    var body:some View {
        Form{
            Section(diary.t("التطبيق","App")){
                Picker(diary.t("اللغة","Language"),selection:Binding(get:{diary.language},set:{value in diary.change{$0.language=value}})){Text("العربية").tag(AppLanguage.ar);Text("English").tag(AppLanguage.en)}
                Button(diary.t("أهداف السعرات والماكروز","Calorie and macro goals")){goals=true}
                NavigationLink(diary.t("خطة الوزن • NIDDK","Weight plan • NIDDK")){PlanView()}
            }
            Section("Apple Health"){HealthPanel().listRowBackground(Theme.background)}
            Section(diary.t("بياناتي","My data")){
                Button{do{document=BackupDocument(data:try Backup.encode(diary.state));exporting=true}catch{diary.report(error)}}label:{Label(diary.t("تصدير نسخة احتياطية","Export backup"),systemImage:"square.and.arrow.up")}
                Button{importing=true}label:{Label(diary.t("استيراد نسخة من الموقع أو التطبيق","Import a website or app backup"),systemImage:"square.and.arrow.down")}.disabled(importingBusy)
                if importingBusy{ProgressView()}
                Notice(text:diary.t("لنقل السجل: صدّر نسخة JSON من إعدادات الموقع، ثم استوردها هنا. يُدمج السجل والوصفات والوزن والمنتجات دون حذف القائمة الحالية؛ السجلات المطابقة تُحدَّث من النسخة.","To migrate: export JSON from website Settings, then import it here. Diary, recipes, weights and products are merged without deleting the current list; matching records update from the backup."))
            }
            Section(diary.t("حول لُقمة","About Luqma")){
                Text(diary.t("تطبيق آيفون أصلي • الإصدار ١٫٠","Native iPhone app • Version 1.0"))
                Notice(text:diary.t("سجلك محفوظ على الجهاز ولا يحتاج اشتراك ChatGPT. البحث الخارجي وتنزيل نماذج الصور أول مرة يحتاجان الإنترنت. الصور وبيانات صحتي لا تُرفع إلى خادم.","Your diary is stored on the device and needs no ChatGPT subscription. Online search and initial image-model downloads need internet. Photos and Health data are not uploaded."))
                Link("Open Food Facts",destination:URL(string:"https://world.openfoodfacts.org")!)
                Link("USDA FoodData Central",destination:URL(string:"https://fdc.nal.usda.gov/")!)
                NavigationLink(diary.t("المصادر والتراخيص","Sources and licenses")){LicensesView()}
            }
        }.appBackground().navigationTitle(diary.t("الإعدادات","Settings"))
            .sheet(isPresented:$goals){GoalEditor()}
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
struct ImportPreview:View {
    let snapshot:DiarySnapshot;let apply:()->Bool
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dismiss) var dismiss
    var body:some View {NavigationStack{Form{Section(diary.t("البيانات التي ستُدمج","Data to merge")){row(diary.t("الأطعمة المسجلة","Diary entries"),snapshot.entries.count);row(diary.t("الوصفات والوجبات","Recipes and meals"),snapshot.recipes.count);row(diary.t("قراءات الوزن","Weight readings"),snapshot.weights.count);row(diary.t("المنتجات المحفوظة","Saved products"),snapshot.products.count)};Section{Notice(text:diary.t("ستُعتمد أهداف السعرات من النسخة. السجل الحالي يبقى محفوظًا، والمطابق يُحدَّث. صلاحيات صحتي وإعداد اللغة الحالية لا تتغير.","Calorie goals will use the backup values. Existing records remain, matching records update. Health access and the current language stay as they are."));Button(diary.t("تأكيد الاستيراد","Confirm import")){if apply(){dismiss()}}}}.appBackground().navigationTitle(diary.t("استيراد النسخة","Import backup")).toolbar{ToolbarItem(placement:.cancellationAction){Button(diary.t("إلغاء","Cancel")){dismiss()}}}}}
    private func row(_ title:String,_ n:Int) -> some View {HStack{Text(title);Spacer();Text(String(n)).foregroundStyle(.secondary)}}
}
struct LicensesView:View {
    @EnvironmentObject var diary:DiaryStore
    private func file(_ name:String) -> String {guard let url=Bundle.main.url(forResource:name,withExtension:"txt") else{return ""};return (try? String(contentsOf:url,encoding:.utf8)) ?? ""}
    var body:some View {ScrollView{VStack(alignment:.leading,spacing:20){Text("ONNX Runtime • Microsoft • MIT\nCLIP • OpenAI • MIT\nTransformers.js / Xenova • Apache 2.0\nOpen Food Facts • ODbL database / DbCL contents\nUSDA • Public domain\nNIDDK weight equations • Hall et al., Lancet 2011").font(.subheadline);Text(file("NOTICE"));Text(file("LICENSES"))}.font(.footnote).padding(20).textSelection(.enabled).environment(\.layoutDirection,.leftToRight)}.appBackground().navigationTitle(diary.t("التراخيص","Licenses"))}
}
