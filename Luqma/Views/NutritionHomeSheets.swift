import SwiftUI

private typealias E=NutritionExactTheme

struct NutritionNewMealSheet:View {
    var seed:NutritionHomeCard?
    let day:String
    var onSearch:()->Void
    @EnvironmentObject private var diary:DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name=""
    @State private var kcal=""
    @State private var protein=""
    @State private var carbs=""
    @State private var fat=""
    @State private var meal:Meal = .lunch
    @State private var initialized=false
    @State private var saving=false
    private var nutrition:Nutrition? {
        guard let k=TextSearch.number(kcal),let p=TextSearch.number(protein),let c=TextSearch.number(carbs),let f=TextSearch.number(fat) else{return nil}
        let result=Nutrition(kcal:k,protein:p,carbs:c,fat:f)
        return result.valid ? result:nil
    }
    private var valid:Bool {!name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && name.count<=180 && nutrition != nil && DayKey.valid(day)}
    var body:some View {
        ScrollView{
            VStack(alignment:.leading,spacing:12){
                sheetHeading(diary.t("إضافة وجبة جديدة إلى خانة الوجبات","Add Meal to Meals Section")){dismiss()}
                if seed?.isExample == true {Text(diary.t("مثال من التصميم. أكمل القيم الفعلية؛ لن نحفظ ماكروز مجهولة كأنها صفر.","Design example. Enter actual values; unknown macros are never saved as zero.")).nutritionFont(12).foregroundStyle(E.muted)}
                field(diary.t("اسم الوجبة","Meal name"),text:$name,numeric:false,identifier:"exact.add.name")
                HStack(spacing:8){field(diary.t("السعرات kcal","Calories kcal"),text:$kcal,identifier:"exact.add.kcal");field(diary.t("البروتين جم","Protein g"),text:$protein,identifier:"exact.add.protein")}
                HStack(spacing:8){field(diary.t("الكارب جم","Carbs g"),text:$carbs,identifier:"exact.add.carbs");field(diary.t("الدهون جم","Fat g"),text:$fat,identifier:"exact.add.fat")}
                Picker(diary.t("الوجبة","Meal"),selection:$meal){ForEach(Meal.allCases){Text($0.label(diary.language)).tag($0)}}.pickerStyle(.menu).nutritionFont(12,weight:.bold).tint(E.orange).accessibilityIdentifier("exact.add.meal")
                Text(diary.t("القيم لحصة واحدة. أدخل 0 فقط إذا كانت القيمة صفرًا فعلًا.","Values are for one serving. Enter 0 only when the value is actually zero.")).nutritionFont(10.5).foregroundStyle(E.muted)
                Button(action:save){Text(diary.t("حفظ وإضافة الوجبة","Save & Add Meal")).nutritionFont(12,weight:.bold).frame(maxWidth:.infinity,minHeight:36).nutritionPanel(E.orange,radius:12)}
                    .buttonStyle(NutritionExactPressStyle()).disabled(!valid || saving).opacity(valid ? 1:0.45).accessibilityIdentifier("exact.add.save")
                Button(action:onSearch){Text(diary.t("أو ابحث عن طعام في القاعدة","Or search the food database")).nutritionFont(11.5,weight:.bold).foregroundStyle(E.orangeLink).frame(maxWidth:.infinity,minHeight:44)}.buttonStyle(.plain).accessibilityIdentifier("exact.add.search")
            }.padding(16)
        }.scrollDismissesKeyboard(.interactively).background(E.modal.ignoresSafeArea()).foregroundStyle(.white).tint(E.orange)
            .overlay{RoundedRectangle(cornerRadius:16).strokeBorder(E.header,lineWidth:1).allowsHitTesting(false)}
            .onAppear{guard !initialized else{return};initialized=true;if let seed{name=seed.name(diary.language);kcal=seed.kcal.map{decimal($0,0)} ?? ""}}
    }
    private func save(){
        guard valid,!saving,let nutrition else{return}
        saving=true
        let food=Food(catalogID:"personal:"+UUID().uuidString,name:name.trimmingCharacters(in:.whitespacesAndNewlines),unit:.serving,nutrition:nutrition,serving:diary.t("حصة واحدة","1 serving"),servingNutrition:nutrition,source:"Your food")
        do{
            let entry=try DiaryEntry(food:food,amount:1,unit:.serving,meal:meal,day:day,language:diary.language)
            if diary.add([entry],foods:[food]){dismiss()}else{saving=false}
        }catch{saving=false;diary.report(error)}
    }
    private func field(_ label:String,text:Binding<String>,numeric:Bool=true,identifier:String)->some View {
        TextField(label,text:text,prompt:Text(label).foregroundColor(E.muted)).keyboardType(numeric ? .decimalPad:.default)
            .nutritionFont(12).padding(.horizontal,12).frame(minHeight:36).nutritionPanel(E.background,radius:12)
            .overlay{RoundedRectangle(cornerRadius:12).strokeBorder(E.header)}.accessibilityLabel(label).accessibilityIdentifier(identifier)
    }
}

struct NutritionGoalSheet:View {
    var onFullGoals:()->Void
    @EnvironmentObject private var diary:DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var amount=""
    @State private var initialized=false
    @State private var saved=false
    private var value:Double? {TextSearch.number(amount)}
    private var valid:Bool {value.map{$0.isFinite && (500...10000).contains($0)} ?? false}
    var body:some View {
        ScrollView{VStack(spacing:12){
            sheetHeading(diary.t("تعديل هدف السعرات","Edit Calorie Goal")){dismiss()}
            HStack(alignment:.firstTextBaseline,spacing:4){TextField("",text:$amount).multilineTextAlignment(.center).keyboardType(.decimalPad).nutritionFont(26,weight:.black).foregroundStyle(E.orange).fixedSize(horizontal:false,vertical:true).accessibilityIdentifier("exact.goal.value");Text("kcal").nutritionFont(13).foregroundStyle(.white.opacity(0.8))}.padding(.vertical,4).environment(\.layoutDirection,.leftToRight)
            Slider(value:Binding(get:{guard let value,value.isFinite else{return 1200};return min(4000,max(1200,value))},set:{amount=decimal($0,0)}),in:1200...4000,step:50).tint(E.orange).accessibilityLabel(diary.t("هدف السعرات","Calorie goal")).accessibilityIdentifier("exact.goal.slider")
            if !valid{Text(diary.t("أدخل هدفًا بين 500 و10000 سعرة.","Enter a goal from 500 to 10,000 kcal.")).nutritionFont(11).foregroundStyle(E.notification)}
            Button{
                guard !saved,valid,let value else{return}
                saved=true
                if diary.setGoals(diary.state.goals.settingCalories(value)){dismiss()}else{saved=false}
            }label:{Text(diary.t("تأكيد","Confirm")).nutritionFont(12,weight:.bold).frame(maxWidth:.infinity,minHeight:36).nutritionPanel(E.orange,radius:12)}.buttonStyle(NutritionExactPressStyle()).disabled(!valid || saved).accessibilityIdentifier("exact.goal.save")
            Button(action:onFullGoals){Text(diary.t("إعدادات السعرات والماكروز الكاملة","Full calorie and macro settings")).nutritionFont(11.5,weight:.bold).foregroundStyle(E.orangeLink).frame(minHeight:44)}.buttonStyle(.plain).accessibilityIdentifier("exact.goal.fullSettings")
        }.padding(16)}.scrollDismissesKeyboard(.interactively).background(E.modal.ignoresSafeArea()).foregroundStyle(.white)
            .overlay{RoundedRectangle(cornerRadius:16).strokeBorder(E.header,lineWidth:1).allowsHitTesting(false)}
            .onAppear{if !initialized{initialized=true;amount=decimal(diary.state.goals.kcal,0)}}
    }
}

struct NutritionMealDetailSheet:View {
    let card:NutritionHomeCard
    let day:String
    var onToggle:()->Void
    var onEdit:(DiaryEntry)->Void
    @EnvironmentObject private var diary:DiaryStore
    @Environment(\.dismiss) private var dismiss
    private var recorded:DiaryEntry? {card.matchingEntry(in:diary.state.entries,day:day)}
    var body:some View {
        ScrollView{VStack(alignment:.leading,spacing:12){
            sheetHeading(card.name(diary.language),size:15,circularClose:true){dismiss()}
            Text(diary.t("صورة توضيحية بديلة من أصول لقمة؛ ليست صورة الوجبة المسجّلة.","Substitute Luqma illustration; not a photograph of the logged meal.")).nutritionFont(12).foregroundStyle(E.muted)
            if let total=card.nutrition {
                HStack(spacing:12){detailMetric("Flame",value:total.kcal,unit:"kcal");detailMetric("Utensils",value:total.protein,unit:diary.t("جم بروتين","g protein"))}
                HStack(spacing:12){detailMetric("Zap",value:total.carbs,unit:diary.t("جم كارب","g carbs"));detailMetric("Heart",value:total.fat,unit:diary.t("جم دهون","g fat"))}
            }else{
                Text(diary.t("مثال من المرجع، وليس تحليلًا أو طعامًا محفوظًا. أدخل معلوماته الغذائية الفعلية قبل الإضافة.","A reference example, not an analysis or saved food. Enter its actual nutrition before adding.")).nutritionFont(12).foregroundStyle(E.muted)
            }
            Button(action:onToggle){Text(diary.t(recorded == nil ? "إضافة الوجبة (+)":"إزالة الوجبة",recorded == nil ? "Add Meal (+)":"Remove Meal")).nutritionFont(12,weight:.bold).frame(maxWidth:.infinity,minHeight:36).nutritionPanel(E.orange,radius:12)}.buttonStyle(NutritionExactPressStyle()).accessibilityIdentifier("exact.detail.toggle")
            if let recorded{Button{onEdit(recorded)}label:{Text(diary.t("تعديل الكمية","Edit quantity")).nutritionFont(12,weight:.bold).foregroundStyle(E.orangeLink).frame(maxWidth:.infinity,minHeight:44)}.buttonStyle(.plain).accessibilityIdentifier("exact.detail.edit")}
        }.padding(16)}.background(E.modal.ignoresSafeArea()).foregroundStyle(.white)
            .overlay(alignment:.top){Rectangle().fill(E.header).frame(height:1).allowsHitTesting(false)}
    }
    private func detailMetric(_ icon:String,value:Double,unit:String)->some View {
        HStack(spacing:6){NutritionExactIcon(name:icon,size:14);Text(decimal(value,1)+" "+unit).nutritionFont(12,weight:.semibold).monospacedDigit()}.frame(maxWidth:.infinity,alignment:.leading)
    }
}

private func sheetHeading(_ title:String,size:CGFloat=14,circularClose:Bool=false,close:@escaping ()->Void)->some View {
    HStack(spacing:12){Text(title).nutritionFont(size,weight:.heavy).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading);Button(action:close){NutritionExactIcon(name:"X",size:16,color:circularClose ? .white:E.subtle).frame(width:28,height:28).nutritionPanel(circularClose ? E.background:.clear,radius:14)}.buttonStyle(.plain).accessibilityLabel(Text("إغلاق / Close")).accessibilityIdentifier("exact.sheet.close")}
}
