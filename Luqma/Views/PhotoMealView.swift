import SwiftUI
import PhotosUI
import UIKit

@MainActor struct PhotoMealView:View {
    var initialMeal:Meal?=nil
    var onCommit:PhotoFoodCommit
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var item:PhotosPickerItem?
    @State private var imageData:Data?
    @State private var preview:UIImage?
    @State private var camera=false
    @State private var busy=false
    @State private var showingSetup=false
    @State private var showingPhotoInput=false
    @State private var detailedComponents=false
    @State private var description=""
    @State private var error:String?
    @State private var cancellationMessage:String?
    @State private var parts:[PhotoPart]=[]
    private struct ProductSelection:Identifiable {var id:UUID;var name:String}
    private struct EstimateSelection:Identifiable {var id:UUID;var estimate:MealPhotoEstimate}
    @State private var selection:ProductSelection?
    @State private var editing:EstimateSelection?
    @State private var products:[UUID:(Food,Double,FoodUnit)]=[:]
    @State private var meal:Meal = .lunch
    @State private var analysisTask:Task<Void,Never>?
    @State private var photoLoadTask:Task<Void,Never>?
    @State private var photoGeneration=UUID()
    @State private var analysisGeneration=UUID()
    @State private var loadingPhoto=false
    @State private var ready=GeminiCredentialStore.isConfigured
    @FocusState private var descriptionFocused:Bool
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
        VStack(alignment:.leading,spacing:20){
            if parts.isEmpty{photoInput}
            else{
                review
                DisclosureGroup(isExpanded:$showingPhotoInput){photoInput.padding(.top,12)}label:{
                    Label(diary.t("الصورة وإعادة التحليل","Photo and reanalysis"),systemImage:"camera")
                        .luqmaFont(.subheadline).foregroundStyle(Theme.text)
                }.luqmaCard()
            }
        }
        .sheet(isPresented:$camera){CameraPhoto{data in camera=false;if let data{photoGeneration=UUID();photoLoadTask?.cancel();loadingPhoto=false;imageData=data;parts=[];error=nil}}.ignoresSafeArea()}
        .sheet(isPresented:$showingSetup,onDismiss:{ready=GeminiCredentialStore.isConfigured}){GeminiSettingsView()}
        .sheet(item:$editing){request in PhotoEstimateEditor(title:componentName(request.id),estimate:request.estimate){updated in
            guard let index=parts.firstIndex(where:{$0.id==request.id}) else{return false}
            do{let food=try updated.food(name:parts[index].food.name,nameEn:parts[index].food.nameEn,identity:request.id,language:diary.language)
                parts[index].mealEstimate=updated;parts[index].grams=updated.grams;parts[index].low=updated.low;parts[index].high=updated.high
                products[request.id]=(food,1,.serving);editing=nil;return true
            }catch{diary.report(error);return false}
        }}
        .sheet(item:$selection){request in AnyView(FoodAddView(initial:products[request.id].flatMap{FoodSearch.isCatalogFood($0.0) ? $0.0:nil},initialQuery:request.name,productSelection:true){food,amount,unit,_ in
            guard FoodSearch.isCatalogFood(food),(try? food.total(amount,unit:unit)) != nil else{return false}
            if !parts.contains(where:{$0.id==request.id}){
                guard let n=food.values(for:food.unit) else{return false}
                let label=PhotoFood(id:food.id,name:food.name,nameEn:food.nameEn ?? food.name,grams:1,kcal:n.kcal,protein:n.protein,carbs:n.carbs,fat:n.fat)
                parts.append(PhotoPart(id:request.id,food:label,grams:1,low:1,high:1,basis:"selected"))
            };products[request.id]=(food,amount,unit);selection=nil;return true
        })}
        .onChange(of:item){_,value in loadPhoto(value)}
        .onChange(of:imageData){_,data in analysisGeneration=UUID();analysisTask?.cancel();analysisTask=nil;busy=false;parts=[];products.removeAll();detailedComponents=false;showingPhotoInput=false;preview=data.flatMap{try? PhotoAnalyzer.image($0,maxPixels:640)}.map{UIImage(cgImage:$0)}}
        .onChange(of:phase){_,value in if value != .active,busy{cancellationMessage=diary.t("توقف التحليل عند مغادرة الشاشة. افتح التطبيق وحاول مجددًا.","Analysis stopped when the app left the foreground. Reopen the app and retry.");analysisTask?.cancel()}}
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.didReceiveMemoryWarningNotification)){_ in if busy{cancellationMessage=diary.t("توقف التحليل بسبب ضغط الذاكرة. حاول مجددًا.","Analysis stopped because of memory pressure. Retry.");analysisTask?.cancel()}}
        .onAppear{if let initialMeal{meal=initialMeal};ready=GeminiCredentialStore.isConfigured
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-loqma-preview-photo"),parts.isEmpty{preparePreview()}
            #endif
        }
        .onDisappear{photoGeneration=UUID();analysisGeneration=UUID();photoLoadTask?.cancel();analysisTask?.cancel()}
    }
    private var photoInput:some View {
        VStack(alignment:.leading,spacing:16){
            if let preview{
                Image(uiImage:preview).resizable().scaledToFit().frame(maxWidth:.infinity,maxHeight:240)
                    .background(Theme.card,in:RoundedRectangle(cornerRadius:20)).clipShape(RoundedRectangle(cornerRadius:20))
            }else if parts.isEmpty{
                VStack(spacing:12){Image(systemName:"camera.viewfinder").font(.system(size:36,weight:.light)).foregroundStyle(Theme.accent);Text(diary.t("صوّر وجبتك أو اختر صورتها","Take or choose a meal photo")).luqmaFont(.subheadline).foregroundStyle(Theme.muted)}
                    .frame(maxWidth:.infinity,minHeight:140).background(Theme.card,in:RoundedRectangle(cornerRadius:20)).accessibilityElement(children:.combine)
            }
            HStack(spacing:12){
                PhotosPicker(selection:$item,matching:.images){Label(diary.t("رفع صورة","Choose photo"),systemImage:"photo")}.buttonStyle(LuqmaSecondaryButtonStyle())
                Button{Task{if UIImagePickerController.isSourceTypeAvailable(.camera),await CameraAccess.request(){camera=true}else{error=diary.t("الكاميرا غير متاحة أو تحتاج إذنًا من الإعدادات.","Camera is unavailable or needs access in Settings.")}}}label:{Label(diary.t("الكاميرا","Camera"),systemImage:"camera")}.buttonStyle(LuqmaSecondaryButtonStyle())
            }.disabled(busy)
            VStack(alignment:.leading,spacing:8){
                Text(diary.t("وصف الوجبة (اختياري)","Meal description (optional)")).luqmaFont(size:15,weight:.bold,relativeTo:.subheadline)
                TextField(diary.t("مثلاً: الوزن، طريقة الطبخ وكمية الزيت","For example: weight, cooking method and oil amount"),text:$description,axis:.vertical).focused($descriptionFocused).lineLimit(2...4).padding(16).background(Theme.card,in:RoundedRectangle(cornerRadius:16)).accessibilityLabel(diary.t("وصف الوجبة الاختياري","Optional meal description")).disabled(busy)
                Notice(text:diary.t("تُرسل الصورة والوصف لخدمة التحليل. الوزن والزيت والصلصات تؤثر في التقدير؛ أضف ما تعرفه لتحسينه.","The photo and description are sent to the analysis service. Weight, oil and sauces affect the estimate; add what you know to improve it."))
            }
            if loadingPhoto{ProgressView(diary.t("تجهيز الصورة…","Preparing photo…"))}
            Button{if ready{analyze()}else{showingSetup=true}}label:{Label(diary.t("تحليل الوجبة","Meal analysis"),systemImage:"sparkles")}.buttonStyle(LuqmaPrimaryButtonStyle()).disabled(imageData==nil || busy || loadingPhoto)
            if busy{HStack(spacing:12){ProgressView().tint(Theme.accent);Text(diary.t("تقدير المكونات والسعرات…","Estimating components and calories…")).luqmaFont(.footnote);Spacer(minLength:0);Button(diary.t("إلغاء","Cancel")){analysisTask?.cancel()}.frame(minHeight:44)}.luqmaCard()}
            if let error{Label(error,systemImage:"exclamationmark.circle").foregroundStyle(Theme.accent).luqmaFont(.footnote).fixedSize(horizontal:false,vertical:true).luqmaCard()}
        }
    }
    private var review:some View {
        let summary=total
        return VStack(alignment:.leading,spacing:16){
            Label(diary.t("تقديرات تقريبية تتأثر بالكمية وطريقة التحضير","Estimates vary with amount and preparation"),systemImage:"sparkles")
                .luqmaFont(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true)
                .padding(12).frame(maxWidth:.infinity,alignment:.leading)
                .background(Theme.accent.opacity(0.08),in:RoundedRectangle(cornerRadius:14))
            resultHeader
            if let summary{estimateSummary(summary)}
            else{Notice(text:diary.t("أكمل بيانات جميع المكونات لعرض إجمالي الوجبة وحفظها.","Complete every component to see and log the meal total.")).luqmaCard()}
            VStack(alignment:.leading,spacing:10){
                LuqmaSectionHeader(title:diary.t("المكونات","Components"),detail:typeSize.isAccessibilitySize ? nil:diary.t("الوزن والسعرات لكل مكوّن","Weight and calories per component"))
                HStack(spacing:8){componentMode(diary.t("مختصر","Compact"),detailed:false);componentMode(diary.t("تفصيلي","Detailed"),detailed:true)}
            }.id("photo-components")
            ForEach(parts){part in component(part)}
            Button{selection=ProductSelection(id:UUID(),name:"")}label:{Label(diary.t("إضافة مكوّن","Add component"),systemImage:"plus.circle")}.buttonStyle(LuqmaSecondaryButtonStyle())
            mealChoice
            Button(diary.t("إضافة الوجبة","Log meal")){
                guard total != nil else{return};let values=parts.compactMap{products[$0.id]};guard values.count==parts.count else{return}
                if onCommit(values,meal){parts=[];products=[:]}
            }.buttonStyle(LuqmaPrimaryButtonStyle()).disabled(summary==nil || busy || loadingPhoto)
        }
    }
    private var resultHeader:some View {
        HStack(spacing:14){
            Image(systemName:"fork.knife").font(.system(size:24,weight:.medium))
                .foregroundStyle(Theme.accent).frame(width:56,height:56)
                .background(Theme.surface,in:RoundedRectangle(cornerRadius:16)).accessibilityHidden(true)
            VStack(alignment:.leading,spacing:8){
                Text(parts.count == 1 ? componentName(parts[0].id):diary.t("وجبتك من الصورة","Your meal from the photo"))
                    .luqmaFont(size:21,weight:.bold,relativeTo:.title2).fixedSize(horizontal:false,vertical:true)
                Text(diary.t("المكوّنات: ","Components: ")+decimal(Double(parts.count),0))
                    .luqmaFont(.caption).foregroundStyle(Theme.accent)
                    .padding(.horizontal,10).padding(.vertical,4)
                    .background(Theme.accent.opacity(0.1),in:Capsule())
            }
            Spacer(minLength:0)
        }.luqmaCard()
    }
    private func estimateSummary(_ nutrition:Nutrition)->some View {
        VStack(alignment:.leading,spacing:18){
            if typeSize.isAccessibilitySize{
                calorieValue(nutrition.kcal)
                calorieContribution(nutrition.kcal)
            }else{
                HStack(spacing:20){
                    ZStack{
                        LuqmaProgressRing(progress:goalProgress(nutrition.kcal,goal:diary.state.goals.kcal) ?? 0,color:Theme.accent,lineWidth:8)
                        calorieValue(nutrition.kcal)
                    }.frame(width:124,height:124)
                    calorieContribution(nutrition.kcal).frame(maxWidth:.infinity,alignment:.leading)
                }
            }
            Rectangle().fill(Theme.stroke).frame(height:1)
            if typeSize.isAccessibilitySize{
                VStack(spacing:16){ForEach(MacroKey.allCases){key in macroGoal(key,nutrition:nutrition)}}
            }else{
                HStack(alignment:.top,spacing:16){ForEach(MacroKey.allCases){key in macroGoal(key,nutrition:nutrition)}}
            }
        }.luqmaCard()
    }
    private func calorieValue(_ kcal:Double)->some View {
        VStack(spacing:2){
            Text(decimal(kcal,0)).luqmaFont(size:32,weight:.bold,relativeTo:.largeTitle).monospacedDigit().foregroundStyle(Theme.text)
            Text(diary.t("سعرة تقريبًا","estimated kcal")).luqmaFont(.caption).foregroundStyle(Theme.muted)
        }.accessibilityElement(children:.combine)
    }
    private func calorieContribution(_ kcal:Double)->some View {
        VStack(alignment:.leading,spacing:8){
            Text(diary.t("مساهمة الوجبة في هدفك اليومي","This meal's share of your daily goal"))
                .luqmaFont(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true)
            if let progress=goalProgress(kcal,goal:diary.state.goals.kcal){
                Text(decimal(progress*100)+"%")
                    .luqmaFont(size:27,weight:.bold,relativeTo:.title).monospacedDigit().foregroundStyle(Theme.accent)
                Text(diary.t("من ","of ")+decimal(diary.state.goals.kcal,0)+diary.t(" سعرة"," kcal"))
                    .luqmaFont(.caption).foregroundStyle(Theme.muted)
            }
            if let range=calorieRange{
                Text(diary.t("النطاق: ","Range: ")+decimal(range.0,0)+"–"+decimal(range.1,0)+diary.t(" سعرة"," kcal"))
                    .luqmaFont(.caption2).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true)
            }
        }.accessibilityElement(children:.combine)
    }
    private func macroGoal(_ key:MacroKey,nutrition:Nutrition)->some View {
        let goal=diary.state.goals[key]
        let color=key == .protein ? Theme.secondaryAccent:key == .carbs ? Theme.accent:Theme.text
        return VStack(alignment:.leading,spacing:6){
            HStack(spacing:5){Circle().fill(color).frame(width:6,height:6).accessibilityHidden(true);Text(key.label(diary.language)).luqmaFont(.caption).foregroundStyle(Theme.muted)}
            HStack(alignment:.firstTextBaseline,spacing:3){
                Text(decimal(nutrition[key])).luqmaFont(size:20,weight:.bold,relativeTo:.title3).monospacedDigit()
                Text(diary.t("جم","g")).luqmaFont(.caption).foregroundStyle(Theme.muted)
            }
            if let progress=goalProgress(nutrition[key],goal:goal){
                ProgressView(value:min(1,progress)).tint(color)
                    .accessibilityLabel(diary.t("مساهمة الوجبة في هدف ","This meal's share of the ")+key.label(diary.language))
                Text(diary.t("من ","of ")+decimal(goal,0)+diary.t(" جم"," g"))
                    .luqmaFont(.caption2).foregroundStyle(Theme.muted)
            }
        }.frame(maxWidth:.infinity,alignment:.leading).accessibilityElement(children:.combine)
    }
    private func goalProgress(_ amount:Double,goal:Double)->Double? {
        guard amount.isFinite,amount>=0,goal.isFinite,goal>0 else{return nil}
        return amount/goal
    }
    private func componentMode(_ title:String,detailed:Bool)->some View {
        Button{detailedComponents=detailed}label:{
            Label(title,systemImage:detailed ? "list.bullet":"square.stack")
                .luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline)
                .foregroundStyle(detailedComponents == detailed ? Theme.text:Theme.muted)
                .frame(maxWidth:.infinity,minHeight:44)
                .background(detailedComponents == detailed ? Theme.accent:Theme.card,in:RoundedRectangle(cornerRadius:14))
        }.buttonStyle(.plain).accessibilityAddTraits(detailedComponents == detailed ? .isSelected:[])
    }
    private var mealChoice:some View {
        VStack(alignment:.leading,spacing:10){
            LuqmaSectionHeader(title:diary.t("أضفها إلى","Log under"))
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:typeSize.isAccessibilitySize ? 2:4),spacing:8){
                ForEach(Meal.allCases){value in
                    Button{meal=value}label:{
                        VStack(spacing:6){
                            Image(systemName:value.symbol).font(.system(size:17,weight:.medium)).accessibilityHidden(true)
                            Text(value.label(diary.language)).luqmaFont(size:13,weight:.semibold,relativeTo:.caption)
                        }.foregroundStyle(meal == value ? Theme.text:Theme.muted)
                            .padding(.vertical,12).frame(maxWidth:.infinity)
                            .background(meal == value ? Theme.accent:Theme.card,in:RoundedRectangle(cornerRadius:16))
                    }.buttonStyle(.plain).accessibilityAddTraits(meal == value ? .isSelected:[])
                }
            }
        }
    }
    private func component(_ part:PhotoPart)->some View {
        let product=products[part.id]
        let nutrition=product.flatMap{try? $0.0.total($0.1,unit:$0.2)}
        return VStack(alignment:.leading,spacing:12){
            if typeSize.isAccessibilitySize{
                componentAmountButton(part)
                HStack{componentCalories(nutrition);Spacer(minLength:0);removeComponent(part)}
            }else{
                HStack(alignment:.center,spacing:12){componentAmountButton(part);componentCalories(nutrition);removeComponent(part)}
            }
            if detailedComponents{
                Rectangle().fill(Theme.stroke).frame(height:1)
                if let nutrition{
                    if typeSize.isAccessibilitySize{
                        VStack(spacing:12){componentMacro(diary.t("بروتين","Protein"),nutrition.protein);componentMacro(diary.t("كارب","Carbs"),nutrition.carbs);componentMacro(diary.t("دهون","Fat"),nutrition.fat)}
                    }else{
                        HStack(spacing:12){componentMacro(diary.t("بروتين","Protein"),nutrition.protein);componentMacro(diary.t("كارب","Carbs"),nutrition.carbs);componentMacro(diary.t("دهون","Fat"),nutrition.fat)}
                    }
                }
                if let product,MealPhotoEstimate.isValidPhotoEstimate(product.0),let estimate=part.mealEstimate{
                    Text(diary.t("نطاق الوزن: ","Weight range: ")+decimal(estimate.low*product.1,0)+"–"+decimal(estimate.high*product.1,0)+diary.t(" جم"," g"))
                        .luqmaFont(.caption).foregroundStyle(Theme.muted)
                    Notice(text:diary.language == .ar ? estimate.assumptions:estimate.assumptionsEn)
                }
                Button{selection=ProductSelection(id:part.id,name:part.food.food.label(diary.language))}label:{
                    Label(diary.t("مطابقة منتج من قاعدة الطعام","Match a catalog product"),systemImage:"magnifyingglass")
                        .luqmaFont(.caption).frame(maxWidth:.infinity,alignment:.leading).frame(minHeight:44)
                }.buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
            if nutrition==nil{Notice(text:diary.t("أكمل بيانات هذا المكوّن قبل الحفظ.","Complete this component before logging."))}
        }.luqmaCard()
    }
    private func componentAmountButton(_ part:PhotoPart)->some View {
        Button{adjust(part)}label:{
            VStack(alignment:.leading,spacing:6){
                Text(componentName(part.id)).luqmaFont(size:16,weight:.semibold,relativeTo:.headline)
                    .foregroundStyle(Theme.text).fixedSize(horizontal:false,vertical:true)
                HStack(spacing:5){
                    Text(componentAmount(part)).luqmaFont(.caption).fixedSize(horizontal:false,vertical:true)
                    Image(systemName:"pencil").font(.system(size:11,weight:.medium)).accessibilityHidden(true)
                }.foregroundStyle(Theme.muted)
            }.frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(componentName(part.id)+", "+componentAmount(part))
            .accessibilityHint(diary.t("اضغط لتعديل الكمية","Tap to adjust the amount"))
    }
    private func componentCalories(_ nutrition:Nutrition?)->some View {
        VStack(alignment:.trailing,spacing:2){
            if let nutrition{
                Text(decimal(nutrition.kcal,0)).luqmaFont(size:23,weight:.bold,relativeTo:.title2).monospacedDigit().foregroundStyle(Theme.accent)
                Text(diary.t("سعرة","kcal")).luqmaFont(.caption2).foregroundStyle(Theme.muted)
            }else{Text(diary.t("غير مكتمل","Incomplete")).luqmaFont(.caption).foregroundStyle(Theme.muted)}
        }.fixedSize(horizontal:true,vertical:false).accessibilityElement(children:.combine)
    }
    private func removeComponent(_ part:PhotoPart)->some View {
        Button(role:.destructive){parts.removeAll{$0.id==part.id};products.removeValue(forKey:part.id)}label:{
            Image(systemName:"trash").font(.system(size:17,weight:.regular)).foregroundStyle(Theme.muted).frame(minWidth:44,minHeight:44)
        }.buttonStyle(.plain).accessibilityLabel(diary.t("حذف ","Remove ")+componentName(part.id))
    }
    private func componentName(_ id:UUID)->String {
        products[id]?.0.label(diary.language) ?? parts.first(where:{$0.id==id})?.food.food.label(diary.language) ?? diary.t("مكوّن الوجبة","Meal component")
    }
    private func componentAmount(_ part:PhotoPart)->String {
        guard let product=products[part.id] else{return diary.t("الوزن غير محدد","Weight not specified")}
        if MealPhotoEstimate.isValidPhotoEstimate(product.0){
            return diary.t("تقدير الوزن · ","Estimated weight · ")+decimal(part.grams*product.1,0)+diary.t(" جم"," g")
        }
        if product.2 == .serving,let grams=product.0.servingQuantity,product.0.servingUnit == "g",grams.isFinite,grams>0{
            return decimal(grams*product.1,0)+diary.t(" جم · "," g · ")+decimal(product.1)+" "+product.2.label(diary.language)
        }
        // A volume or a serving with no declared gram weight stays in its source unit.
        return decimal(product.1)+" "+product.2.label(diary.language)
    }
    private func adjust(_ part:PhotoPart){
        if let product=products[part.id],MealPhotoEstimate.isValidPhotoEstimate(product.0),let estimate=part.mealEstimate{
            editing=EstimateSelection(id:part.id,estimate:estimate)
        }else{selection=ProductSelection(id:part.id,name:componentName(part.id))}
    }
    private func componentMacro(_ title:String,_ value:Double)->some View {
        VStack(alignment:.leading,spacing:4){Text(title).luqmaFont(.caption).foregroundStyle(Theme.muted);Text(decimal(value)+" "+diary.t("جم","g")).luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline).monospacedDigit()}.frame(maxWidth:.infinity,alignment:.leading)
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
    private func analyze(){guard let imageData,!loadingPhoto else{return};descriptionFocused=false;busy=true;error=nil;cancellationMessage=nil;parts=[];products=[:]
        let token=UUID();analysisGeneration=token;let context=description,language=diary.language
        analysisTask=Task{do{
            let result=try await GeminiMealService.shared.analyze(imageData:imageData,context:context,language:language);try Task.checkCancellation();guard analysisGeneration==token else{return}
            var prepared:[UUID:(Food,Double,FoodUnit)]=[:]
            for part in result.parts{guard let e=part.mealEstimate else{throw AppError.invalid("تقدير الوجبة غير مكتمل. حاول مجددًا.","The meal estimate is incomplete. Retry.")};prepared[part.id]=(try e.food(name:part.food.name,nameEn:part.food.nameEn,identity:part.id,language:diary.language),1,.serving)}
            parts=result.parts;products=prepared;showingPhotoInput=false;detailedComponents=false
        }catch is CancellationError{if analysisGeneration==token{error=cancellationMessage}}catch{if analysisGeneration==token{self.error=Task.isCancelled ? cancellationMessage:((error as? AppError)?.message(diary.language) ?? diary.t("تعذّر التحليل. تحقق من الاتصال وحاول مجددًا.","Analysis failed. Check your connection and retry."))}};if analysisGeneration==token{busy=false;analysisTask=nil}}
    }
    #if DEBUG
    // Synthetic UI fixture uses the production review; never calls a service,
    // logs a meal, or enters the Release app.
    private func preparePreview(){
        do{
            let examples:[(String,String,Double,Nutrition)]=[
                ("بودينغ الشوكولاتة","Chocolate pudding",125,Nutrition(kcal:200,protein:5,carbs:30,fat:6.6)),
                ("قطع براوني بالشوكولاتة","Chocolate brownie pieces",65,Nutrition(kcal:260,protein:3,carbs:34,fat:13.8)),
                ("صوص كريمي","Creamy sauce",30,Nutrition(kcal:75,protein:0.5,carbs:7,fat:5)),
                ("فتات الشوكولاتة","Chocolate crumbs",10,Nutrition(kcal:50,protein:0.5,carbs:6,fat:2.7))
            ]
            for (index,example) in examples.enumerated(){
                let (name,nameEn,grams,nutrition)=example
                let estimate=try MealPhotoEstimate(grams:grams,low:grams*0.8,high:grams*1.25,nutrition:nutrition,kcalLow:nutrition.kcal*0.8,kcalHigh:nutrition.kcal*1.25,assumptions:"مثال للواجهة فقط؛ يتغير التقدير حسب الكمية والوصفة.",assumptionsEn:"UI example only; estimates vary with amount and recipe.")
                let photo=PhotoFood(id:"preview-\(index)",name:name,nameEn:nameEn,grams:grams,kcal:nutrition.kcal*100/grams,protein:nutrition.protein*100/grams,carbs:nutrition.carbs*100/grams,fat:nutrition.fat*100/grams)
                let part=PhotoPart(food:photo,grams:grams,low:estimate.low,high:estimate.high,basis:"photo-estimate",tentative:true,mealEstimate:estimate)
                parts.append(part);products[part.id]=(try estimate.food(name:name,nameEn:nameEn,identity:part.id,language:diary.language),1,.serving)
            }
            detailedComponents=ProcessInfo.processInfo.arguments.contains("-loqma-preview-photo-detailed")
        }catch{self.error=diary.t("تعذّر تجهيز المعاينة.","Preview could not be prepared.")}
    }
    #endif
}

private struct PhotoEstimateEditor:View {
    let title:String;let estimate:MealPhotoEstimate;let apply:(MealPhotoEstimate)->Bool
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var grams:Double
    init(title:String,estimate:MealPhotoEstimate,apply:@escaping(MealPhotoEstimate)->Bool){self.title=title;self.estimate=estimate;self.apply=apply;_grams=State(initialValue:estimate.grams)}
    private var updated:MealPhotoEstimate?{try? estimate.scaled(toGrams:grams)}
    var body:some View {NavigationStack{Form{
        Section{Label(title,systemImage:"fork.knife").luqmaFont(.headline).fixedSize(horizontal:false,vertical:true)}.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
        Section(diary.t("الكمية","Amount")){NumericInput(title:diary.t("الوزن","Weight"),value:$grams,suffix:diary.t("جم","g"));Notice(text:diary.t("أدخل وزنًا بين 1 و3000 جم.","Enter a weight from 1 to 3000 g."))}.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
        Section(diary.t("القيم بعد تعديل الوزن","Nutrition at the adjusted weight")){
            if let updated{
                NutritionView(value:updated.nutrition)
                Notice(text:diary.t("النطاق التقريبي: ","Estimated range: ")+decimal(updated.kcalLow,0)+"–"+decimal(updated.kcalHigh,0)+diary.t(" سعرة"," kcal"))
            }
            Notice(text:diary.t("تتغير السعرات مع الوزن. إذا كانت طريقة الطبخ أو كمية الزيت مختلفة، أضف وصفها وأعد التحليل.","Calories scale with weight. If preparation or oil differs, describe it and analyze again."))
        }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
    }.sandowForm().navigationTitle(diary.t("تعديل الكمية","Adjust amount")).navigationBarTitleDisplayMode(.inline).toolbar{
        ToolbarItem(placement:.cancellationAction){Button(diary.t("إلغاء","Cancel")){dismiss()}}
        ToolbarItem(placement:.confirmationAction){Button(diary.t("حفظ","Save")){if let updated,apply(updated){dismiss()}}.disabled(updated==nil)}
    }}}
}
