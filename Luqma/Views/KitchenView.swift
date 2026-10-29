import SwiftUI

struct KitchenView:View {
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var filter="all"
    @State private var query=""
    @State private var creating=false
    @State private var importingRecipe=false
    @State private var editing:Recipe?
    @State private var viewing:Recipe?
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
            categoryBar
            HStack(spacing:10){
                kitchenAction(diary.t("وصفة جديدة","New recipe"),symbol:"plus",primary:true){creating=true}.accessibilityIdentifier("kitchen.create")
                kitchenAction(diary.t("استيراد رابط","Import link"),symbol:"link",primary:false){importingRecipe=true}
            }
            LuqmaSectionHeader(title:diary.t("محفوظاتك","Your saved items"),detail:decimal(Double(filteredRecipes.count),0))
            if diary.state.recipes.isEmpty{kitchenEmptyState}
            else if filteredRecipes.isEmpty{
                SandowEmptyState(title:diary.t("لا توجد نتائج","No results"),message:diary.t("جرّب اسمًا آخر أو غيّر نوع المحفوظات.","Try another name or change the saved-item type."),
                    actionLabel:diary.t("عرض جميع المحفوظات","Show all saved items"),onAction:{query="";filter="all"})
            }
            ForEach(filteredRecipes){r in recipeCard(r).luqmaMotionTransition()}
        }.luqmaMotion(.content,value:diary.state.recipes.count).luqmaMotion(.content,value:filter).padding(.horizontal,16).padding(.top,16).padding(.bottom,24)}.scrollDismissesKeyboard(.interactively).appBackground()
            .navigationTitle(diary.t("مطبخي","My kitchen"))
            .luqmaFeedback(.light,trigger:creating){_,value in value}
            .luqmaFeedback(.success,trigger:diary.state.recipes.count){old,new in new>old}
            .toolbar(.hidden,for:.navigationBar)
            .safeAreaInset(edge:.top,spacing:0){kitchenHeader}
            .sheet(isPresented:$creating){RecipeEditor(recipe:Recipe(id:UUID(),name:"",type:"recipe",ingredients:[],portions:1,cookedWeight:nil,notes:""))}
            .sheet(isPresented:$importingRecipe){RecipeImportView()}
            .sheet(item:$editing){RecipeEditor(recipe:$0)}
            .sheet(item:$viewing){RecipeDetailView(recipeID:$0.id)}
            .sheet(item:$selected){f in FoodPortionView(food:f){food,amount,unit,meal in do{return diary.add([try DiaryEntry(food:food,amount:amount,unit:unit,meal:meal,day:DayKey.today,language:diary.language)],foods:[food])}catch{diary.report(error);return false}}}
            .confirmationDialog(diary.t("حذف الوصفة؟","Delete recipe?"),isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}}),titleVisibility:.visible){Button(diary.t("حذف","Delete"),role:.destructive){if let r=deleting{diary.removeRecipe(r.id)};deleting=nil}}
    }
    private var kitchenHeader:some View {
        VStack(spacing:8){
            LuqmaCompactTitle(title:diary.t("مطبخي","My kitchen"))
            HStack(spacing:10){
                Image(systemName:"magnifyingglass").font(.system(size:18,weight:.regular)).foregroundStyle(Theme.muted).accessibilityHidden(true)
                TextField(diary.t("ابحث في محفوظاتك","Search your saved items"),text:$query,
                          prompt:Text(diary.t("ابحث في محفوظاتك","Search your saved items")).foregroundColor(Theme.muted))
                    .luqmaFont(.subheadline).submitLabel(.search)
                    .accessibilityLabel(diary.t("البحث في وصفاتك ووجباتك","Search your recipes and meals"))
                if !query.isEmpty{Button{query=""}label:{Image(systemName:"xmark.circle.fill").foregroundStyle(Theme.muted).frame(minWidth:44,minHeight:44)}
                    .buttonStyle(LuqmaPressStyle()).accessibilityLabel(diary.t("مسح البحث","Clear search")).luqmaMotionTransition()}
            }.padding(.horizontal,12).frame(minHeight:48)
                .background(Theme.card,in:RoundedRectangle(cornerRadius:LuqmaReviewStyle.controlRadius,style:.continuous))
                .luqmaMotion(.content,value:query.isEmpty)
        }.padding(.horizontal,LuqmaReviewStyle.margin).padding(.bottom,8)
            .background(Theme.background.ignoresSafeArea(edges:.top))
    }
    private var categoryBar:some View {
        LuqmaReviewSegments(options:["all","recipe","meal","prep"],selection:$filter){value in
            switch value{case "recipe":return diary.t("الوصفات","Recipes");case "meal":return diary.t("الوجبات","Meals");case "prep":return diary.t("التحضير","Meal prep");default:return diary.t("الكل","All")}
        }
    }
    private func kitchenAction(_ title:String,symbol:String,primary:Bool,action:@escaping()->Void)->some View {
        Button(action:action){Label(title,systemImage:symbol).luqmaFont(size:13,weight:.semibold,relativeTo:.subheadline)
            .foregroundStyle(primary ? Theme.onAccent:Theme.text).padding(.horizontal,10).frame(maxWidth:.infinity,minHeight:44)
            .background(primary ? Theme.accent:Theme.card,in:RoundedRectangle(cornerRadius:12,style:.continuous))
        }.buttonStyle(LuqmaPressStyle())
    }
    private func recipeCard(_ recipe:Recipe)->some View {
        let total=recipe.total
        let perServing=total.scaled(1/max(recipe.portions,0.001))
        return VStack(alignment:.leading,spacing:14){
            HStack(alignment:.top,spacing:10){
                Button{viewing=recipe}label:{
                    HStack(spacing:12){
                        VStack(alignment:.leading,spacing:6){
                            Text(DisplayFormat.westernDigits(recipe.name))
                                .luqmaFont(size:17,weight:.bold,relativeTo:.headline)
                                .fixedSize(horizontal:false,vertical:true)
                            Text(recipeKind(recipe.type)).luqmaFont(size:10,weight:.medium,relativeTo:.caption2)
                                .foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength:0)
                        Image(systemName:"chevron.forward").font(.system(size:11,weight:.semibold)).foregroundStyle(Theme.muted)
                    }.frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
                }.buttonStyle(LuqmaPressStyle()).accessibilityHint(diary.t("عرض المكونات والتفاصيل وخطوات التحضير","View ingredients, details and preparation steps"))
                recipeMenu(recipe)
            }
            recipeServingLine(recipe,kcal:perServing.kcal)
            if typeSize.isAccessibilitySize{
                VStack(spacing:12){ForEach(MacroKey.allCases){key in recipeMacro(key,perServing)}}
            }else{
                HStack(spacing:10){ForEach(MacroKey.allCases){key in recipeMacro(key,perServing)}}
            }
            HStack(spacing:10){
                kitchenAction(diary.t("إضافة حصة","Log serving"),symbol:"plus",primary:true){select(recipe,false)}
                if recipe.cookedWeight != nil{kitchenAction(diary.t("بالجرام","By weight"),symbol:"scalemass",primary:false){select(recipe,true)}}
            }
        }.padding(16).frame(maxWidth:.infinity,alignment:.leading)
            .foregroundStyle(Theme.text).background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius:20,style:.continuous))
    }
    private func recipeMenu(_ recipe:Recipe)->some View {
        Menu{
            Button(diary.t("تعديل","Edit")){editing=recipe}
            Button(diary.t("حذف","Delete"),role:.destructive){deleting=recipe}
        }label:{
            Image(systemName:"ellipsis").font(.system(size:18,weight:.semibold))
                .foregroundStyle(Theme.text).frame(width:44,height:44)
                .background(Theme.background.opacity(0.6),in:RoundedRectangle(cornerRadius:12))
        }.accessibilityLabel(diary.t("خيارات ","Options for ")+recipe.name)
    }
    private func recipeServingLine(_ recipe:Recipe,kcal:Double)->some View {
        ViewThatFits(in:.horizontal){
            HStack(spacing:12){recipeServingLabels(recipe,kcal:kcal)}
            VStack(alignment:.leading,spacing:6){recipeServingLabels(recipe,kcal:kcal)}
        }.luqmaFont(size:11,weight:.medium,relativeTo:.caption).foregroundStyle(Theme.text.opacity(0.85))
    }
    @ViewBuilder private func recipeServingLabels(_ recipe:Recipe,kcal:Double)->some View {
        Label(decimal(kcal,0)+" "+diary.t("سعرة للحصة","kcal per serving"),systemImage:"flame.fill")
            .luqmaNumericMotion(value:kcal)
        Label(decimal(recipe.portions)+" "+diary.t("حصص","servings"),systemImage:"square.stack")
            .luqmaNumericMotion(value:recipe.portions)
    }
    private var kitchenEmptyState:some View {
        VStack(spacing:16){
            EditorialPanel(artwork:.kitchen,height:112).frame(maxWidth:240)
            Text(diary.t("مطبخك يبدأ هنا","Your kitchen starts here")).luqmaFont(.title3).accessibilityAddTraits(.isHeader)
            Text(diary.t("احفظ وصفاتك واحسب حصصها بسهولة. ابدأ بوصفة جديدة أو استورد رابطًا من الأعلى.","Save recipes and calculate their servings. Start a new recipe or import a link above."))
                .luqmaFont(.footnote).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true)
        }.multilineTextAlignment(.center).frame(maxWidth:.infinity).padding(.vertical,24)
    }
    private func recipeMacro(_ key:MacroKey,_ nutrition:Nutrition)->some View {
        let ratio=nutrition.macroCalories>0 ? nutrition[key]*key.energy/nutrition.macroCalories:0
        return HStack(spacing:7){
            LuqmaProgressRing(progress:ratio,color:Theme.text.opacity(0.85),lineWidth:4).frame(width:24,height:24)
            VStack(alignment:.leading,spacing:3){
                Text(decimal(nutrition[key])+" "+diary.t("جم","g")).luqmaFont(size:12,weight:.bold,relativeTo:.caption).monospacedDigit()
                    .luqmaNumericMotion(value:nutrition[key])
                Text(key.label(diary.language)).luqmaFont(size:10,relativeTo:.caption2).foregroundStyle(Theme.muted)
            }
        }.frame(maxWidth:.infinity,alignment:.leading).accessibilityElement(children:.combine)
    }
    private func recipeKind(_ type:String)->String {switch type{case "meal":return diary.t("وجبة محفوظة","Saved meal");case "prep":return diary.t("تحضير وجبات","Meal prep");default:return diary.t("وصفة","Recipe")}}
    private func select(_ r:Recipe,_ weighted:Bool){do{selected=try r.food(byWeight:weighted)}catch{diary.report(error)}}
}
/// N11's ingredient/instruction structure uses real saved recipe data.
/// The unavailable reference photo/gallery/rating assets are not fabricated.
struct RecipeDetailView:View {
    let recipeID:UUID
    var previewRecipe:Recipe?=nil
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dismiss) private var dismiss
    @State private var editing=false
    @State private var selected:Food?
    @State private var checked:Set<UUID>=[]
    @State private var expandedIngredients:Set<UUID>=[]
    @Environment(\.dynamicTypeSize) private var detailTypeSize
    private var recipe:Recipe? {diary.state.recipes.first{$0.id==recipeID} ?? previewRecipe}
    var body:some View {
        NavigationStack{
            ScrollViewReader{scroll in
            ScrollView{
                if let recipe{
                    VStack(alignment:.leading,spacing:20){
                        recipeHeader(recipe)
                        nutritionSummary(recipe)
                        VStack(alignment:.leading,spacing:12){
                            LuqmaSectionHeader(title:diary.t("المكونات","Ingredients"),detail:String(recipe.ingredients.count)+" "+diary.t("مكونات","items"))
                            Text(diary.t("المقادير للوصفة كاملة","Quantities for the whole recipe")).luqmaFont(.caption).foregroundStyle(Theme.muted)
                            VStack(spacing:0){
                                ForEach(Array(recipe.ingredients.enumerated()),id:\.element.id){index,ingredient in
                                    ingredientRow(ingredient,recipe:recipe)
                                    if index < recipe.ingredients.count-1{Rectangle().fill(Theme.stroke).frame(height:0.5).padding(.vertical,12)}
                                }
                            }.luqmaCard()
                        }.id("recipe-detail-ingredients")
                        if !recipe.notes.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty{
                            VStack(alignment:.leading,spacing:8){
                                LuqmaSectionHeader(title:diary.t("ملاحظات الوصفة","Recipe notes"))
                                Text(DisplayFormat.westernDigits(recipe.notes)).luqmaFont(.footnote).foregroundStyle(Theme.muted)
                                    .fixedSize(horizontal:false,vertical:true)
                            }
                        }
                        if let info=recipe.importInfo{
                            if !info.steps.isEmpty{
                                VStack(alignment:.leading,spacing:16){
                                    LuqmaSectionHeader(title:diary.t("خطوات التحضير","Instructions"))
                                    ForEach(Array(info.steps.enumerated()),id:\.offset){index,step in
                                        HStack(alignment:.top,spacing:12){
                                            Text(String(index+1)).luqmaFont(.caption).frame(minWidth:26,minHeight:26)
                                                .foregroundStyle(Theme.onAccent)
                                                .background(Theme.accent,in:RoundedRectangle(cornerRadius:8))
                                            Text(DisplayFormat.westernDigits(step)).luqmaFont(.footnote).foregroundStyle(Theme.muted)
                                                .frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true)
                                        }
                                    }
                                }
                            }
                            if let source=info.sourceURL,let url=URL(string:source){Link(diary.t("فتح الوصفة الأصلية","Open original recipe"),destination:url).luqmaFont(.footnote)}
                            if info.nutritionIsEstimated{Notice(text:diary.t("القيم الغذائية تقديرية؛ راجع المقادير وعدد الحصص.","Nutrition is estimated; review quantities and servings."))}
                            ForEach(info.assumptions,id:\.self){Notice(text:$0)}
                        }
                    }.padding(16).padding(.bottom,16)
                        .luqmaFeedback(.selection,trigger:checked)
                }else{
                    SandowEmptyState(title:diary.t("الوصفة غير متاحة","Recipe unavailable"),message:diary.t("ربما حُذفت هذه الوصفة. ارجع إلى مطبخك للاطلاع على المحفوظات.","This recipe may have been deleted. Return to your kitchen to view saved items."),
                        actionLabel:diary.t("العودة إلى مطبخي","Back to my kitchen"),onAction:{dismiss()}).padding(16)
                }
            }.appBackground().sandowNavigation(diary.t("تفاصيل الوصفة","Recipe details"),backLabel:diary.t("إغلاق","Close"),onBack:{dismiss()})
                .safeAreaInset(edge:.bottom,spacing:0){
                    if let recipe{
                        VStack(spacing:8){
                            Button{select(recipe,false)}label:{Label(diary.t("إضافة حصة","Log serving"),systemImage:"plus")}.buttonStyle(LuqmaPrimaryButtonStyle())
                                .accessibilityIdentifier("recipeDetail.logServing")
                            if recipe.cookedWeight != nil{
                                Button{select(recipe,true)}label:{
                                    Label(diary.t("إضافة كمية بالجرام","Log a gram quantity"),systemImage:"scalemass")
                                        .luqmaFont(.footnote).foregroundStyle(Theme.textSecondary).frame(maxWidth:.infinity,minHeight:44)
                                }.buttonStyle(LuqmaPressStyle()).accessibilityIdentifier("recipeDetail.logGrams")
                            }
                        }.padding(.horizontal,16).padding(.top,12).padding(.bottom,8).background(Theme.background)
                    }
                }
                .sheet(isPresented:$editing){if let recipe{RecipeEditor(recipe:recipe)}}
                .sheet(item:$selected){food in FoodPortionView(food:food,initialUnit:food.unit){value,amount,unit,meal in
                    do{return diary.add([try DiaryEntry(food:value,amount:amount,unit:unit,meal:meal,day:DayKey.today,language:diary.language)],foods:[value])}
                    catch{diary.report(error);return false}
                }}
                #if DEBUG
                .task{
                    if previewRecipe != nil,ProcessInfo.processInfo.arguments.contains("-loqma-preview-recipe-nutrition"){
                        try? await Task.sleep(for:.milliseconds(300))
                        scroll.scrollTo("recipe-detail-ingredients",anchor:.top)
                    }
                }
                #endif
            }
        }
    }
    private func recipeHeader(_ recipe:Recipe)->some View {
        VStack(alignment:.leading,spacing:8){
            HStack(alignment:.firstTextBaseline,spacing:12){
                Text(diary.t("من مطبخي","From my kitchen")).luqmaFont(.caption).foregroundStyle(Theme.accentText)
                Spacer(minLength:8)
                Button{editing=true}label:{Label(diary.t("تعديل","Edit"),systemImage:"square.and.pencil")
                    .luqmaFont(.footnote).foregroundStyle(Theme.textSecondary).frame(minHeight:44)}
                    .buttonStyle(LuqmaPressStyle()).accessibilityLabel(diary.t("تعديل الوصفة","Edit recipe"))
                    .accessibilityIdentifier("recipeDetail.edit")
            }
            Text(DisplayFormat.westernDigits(recipe.name)).luqmaFont(.title2)
                .frame(maxWidth:.infinity,alignment:.leading).fixedSize(horizontal:false,vertical:true).accessibilityAddTraits(.isHeader)
            ViewThatFits(in:.horizontal){
                HStack(spacing:12){recipeYield(recipe)}
                VStack(alignment:.leading,spacing:6){recipeYield(recipe)}
            }
        }
    }
    @ViewBuilder private func recipeYield(_ recipe:Recipe)->some View {
        Label(decimal(recipe.portions)+" "+diary.t("حصص","servings"),systemImage:"fork.knife")
            .luqmaFont(.caption).foregroundStyle(Theme.muted)
        if let weight=recipe.cookedWeight{
            Label(decimal(weight)+" "+diary.t("جم بعد الطبخ","g cooked"),systemImage:"scalemass")
                .luqmaFont(.caption).foregroundStyle(Theme.muted)
        }
    }
    private func nutritionSummary(_ recipe:Recipe)->some View {
        let value=recipe.total.scaled(1/max(recipe.portions,0.001))
        return VStack(alignment:.leading,spacing:12){
            HStack(alignment:.center,spacing:12){
                VStack(alignment:.leading,spacing:2){
                    Text(diary.t("القيم الغذائية","Nutrition")).luqmaFont(.subheadline)
                    Text(diary.t("لكل حصة","Per serving")).luqmaFont(.caption).foregroundStyle(Theme.muted)
                }
                Spacer(minLength:8)
                HStack(alignment:.firstTextBaseline,spacing:5){
                    Text(decimal(value.kcal,0)).luqmaFont(.metric).monospacedDigit().foregroundStyle(Theme.accentText)
                    Text(diary.t("سعرة","kcal")).luqmaFont(.caption).foregroundStyle(Theme.muted)
                }.accessibilityElement(children:.combine)
            }
            Rectangle().fill(Theme.stroke).frame(height:0.5)
            macroGrid(value)
        }.luqmaCard()
    }
    @ViewBuilder private func macroGrid(_ value:Nutrition)->some View {
        if detailTypeSize.isAccessibilitySize{
            VStack(spacing:12){ForEach(MacroKey.allCases){key in LuqmaReviewMacro(key:key,amount:value[key])}}
        }else{
            HStack(alignment:.top,spacing:12){ForEach(MacroKey.allCases){key in LuqmaReviewMacro(key:key,amount:value[key])}}
        }
    }
    private var expandedReviewFixture:Bool {
        #if DEBUG
        // Preview recipe IDs are regenerated by the parent. The read-only
        // capture flag therefore derives the open state without storing IDs.
        return previewRecipe != nil && ProcessInfo.processInfo.arguments.contains("-loqma-preview-recipe-nutrition")
        #else
        return false
        #endif
    }
    private func ingredientRow(_ ingredient:Ingredient,recipe:Recipe)->some View {
        let isChecked=checked.contains(ingredient.id)
        let isExpanded=expandedIngredients.contains(ingredient.id) || expandedReviewFixture
        return VStack(alignment:.leading,spacing:10){
            HStack(alignment:.top,spacing:8){
                Button{if isChecked{checked.remove(ingredient.id)}else{checked.insert(ingredient.id)}}label:{
                    Image(systemName:isChecked ? "checkmark.circle.fill":"circle")
                        .font(.system(size:20,weight:.regular)).foregroundStyle(isChecked ? Theme.accentText:Theme.muted)
                        .frame(width:44,height:44).contentShape(Rectangle())
                }.buttonStyle(LuqmaPressStyle()).accessibilityLabel(DisplayFormat.westernDigits(ingredient.name))
                    .accessibilityValue(isChecked ? diary.t("محدد","Checked"):diary.t("غير محدد","Unchecked"))
                    .accessibilityAddTraits(isChecked ? .isSelected:[]).accessibilityIdentifier("recipeDetail.check."+ingredient.id.uuidString)
                VStack(alignment:.leading,spacing:5){
                    Text(DisplayFormat.westernDigits(ingredient.name)).luqmaFont(.subheadline).foregroundStyle(Theme.text)
                        .fixedSize(horizontal:false,vertical:true)
                    Text(decimal(ingredient.amount)+" "+DisplayFormat.westernDigits(recipe.importInfo?.ingredientUnitLabels[ingredient.id.uuidString] ?? ingredient.unit.label(diary.language)))
                        .luqmaFont(.caption).foregroundStyle(Theme.muted).monospacedDigit()
                }.frame(maxWidth:.infinity,alignment:.leading)
                VStack(alignment:.trailing,spacing:2){
                    Text(decimal(ingredient.kcal,0)).luqmaFont(.headline).foregroundStyle(Theme.text).monospacedDigit()
                    Text(diary.t("سعرة","kcal")).luqmaFont(.caption).foregroundStyle(Theme.muted)
                }.accessibilityElement(children:.combine)
            }
            Button{if isExpanded{expandedIngredients.remove(ingredient.id)}else{expandedIngredients.insert(ingredient.id)}}label:{
                HStack(spacing:6){
                    Text(diary.t("التفاصيل الغذائية","Nutrition details")).luqmaFont(.caption)
                    Image(systemName:isExpanded ? "chevron.up":"chevron.down").font(.system(size:10,weight:.semibold))
                    Spacer(minLength:0)
                }.foregroundStyle(Theme.accentText).frame(minHeight:44).contentShape(Rectangle())
            }.buttonStyle(LuqmaPressStyle()).accessibilityValue(isExpanded ? diary.t("موسّع","Expanded"):diary.t("مطوي","Collapsed"))
                .accessibilityIdentifier("recipeDetail.nutrition."+ingredient.id.uuidString)
            if isExpanded{
                VStack(alignment:.leading,spacing:8){
                    Text(diary.t("للكمية الموضحة أعلاه","For the quantity shown above")).luqmaFont(.caption).foregroundStyle(Theme.muted)
                    macroGrid(ingredient.nutrition)
                }.padding(12).background(Theme.background,in:RoundedRectangle(cornerRadius:LuqmaReviewStyle.controlRadius,style:.continuous))
            }
        }.luqmaMotion(.content,value:isExpanded).luqmaMotion(.selection,value:isChecked)
    }
    private func select(_ recipe:Recipe,_ weighted:Bool){do{selected=try recipe.food(byWeight:weighted)}catch{diary.report(error)}}
}

struct RecipeEditor:View {
    @State var recipe:Recipe
    @EnvironmentObject var diary:DiaryStore
    @Environment(\.dismiss) var dismiss
    @State private var adding=false
    @State private var byWeight=false
    @State private var showingNotes=false
    @State private var initialized=false
    var body:some View {
        NavigationStack{Form{
            LuqmaReviewFormSection(title:diary.t("الوصفة","Recipe")){
                TextField(diary.t("اسم الوصفة أو الوجبة","Recipe or meal name"),text:$recipe.name,prompt:Text(diary.t("اسم الوصفة أو الوجبة","Recipe or meal name")).foregroundColor(Theme.muted),axis:.vertical)
                    .luqmaFont(.title3).lineLimit(1...3).accessibilityIdentifier("recipe.name")
                LuqmaReviewSegments(options:["recipe","meal","prep"],selection:$recipe.type){value in
                    value == "recipe" ? diary.t("وصفة","Recipe"):value == "meal" ? diary.t("وجبة","Meal"):diary.t("تحضير","Prep")
                }
            }.listRowBackground(Theme.card).listRowSeparator(.hidden)
            LuqmaReviewFormSection(title:diary.t("المكونات","Ingredients")){
                ForEach(recipe.ingredients){i in HStack(spacing:12){Image(systemName:"fork.knife").font(.system(size:16)).foregroundStyle(Theme.accentText).frame(width:36,height:36).background(Theme.surface,in:RoundedRectangle(cornerRadius:10)).accessibilityHidden(true);VStack(alignment:.leading,spacing:5){Text(DisplayFormat.westernDigits(i.name)).luqmaFont(size:15,weight:.semibold,relativeTo:.subheadline);Text("\(decimal(i.amount)) \(DisplayFormat.westernDigits(recipe.importInfo?.ingredientUnitLabels[i.id.uuidString] ?? i.unit.label(diary.language))) · \(decimal(i.kcal,0)) \(diary.t("سعرة","kcal"))").luqmaFont(.caption).foregroundStyle(Theme.muted)}}.padding(.vertical,4)}.onDelete{indices in
                    recipe.ingredients.remove(atOffsets:indices)
                    let remaining=Set(recipe.ingredients.map{$0.id.uuidString})
                    recipe.importInfo?.ingredientUnitLabels=recipe.importInfo?.ingredientUnitLabels.filter{remaining.contains($0.key)} ?? [:]
                }
                Button{adding=true}label:{Label(diary.t("إضافة مكوّن","Add ingredient"),systemImage:"plus")}.disabled(recipe.ingredients.count>=80).accessibilityIdentifier("recipe.addIngredient")
            }.luqmaMotion(.content,value:recipe.ingredients.map(\.id)).listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            LuqmaReviewFormSection(title:diary.t("الحصص والوزن","Servings and weight")){
                LuqmaReviewNumber(title:diary.t("عدد الحصص","Number of servings"),value:$recipe.portions)
                Toggle(diary.t("حساب بالوزن بعد الطبخ","Use final cooked weight"),isOn:$byWeight).accessibilityIdentifier("recipe.byWeight")
                if byWeight{LuqmaReviewNumber(title:diary.t("الوزن بعد الطبخ","Cooked weight"),value:Binding(get:{recipe.cookedWeight ?? 0},set:{recipe.cookedWeight=$0}),suffix:diary.t("جم","g"));Notice(text:diary.t("أدخل الوزن النهائي لحساب أي كمية بالجرام. الماء يغيّر الوزن دون تغيير مجموع السعرات.","Enter the final weight to calculate any gram portion. Water changes weight without changing total calories."))}
            }.luqmaMotion(.content,value:byWeight).listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            if !recipe.ingredients.isEmpty{LuqmaReviewFormSection(title:diary.t("لكل حصة","Per serving")){LuqmaReviewNutrition(value:recipe.total.scaled(1/max(recipe.portions,0.001)))}.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke);if byWeight,let w=recipe.cookedWeight,w>0{LuqmaReviewFormSection(title:diary.t("لكل ١٠٠ جم بعد الطبخ","Per 100 g cooked")){LuqmaReviewNutrition(value:recipe.total.scaled(100/w))}.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)}}
            Section{DisclosureGroup(diary.t("ملاحظات اختيارية","Optional notes"),isExpanded:$showingNotes){TextField(diary.t("ملاحظاتك","Your notes"),text:$recipe.notes,prompt:Text(diary.t("ملاحظاتك","Your notes")).foregroundColor(Theme.muted),axis:.vertical).lineLimit(2...5)}.luqmaMotion(.content,value:showingNotes)}.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            if let info=recipe.importInfo{
                LuqmaReviewFormSection(title:diary.t("خطوات التحضير","Preparation steps")){ForEach(Array(info.steps.enumerated()),id:\.offset){index,step in Text("\(index+1). "+DisplayFormat.westernDigits(step))}}.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
                LuqmaReviewFormSection(title:diary.t("المصدر والتقدير","Source and estimate")){
                    if let source=info.sourceURL,let url=URL(string:source){Link(diary.t("فتح الوصفة الأصلية","Open original recipe"),destination:url)}
                    if info.nutritionIsEstimated{Notice(text:diary.t("القيم الغذائية تقديرية؛ راجع المقادير وعدد الحصص.","Nutrition is estimated; review quantities and servings."))}
                    ForEach(info.assumptions,id:\.self){Notice(text:$0)}
                }.listRowBackground(Theme.card).listRowSeparatorTint(Theme.stroke)
            }
        }.sandowForm().luqmaReviewKeyboard().sandowNavigation(diary.t("حفظ في مطبخي","Save to kitchen"),backLabel:diary.t("إلغاء","Cancel"),onBack:{dismiss()},
            actionLabel:diary.t("حفظ","Save"),actionEnabled:!recipe.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && !recipe.ingredients.isEmpty && recipe.portions.isFinite && recipe.portions>0 && (!byWeight || (recipe.cookedWeight.map{$0.isFinite && $0>0} ?? false)),
            onAction:{if !byWeight{recipe.cookedWeight=nil};if diary.saveRecipe(recipe){dismiss()}})
            .fullScreenCover(isPresented:$adding){FoodAddView{f,a,u,_ in do{let n=try f.total(a,unit:u);recipe.ingredients.append(Ingredient(id:UUID(),name:f.label(diary.language),amount:a,unit:u,kcal:n.kcal,protein:n.protein,carbs:n.carbs,fat:n.fat))
                if MealPhotoEstimate.isValidPhotoEstimate(f) || f.sourceDescription=="luqma:estimated-components"{let note=diary.t("تحتوي الوصفة على قيم مقدّرة من صورة؛ راجعها قبل الاستخدام.","This recipe includes photo estimates; review them before use.");if !recipe.notes.contains(note){recipe.notes=String((recipe.notes+"\n"+note).trimmingCharacters(in:.whitespacesAndNewlines).prefix(2000))}}
                return true}catch{diary.report(error);return false}}}
        }.onAppear{
            guard !initialized else{return}
            initialized=true
            byWeight=recipe.cookedWeight != nil;showingNotes = !recipe.notes.isEmpty
        }
    }
}
