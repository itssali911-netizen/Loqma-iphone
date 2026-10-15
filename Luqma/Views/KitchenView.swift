import SwiftUI

struct KitchenView:View {
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dynamicTypeSize) private var typeSize
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
        let filteredRecipes=recipes
        return ScrollView{LazyVStack(alignment:.leading,spacing:16){
            kitchenHeader
            categoryBar
            HStack(spacing:10){
                kitchenAction(diary.t("وصفة جديدة","New recipe"),symbol:"plus",primary:true){creating=true}
                kitchenAction(diary.t("استيراد رابط","Import link"),symbol:"link",primary:false){importingRecipe=true}
            }
            LuqmaSectionHeader(title:diary.t("محفوظاتك","Your saved items"),detail:decimal(Double(filteredRecipes.count),0))
            if diary.state.recipes.isEmpty{VStack(spacing:12){Image(systemName:"book.closed").font(.system(size:32,weight:.light)).foregroundStyle(Theme.accent);Text(diary.t("مطبخك يبدأ هنا","Your kitchen starts here")).luqmaFont(size:17,weight:.bold,relativeTo:.headline);Text(diary.t("احفظ وصفاتك أو استورد وصفة من رابط، ثم احسب حصصها وأضفها ليومك.","Save your recipes or import one from a link, then calculate servings and log them to your day.")).luqmaFont(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)}.frame(maxWidth:.infinity).padding(.vertical,16).luqmaCard()}
            else if filteredRecipes.isEmpty{ContentUnavailableView(diary.t("لا توجد نتائج","No results"),systemImage:"magnifyingglass",description:Text(diary.t("جرّب اسمًا آخر أو غيّر نوع المحفوظات.","Try another name or change the saved-item type.")))}
            ForEach(filteredRecipes){r in recipeCard(r)}
        }.padding(.horizontal,16).padding(.bottom,24)}.scrollDismissesKeyboard(.interactively).appBackground().navigationTitle(diary.t("مطبخي","My kitchen"))
            .toolbar(.hidden,for:.navigationBar)
            .sheet(isPresented:$creating){RecipeEditor(recipe:Recipe(id:UUID(),name:"",type:"recipe",ingredients:[],portions:1,cookedWeight:nil,notes:""))}
            .sheet(isPresented:$importingRecipe){RecipeImportView()}
            .sheet(item:$editing){RecipeEditor(recipe:$0)}
            .sheet(item:$selected){f in FoodPortionView(food:f){food,amount,unit,meal in do{return diary.add([try DiaryEntry(food:food,amount:amount,unit:unit,meal:meal,day:DayKey.today,language:diary.language)],foods:[food])}catch{diary.report(error);return false}}}
            .confirmationDialog(diary.t("حذف الوصفة؟","Delete recipe?"),isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}}),titleVisibility:.visible){Button(diary.t("حذف","Delete"),role:.destructive){if let r=deleting{diary.removeRecipe(r.id)};deleting=nil}}
    }
    private var kitchenHeader:some View {
        VStack(spacing:16){
            Text(diary.t("مطبخي","My kitchen")).luqmaFont(size:18,weight:.bold,relativeTo:.headline)
                .foregroundStyle(Theme.text).frame(maxWidth:.infinity).accessibilityAddTraits(.isHeader)
            HStack(spacing:10){
                TextField(diary.t("ابحث في محفوظاتك","Search your saved items"),text:$query)
                    .luqmaFont(size:13,relativeTo:.subheadline).submitLabel(.search)
                    .accessibilityLabel(diary.t("البحث في وصفاتك ووجباتك","Search your recipes and meals"))
                if !query.isEmpty{Button{query=""}label:{Image(systemName:"xmark.circle.fill").foregroundStyle(Theme.muted).frame(minWidth:32,minHeight:44)}.buttonStyle(.plain).accessibilityLabel(diary.t("مسح البحث","Clear search"))}
                Image(systemName:"magnifyingglass").font(.system(size:16)).foregroundStyle(Theme.text.opacity(0.85)).accessibilityHidden(true)
            }.padding(.horizontal,14).frame(minHeight:44)
                .background(Theme.background,in:RoundedRectangle(cornerRadius:12,style:.continuous))
        }.padding(16).background(Theme.surface,in:UnevenRoundedRectangle(bottomLeadingRadius:24,bottomTrailingRadius:24,style:.continuous)).padding(.horizontal,-16)
    }
    private var categoryBar:some View {
        Group{
            if typeSize.isAccessibilitySize{
                LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:4),count:2),spacing:4){categoryItems}
            }else{HStack(spacing:4){categoryItems}}
        }.padding(4).background(Theme.surface,in:RoundedRectangle(cornerRadius:14,style:.continuous))
    }
    @ViewBuilder private var categoryItems:some View {
        category(diary.t("الكل","All"),id:"all")
        category(diary.t("الوصفات","Recipes"),id:"recipe")
        category(diary.t("الوجبات","Meals"),id:"meal")
        category(diary.t("التحضير","Meal prep"),id:"prep")
    }
    private func category(_ title:String,id:String)->some View {
        Button{filter=id}label:{Text(title).luqmaFont(size:12,weight:.semibold,relativeTo:.caption)
            .foregroundStyle(filter == id ? Theme.background:Theme.text.opacity(0.8))
            .padding(.horizontal,6).frame(maxWidth:.infinity,minHeight:36)
            .background(filter == id ? Theme.text:Color.clear,in:RoundedRectangle(cornerRadius:10,style:.continuous))
        }.buttonStyle(.plain).accessibilityAddTraits(filter == id ? .isSelected:[])
    }
    private func kitchenAction(_ title:String,symbol:String,primary:Bool,action:@escaping()->Void)->some View {
        Button(action:action){Label(title,systemImage:symbol).luqmaFont(size:13,weight:.semibold,relativeTo:.subheadline)
            .foregroundStyle(Theme.text).padding(.horizontal,10).frame(maxWidth:.infinity,minHeight:44)
            .background(primary ? Theme.accent:Theme.card,in:RoundedRectangle(cornerRadius:12,style:.continuous))
        }.buttonStyle(.plain)
    }
    private func recipeCard(_ recipe:Recipe)->some View {
        let total=recipe.total
        let perServing=total.scaled(1/max(recipe.portions,0.001))
        return VStack(alignment:.leading,spacing:12){
            HStack(alignment:.top,spacing:12){
                Image(systemName:recipe.type == "prep" ? "takeoutbag.and.cup.and.straw":recipe.type == "meal" ? "fork.knife":"book.closed").font(.system(size:20)).foregroundStyle(Theme.accent).frame(width:44,height:44).background(Theme.surface,in:RoundedRectangle(cornerRadius:12)).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:4){Text(DisplayFormat.westernDigits(recipe.name)).luqmaFont(size:16,weight:.bold,relativeTo:.headline).fixedSize(horizontal:false,vertical:true);Text(recipeKind(recipe.type)).luqmaFont(.caption2).foregroundStyle(Theme.muted)}
                Spacer(minLength:0)
                Menu{Button(diary.t("تعديل","Edit")){editing=recipe};Button(diary.t("حذف","Delete"),role:.destructive){deleting=recipe}}label:{Image(systemName:"ellipsis").font(.system(size:20)).foregroundStyle(Theme.muted).frame(minWidth:44,minHeight:44)}.accessibilityLabel(diary.t("خيارات ","Options for ")+recipe.name)
            }
            HStack(spacing:12){
                Label("\(decimal(total.kcal/max(recipe.portions,0.001),0)) "+diary.t("سعرة للحصة","kcal per serving"),systemImage:"flame").foregroundStyle(Theme.accent)
                Spacer(minLength:0)
                Label("\(decimal(recipe.portions)) "+diary.t("حصص","servings"),systemImage:"square.stack").foregroundStyle(Theme.muted)
            }.luqmaFont(size:11,weight:.medium,relativeTo:.caption)
            if typeSize.isAccessibilitySize{
                VStack(spacing:10){recipeMacros(perServing)}
            }else{HStack(spacing:12){recipeMacros(perServing)}}
            HStack(spacing:10){
                kitchenAction(diary.t("إضافة حصة","Log serving"),symbol:"plus",primary:true){select(recipe,false)}
                if recipe.cookedWeight != nil{kitchenAction(diary.t("بالجرام","By weight"),symbol:"scalemass",primary:false){select(recipe,true)}}
            }
        }.padding(14).frame(maxWidth:.infinity,alignment:.leading).background(Theme.card,in:RoundedRectangle(cornerRadius:20,style:.continuous))
    }
    @ViewBuilder private func recipeMacros(_ nutrition:Nutrition)->some View {
        recipeMacro(diary.t("بروتين","Protein"),nutrition.protein)
        recipeMacro(diary.t("كارب","Carbs"),nutrition.carbs)
        recipeMacro(diary.t("دهون","Fat"),nutrition.fat)
    }
    private func recipeMacro(_ title:String,_ value:Double)->some View {
        HStack(alignment:.firstTextBaseline,spacing:4){Text(title).luqmaFont(size:10,relativeTo:.caption2).foregroundStyle(Theme.muted);Text(decimal(value)+" "+diary.t("جم","g")).luqmaFont(size:12,weight:.semibold,relativeTo:.caption).monospacedDigit().foregroundStyle(Theme.text)}.frame(maxWidth:.infinity,alignment:.leading)
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
