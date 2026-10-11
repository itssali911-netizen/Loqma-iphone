import SwiftUI
import PhotosUI
import UIKit

@MainActor struct PhotoMealView:View {
    var onCommit:PhotoFoodCommit
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.scenePhase) private var phase
    @State private var item:PhotosPickerItem?
    @State private var imageData:Data?
    @State private var preview:UIImage?
    @State private var camera=false
    @State private var busy=false
    @State private var description=""
    @State private var stage=""
    @State private var error:String?
    @State private var cancellationMessage:String?
    @State private var recoveredRun=false
    @State private var parts:[PhotoPart]=[]
    private struct ProductSelection:Identifiable {var id:UUID;var name:String}
    @State private var selection:ProductSelection?
    @State private var products:[UUID:(Food,Double,FoodUnit)]=[:]
    @State private var references:[PhotoFood]=[]
    @State private var sauceSuggested=false
    @State private var unmatched=false
    @State private var meal:Meal = .lunch
    @State private var analysisTask:Task<Void,Never>?
    @State private var advanced = VisionAnalyzer.supported
    @State private var engine = ""
    @State private var activeModel = "Qwen3-VL"
    private var total:Nutrition{products.values.reduce(.zero){$0+((try? $1.0.total($1.1,unit:$1.2)) ?? .zero)}}
    var body:some View {
        let choosePhotoTitle=diary.t("رفع صورة","Choose photo")
        return VStack(alignment:.leading,spacing:18){
            if let preview{Image(uiImage:preview).resizable().scaledToFit().frame(maxHeight:260).clipShape(RoundedRectangle(cornerRadius:18))}
            HStack{PhotosPicker(selection:$item,matching:.images){Label(choosePhotoTitle,systemImage:"photo")}.buttonStyle(.bordered);Button{Task{if UIImagePickerController.isSourceTypeAvailable(.camera),await CameraAccess.request(){camera=true}else{error=diary.t("الكاميرا غير متاحة أو تحتاج إذنًا من الإعدادات.","Camera is unavailable or needs access in Settings.")}}}label:{Label(diary.t("الكاميرا","Camera"),systemImage:"camera")}.buttonStyle(.bordered)}.disabled(busy)
            VStack(alignment:.leading){Text(diary.t("ماذا في الوجبة؟ (اختياري)","What's in the meal? (optional)")).font(.subheadline);TextField("",text:$description,axis:.vertical).lineLimit(2...4).padding(12).background(Theme.card,in:RoundedRectangle(cornerRadius:12)).accessibilityLabel(diary.t("وصف الوجبة الاختياري","Optional meal description"))}
            if VisionAnalyzer.supported {
                Picker(diary.t("طريقة التحليل", "Analysis mode"), selection: $advanced) {
                    Text(diary.t("متقدم", "Advanced")).tag(true)
                    Text(diary.t("خفيف", "Lightweight")).tag(false)
                }.pickerStyle(.segmented).disabled(busy)
            }
            Notice(text:advanced ? diary.t("يختار نموذجًا متقدمًا يناسب ذاكرة التطبيق: نحو ١٫٨ جيجابايت لأجهزة ٨ جيجابايت، أو ٣٫١ جيجابايت عند توفر ذاكرة كافية. استخدم Wi-Fi واترك الشاشة مفتوحة. يعمل دون إنترنت بعد التنزيل.", "Selects an advanced model that fits the app's memory: about 1.8 GB on 8 GB devices, or 3.1 GB when enough memory is available. Use Wi-Fi and keep this screen open. Works offline after download.") : diary.t("تحليل خفيف للأصناف المعروفة. ينزّل نحو ١٧٧ ميجابايت أول مرة، ثم يعمل دون إنترنت. ذكر المكونات وعدد القطع يساعده. التحليل المتقدم يحتاج ذاكرة جهاز ٨ جيجابايت.", "Lightweight analysis recognizes known foods. First use downloads about 177 MB, then works offline. Ingredients and counts help. Advanced analysis requires an 8 GB device."))
            if recoveredRun{Notice(text:diary.t("توقف التحليل السابق قبل اكتماله. المحاولة التالية تستخدم النموذج المتقدم الأصغر مع فحص الذاكرة؛ ملفات التنزيل السابقة محفوظة.", "The previous analysis stopped before finishing. The next attempt uses the smaller advanced model with memory checks; existing downloads are preserved."))}
            Button{analyze()}label:{Label(diary.t("تحليل الوجبة","Analyze meal"),systemImage:"sparkles").frame(maxWidth:.infinity).padding(12)}.buttonStyle(.borderedProminent).disabled(imageData==nil || busy)
            if busy{HStack{ProgressView();Text(stageText).font(.footnote);Spacer();Button(diary.t("إلغاء","Cancel")){analysisTask?.cancel()}}}
            if let error{Text(error).foregroundStyle(.orange).font(.footnote)}
            if !parts.isEmpty{review}
        }.sheet(isPresented:$camera){CameraPhoto{data in camera=false;if let data{imageData=data;parts=[];error=nil}}.ignoresSafeArea()}
            .sheet(item:$selection){request in AnyView(FoodAddView(initial:products[request.id]?.0,initialQuery:request.name,productSelection:true){food,amount,unit,_ in
                guard FoodSearch.isOpenFoodFacts(food),(try? food.total(amount,unit:unit)) != nil else{return false}
                if !parts.contains(where:{$0.id==request.id}) {
                    let n=food.values(for:food.unit) ?? .zero
                    let label=PhotoFood(id:food.id,name:food.name,nameEn:food.nameEn ?? food.name,grams:1,kcal:n.kcal,protein:n.protein,carbs:n.carbs,fat:n.fat)
                    parts.append(PhotoPart(id:request.id,food:label,grams:1,low:1,high:1,basis:"selected"))
                }
                products[request.id]=(food,amount,unit);selection=nil;return true
            })}
            .onChange(of:item){_,value in Task{guard let value else{return};do{imageData=try await value.loadTransferable(type:Data.self);parts=[];error=nil}catch{self.error=error.localizedDescription}}}
            .onChange(of:imageData){_,data in products.removeAll();preview=data.flatMap{try? PhotoAnalyzer.image($0,maxPixels:640)}.map{UIImage(cgImage:$0)}}
            .onChange(of:phase){_,value in if value != .active,busy{cancellationMessage=diary.t("توقف التحليل عند مغادرة الشاشة. ملفات النموذج محفوظة؛ افتح التطبيق واضغط تحليل مجددًا.", "Analysis stopped when the app left the foreground. Model files are preserved; reopen the app and analyze again.");analysisTask?.cancel()}}
            .onReceive(NotificationCenter.default.publisher(for:UIApplication.didReceiveMemoryWarningNotification)){_ in if busy{cancellationMessage=diary.t("أوقفنا التحليل بسبب ضغط الذاكرة. أعد فتح لقمة وحاول مجددًا أو اختر التحليل الخفيف.", "Analysis stopped because of memory pressure. Reopen Luqma and retry or choose lightweight analysis.");analysisTask?.cancel()}}
            .task{recoveredRun=await VisionAnalyzer.shared.recoverInterruptedRun()}
            .onDisappear{analysisTask?.cancel()}
    }
    private var stageText:String {
        if stage.hasPrefix("download") { return diary.t("تنزيل النموذج… ", "Downloading model… ") + (stage.contains(":") ? stage.replacingOccurrences(of: "download:", with: "") + "%" : "") }
        if stage=="verify" { return diary.t("التحقق من النموذج…", "Verifying model…") }
        if stage=="load" { return diary.t("تجهيز الذكاء الاصطناعي…", "Loading the vision model…") }
        if stage=="memory" || stage.hasPrefix("model:") {return diary.t("فحص الذاكرة واختيار النموذج…", "Checking memory and selecting a model…")}
        if stage=="vision" { return diary.t("تحليل المكونات والكميات…", "Analyzing components and portions…") }
        if stage=="audit" { return diary.t("مراجعة ثانية للمكونات والكميات…", "Reviewing components and portions again…") }
        if stage=="validate" { return diary.t("مراجعة القيم الغذائية…", "Checking nutrition…") }
        return diary.t("فحص مكونات الصورة…", "Inspecting image regions…") + " " + stage.replacingOccurrences(of:"analyze:",with:"")
    }
    private var review:some View {
        VStack(alignment:.leading,spacing:16){
            Text(diary.t("اختر منتجات الوجبة","Choose meal products")).font(.title3.bold())
            Text(diary.t("الصورة تقترح الأصناف فقط. اختر المنتج والكمية من Open Food Facts لكل مكوّن قبل الإضافة.","The photo suggests food names only. Choose an Open Food Facts product and amount for each component before logging.")).font(.footnote).foregroundStyle(Theme.muted)
            ForEach(parts){part in
                VStack(alignment:.leading,spacing:10){
                    HStack{
                        Text(part.food.food.label(diary.language)).font(.headline)
                        Spacer()
                        Button(role:.destructive){parts.removeAll{$0.id==part.id};products.removeValue(forKey:part.id)}label:{Image(systemName:"minus.circle")}.accessibilityLabel(diary.t("إزالة المكوّن","Remove component"))
                    }
                    if let product=products[part.id] {
                        Text(product.0.label(diary.language)).font(.subheadline)
                        Text("\(decimal(product.1)) \(product.2.label(diary.language)) · Open Food Facts").font(.caption).foregroundStyle(Theme.muted)
                        if let nutrition=try? product.0.total(product.1,unit:product.2){NutritionView(value:nutrition)}
                    }else if part.basis != "selected" {
                        Text(diary.t("وزن تقريبي من الصورة: ","Rough photo weight: ")+decimal(part.grams,0)+diary.t(" جم — راجع الكمية عند اختيار المنتج"," g — review the amount when choosing a product")).font(.caption).foregroundStyle(Theme.muted)
                    }
                    Button{selection=ProductSelection(id:part.id,name:part.food.food.label(diary.language))}label:{Label(diary.t(products[part.id]==nil ? "اختيار المنتج والكمية":"تغيير المنتج أو الكمية",products[part.id]==nil ? "Choose product and amount":"Change product or amount"),systemImage:"magnifyingglass")}.buttonStyle(.bordered)
                }.luqmaCard()
            }
            Button{selection=ProductSelection(id:UUID(),name:"")}label:{Label(diary.t("إضافة مكوّن","Add component"),systemImage:"plus.circle")}
            if !products.isEmpty {NutritionView(value:total,large:true).luqmaCard()}
            Picker(diary.t("الوجبة","Meal"),selection:$meal){ForEach(Meal.allCases){Text($0.label(diary.language)).tag($0)}}
            Button(diary.t("إضافة المنتجات المحددة","Log selected products")){
                let values=parts.compactMap{products[$0.id]}
                if onCommit(values,meal){parts=[];products=[:]}
            }.buttonStyle(.borderedProminent).disabled(parts.isEmpty || parts.contains{products[$0.id]==nil})
        }
    }
    private func analyze(){guard let imageData else{return};busy=true;error=nil;cancellationMessage=nil;parts=[];products=[:];stage=""
        analysisTask=Task{do{
            let refs=try await PhotoAnalyzer.shared.foods()
            let result:PhotoResult
            if advanced {
                result=try await VisionAnalyzer.shared.analyze(imageData,description:description,foods:refs){value in Task{@MainActor in stage=value;if value.hasPrefix("model:"){activeModel=String(value.dropFirst(6))}}}
                engine=diary.t("تحليل متقدم • ", "Advanced analysis • ")+activeModel+diary.t(" • على الجهاز", " • on-device")
            } else {
                result=try await PhotoAnalyzer.shared.analyze(imageData,description:description){value in Task{@MainActor in stage=value}}
                engine=diary.t("تحليل خفيف • CLIP • على الجهاز", "Lightweight analysis • CLIP • on-device")
            }
            try Task.checkCancellation();references=refs;parts=result.parts;sauceSuggested=result.sauceSuggested;unmatched=result.unmatched
            if parts.isEmpty{error=diary.t("لم تتضح مكونات الطعام. جرّب صورة أقرب ووصفًا اختياريًا.","Food components were unclear. Try a closer photo and an optional description.")}
        }catch is CancellationError{error=cancellationMessage}catch{self.error=Task.isCancelled ? cancellationMessage : ((error as? AppError)?.message(diary.language) ?? diary.t("تعذّر التحليل. تحقق من الاتصال والمساحة لتنزيل النموذج؛ يمكنك إعادة المحاولة أو اختيار التحليل الخفيف.","Analysis failed. Check your connection and storage for the model download; retry or choose lightweight analysis."))};busy=false;analysisTask=nil}
    }
}
