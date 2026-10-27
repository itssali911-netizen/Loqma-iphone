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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var liveCamera = MealCamera()
    @State private var item:PhotosPickerItem?
    @State private var imageData:Data?
    @State private var preview:UIImage?
    @State private var showingGallery=false
    @State private var visible=false
    @State private var automaticallyAnalyze=false
    @State private var shutterVisible=false
    @State private var scanStarted=Date()
    @State private var scanFinishing:Date?
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
        .photosPicker(isPresented:$showingGallery,selection:$item,matching:.images)
        .sheet(isPresented:$showingSetup,onDismiss:{
            ready=GeminiCredentialStore.isConfigured
            if ready,automaticallyAnalyze,preview != nil{automaticallyAnalyze=false;analyze()}
            refreshCamera()
        }){GeminiSettingsView()}
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
        .onChange(of:imageData){_,data in analysisGeneration=UUID();analysisTask?.cancel();analysisTask=nil;busy=false;scanFinishing=nil;parts=[];products.removeAll();detailedComponents=false;showingPhotoInput=false;refreshCamera();preparePhotoPreview(data)}
        .onChange(of:showingGallery){_,_ in refreshCamera()}
        .onChange(of:showingSetup){_,_ in refreshCamera()}
        .onChange(of:showingPhotoInput){_,_ in refreshCamera()}
        .onChange(of:parts.isEmpty){_,_ in refreshCamera()}
        .onChange(of:phase){_,value in
            if value != .active,busy{cancellationMessage=diary.t("توقف التحليل عند مغادرة الشاشة. افتح التطبيق وحاول مجددًا.","Analysis stopped when the app left the foreground. Reopen the app and retry.");analysisTask?.cancel()}
            refreshCamera()
            if value == .active,automaticallyAnalyze,ready,preview != nil,!busy{automaticallyAnalyze=false;analyze()}
        }
        .onReceive(NotificationCenter.default.publisher(for:UIApplication.didReceiveMemoryWarningNotification)){_ in if busy{cancellationMessage=diary.t("توقف التحليل بسبب ضغط الذاكرة. حاول مجددًا.","Analysis stopped because of memory pressure. Retry.");analysisTask?.cancel()}}
        .onAppear{
            visible=true
            if !initialized{initialized=true;if let initialMeal{meal=initialMeal}}
            ready=GeminiCredentialStore.isConfigured
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-loqma-camera-ui-scan"){
                // Native UI rendering fixture only: no camera, service request,
                // fabricated analysis response or save action. Release excludes it.
                preview=UIImage(named:"LuqmaEditorialLunch");busy=true;scanStarted=Date()
            }
            else if ProcessInfo.processInfo.arguments.contains("-loqma-approved-photo-results"),parts.isEmpty{prepareApprovedPreview()}
            else if ProcessInfo.processInfo.arguments.contains("-loqma-preview-photo"),parts.isEmpty{preparePreview()}
            #endif
            if let data=imageData,preview==nil,previewTask==nil{preparePhotoPreview(data)}
            refreshCamera()
        }
        .onDisappear{visible=false;liveCamera.setActive(false);photoGeneration=UUID();analysisGeneration=UUID();previewGeneration=UUID();photoLoadTask?.cancel();analysisTask?.cancel();previewTask?.cancel();photoLoadTask=nil;analysisTask=nil;previewTask=nil;loadingPhoto=false;busy=false;scanFinishing=nil;shutterVisible=false}
    }
    private var analysisHeader:some View {
        HStack {
            Button{closeAnalysis()}label:{
                CFACrescentChevron().stroke(Color.white,style:StrokeStyle(lineWidth:2.2,lineCap:.round,lineJoin:.round))
                    .frame(width:10,height:18).scaleEffect(x:-1,y:1).frame(width:48,height:48)
                    .background(Color(hex:0x393C43),in:RoundedRectangle(cornerRadius:18,style:.continuous))
            }.buttonStyle(.plain).accessibilityLabel(diary.t("رجوع","Back"))
            Spacer(minLength:12)
            Text(diary.t("تحليل الطعام","Food Analysis")).luqmaFont(size:18,weight:.bold,relativeTo:.headline)
                .foregroundStyle(.white).accessibilityAddTraits(.isHeader)
            Spacer(minLength:12)
            Button{showingSetup=true}label:{
                Image(systemName:"gearshape").font(.system(size:18,weight:.semibold)).foregroundStyle(.white)
                    .frame(width:48,height:48).background(Color(hex:0x393C43),in:RoundedRectangle(cornerRadius:18,style:.continuous))
            }.buttonStyle(.plain).accessibilityLabel(diary.t("إعدادات خدمة التحليل","Analysis Settings"))
        }.environment(\.layoutDirection,.leftToRight)
    }
    private func closeAnalysis(){if let onClose{onClose()}else{dismiss()}}
    private var photoInput:some View {
        VStack(alignment:.leading,spacing:18) {
            scanViewfinder
            HStack(alignment:.bottom,spacing:32) {
                Button{showingGallery=true}label:{
                    cameraControl("photo.on.rectangle.angled",size:68,radius:20)
                }.buttonStyle(.plain).disabled(busy || loadingPhoto || liveCamera.capturing).accessibilityLabel(diary.t("اختيار صورة من المكتبة","Choose photo from library")).accessibilityIdentifier("photo.gallery")
                Button {
                    if imageData != nil {if ready{analyze()}else{showingSetup=true}}
                    else{capturePhoto()}
                }label:{
                    cameraControl("camera.fill",size:96,radius:28)
                        .overlay{RoundedRectangle(cornerRadius:31,style:.continuous).stroke(Color(hex:0x393C43),lineWidth:4).padding(-2)}
                }.buttonStyle(.plain).padding(.bottom,16).disabled(busy || loadingPhoto || liveCamera.capturing || (imageData == nil && liveCamera.state != .ready) || (imageData != nil && preview == nil))
                    .accessibilityLabel(imageData == nil ? diary.t("الكاميرا","Camera"):diary.t("تحليل الوجبة","Meal analysis"))
                    .accessibilityIdentifier("photo.shutter")
                Button{showingSetup=true}label:{cameraControl("gearshape",size:68,radius:20)}
                    .buttonStyle(.plain).disabled(busy).accessibilityLabel(diary.t("إعدادات خدمة التحليل","Analysis Settings"))
            }.frame(maxWidth:.infinity).environment(\.layoutDirection,.leftToRight)
            if preview == nil && imageData == nil {
                Text(diary.t("صوّر وجبتك أو اختر صورتها لبدء التحليل.","Take or choose your meal photo to begin analysis."))
                    .luqmaFont(.caption).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true)
            }
            if imageData != nil,!busy,!loadingPhoto{
                Button(diary.t("التقاط صورة جديدة","Take another photo")){automaticallyAnalyze=false;item=nil;error=nil;cancellationMessage=nil;imageData=nil}
                    .buttonStyle(LuqmaSecondaryButtonStyle()).accessibilityIdentifier("photo.retake")
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
            if busy{SandowOperationState(title:analysisStatus,cancelLabel:diary.t("إلغاء","Cancel"),onCancel:{cancellationMessage=diary.t("تم إلغاء التحليل. يمكنك المحاولة مجددًا.","Analysis cancelled. You can retry.");analysisTask?.cancel()})}
            if let error{
                SandowStateAlert(text:error)
                if imageData != nil,!busy,!loadingPhoto{
                    Button(diary.t("إعادة التحليل","Retry analysis")){if ready{analyze()}else{automaticallyAnalyze=true;showingSetup=true}}
                        .buttonStyle(LuqmaSecondaryButtonStyle()).accessibilityIdentifier("photo.retry")
                }
            }
        }
    }
    private func cameraControl(_ symbol:String,size:CGFloat,radius:CGFloat)->some View {
        Image(systemName:symbol).font(.system(size:size>70 ? 26:20,weight:.bold)).foregroundStyle(Color(hex:0x111214))
            .frame(width:size,height:size).background(.white,in:RoundedRectangle(cornerRadius:radius,style:.continuous))
    }
    private var scanViewfinder:some View {
        GeometryReader{geometry in
            let width=geometry.size.width
            let height=width*1540/1125
            ZStack(alignment:.top) {
                Group {
                    if let preview {Image(uiImage:preview).resizable().scaledToFill()}
                    else if imageData == nil {MealCameraPreview(driver:liveCamera.driver)}
                    else {Theme.background}
                }.frame(width:width,height:height).clipped()
                CFAScanBracketsShape().stroke(Color.white,style:StrokeStyle(lineWidth:6,lineCap:.round,lineJoin:.round))
                    .frame(width:width*0.78,height:height*0.69).padding(.top,height*0.16).accessibilityHidden(true)
                if busy,preview != nil{
                    FoodScanOverlay(startedAt:scanStarted,finishingAt:scanFinishing)
                        .frame(width:width*0.78,height:height*0.69).padding(.top,height*0.16)
                }
                VStack(spacing:-2) {
                    Text(busy ? analysisStatus:preview != nil ? diary.t("صورة الوجبة","Meal photo"):liveCamera.state == .ready ? diary.t("جاهز للمسح","Ready to scan"):diary.t("الكاميرا","Camera"))
                        .luqmaFont(size:13,weight:.bold,relativeTo:.caption).foregroundStyle(.white)
                        .padding(.horizontal,16).frame(minHeight:34)
                        .background(Theme.accent,in:RoundedRectangle(cornerRadius:12,style:.continuous))
                    Image(systemName:"arrowtriangle.down.fill").font(.system(size:9)).foregroundStyle(Theme.accent)
                }.padding(.top,height*0.08)
                if preview == nil,imageData == nil,liveCamera.state != .ready{
                    VStack(spacing:12){
                        if liveCamera.state == .starting{ProgressView().tint(.white)}
                        Text(cameraMessage ?? diary.t("تجهيز الكاميرا…","Preparing camera…"))
                            .luqmaFont(.subheadline).foregroundStyle(.white).multilineTextAlignment(.center)
                        Button(diary.t("اختيار صورة من المكتبة","Choose photo from library")){showingGallery=true}
                            .buttonStyle(LuqmaSecondaryButtonStyle())
                        if liveCamera.state == .failed{
                            Button(diary.t("إعادة تشغيل الكاميرا","Restart camera")){liveCamera.setActive(false);refreshCamera()}
                                .buttonStyle(LuqmaSecondaryButtonStyle())
                        }
                    }.padding(24).frame(width:width*0.75).background(Theme.card,in:RoundedRectangle(cornerRadius:20))
                        .position(x:width/2,y:height/2)
                }
                if shutterVisible{
                    Color.black.opacity(0.55).allowsHitTesting(false).accessibilityHidden(true)
                        .transition(.opacity)
                        .task{
                            // Wait for an actual rendered shutter frame before
                            // fading it; same-turn opacity writes can coalesce.
                            do{try await Task.sleep(for:.milliseconds(50))}catch{return}
                            withAnimation(.easeOut(duration:0.16)){shutterVisible=false}
                        }
                }
            }.frame(maxWidth:.infinity)
                .accessibilityElement(children:.contain)
                .accessibilityLabel(diary.t(preview == nil ? "معاينة الكاميرا المباشرة":"صورة وجبتك داخل إطار المسح",preview == nil ? "Live camera preview":"Your meal photo in the viewfinder"))
                .accessibilityIdentifier("photo.viewfinder")
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
            ForEach(parts){part in component(part)}
            Button{selection=ProductSelection(id:UUID(),name:"")}label:{Label(diary.t("إضافة مكوّن","Add component"),systemImage:"plus.circle")}.buttonStyle(LuqmaSecondaryButtonStyle())
        }
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
                }.buttonStyle(.plain).padding(16).accessibilityLabel(diary.t("رجوع","Back"))
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
            }.buttonStyle(.plain).disabled(nutrition==nil || busy || loadingPhoto).accessibilityIdentifier("photo.logMeal")
        }.padding(.horizontal,16).padding(.top,12).padding(.bottom,16)
            .frame(maxWidth:.infinity,minHeight:typeSize.isAccessibilitySize ? nil:498,alignment:.top)
            .background(Color(hex:0x111214),in:UnevenRoundedRectangle(topLeadingRadius:34,topTrailingRadius:34,style:.continuous))
    }
    private func logMeal(){
        guard total != nil else{return};let values=parts.compactMap{products[$0.id]};guard values.count==parts.count else{return}
        if onCommit(values,meal){parts=[];products=[:]}
    }
    private func calorieValue(_ kcal:Double)->some View {
        VStack(spacing:4){
            if typeSize.isAccessibilitySize{
                calorieNumber(kcal)
                Text(diary.t("سعرة حرارية","kcal")).luqmaFont(size:20,weight:.medium,relativeTo:.title3)
                    .foregroundStyle(.white).multilineTextAlignment(.center)
            }else{
                HStack(alignment:.firstTextBaseline,spacing:8){
                    calorieNumber(kcal)
                    Text(diary.t("سعرة حرارية","kcal")).luqmaFont(size:20,weight:.medium,relativeTo:.title3)
                }.foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                    .environment(\.layoutDirection,diary.language == .ar ? .rightToLeft:.leftToRight)
            }
            Text(diary.t("تقدير الصورة","Photo estimate")).luqmaFont(.caption).foregroundStyle(Theme.muted)
        }.accessibilityElement(children:.ignore)
            .accessibilityLabel(diary.t("تقدير الصورة","Photo estimate")+", "+decimal(kcal,0)+" "+diary.t("سعرة حرارية","kcal"))
            .accessibilityIdentifier("photo.calories")
    }
    private func calorieNumber(_ kcal:Double)->some View {
        HStack(alignment:.firstTextBaseline,spacing:8){
            FoodAnalysisIcon(kind:.calories).frame(width:28,height:32)
                .alignmentGuide(.firstTextBaseline){$0[.bottom]-3}.accessibilityHidden(true)
            Text(decimal(kcal,0)).luqmaFont(size:40,weight:.bold,relativeTo:.largeTitle)
                .monospacedDigit().environment(\.layoutDirection,.leftToRight)
        }.foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
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
                    .frame(height:geometry.size.height*CGFloat(fraction))
                VStack(spacing:8) {
                    FoodAnalysisIcon(kind:macroIcon(key)).frame(width:26,height:26).padding(4)
                        .background(Theme.background,in:RoundedRectangle(cornerRadius:8)).accessibilityHidden(true)
                    Text(key.label(diary.language)).luqmaFont(size:13,weight:.medium,relativeTo:.caption)
                    Spacer(minLength:8)
                    HStack(alignment:.firstTextBaseline,spacing:3){
                        Text(decimal(amount,1)).luqmaFont(size:22,weight:.heavy,relativeTo:.title3).monospacedDigit()
                        Text(diary.t("جم","g")).luqmaFont(.caption)
                    }.environment(\.layoutDirection,.leftToRight).lineLimit(1).minimumScaleFactor(0.75)
                }.foregroundStyle(.white).padding(.horizontal,4).padding(.top,16).padding(.bottom,14)
            }
        }.frame(maxWidth:.infinity).frame(height:177)
            .accessibilityElement(children:.ignore).accessibilityLabel(key.label(diary.language))
            .accessibilityValue(decimal(amount)+" "+diary.t("جم","g"))
            .accessibilityHint(diary.t("ارتفاع العمود يوضح كمية المغذي مقارنة ببقية مكونات التغذية في الوجبة.","Bar height compares the macro's grams with the other macros in this meal."))
    }
    private func macroIcon(_ key:MacroKey)->FoodAnalysisIcon.Kind {
        switch key {
        case .protein:return .protein
        case .carbs:return .carbs
        case .fat:return .fat
        }
    }
    private func macroGoal(_ key:MacroKey,nutrition:Nutrition)->some View {
        let goal=diary.state.goals[key]
        let color=macroColor(key)
        return VStack(alignment:.leading,spacing:6){
            HStack(spacing:8){FoodAnalysisIcon(kind:macroIcon(key)).frame(width:26,height:26).accessibilityHidden(true);Text(key.label(diary.language)).luqmaFont(.caption).foregroundStyle(Theme.muted)}
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
                .foregroundStyle(detailedComponents == detailed ? Theme.onAccent:Theme.muted)
                .frame(maxWidth:.infinity,minHeight:44)
                .background(detailedComponents == detailed ? Theme.accent:Theme.card,in:RoundedRectangle(cornerRadius:14))
        }.buttonStyle(.plain).accessibilityAddTraits(detailedComponents == detailed ? .isSelected:[])
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
                }.buttonStyle(.plain).foregroundStyle(Theme.link)
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
    private var cameraAccessBlocked:Bool { liveCamera.state == .denied || liveCamera.state == .restricted }
    private var cameraMessage:String? {
        guard imageData == nil else{return nil}
        switch liveCamera.state {
        case .denied:return diary.t("الوصول إلى الكاميرا مرفوض. اسمح للقمة باستخدامها من الإعدادات أو اختر صورة.","Allow camera access in Settings or choose a photo.")
        case .restricted:return diary.t("الوصول إلى الكاميرا مقيّد. يمكنك اختيار صورة من المكتبة.","Camera access is restricted. Choose a photo from your library.")
        case .unavailable:return diary.t("لا توجد كاميرا متاحة على هذا الجهاز. اختر صورة من المكتبة.","No camera is available on this device. Choose a photo from your library.")
        case .interrupted:return diary.t("توقفت الكاميرا مؤقتًا. ستعود عند انتهاء المقاطعة.","Camera temporarily interrupted. Preview will resume when available.")
        case .failed:return diary.t("تعذّر تشغيل الكاميرا. حاول مجددًا أو اختر صورة.","The camera could not start. Retry or choose a photo.")
        default:return nil
        }
    }
    private var analysisStatus:String {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-loqma-camera-ui-scan"){return diary.t("معاينة واجهة — دون تحليل","UI fixture — no analysis")}
        #endif
        return scanFinishing == nil ? diary.t("جاري تحليل الصورة…","Analyzing photo…"):diary.t("اكتمل التحليل","Analysis complete")
    }
    private func refreshCamera(){
        // DEBUG fixtures remain isolated from hardware and the real analyzer.
        #if DEBUG
        let fixture=ProcessInfo.processInfo.arguments.contains("-loqma-approved-photo-results") || ProcessInfo.processInfo.arguments.contains("-loqma-preview-photo") || ProcessInfo.processInfo.arguments.contains("-loqma-camera-ui-scan")
        #else
        let fixture=false
        #endif
        liveCamera.setActive(visible && phase == .active && imageData == nil && !loadingPhoto && parts.isEmpty && !showingGallery && !showingSetup && !fixture)
    }
    private func capturePhoto(){
        guard !busy,!loadingPhoto else{return}
        liveCamera.capture{data in
            guard visible,phase == .active else{return}
            guard let data else{error=diary.t("تعذّر التقاط الصورة. حاول مجددًا أو اختر صورة من المكتبة.","The photo could not be captured. Retry or choose a photo.");return}
            UIImpactFeedbackGenerator(style:.light).impactOccurred(intensity:0.6)
            if !reduceMotion{shutterVisible=true}
            automaticallyAnalyze=true;error=nil;imageData=data
        }
    }
    private func cancelPhotoLoad(){
        photoGeneration=UUID();photoLoadTask?.cancel();photoLoadTask=nil;loadingPhoto=false;automaticallyAnalyze=false;item=nil;refreshCamera()
    }
    private func loadPhoto(_ value:PhotosPickerItem?){
        photoLoadTask?.cancel();let token=UUID();photoGeneration=token
        guard let value else{loadingPhoto=false;refreshCamera();return}
        previewGeneration=UUID();previewTask?.cancel();previewTask=nil
        loadingPhoto=true;automaticallyAnalyze=false;parts=[];products=[:];error=nil;refreshCamera()
        photoLoadTask=Task{do{
            let data=try await value.loadTransferable(type:Data.self);try Task.checkCancellation()
            guard photoGeneration==token else{return}
            guard let data else{throw AppError.invalid("تعذّر فتح الصورة. اختر صورة أخرى.","The photo could not be opened. Choose another photo.")}
            automaticallyAnalyze=true
            // Equal bytes still represent a new selection and must invoke analysis.
            if imageData == data{preparePhotoPreview(data)}else{imageData=data}
        }catch{guard photoGeneration==token,!Task.isCancelled else{return};self.error=diary.t("تعذّر فتح الصورة. اختر صورة أخرى.","The photo could not be opened. Choose another photo.")}
            if photoGeneration==token{loadingPhoto=false;photoLoadTask=nil;item=nil;refreshCamera()}
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
                if automaticallyAnalyze{
                    if ready,visible,phase == .active{automaticallyAnalyze=false;analyze()}else if !ready{showingSetup=true}
                }
            }catch is CancellationError{return}
            catch {
                guard !Task.isCancelled,previewGeneration==token else{return}
                previewTask=nil;imageData=nil
                self.error=(error as? AppError)?.message(diary.language) ?? diary.t("تعذّر فتح الصورة. اختر صورة أخرى.","The photo could not be opened. Choose another photo.")
            }
        }
    }
    private func analyze(){guard let imageData,preview != nil,!busy,!loadingPhoto,visible,phase == .active else{return};descriptionFocused=false;busy=true;scanStarted=Date();scanFinishing=nil;error=nil;cancellationMessage=nil;parts=[];products=[:]
        let token=UUID();analysisGeneration=token;let context=description,language=diary.language
        analysisTask=Task{do{
            let result=try await GeminiMealService.shared.analyze(imageData:imageData,context:context,language:language);try Task.checkCancellation();guard analysisGeneration==token else{return}
            var prepared:[UUID:(Food,Double,FoodUnit)]=[:]
            for part in result.parts{guard let e=part.mealEstimate else{throw AppError.invalid("تقدير الوجبة غير مكتمل. حاول مجددًا.","The meal estimate is incomplete. Retry.")};prepared[part.id]=(try e.food(name:part.food.name,nameEn:part.food.nameEn,identity:part.id,language:diary.language),1,.serving)}
            // Finish only after genuine service success, with a short, bounded
            // sweep/fade. Cancellation during this transition discards the result.
            scanFinishing=Date()
            try await Task.sleep(for:.milliseconds(240));try Task.checkCancellation()
            guard analysisGeneration==token,visible,phase == .active else{return}
            withAnimation(reduceMotion ? nil:.easeOut(duration:0.2)){
                parts=result.parts;products=prepared;showingPhotoInput=false;detailedComponents=false
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }catch is CancellationError{if analysisGeneration==token{error=cancellationMessage ?? diary.t("تم إلغاء التحليل. يمكنك المحاولة مجددًا.","Analysis cancelled. You can retry.")}}catch{if analysisGeneration==token{self.error=Task.isCancelled ? cancellationMessage:((error as? AppError)?.message(diary.language) ?? diary.t("تعذّر التحليل. تحقق من الاتصال وحاول مجددًا.","Analysis failed. Check your connection and retry."))}};if analysisGeneration==token{busy=false;scanFinishing=nil;analysisTask=nil}}
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
