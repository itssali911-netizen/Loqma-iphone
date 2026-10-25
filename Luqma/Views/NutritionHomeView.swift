import SwiftUI

private typealias E=NutritionExactTheme

/// The real Home. Rebuild the projection on diary/date changes, while search,
/// focus and sheet state remain in the child and don't regroup saved entries.
struct NutritionHomeView:View {
    @Binding var date:Date
    var externalAdd:Binding<Bool>?=nil
    var onSearch:(String)->Void
    var onChooseDate:()->Void
    var onNotifications:()->Void
    var onFood:(Food)->Void
    var onEdit:(DiaryEntry)->Void
    var onFullGoals:()->Void
    var onHistory:()->Void
    @EnvironmentObject private var diary:DiaryStore
    var body:some View {
        let snapshot=NutritionHomeSnapshot(state:diary.state,day:DayKey.string(date))
        NutritionHomeContent(snapshot:snapshot,date:$date,externalAdd:externalAdd,
            onSearch:onSearch,onChooseDate:onChooseDate,onNotifications:onNotifications,
            onFood:onFood,onEdit:onEdit,onFullGoals:onFullGoals,onHistory:onHistory)
    }
}

private struct NutritionHomeContent:View {
    let snapshot:NutritionHomeSnapshot
    @Binding var date:Date
    var externalAdd:Binding<Bool>?
    var onSearch:(String)->Void
    var onChooseDate:()->Void
    var onNotifications:()->Void
    var onFood:(Food)->Void
    var onEdit:(DiaryEntry)->Void
    var onFullGoals:()->Void
    var onHistory:()->Void
    @EnvironmentObject private var diary:DiaryStore
    @EnvironmentObject private var reminders:ReminderService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var direction
    @State private var query=""
    @State private var category:NutritionHomeCategory = .meat
    @State private var featuredIndex=0
    @State private var details:NutritionHomeCard?
    @State private var deleting:DiaryEntry?
    @State private var localAdding=false
    @State private var seed:NutritionHomeCard?
    @State private var goalEditing=false
    @State private var filteredIDs:[String]?
    @State private var pendingFood:Food?
    @State private var pendingExample:NutritionHomeCard?
    @State private var pendingEntry:DiaryEntry?
    @State private var pendingDelete:DiaryEntry?
    @State private var pendingSearch=false
    @State private var pendingFullGoals=false
    private var day:String {DayKey.string(date)}
    private var adding:Binding<Bool>{externalAdd ?? $localAdding}
    private var goals:Nutrition {diary.dailyGoals(day)}
    private struct FilterRequest:Hashable {let query:String;let category:NutritionHomeCategory;let revision:Int}
    private var filterRequest:FilterRequest {FilterRequest(query:query,category:category,revision:snapshot.searchIndex.revision)}

    var body:some View {
        ScrollView{
            VStack(spacing:0){
                header
                VStack(alignment:.leading,spacing:E.sectionGap){
                    categories
                    morning
                    calorieGoal
                    featured
                    browse
                }.padding(.horizontal,E.horizontal).padding(.top,E.sectionGap).padding(.bottom,40)
            }
        }.scrollDismissesKeyboard(.interactively)
            .background(E.background.ignoresSafeArea()).foregroundStyle(E.primary).tint(E.orange)
            .toolbar(.hidden,for:.navigationBar)
            .task(id:filterRequest){await filterMeals()}
            .sheet(item:$details,onDismiss:drainPending){card in
                NutritionMealDetailSheet(card:card,day:day,onToggle:{
                    if let entry=card.matchingEntry(in:diary.state.entries,day:day){pendingDelete=entry;details=nil}
                    else if let food=card.food{pendingFood=food;details=nil}
                    else{pendingExample=card;details=nil}
                },onEdit:{entry in pendingEntry=entry;details=nil})
                    .presentationDetents([.height(280),.medium,.large]).presentationCornerRadius(24).presentationDragIndicator(.visible)
            }
            .sheet(isPresented:adding,onDismiss:drainPending){
                NutritionNewMealSheet(seed:seed,day:day,onSearch:{pendingSearch=true;adding.wrappedValue=false})
                    .presentationDetents([.medium,.large]).presentationCornerRadius(16).presentationDragIndicator(.visible)
            }
            .sheet(isPresented:$goalEditing,onDismiss:drainPending){
                NutritionGoalSheet(onFullGoals:{pendingFullGoals=true;goalEditing=false})
                    .presentationDetents([.height(310),.large]).presentationCornerRadius(16).presentationDragIndicator(.visible)
            }
            .confirmationDialog(diary.t("إزالة الوجبة من السجل؟","Remove meal from diary?"),isPresented:Binding(get:{deleting != nil},set:{if !$0{deleting=nil}}),titleVisibility:.visible){
                Button(diary.t("حذف","Delete"),role:.destructive){if let deleting{diary.remove(deleting.id)};deleting=nil}
                Button(diary.t("إلغاء","Cancel"),role:.cancel){deleting=nil}
            }
    }
    private var header:some View {
        VStack(spacing:14){
            HStack(spacing:12){
                NavigationLink{FitnessProfileView()}label:{
                    Image("LuqmaMark").resizable().scaledToFit().padding(7).frame(width:54,height:54)
                        .background(.white,in:RoundedRectangle(cornerRadius:16)).clipShape(RoundedRectangle(cornerRadius:16))
                }.buttonStyle(NutritionExactPressStyle()).accessibilityLabel(diary.t("ملف اللياقة","Fitness profile")).accessibilityIdentifier("diary.fitnessProfile")
                VStack(alignment:.leading,spacing:2){
                    Button(action:onChooseDate){Text(DisplayFormat.date(date,template:"d MMM yyyy",language:diary.language)).tracking(0.5).nutritionFont(10,weight:.bold).textCase(.uppercase).foregroundStyle(E.muted)}.buttonStyle(.plain).accessibilityLabel(diary.t("اختيار التاريخ","Choose date"))
                    Text(diary.t("مرحباً بك!","Hello there!")).tracking(-0.5).nutritionFont(20,weight:.heavy,lineHeight:1.25).accessibilityAddTraits(.isHeader)
                    HStack(spacing:6){
                        HStack(spacing:4){NutritionExactIcon(name:"HeaderFlame",size:14);Text(decimal(snapshot.consumed.kcal,0)+"kcal").accessibilityIdentifier("exact.home.consumed")}.environment(\.layoutDirection,.leftToRight)
                        Text("•").foregroundStyle(E.subtle)
                        HStack(spacing:4){Text("#").nutritionFont(9,weight:.bold).frame(width:14,height:14).background(E.blue,in:RoundedRectangle(cornerRadius:4));Text(diary.t(snapshot.entries.isEmpty ? "لم تسجّل":"مسجّل",snapshot.entries.isEmpty ? "Not logged":"Logged"))}
                    }.nutritionFont(11.5,weight:.semibold).foregroundStyle(E.secondary).padding(.top,2)
                }.frame(maxWidth:.infinity,alignment:.leading)
                Button(action:onNotifications){
                    NutritionExactIcon(name:"Bell",size:20).frame(width:46,height:46)
                        .background(E.badge,in:RoundedRectangle(cornerRadius:15))
                        .overlay{RoundedRectangle(cornerRadius:15).strokeBorder(E.notificationBorder,lineWidth:1)}
                        .overlay(alignment:.topTrailing){if !reminders.deliveredNotifications.isEmpty{Text(String(reminders.deliveredNotifications.count)).nutritionFont(9,weight:.bold).frame(minWidth:16,minHeight:16).background(E.notification,in:Circle()).offset(x:4,y:-4)}}
                }.environment(\.layoutDirection,.leftToRight).buttonStyle(NutritionExactPressStyle()).accessibilityLabel(diary.t("الإشعارات","Notifications"))
            }
            HStack(spacing:8){
                TextField(diary.t("ابحث في قاعدة بيانات الطعام...","Search our food database..."),text:$query,prompt:Text(diary.t("ابحث في قاعدة بيانات الطعام...","Search our food database...")).foregroundColor(E.muted))
                    .nutritionFont(13,weight:.medium,lineHeight:1.5).submitLabel(.search).onSubmit{onSearch(query)}
                    .accessibilityIdentifier("exact.home.searchInput")
                Button{onSearch(query)}label:{NutritionExactIcon(name:"Search",size:16).frame(width:28,height:44)}.buttonStyle(.plain).accessibilityLabel(diary.t("البحث عن الطعام","Search food")).accessibilityIdentifier("diary.search")
            }.padding(.horizontal,16).frame(minHeight:44).nutritionPanel(E.search,radius:16)
        }.padding(16)
            .background{E.header.clipShape(UnevenRoundedRectangle(bottomLeadingRadius:28,bottomTrailingRadius:28)).ignoresSafeArea(edges:.top)}
            .shadow(color:.black.opacity(0.12),radius:3,y:2)
    }
    private var categories:some View {
        VStack(alignment:.leading,spacing:10){
            sectionHeader(diary.t("تصفح التصنيفات","Browse Category"),action:diary.t("عرض الكل","See All")){category = .all}
            ScrollView(.horizontal,showsIndicators:false){HStack(spacing:8){ForEach(NutritionHomeCategory.allCases){item in
                Button{category=item}label:{
                    HStack(spacing:6){
                        if item == .vegetables{Text("🥬").font(.system(size:13))}
                        else if item == .fruit{Text("🍐").font(.system(size:12))}
                        else{NutritionExactIcon(name:item == .meat ? "Heart":"Utensils",size:14)}
                        Text(item.label(diary.language)).nutritionFont(12,weight:.bold).fixedSize()
                    }.padding(.horizontal,item == .meat ? 14:12).frame(minHeight:34)
                        .nutritionPanel(category == item ? E.blue:E.secondaryCard,radius:11)
                        .shadow(color:category == item ? E.blue.opacity(0.5):.clear,radius:6)
                }.buttonStyle(NutritionExactPressStyle()).accessibilityAddTraits(category == item ? .isSelected:[]).accessibilityIdentifier("exact.category."+item.rawValue)
            }}}
        }
    }
    private var morning:some View {
        VStack(alignment:.leading,spacing:10){
            sectionHeader(diary.t("الروتين الصباحي","Morning Routine"),action:diary.t("عرض الكل","See All")){if let first=snapshot.morning.first{details=first}}
            ScrollView(.horizontal,showsIndicators:false){LazyHStack(spacing:12){ForEach(snapshot.morning){card in
                Button{details=card}label:{morningCard(card)}.buttonStyle(NutritionExactPressStyle())
            }}}
        }
    }
    private func morningCard(_ card:NutritionHomeCard)->some View {
        ZStack(alignment:.trailing){
            NutritionHomeArtwork(name:card.artwork,caption:diary.t("توضيحية","Illustration")).frame(width:92)
            VStack(alignment:.leading,spacing:0){
                NutritionExactIcon(name:"Utensils",size:16).frame(width:30,height:30).nutritionPanel(E.orange,radius:9)
                Spacer(minLength:8)
                VStack(alignment:.leading,spacing:2){
                    Text(card.name(diary.language)).nutritionFont(13.5,weight:.heavy,lineHeight:1.25).lineLimit(2)
                    metadata("Flame",text:calories(card),color:E.metadata)
                    metadata("Zap",text:card.proteinLabel(diary.language),color:E.metadata)
                    if card.isExample{Text(diary.t("مثال من المرجع","Reference example")).nutritionFont(9,weight:.medium).foregroundStyle(E.muted)}
                }.frame(maxWidth:150,alignment:.leading)
            }.padding(12).frame(maxWidth:.infinity,alignment:.leading)
        }.frame(width:198).frame(minHeight:134).nutritionPanel(E.card,radius:20).clipShape(RoundedRectangle(cornerRadius:20))
            .accessibilityElement(children:.combine).accessibilityHint(diary.t("صورة توضيحية بديلة؛ اضغط للتفاصيل","Substitute illustration; tap for details"))
    }
    private var calorieGoal:some View {
        VStack(alignment:.leading,spacing:8){
                HStack{Text(diary.t("هدف السعرات","Calorie Goal")).tracking(-0.35).nutritionFont(14,weight:.heavy);Spacer();Button{goalEditing=true}label:{NutritionExactIcon(name:"MoreVertical",size:16,color:E.subtle).frame(width:32,height:24)}.buttonStyle(.plain).accessibilityLabel(diary.t("إعدادات هدف السعرات","Calorie goal settings"))}
            VStack(spacing:12){
                HStack{
                    HStack(alignment:.firstTextBaseline,spacing:6){Text(decimal(goals.kcal,0)).tracking(-0.7).nutritionFont(28,weight:.black,lineHeight:1).accessibilityIdentifier("exact.home.goal");Text("kcal").nutritionFont(15,weight:.semibold,lineHeight:1).foregroundStyle(.white.opacity(0.9))}.environment(\.layoutDirection,.leftToRight).monospacedDigit()
                    Spacer()
                    Button{goalEditing=true}label:{NutritionExactIcon(name:"Settings",size:16).frame(width:38,height:38).background(.white.opacity(0.1),in:RoundedRectangle(cornerRadius:12)).overlay{RoundedRectangle(cornerRadius:12).strokeBorder(.white.opacity(0.4))}}.buttonStyle(NutritionExactPressStyle()).accessibilityLabel(diary.t("تعديل هدف السعرات","Edit calorie goal")).accessibilityIdentifier("diary.goals")
                }
                Button{goalEditing=true}label:{NutritionCalorieProgress(consumed:snapshot.consumed.kcal,goal:goals.kcal)}.buttonStyle(.plain).accessibilityLabel(diary.t("تقدم السعرات المستهلكة؛ تعديل الهدف","Consumed calorie progress; edit goal")).accessibilityValue(decimal(snapshot.consumed.kcal,0)+" / "+decimal(goals.kcal,0))
            }.padding(16).background(E.cardGradient,in:RoundedRectangle(cornerRadius:22)).shadow(color:.black.opacity(0.2),radius:7,y:5)
        }
    }
    private var featured:some View {
        VStack(alignment:.leading,spacing:10){
            HStack{
                Text(diary.t("الوجبات","Meals")).tracking(-0.35).nutritionFont(14,weight:.heavy)
                Spacer(minLength:8)
                Button{seed=nil;adding.wrappedValue=true}label:{Text(diary.t("+ وجبة جديدة","+ New Meal")).nutritionFont(11.5,weight:.bold).foregroundStyle(E.orangeLink)}.buttonStyle(.plain).accessibilityIdentifier("exact.home.newMeal")
                Button{featuredIndex=(featuredIndex+1)%max(1,snapshot.featured.count)}label:{Text(diary.t("عرض الكل","See All")).nutritionFont(11.5,weight:.bold).foregroundStyle(E.orangeLink)}.buttonStyle(.plain).accessibilityLabel(diary.t("عرض الوجبة التالية","Show next meal"))
            }
            if !snapshot.featured.isEmpty {featuredCard(snapshot.featured[featuredIndex%snapshot.featured.count])}
        }
    }
    private func featuredCard(_ card:NutritionHomeCard)->some View {
        NutritionFeaturedLayout(direction:direction){
            VStack(alignment:.leading,spacing:10){
                Button{details=card}label:{VStack(alignment:.leading,spacing:10){
                    HStack(spacing:6){NutritionExactIcon(name:"Utensils",size:12).frame(width:22,height:22).nutritionPanel(E.orange,radius:6);Text(diary.t(card.isExample ? "الوجبات • مثال":"الوجبات • إضافة وجبة",card.isExample ? "Meals • Example":"Meals • Add Meal")).nutritionFont(10,weight:.bold).foregroundStyle(E.secondary).padding(.horizontal,10).padding(.vertical,4).nutritionPanel(E.badge,radius:7)}
                    Text(card.name(diary.language)).nutritionFont(16,weight:.heavy,lineHeight:1.375).fixedSize(horizontal:false,vertical:true)
                    LazyVGrid(columns:[GridItem(.flexible(),spacing:8),GridItem(.flexible(),spacing:8)],alignment:.leading,spacing:4){
                        metadata("Flame",text:calories(card));metadata("Clock",text:time(card));metadata("Utensils",text:card.proteinLabel(diary.language));metadata("Plus",text:diary.t(card.isExample ? "للعرض":"محفوظة",card.isExample ? "Example":"Saved"))
                    }
                }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())}.buttonStyle(.plain)
                    Button{toggle(card)}label:{
                        HStack(spacing:6){Text(diary.t(isAdded(card) ? "تمت الإضافة":"إضافة وجبة",isAdded(card) ? "Meal Added":"Add Meal")).nutritionFont(11,weight:.bold);NutritionExactIcon(name:isAdded(card) ? "Check":"Plus",size:14)}
                            .padding(.horizontal,14).frame(height:32).background(isAdded(card) ? E.orange:.clear,in:RoundedRectangle(cornerRadius:10))
                            .overlay{RoundedRectangle(cornerRadius:10).strokeBorder(isAdded(card) ? E.orange:.white.opacity(0.8))}
                    }.buttonStyle(NutritionExactPressStyle()).accessibilityIdentifier("exact.featured.add")
            }
        }.background{GeometryReader{geometry in
            ZStack(alignment:.trailing){E.secondaryCard;Button{details=card}label:{NutritionHomeArtwork(name:card.artwork,caption:diary.t("توضيحية","Illustration")).frame(width:124,height:geometry.size.height)}.buttonStyle(.plain).accessibilityLabel(diary.t("تفاصيل الوجبة؛ صورة توضيحية","Meal details; substitute illustration"))}
        }}.clipShape(RoundedRectangle(cornerRadius:22))
    }
    private var browse:some View {
        let byID=Dictionary(uniqueKeysWithValues:snapshot.browse.map{($0.id,$0)})
        let visible=(filteredIDs ?? []).compactMap{byID[$0]}
        return VStack(alignment:.leading,spacing:10){
            HStack{Text(diary.t("تصفح الوجبات","Browse Meals")).tracking(-0.35).nutritionFont(14,weight:.heavy);Spacer();HStack(spacing:6){Text(diary.t("محفوظاتك","Your saved meals")).nutritionFont(11,weight:.bold).foregroundStyle(E.secondary);NutritionExactIcon(name:"Wifi",size:14,color:E.orange)}}.padding(.top,4)
            if filteredIDs == nil{ProgressView().tint(E.orange).frame(maxWidth:.infinity,minHeight:54)}
            else if visible.isEmpty{
                Button{onSearch(query)}label:{VStack(alignment:.leading,spacing:6){Text(diary.t("لا توجد وجبات مطابقة","No matching meals")).nutritionFont(12.5,weight:.heavy);Text(diary.t("ابحث في قاعدة الطعام أو اختر عرض الكل","Search foods or choose See All")).nutritionFont(10.5,weight:.medium).foregroundStyle(E.muted)}.padding(12).frame(maxWidth:.infinity,alignment:.leading).nutritionPanel()}.buttonStyle(.plain)
            }
            LazyVStack(spacing:10){ForEach(visible){card in browseRow(card)}}
            Button(action:onHistory){Text(diary.t("تفاصيل السعرات خلال 7 أيام","Seven-day calorie details")).nutritionFont(11.5,weight:.bold).foregroundStyle(E.orangeLink).frame(maxWidth:.infinity,minHeight:44)}.buttonStyle(.plain).accessibilityIdentifier("diary.calorieDetails")
            NavigationLink{DiaryView(initialDate:date,showDetailedDiary:true)}label:{Text(diary.t("سجل اليوم وتفاصيل ماكروز الوجبات","Daily diary and meal macro details")).nutritionFont(11.5,weight:.bold).foregroundStyle(E.orangeLink).frame(maxWidth:.infinity,minHeight:44)}.buttonStyle(.plain).accessibilityIdentifier("exact.home.fullDiary")
        }
    }
    private func browseRow(_ card:NutritionHomeCard)->some View {
        Button{toggle(card)}label:{
            HStack(spacing:12){
                VStack(alignment:.leading,spacing:6){
                    Text(card.name(diary.language)).nutritionFont(12.5,weight:.heavy,lineHeight:1.375).fixedSize(horizontal:false,vertical:true)
                    HStack(spacing:8){
                        metadata("BrowseFlame",text:calories(card));Text("•").foregroundStyle(E.divider)
                        metadata("BrowseStar",text:card.rating.map{decimal($0,1)} ?? "—");Text("•").foregroundStyle(E.divider)
                        metadata("BrowseClock",text:time(card))
                    }.nutritionFont(10.5,weight:.semibold).foregroundStyle(E.metadata)
                    if card.isExample{Text(diary.t("مثال توضيحي — أكمل بياناته قبل التسجيل","Example — complete its data before logging")).nutritionFont(9,weight:.medium).foregroundStyle(E.muted)}
                }.frame(maxWidth:.infinity,alignment:.leading)
                NutritionHomeArtwork(name:card.artwork,caption:diary.t("توضيحية","Illustration")).frame(width:54,height:54).clipShape(RoundedRectangle(cornerRadius:14))
                    .overlay{if isAdded(card){RoundedRectangle(cornerRadius:14).fill(E.orange.opacity(0.8)).overlay{NutritionExactIcon(name:"CheckBold",size:20)}}}
            }.padding(12).padding(1).nutritionPanel(isAdded(card) ? E.activeCard:E.card,radius:18)
                .overlay{RoundedRectangle(cornerRadius:18).strokeBorder(isAdded(card) ? E.orange.opacity(0.6):.clear,lineWidth:1)}
        }.buttonStyle(NutritionExactPressStyle()).accessibilityIdentifier("exact.meal."+card.id)
            .accessibilityValue(diary.t(isAdded(card) ? "مضافة":"غير مضافة",isAdded(card) ? "Added":"Not added"))
            .contextMenu{Button(diary.t("تفاصيل الوجبة","Meal details")){details=card};if case .entry(let entry)=card.origin{Button(diary.t("تعديل الكمية","Edit quantity")){onEdit(entry)}}}
            .accessibilityAction(named:diary.t("تفاصيل الوجبة","Meal details")){details=card}
    }
    private func sectionHeader(_ title:String,action:String,onAction:@escaping ()->Void)->some View {
        HStack{Text(title).tracking(-0.35).nutritionFont(14,weight:.heavy).accessibilityAddTraits(.isHeader);Spacer();Button(action,action:onAction).nutritionFont(11.5,weight:.bold).foregroundStyle(E.orangeLink).buttonStyle(.plain)}
    }
    private func metadata(_ icon:String,text:String,color:Color=E.secondary)->some View {
        HStack(spacing:4){NutritionExactIcon(name:icon,size:12,color:icon.hasPrefix("Browse") ? nil:color);Text(DisplayFormat.westernDigits(text)).nutritionFont(10.5,weight:.semibold).lineLimit(1)}.foregroundStyle(color)
    }
    private func calories(_ card:NutritionHomeCard)->String{card.kcal.map{decimal($0,0)+"kcal"} ?? "—"}
    private func time(_ card:NutritionHomeCard)->String{card.preparationMinutes.map{String($0)+"min"} ?? "—"}
    private func isAdded(_ card:NutritionHomeCard)->Bool{card.matchingEntry(in:snapshot.entries,day:day) != nil}
    private func toggle(_ card:NutritionHomeCard){
        if let entry=card.matchingEntry(in:diary.state.entries,day:day){deleting=entry}
        else if let food=card.food{onFood(food)}
        else{seed=card;adding.wrappedValue=true}
    }
    private func drainPending(){
        seed=nil
        if let entry=pendingDelete{pendingDelete=nil;deleting=entry}
        else if let food=pendingFood{pendingFood=nil;onFood(food)}
        else if let entry=pendingEntry{pendingEntry=nil;onEdit(entry)}
        else if let card=pendingExample{pendingExample=nil;seed=card;adding.wrappedValue=true}
        else if pendingSearch{pendingSearch=false;onSearch(query)}
        else if pendingFullGoals{pendingFullGoals=false;onFullGoals()}
    }
    private func filterMeals() async {
        let index=snapshot.searchIndex,selected=category,text=query
        do{if !text.isEmpty{try await Task.sleep(for:.milliseconds(150))}}catch{return}
        guard !Task.isCancelled else{return}
        let worker=Task.detached(priority:.userInitiated){index.results(category:selected,query:text)}
        let matches=await withTaskCancellationHandler(operation:{await worker.value},onCancel:{worker.cancel()})
        guard !Task.isCancelled else{return}
        filteredIDs=matches
    }
}

/// Match max-width:62% and min-height:168 without an invented fixed hero height.
/// Text measures at its actual width, so long Arabic/Dynamic Type can grow.
private struct NutritionFeaturedLayout:Layout {
    var direction:LayoutDirection
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize {
        let width=proposal.width ?? 313
        let contentWidth=max(1,(width-32)*0.62)
        let content=subviews.first?.sizeThatFits(ProposedViewSize(width:contentWidth,height:nil)) ?? .zero
        return CGSize(width:width,height:max(168,content.height+32))
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        guard let content=subviews.first else{return}
        let width=max(1,(bounds.width-32)*0.62)
        let x=direction == .rightToLeft ? bounds.maxX-16-width:bounds.minX+16
        content.place(at:CGPoint(x:x,y:bounds.minY+16),anchor:.topLeading,proposal:ProposedViewSize(width:width,height:nil))
    }
}

private struct NutritionCalorieProgress:View {
    let consumed:Double
    let goal:Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body:some View {
        let fraction=min(1,max(0,consumed/max(1,goal)))
        return GeometryReader{geometry in
            ZStack(alignment:.leading){
                RoundedRectangle(cornerRadius:12).fill(E.sliderTrack)
                RoundedRectangle(cornerRadius:9).fill(E.orange).frame(width:max(0,(geometry.size.width-8)*fraction),height:22).padding(.horizontal,4)
                HStack(spacing:0){NutritionExactIcon(name:"ChevronLeft",size:10);NutritionExactIcon(name:"ChevronRight",size:10)}.frame(width:34,height:30).background(E.sliderThumb,in:RoundedRectangle(cornerRadius:10)).overlay{RoundedRectangle(cornerRadius:10).strokeBorder(.white,lineWidth:2)}
                    .offset(x:min(max(0,geometry.size.width*fraction-18),max(0,geometry.size.width-34)))
            }
        }.frame(height:30).environment(\.layoutDirection,.leftToRight).animation(reduceMotion ? nil:.easeOut(duration:0.15),value:fraction)
    }
}
