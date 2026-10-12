import SwiftUI
import UniformTypeIdentifiers

struct GeminiSettingsView:View {
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var key=""
    @State private var configured=GeminiCredentialStore.isConfigured
    @State private var importing=false
    @State private var message:String?
    @State private var removing=false
    var body:some View {
        NavigationStack {
            Form {
                Section {
                    Label("Gemini 3.8 Flash",systemImage:"sparkles").font(.headline)
                    Label(diary.t(configured ? "المفتاح محفوظ على هذا الجهاز":"يلزم إعداد المفتاح",configured ? "Key saved on this device":"Key setup needed"),systemImage:configured ? "checkmark.circle.fill":"key.fill")
                        .foregroundStyle(configured ? Theme.accent:Theme.muted)
                    Text(diary.t("يحلل الصورة والوصف عبر Google. سجل الطعام وبيانات صحتي لا تُرسل إليه.","Analyzes the photo and description through Google. Your diary and Health data are not sent."))
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                Section(diary.t("إعداد التحليل","Analysis setup")) {
                    Button{importing=true}label:{Label(diary.t("استيراد ملف إعداد Gemini","Import Gemini setup file"),systemImage:"square.and.arrow.down")}
                    DisclosureGroup(diary.t("إدخال المفتاح يدويًا","Enter key manually")) {
                        SecureField(diary.t("مفتاح Gemini API","Gemini API key"),text:$key).textInputAutocapitalization(.never).autocorrectionDisabled()
                        Button(diary.t("حفظ المفتاح","Save key")){save(key)}.disabled(key.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                    }
                    Link(diary.t("Google AI Studio","Google AI Studio"),destination:URL(string:"https://aistudio.google.com/api-keys")!)
                }
                if let message {Section{Text(message).font(.footnote)}}
                Section {
                    Text(diary.t("المفتاح يُحفظ في خزنة الجهاز، ولا يدخل النسخ الاحتياطية. استخدام النموذج يخضع لحصص Google وتسعير حسابك وسياسة بياناته.","The key is stored in the device Keychain and excluded from backups. Model use follows your Google account quotas, pricing and data policy."))
                        .font(.footnote).foregroundStyle(Theme.muted)
                    Link(diary.t("سياسة بيانات Gemini","Gemini data policy"),destination:URL(string:"https://ai.google.dev/gemini-api/terms")!)
                    if configured {Button(diary.t("إزالة المفتاح من هذا الجهاز","Remove key from this device"),role:.destructive){removing=true}}
                }
            }.appBackground().navigationTitle(diary.t("تحليل الوجبات","Meal analysis"))
                .toolbar{ToolbarItem(placement:.confirmationAction){Button(diary.t("تم","Done")){dismiss()}}}
        }
        .fileImporter(isPresented:$importing,allowedContentTypes:[.json],allowsMultipleSelection:false){result in
            do {
                let urls=try result.get();guard let url=urls.first else{return}
                let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
                let values=try url.resourceValues(forKeys:[.fileSizeKey]);guard (values.fileSize ?? 0)<=8192 else{throw AppError.invalid("ملف الإعداد كبير أو غير صالح.","The setup file is too large or invalid.")}
                save(try GeminiConfiguration.key(from:Data(contentsOf:url)))
            }catch{message=(error as? AppError)?.message(diary.language) ?? diary.t("تعذّر قراءة ملف الإعداد.","The setup file could not be read.")}
        }
        .confirmationDialog(diary.t("إزالة مفتاح Gemini؟","Remove the Gemini key?"),isPresented:$removing,titleVisibility:.visible){
            Button(diary.t("إزالة","Remove"),role:.destructive){do{try GeminiCredentialStore.clear();configured=false;message=nil}catch{diary.report(error)}}
        }
    }
    private func save(_ input:String) {
        do{try GeminiCredentialStore.save(input);key="";configured=true;message=diary.t("تم إعداد Gemini. ارجع إلى صورة الوجبة وابدأ التحليل.","Gemini is configured. Return to the meal photo and analyze.")}
        catch{message=(error as? AppError)?.message(diary.language) ?? diary.t("تعذّر حفظ المفتاح.","The key could not be saved.")}
    }
}
