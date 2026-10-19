import SwiftUI
import PhotosUI
import UIKit
import AVFoundation

typealias FoodCommit = (Food,Double,FoodUnit,Meal) -> Bool
typealias PhotoFoodCommit = ([(Food,Double,FoodUnit)],Meal) -> Bool
@MainActor struct FoodAddView:View {
    var initial:Food? = nil
    var initialQuery=""
    var productSelection=false
    var initialMeal:Meal?=nil
    var onPhotoCommit: PhotoFoodCommit? = nil
    var onCommit:FoodCommit
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var phase
    @State private var tab=0
    @State private var query=""
    @State private var code=""
    @State private var busy=false
    @State private var pageLoading=false
    @State private var scanning=false
    @State private var manual=false
    @State private var localResults:[Food]=[]
    @State private var remoteResults:[Food]=[]
    @State private var results:[Food]=[]
    @State private var nextPage:Int?
    @State private var reachedSourceWindow=false
    @State private var selected:Food?
    private struct SearchNotice {let text:String;let isError:Bool;let offersSettings:Bool}
    @State private var notice:SearchNotice?
    @State private var photo:PhotosPickerItem?
    @State private var queryToken=UUID()
    @State private var searchTask:Task<Void,Never>?
    @State private var barcodePhotoTask:Task<Void,Never>?
    @State private var selectionTask:Task<Void,Never>?
    @State private var choosingFood=false
    @State private var filter=0
    @State private var recentFoods:[Food]=[]
    @State private var frequentFoods:[Food]=[]
    @State private var savedFoods:[Food]=[]
    @State private var historyTask:Task<Void,Never>?
    @State private var suggestedQuery:String?
    @State private var photoToken=UUID()
    @State private var suggestions:[FoodSuggestion]=[]
    @State private var nearbyResults:[Food]=[]
    @State private var bestMatch:Food?
    @State private var otherResults:[Food]=[]
    private var term:String {query.trimmingCharacters(in:.whitespacesAndNewlines)}
    private var displayedResults:[Food] {results}
    // Reconstruction measurements from the saved Search raster, not Figma child-node metrics.
    private enum SearchLayout {
        static let margin:CGFloat=16
        static let headerRadius:CGFloat=28
        static let fieldRadius:CGFloat=16
        static let chipRadius:CGFloat=7
        static let glowHeight:CGFloat=88
    }
    var body:some View {
        NavigationStack {
            VStack(spacing:0){
                searchHeader
                ScrollView {
                    VStack(alignment:.leading,spacing:12) {
                        if tab==0 {searchContent}
                        if tab==1 {barcodeContent}
                        if tab==2 && !productSelection {AnyView(PhotoMealView(initialMeal:initialMeal){foods,meal in onPhoto(foods,meal)})}
                        if let notice,tab != 2 {
                            if notice.isError{SandowStateAlert(text:notice.text)}else{Notice(text:notice.text)}
                            if notice.offersSettings{
                                Button(diary.t("فتح الإعدادات","Open Settings")){if let url=URL(string:UIApplication.openSettingsURLString){openURL(url)}}
                                    .buttonStyle(LuqmaSecondaryButtonStyle())
                            }
                        }
                        if busy || choosingFood {
                            SandowOperationState(title:choosingFood ? diary.t("جلب تفاصيل المنتج…","Loading product details…"):
                                diary.t(tab==1 ? "البحث عن المنتج…":"البحث عن المنتجات…",tab==1 ? "Looking up the product…":"Searching products…"),
                                cancelLabel:diary.t("إلغاء","Cancel"),onCancel:{cancelOperation()})
                        }
                        resultsContent
                    }.padding(SearchLayout.margin)
                }.scrollDismissesKeyboard(.interactively)
                    .background(alignment:.top){
                        if tab==0{
                            LinearGradient(colors:[Theme.accent.opacity(0.13),.clear],startPoint:.top,endPoint:.bottom)
                                .frame(height:SearchLayout.glowHeight).allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
            }.appBackground()
                .toolbar(.hidden,for:.navigationBar)
                .sheet(item:$selected){food in FoodPortionView(food:food,sourceBarcode:tab==1,initialMeal:initialMeal,onCommit:{f,a,u,m in if onCommit(f,a,u,m){dismiss();return true};return false})}
                .sheet(isPresented:$manual){FoodPortionView(food:Food(name:""),manual:true,initialMeal:initialMeal,onCommit:{f,a,u,m in if onCommit(f,a,u,m){dismiss();return true};return false})}
                .sheet(isPresented:$scanning){NavigationStack{BarcodeCamera(language:diary.language,completion:{value in scanning=false;code=value;startLookup()},failed:{message in scanning=false;presentNotice(message,error:true,settings:cameraAccessBlocked)}).ignoresSafeArea().sandowNavigation(diary.t("مسح الباركود","Scan barcode"),backLabel:diary.t("إغلاق","Close"),onBack:{scanning=false})}}
        }.onAppear{if let initial{selected=initial};if query.isEmpty && !initialQuery.isEmpty {query=initialQuery};refreshHistory();if tab==0 {searchTask=Task{await refreshLocal()}}}
            .onChange(of:diary.state.entries){_,_ in refreshHistory()}
            .onChange(of:diary.state.customFoods){_,_ in refreshHistory()}
            .onChange(of:diary.state.products){_,_ in refreshHistory()}
            .onChange(of:diary.language){_,_ in resetSearch();searchTask=Task{await refreshLocal()}}
            .onChange(of:query){_,value in let submit=suggestedQuery==value;suggestedQuery=nil;resetSearch();searchTask=Task{if submit{await search()}else{await refreshLocal()}}}
            .onChange(of:filter){_,_ in resetSearch();searchTask=Task{await refreshLocal()}}
            .onChange(of:tab){_,value in resetSearch();barcodePhotoTask?.cancel();photoToken=UUID();photo=nil;if value==0 {searchTask=Task{await refreshLocal()}}}
            .onChange(of:phase){_,value in if value == .active,notice?.offersSettings == true,AVCaptureDevice.authorizationStatus(for:.video) == .authorized{notice=nil}}
            .onDisappear{searchTask?.cancel();selectionTask?.cancel();historyTask?.cancel();queryToken=UUID();busy=false;pageLoading=false;choosingFood=false;barcodePhotoTask?.cancel();photoToken=UUID()}
            .onChange(of:photo){_,item in readBarcodePhoto(item)}
    }
    private var searchHeader:some View {
        VStack(alignment:.leading,spacing:8){
            HStack(spacing:8){
                Button{if tab==0{closeFoodAdd()}else{tab=0}}label:{
                    Image(systemName:"chevron.backward").font(.system(size:13,weight:.semibold))
                        .frame(width:36,height:36).background((tab==0 ? Theme.onAccent:Theme.text).opacity(0.12),in:RoundedRectangle(cornerRadius:12,style:.continuous))
                        .frame(width:44,height:44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(diary.t(tab==0 ? "إغلاق":"العودة للبحث",tab==0 ? "Close":"Back to search"))
                    .accessibilityIdentifier("search.close")
                Text(diary.t(tab==1 ? "باركود":tab==2 ? "تحليل الوجبة":productSelection ? "اختيار المنتج":"بحث",tab==1 ? "Barcode":tab==2 ? "Meal analysis":productSelection ? "Select a product":"Search"))
                    .luqmaFont(size:tab==0 ? 18:14,weight:.semibold,relativeTo:.headline)
                    .multilineTextAlignment(.leading).accessibilityAddTraits(.isHeader)
                Spacer(minLength:0)
                if tab != 0{
                    Button{closeFoodAdd()}label:{Image(systemName:"xmark").font(.system(size:14,weight:.medium)).frame(width:44,height:44)}
                        .buttonStyle(.plain).accessibilityLabel(diary.t("إغلاق","Close"))
                }else{
                    HStack(spacing:0){
                        Button{tab=1}label:{Image(systemName:"barcode.viewfinder").font(.system(size:17,weight:.regular)).frame(width:44,height:44)}
                            .buttonStyle(.plain).accessibilityLabel(diary.t("قارئ الباركود","Barcode reader"))
                        if !productSelection{
                            Button{tab=2}label:{Image(systemName:"camera").font(.system(size:17,weight:.regular)).frame(width:44,height:44)}
                                .buttonStyle(.plain).accessibilityLabel(diary.t("تحليل صورة الوجبة","Analyze a meal photo"))
                        }
                    }.disabled(choosingFood)
                }
            }
            if tab==0{
                HStack(spacing:10){
                    TextField(diary.t("اسم الطعام أو المنتج","Food or product name"),text:$query,
                        prompt:Text(diary.t("ابحث عن طعامك…","Search your food…")).foregroundColor(Theme.muted))
                        .submitLabel(.search).autocorrectionDisabled().onSubmit{startSearch()}
                        .accessibilityIdentifier("search.query")
                    if !query.isEmpty{
                        Button{query=""}label:{Image(systemName:"xmark.circle.fill").frame(width:44,height:44)}
                            .buttonStyle(.plain).accessibilityLabel(diary.t("مسح البحث","Clear search"))
                    }
                    if filter==0{
                        Button{startSearch()}label:{Image(systemName:"magnifyingglass").font(.system(size:18,weight:.regular)).frame(width:44,height:44)}
                            .buttonStyle(.plain).accessibilityLabel(diary.t("بحث عن المنتجات","Search products"))
                            .disabled(term.isEmpty || busy || pageLoading || choosingFood)
                    }else{Image(systemName:"magnifyingglass").font(.system(size:18)).frame(width:44,height:44).accessibilityHidden(true)}
                }.luqmaFont(size:14,relativeTo:.subheadline).foregroundStyle(Theme.text)
                    .padding(.leading,16).padding(.trailing,6).padding(.vertical,6).frame(minHeight:56)
                    .background(Theme.background,in:RoundedRectangle(cornerRadius:SearchLayout.fieldRadius,style:.continuous))
                ScrollView(.horizontal,showsIndicators:false){
                    HStack(spacing:6){
                        sourceFilter(0,title:diary.t("الكل","All"),symbol:"fork.knife")
                        sourceFilter(1,title:diary.t("الأخيرة","Recent"),symbol:"clock")
                        sourceFilter(2,title:diary.t("المتكررة","Frequent"),symbol:"chart.bar")
                        if !productSelection{sourceFilter(3,title:diary.t("أطعمتي","My foods"),symbol:"square.and.pencil")}
                    }
                }.accessibilityElement(children:.contain).accessibilityLabel(diary.t("قائمة الأطعمة","Food list"))
            }
        }.foregroundStyle(tab==0 ? Theme.onAccent:Theme.text).padding(.horizontal,SearchLayout.margin).padding(.top,6).padding(.bottom,10)
            .frame(maxWidth:.infinity,alignment:.leading)
            .background{
                if tab==0{UnevenRoundedRectangle(bottomLeadingRadius:SearchLayout.headerRadius,bottomTrailingRadius:SearchLayout.headerRadius,style:.continuous).fill(Theme.accent).ignoresSafeArea(edges:.top)}
                else{Theme.background.ignoresSafeArea(edges:.top)}
            }
    }
    private func sourceFilter(_ value:Int,title:String,symbol:String)->some View {
        Button{filter=value}label:{
            Label(title,systemImage:symbol).luqmaFont(size:12,weight:.medium,relativeTo:.caption)
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal,8).frame(minHeight:28)
                .background(filter==value ? Theme.onAccent.opacity(0.12):Color.clear,in:RoundedRectangle(cornerRadius:SearchLayout.chipRadius,style:.continuous))
                .overlay{RoundedRectangle(cornerRadius:SearchLayout.chipRadius,style:.continuous).strokeBorder(Theme.onAccent,lineWidth:1)}
                .frame(minHeight:44).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(choosingFood).accessibilityAddTraits(filter==value ? .isSelected:[])
            .accessibilityIdentifier("search.filter."+String(value))
    }
    private func closeFoodAdd(){
        searchTask?.cancel();selectionTask?.cancel();barcodePhotoTask?.cancel();queryToken=UUID();photoToken=UUID();dismiss()
    }
    private var sourceFilterTitle:String {
        diary.t(filter==1 ? "الأخيرة":filter==2 ? "المتكررة":filter==3 ? "أطعمتي":"المصادر",
                filter==1 ? "Recent":filter==2 ? "Frequent":filter==3 ? "My foods":"Sources")
    }
    private func resultsToolbar(count:Int,nearby:Bool=false)->some View {
        HStack(spacing:8){
            Text(diary.t(nearby ? "\(count) نتائج قريبة":"\(count) نتيجة معروضة",
                         nearby ? "\(count) nearby results":"\(count) results shown"))
                .luqmaFont(size:12,weight:.semibold,relativeTo:.caption).foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength:0)
            Menu{
                Picker(diary.t("قائمة الأطعمة","Food list"),selection:$filter){
                    Text(diary.t("الكل","All")).tag(0)
                    Text(diary.t("الأخيرة","Recent")).tag(1)
                    Text(diary.t("المتكررة","Frequent")).tag(2)
                    if !productSelection{Text(diary.t("أطعمتي","My foods")).tag(3)}
                }
            }label:{
                HStack(spacing:5){
                    Image(systemName:"line.3.horizontal.decrease").font(.system(size:11))
                    Text(!nearby && bestMatch != nil ? diary.t("أفضل تطابق","Best match"):sourceFilterTitle)
                        .luqmaFont(size:11,weight:.medium,relativeTo:.caption2)
                    Image(systemName:"chevron.down").font(.system(size:8,weight:.medium))
                }.foregroundStyle(Theme.muted).padding(.horizontal,8).padding(.vertical,5)
                    .background(Theme.background,in:RoundedRectangle(cornerRadius:6,style:.continuous))
                    .overlay{RoundedRectangle(cornerRadius:6,style:.continuous).strokeBorder(Theme.muted.opacity(0.35),lineWidth:1)}
                    .frame(minHeight:44).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(choosingFood)
                .accessibilityLabel(diary.t("تصفية قائمة الأطعمة","Filter food list"))
                .accessibilityValue(!nearby && bestMatch != nil ? diary.t("أفضل تطابق","Best match"):sourceFilterTitle)
        }
    }
    private var resultsContent:some View {
        Group {
                    if tab==0 && !displayedResults.isEmpty {
                        resultsToolbar(count:displayedResults.count)
                        LazyVStack(alignment:.leading,spacing:8) {
                            if let bestMatch{FoodRow(food:bestMatch){select(bestMatch)}.disabled(choosingFood)}
                            ForEach(otherResults) {food in FoodRow(food:food){select(food)}.disabled(choosingFood).contextMenu{if filter==3{Button(role:.destructive){diary.removePersonal(food.id)}label:{Label(diary.t("حذف من أطعمتي","Remove from My foods"),systemImage:"trash")}}}}
                        }
                        if filter==0 && nextPage != nil {
                            Button {startMore()} label: {
                                HStack {if pageLoading {ProgressView()};Text(diary.t("عرض المزيد من المنتجات","Show more products"))}.frame(maxWidth:.infinity).padding(10)
                            }.buttonStyle(LuqmaSecondaryButtonStyle()).disabled(pageLoading || busy || choosingFood)
                        }
                    } else if tab==0 && filter==0 && nextPage != nil {
                        Button(diary.t("متابعة نتائج المنتجات","Continue product results")){startMore()}.buttonStyle(LuqmaSecondaryButtonStyle()).disabled(pageLoading || busy || choosingFood)
                    }
                    if tab==0 && filter==0 && !nearbyResults.isEmpty {
                        VStack(alignment:.leading,spacing:8) {
                            resultsToolbar(count:nearbyResults.count,nearby:true)
                            Text(diary.t("تشابه في الاسم فقط؛ قد تختلف العلامة التجارية أو نوع المنتج.","Similar names; the brand or product type may differ."))
                                .luqmaFont(size:11,relativeTo:.caption).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true)
                            LazyVStack(alignment:.leading,spacing:8){ForEach(nearbyResults){food in FoodRow(food:food){select(food)}.disabled(choosingFood)}}
                        }
                    }
                    if tab==0 && filter==0 && reachedSourceWindow {Notice(text:diary.t("البحث واسع جدًا. أضف كلمة مثل نوع الطعام أو العلامة التجارية للوصول إلى منتجات أخرى.","This search is very broad. Add a food type or brand to find other products."))}
                    if tab==0 && filter != 0 && displayedResults.isEmpty {Notice(text:diary.t(filter==3 ? "الأطعمة التي تضيفها يدويًا تُحفظ هنا لك وحدك." : "تظهر هنا الأطعمة التي تسجّلها في يومياتك. جرّب «الكل» للبحث في القاعدة.",filter==3 ? "Foods you create manually are saved here privately." : "Foods logged in your diary appear here. Choose All to search the database."))}
                    if tab==0 && !productSelection {
                        Button {manual=true} label: {Label(diary.t("إضافة طعام يدويًا","Add food manually"),systemImage:"square.and.pencil").luqmaFont(size:13,weight:.medium,relativeTo:.subheadline).frame(minHeight:44)}.padding(.top,4).disabled(choosingFood).accessibilityIdentifier("search.manual")
                    }
        }
    }
    private var searchContent:some View {
        Group{
            if filter==0 && displayedResults.isEmpty && nearbyResults.isEmpty{
                VStack(alignment:.leading,spacing:12){
                    if term.isEmpty && !recentFoods.isEmpty{recent(diary.t("الأخيرة","Recent foods"),Array(recentFoods.prefix(8)),reverse:false)}
                    if !suggestions.isEmpty && !busy{
                        VStack(alignment:.leading,spacing:0){
                            ForEach(suggestions.prefix(6)){suggestion in
                                Button{submitSuggestion(suggestion.query)}label:{
                                    HStack(spacing:10){
                                        Image(systemName:suggestion.kind == .history ? "clock":"magnifyingglass").font(.system(size:14))
                                        Text(DisplayFormat.westernDigits(suggestion.label)).lineLimit(2).multilineTextAlignment(.leading)
                                        Spacer(minLength:0)
                                        Image(systemName:"arrow.up.left").font(.system(size:12))
                                    }.luqmaFont(size:13,relativeTo:.subheadline).foregroundStyle(Theme.text)
                                        .padding(.horizontal,10).frame(minHeight:44).contentShape(Rectangle())
                                }.buttonStyle(.plain).disabled(choosingFood)
                            }
                        }.padding(6).background(Theme.card,in:RoundedRectangle(cornerRadius:14,style:.continuous))
                            .accessibilityElement(children:.contain).accessibilityLabel(diary.t("اقتراحات البحث","Suggested searches"))
                    }
                    if !term.isEmpty && !busy{Text(diary.t("اضغط بحث لعرض المزيد من المنتجات.","Tap Search to find more products.")).luqmaFont(.caption).foregroundStyle(Theme.muted)}
                }
            }
        }
    }
    private var barcodeContent:some View {
        VStack(alignment:.leading,spacing:16) {
            Button{openBarcodeCamera()}label:{Label(diary.t("مسح الباركود","Scan barcode"),systemImage:"barcode.viewfinder")}.buttonStyle(LuqmaPrimaryButtonStyle())
            PhotosPicker(selection:$photo,matching:.images){Label(diary.t("قراءة باركود من صورة","Read a barcode photo"),systemImage:"photo")}
            DisclosureGroup(diary.t("كتابة رقم الباركود","Enter barcode number")) {
                HStack{TextField(diary.t("رقم الباركود","Barcode number"),text:$code,prompt:Text(diary.t("رقم الباركود","Barcode number")).foregroundColor(Theme.muted)).keyboardType(.numberPad).environment(\.layoutDirection,.leftToRight);Button(diary.t("بحث","Look up")){startLookup()}.disabled(busy || code.isEmpty)}.padding(.vertical,12)
            }.luqmaCard()
            let scanned=diary.state.barcodeHistory.filter(FoodSearch.isCatalogFood)
            if !scanned.isEmpty {recent(diary.t("آخر المنتجات الممسوحة","Recently scanned products"),scanned)}
        }
    }
    private func select(_ food:Food) {
        guard FoodSearch.availableForAdding(food), !productSelection || FoodSearch.isCatalogFood(food) else{return}
        selectionTask?.cancel();searchTask?.cancel();barcodePhotoTask?.cancel();photoToken=UUID()
        let token=UUID(),fromBarcode=tab==1,selectionQuery=query,selectionTab=tab;queryToken=token;busy=false;pageLoading=false;choosingFood=false;notice=nil
        guard food.sourceDescription==FoodDatabase.searchSummarySourceDescription else {diary.remember(food,barcode:fromBarcode);selected=food;return}
        choosingFood=true
        selectionTask=Task {
            do {
                let resolved=try await FoodDatabase.shared.details(for:food)
                guard !Task.isCancelled,token==queryToken,selectionQuery==query,selectionTab==tab else{return}
                localResults=localResults.map{$0.id==food.id ? resolved:$0}
                remoteResults=remoteResults.map{$0.id==food.id ? resolved:$0}
                publishResults(results.map{$0.id==food.id ? resolved:$0})
                nearbyResults=nearbyResults.map{$0.id==food.id ? resolved:$0}
                choosingFood=false;diary.remember(resolved,barcode:fromBarcode);selected=resolved
            } catch {
                guard !Task.isCancelled,token==queryToken,selectionQuery==query,selectionTab==tab else{return}
                choosingFood=false
                presentNotice((error as? AppError)?.message(diary.language) ?? diary.t("تعذّر جلب تفاصيل المنتج ووحدته. أعد المحاولة عند توفر الإنترنت أو أضفه من الملصق.","Could not load the product details and unit. Retry when connected, or add it from the label."),error:true)
            }
        }
    }
    private func recent(_ title:String,_ foods:[Food],reverse:Bool=true) -> some View {let available=foods.filter{FoodSearch.availableForAdding($0) && (!productSelection || FoodSearch.isCatalogFood($0))};return VStack(alignment:.leading,spacing:10){Text(title).luqmaFont(.headline);ForEach(Array((reverse ? Array(available.reversed()):available).prefix(8))){food in FoodRow(food:food){select(food)}.disabled(choosingFood)}}}
    private func resetSearch() {
        searchTask?.cancel();selectionTask?.cancel();queryToken=UUID();busy=false;pageLoading=false;choosingFood=false;nextPage=nil;reachedSourceWindow=false
        localResults=[];remoteResults=[];publishResults([]);nearbyResults=[];suggestions=[];notice=nil
    }
    private func presentNotice(_ text:String,error:Bool=false,settings:Bool=false){
        notice=SearchNotice(text:text,isError:error,offersSettings:settings)
    }
    private func cancelOperation(){
        queryToken=UUID();photoToken=UUID();searchTask?.cancel();selectionTask?.cancel();barcodePhotoTask?.cancel()
        searchTask=nil;selectionTask=nil;barcodePhotoTask=nil;busy=false;pageLoading=false;choosingFood=false
    }
    private var cameraAccessBlocked:Bool {
        let status=AVCaptureDevice.authorizationStatus(for:.video)
        return status == .denied || status == .restricted
    }
    private func openBarcodeCamera(){
        notice=nil
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else{
            presentNotice(diary.t("لا توجد كاميرا متاحة على هذا الجهاز. استخدم صورة للباركود أو اكتب رقمه.","No camera is available on this device. Use a barcode photo or enter its number."),error:true);return
        }
        Task{
            let token=queryToken,allowed=await CameraAccess.request()
            guard tab==1,token==queryToken,!Task.isCancelled else{return}
            if allowed{scanning=true}
            else if cameraAccessBlocked{
                presentNotice(diary.t("الوصول إلى الكاميرا مرفوض أو مقيّد. راجع إذن الكاميرا في الإعدادات أو استخدم صورة للباركود.","Camera access is denied or restricted. Check camera access in Settings or use a barcode photo."),error:true,settings:true)
            }else{
                presentNotice(diary.t("تعذّر فتح الكاميرا. استخدم صورة للباركود أو اكتب رقمه.","The camera could not be opened. Use a barcode photo or enter its number."),error:true)
            }
        }
    }
    private func refreshHistory() {
        historyTask?.cancel();let snapshot=diary.state
        historyTask=Task{let lists=await FoodDatabase.shared.historyLists(snapshot);guard !Task.isCancelled else{return};recentFoods=lists.recent;frequentFoods=lists.frequent;savedFoods=lists.personal;if !busy && tab==0{await refreshLocal(debounce:false)}}
    }
    private func startSearch(){guard !choosingFood else{return};searchTask?.cancel();searchTask=Task{await search()}}
    private func submitSuggestion(_ value:String){if query==value{startSearch()}else{suggestedQuery=value;query=value}}
    private func startMore(){guard tab==0,!busy,!pageLoading,!choosingFood,nextPage != nil else{return};searchTask?.cancel();searchTask=Task{await more()}}
    private func startLookup(){guard tab==1 else{return};barcodePhotoTask?.cancel();photoToken=UUID();searchTask?.cancel();searchTask=Task{await lookup()}}
    private func readBarcodePhoto(_ item:PhotosPickerItem?) {
        barcodePhotoTask?.cancel();let token=UUID();photoToken=token
        guard tab==1,let item else{return}
        searchTask?.cancel();queryToken=UUID();busy=false;pageLoading=false;notice=nil
        barcodePhotoTask=Task {
            do {
                let data=try await item.loadTransferable(type:Data.self)
                guard !Task.isCancelled,token==photoToken,tab==1 else{return}
                let value:String?
                if let data {value=try await CameraAccess.barcode(in:data)} else {value=nil}
                guard !Task.isCancelled,token==photoToken,tab==1 else{return}
                if let value {code=value;startLookup()}
                else {presentNotice(diary.t("لم نعثر على باركود واضح في الصورة.","No readable barcode was found in the photo."))}
            } catch {
                guard !Task.isCancelled,token==photoToken,tab==1 else{return};diary.report(error)
            }
        }
    }
    private func publishResults(_ found:[Food]) {
        results=found
        bestMatch=filter==0 && !term.isEmpty ? found.first:nil
        otherResults=bestMatch == nil ? found:Array(found.dropFirst())
    }
    private func mergeResults(_ token:UUID) async -> Bool {
        let value=term
        let found=await FoodDatabase.shared.combinedMatches(value,local:localResults,remote:remoteResults,catalogOnly:productSelection)
        guard !Task.isCancelled,token==queryToken,value==term else{return false}
        publishResults(found.exact);nearbyResults=found.nearby;return true
    }
    private func refreshLocal(debounce:Bool=true) async {
        let token=queryToken,value=term,currentFilter=filter,language=diary.language
        guard tab==0 else{return}
        if debounce {do{try await Task.sleep(nanoseconds:280_000_000)}catch{return}}
        guard !Task.isCancelled,token==queryToken else{return}
        let personal:[Food]? = currentFilter==0 ? nil:currentFilter==1 ? recentFoods:currentFilter==2 ? frequentFoods:savedFoods
        let found=await FoodDatabase.shared.presentation(value,cached:diary.state.products+savedFoods,history:recentFoods,personal:personal,language:language,catalogOnly:productSelection)
        guard !Task.isCancelled,token==queryToken,tab==0,currentFilter==filter,value==term,language==diary.language else{return}
        suggestions=found.suggestions
        localResults=found.exact+found.nearby
        if currentFilter==0 && !remoteResults.isEmpty {_ = await mergeResults(token)}
        else {publishResults(found.exact);nearbyResults=found.nearby}
    }
    private func search() async {
        let value=term;guard !Task.isCancelled,tab==0,filter==0,!value.isEmpty else{return}
        let token=UUID();queryToken=token;busy=true;pageLoading=false;notice=nil;nextPage=nil;reachedSourceWindow=false;remoteResults=[]
        let found=await FoodDatabase.shared.presentation(value,cached:diary.state.products+savedFoods,history:recentFoods,language:diary.language,catalogOnly:productSelection)
        guard !Task.isCancelled,token==queryToken else{return};localResults=found.exact+found.nearby;suggestions=found.suggestions
        guard await mergeResults(token) else{return}
        do {
            let page=try await FoodDatabase.shared.remote(value)
            guard !Task.isCancelled,token==queryToken else{return}
            remoteResults=page.foods;nextPage=page.nextPage;reachedSourceWindow=page.reachedSourceWindow
            guard await mergeResults(token) else{return}
            if results.isEmpty {presentNotice(diary.t(nearbyResults.isEmpty ? "لم نجد منتجًا مطابقًا. اختصر البحث أو جرّب اسم العلامة التجارية." : "لم نجد تطابقًا لكل الكلمات. المنتجات القريبة أدناه قد تختلف في العلامة أو النوع؛ راجعها قبل الإضافة.",nearbyResults.isEmpty ? "No matching product. Shorten the query or try its brand name.":"No product matches every word. Nearby products may have a different brand or type; review them before adding."))}
        } catch {
            guard !Task.isCancelled,token==queryToken else{return}
            presentNotice((error as? AppError)?.message(diary.language) ?? diary.t("البحث عبر الإنترنت غير متاح. نعرض الأطعمة المحفوظة.","Online search is unavailable. Saved foods are shown."),error:true)
        }
        if token==queryToken {busy=false}
    }
    private func more() async {
        guard !Task.isCancelled,tab==0,filter==0,let pageNumber=nextPage,!busy,!pageLoading else{return}
        let token=queryToken,value=term;pageLoading=true;notice=nil
        do {
            let page=try await FoodDatabase.shared.remote(value,page:pageNumber)
            guard !Task.isCancelled,token==queryToken else{return}
            remoteResults += page.foods;nextPage=page.nextPage;reachedSourceWindow=page.reachedSourceWindow
            guard await mergeResults(token) else{return}
        } catch {
            guard !Task.isCancelled,token==queryToken else{return}
            presentNotice((error as? AppError)?.message(diary.language) ?? diary.t("تعذّر تحميل المزيد. حاول مرة أخرى.","Could not load more. Try again."),error:true)
        }
        if token==queryToken {pageLoading=false}
    }
    private func lookup() async {
        guard !Task.isCancelled,tab==1 else{return}
        let token=UUID();queryToken=token;busy=true;notice=nil
        do{let food=try await FoodDatabase.shared.barcode(code,cached:diary.state.products);guard !Task.isCancelled,token==queryToken else{return};if let food{diary.remember(food,barcode:true);selected=food}else{presentNotice(diary.t("الباركود مقروء لكن المنتج غير مسجل في Open Food Facts. أضفه من الملصق.","The barcode was read, but the product is absent from Open Food Facts. Add its label nutrition."))}}
        catch{guard !Task.isCancelled,token==queryToken else{return};presentNotice((error as? AppError)?.message(diary.language) ?? diary.t("تعذّر الاتصال بقاعدة المنتجات. أعد المحاولة عند توفر الإنترنت.","The database could not be reached. Retry when connected."),error:true)}
        if token==queryToken {busy=false}
    }
    private func onPhoto(_ values:[(Food,Double,FoodUnit)],_ meal:Meal) -> Bool {
        guard !values.isEmpty,values.allSatisfy({FoodSearch.isCatalogFood($0.0) || MealPhotoEstimate.isValidPhotoEstimate($0.0)}) else{return false}
        if let onPhotoCommit {if onPhotoCommit(values,meal){dismiss();return true};return false}
        if values.count==1,let first=values.first{if onCommit(first.0,first.1,first.2,meal){dismiss();return true};return false}
        guard let combined=try? values.reduce(Nutrition.zero,{$0+(try $1.0.total($1.1,unit:$1.2))}) else{return false}
        let name=values.map{$0.0.label(diary.language)}.joined(separator:" + ")
        var food=Food(catalogID:"personal:"+UUID().uuidString,name:String(name.prefix(180)),unit:.serving,nutrition:combined,servingNutrition:combined,source:"Your food")
        if values.contains(where:{MealPhotoEstimate.isValidPhotoEstimate($0.0)}){food.sourceDescription="luqma:estimated-components"}
        if onCommit(food,1,.serving,meal){dismiss();return true};return false
    }
}

struct FoodPortionView:View {
    let food:Food
    var manual=false,sourceBarcode=false
    var initialMeal:Meal?=nil
    var onCommit:FoodCommit
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dismiss) var dismiss
    @State private var unit:FoodUnit = .serving
    @State private var portionID=""
    @State private var meal:Meal = .breakfast
    @State private var name=""
    @State private var amount="1"
    @State private var kcal=""
    @State private var protein=""
    @State private var carbs=""
    @State private var fat=""
    @State private var editingNutrition=false
    @State private var servingID=""
    @State private var servingWeight=""
    @State private var personalID="personal:"+UUID().uuidString
    private var needsServingSize:Bool {!manual && food.unit != .serving && food.values(for:.serving)==nil && food.per100 != nil}
    private var portionFood:Food {
        if let choice=food.portionChoices.first(where:{$0.id==portionID}) {return (try? food.selectingPortion(choice)) ?? food}
        if let choice=food.servingChoices.first(where:{$0.id==servingID}) {return (try? food.selecting(choice)) ?? food}
        if needsServingSize,let value=TextSearch.number(servingWeight) {return (try? food.definingServing(quantity:value,unit:food.unit,label:"\(decimal(value)) \(food.unit.label(diary.language))")) ?? food}
        return food
    }
    private var base:Nutrition? {guard let k=TextSearch.number(kcal),let p=TextSearch.number(protein),let c=TextSearch.number(carbs),let f=TextSearch.number(fat) else{return nil};let n=Nutrition(kcal:k,protein:p,carbs:c,fat:f);return n.valid ? n:nil}
    private var quantity:Double? {TextSearch.number(amount)}
    private var total:Nutrition {base?.scaled((quantity ?? 0)/(unit == .serving ? 1:100)) ?? .zero}
    var body:some View {
        NavigationStack{Form{
            Section{
                if manual {TextField(diary.t("اسم الطعام","Food name"),text:$name,prompt:Text(diary.t("اسم الطعام","Food name")).foregroundColor(Theme.muted)).accessibilityIdentifier("portion.name")}else{Text(name).luqmaFont(.headline);if let brand=food.brand{Text(DisplayFormat.westernDigits(brand)).luqmaFont(.caption).foregroundStyle(Theme.muted)}}
                Picker(diary.t("الوجبة","Meal"),selection:$meal){ForEach(Meal.allCases){Text($0.label(diary.language)).tag($0)}}
            }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            Section(diary.t("الكمية","Amount")) {
                Picker(diary.t("الوحدة","Unit"),selection:$unit){ForEach(manual ? [.serving,.g,.ml]:food.additionUnits,id:\.self){Text($0.label(diary.language)).tag($0)}}.pickerStyle(.segmented)
                if unit == .serving && !food.servingChoices.isEmpty {
                    Picker(diary.t("حجم الحصة","Serving size"),selection:$servingID){
                        if food.servingNutrition != nil {Text(DisplayFormat.westernDigits(food.serving ?? diary.t("الحصة المحفوظة","Saved serving"))).tag("")}
                        ForEach(food.servingChoices){choice in Text("\(DisplayFormat.westernDigits(choice.label)) · \(decimal(choice.grams)) \(diary.t("جم","g"))").tag(choice.id)}
                    }
                }
                if unit == .serving && !food.portionChoices.isEmpty {
                    Picker(diary.t("حجم الحصة","Serving size"),selection:$portionID){ForEach(food.portionChoices){choice in Text(DisplayFormat.westernDigits(choice.label)).tag(choice.id)}}
                }
                if unit == .serving && needsServingSize {
                    input(diary.t(food.unit == .ml ? "حجم الحصة (مل)":"وزن الحصة (جم)",food.unit == .ml ? "Serving volume (ml)":"Serving weight (g)"),$servingWeight)
                    Text(diary.t("لا يحدد المصدر حجم الحصة. أدخله من الملصق أو اختر وحدة المنتج.","The source has no serving size. Enter it from the label, or choose the product's unit.")).luqmaFont(.caption).foregroundStyle(Theme.muted)
                }
                if let serving=portionFood.serving,unit == .serving{Text(DisplayFormat.westernDigits(serving)).luqmaFont(.footnote).foregroundStyle(.secondary)}
                input(diary.t(unit == .serving ? "عدد الحصص":"الكمية المستهلكة",unit == .serving ? "Number of servings":"Consumed amount"),$amount,identifier:"portion.amount")
                if base != nil {NutritionView(value:total,large:true)}else{Text(diary.t("حدد الحصة لعرض مجموع التغذية","Set the serving to see nutrition totals")).luqmaFont(.subheadline).foregroundStyle(Theme.muted)}
            }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            Section{
                if manual {Text(referenceTitle).luqmaFont(.headline);referenceInputs}
                else {DisclosureGroup(referenceTitle,isExpanded:$editingNutrition){referenceInputs}}
            }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
        }.sandowForm().sandowNavigation(diary.t("كمية الطعام","Food portion"),backLabel:diary.t("إلغاء","Cancel"),onBack:{dismiss()},
            actionLabel:diary.t("إضافة الطعام","Add food"),
            actionEnabled:!(base==nil || name.trimmingCharacters(in:.whitespaces).isEmpty || (quantity ?? 0)<=0 || (quantity ?? 0)>10000),actionIdentifier:"portion.save",onAction:{save()})
        }.onAppear{if let initialMeal{meal=initialMeal};unit=food.defaultAdditionUnit;name=food.label(diary.language);amount="1";portionID=food.selectedPortionID ?? food.portionChoices.first?.id ?? "";if food.servingNutrition==nil{servingID=food.servingChoices.first?.id ?? ""};loadBase();editingNutrition=manual || (portionFood.per100==nil && portionFood.servingNutrition==nil)}
            .onChange(of:unit){_,_ in amount=unit == .serving ? "1":"100";if !manual{loadBase();if portionFood.values(for:unit)==nil && !needsServingSize{editingNutrition=true}}}
            .onChange(of:servingID){_,_ in if !manual{loadBase()}}
            .onChange(of:portionID){_,_ in if !manual{loadBase();editingNutrition=portionFood.values(for:unit)==nil}}
            .onChange(of:servingWeight){_,_ in if !manual && unit == .serving{loadBase()}}
    }
    private var referenceTitle:String {unit == .serving ? diary.t("القيم للحصة الواحدة","Values per serving"):diary.t("القيم لكل ١٠٠","Values per 100")+" "+unit.label(diary.language)}
    private var referenceInputs:some View {Group{
        input(diary.t("السعرات","Calories"),$kcal,identifier:"portion.kcal");input(diary.t("البروتين","Protein"),$protein,identifier:"portion.protein");input(diary.t("الكارب","Carbs"),$carbs,identifier:"portion.carbs");input(diary.t("الدهون","Fat"),$fat,identifier:"portion.fat")
        if !manual,portionFood.values(for:unit)==nil && !needsServingSize {Notice(text:diary.t("المنتج ينقصه بيانات؛ أكملها من الملصق قبل الإضافة.","Nutrition is incomplete. Fill in the label values before adding."))}
    }}
    private func input(_ label:String,_ text:Binding<String>,identifier:String?=nil) -> some View {HStack{Text(label);Spacer();TextField(label,text:text,prompt:Text(label).foregroundColor(Theme.muted)).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width:120).accessibilityIdentifier(identifier ?? label)}}
    private func loadBase(){let n=portionFood.values(for:unit);kcal=n.map{decimal($0.kcal,2)} ?? "";protein=n.map{decimal($0.protein,3)} ?? "";carbs=n.map{decimal($0.carbs,3)} ?? "";fat=n.map{decimal($0.fat,3)} ?? ""}
    private func save(){
        guard let base,let quantity else{return}
        var f=portionFood;f.name=String(name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(180))
        if diary.language == .en {f.nameEn=f.name}
        if manual{f.catalogID=personalID;f.source="Your food";f.unit=unit}
        do {f=try f.withReference(base,unit:unit);if onCommit(f,quantity,unit,meal){diary.remember(f,barcode:sourceBarcode);dismiss()}}
        catch{diary.report(error)}
    }
}
