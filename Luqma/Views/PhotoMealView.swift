import SwiftUI
import PhotosUI
import UIKit

struct PhotoMealView:View {
    var onCommit:([(Food,Double)],Meal)->Bool
    @EnvironmentObject var diary:DiaryStore
    @State private var item:PhotosPickerItem?
    @State private var imageData:Data?
    @State private var camera=false
    @State private var busy=false
    @State private var description=""
    @State private var stage=""
    @State private var error:String?
    @State private var parts:[PhotoPart]=[]
    @State private var references:[PhotoFood]=[]
    @State private var sauceSuggested=false
    @State private var unmatched=false
    @State private var meal:Meal = .lunch
    @State private var analysisTask:Task<Void,Never>?
    private var total:Nutrition{parts.reduce(.zero){$0+$1.nutrition}}
    var body:some View {
        VStack(alignment:.leading,spacing:18){
            if let imageData,let image=try? PhotoAnalyzer.image(imageData){Image(uiImage:UIImage(cgImage:image)).resizable().scaledToFit().frame(maxHeight:260).clipShape(RoundedRectangle(cornerRadius:18))}
            HStack{PhotosPicker(selection:$item,matching:.images){Label(diary.t("رفع صورة","Choose photo"),systemImage:"photo")}.buttonStyle(.bordered);Button{Task{if UIImagePickerController.isSourceTypeAvailable(.camera),await CameraAccess.request(){camera=true}else{error=diary.t("الكاميرا غير متاحة أو تحتاج إذنًا من الإعدادات.","Camera is unavailable or needs access in Settings.")}}}label:{Label(diary.t("الكاميرا","Camera"),systemImage:"camera")}.buttonStyle(.bordered)}.disabled(busy)
            VStack(alignment:.leading){Text(diary.t("ماذا في الوجبة؟ (اختياري)","What's in the meal? (optional)")).font(.subheadline);TextField("",text:$description,axis:.vertical).lineLimit(2...4).padding(12).background(Theme.card,in:RoundedRectangle(cornerRadius:12)).accessibilityLabel(diary.t("وصف الوجبة الاختياري","Optional meal description"))}
            Notice(text:diary.t("التحليل على الجهاز. أول استخدام ينزّل نموذجين بحجم إجمالي نحو ١٧٧ ميجابايت، ثم يعمل دون إنترنت. ذكر مكونات الوجبة وعدد القطع يساعد التحليل.","Analysis runs on your device. First use downloads two models totaling about 177 MB, then works offline. Naming ingredients and counts helps."))
            Button{analyze()}label:{Label(diary.t("تحليل الوجبة","Analyze meal"),systemImage:"sparkles").frame(maxWidth:.infinity).padding(12)}.buttonStyle(.borderedProminent).disabled(imageData==nil || busy)
            if busy{HStack{ProgressView();Text(stageText).font(.footnote);Spacer();Button(diary.t("إلغاء","Cancel")){analysisTask?.cancel()}}}
            if let error{Text(error).foregroundStyle(.orange).font(.footnote)}
            if !parts.isEmpty{review}
        }.sheet(isPresented:$camera){CameraPhoto{data in camera=false;if let data{imageData=data;parts=[];error=nil}}.ignoresSafeArea()}
            .onChange(of:item){_,value in Task{guard let value else{return};do{imageData=try await value.loadTransferable(type:Data.self);parts=[];error=nil}catch{self.error=error.localizedDescription}}}
            .onDisappear{analysisTask?.cancel()}
    }
    private var stageText:String {if stage=="download"{return diary.t("تنزيل النموذج…","Downloading model…")};if stage=="verify"{return diary.t("التحقق من النموذج…","Verifying model…")};return diary.t("فحص مكونات الصورة…","Inspecting image regions…")+" "+stage.replacingOccurrences(of:"analyze:",with:"")}
    private var review:some View {VStack(alignment:.leading,spacing:18){
        Text(diary.t("راجع مكونات الوجبة","Review meal components")).font(.title3.bold())
        ForEach($parts){$part in VStack(alignment:.leading,spacing:8){HStack{Text(part.food.food.label(diary.language)).font(.headline);Spacer();Button(role:.destructive){parts.removeAll{$0.id==part.id}}label:{Image(systemName:"minus.circle")}};if part.tentative{Text(diary.t("اقتراح يحتاج تأكيدك","Tentative: confirm this component")).foregroundStyle(.orange).font(.caption)};NumericInput(title:diary.t("الوزن المقدّر","Estimated weight"),value:Binding(get:{part.grams},set:{part.setGrams($0)}),suffix:diary.t("جم","g"));Text("\(decimal(part.low,0))–\(decimal(part.high,0)) "+diary.t("جم • نطاق تقديري","g • rough range")).font(.caption).foregroundStyle(Theme.muted);NutritionView(value:part.nutrition)}.luqmaCard()}
        Menu{ForEach(references){f in Button(f.food.label(diary.language)){parts.append(PhotoPart(food:f,grams:f.grams,low:f.grams*0.5,high:f.grams*1.8,basis:"reference"))}}}label:{Label(diary.t("إضافة مكوّن ناقص","Add a missing component"),systemImage:"plus.circle")}
        if sauceSuggested{Notice(text:diary.t("قد توجد علبة صوص؛ حدّد نوعها من إضافة مكوّن ناقص قبل الحفظ.","A dip may be present. Confirm its type using Add a missing component."))}
        if unmatched{Notice(text:diary.t("بعض تفاصيل وصفك غير معروفة؛ راجع المكونات الناقصة.","Some description details were not recognized. Check missing components."))}
        NutritionView(value:total,large:true).luqmaCard()
        Notice(text:diary.t("هذه أوزان مستنتجة من حصص مرجعية وليست قياسًا من الصورة. الزيت ونوع الصوص وعمق الطعام قد يغيّرون الحسبة كثيرًا. راجع المكونات والكميات قبل الحفظ.","Weights are inferred from reference portions, not measured from the image. Oil, sauce recipes and food depth can change the result substantially. Review before saving."))
        Picker(diary.t("الوجبة","Meal"),selection:$meal){ForEach(Meal.allCases){Text($0.label(diary.language)).tag($0)}}
        Button(diary.t("تأكيد وإضافة الوجبة","Confirm and add meal")){if onCommit(parts.map{($0.food.food,$0.grams)},meal){parts=[]}}.buttonStyle(.borderedProminent).disabled(parts.contains{!$0.grams.isFinite || $0.grams<=0 || $0.grams>3000})
    }}
    private func analyze(){guard let imageData else{return};busy=true;error=nil;parts=[];stage=""
        analysisTask=Task{do{
            let refs=try await PhotoAnalyzer.shared.foods()
            let result=try await PhotoAnalyzer.shared.analyze(imageData,description:description){value in Task{@MainActor in stage=value}}
            try Task.checkCancellation();references=refs;parts=result.parts;sauceSuggested=result.sauceSuggested;unmatched=result.unmatched
            if parts.isEmpty{error=diary.t("لم تتضح مكونات الطعام. جرّب صورة أقرب ووصفًا اختياريًا.","Food components were unclear. Try a closer photo and an optional description.")}
        }catch is CancellationError{error=nil}catch{error=(error as? AppError)?.message(diary.language) ?? diary.t("تعذّر التحليل. تحقق من الاتصال لتنزيل النموذج ثم أعد المحاولة.","Analysis failed. Check your connection to download the model, then retry.")};busy=false}
    }
}
