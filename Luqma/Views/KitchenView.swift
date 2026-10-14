import SwiftUI

struct KitchenView:View {
    @EnvironmentObject var diary:DiaryStore
    @State private var filter="all"
    @State private var query=""
    @State private var creating=false
    @State private var importingRecipe=false
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
        ScrollView{VStack(alignment:.leading,spacing:24){
            LuqmaPageHeader(title:diary.t("مطبخي","My kitchen"),subtitle:diary.t("وجبات تحبها، في مكان واحد","Meals you love, in one place"),symbol:"fork.knife")
            HStack(spacing:12){Image(systemName:"magnifyingglass").font(.system(size:20)).foregroundStyle(Theme.muted);TextField(diary.t("ابحث في محفوظاتك","Search your saved items"),text:$query).submitLabel(.search);if !query.isEmpty{Button{query=""}label:{Image(systemName:"xmark.circle.fill").foregroundStyle(Theme.muted).frame(minWidth:32,minHeight:32)}.accessibilityLabel(diary.t("مسح البحث","Clear search"))}}.padding(.horizontal,16).frame(minHeight:56).background(Theme.card,in:RoundedRectangle(cornerRadius:16))
            ScrollView(.horizontal,showsIndicators:false){HStack(spacing:8){
                LuqmaPill(title:diary.t("الكل","All"),selected:filter=="all"){filter="all"}
                LuqmaPill(title:diary.t("الوصفات","Recipes"),selected:filter=="recipe"){filter="recipe"}
                LuqmaPill(title:diary.t("الوجبات","Meals"),selected:filter=="meal"){filter="meal"}
                LuqmaPill(title:diary.t("التحضير","Meal prep"),selected:filter=="prep"){filter="prep"}
            }}
            Button{creating=true}label:{Label(diary.t("حفظ وصفة أو وجبة","Save a recipe or meal"),systemImage:"plus")}.buttonStyle(LuqmaPrimaryButtonStyle())
            Button{importingRecipe=true}label:{Label(diary.t("استيراد وصفة من رابط","Import a recipe from a link"),systemImage:"link")}.buttonStyle(LuqmaSecondaryButtonStyle())
            LuqmaSectionHeader(title:diary.t("محفوظاتك","Your saved items"),detail:"\(recipes.count)")
            if diary.state.recipes.isEmpty{VStack(spacing:18){Image(systemName:"book.closed").font(.system(size:44,weight:.light)).foregroundStyle(Theme.accent);Text(diary.t("مطبخك يبدأ هنا","Your kitchen starts here")).luqmaFont(size:18,weight:.bold,relativeTo:.title3);Text(diary.t("اجمع المكونات واحسب الحصص، ثم أضف وجبتك بلمسة.","Combine ingredients, calculate servings, and log your meal in a tap.")).luqmaFont(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)}.frame(maxWidth:.infinity).padding(.vertical,22).luqmaCard()}
            else if recipes.isEmpty{ContentUnavailableView(diary.t("لا توجد نتائج","No results"),systemImage:"magnifyingglass",description:Text(diary.t("جرّب اسمًا آخر أو غيّر نوع المحفوظات.","Try another name or change the saved-item type.")))}
            ForEach(recipes){r in recipeCard(r)}
        }.padding(24).padding(.bottom,10)}.scrollDismissesKeyboard(.interactively).appBackground().navigationTitle(diary.t("مطبخي","My kitchen"))
            .toolbar(.hidden,for:.navigationBar)
            .sheet(isPresented:$creating){RecipeEditor(recipe:Recipe(id:UUID(),name:"",type:"recipe",ingredients:[],portions:1,cookedWeight:nil,notes:""))}
            .sheet(isPresented:$importingRecipe){RecipeImportView()}
            .sheet(item:$editing){RecipeEditor(recipe:$0)}
            .sheet(item:$selected){f in FoodPortionView(food:f){food,amount,unit,meal in do{return diary.add([try DiaryEntry(food:food,amount:amount,unit:unit,meal:meal,day:DayKey.today,language:diary.language)],foods:[food])}catch{diary.report(error);return false}}}
            .confirmationDialog(diary.t("حذف الوصفة؟","Delete recipe?"),isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}}),titleVisibility:.visible){Button(diary.t("حذف","Delete"),role:.destructive){if let r=deleting{diary.removeRecipe(r.id)};deleting=nil}}
    }
    private func recipeCard(_ recipe:Recipe)->some View {
        VStack(alignment:.leading,spacing:16){
            HStack(alignment:.top,spacing:13){
                Image(systemName:recipe.type == "prep" ? "takeoutbag.and.cup.and.straw":recipe.type == "meal" ? "fork.knife":"book.closed").font(.system(size:24)).foregroundStyle(Theme.accent).frame(width:56,height:56).background(Theme.surface,in:RoundedRectangle(cornerRadius:16)).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:5){Text(DisplayFormat.westernDigits(recipe.name)).luqmaFont(size:17,weight:.bold,relativeTo:.headline).fixedSize(horizontal:false,vertical:true);Text(recipeKind(recipe.type)).luqmaFont(.caption).foregroundStyle(Theme.muted)}
                Spacer(minLength:0)
                Menu{Button(diary.t("تعديل","Edit")){editing=recipe};Button(diary.t("حذف","Delete"),role:.destructive){deleting=recipe}}label:{Image(systemName:"ellipsis").font(.system(size:20)).foregroundStyle(Theme.muted).frame(minWidth:44,minHeight:44)}.accessibilityLabel(diary.t("خيارات ","Options for ")+recipe.name)
            }
            HStack(spacing:16){
                Label("\(decimal(recipe.total.kcal/max(recipe.portions,0.001),0)) "+diary.t("سعرة","kcal"),systemImage:"flame").foregroundStyle(Theme.accent)
                Label("\(decimal(recipe.portions)) "+diary.t("حصص","servings"),systemImage:"square.stack").foregroundStyle(Theme.muted)
            }.luqmaFont(size:13,weight:.medium,relativeTo:.caption)
            let perServing=recipe.total.scaled(1/max(recipe.portions,0.001))
            HStack(spacing:12){
                recipeMacro(diary.t("بروتين","Protein"),perServing.protein)
                recipeMacro(diary.t("كارب","Carbs"),perServing.carbs)
                recipeMacro(diary.t("دهون","Fat"),perServing.fat)
            }.padding(12).background(Theme.surface,in:RoundedRectangle(cornerRadius:12))
            HStack(spacing:10){
                Button{select(recipe,false)}label:{Label(diary.t("إضافة حصة","Log serving"),systemImage:"plus")}.buttonStyle(LuqmaPrimaryButtonStyle())
                if recipe.cookedWeight != nil{Button{select(recipe,true)}label:{Text(diary.t("بالجرام","By weight"))}.buttonStyle(LuqmaSecondaryButtonStyle())}
            }
        }.luqmaCard()
    }
    private func recipeMacro(_ title:String,_ value:Double)->some View {
        VStack(alignment:.leading,spacing:4){Text(title).luqmaFont(.caption).foregroundStyle(Theme.muted);Text(decimal(value)+" "+diary.t("جم","g")).luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline).monospacedDigit()}.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func recipeKind(_ type:String)->String {switch type{case "meal":return diary.t("وجبة محفوظة","Saved meal");case "prep":return diary.t("تحضير وجبات","Meal prep");default:return diary.t("وصفة","Recipe")}}
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
            Section{TextField(diary.t("اسم الوصفة أو الوجبة","Recipe or meal name"),text:$recipe.name);Picker(diary.t("النوع","Type"),selection:$recipe.type){Text(diary.t("وصفة","Recipe")).tag("recipe");Text(diary.t("وجبة محفوظة","Saved meal")).tag("meal");Text(diary.t("تحضير وجبات","Meal prep")).tag("prep")}}.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            Section(diary.t("المكونات","Ingredients")){
                ForEach(recipe.ingredients){i in HStack(spacing:12){Image(systemName:"fork.knife").font(.system(size:16)).foregroundStyle(Theme.accent).frame(width:36,height:36).background(Theme.surface,in:RoundedRectangle(cornerRadius:10)).accessibilityHidden(true);VStack(alignment:.leading,spacing:5){Text(DisplayFormat.westernDigits(i.name)).luqmaFont(size:15,weight:.semibold,relativeTo:.subheadline);Text("\(decimal(i.amount)) \(DisplayFormat.westernDigits(recipe.importInfo?.ingredientUnitLabels[i.id.uuidString] ?? i.unit.label(diary.language))) · \(decimal(i.kcal,0)) \(diary.t("سعرة","kcal"))").luqmaFont(.caption).foregroundStyle(Theme.muted)}}.padding(.vertical,4)}.onDelete{indices in
                    recipe.ingredients.remove(atOffsets:indices)
                    let remaining=Set(recipe.ingredients.map{$0.id.uuidString})
                    recipe.importInfo?.ingredientUnitLabels=recipe.importInfo?.ingredientUnitLabels.filter{remaining.contains($0.key)} ?? [:]
                }
                Button{adding=true}label:{Label(diary.t("إضافة مكوّن","Add ingredient"),systemImage:"plus")}.disabled(recipe.ingredients.count>=80)
            }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            Section(diary.t("الحصص والوزن","Servings and weight")){
                NumericInput(title:diary.t("عدد الحصص","Number of servings"),value:$recipe.portions)
                Toggle(diary.t("حساب بالوزن بعد الطبخ","Use final cooked weight"),isOn:$byWeight)
                if byWeight{NumericInput(title:diary.t("الوزن بعد الطبخ","Cooked weight"),value:Binding(get:{recipe.cookedWeight ?? 0},set:{recipe.cookedWeight=$0}),suffix:diary.t("جم","g"));Notice(text:diary.t("أدخل الوزن النهائي لحساب أي كمية بالجرام. الماء يغيّر الوزن دون تغيير مجموع السعرات.","Enter the final weight to calculate any gram portion. Water changes weight without changing total calories."))}
            }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            if !recipe.ingredients.isEmpty{Section(diary.t("لكل حصة","Per serving")){NutritionView(value:recipe.total.scaled(1/max(recipe.portions,0.001)))}.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke);if byWeight,let w=recipe.cookedWeight,w>0{Section(diary.t("لكل ١٠٠ جم بعد الطبخ","Per 100 g cooked")){NutritionView(value:recipe.total.scaled(100/w))}.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)}}
            Section{DisclosureGroup(diary.t("ملاحظات اختيارية","Optional notes"),isExpanded:$showingNotes){TextField(diary.t("ملاحظاتك","Your notes"),text:$recipe.notes,axis:.vertical).lineLimit(2...5)}}.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            if let info=recipe.importInfo{
                Section(diary.t("خطوات التحضير","Preparation steps")){ForEach(Array(info.steps.enumerated()),id:\.offset){index,step in Text("\(index+1). "+DisplayFormat.westernDigits(step))}}.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
                Section(diary.t("المصدر والتقدير","Source and estimate")){
                    if let source=info.sourceURL,let url=URL(string:source){Link(diary.t("فتح الوصفة الأصلية","Open original recipe"),destination:url)}
                    if info.nutritionIsEstimated{Notice(text:diary.t("القيم الغذائية تقديرية؛ راجع المقادير وعدد الحصص.","Nutrition is estimated; review quantities and servings."))}
                    ForEach(info.assumptions,id:\.self){Notice(text:$0)}
                }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            }
        }.sandowForm().navigationTitle(diary.t("حفظ في مطبخي","Save to kitchen")).navigationBarTitleDisplayMode(.inline)
            .toolbar{ToolbarItem(placement:.cancellationAction){Button(diary.t("إلغاء","Cancel")){dismiss()}};ToolbarItem(placement:.confirmationAction){Button(diary.t("حفظ","Save")){if !byWeight{recipe.cookedWeight=nil};if diary.saveRecipe(recipe){dismiss()}}.disabled(recipe.name.isEmpty || recipe.ingredients.isEmpty)}}
            .sheet(isPresented:$adding){FoodAddView{f,a,u,_ in do{let n=try f.total(a,unit:u);recipe.ingredients.append(Ingredient(id:UUID(),name:f.label(diary.language),amount:a,unit:u,kcal:n.kcal,protein:n.protein,carbs:n.carbs,fat:n.fat))
                if MealPhotoEstimate.isValidPhotoEstimate(f) || f.sourceDescription=="luqma:estimated-components"{let note=diary.t("تحتوي الوصفة على قيم مقدّرة من صورة؛ راجعها قبل الاستخدام.","This recipe includes photo estimates; review them before use.");if !recipe.notes.contains(note){recipe.notes=String((recipe.notes+"\n"+note).trimmingCharacters(in:.whitespacesAndNewlines).prefix(2000))}}
                return true}catch{diary.report(error);return false}}}
        }.onAppear{byWeight=recipe.cookedWeight != nil;showingNotes = !recipe.notes.isEmpty}
    }
}
