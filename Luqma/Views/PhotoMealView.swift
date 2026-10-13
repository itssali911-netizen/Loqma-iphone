import SwiftUI
import PhotosUI
import UIKit

@MainActor struct PhotoMealView:View {
    var initialMeal:Meal?=nil
    var onCommit:PhotoFoodCommit
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.scenePhase) private var phase
    @State private var item:PhotosPickerItem?
    @State private var imageData:Data?
    @State private var preview:UIImage?
    @State private var camera=false,busy=false,showingSetup=false
    @State private var description=""
    @State private var error:String?,cancellationMessage:String?
    @State private var parts:[PhotoPart]=[]
    private struct ProductSelection:Identifiable {var id:UUID;var name:String}
    private struct EstimateSelection:Identifiable {var id:UUID;var estimate:MealPhotoEstimate}
    @State private var selection:ProductSelection?
    @State private var editing:EstimateSelection?
    @State private var products:[UUID:(Food,Double,FoodUnit)]=[:]
    @State private var meal:Meal = .lunch
    @State private var analysisTask:Task<Void,Never>?
    @State private var photoLoadTask:Task<Void,Never>?
    @State private var photoGeneration=UUID(),analysisGeneration=UUID()
    @State private var loadingPhoto=false
    @State private var ready=GeminiCredentialStore.isConfigured
    // Missing nutrition must never become zero or disappear from the meal.
    private var total:Nutrition? {
        guard !parts.isEmpty else{return nil};var value=Nutrition.zero
        for part in parts {
            guard let product=products[part.id],FoodSearch.isCatalogFood(product.0) || MealPhotoEstimate.isValidPhotoEstimate(product.0),
                  let n=try? product.0.total(product.1,unit:product.2),n.valid else{return nil}
            value=value+n
        };return value.valid ? value:nil
    }
    private var calorieRange:(Double,Double)? {
        guard total != nil else{return nil};var low=0.0,high=0.0;var estimated=false
        for part in parts {
            guard let product=products[part.id],let n=try? product.0.total(product.1,unit:product.2) else{return nil}
            if MealPhotoEstimate.isValidPhotoEstimate(product.0),let e=part.mealEstimate {low+=e.kcalLow*product.1;high+=e.kcalHigh*product.1;estimated=true}
            else{low+=n.kcal;high+=n.kcal}
        };return estimated ? (low,high):nil
    }
    var body:some View {
        VStack(alignment:.leading,spacing:18){
            if let preview{Image(uiImage:preview).resizable().scaledToFit().frame(maxHeight:240).clipShape(RoundedRectangle(cornerRadius:20))}
            HStack{
                PhotosPicker(selection:$item,matching:.images){Label(diary.t("رفع صورة","Choose photo"),systemImage:"photo")}.buttonStyle(.bordered)
                Button{Task{if UIImagePickerController.isSourceTypeAvailable(.camera),await CameraAccess.request(){camera=true}else{error=diary.t("الكاميرا غير متاحة أو تحتاج إذنًا من الإعدادات.","Camera is unavailable or needs access in Settings.")}}}label:{Label(diary.t("الكاميرا","Camera"),systemImage:"camera")}.buttonStyle(.bordered)
            }.disabled(busy)
            VStack(alignment:.leading,spacing:8){
                Text(diary.t("وصف الوجبة (اختياري)","Meal description (optional)")).font(.subheadline.bold())
                TextField(diary.t("مثلاً: الوزن، طريقة الطبخ وكمية الزيت","For example: weight, cooking method and oil amount"),text:$description,axis:.vertical).lineLimit(2...4).padding(12).background(Theme.card,in:RoundedRectangle(cornerRadius:12)).accessibilityLabel(diary.t("وصف الوجبة الاختياري","Optional meal description")).disabled(busy)
                Notice(text:diary.t("تُرسل الصورة والوصف لخدمة التحليل. الوزن والزيت والصلصات تؤثر في التقدير؛ أضف ما تعرفه لتحسينه.","The photo and description are sent to the analysis service. Weight, oil and sauces affect the estimate; add what you know to improve it."))
            }
            if loadingPhoto{ProgressView(diary.t("تجهيز الصورة…","Preparing photo…"))}
            Button{if ready{analyze()}else{showingSetup=true}}label:{Label(diary.t("تحليل الوجبة","Meal analysis"),systemImage:"sparkles")}.buttonStyle(LuqmaPrimaryButtonStyle()).disabled(imageData==nil || busy || loadingPhoto)
            if busy{HStack{ProgressView();Text(diary.t("تقدير المكونات والسعرات…","Estimating components and calories…")).font(.footnote);Spacer();Button(diary.t("إلغاء","Cancel")){analysisTask?.cancel()}}}
            if let error{Text(error).foregroundStyle(.orange).font(.footnote)}
            if !parts.isEmpty{review}
        }
        .sheet(isPresented:$camera){CameraPhoto{data in camera=false;if let data{photoGeneration=UUID();photoLoadTask?.cancel();loadingPhoto=false;imageData=data;parts=[];error=nil}}.ignoresSafeArea()}
        .sheet(isPresented:$showingSetup,onDismiss:{ready=GeminiCredentialStore.isConfigured}){GeminiSettingsView()}
        .sheet(item:$editing){request in PhotoEstimateEditor(estimate:request.estimate){updated in
            guard let index=parts.firstIndex(where:{$0.id==request.id}) else{return false}
            do{let food=try updated.food(name:parts[index].food.name,nameEn:parts[index].food.nameEn,identity:request.id,language:diary.language)
                parts[index].mealEstimate=updated;parts[index].grams=updated.grams;parts[index].low=updated.low;parts[index].high=updated.high
                products[request.id]=(food,1,.serving);editing=nil;return true
            }catch{diary.report(error);return false}
        }}
        .sheet(item:$selection){request in FoodAddView(initial:products[request.id].flatMap{FoodSearch.isCatalogFood($0.0) ? $0.0:nil},initialQuery:request.name,productSelection:true){food,amount,unit,_ in
            guard FoodSearch.isCatalogFood(food),(try? food.total(amount,unit:unit)) != nil else{return false}
            if !parts.contains(where:{$0.id==request.id}){
                guard let n=food.values(for:food.unit) else{return false}
                let label=PhotoFood(id:food.id,name:food.name,nameEn:food.nameEn ?? food.name,grams:1,kcal:n.kcal,protein:n.protein,carbs:n.carbs,fat:n.fat)
                parts.append(PhotoPart(id:request.id,food:label,grams:1,low:1,high:1,basis:"selected"))
            };products[request.id]=(food,amount,unit);selection=nil;return true
        }}
        .onChange(of:item){_,value in loadPhoto(value)}
        .onChange(of:imageData){_,data in analysisGeneration=UUID();analysisTask?.cancel();analysisTask=nil;busy=false;parts=[];products.removeAll();preview=data.flatMap{try? PhotoAnalyzer.image($0,maxPixels:640)}.map{UIImage(cgImage:$0)}}
        .onChange(of:phase){_,value in if value != .active,busy{cancellationMessage=diary.t("توقف التحليل عند مغادرة الشاشة. افتح التطبيق وحاول مجددًا.","Analysis stopped when the app left the foreground. Reopen the app and retry.");analysisTask?.cancel()}}
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.didReceiveMemoryWarningNotification)){_ in if busy{cancellationMessage=diary.t("توقف التحليل بسبب ضغط الذاكرة. حاول مجددًا.","Analysis stopped because of memory pressure. Retry.");analysisTask?.cancel()}}
        .onAppear{if let initialMeal{meal=initialMeal};ready=GeminiCredentialStore.isConfigured
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-loqma-preview-photo"),parts.isEmpty{preparePreview()}
            #endif
        }
        .onDisappear{photoGeneration=UUID();analysisGeneration=UUID();photoLoadTask?.cancel();analysisTask?.cancel()}
    }
    private var review:some View {
        VStack(alignment:.leading,spacing:16){
            VStack(alignment:.leading,spacing:10){
                Text(diary.t("تقدير الوجبة","Meal estimate")).font(.title3.bold())
                if let total{NutritionView(value:total,large:true)}
                if let range=calorieRange{Text(diary.t("النطاق التقريبي: ","Estimated range: ")+decimal(range.0,0)+"–"+decimal(range.1,0)+diary.t(" سعرة"," kcal")).font(.caption).foregroundStyle(Theme.muted)}
                Notice(text:diary.t("راجع الكمية قبل الإضافة. التقدير من الصورة قد يتغير حسب الزيت والصلصات وطريقة التحضير.","Review the amount before logging. Photo estimates vary with oil, sauces and preparation."))
            }.luqmaCard()
            ForEach(parts){part in component(part)}
            Button{selection=ProductSelection(id:UUID(),name:"")}label:{Label(diary.t("إضافة مكوّن","Add component"),systemImage:"plus.circle")}
            Picker(diary.t("الوجبة","Meal"),selection:$meal){ForEach(Meal.allCases){Text($0.label(diary.language)).tag($0)}}.pickerStyle(.menu)
            Button(diary.t("إضافة الوجبة","Log meal")){
                guard total != nil else{return};let values=parts.compactMap{products[$0.id]};guard values.count==parts.count else{return}
                if onCommit(values,meal){parts=[];products=[:]}
            }.buttonStyle(LuqmaPrimaryButtonStyle()).disabled(total==nil)
        }
    }
    private func component(_ part:PhotoPart)->some View {
        VStack(alignment:.leading,spacing:10){
            HStack{Text(products[part.id]?.0.label(diary.language) ?? part.food.food.label(diary.language)).font(.headline);Spacer();Button(role:.destructive){parts.removeAll{$0.id==part.id};products.removeValue(forKey:part.id)}label:{Image(systemName:"minus.circle")}.accessibilityLabel(diary.t("إزالة المكوّن","Remove component"))}
            if let product=products[part.id],let n=try? product.0.total(product.1,unit:product.2){
                Text(MealPhotoEstimate.isValidPhotoEstimate(product.0) ? diary.t("حصة تقديرية · ","Estimated portion · ")+decimal(part.grams,0)+diary.t(" جم"," g") : decimal(product.1)+" "+product.2.label(diary.language)).font(.caption).foregroundStyle(Theme.muted)
                NutritionView(value:n)
                if MealPhotoEstimate.isValidPhotoEstimate(product.0),let e=part.mealEstimate{
                    Notice(text:diary.language == .ar ? e.assumptions:e.assumptionsEn)
                    Button{editing=EstimateSelection(id:part.id,estimate:e)}label:{Label(diary.t("تعديل الكمية","Adjust amount"),systemImage:"slider.horizontal.3")}.buttonStyle(.bordered)
                }
            }else{Notice(text:diary.t("أكمل بيانات هذا المكوّن قبل الحفظ.","Complete this component before logging."))}
            Button{selection=ProductSelection(id:part.id,name:part.food.food.label(diary.language))}label:{Label(diary.t("اختيار منتج من قاعدة الطعام","Choose a catalog product"),systemImage:"magnifyingglass")}.font(.subheadline).buttonStyle(.borderless)
        }.luqmaCard()
    }
    private func loadPhoto(_ value:PhotosPickerItem?){
        photoLoadTask?.cancel();let token=UUID();photoGeneration=token
        guard let value else{loadingPhoto=false;return};loadingPhoto=true;imageData=nil;parts=[];products=[:];error=nil
        photoLoadTask=Task{do{
            let data=try await value.loadTransferable(type:Data.self);try Task.checkCancellation()
            guard photoGeneration==token else{return};imageData=data
        }catch{guard photoGeneration==token,!Task.isCancelled else{return};self.error=diary.t("تعذّر فتح الصورة. اختر صورة أخرى.","The photo could not be opened. Choose another photo.")}
            if photoGeneration==token{loadingPhoto=false;photoLoadTask=nil}
        }
    }
    private func analyze(){guard let imageData,!loadingPhoto else{return};busy=true;error=nil;cancellationMessage=nil;parts=[];products=[:]
        let token=UUID();analysisGeneration=token;let context=description,language=diary.language
        analysisTask=Task{do{
            let result=try await GeminiMealService.shared.analyze(imageData:imageData,context:context,language:language);try Task.checkCancellation();guard analysisGeneration==token else{return}
            var prepared:[UUID:(Food,Double,FoodUnit)]=[:]
            for part in result.parts{guard let e=part.mealEstimate else{throw AppError.invalid("تقدير الوجبة غير مكتمل. حاول مجددًا.","The meal estimate is incomplete. Retry.")};prepared[part.id]=(try e.food(name:part.food.name,nameEn:part.food.nameEn,identity:part.id,language:diary.language),1,.serving)}
            parts=result.parts;products=prepared
        }catch is CancellationError{if analysisGeneration==token{error=cancellationMessage}}catch{if analysisGeneration==token{self.error=Task.isCancelled ? cancellationMessage:((error as? AppError)?.message(diary.language) ?? diary.t("تعذّر التحليل. تحقق من الاتصال وحاول مجددًا.","Analysis failed. Check your connection and retry."))}};if analysisGeneration==token{busy=false;analysisTask=nil}}
    }
    #if DEBUG
    // Synthetic UI fixture uses the production review; never calls a service,
    // logs a meal, or enters the Release app.
    private func preparePreview(){
        do{
            let estimate=try MealPhotoEstimate(grams:250,low:200,high:320,nutrition:Nutrition(kcal:550,protein:35,carbs:50,fat:23),kcalLow:430,kcalHigh:720,assumptions:"وزن تقريبي؛ راجع كمية الزيت والصلصة.",assumptionsEn:"Approximate weight; review oil and sauce amounts.")
            let photo=PhotoFood(id:"preview",name:"دجاج مع الأرز",nameEn:"Chicken with rice",grams:250,kcal:220,protein:14,carbs:20,fat:9.2)
            let part=PhotoPart(food:photo,grams:250,low:200,high:320,basis:"photo-estimate",tentative:true,mealEstimate:estimate)
            parts=[part];products[part.id]=(try estimate.food(name:photo.name,nameEn:photo.nameEn,identity:part.id,language:diary.language),1,.serving)
        }catch{self.error=diary.t("تعذّر تجهيز المعاينة.","Preview could not be prepared.")}
    }
    #endif
}

private struct PhotoEstimateEditor:View {
    let estimate:MealPhotoEstimate;let apply:(MealPhotoEstimate)->Bool
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var grams:Double
    init(estimate:MealPhotoEstimate,apply:@escaping(MealPhotoEstimate)->Bool){self.estimate=estimate;self.apply=apply;_grams=State(initialValue:estimate.grams)}
    private var updated:MealPhotoEstimate?{try? estimate.scaled(toGrams:grams)}
    var body:some View {NavigationStack{Form{
        Section(diary.t("الكمية","Amount")){NumericInput(title:diary.t("الوزن","Weight"),value:$grams,suffix:diary.t("جم","g"))}
        Section{if let updated{NutritionView(value:updated.nutrition)};Notice(text:diary.t("تتغير السعرات مع الوزن. إذا كانت طريقة الطبخ أو كمية الزيت مختلفة، أضف وصفها وأعد التحليل.","Calories scale with weight. If preparation or oil differs, describe it and analyze again."))}
    }.appBackground().navigationTitle(diary.t("تعديل الكمية","Adjust amount")).toolbar{
        ToolbarItem(placement:.cancellationAction){Button(diary.t("إلغاء","Cancel")){dismiss()}}
        ToolbarItem(placement:.confirmationAction){Button(diary.t("حفظ","Save")){if let updated,apply(updated){dismiss()}}.disabled(updated==nil)}
    }}}
}
