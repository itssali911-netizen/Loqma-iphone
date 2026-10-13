import SwiftUI
import PhotosUI
import UIKit

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
    @State private var notice:String?
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
    @State private var suggestionFoods:[Food]=[]
    private var term:String {query.trimmingCharacters(in:.whitespacesAndNewlines)}
    private var personalList:[Food] {
        let foods = filter == 1 ? recentFoods : filter == 2 ? frequentFoods : savedFoods
        return term.isEmpty ? foods : foods.filter { FoodSearch.matches($0,query:term) }
    }
    private var displayedResults:[Food] {let found=filter == 0 ? results:personalList;return productSelection ? found.filter{FoodSearch.isCatalogFood($0)}:found}
    private var bestMatch:Food? {filter == 0 && !term.isEmpty ? displayedResults.first : nil}
    private var otherResults:[Food] {guard let bestMatch else{return displayedResults};return displayedResults.filter{$0.id != bestMatch.id}}
    private var suggestions:[FoodSuggestion] {FoodSuggestions.suggestions(query:term,foods:suggestionFoods,language:diary.language,history:recentFoods,limit:6)}
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    if tab != 0 {
                        Button {tab=0} label: {Label(diary.t("العودة للبحث","Back to search"),systemImage:"magnifyingglass")}
                    }
                    if tab==0 {searchContent}
                    if tab==1 {barcodeContent}
                    if tab==2 && !productSelection {AnyView(PhotoMealView(initialMeal:initialMeal){foods,meal in onPhoto(foods,meal)})}
                    if let notice,tab != 2 {Notice(text:notice)}
                    if busy || choosingFood {ProgressView(choosingFood ? diary.t("جلب تفاصيل المنتج…","Loading product details…"):"").frame(maxWidth:.infinity)}
                    if tab==0 && !displayedResults.isEmpty {
                        if let bestMatch {
                            VStack(alignment:.leading,spacing:8){
                                Label(diary.t("أفضل تطابق","Best match"),systemImage:"star.fill").font(.subheadline.bold()).foregroundStyle(Theme.accent)
                                FoodRow(food:bestMatch){select(bestMatch)}.disabled(choosingFood)
                            }.luqmaCard()
                        }
                        if !otherResults.isEmpty {Text(diary.t(bestMatch == nil ? "الأطعمة":"نتائج أخرى",bestMatch == nil ? "Foods":"Other results")+" (\(otherResults.count))").font(.headline)}
                        LazyVStack(alignment:.leading,spacing:4) {
                            ForEach(otherResults) {food in FoodRow(food:food){select(food)}.disabled(choosingFood).contextMenu{if filter==3{Button(role:.destructive){diary.removePersonal(food.id)}label:{Label(diary.t("حذف من أطعمتي","Remove from My foods"),systemImage:"trash")}}}}
                        }
                        if filter==0 && nextPage != nil {
                            Button {startMore()} label: {
                                HStack {if pageLoading {ProgressView()};Text(diary.t("عرض المزيد من المنتجات","Show more products"))}.frame(maxWidth:.infinity).padding(10)
                            }.buttonStyle(.bordered).disabled(pageLoading || busy || choosingFood)
                        }
                    } else if tab==0 && filter==0 && nextPage != nil {
                        Button(diary.t("متابعة نتائج المنتجات","Continue product results")){startMore()}.buttonStyle(.bordered).disabled(pageLoading || busy || choosingFood)
                    }
                    if tab==0 && filter==0 && reachedSourceWindow {Notice(text:diary.t("البحث واسع جدًا. أضف كلمة مثل نوع الطعام أو العلامة التجارية للوصول إلى منتجات أخرى.","This search is very broad. Add a food type or brand to find other products."))}
                    if tab==0 && filter != 0 && displayedResults.isEmpty {Notice(text:diary.t(filter==3 ? "الأطعمة التي تضيفها يدويًا تُحفظ هنا لك وحدك." : "تظهر هنا الأطعمة التي تسجّلها في يومياتك. جرّب «الكل» للبحث في القاعدة.",filter==3 ? "Foods you create manually are saved here privately." : "Foods logged in your diary appear here. Choose All to search the database."))}
                    if tab==0 && !productSelection {
                        Button {manual=true} label: {Label(diary.t("إضافة طعام يدويًا","Add food manually"),systemImage:"square.and.pencil")}.padding(.top,4).disabled(choosingFood)
                    }
                }.padding(20)
            }.appBackground().navigationTitle(diary.t(tab==1 ? "باركود":tab==2 ? "صورة الوجبة":"إضافة طعام",tab==1 ? "Barcode":tab==2 ? "Meal photo":"Add food"))
                .toolbar {ToolbarItem(placement:.cancellationAction){Button(diary.t("إغلاق","Close")){searchTask?.cancel();selectionTask?.cancel();barcodePhotoTask?.cancel();queryToken=UUID();photoToken=UUID();dismiss()}}}
                .sheet(item:$selected){food in FoodPortionView(food:food,sourceBarcode:tab==1,initialMeal:initialMeal,onCommit:{f,a,u,m in if onCommit(f,a,u,m){dismiss();return true};return false})}
                .sheet(isPresented:$manual){FoodPortionView(food:Food(name:""),manual:true,initialMeal:initialMeal,onCommit:{f,a,u,m in if onCommit(f,a,u,m){dismiss();return true};return false})}
                .sheet(isPresented:$scanning){NavigationStack{BarcodeCamera(completion:{value in scanning=false;code=value;startLookup()},failed:{message in scanning=false;notice=message}).ignoresSafeArea().navigationTitle(diary.t("مسح الباركود","Scan barcode")).toolbar{ToolbarItem(placement:.cancellationAction){Button(diary.t("إغلاق","Close")){scanning=false}}}}}
        }.onAppear{if let initial{selected=initial};if query.isEmpty && !initialQuery.isEmpty {query=initialQuery};refreshHistory();if tab==0 {searchTask=Task{await refreshLocal()}}}
            .task{suggestionFoods=await FoodDatabase.shared.suggestionCandidates(cached:diary.state.products+diary.personalFoods)}
            .onChange(of:diary.state.entries){_,_ in refreshHistory()}
            .onChange(of:diary.state.customFoods){_,_ in refreshHistory()}
            .onChange(of:query){_,value in let submit=suggestedQuery==value;suggestedQuery=nil;resetSearch();searchTask=Task{if submit{await search()}else{await refreshLocal()}}}
            .onChange(of:filter){_,_ in resetSearch();searchTask=Task{await refreshLocal()}}
            .onChange(of:tab){_,value in resetSearch();barcodePhotoTask?.cancel();photoToken=UUID();photo=nil;if value==0 {searchTask=Task{await refreshLocal()}}}
            .onDisappear{searchTask?.cancel();selectionTask?.cancel();historyTask?.cancel();queryToken=UUID();busy=false;pageLoading=false;choosingFood=false;barcodePhotoTask?.cancel();photoToken=UUID()}
            .onChange(of:photo){_,item in readBarcodePhoto(item)}
    }
    private var searchContent:some View {
        VStack(alignment:.leading,spacing:16) {
            HStack(spacing:10) {
                Image(systemName:"magnifyingglass").foregroundStyle(Theme.muted)
                TextField(diary.t("اسم الطعام أو المنتج","Food or product name"),text:$query).submitLabel(.search).autocorrectionDisabled().onSubmit{startSearch()}
                if !query.isEmpty {Button {query=""} label:{Image(systemName:"xmark.circle.fill")}.accessibilityLabel(diary.t("مسح البحث","Clear search"))}
                if filter==0 {Button(diary.t("بحث","Search")){startSearch()}.disabled(term.isEmpty || busy || pageLoading || choosingFood)}
            }.padding(14).background(Theme.card,in:RoundedRectangle(cornerRadius:16))
            Picker(diary.t("قائمة الأطعمة","Food list"),selection:$filter) {
                Text(diary.t("الكل","All")).tag(0);Text(diary.t("الأخيرة","Recent")).tag(1);Text(diary.t("المتكررة","Frequent")).tag(2);if !productSelection {Text(diary.t("أطعمتي","My foods")).tag(3)}
            }.pickerStyle(.segmented).disabled(choosingFood)
            HStack(spacing:12) {
                Button {tab=1} label:{Label(diary.t("باركود","Barcode"),systemImage:"barcode.viewfinder").frame(maxWidth:.infinity).padding(.vertical,10)}
                if !productSelection {Button {tab=2} label:{Label(diary.t("صورة الوجبة","Meal photo"),systemImage:"camera").frame(maxWidth:.infinity).padding(.vertical,10)}}
            }.buttonStyle(.bordered)
            if filter==0 && term.isEmpty && !recentFoods.isEmpty {recent(diary.t("الأخيرة","Recent foods"),Array(recentFoods.prefix(8)),reverse:false)}
            if filter==0 {
                if !suggestions.isEmpty {VStack(alignment:.leading,spacing:10){Text(diary.t(term.isEmpty ? "ابدأ البحث":"اقتراحات البحث",term.isEmpty ? "Start searching":"Suggested searches")).font(.subheadline.bold());ForEach(suggestions){suggestion in Button {submitSuggestion(suggestion.query)} label:{HStack{Image(systemName:suggestion.kind == .history ? "clock":"magnifyingglass");Text(suggestion.label).lineLimit(2).multilineTextAlignment(.leading);Spacer();Image(systemName:"arrow.up.left").font(.caption)}}.buttonStyle(.plain).disabled(choosingFood)}}.luqmaCard()}
                if !term.isEmpty {Text(diary.t("الأطعمة المحفوظة • بحث لعرض منتجات Open Food Facts","Saved foods • Search for Open Food Facts products")).font(.caption).foregroundStyle(Theme.muted)}
            }
        }
    }
    private var barcodeContent:some View {
        VStack(alignment:.leading,spacing:16) {
            Button{Task{let token=queryToken;let allowed=await CameraAccess.request();guard tab==1,token==queryToken,!Task.isCancelled else{return};if allowed{scanning=true}else{notice=diary.t("اسمح للُقمة باستخدام الكاميرا من إعدادات الآيفون.","Allow Luqma camera access in iPhone Settings.")}}}label:{Label(diary.t("مسح الباركود","Scan barcode"),systemImage:"barcode.viewfinder").frame(maxWidth:.infinity).padding(20)}.buttonStyle(.borderedProminent)
            PhotosPicker(selection:$photo,matching:.images){Label(diary.t("قراءة باركود من صورة","Read a barcode photo"),systemImage:"photo")}
            DisclosureGroup(diary.t("كتابة رقم الباركود","Enter barcode number")) {
                HStack{TextField(diary.t("رقم الباركود","Barcode number"),text:$code).keyboardType(.numberPad).environment(\.layoutDirection,.leftToRight);Button(diary.t("بحث","Look up")){startLookup()}.disabled(busy || code.isEmpty)}.padding(.vertical,12)
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
                results=results.map{$0.id==food.id ? resolved:$0}
                choosingFood=false;diary.remember(resolved,barcode:fromBarcode);selected=resolved
            } catch {
                guard !Task.isCancelled,token==queryToken,selectionQuery==query,selectionTab==tab else{return}
                choosingFood=false
                notice=(error as? AppError)?.message(diary.language) ?? diary.t("تعذّر جلب تفاصيل المنتج ووحدته. أعد المحاولة عند توفر الإنترنت أو أضفه من الملصق.","Could not load the product details and unit. Retry when connected, or add it from the label.")
            }
        }
    }
    private func recent(_ title:String,_ foods:[Food],reverse:Bool=true) -> some View {let available=foods.filter{FoodSearch.availableForAdding($0) && (!productSelection || FoodSearch.isCatalogFood($0))};return VStack(alignment:.leading,spacing:4){Text(title).font(.headline);ForEach(Array((reverse ? Array(available.reversed()):available).prefix(8))){food in FoodRow(food:food){select(food)}.disabled(choosingFood)}}.luqmaCard()}
    private func resetSearch() {
        searchTask?.cancel();selectionTask?.cancel();queryToken=UUID();busy=false;pageLoading=false;choosingFood=false;nextPage=nil;reachedSourceWindow=false
        localResults=[];remoteResults=[];results=[];notice=nil
    }
    private func refreshHistory() {
        historyTask?.cancel();let snapshot=diary.state
        historyTask=Task{let lists=await FoodDatabase.shared.historyLists(snapshot);guard !Task.isCancelled else{return};recentFoods=lists.recent;frequentFoods=lists.frequent;savedFoods=lists.personal}
    }
    private func startSearch(){guard !choosingFood else{return};searchTask?.cancel();searchTask=Task{await search()}}
    private func submitSuggestion(_ value:String){if query==value{startSearch()}else{suggestedQuery=value;query=value}}
    private func startMore(){guard tab==0,!busy,!pageLoading,!choosingFood,nextPage != nil else{return};searchTask?.cancel();searchTask=Task{await more()}}
    private func startLookup(){guard tab==1 else{return};barcodePhotoTask?.cancel();photoToken=UUID();searchTask?.cancel();searchTask=Task{await lookup()}}
    private func readBarcodePhoto(_ item:PhotosPickerItem?) {
        barcodePhotoTask?.cancel();let token=UUID();photoToken=token
        guard tab==1,let item else{return}
        searchTask?.cancel();queryToken=UUID();busy=false;pageLoading=false
        barcodePhotoTask=Task {
            do {
                let data=try await item.loadTransferable(type:Data.self)
                guard !Task.isCancelled,token==photoToken,tab==1 else{return}
                let value:String?
                if let data {value=try await CameraAccess.barcode(in:data)} else {value=nil}
                guard !Task.isCancelled,token==photoToken,tab==1 else{return}
                if let value {code=value;startLookup()}
                else {notice=diary.t("لم نعثر على باركود واضح في الصورة.","No readable barcode was found in the photo.")}
            } catch {
                guard !Task.isCancelled,token==photoToken,tab==1 else{return};diary.report(error)
            }
        }
    }
    private func mergeResults(_ token:UUID) async -> Bool {
        let found=await FoodDatabase.shared.combined(term,local:localResults,remote:remoteResults)
        guard !Task.isCancelled,token==queryToken else{return false}
        results=found;return true
    }
    private func refreshLocal() async {
        let token=queryToken,value=term
        guard tab==0,filter==0,!value.isEmpty else{return}
        do{try await Task.sleep(nanoseconds:250_000_000)}catch{return}
        let found=await FoodDatabase.shared.local(value,cached:diary.state.products+diary.personalFoods)
        guard !Task.isCancelled,token==queryToken,tab==0 else{return}
        localResults=found;_ = await mergeResults(token)
    }
    private func search() async {
        let value=term;guard !Task.isCancelled,tab==0,filter==0,!value.isEmpty else{return}
        let token=UUID();queryToken=token;busy=true;pageLoading=false;notice=nil;nextPage=nil;reachedSourceWindow=false;remoteResults=[]
        let found=await FoodDatabase.shared.local(value,cached:diary.state.products+diary.personalFoods)
        guard !Task.isCancelled,token==queryToken else{return};localResults=found
        guard await mergeResults(token) else{return}
        do {
            let page=try await FoodDatabase.shared.remote(value)
            guard !Task.isCancelled,token==queryToken else{return}
            remoteResults=page.foods;nextPage=page.nextPage;reachedSourceWindow=page.reachedSourceWindow
            guard await mergeResults(token) else{return}
            if results.isEmpty {notice=diary.t("لم نجد طعامًا مطابقًا في النتائج الحالية. جرّب كلمة أخرى أو أضفه يدويًا.","No matching food in the current results. Try another word or add it manually.")}
        } catch {
            guard !Task.isCancelled,token==queryToken else{return}
            notice=(error as? AppError)?.message(diary.language) ?? diary.t("البحث عبر الإنترنت غير متاح. نعرض الأطعمة المحفوظة.","Online search is unavailable. Saved foods are shown.")
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
            notice=(error as? AppError)?.message(diary.language) ?? diary.t("تعذّر تحميل المزيد. حاول مرة أخرى.","Could not load more. Try again.")
        }
        if token==queryToken {pageLoading=false}
    }
    private func lookup() async {
        guard !Task.isCancelled,tab==1 else{return}
        let token=UUID();queryToken=token;busy=true;notice=nil
        do{let food=try await FoodDatabase.shared.barcode(code,cached:diary.state.products);guard !Task.isCancelled,token==queryToken else{return};if let food{diary.remember(food,barcode:true);selected=food}else{notice=diary.t("الباركود مقروء لكن المنتج غير مسجل في Open Food Facts. أضفه من الملصق.","The barcode was read, but the product is absent from Open Food Facts. Add its label nutrition.")}}
        catch{guard !Task.isCancelled,token==queryToken else{return};notice=(error as? AppError)?.message(diary.language) ?? diary.t("تعذّر الاتصال بقاعدة المنتجات. أعد المحاولة عند توفر الإنترنت.","The database could not be reached. Retry when connected.")}
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
                if manual {TextField(diary.t("اسم الطعام","Food name"),text:$name)}else{Text(name).font(.headline);if let brand=food.brand{Text(brand).font(.caption).foregroundStyle(Theme.muted)}}
                Picker(diary.t("الوجبة","Meal"),selection:$meal){ForEach(Meal.allCases){Text($0.label(diary.language)).tag($0)}}
            }
            Section(diary.t("الكمية","Amount")) {
                Picker(diary.t("الوحدة","Unit"),selection:$unit){ForEach(manual ? [.serving,.g,.ml]:food.additionUnits,id:\.self){Text($0.label(diary.language)).tag($0)}}.pickerStyle(.segmented)
                if unit == .serving && !food.servingChoices.isEmpty {
                    Picker(diary.t("حجم الحصة","Serving size"),selection:$servingID){
                        if food.servingNutrition != nil {Text(food.serving ?? diary.t("الحصة المحفوظة","Saved serving")).tag("")}
                        ForEach(food.servingChoices){choice in Text("\(choice.label) · \(decimal(choice.grams)) \(diary.t("جم","g"))").tag(choice.id)}
                    }
                }
                if unit == .serving && !food.portionChoices.isEmpty {
                    Picker(diary.t("حجم الحصة","Serving size"),selection:$portionID){ForEach(food.portionChoices){choice in Text(choice.label).tag(choice.id)}}
                }
                if unit == .serving && needsServingSize {
                    input(diary.t(food.unit == .ml ? "حجم الحصة (مل)":"وزن الحصة (جم)",food.unit == .ml ? "Serving volume (ml)":"Serving weight (g)"),$servingWeight)
                    Text(diary.t("لا يحدد المصدر حجم الحصة. أدخله من الملصق أو اختر وحدة المنتج.","The source has no serving size. Enter it from the label, or choose the product's unit.")).font(.caption).foregroundStyle(Theme.muted)
                }
                if let serving=portionFood.serving,unit == .serving{Text(serving).font(.footnote).foregroundStyle(.secondary)}
                input(diary.t(unit == .serving ? "عدد الحصص":"الكمية المستهلكة",unit == .serving ? "Number of servings":"Consumed amount"),$amount)
                if base != nil {NutritionView(value:total,large:true)}else{Text(diary.t("حدد الحصة لعرض مجموع التغذية","Set the serving to see nutrition totals")).font(.subheadline).foregroundStyle(Theme.muted)}
            }
            Section{
                if manual {Text(referenceTitle).font(.headline);referenceInputs}
                else {DisclosureGroup(referenceTitle,isExpanded:$editingNutrition){referenceInputs}}
            }
            Section{Button(diary.t("إضافة الطعام","Add food")){save()}.disabled(base==nil || name.trimmingCharacters(in:.whitespaces).isEmpty || (quantity ?? 0)<=0 || (quantity ?? 0)>10000)}
        }.appBackground().navigationTitle(diary.t("كمية الطعام","Food portion"))
            .toolbar{ToolbarItem(placement:.cancellationAction){Button(diary.t("إلغاء","Cancel")){dismiss()}}}
        }.onAppear{if let initialMeal{meal=initialMeal};unit=food.defaultAdditionUnit;name=food.label(diary.language);amount="1";portionID=food.selectedPortionID ?? food.portionChoices.first?.id ?? "";if food.servingNutrition==nil{servingID=food.servingChoices.first?.id ?? ""};loadBase();editingNutrition=manual || (portionFood.per100==nil && portionFood.servingNutrition==nil)}
            .onChange(of:unit){_,_ in amount=unit == .serving ? "1":"100";if !manual{loadBase();if portionFood.values(for:unit)==nil && !needsServingSize{editingNutrition=true}}}
            .onChange(of:servingID){_,_ in if !manual{loadBase()}}
            .onChange(of:portionID){_,_ in if !manual{loadBase();editingNutrition=portionFood.values(for:unit)==nil}}
            .onChange(of:servingWeight){_,_ in if !manual && unit == .serving{loadBase()}}
    }
    private var referenceTitle:String {unit == .serving ? diary.t("القيم للحصة الواحدة","Values per serving"):diary.t("القيم لكل ١٠٠","Values per 100")+" "+unit.label(diary.language)}
    private var referenceInputs:some View {Group{
        input(diary.t("السعرات","Calories"),$kcal);input(diary.t("البروتين","Protein"),$protein);input(diary.t("الكارب","Carbs"),$carbs);input(diary.t("الدهون","Fat"),$fat)
        if !manual,portionFood.values(for:unit)==nil && !needsServingSize {Notice(text:diary.t("المنتج ينقصه بيانات؛ أكملها من الملصق قبل الإضافة.","Nutrition is incomplete. Fill in the label values before adding."))}
    }}
    private func input(_ label:String,_ text:Binding<String>) -> some View {HStack{Text(label);Spacer();TextField(label,text:text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width:120)}}
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
