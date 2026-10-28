import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

@MainActor struct PhotoMealView:View {
    var initialMeal:Meal?=nil
    var onClose:(()->Void)?=nil
    var onCommit:PhotoFoodCommit
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
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
    @State private var cameraMessage:String?
    @State private var cameraAccessBlocked=false
    @State private var cancellationMessage:String?
    @State private var parts:[PhotoPart]=[]
    private struct ProductSelection:Identifiable {var id:UUID;var name:String}
    private struct EstimateSelection:Identifiable {var id:UUID;var estimate:MealPhotoEstimate}
    @State private var selection:ProductSelection?
    @State private var editing:EstimateSelection?
    @State private var products:[UUID:(Food,Double,FoodUnit)]=[:]
    @State private var meal:Meal = .lunch
    @State private var initialized=false
    @State private var analysisTask:Task<Void,Never>?
    @State private var photoLoadTask:Task<Void,Never>?
    @State private var previewTask:Task<Void,Never>?
    @State private var previewGeneration=UUID()
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
            if parts.isEmpty{analysisHeader;photoInput}
            else{
                review
                DisclosureGroup(isExpanded:$showingPhotoInput){photoInput.padding(.top,12)}label:{
                    Label(diary.t("الصورة وإعادة التحليل","Photo and reanalysis"),systemImage:"camera")
                        .luqmaFont(.subheadline).foregroundStyle(Theme.text)
                }.luqmaCard()
            }
        }
        .luqmaMotion(.content,value:parts.isEmpty)
        .luqmaMotion(.content,value:loadingPhoto)
        .luqmaMotion(.content,value:busy)
        .sheet(isPresented:$camera){CameraPhoto{data in camera=false;if let data{photoGeneration=UUID();photoLoadTask?.cancel();loadingPhoto=false;imageData=data;parts=[];error=nil}}.ignoresSafeArea()}
        .sheet(isPresented:$showingSetup,onDismiss:{ready=GeminiCredentialStore.isConfigured}){GeminiSettingsView()}
        .sheet(item:$editing){request in PhotoEstimateEditor(title:componentName(request.id),estimate:request.estimate){updated in
            guard let index=parts.firstIndex(where:{$0.id==request.id}) else{return false}
            do{let food=try updated.food(name:parts[index].food.name,nameEn:parts[index].food.nameEn,identity:request.id,language:diary.language)
                parts[index].mealEstimate=updated;parts[index].grams=updated.grams;parts[index].low=updated.low;parts[index].high=updated.high
                products[request.id]=(food,1,.serving);editing=nil;return true
            }catch{diary.report(error);return false}
        }}
        .fullScreenCover(item:$selection){request in AnyView(FoodAddView(initial:products[request.id].flatMap{FoodSearch.isCatalogFood($0.0) ? $0.0:nil},initialQuery:request.name,productSelection:true){food,amount,unit,_ in
            guard FoodSearch.isCatalogFood(food),(try? food.total(amount,unit:unit)) != nil else{return false}
            if !parts.contains(where:{$0.id==request.id}){
                guard let n=food.values(for:food.unit) else{return false}
                let label=PhotoFood(id:food.id,name:food.name,nameEn:food.nameEn ?? food.name,grams:1,kcal:n.kcal,protein:n.protein,carbs:n.carbs,fat:n.fat)
                parts.append(PhotoPart(id:request.id,food:label,grams:1,low:1,high:1,basis:"selected"))
            };products[request.id]=(food,amount,unit);selection=nil;return true
        })}
        .onChange(of:item){_,value in loadPhoto(value)}
        .onChange(of:imageData){_,data in analysisGeneration=UUID();analysisTask?.cancel();analysisTask=nil;busy=false;parts=[];products.removeAll();detailedComponents=false;showingPhotoInput=false;preparePhotoPreview(data)}
        .onChange(of:phase){_,value in
            if value != .active,busy{cancellationMessage=diary.t("توقف التحليل عند مغادرة الشاشة. افتح التطبيق وحاول مجددًا.","Analysis stopped when the app left the foreground. Reopen the app and retry.");analysisTask?.cancel()}
            if value == .active,cameraAccessBlocked,AVCaptureDevice.authorizationStatus(for:.video) == .authorized{cameraAccessBlocked=false;cameraMessage=nil}
        }
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.didReceiveMemoryWarningNotification)){_ in if busy{cancellationMessage=diary.t("توقف التحليل بسبب ضغط الذاكرة. حاول مجددًا.","Analysis stopped because of memory pressure. Retry.");analysisTask?.cancel()}}
        .onAppear{
            if !initialized{initialized=true;if let initialMeal{meal=initialMeal}}
            ready=GeminiCredentialStore.isConfigured
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-loqma-approved-photo-results"),parts.isEmpty{prepareApprovedPreview()}
            else if ProcessInfo.processInfo.arguments.contains("-loqma-preview-photo"),parts.isEmpty{preparePreview()}
            #endif
            if let data=imageData,preview==nil,previewTask==nil{preparePhotoPreview(data)}
        }
        .onDisappear{photoGeneration=UUID();analysisGeneration=UUID();previewGeneration=UUID();photoLoadTask?.cancel();analysisTask?.cancel();previewTask?.cancel();previewTask=nil}
    }
    private var analysisHeader:some View {
        HStack {
            Button{closeAnalysis()}label:{
                CFACrescentChevron().stroke(Color.white,style:StrokeStyle(lineWidth:2.2,lineCap:.round,lineJoin:.round))
                    .frame(width:10,height:18).scaleEffect(x:-1,y:1).frame(width:48,height:48)
                    .background(Color(hex:0x393C43),in:RoundedRectangle(cornerRadius:18,style:.continuous))
            }.buttonStyle(LuqmaPressStyle()).accessibilityLabel(diary.t("رجوع","Back"))
            Spacer(minLength:12)
            Text(diary.t("تحليل الطعام","Food Analysis")).luqmaFont(size:18,weight:.bold,relativeTo:.headline)
                .foregroundStyle(.white).accessibilityAddTraits(.isHeader)
            Spacer(minLength:12)
            Button{showingSetup=true}label:{
                Image(systemName:"gearshape").font(.system(size:18,weight:.semibold)).foregroundStyle(.white)
                    .frame(width:48,height:48).background(Color(hex:0x393C43),in:RoundedRectangle(cornerRadius:18,style:.continuous))
            }.buttonStyle(LuqmaPressStyle()).accessibilityLabel(diary.t("إعدادات خدمة التحليل","Analysis Settings"))
        }.environment(\.layoutDirection,.leftToRight)
    }
    private func closeAnalysis(){if let onClose{onClose()}else{dismiss()}}
    private var approvedScanPreview:Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-loqma-approved-photo-scan")
        #else
        return false
        #endif
    }
    private var approvedCapture:Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-loqma-approved-capture")
        #else
        return false
        #endif
    }
    private var photoInput:some View {
        VStack(alignment:.leading,spacing:18) {
            scanViewfinder
            HStack(alignment:.bottom,spacing:32) {
                PhotosPicker(selection:$item,matching:.images) {
                    cameraControl("slider.horizontal.3",size:68,radius:20)
                }.buttonStyle(LuqmaPressStyle()).disabled(busy).accessibilityLabel(diary.t("رفع صورة","Choose photo"))
                Button {
                    if imageData != nil {if ready{analyze()}else{showingSetup=true}}
                    else{openCamera()}
                }label:{
                    cameraControl("camera.fill",size:96,radius:28)
                        .overlay{RoundedRectangle(cornerRadius:31,style:.continuous).stroke(Color(hex:0x393C43),lineWidth:4).padding(-2)}
                }.buttonStyle(LuqmaPressStyle()).padding(.bottom,16).disabled(busy || loadingPhoto)
                    .accessibilityLabel(imageData == nil ? diary.t("الكاميرا","Camera"):diary.t("تحليل الوجبة","Meal analysis"))
                    .accessibilityIdentifier("photo.shutter")
                Button{showingSetup=true}label:{cameraControl("gearshape",size:68,radius:20)}
                    .buttonStyle(LuqmaPressStyle()).disabled(busy).accessibilityLabel(diary.t("إعدادات خدمة التحليل","Analysis Settings"))
            }.frame(maxWidth:.infinity).environment(\.layoutDirection,.leftToRight)
            if preview == nil && imageData == nil && !approvedCapture {
                Text(diary.t("صورة توضيحية — صوّر وجبتك أو اختر صورتها لبدء التحليل.","Illustration — take or choose your own meal photo to begin analysis."))
                    .luqmaFont(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true)
            }
            if let cameraMessage{
                SandowStateAlert(text:cameraMessage)
                if cameraAccessBlocked{
                    Button(diary.t("فتح الإعدادات","Open Settings")){if let url=URL(string:UIApplication.openSettingsURLString){openURL(url)}}
                        .buttonStyle(LuqmaSecondaryButtonStyle())
                }
            }
            VStack(alignment:.leading,spacing:8){
                Text(diary.t("وصف الوجبة (اختياري)","Meal description (optional)")).luqmaFont(size:15,weight:.bold,relativeTo:.subheadline)
                TextField(diary.t("مثلاً: الوزن، طريقة الطبخ وكمية الزيت","For example: weight, cooking method and oil amount"),text:$description,prompt:Text(diary.t("مثلاً: الوزن، طريقة الطبخ وكمية الزيت","For example: weight, cooking method and oil amount")).foregroundColor(Theme.muted),axis:.vertical).focused($descriptionFocused).lineLimit(2...4).padding(16).background(Theme.card,in:RoundedRectangle(cornerRadius:16)).accessibilityLabel(diary.t("وصف الوجبة الاختياري","Optional meal description")).disabled(busy)
                Notice(text:diary.t("تُرسل الصورة والوصف لخدمة التحليل. الوزن والزيت والصلصات تؤثر في التقدير؛ أضف ما تعرفه لتحسينه.","The photo and description are sent to the analysis service. Weight, oil and sauces affect the estimate; add what you know to improve it."))
            }
            if loadingPhoto{SandowOperationState(title:diary.t("تجهيز الصورة…","Preparing photo…"),cancelLabel:diary.t("إلغاء","Cancel"),onCancel:{cancelPhotoLoad()})}
            if busy{SandowOperationState(title:diary.t("تقدير المكونات والسعرات…","Estimating components and calories…"),cancelLabel:diary.t("إلغاء","Cancel"),onCancel:{analysisTask?.cancel()})}
            if let error{SandowStateAlert(text:error).luqmaMotionTransition()}
        }
    }
    private func cameraControl(_ symbol:String,size:CGFloat,radius:CGFloat)->some View {
        Image(systemName:symbol).font(.system(size:size>70 ? 26:20,weight:.bold)).foregroundStyle(Color(hex:0x111214))
            .luqmaLoadingPulse(active:busy && symbol == "camera.fill")
            .frame(width:size,height:size).background(.white,in:RoundedRectangle(cornerRadius:radius,style:.continuous))
    }
    private var scanViewfinder:some View {
        GeometryReader{geometry in
            let width=geometry.size.width
            let height=width*1540/1125
            let illustration=(preview == nil && imageData == nil) || approvedScanPreview
            ZStack(alignment:.top) {
                Group {
                    if illustration {Image("DNMMandarinScanHero").resizable().scaledToFit()}
                    else if let preview {Image(uiImage:preview).resizable().scaledToFill()}
                    else {Color(hex:0x111214)}
                }.frame(width:width,height:height).clipped()
                if illustration {
                    // This supplied raster already contains its brackets, beam
                    // and bubble. Localize its text in place; do not draw a
                    // second set of scanning chrome over the original artwork.
                    Text(busy || approvedScanPreview ? diary.t("جارٍ المسح...","Scanning..."):diary.t("جاهز للمسح","Ready to scan"))
                        .luqmaFont(size:12,weight:.bold,relativeTo:.caption).foregroundStyle(.white)
                        .frame(width:width*0.25,height:width*0.075)
                        .background(Color(hex:0xF97316),in:RoundedRectangle(cornerRadius:8))
                        .position(x:width*0.5,y:height*0.11)
                } else {
                    CFAScanBracketsShape().stroke(Color.white,style:StrokeStyle(lineWidth:6,lineCap:.round,lineJoin:.round))
                        .frame(width:width*0.78,height:height*0.69).padding(.top,height*0.16)
                    VStack(spacing:0) {
                        Spacer().frame(height:height*0.47)
                        RoundedRectangle(cornerRadius:2.5).fill(.white).frame(height:5)
                        LinearGradient(colors:[Color.white.opacity(0.45),Color.white.opacity(0)],startPoint:.top,endPoint:.bottom).frame(height:height*0.23)
                        Spacer(minLength:0)
                    }.frame(width:width*0.78,height:height)
                    VStack(spacing:-2) {
                        Text(busy ? diary.t("جارٍ المسح...","Scanning..."):diary.t("جاهز للمسح","Ready to scan"))
                            .luqmaFont(size:13,weight:.bold,relativeTo:.caption).foregroundStyle(.white)
                            .padding(.horizontal,16).frame(height:34)
                            .background(Color(hex:0xF97316),in:RoundedRectangle(cornerRadius:12,style:.continuous))
                        Image(systemName:"arrowtriangle.down.fill").font(.system(size:9)).foregroundStyle(Color(hex:0xF97316))
                    }.padding(.top,height*0.08)
                }
            }.frame(maxWidth:.infinity)
                .accessibilityElement(children:.ignore)
                .accessibilityLabel(diary.t(illustration ? "صورة توضيحية لإطار مسح الوجبة":preview == nil ? "تجهيز صورة الوجبة":"صورة وجبتك داخل إطار المسح",illustration ? "Illustrative meal scanning viewfinder":preview == nil ? "Preparing your meal photo":"Your meal photo in the viewfinder"))
                .accessibilityAddTraits(.isImage)
        }.aspectRatio(1125.0/1540.0,contentMode:.fit).padding(.horizontal,-16)
    }
    private var review:some View {
        let summary=total
        return VStack(alignment:.leading,spacing:16){
            VStack(spacing:0){
                resultHero.padding(.bottom,-24)
                resultPanel(summary)
            }.padding(.horizontal,-16)
            if let summary{calorieContribution(summary.kcal)}
            Label(diary.t("تقديرات تقريبية تتأثر بالكمية وطريقة التحضير","Estimates vary with amount and preparation"),systemImage:"sparkles")
                .luqmaFont(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true)
            mealChoice
            VStack(alignment:.leading,spacing:10){
                LuqmaSectionHeader(title:diary.t("المكونات","Components"),detail:typeSize.isAccessibilitySize ? nil:diary.t("الوزن والسعرات لكل مكوّن","Weight and calories per component"))
                HStack(spacing:8){componentMode(diary.t("مختصر","Compact"),detailed:false);componentMode(diary.t("تفصيلي","Detailed"),detailed:true)}
            }.id("photo-components")
            ForEach(parts){part in component(part).luqmaMotionTransition()}
            Button{selection=ProductSelection(id:UUID(),name:"")}label:{Label(diary.t("إضافة مكوّن","Add component"),systemImage:"plus.circle")}.buttonStyle(LuqmaSecondaryButtonStyle())
        }.luqmaMotion(.content,value:detailedComponents)
            .luqmaMotion(.content,value:parts.count)
    }
    private var resultHero:some View {
        GeometryReader{geometry in
            ZStack(alignment:.topLeading) {
                Group {
                    if let preview{Image(uiImage:preview).resizable().scaledToFill()}
                    else{
                        ZStack {
                            Theme.card
                            VStack(spacing:8){
                                Image(systemName:"fork.knife").font(.system(size:24,weight:.light))
                                Text(diary.t("لا توجد صورة مرفقة","No attached photo")).luqmaFont(.caption)
                            }.foregroundStyle(Theme.muted)
                        }
                    }
                }.frame(width:geometry.size.width,height:geometry.size.height).clipped()
                Button{closeAnalysis()}label:{
                    CFACrescentChevron().stroke(Color.white,style:StrokeStyle(lineWidth:2.2,lineCap:.round,lineJoin:.round))
                        .frame(width:10,height:18).scaleEffect(x:-1,y:1).frame(width:48,height:48)
                        .background(Color(hex:0x393C43).opacity(approvedResultPreview ? 1:0.6),in:RoundedRectangle(cornerRadius:18,style:.continuous))
                }.buttonStyle(LuqmaPressStyle()).padding(16).accessibilityLabel(diary.t("رجوع","Back"))
            }
        }.environment(\.layoutDirection,.leftToRight).aspectRatio(resultHeroAspect,contentMode:.fit)
            .accessibilityElement(children:.contain)
            .accessibilityLabel(diary.t(preview == nil ? "لا توجد صورة في هذه المعاينة":"صورة الوجبة",preview == nil ? "No photo in this preview":"Meal photo"))
    }
    private var approvedResultPreview:Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-loqma-approved-photo-results") && imageData == nil
        #else
        return false
        #endif
    }
    private var resultHeroAspect:CGFloat {
        // Only the explicitly synthetic capture uses its supplied artwork's
        // visible aspect; real meal photos retain their existing presentation.
        if approvedResultPreview,let preview,preview.size.height>0{return preview.size.width/preview.size.height}
        return preview == nil ? 2.6:1/0.85
    }
    private var resultTitle:some View {
        VStack(alignment:.center,spacing:14) {
            HStack(spacing:8) {
                resultChip(decimal(Double(parts.count),0)+" "+diary.t("مكوّنات","components"))
                if let grams=knownMealWeight{resultChip(decimal(grams,0)+" "+diary.t("جم","g"))}
            }
            Text(parts.count == 1 ? componentName(parts[0].id):diary.t("وجبتك من الصورة","Your meal from the photo"))
                .luqmaFont(size:26,weight:.heavy,relativeTo:.title).foregroundStyle(.white)
                .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
        }.frame(maxWidth:.infinity)
    }
    private func resultChip(_ title:String)->some View {
        Text(title).luqmaFont(size:12,weight:.bold,relativeTo:.caption).foregroundStyle(.white)
            .padding(.horizontal,14).frame(minHeight:30)
            .overlay{RoundedRectangle(cornerRadius:10,style:.continuous).stroke(Color(hex:0x676C75),lineWidth:1)}
    }
    private var knownMealWeight:Double? {
        var grams=0.0
        for part in parts{
            guard let product=products[part.id],product.1.isFinite,product.1>0 else{return nil}
            if MealPhotoEstimate.isValidPhotoEstimate(product.0){grams+=part.grams*product.1}
            else if product.2 == .g{grams+=product.1}
            else if product.2 == .serving,product.0.servingUnit == "g",let quantity=product.0.servingQuantity,quantity.isFinite,quantity>0{grams+=quantity*product.1}
            else{return nil}
        }
        return grams.isFinite && grams>0 ? grams:nil
    }
    private func resultPanel(_ nutrition:Nutrition?)->some View {
        VStack(alignment:.center,spacing:18) {
            Capsule().fill(Color(hex:0x393C43)).frame(width:48,height:4).accessibilityHidden(true)
            resultTitle
            if let nutrition {
                calorieValue(nutrition.kcal)
                if typeSize.isAccessibilitySize{
                    VStack(spacing:16){ForEach(MacroKey.allCases){key in macroGoal(key,nutrition:nutrition)}}
                }else{
                    HStack(alignment:.bottom,spacing:10){ForEach([MacroKey.protein,MacroKey.carbs,MacroKey.fat]){key in macroColumn(key,nutrition:nutrition)}}
                        .environment(\.layoutDirection,.leftToRight)
                }
            }else{
                Notice(text:diary.t("أكمل بيانات جميع المكونات لعرض إجمالي الوجبة وحفظها.","Complete every component to see and log the meal total."))
            }
            Button{logMeal()}label:{
                HStack(spacing:10){Text(diary.t("إضافة الوجبة","Log meal"));Image(systemName:"plus").font(.system(size:16,weight:.bold))}
                    .luqmaFont(size:16,weight:.bold,relativeTo:.headline).foregroundStyle(.white)
                    .frame(maxWidth:.infinity,minHeight:56)
                    .background(Color(hex:0xF97316),in:RoundedRectangle(cornerRadius:18,style:.continuous))
            }.buttonStyle(LuqmaPressStyle()).disabled(nutrition==nil || busy || loadingPhoto).accessibilityIdentifier("photo.logMeal")
        }.padding(.horizontal,16).padding(.top,12).padding(.bottom,16)
            .frame(maxWidth:.infinity,minHeight:typeSize.isAccessibilitySize ? nil:498,alignment:.top)
            .background(Color(hex:0x111214),in:UnevenRoundedRectangle(topLeadingRadius:34,topTrailingRadius:34,style:.continuous))
    }
    private func logMeal(){
        guard total != nil else{return};let values=parts.compactMap{products[$0.id]};guard values.count==parts.count else{return}
        if onCommit(values,meal){parts=[];products=[:]}
    }
    private func calorieValue(_ kcal:Double)->some View {
        HStack(alignment:.firstTextBaseline,spacing:5){
            Text(diary.t("تقدير الصورة","Photo estimate"))
            Text("·").accessibilityHidden(true)
            Text(decimal(kcal,0)+" "+diary.t("سعرة","kcal")).monospacedDigit().luqmaNumericMotion(value:kcal)
        }.luqmaFont(size:15,weight:.medium,relativeTo:.subheadline).foregroundStyle(Color(hex:0xD7D8D9)).accessibilityElement(children:.combine)
    }
    private func calorieContribution(_ kcal:Double)->some View {
        VStack(alignment:.leading,spacing:8){
            if let progress=goalProgress(kcal,goal:diary.state.goals.kcal){
                Text(decimal(progress*100)+"% "+diary.t("من هدفك اليومي","of your daily goal"))
                    .luqmaFont(.caption).foregroundStyle(Theme.muted)
            }
            if let range=calorieRange{
                Text(diary.t("النطاق: ","Range: ")+decimal(range.0,0)+"–"+decimal(range.1,0)+diary.t(" سعرة"," kcal"))
                    .luqmaFont(.caption2).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true)
            }
        }.accessibilityElement(children:.combine)
    }
    private func macroColor(_ key:MacroKey)->Color {
        switch key {
        case .protein:return Color(hex:0x676C75)
        case .carbs:return Color(hex:0xF97316)
        case .fat:return Color(hex:0x2563EB)
        }
    }
    private func macroColumn(_ key:MacroKey,nutrition:Nutrition)->some View {
        let amount=nutrition[key]
        let largest=max(nutrition.protein,max(nutrition.carbs,nutrition.fat))
        let fraction=largest>0 && amount>0 ? min(0.72,amount/largest*0.72):0
        return GeometryReader{geometry in
            ZStack(alignment:.bottom) {
                RoundedRectangle(cornerRadius:24,style:.continuous).fill(Color(hex:0x393C43))
                RoundedRectangle(cornerRadius:24,style:.continuous).fill(macroColor(key))
                    .frame(height:geometry.size.height*CGFloat(fraction)).luqmaMotion(.progress,value:fraction)
                VStack {
                    Image(macroIcon(key)).renderingMode(.original).resizable().scaledToFit().frame(width:20,height:20)
                        .foregroundStyle(Color(hex:0xD7D8D9)).padding(.top,16)
                    Spacer(minLength:0)
                }.accessibilityHidden(true)
                VStack(spacing:2) {
                    Text(key.label(diary.language)).luqmaFont(size:13,weight:.medium,relativeTo:.caption)
                    Text(decimal(amount,1)+diary.t("جم","g")).luqmaFont(size:22,weight:.heavy,relativeTo:.title3).monospacedDigit().luqmaNumericMotion(value:amount)
                }.foregroundStyle(.white).padding(.horizontal,4).padding(.bottom,14)
            }
        }.frame(maxWidth:.infinity).frame(height:177)
            .accessibilityElement(children:.ignore).accessibilityLabel(key.label(diary.language))
            .accessibilityValue(decimal(amount)+" "+diary.t("جم","g"))
            .accessibilityHint(diary.t("ارتفاع العمود يوضح كمية المغذي مقارنة ببقية مكونات التغذية في الوجبة.","Bar height compares the macro's grams with the other macros in this meal."))
    }
    private func macroIcon(_ key:MacroKey)->String {
        switch key {
        case .protein:return "DNMVerticalProteinIcon"
        case .carbs:return "DNMVerticalCarbsIcon"
        case .fat:return "DNMVerticalFatIcon"
        }
    }
    private func macroGoal(_ key:MacroKey,nutrition:Nutrition)->some View {
        let goal=diary.state.goals[key]
        let color=macroColor(key)
        return VStack(alignment:.leading,spacing:6){
            HStack(spacing:5){Circle().fill(color).frame(width:6,height:6).accessibilityHidden(true);Text(key.label(diary.language)).luqmaFont(.caption).foregroundStyle(Theme.muted)}
            HStack(alignment:.firstTextBaseline,spacing:3){
                Text(decimal(nutrition[key])).luqmaFont(size:20,weight:.bold,relativeTo:.title3).monospacedDigit().luqmaNumericMotion(value:nutrition[key])
                Text(diary.t("جم","g")).luqmaFont(.caption).foregroundStyle(Theme.muted)
            }
            if let progress=goalProgress(nutrition[key],goal:goal){
                ProgressView(value:min(1,progress)).tint(color).luqmaMotion(.progress,value:progress)
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
                .foregroundStyle(detailedComponents == detailed ? Theme.onAccent:Theme.muted)
                .frame(maxWidth:.infinity,minHeight:44)
                .background(detailedComponents == detailed ? Theme.accent:Theme.card,in:RoundedRectangle(cornerRadius:14))
        }.buttonStyle(LuqmaPressStyle()).accessibilityAddTraits(detailedComponents == detailed ? .isSelected:[])
            .luqmaMotion(.selection,value:detailedComponents == detailed)
    }
    private var mealChoice:some View {
        HStack(spacing:12){
            Text(diary.t("أضفها إلى","Log under")).luqmaFont(.caption).foregroundStyle(Theme.muted)
            Spacer(minLength:0)
            Picker(diary.t("الوجبة","Meal"),selection:$meal){
                ForEach(Meal.allCases){value in Text(value.label(diary.language)).tag(value)}
            }
            .pickerStyle(.menu).labelsHidden().tint(Theme.text)
        }.frame(minHeight:44)
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
                }.buttonStyle(LuqmaPressStyle()).foregroundStyle(Theme.link)
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
        }.buttonStyle(LuqmaPressStyle()).accessibilityLabel(componentName(part.id)+", "+componentAmount(part))
            .accessibilityHint(diary.t("اضغط لتعديل الكمية","Tap to adjust the amount"))
    }
    private func componentCalories(_ nutrition:Nutrition?)->some View {
        VStack(alignment:.trailing,spacing:2){
            if let nutrition{
                Text(decimal(nutrition.kcal,0)).luqmaFont(size:23,weight:.bold,relativeTo:.title2).monospacedDigit().foregroundStyle(Theme.accent).luqmaNumericMotion(value:nutrition.kcal)
                Text(diary.t("سعرة","kcal")).luqmaFont(.caption2).foregroundStyle(Theme.muted)
            }else{Text(diary.t("غير مكتمل","Incomplete")).luqmaFont(.caption).foregroundStyle(Theme.muted)}
        }.fixedSize(horizontal:true,vertical:false).accessibilityElement(children:.combine)
    }
    private func removeComponent(_ part:PhotoPart)->some View {
        Button(role:.destructive){parts.removeAll{$0.id==part.id};products.removeValue(forKey:part.id)}label:{
            Image(systemName:"trash").font(.system(size:17,weight:.regular)).foregroundStyle(Theme.muted).frame(minWidth:44,minHeight:44)
        }.buttonStyle(LuqmaPressStyle()).accessibilityLabel(diary.t("حذف ","Remove ")+componentName(part.id))
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
        VStack(alignment:.leading,spacing:4){Text(title).luqmaFont(.caption).foregroundStyle(Theme.muted);Text(decimal(value)+" "+diary.t("جم","g")).luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline).monospacedDigit().luqmaNumericMotion(value:value)}.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func openCamera(){
        cameraMessage=nil;cameraAccessBlocked=false
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else{
            cameraMessage=diary.t("لا توجد كاميرا متاحة على هذا الجهاز. اختر صورة من المكتبة.","No camera is available on this device. Choose a photo from your library.");return
        }
        Task{
            if await CameraAccess.request(){camera=true;return}
            switch AVCaptureDevice.authorizationStatus(for:.video){
            case .denied:
                cameraAccessBlocked=true
                cameraMessage=diary.t("الوصول إلى الكاميرا مرفوض. اسمح للقمة باستخدامها من الإعدادات.","Camera access is denied. Allow Luqma to use it in Settings.")
            case .restricted:
                cameraAccessBlocked=true
                cameraMessage=diary.t("الوصول إلى الكاميرا مقيّد على هذا الجهاز. راجع الإعدادات أو اختر صورة من المكتبة.","Camera access is restricted on this device. Check Settings or choose a photo from your library.")
            default:
                cameraMessage=diary.t("تعذّر فتح الكاميرا. اختر صورة من المكتبة أو حاول مجددًا.","The camera could not be opened. Choose a photo from your library or retry.")
            }
        }
    }
    private func cancelPhotoLoad(){
        photoGeneration=UUID();photoLoadTask?.cancel();photoLoadTask=nil;loadingPhoto=false;item=nil
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
    private func preparePhotoPreview(_ data:Data?) {
        previewTask?.cancel();previewTask=nil;previewGeneration=UUID();preview=nil
        guard let data else{return}
        let token=previewGeneration
        previewTask=Task{
            do {
                let image=try await PhotoPreparationWorker.shared.preview(data)
                guard !Task.isCancelled,previewGeneration==token else{return}
                preview=image;previewTask=nil
            }catch is CancellationError{return}
            catch {
                guard !Task.isCancelled,previewGeneration==token else{return}
                previewTask=nil;imageData=nil
                self.error=(error as? AppError)?.message(diary.language) ?? diary.t("تعذّر فتح الصورة. اختر صورة أخرى.","The photo could not be opened. Choose another photo.")
            }
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
    private func prepareApprovedPreview(){
        do {
            let nutrition=Nutrition(kcal:187,protein:3,carbs:42,fat:0.7)
            let estimate=try MealPhotoEstimate(grams:250,low:200,high:300,nutrition:nutrition,kcalLow:150,kcalHigh:225,assumptions:"مثال للواجهة فقط.",assumptionsEn:"UI example only.")
            let food=PhotoFood(id:"approved-mandarin",name:"برتقال يوسفي",nameEn:"Mandarin orange",grams:250,kcal:74.8,protein:1.2,carbs:16.8,fat:0.28)
            let part=PhotoPart(food:food,grams:250,low:200,high:300,basis:"photo-estimate",tentative:true,mealEstimate:estimate)
            if let artwork=UIImage(named:"DNMMandarinPileHero"),let source=artwork.cgImage,
               let cropped=source.cropping(to:CGRect(x:0,y:132,width:CGFloat(source.width),height:CGFloat(min(808,source.height-132)))) {
                // Preserve the original full-width food composition between
                // the baked status bar and panel handle. The opaque live back
                // control covers the baked button in the same design slot.
                preview=UIImage(cgImage:cropped)
            }
            parts=[part]
            products=[part.id:(try estimate.food(name:food.name,nameEn:food.nameEn,identity:part.id,language:diary.language),1,.serving)]
        }catch{self.error=diary.t("تعذّر تجهيز المعاينة.","Preview could not be prepared.")}
    }
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
    }.sandowForm().sandowNavigation(diary.t("تعديل الكمية","Adjust amount"),backLabel:diary.t("إلغاء","Cancel"),onBack:{dismiss()},
        actionLabel:diary.t("حفظ","Save"),actionEnabled:updated != nil,onAction:{if let updated,apply(updated){dismiss()}})}}
}
