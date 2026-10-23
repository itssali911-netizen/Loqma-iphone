import SwiftUI
import UIKit

@MainActor final class AppServices {
    static let shared = AppServices()
    let diary = DiaryStore()
    let reminders = ReminderService()
    #if DEBUG && targetEnvironment(simulator)
    private(set) var performanceFixtureIdentity: String?
    #endif
    init(){
        #if DEBUG
        // Only the isolated UI-test Simulator uses this flag; it is absent from Release.
        if CommandLine.arguments.contains("-loqma-ui-test-en"), diary.language != .en {diary.change{$0.language = .en}}
        #if targetEnvironment(simulator)
        performanceFixtureIdentity = LuqmaPerformanceFixture.prepare(diary)
        #endif
        #endif
    }
}

@MainActor final class DiaryAppDelegate: NSObject, UIApplicationDelegate {
    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        // A launch while locked must not replace the protected diary with an empty one.
        _ = AppServices.shared.diary.restoreAfterUnlock()
        Task{await AppServices.shared.reminders.refresh(language:AppServices.shared.diary.language)}
    }
}

@main @MainActor struct LuqmaApp:App {
    @UIApplicationDelegateAdaptor(DiaryAppDelegate.self) private var delegate
    @StateObject private var diary=AppServices.shared.diary
    @StateObject private var reminders=AppServices.shared.reminders
    @Environment(\.scenePhase) private var phase
    init(){
        let navigation=UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor=UIColor(Theme.background)
        navigation.titleTextAttributes=[.foregroundColor:UIColor(Theme.text),.font:LTypography.uiFont(size:18,weight:.bold,relativeTo:.headline)]
        navigation.largeTitleTextAttributes=[.foregroundColor:UIColor(Theme.text),.font:LTypography.uiFont(size:22,weight:.heavy,relativeTo:.title1)]
        UINavigationBar.appearance().standardAppearance=navigation
        UINavigationBar.appearance().scrollEdgeAppearance=navigation
        UISegmentedControl.appearance().selectedSegmentTintColor=UIColor(Theme.text)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor:UIColor(Theme.background),.font:LTypography.uiFont(size:14,weight:.bold,relativeTo:.subheadline)],for:.selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor:UIColor(Theme.muted),.font:LTypography.uiFont(size:14,relativeTo:.subheadline)],for:.normal)
    }
    var body:some Scene {
        WindowGroup {
            RootView().luqmaFont(.body).foregroundStyle(Theme.text).environmentObject(diary).environmentObject(reminders)
                .environment(\.layoutDirection,diary.language == .ar ? .rightToLeft:.leftToRight)
                .environment(\.locale,DisplayFormat.locale(diary.language))
                .environment(\.calendar,DisplayFormat.calendar(diary.language))
                .tint(Theme.accent).preferredColorScheme(.dark)
                .onChange(of:phase, initial:true) { _,value in
                    if value == .active{
                        if diary.restoreAfterUnlock(){diary.adapt()}
                        Task{await reminders.refresh(language:diary.language)}
                    }
                }
                .onChange(of:diary.language){_,language in Task{await reminders.refresh(language:language)}}
                .onReceive(NotificationCenter.default.publisher(for:NSNotification.Name.NSSystemTimeZoneDidChange)){_ in Task{await reminders.refresh(language:diary.language)}}
                .alert(diary.t("تنبيه","Notice"),isPresented:Binding(get:{diary.error != nil},set:{if !$0 {diary.error=nil}})) {Button(diary.t("حسنًا","OK")){diary.error=nil}} message:{Text(diary.error ?? "")}
        }
    }
}
struct RootView:View {
    @EnvironmentObject var diary:DiaryStore
    @EnvironmentObject var reminders:ReminderService
    @State private var tab:Int
    @State private var adding=false
    @State private var addingMeal:Meal?
    @State private var todayRouteID=0
    @State private var photoPreview=false
    @State private var recipePreview=false
    @State private var searchPreview=false
    @State private var mealsPreview=false
    #if DEBUG
    @Environment(\.dynamicTypeSize) private var typeSize
    private enum TemplatePreviewRoute:String,Identifiable {
        case goals,portion,recipe,recipeDetail,plan,weight,connection,backup,about,barcode,language,notifications,reminders,stateError,stateLoading,stateEmpty,stateSuccess
        case assessmentGoal,assessmentGender,assessmentActivity,assessmentDetails,assessmentReview,fitnessProfile,fitnessPlan
        case approvedHome,calorieDetails,approvedPhotoScan,approvedPhotoResults
        var id:String{rawValue}
    }
    @State private var templatePreview:TemplatePreviewRoute?
    @StateObject private var fitnessPreviewStore=DiaryStore(previewSnapshot:FitnessPreviewData.snapshot)
    @StateObject private var approvedPreviewStore=DiaryStore(previewSnapshot:ApprovedScreenPreviewData.snapshot)
    @State private var approvedDate=Date()
    #endif
    init(){
        var selected=0
        #if DEBUG
        let arguments=ProcessInfo.processInfo.arguments
        _photoPreview=State(initialValue:arguments.contains("-loqma-preview-photo"))
        _recipePreview=State(initialValue:arguments.contains("-loqma-preview-recipe"))
        _searchPreview=State(initialValue:arguments.contains("-loqma-preview-search"))
        _mealsPreview=State(initialValue:arguments.contains("-loqma-preview-meals"))
        if let index=arguments.firstIndex(of:"-loqma-preview-template"),arguments.indices.contains(index+1){
            _templatePreview=State(initialValue:TemplatePreviewRoute(rawValue:arguments[index+1]))
        }
        if let index=arguments.firstIndex(of:"-loqma-preview-tab"),arguments.indices.contains(index+1),let value=Int(arguments[index+1]),(0...3).contains(value){selected=value}
        #endif
        _tab=State(initialValue:selected)
    }
    var body:some View {
        TabView(selection:$tab) {
            NavigationStack{DiaryView().id(todayRouteID).toolbar(.hidden,for:.tabBar)}.tabItem{Label(diary.t("اليوم","Today"),systemImage:"house")}.tag(0)
            NavigationStack{KitchenView().toolbar(.hidden,for:.tabBar)}.tabItem{Label(diary.t("مطبخي","Kitchen"),systemImage:"fork.knife")}.tag(1)
            NavigationStack{ProgressViewScreen().toolbar(.hidden,for:.tabBar)}.tabItem{Label(diary.t("تقدّمي","Progress"),systemImage:"chart.bar")}.tag(2)
            NavigationStack{SettingsView(onBack:{tab=0}).toolbar(.hidden,for:.tabBar)}.tabItem{Label(diary.t("الإعدادات","Settings"),systemImage:"gearshape")}.tag(3)
        }.toolbar(.hidden,for:.tabBar)
            #if DEBUG && targetEnvironment(simulator)
            .modifier(LuqmaPerformanceMarker())
            #endif
            .safeAreaInset(edge:.bottom,spacing:0){bottomNavigation}
            .fullScreenCover(isPresented:$adding,onDismiss:{addingMeal=nil;consumeReminderRoute()}){FoodAddView(initialMeal:addingMeal,onPhotoCommit:{foods,meal in
                do{let entries=try foods.map{try DiaryEntry(food:$0.0,amount:$0.1,unit:$0.2,meal:meal,day:DayKey.today,language:diary.language)};return diary.add(entries,foods:foods.map{$0.0})}catch{diary.report(error);return false}
            }){food,amount,unit,meal in
                do{return diary.add([try DiaryEntry(food:food,amount:amount,unit:unit,meal:meal,day:DayKey.today,language:diary.language)],foods:[food])}catch{diary.report(error);return false}
            }}
            .sheet(isPresented:$photoPreview){
                #if DEBUG
                NavigationStack{ScrollViewReader{proxy in
                    ScrollView{PhotoMealView{_,_ in false}.padding(16)}.appBackground()
                        .task{if ProcessInfo.processInfo.arguments.contains("-loqma-preview-photo-detailed"){
                            try? await Task.sleep(for:.milliseconds(400))
                            proxy.scrollTo("photo-components",anchor:.top)
                        }}
                }.sandowNavigation(diary.t("تحليل الوجبة","Meal analysis"),backLabel:diary.t("إغلاق","Close"),onBack:{photoPreview=false})}
                #endif
            }
            .sheet(isPresented:$recipePreview){
                #if DEBUG
                RecipeImportView()
                #endif
            }
            .fullScreenCover(isPresented:$searchPreview){
                #if DEBUG
                FoodAddView(initialQuery:"التنمية صدر دجاج"){_,_,_,_ in false}
                #endif
            }
            .fullScreenCover(isPresented:$mealsPreview){
                #if DEBUG
                NavigationStack{DiaryView()}
                #endif
            }
            .task(id:reminders.pendingRoute){
                // A notification tap must not discard an open recipe/food draft.
                // Keep the requested destination queued until the current modal closes.
                while reminders.pendingRoute != nil,!Task.isCancelled{
                    if !hasPresentedModal{consumeReminderRoute()}
                    if reminders.pendingRoute != nil{try? await Task.sleep(for:.milliseconds(400))}
                }
            }
            #if DEBUG
            .sheet(item:$templatePreview){route in
                templatePreviewContent(route)
                    .luqmaFont(.body)
                    .modifier(NativePreviewFontAudit(scope:"template"))
                    .environment(\.dynamicTypeSize,previewDynamicTypeSize)
            }
            .luqmaFont(.body)
            .modifier(NativePreviewFontAudit(scope:"root",enabled:templatePreview == nil))
            .environment(\.dynamicTypeSize,ProcessInfo.processInfo.arguments.contains("-loqma-preview-accessibility") ? .accessibility3:typeSize)
            #endif
    }
    #if DEBUG
    @ViewBuilder private func templatePreviewContent(_ route:TemplatePreviewRoute)->some View {
        Group{
            switch route {
            case .goals:GoalEditor()
            case .portion:FoodPortionView(food:previewPortionFood,initialMeal:ProcessInfo.processInfo.arguments.contains("-loqma-approved-capture") ? .lunch:nil){_,_,_,_ in false}
            case .recipe:RecipeEditor(recipe:previewRecipe)
            case .recipeDetail:RecipeDetailView(recipeID:previewRecipe.id,previewRecipe:previewRecipe)
            case .plan:NavigationStack{PlanView().navigationBarTitleDisplayMode(.inline)}
            case .weight:WeightEditor()
            case .connection:GeminiSettingsView()
            case .backup:NavigationStack{BackupSettingsView().navigationBarTitleDisplayMode(.inline)}
            case .about:NavigationStack{AboutLuqmaView().navigationBarTitleDisplayMode(.inline)}
            case .language:NavigationStack{LuqmaLanguageView()}
            case .notifications:NavigationStack{NotificationsView()}
            case .reminders:NavigationStack{RemindersView()}
            case .assessmentGoal:FitnessAssessmentView(previewPage:assessmentPreviewPage)
            case .assessmentGender:FitnessAssessmentView(previewPage:2)
            case .assessmentActivity:FitnessAssessmentView(previewPage:7)
            case .assessmentDetails:FitnessAssessmentView(previewPage:9)
            case .assessmentReview:FitnessAssessmentView(previewPage:10)
            case .fitnessProfile:fitnessFixture{FitnessProfileView()}
            case .fitnessPlan:fitnessFixture{FitnessPlanReviewView()}
            case .approvedHome:approvedDiaryFixture{DiaryView().safeAreaInset(edge:.bottom,spacing:0){bottomNavigation}}
            case .calorieDetails:approvedDiaryFixture{CalorieIntakeDetailView(selectedDate:$approvedDate)}
            case .approvedPhotoScan:ScrollView(showsIndicators:false){PhotoMealView{_,_ in false}.padding(.horizontal,16)}.appBackground()
            case .approvedPhotoResults:ScrollView(showsIndicators:false){PhotoMealView{_,_ in false}.padding(.horizontal,16)}.appBackground().ignoresSafeArea(.container,edges:.top)
            case .stateError:statePreview{SandowStateAlert(text:diary.t("تعذّر إكمال الطلب. تحقق من الاتصال وحاول مجددًا.","The request could not be completed. Check your connection and retry."))}
            case .stateLoading:statePreview{SandowOperationState(title:diary.t("تقدير المكونات والسعرات…","Estimating components and calories…"),cancelLabel:diary.t("إلغاء","Cancel"),onCancel:{})}
            case .stateEmpty:statePreview{SandowEmptyState(title:diary.t("لا توجد نتائج","No results"),message:diary.t("جرّب اسمًا آخر أو غيّر كلمات البحث.","Try another name or change your search words."))}
            case .stateSuccess:statePreview{SandowSavedConfirmation(text:diary.t("حُفظ وقت التذكير.","Reminder time saved."))}
            case .barcode:NavigationStack{
                BarcodeScanGuide(language:diary.language).background(Theme.surface).ignoresSafeArea()
                    .sandowNavigation(diary.t("مسح الباركود","Scan barcode"),backLabel:diary.t("إغلاق","Close"))
                    .safeAreaInset(edge:.bottom){Text(diary.t("معاينة للمؤشر فقط؛ الكاميرا غير مشغّلة","Guide preview only; camera is inactive")).luqmaFont(.caption).foregroundStyle(Theme.text).multilineTextAlignment(.center).padding(16).frame(maxWidth:.infinity).background(Theme.background)}
            }
            }
        }.allowsHitTesting(false)
    }
    private func fitnessFixture<Content:View>(@ViewBuilder content:()->Content)->some View {
        NavigationStack{VStack(spacing:0){
            if !ProcessInfo.processInfo.arguments.contains("-loqma-approved-capture") {
                Notice(text:diary.t("مثال للعرض فقط؛ لا يُحفظ هذا الملف في سجلّك.","Display example only; this profile is not saved to your diary.")).padding(16)
            }
            content()
        }}.environmentObject(fitnessPreviewStore)
            .onAppear{fitnessPreviewStore.change{$0.language=diary.language}}
    }
    private func approvedDiaryFixture<Content:View>(@ViewBuilder content:()->Content)->some View {
        NavigationStack{content()}.environmentObject(approvedPreviewStore)
            .onAppear{approvedPreviewStore.change{$0.language=diary.language}}
    }
    private var assessmentPreviewPage:Int {
        let arguments=ProcessInfo.processInfo.arguments
        guard let index=arguments.firstIndex(of:"-loqma-preview-assessment-page"),arguments.indices.contains(index+1),
              let value=Int(arguments[index+1]),(0...10).contains(value) else{return 0}
        return value
    }
    private var previewDynamicTypeSize:DynamicTypeSize {
        ProcessInfo.processInfo.arguments.contains("-loqma-preview-accessibility") ? .accessibility3:typeSize
    }
    private func statePreview<Content:View>(@ViewBuilder content:()->Content)->some View {
        NavigationStack{ScrollView{VStack(spacing:24){
            Notice(text:diary.t("معاينة لحالة الواجهة فقط؛ لم تنفّذ عملية أو تحفظ بيانات.","Interface-state preview only; no operation ran and no data was saved."))
            content()
        }.padding(16)}.appBackground().sandowNavigation(diary.t("معاينة الحالة","State preview"),backLabel:diary.t("إغلاق","Close"))}
    }
    private var previewPortionFood:Food {
        if ProcessInfo.processInfo.arguments.contains("-loqma-approved-capture") {
            // Read-only synthetic reference fixture; provenance is recorded in
            // the capture JSON/gallery rather than appended to visible labels.
            let serving=Nutrition(kcal:114,protein:2.4,carbs:24,fat:0.7)
            return Food(catalogID:"preview:approved-cereal",name:"Gold Corn flakes",nameEn:"Gold Corn flakes",brand:"Nestlé, Fitness",unit:.g,
                nutrition:serving.scaled(100.0/30.0),serving:"30.0 g",servingQuantity:30,servingUnit:"g",servingNutrition:serving,source:"Preview fixture")
        }
        let serving=Nutrition(kcal:124,protein:17,carbs:8,fat:2.66)
        return Food(catalogID:"preview:serving",name:"زبادي يوناني — مثال للعرض فقط",nameEn:"Greek yogurt — display example only",unit:.g,
            nutrition:serving.scaled(100.0/150.0),serving:diary.t("حصة 150 جم · مثال للعرض فقط","150 g serving · display example only"),
            servingQuantity:150,servingUnit:"g",servingNutrition:serving,source:"Preview fixture")
    }
    private var previewRecipe:Recipe {
        let ingredients=[
            Ingredient(id:UUID(),name:diary.t("دجاج مطهو","Cooked chicken"),amount:100,unit:.g,kcal:165,protein:31,carbs:0,fat:4.55),
            Ingredient(id:UUID(),name:diary.t("أرز مطهو","Cooked rice"),amount:100,unit:.g,kcal:128,protein:2,carbs:29.5,fat:0.22)
        ]
        return Recipe(id:UUID(),name:diary.t("أرز بالدجاج — مثال للعرض فقط","Chicken and rice — display example only"),type:"recipe",ingredients:ingredients,
            portions:2,cookedWeight:200,notes:diary.t("مثال للعرض فقط؛ لا يُحفظ في سجلّك ولا يستخدم التحليل.","Display example only; it is not saved to your diary and uses no analysis request."))
    }
    #endif
    private func consumeReminderRoute(){
        guard let kind=reminders.pendingRoute,!adding,!hasPresentedModal else{return}
        reminders.pendingRoute=nil;tab=0;todayRouteID+=1
        if let meal=kind.meal{addingMeal=meal;adding=true}
    }
    private var hasPresentedModal:Bool {
        UIApplication.shared.connectedScenes.compactMap{$0 as? UIWindowScene}.flatMap(\.windows)
            .first(where:{$0.isKeyWindow})?.rootViewController?.presentedViewController != nil
    }
    private var bottomNavigation:some View {
        HStack(alignment:.center,spacing:4){
            navigationButton(0,title:diary.t("اليوم","Today"),symbol:"house")
            navigationButton(1,title:diary.t("مطبخي","Kitchen"),symbol:"fork.knife")
            Button{addingMeal=nil;adding=true}label:{Image(systemName:"plus").font(.system(size:27,weight:.medium)).foregroundStyle(Theme.onAccent).frame(width:Theme.bottomBarItemHeight,height:Theme.bottomBarItemHeight).background(Theme.accent,in:RoundedRectangle(cornerRadius:17,style:.continuous))}.buttonStyle(.plain).frame(maxWidth:.infinity,minHeight:Theme.bottomBarItemHeight).accessibilityLabel(diary.t("إضافة طعام إلى اليوم","Add food to today")).accessibilityIdentifier("nav.add")
            navigationButton(2,title:diary.t("تقدّمي","Progress"),symbol:"chart.bar")
            navigationButton(3,title:diary.t("الإعدادات","Settings"),symbol:"gearshape")
        }.padding(.horizontal,10).padding(.vertical,Theme.bottomBarPadding)
            .background(Theme.surface,in:RoundedRectangle(cornerRadius:24,style:.continuous))
            .padding(.horizontal,16).padding(.top,Theme.bottomBarTopGap).padding(.bottom,Theme.bottomBarBottomGap).background(Theme.background)
    }
    private func navigationButton(_ value:Int,title:String,symbol:String)->some View {
        Button{tab=value}label:{VStack(spacing:3){
            Image(systemName:tab == value && value == 0 ? "house.fill":symbol).font(.system(size:21,weight:.regular))
                .foregroundStyle(tab == value ? Theme.text:Theme.muted).frame(width:44,height:34)
                .background(tab == value ? Theme.background:Color.clear,in:RoundedRectangle(cornerRadius:12,style:.continuous))
            Capsule().fill(tab == value ? Theme.accent:Color.clear).frame(width:18,height:3)
        }.frame(maxWidth:.infinity,minHeight:Theme.bottomBarItemHeight).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityLabel(title).accessibilityAddTraits(tab == value ? .isSelected:[])
            .accessibilityIdentifier(["nav.today","nav.kitchen","nav.progress","nav.settings"][value])
    }
}

#if DEBUG
/// Disposable read-only capture data; never a real meal or remote analysis.
private enum ApprovedScreenPreviewData {
    static var snapshot:DiarySnapshot {
        var result=FitnessPreviewData.snapshot
        let food=Food(catalogID:"preview:approved-diary",name:"وجبة توضيحية",nameEn:"Display meal",unit:.serving,
                      nutrition:Nutrition(kcal:100,protein:10,carbs:15,fat:0),serving:"1 serving",source:"Preview fixture")
        let calendar=DisplayFormat.calendar(.en)
        // Seven distinct illustrative daily totals exercise the real curved
        // chart. These DEBUG-only values never enter a user's saved diary or
        // the separately frozen performance fixture.
        let calories=[429,310,475,285,390,220,350]
        for offset in 0..<calories.count {
            if let date=calendar.date(byAdding:.day,value:-offset,to:Date()),
               let entry=try? DiaryEntry(food:food,amount:Double(calories[offset])/100,unit:.serving,meal:.breakfast,day:DayKey.string(date),language:.ar) {
                result.entries.append(entry)
            }
        }
        return result
    }
}
#endif

#if DEBUG
/// Read from the rendered subtree, including presentation boundaries. Command
/// arguments request a preview size but are not evidence that it was received.
private struct NativePreviewFontAudit:ViewModifier {
    let scope:String
    var enabled=true
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo:.body) private var bodyPoints:CGFloat=16

    func body(content:Content)->some View {
        content.task(id:typeSize){writeAudit()}
    }
    private var observedSize:(name:String,category:UIContentSizeCategory) {
        switch typeSize {
        case .xSmall:return ("xSmall",.extraSmall)
        case .small:return ("small",.small)
        case .medium:return ("medium",.medium)
        case .large:return ("large",.large)
        case .xLarge:return ("xLarge",.extraLarge)
        case .xxLarge:return ("xxLarge",.extraExtraLarge)
        case .xxxLarge:return ("xxxLarge",.extraExtraExtraLarge)
        case .accessibility1:return ("accessibility1",.accessibilityMedium)
        case .accessibility2:return ("accessibility2",.accessibilityLarge)
        case .accessibility3:return ("accessibility3",.accessibilityExtraLarge)
        case .accessibility4:return ("accessibility4",.accessibilityExtraExtraLarge)
        case .accessibility5:return ("accessibility5",.accessibilityExtraExtraExtraLarge)
        @unknown default:return ("unrecognized",.large)
        }
    }
    @MainActor private func writeAudit(){
        guard enabled,ProcessInfo.processInfo.arguments.contains("-loqma-preview-font-audit") else{return}
        do{
            let data=try JSONEncoder().encode(LTypography.runtimeFontAudit(category:observedSize.category))
            let audit=try JSONSerialization.jsonObject(with:data)
            let contrasts=try JSONSerialization.jsonObject(with:JSONEncoder().encode(VisualDesignTokens.contrastAudit))
            let envelope:[String:Any]=[
                "processIdentifier":ProcessInfo.processInfo.processIdentifier,
                "fontAudit":audit,"contrastAudit":contrasts,"renderingScope":scope,
                "swiftUIDynamicTypeSize":observedSize.name,
                "swiftUIIsAccessibilitySize":typeSize.isAccessibilitySize,
                "swiftUIBodyPoints":Double(bodyPoints)
            ]
            let encoded=try JSONSerialization.data(withJSONObject:envelope,options:[.prettyPrinted,.sortedKeys])
            let folder=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0]
            try encoded.write(to:folder.appendingPathComponent("luqma-font-audit.json"),options:.atomic)
        }catch{print("Native font audit could not be written.")}
    }
}
#endif
