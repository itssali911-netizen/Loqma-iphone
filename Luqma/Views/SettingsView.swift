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
        ScrollView{VStack(alignment:.leading,spacing:24){
            LuqmaPageHeader(title:diary.t("الإعدادات","Settings"),subtitle:diary.t("أهدافك وربطك وبياناتك","Your goals, connections and data"),symbol:"slider.horizontal.3")
            HStack(spacing:16){Image("LuqmaMark").resizable().scaledToFit().frame(width:54,height:54).accessibilityHidden(true);VStack(alignment:.leading,spacing:4){Text(diary.t("لُقمة","Luqma")).luqmaFont(.title2);Text(diary.t("كل لقمة تقرّبك من هدفك","Every bite brings you closer")).luqmaFont(.footnote).foregroundStyle(Theme.muted)};Spacer(minLength:0)}.luqmaCard()
            settingsGroup(diary.t("أهدافي","My goals")){
                Button{goals=true}label:{settingsRow(diary.t("السعرات والماكروز","Calories and macros"),symbol:"target")}
                Divider().overlay(Theme.stroke)
                NavigationLink{PlanView().toolbar(.visible,for:.navigationBar)}label:{settingsRow(diary.t("خطة الوزن","Weight plan"),symbol:"chart.line.uptrend.xyaxis")}
            }
            settingsGroup(diary.t("التفضيلات","Preferences")){
                HStack(spacing:12){settingsIcon("globe");Text(diary.t("اللغة","Language"));Spacer(minLength:0);Picker(diary.t("اللغة","Language"),selection:Binding(get:{diary.language},set:{value in diary.change{$0.language=value}})){Text("العربية").tag(AppLanguage.ar);Text("English").tag(AppLanguage.en)}.pickerStyle(.menu).labelsHidden()}.frame(minHeight:52)
            }
            settingsGroup(diary.t("الربط والبيانات","Connections and data")){
                Button{gemini=true}label:{settingsRow(diary.t("تحليل الوجبة","Meal analysis"),symbol:"sparkles")}
                Divider().overlay(Theme.stroke)
                NavigationLink{BackupSettingsView().toolbar(.visible,for:.navigationBar)}label:{settingsRow(diary.t("النسخ الاحتياطي والنقل","Backup and transfer"),symbol:"externaldrive")}
            }
            settingsGroup(diary.t("لُقمة","Luqma")){
                NavigationLink{AboutLuqmaView().toolbar(.visible,for:.navigationBar)}label:{settingsRow(diary.t("حول لُقمة والخصوصية","About Luqma and privacy"),symbol:"info.circle")}
            }
        }.buttonStyle(.plain).padding(24)}.appBackground().navigationTitle(diary.t("الإعدادات","Settings"))
            .toolbar(.hidden,for:.navigationBar)
            .sheet(isPresented:$goals){GoalEditor()}
            .sheet(isPresented:$gemini){GeminiSettingsView()}
    }
    private func settingsGroup<Content:View>(_ title:String,@ViewBuilder content:()->Content)->some View {
        VStack(alignment:.leading,spacing:12){LuqmaSectionHeader(title:title);VStack(spacing:6,content:content).luqmaCard()}
    }
    private func settingsIcon(_ symbol:String)->some View {Image(systemName:symbol).font(.system(size:19,weight:.medium)).foregroundStyle(Theme.accent).frame(width:36,height:36).accessibilityHidden(true)}
    private func settingsRow(_ title:String,symbol:String)->some View {HStack(spacing:12){settingsIcon(symbol);Text(title).luqmaFont(.body).foregroundStyle(Theme.text);Spacer(minLength:0);Image(systemName:"chevron.forward").font(.system(size:12,weight:.semibold)).foregroundStyle(Theme.muted)}.frame(minHeight:52).contentShape(Rectangle())}
}
struct BackupSettingsView:View {
    @EnvironmentObject var diary:DiaryStore
    @State private var exporting=false
    @State private var importing=false
    @State private var document=BackupDocument(data:Data())
    @State private var pending:DiarySnapshot?
    @State private var importingBusy=false
    var body:some View {
        Form{
            Section(diary.t("بياناتي","My data")){
                Button{do{document=BackupDocument(data:try Backup.encode(diary.state));exporting=true}catch{diary.report(error)}}label:{Label(diary.t("تصدير نسخة احتياطية","Export backup"),systemImage:"square.and.arrow.up")}.buttonStyle(LuqmaPrimaryButtonStyle())
                Button{importing=true}label:{Label(diary.t("استيراد نسخة من الموقع أو التطبيق","Import a website or app backup"),systemImage:"square.and.arrow.down")}.buttonStyle(LuqmaSecondaryButtonStyle()).disabled(importingBusy)
                if importingBusy{ProgressView()}
            }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            Section{
                Notice(text:diary.t("صدّر نسخة لحفظ بياناتك أو نقلها إلى جهاز آخر. عند الاستيراد تُدمج البيانات، وتُحدَّث السجلات المطابقة دون حذف باقي سجلك.","Export a backup to save your data or move it to another device. Import merges the data and updates matching records without deleting the rest of your diary."))
            }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
        }.sandowForm().navigationTitle(diary.t("النسخ الاحتياطي","Backup")).navigationBarTitleDisplayMode(.inline)
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
struct AboutLuqmaView:View {
    @EnvironmentObject var diary:DiaryStore
    var body:some View {
        Form{
            Section(diary.t("لُقمة","Luqma")){
                HStack(spacing:14){Image("LuqmaMark").resizable().scaledToFit().frame(width:60,height:60);Text(diary.t("لُقمة","Luqma")).luqmaFont(.title2)}.frame(maxWidth:.infinity,alignment:.leading).padding(.vertical,8)
                Text(diary.t("الإصدار ","Version ") + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.4"))
            }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            Section(diary.t("الخصوصية","Privacy")){
                Notice(text:diary.t("سجلك محفوظ على الجهاز. تحليل الوجبة يرسل الصورة والوصف إلى Google. استيراد الوصفة يرسل الرابط العام الذي تختاره أو نص الوصفة. إعداد الربط محفوظ في خزنة الجهاز ولا يدخل النسخ الاحتياطية.","Your diary stays on the device. Meal analysis sends the selected photo and description to Google. Recipe import sends your selected public link or recipe text. Connection credentials are stored in the device Keychain and excluded from backups."))
            }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            Section(diary.t("مصادر الطعام","Food sources")){
                Text(diary.t("٧٤٤ طعامًا من ملف MyFitnessPal الذي أضفته. هذه عينة محلية؛ البيانات الناقصة تحتاج مراجعة الملصق.","744 foods from your supplied MyFitnessPal file. This is a local sample; incomplete values need label review."))
                Link("Open Food Facts",destination:URL(string:"https://world.openfoodfacts.org")!)
            }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            Section(diary.t("التصميم","Design")){
                Link("Sandow · Figma Community",destination:URL(string:"https://www.figma.com/design/IfMCdTI3FcvXpNFy79PRUA?node-id=2-606")!)
                Text(diary.t("الثيم الداكن وألوان Sandow، مع تنظيم مخصص لسجل الطعام العربي. بعض شاشات المرجع صور معاينة أُعيد بناؤها للتطبيق.","Sandow dark theme and colors, arranged for the Arabic food diary. Some reference screens are flattened previews reconstructed for this app.")).luqmaFont(.footnote).foregroundStyle(Theme.muted)
                Link("Work Sans · SIL Open Font License",destination:URL(string:"https://github.com/weiweihuanghuang/Work-Sans")!)
                Link("Tajawal · SIL Open Font License",destination:URL(string:"https://github.com/google/fonts/tree/main/ofl/tajawal")!)
            }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
        }.sandowForm().navigationTitle(diary.t("حول لُقمة","About Luqma")).navigationBarTitleDisplayMode(.inline)
    }
}
struct ImportPreview:View {
    let snapshot:DiarySnapshot;let apply:()->Bool
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dismiss) var dismiss
    var body:some View {
        NavigationStack{Form{
            Section(diary.t("البيانات التي ستُدمج","Data to merge")){
                row(diary.t("الأطعمة المسجلة","Diary entries"),snapshot.entries.count)
                row(diary.t("الوصفات والوجبات","Recipes and meals"),snapshot.recipes.count)
                row(diary.t("قراءات الوزن","Weight readings"),snapshot.weights.count)
                row(diary.t("المنتجات المحفوظة","Saved products"),snapshot.products.count)
            }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            Section{Notice(text:diary.t("ستُعتمد أهداف السعرات من النسخة. السجل الحالي يبقى محفوظًا، والمطابق يُحدَّث. إعداد اللغة الحالية لا يتغير.","Calorie goals will use the backup values. Existing records remain, matching records update. The current language stays as it is."))}.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            Section{Button(diary.t("تأكيد الاستيراد","Confirm import")){if apply(){dismiss()}}.buttonStyle(LuqmaPrimaryButtonStyle())}.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top:0,leading:0,bottom:0,trailing:0))
        }.sandowForm().navigationTitle(diary.t("استيراد النسخة","Import backup")).navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.cancellationAction){Button(diary.t("إلغاء","Cancel")){dismiss()}}}
        }
    }
    private func row(_ title:String,_ n:Int) -> some View {HStack{Text(title);Spacer();Text(String(n)).foregroundStyle(.secondary)}}
}
