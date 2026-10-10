import SwiftUI

struct KitchenView:View {
    @EnvironmentObject var diary:DiaryStore
    @State private var filter="all"
    @State private var query=""
    @State private var creating=false
    @State private var editing:Recipe?
    @State private var selected:Food?
    @State private var deleting:Recipe?
    private var recipes:[Recipe]{
        let words=FoodSearch.normalized(query).split(separator:" ")
        return diary.state.recipes.filter{recipe in
            let name=FoodSearch.normalized(recipe.name)
            return (filter=="all" || recipe.type==filter) && words.allSatisfy{name.contains(String($0))}
        }
    }
    var body:some View {
        ScrollView{VStack(alignment:.leading,spacing:18){
            Button{creating=true}label:{Label(diary.t("حفظ وصفة أو وجبة","Save a recipe or meal"),systemImage:"plus").frame(maxWidth:.infinity).padding(10)}.buttonStyle(.borderedProminent)
            Picker(diary.t("عرض","Show"),selection:$filter){Text(diary.t("كل المحفوظات","All saved items")).tag("all");Text(diary.t("الوصفات","Recipes")).tag("recipe");Text(diary.t("الوجبات","Meals")).tag("meal");Text(diary.t("تحضير الوجبات","Meal prep")).tag("prep")}.pickerStyle(.menu)
            if diary.state.recipes.isEmpty{ContentUnavailableView(diary.t("مطبخك يبدأ هنا","Your kitchen starts here"),systemImage:"fork.knife",description:Text(diary.t("اجمع المكونات واحسب الحصة أو وزن الوجبة بعد الطبخ.","Combine ingredients and calculate servings or final cooked weight.")))}
            else if recipes.isEmpty{ContentUnavailableView(diary.t("لا توجد نتائج","No results"),systemImage:"magnifyingglass",description:Text(diary.t("جرّب اسمًا آخر أو غيّر نوع المحفوظات.","Try another name or change the saved-item type.")))}
            ForEach(recipes){r in VStack(alignment:.leading,spacing:14){
                HStack{Text(r.name).font(.title3.bold());Spacer();Menu{Button(diary.t("تعديل","Edit")){editing=r};Button(diary.t("حذف","Delete"),role:.destructive){deleting=r}}label:{Image(systemName:"ellipsis").frame(minWidth:44,minHeight:44)}.accessibilityLabel(diary.t("خيارات ","Options for ")+r.name)}
                Text("\(decimal(r.portions)) "+diary.t("حصص","servings")+" · \(decimal(r.total.kcal/r.portions,0)) "+diary.t("سعرة للحصة","kcal per serving")).foregroundStyle(Theme.muted).font(.subheadline)
                HStack{Button(diary.t("إضافة حصة","Log a serving")){select(r,false)}.buttonStyle(.bordered);if r.cookedWeight != nil{Button(diary.t("بالجرام","By weight")){select(r,true)}.buttonStyle(.bordered)}}
            }.luqmaCard()}
        }.padding(20)}.appBackground().navigationTitle(diary.t("مطبخي","My kitchen"))
            .searchable(text:$query,prompt:diary.t("ابحث في وصفاتك ووجباتك","Search your recipes and meals"))
            .sheet(isPresented:$creating){RecipeEditor(recipe:Recipe(id:UUID(),name:"",type:"recipe",ingredients:[],portions:1,cookedWeight:nil,notes:""))}
            .sheet(item:$editing){RecipeEditor(recipe:$0)}
            .sheet(item:$selected){f in FoodPortionView(food:f){food,amount,unit,meal in do{return diary.add([try DiaryEntry(food:food,amount:amount,unit:unit,meal:meal,day:DayKey.today,language:diary.language)])}catch{diary.report(error);return false}}}
            .confirmationDialog(diary.t("حذف الوصفة؟","Delete recipe?"),isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}}),titleVisibility:.visible){Button(diary.t("حذف","Delete"),role:.destructive){if let r=deleting{diary.removeRecipe(r.id)};deleting=nil}}
    }
    private func select(_ r:Recipe,_ weighted:Bool){do{selected=try r.food(byWeight:weighted)}catch{diary.report(error)}}
}
struct RecipeEditor:View {
    @State var recipe:Recipe
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dismiss) var dismiss
    @State private var adding=false
    @State private var byWeight=false
    @State private var showingNotes=false
    var body:some View {
        NavigationStack{Form{
            Section{TextField(diary.t("اسم الوصفة أو الوجبة","Recipe or meal name"),text:$recipe.name);Picker(diary.t("النوع","Type"),selection:$recipe.type){Text(diary.t("وصفة","Recipe")).tag("recipe");Text(diary.t("وجبة محفوظة","Saved meal")).tag("meal");Text(diary.t("تحضير وجبات","Meal prep")).tag("prep")}}
            Section(diary.t("المكونات","Ingredients")){
                ForEach(recipe.ingredients){i in VStack(alignment:.leading){Text(i.name);Text("\(decimal(i.amount)) \(i.unit.label(diary.language)) · \(decimal(i.kcal,0)) kcal").font(.caption).foregroundStyle(.secondary)}}.onDelete{recipe.ingredients.remove(atOffsets:$0)}
                Button{adding=true}label:{Label(diary.t("إضافة مكوّن","Add ingredient"),systemImage:"plus")}.disabled(recipe.ingredients.count>=80)
            }
            Section(diary.t("الحصص والوزن","Servings and weight")){
                NumericInput(title:diary.t("عدد الحصص","Number of servings"),value:$recipe.portions)
                Toggle(diary.t("حساب بالوزن بعد الطبخ","Use final cooked weight"),isOn:$byWeight)
                if byWeight{NumericInput(title:diary.t("الوزن بعد الطبخ","Cooked weight"),value:Binding(get:{recipe.cookedWeight ?? 0},set:{recipe.cookedWeight=$0}),suffix:diary.t("جم","g"));Notice(text:diary.t("أدخل الوزن النهائي لحساب أي كمية بالجرام. الماء يغيّر الوزن دون تغيير مجموع السعرات.","Enter the final weight to calculate any gram portion. Water changes weight without changing total calories."))}
            }
            if !recipe.ingredients.isEmpty{Section(diary.t("لكل حصة","Per serving")){NutritionView(value:recipe.total.scaled(1/max(recipe.portions,0.001)))};if byWeight,let w=recipe.cookedWeight,w>0{Section(diary.t("لكل ١٠٠ جم بعد الطبخ","Per 100 g cooked")){NutritionView(value:recipe.total.scaled(100/w))}}}
            Section{DisclosureGroup(diary.t("ملاحظات اختيارية","Optional notes"),isExpanded:$showingNotes){TextField(diary.t("ملاحظاتك","Your notes"),text:$recipe.notes,axis:.vertical).lineLimit(2...5)}}
        }.appBackground().navigationTitle(diary.t("حفظ في مطبخي","Save to kitchen"))
            .toolbar{ToolbarItem(placement:.cancellationAction){Button(diary.t("إلغاء","Cancel")){dismiss()}};ToolbarItem(placement:.confirmationAction){Button(diary.t("حفظ","Save")){if !byWeight{recipe.cookedWeight=nil};if diary.saveRecipe(recipe){dismiss()}}.disabled(recipe.name.isEmpty || recipe.ingredients.isEmpty)}}
            .sheet(isPresented:$adding){FoodAddView{f,a,u,_ in do{let n=try f.total(a,unit:u);recipe.ingredients.append(Ingredient(id:UUID(),name:f.label(diary.language),amount:a,unit:u,kcal:n.kcal,protein:n.protein,carbs:n.carbs,fat:n.fat));return true}catch{diary.report(error);return false}}}
        }.onAppear{byWeight=recipe.cookedWeight != nil;showingNotes = !recipe.notes.isEmpty}
    }
}
