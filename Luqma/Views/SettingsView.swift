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
    @State private var goals=false
    @State private var gemini=false
    var body:some View {
        VStack(spacing:0){
            LuqmaPageHeader(title:diary.t("الإعدادات","Settings"),subtitle:diary.t("أهدافك وربطك وبياناتك","Your goals, connections and data"),symbol:"slider.horizontal.3")
                .padding(.horizontal,20).padding(.top,20).padding(.bottom,8)
        Form{
            Section(diary.t("أهدافي","My goals")){
                Button{goals=true}label:{Label(diary.t("السعرات والماكروز","Calories and macros"),systemImage:"target")}
                NavigationLink{PlanView().toolbar(.visible,for:.navigationBar)}label:{Label(diary.t("خطة الوزن","Weight plan"),systemImage:"chart.line.uptrend.xyaxis")}
            }
            Section(diary.t("التفضيلات","Preferences")){
                Picker(diary.t("اللغة","Language"),selection:Binding(get:{diary.language},set:{value in diary.change{$0.language=value}})){Text("العربية").tag(AppLanguage.ar);Text("English").tag(AppLanguage.en)}.pickerStyle(.menu)
            }
            Section(diary.t("الربط والبيانات","Connections and data")){
                Button{gemini=true}label:{Label(diary.t("تحليل الوجبة","Meal analysis"),systemImage:"sparkles")}
                NavigationLink{BackupSettingsView().toolbar(.visible,for:.navigationBar)}label:{Label(diary.t("النسخ الاحتياطي والنقل","Backup and transfer"),systemImage:"externaldrive")}
            }
            Section{
                NavigationLink{AboutLuqmaView().toolbar(.visible,for:.navigationBar)}label:{Label(diary.t("حول لُقمة والخصوصية","About Luqma and privacy"),systemImage:"info.circle")}
            }
        }.appBackground()
        }.appBackground().navigationTitle(diary.t("الإعدادات","Settings"))
            .toolbar(.hidden,for:.navigationBar)
            .sheet(isPresented:$goals){GoalEditor()}
            .sheet(isPresented:$gemini){GeminiSettingsView()}
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
                Notice(text:diary.t("سجلك محفوظ على الجهاز. تحليل الوجبة يرسل الصورة والوصف إلى Google. استيراد الوصفة يرسل الرابط العام الذي تختاره أو نص الوصفة. إعداد الربط محفوظ في خزنة الجهاز ولا يدخل النسخ الاحتياطية.","Your diary stays on the device. Meal analysis sends the selected photo and description to Google. Recipe import sends your selected public link or recipe text. Connection credentials are stored in the device Keychain and excluded from backups."))
            }
            Section(diary.t("مصادر الطعام","Food sources")){
                Text(diary.t("٧٤٤ طعامًا من ملف MyFitnessPal الذي أضفته. هذه عينة محلية؛ البيانات الناقصة تحتاج مراجعة الملصق.","744 foods from your supplied MyFitnessPal file. This is a local sample; incomplete values need label review."))
                Link("Open Food Facts",destination:URL(string:"https://world.openfoodfacts.org")!)
            }
            Section(diary.t("التصميم","Design")){
                Link("Sandow · strangehelix.bio",destination:URL(string:"https://www.figma.com/community/file/1334779038193346013/sandow-ui-kit-ai-fitness-nutrition-app")!)
                Text(diary.t("مقتبس من نسخة Community الداكنة، بتعديلات لواجهة لقمة العربية.","Adapted from the dark Community edition for Luqma's Arabic interface.")).font(.footnote).foregroundStyle(Theme.muted)
                Link("CC BY 4.0",destination:URL(string:"https://creativecommons.org/licenses/by/4.0/")!)
            }
        }.appBackground().navigationTitle(diary.t("حول لُقمة","About Luqma"))
    }
}
struct ImportPreview:View {
    let snapshot:DiarySnapshot;let apply:()->Bool
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dismiss) var dismiss
    var body:some View {NavigationStack{Form{Section(diary.t("البيانات التي ستُدمج","Data to merge")){row(diary.t("الأطعمة المسجلة","Diary entries"),snapshot.entries.count);row(diary.t("الوصفات والوجبات","Recipes and meals"),snapshot.recipes.count);row(diary.t("قراءات الوزن","Weight readings"),snapshot.weights.count);row(diary.t("المنتجات المحفوظة","Saved products"),snapshot.products.count)};Section{Notice(text:diary.t("ستُعتمد أهداف السعرات من النسخة. السجل الحالي يبقى محفوظًا، والمطابق يُحدَّث. إعداد اللغة الحالية لا يتغير.","Calorie goals will use the backup values. Existing records remain, matching records update. The current language stays as it is."));Button(diary.t("تأكيد الاستيراد","Confirm import")){if apply(){dismiss()}}}}.appBackground().navigationTitle(diary.t("استيراد النسخة","Import backup")).toolbar{ToolbarItem(placement:.cancellationAction){Button(diary.t("إلغاء","Cancel")){dismiss()}}}}}
    private func row(_ title:String,_ n:Int) -> some View {HStack{Text(title);Spacer();Text(String(n)).foregroundStyle(.secondary)}}
}
