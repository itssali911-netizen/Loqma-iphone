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
    var onBack:(()->Void)?=nil
    @EnvironmentObject var diary:DiaryStore
    @State private var goals=false
    @State private var gemini=false
    var body:some View {
        ScrollView{VStack(alignment:.leading,spacing:24){
            settingsGroup(diary.t("أهدافي","My goals")){
                Button{goals=true}label:{settingsRow(diary.t("السعرات والماكروز","Calories and macros"),symbol:"target")}.accessibilityIdentifier("settings.goals")
                NavigationLink{PlanView()}label:{settingsRow(diary.t("خطة الوزن","Weight plan"),symbol:"chart.line.uptrend.xyaxis")}
            }
            settingsGroup(diary.t("التفضيلات","Preferences")){
                languageRow
            }
            settingsGroup(diary.t("الربط والبيانات","Connections and data")){
                Button{gemini=true}label:{settingsRow(diary.t("تحليل الوجبة","Meal analysis"),symbol:"sparkles")}
                NavigationLink{BackupSettingsView()}label:{settingsRow(diary.t("النسخ الاحتياطي والنقل","Backup and transfer"),symbol:"externaldrive")}
            }
            settingsGroup(diary.t("لُقمة","Luqma")){
                NavigationLink{AboutLuqmaView()}label:{settingsRow(diary.t("حول لُقمة والخصوصية","About Luqma and privacy"),symbol:"info.circle")}
            }
            settingsFooter
        }.buttonStyle(.plain).padding(16).padding(.top,4)}.appBackground().navigationTitle(diary.t("الإعدادات","Settings"))
            .toolbar(.hidden,for:.navigationBar)
            .safeAreaInset(edge:.top,spacing:0){settingsHeader}
            .sheet(isPresented:$goals){GoalEditor()}
            .sheet(isPresented:$gemini){GeminiSettingsView()}
    }
    private var settingsHeader:some View {
        VStack(alignment:.leading,spacing:12){
            if let onBack{
                Button(action:onBack){Image(systemName:"chevron.backward").font(.system(size:13,weight:.medium))
                    .foregroundStyle(Theme.text).frame(width:34,height:34)
                    .background(Theme.card,in:RoundedRectangle(cornerRadius:12))
                    .frame(width:44,height:44).contentShape(Rectangle())}
                    .buttonStyle(.plain).accessibilityLabel(diary.t("رجوع","Back")).accessibilityIdentifier("settings.back")
            }
            Text(diary.t("الإعدادات","Settings")).luqmaFont(size:24,weight:.bold,relativeTo:.title2)
                .foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
        }.padding(.horizontal,16).padding(.top,8).padding(.bottom,20)
            .frame(maxWidth:.infinity,minHeight:112,alignment:.bottomLeading)
            .background{UnevenRoundedRectangle(bottomLeadingRadius:28,bottomTrailingRadius:28,style:.continuous)
                .fill(Theme.surface).ignoresSafeArea(edges:.top)}
    }
    private var languageRow:some View {
        HStack(spacing:10){
            settingsIcon("globe")
            Text(diary.t("اللغة","Language")).luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline)
            Spacer(minLength:0)
            Picker(diary.t("اللغة","Language"),selection:Binding(get:{diary.language},set:{value in diary.change{$0.language=value}})){
                Text("العربية").tag(AppLanguage.ar);Text("English").tag(AppLanguage.en)
            }.pickerStyle(.menu).labelsHidden().luqmaFont(size:11,relativeTo:.caption)
        }.foregroundStyle(Theme.text).padding(.horizontal,10).padding(.vertical,8).frame(minHeight:64)
            .background(Theme.card,in:RoundedRectangle(cornerRadius:20,style:.continuous))
    }
    private var settingsFooter:some View {
        VStack(spacing:6){
            Image("LuqmaMark").resizable().scaledToFit().frame(width:24,height:24).accessibilityHidden(true)
            Text(diary.t("لُقمة","Luqma")+" · "+(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""))
                .luqmaFont(size:10,weight:.semibold,relativeTo:.caption2)
        }.foregroundStyle(Theme.text).frame(maxWidth:.infinity).padding(.vertical,20)
            .background(Theme.surface,in:RoundedRectangle(cornerRadius:24,style:.continuous))
    }
    private func settingsGroup<Content:View>(_ title:String,@ViewBuilder content:()->Content)->some View {
        VStack(alignment:.leading,spacing:9){
            Text(title).luqmaFont(size:12,weight:.semibold,relativeTo:.caption)
                .foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
            VStack(spacing:8,content:content)
        }
    }
    private func settingsIcon(_ symbol:String)->some View {Image(systemName:symbol).font(.system(size:18,weight:.regular)).foregroundStyle(Theme.text).frame(width:42,height:42).background(Theme.surface,in:RoundedRectangle(cornerRadius:13)).accessibilityHidden(true)}
    private func settingsRow(_ title:String,symbol:String)->some View {HStack(spacing:10){settingsIcon(symbol);Text(title).luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline).foregroundStyle(Theme.text);Spacer(minLength:0);Image(systemName:"chevron.forward").font(.system(size:13,weight:.medium)).foregroundStyle(Theme.muted)}.padding(.horizontal,10).padding(.vertical,8).frame(maxWidth:.infinity,minHeight:64,alignment:.leading).background(Theme.card,in:RoundedRectangle(cornerRadius:20,style:.continuous)).contentShape(RoundedRectangle(cornerRadius:20))}
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
        }.sandowForm().sandowNavigation(diary.t("النسخ الاحتياطي","Backup"),backLabel:diary.t("رجوع","Back"))
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
        ScrollView{VStack(spacing:14){
            VStack(spacing:12){
                Image("LuqmaMark").resizable().scaledToFit().frame(width:84,height:84).accessibilityHidden(true)
                Text(diary.t("لُقمة","Luqma")).luqmaFont(size:28,weight:.bold,relativeTo:.title)
                Text(diary.t("مفكرة السعرات والتغذية","Your calorie and nutrition diary"))
                    .luqmaFont(size:13,relativeTo:.subheadline).foregroundStyle(Theme.muted)
                Text(diary.t("الإصدار ","Version ") + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""))
                    .luqmaFont(size:10,relativeTo:.caption2).foregroundStyle(Theme.muted)
            }.multilineTextAlignment(.center).frame(maxWidth:.infinity).padding(.top,28).padding(.bottom,20)
            aboutCard(diary.t("الخصوصية","Privacy"),symbol:"hand.raised.fill"){
                Notice(text:diary.t("سجلك محفوظ على الجهاز. تحليل الوجبة يرسل الصورة والوصف إلى Google. استيراد الوصفة يرسل الرابط العام الذي تختاره أو نص الوصفة. إعداد الربط محفوظ في خزنة الجهاز ولا يدخل النسخ الاحتياطية.","Your diary stays on the device. Meal analysis sends the selected photo and description to Google. Recipe import sends your selected public link or recipe text. Connection credentials are stored in the device Keychain and excluded from backups."))
            }
            aboutCard(diary.t("مصادر الطعام","Food sources"),symbol:"fork.knife"){
                Notice(text:diary.t("٧٤٤ طعامًا من ملف MyFitnessPal الذي أضفته. هذه عينة محلية؛ البيانات الناقصة تحتاج مراجعة الملصق.","744 foods from your supplied MyFitnessPal file. This is a local sample; incomplete values need label review."))
                aboutLink("Open Food Facts",url:"https://world.openfoodfacts.org")
            }
            aboutCard(diary.t("التصميم","Design"),symbol:"paintpalette.fill"){
                aboutLink("Sandow · Figma Community",url:"https://www.figma.com/design/IfMCdTI3FcvXpNFy79PRUA?node-id=2-606")
                Text(diary.t("الثيم الداكن وألوان Sandow، مع تنظيم مخصص لسجل الطعام العربي. بعض شاشات المرجع صور معاينة أُعيد بناؤها للتطبيق.","Sandow dark theme and colors, arranged for the Arabic food diary. Some reference screens are flattened previews reconstructed for this app.")).luqmaFont(.footnote).foregroundStyle(Theme.muted)
                aboutLink("Work Sans · SIL Open Font License",url:"https://github.com/weiweihuanghuang/Work-Sans")
                aboutLink("Tajawal · SIL Open Font License",url:"https://github.com/google/fonts/tree/main/ofl/tajawal")
            }
        }.padding(.horizontal,16).padding(.bottom,24)}.appBackground()
            .sandowNavigation(diary.t("حول لُقمة","About Luqma"),backLabel:diary.t("رجوع","Back"))
    }
    private func aboutCard<Content:View>(_ title:String,symbol:String,@ViewBuilder content:()->Content)->some View {
        VStack(alignment:.leading,spacing:12){
            Label(title,systemImage:symbol).luqmaFont(size:12,weight:.semibold,relativeTo:.caption)
                .foregroundStyle(Theme.text).accessibilityAddTraits(.isHeader)
            content()
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
            .background(Theme.card,in:RoundedRectangle(cornerRadius:24,style:.continuous))
    }
    private func aboutLink(_ title:String,url:String)->some View {
        Link(destination:URL(string:url)!){HStack(spacing:8){
            Text(title).luqmaFont(size:12,relativeTo:.caption).multilineTextAlignment(.leading)
            Spacer(minLength:0)
            Image(systemName:"arrow.up.forward").font(.system(size:10,weight:.medium))
        }.foregroundStyle(Theme.text).frame(minHeight:32)}
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
        }.sandowForm().sandowNavigation(diary.t("استيراد النسخة","Import backup"),backLabel:diary.t("إلغاء","Cancel"),onBack:{dismiss()},
            actionLabel:diary.t("تأكيد الاستيراد","Confirm import"),onAction:{if apply(){dismiss()}})
        }
    }
    private func row(_ title:String,_ n:Int) -> some View {HStack{Text(title);Spacer();Text(String(n)).foregroundStyle(.secondary)}}
}
