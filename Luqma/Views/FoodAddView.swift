import SwiftUI
import PhotosUI
import UIKit

typealias FoodCommit = (Food,Double,FoodUnit,Meal) -> Bool
struct FoodAddView:View {
    var initial:Food? = nil
    var onPhotoCommit: (([(Food,Double)],Meal)->Bool)? = nil
    var onCommit:FoodCommit
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dismiss) var dismiss
    @State private var tab=0
    @State private var query=""
    @State private var code=""
    @State private var busy=false
    @State private var scanning=false
    @State private var manual=false
    @State private var results:[Food]=[]
    @State private var selected:Food?
    @State private var notice:String?
    @State private var photo:PhotosPickerItem?
    @State private var queryToken=UUID()
    var body:some View {
        NavigationStack{ScrollView{VStack(alignment:.leading,spacing:20){
            Picker(diary.t("طريقة الإضافة","Add method"),selection:$tab){Text(diary.t("بحث","Search")).tag(0);Text(diary.t("باركود","Barcode")).tag(1);Text(diary.t("صورة","Photo")).tag(2);Text(diary.t("يدوي","Manual")).tag(3)}.pickerStyle(.segmented)
            if tab==0 {searchContent}
            if tab==1 {barcodeContent}
            if tab==2 {PhotoMealView {foods,meal in onPhoto(foods,meal)}}
            if tab==3 {Button{manual=true}label:{Label(diary.t("إدخال بيانات الملصق","Enter label nutrition"),systemImage:"square.and.pencil").frame(maxWidth:.infinity).padding(12)}.buttonStyle(.borderedProminent);Notice(text:diary.t("أدخل السعرات والماكروز لكل ١٠٠ جم أو مل، أو للحصة الواحدة.","Enter calories and macros per 100 g/ml or per serving."))}
            if let notice,tab != 2{Notice(text:notice)}
            if busy{ProgressView().frame(maxWidth:.infinity)}
            if tab==0 || tab==1 {ForEach(results){food in FoodRow(food:food){select(food)}}}
        }.padding(20)}.appBackground().navigationTitle(diary.t("إضافة طعام","Add food"))
            .toolbar{ToolbarItem(placement:.cancellationAction){Button(diary.t("إغلاق","Close")){dismiss()}}}
            .sheet(item:$selected){food in FoodPortionView(food:food,sourceBarcode:tab==1,onCommit:{f,a,u,m in if onCommit(f,a,u,m){dismiss();return true};return false})}
            .sheet(isPresented:$manual){FoodPortionView(food:Food(name:""),manual:true,onCommit:{f,a,u,m in if onCommit(f,a,u,m){dismiss();return true};return false})}
            .sheet(isPresented:$scanning){NavigationStack{BarcodeCamera(completion:{value in scanning=false;code=value;Task{await lookup()}},failed:{message in scanning=false;notice=message}).ignoresSafeArea().navigationTitle(diary.t("مسح الباركود","Scan barcode")).toolbar{ToolbarItem(placement:.cancellationAction){Button(diary.t("إغلاق","Close")){scanning=false}}}}}
        }.onAppear{if let initial{selected=initial}}
            .onChange(of:tab){_,_ in queryToken=UUID();results=[];notice=nil;busy=false}
            .onChange(of:photo){_,item in Task{guard let item else{return};do{if let data=try await item.loadTransferable(type:Data.self),let value=try await CameraAccess.barcode(in:data){code=value;await lookup()}else{notice=diary.t("لم نعثر على باركود واضح في الصورة.","No readable barcode was found in the photo.")}}catch{diary.report(error)}}}
    }
    private var searchContent:some View {VStack(alignment:.leading,spacing:16){
        HStack{TextField(diary.t("اسم الطعام أو المنتج","Food or product name"),text:$query).submitLabel(.search).onSubmit{Task{await search()}};Button(diary.t("بحث","Search")){Task{await search()}}.disabled(query.trimmingCharacters(in:.whitespaces).isEmpty || busy)}.padding(14).background(Theme.card,in:RoundedRectangle(cornerRadius:16))
        if query.isEmpty && !diary.state.searchHistory.isEmpty {recent(diary.t("آخر المنتجات التي بحثت عنها","Recently searched products"),diary.state.searchHistory)}
        Notice(text:diary.t("الأطعمة الأساسية والمنتجات المحفوظة متاحة دون إنترنت. البحث عن منتج جديد يحتاج اتصالًا.","Basic and saved foods work offline. New packaged products require a connection."))
    }}
    private var barcodeContent:some View {VStack(alignment:.leading,spacing:16){
        Button{Task{if await CameraAccess.request(){scanning=true}else{notice=diary.t("اسمح للُقمة باستخدام الكاميرا من إعدادات الآيفون.","Allow Luqma camera access in iPhone Settings.")}}}label:{Label(diary.t("تشغيل الكاميرا","Open camera"),systemImage:"barcode.viewfinder").frame(maxWidth:.infinity).padding(20)}.buttonStyle(.borderedProminent)
        PhotosPicker(selection:$photo,matching:.images){Label(diary.t("قراءة باركود من صورة","Read a barcode photo"),systemImage:"photo")}
        HStack{TextField(diary.t("رقم الباركود","Barcode number"),text:$code).keyboardType(.numberPad).environment(\.layoutDirection,.leftToRight);Button(diary.t("بحث","Look up")){Task{await lookup()}}.disabled(busy || code.isEmpty)}.padding(14).background(Theme.card,in:RoundedRectangle(cornerRadius:16))
        if !diary.state.barcodeHistory.isEmpty{recent(diary.t("آخر المنتجات الممسوحة","Recently scanned products"),diary.state.barcodeHistory)}
    }}
    private func select(_ food:Food){diary.remember(food,barcode:tab==1);selected=food}
    private func recent(_ title:String,_ foods:[Food]) -> some View {VStack(alignment:.leading,spacing:4){Text(title).font(.headline);ForEach(Array(foods.reversed().prefix(8))){food in FoodRow(food:food){select(food)}}}.luqmaCard()}
    @MainActor private func search() async {
        let term=query.trimmingCharacters(in:.whitespacesAndNewlines);guard !term.isEmpty else{return}
        let token=UUID();queryToken=token;busy=true;notice=nil
        let cached=diary.state.products
        let local=await FoodDatabase.shared.local(term,cached:cached);guard token==queryToken else{return};results=local
        do{let remote=try await FoodDatabase.shared.remote(term);guard token==queryToken else{return};var ids=Set(results.map(\.id));results += remote.filter{ids.insert($0.id).inserted};if results.isEmpty{notice=diary.t("لم نجد المنتج. يمكنك إدخال بيانات ملصقه يدويًا.","No product found. You can enter its label manually.")}}
        catch{if token==queryToken{notice=local.isEmpty ? diary.t("تعذّر الاتصال. جرّب طعامًا أساسيًا مثل بيض أو أرز، أو أضف المنتج يدويًا.","Connection failed. Try a basic food like eggs or rice, or enter a product manually."):diary.t("نعرض النتائج المحفوظة؛ البحث الخارجي غير متاح حاليًا.","Showing saved results; online search is currently unavailable.")}}
        if token==queryToken{busy=false}
    }
    @MainActor private func lookup() async {
        let token=UUID();queryToken=token;busy=true;notice=nil;results=[]
        do{let food=try await FoodDatabase.shared.barcode(code,cached:diary.state.products);guard token==queryToken else{return};if let food{diary.remember(food,barcode:true);selected=food}else{notice=diary.t("الباركود مقروء لكن المنتج غير مسجل في Open Food Facts. أضفه من الملصق.","The barcode was read, but the product is absent from Open Food Facts. Add its label nutrition.")}}
        catch{if token==queryToken{notice=(error as? AppError)?.message(diary.language) ?? diary.t("تعذّر الاتصال بقاعدة المنتجات. أعد المحاولة عند توفر الإنترنت.","The database could not be reached. Retry when connected.")}}
        if token==queryToken{busy=false}
    }
    private func onPhoto(_ values:[(Food,Double)],_ meal:Meal) -> Bool {
        guard !values.isEmpty else{return false}
        if let onPhotoCommit {if onPhotoCommit(values,meal){dismiss();return true};return false}
        // Recipe pickers can combine photo components into one ingredient.
        if values.count==1,let first=values.first{return onCommit(first.0,first.1,.g,meal)}
        let combined=values.reduce(Nutrition.zero){$0+($1.0.per100 ?? .zero).scaled($1.1/100)},weight=values.reduce(0){$0+$1.1}
        let name=values.map{$0.0.label(diary.language)}.joined(separator:" + ")
        let food=Food(name:String(name.prefix(180)),nutrition:combined.scaled(100/weight),source:"Photo estimate")
        if onCommit(food,weight,.g,meal){dismiss();return true};return false
    }
}

struct FoodPortionView:View {
    let food:Food
    var manual=false,sourceBarcode=false
    var onCommit:FoodCommit
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dismiss) var dismiss
    @State private var unit:FoodUnit = .g
    @State private var meal:Meal = .breakfast
    @State private var name=""
    @State private var amount="100"
    @State private var kcal=""
    @State private var protein=""
    @State private var carbs=""
    @State private var fat=""
    private var base:Nutrition? {guard let k=TextSearch.number(kcal),let p=TextSearch.number(protein),let c=TextSearch.number(carbs),let f=TextSearch.number(fat) else{return nil};let n=Nutrition(kcal:k,protein:p,carbs:c,fat:f);return n.valid ? n:nil}
    private var quantity:Double? {TextSearch.number(amount)}
    private var total:Nutrition {base?.scaled((quantity ?? 0)/(unit == .serving ? 1:100)) ?? .zero}
    var body:some View {
        NavigationStack{Form{
            Section{TextField(diary.t("اسم الطعام","Food name"),text:$name);Picker(diary.t("الوجبة","Meal"),selection:$meal){ForEach(Meal.allCases){Text($0.label(diary.language)).tag($0)}};Picker(diary.t("الوحدة","Unit"),selection:$unit){ForEach(manual ? FoodUnit.allCases:food.units,id:\.self){Text($0.label(diary.language)).tag($0)}};if let serving=food.serving,unit == .serving{Text(serving).font(.footnote).foregroundStyle(.secondary)}}
            Section(unit == .serving ? diary.t("القيم للحصة الواحدة","Values per serving"):diary.t("القيم لكل ١٠٠","Values per 100")+" "+unit.label(diary.language)){
                input(diary.t("السعرات","Calories"),$kcal);input(diary.t("البروتين","Protein"),$protein);input(diary.t("الكارب","Carbs"),$carbs);input(diary.t("الدهون","Fat"),$fat)
                if !manual{Notice(text:diary.t("هذه بيانات الملصق المرجعية. إجمالي الكمية يتغير مباشرة بالأسفل.","These are reference label values. Your portion totals update immediately below."))}
                if !manual,food.values(for:unit)==nil{Notice(text:diary.t("المنتج ينقصه بيانات؛ أكملها من الملصق قبل الإضافة.","Nutrition is incomplete. Fill in the label values before adding."))}
            }
            Section(diary.t("الكمية المستهلكة","Consumed amount")){TextField(unit.label(diary.language),text:$amount).keyboardType(.decimalPad);NutritionView(value:total,large:true)}
            Section{Button(diary.t("إضافة الطعام","Add food")){save()}.disabled(base==nil || name.trimmingCharacters(in:.whitespaces).isEmpty || (quantity ?? 0)<=0 || (quantity ?? 0)>10000)}
        }.appBackground().navigationTitle(diary.t("كمية الطعام","Food portion"))
            .toolbar{ToolbarItem(placement:.cancellationAction){Button(diary.t("إلغاء","Cancel")){dismiss()}}}
        }.onAppear{unit=food.unit;name=food.label(diary.language);amount=food.unit == .serving ? "1":"100";loadBase()}
            .onChange(of:unit){_,_ in amount=unit == .serving ? "1":"100";if !manual{loadBase()}}
    }
    private func input(_ label:String,_ text:Binding<String>) -> some View {HStack{Text(label);Spacer();TextField(label,text:text).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width:120)}}
    private func loadBase(){let n=food.values(for:unit);kcal=n.map{decimal($0.kcal,2)} ?? "";protein=n.map{decimal($0.protein,3)} ?? "";carbs=n.map{decimal($0.carbs,3)} ?? "";fat=n.map{decimal($0.fat,3)} ?? ""}
    private func save(){guard let base,let quantity else{return};var f=food;f.name=String(name.trimmingCharacters(in:.whitespacesAndNewlines).prefix(180));if diary.language == .en {f.nameEn=f.name};if unit == .serving{f.servingNutrition=base;if manual{f.unit = .serving;f.kcal=base.kcal;f.protein=base.protein;f.carbs=base.carbs;f.fat=base.fat}}else{f.unit=unit;f.kcal=base.kcal;f.protein=base.protein;f.carbs=base.carbs;f.fat=base.fat};if onCommit(f,quantity,unit,meal){diary.remember(f,barcode:sourceBarcode);dismiss()}}
}
