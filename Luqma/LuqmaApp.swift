import SwiftUI
import UIKit

@MainActor final class AppServices {
    static let shared = AppServices()
    let diary = DiaryStore()
    init(){
        #if DEBUG
        // Only the isolated UI-test Simulator uses this flag; it is absent from Release.
        if CommandLine.arguments.contains("-loqma-ui-test-en") {diary.change{$0.language = .en}}
        #endif
    }
}

@MainActor final class DiaryAppDelegate: NSObject, UIApplicationDelegate {
    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        // A launch while locked must not replace the protected diary with an empty one.
        _ = AppServices.shared.diary.restoreAfterUnlock()
    }
}

@main @MainActor struct LuqmaApp:App {
    @UIApplicationDelegateAdaptor(DiaryAppDelegate.self) private var delegate
    @StateObject private var diary=AppServices.shared.diary
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
            RootView().luqmaFont(.body).foregroundStyle(Theme.text).environmentObject(diary)
                .environment(\.layoutDirection,diary.language == .ar ? .rightToLeft:.leftToRight)
                .environment(\.locale,DisplayFormat.locale(diary.language))
                .environment(\.calendar,DisplayFormat.calendar(diary.language))
                .tint(Theme.accent).preferredColorScheme(.dark)
                .onChange(of:phase, initial:true) { _,value in
                    if value == .active,diary.restoreAfterUnlock() { diary.adapt() }
                }
                .alert(diary.t("تنبيه","Notice"),isPresented:Binding(get:{diary.error != nil},set:{if !$0 {diary.error=nil}})) {Button(diary.t("حسنًا","OK")){diary.error=nil}} message:{Text(diary.error ?? "")}
        }
    }
}
struct RootView:View {
    @EnvironmentObject var diary:DiaryStore
    @State private var tab:Int
    @State private var adding=false
    @State private var photoPreview=false
    @State private var recipePreview=false
    @State private var searchPreview=false
    @State private var mealsPreview=false
    #if DEBUG
    @Environment(\.dynamicTypeSize) private var typeSize
    private enum TemplatePreviewRoute:String,Identifiable {
        case goals,portion,recipe,recipeDetail,plan,weight,connection,backup,about,barcode,language
        var id:String{rawValue}
    }
    @State private var templatePreview:TemplatePreviewRoute?
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
            NavigationStack{DiaryView().toolbar(.hidden,for:.tabBar)}.tabItem{Label(diary.t("اليوم","Today"),systemImage:"house")}.tag(0)
            NavigationStack{KitchenView().toolbar(.hidden,for:.tabBar)}.tabItem{Label(diary.t("مطبخي","Kitchen"),systemImage:"fork.knife")}.tag(1)
            NavigationStack{ProgressViewScreen().toolbar(.hidden,for:.tabBar)}.tabItem{Label(diary.t("تقدّمي","Progress"),systemImage:"chart.bar")}.tag(2)
            NavigationStack{SettingsView(onBack:{tab=0}).toolbar(.hidden,for:.tabBar)}.tabItem{Label(diary.t("الإعدادات","Settings"),systemImage:"gearshape")}.tag(3)
        }.toolbar(.hidden,for:.tabBar)
            .safeAreaInset(edge:.bottom,spacing:0){bottomNavigation}
            .fullScreenCover(isPresented:$adding){FoodAddView(onPhotoCommit:{foods,meal in
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
            #if DEBUG
            .sheet(item:$templatePreview){route in templatePreviewContent(route)}
            .environment(\.dynamicTypeSize,ProcessInfo.processInfo.arguments.contains("-loqma-preview-accessibility") ? .accessibility3:typeSize)
            #endif
    }
    #if DEBUG
    @ViewBuilder private func templatePreviewContent(_ route:TemplatePreviewRoute)->some View {
        Group{
            switch route {
            case .goals:GoalEditor()
            case .portion:FoodPortionView(food:previewPortionFood){_,_,_,_ in false}
            case .recipe:RecipeEditor(recipe:previewRecipe)
            case .recipeDetail:RecipeDetailView(recipeID:previewRecipe.id,previewRecipe:previewRecipe)
            case .plan:NavigationStack{PlanView().navigationBarTitleDisplayMode(.inline)}
            case .weight:WeightEditor()
            case .connection:GeminiSettingsView()
            case .backup:NavigationStack{BackupSettingsView().navigationBarTitleDisplayMode(.inline)}
            case .about:NavigationStack{AboutLuqmaView().navigationBarTitleDisplayMode(.inline)}
            case .language:NavigationStack{LuqmaLanguageView()}
            case .barcode:NavigationStack{
                BarcodeScanGuide(language:diary.language).background(Theme.surface).ignoresSafeArea()
                    .sandowNavigation(diary.t("مسح الباركود","Scan barcode"),backLabel:diary.t("إغلاق","Close"))
                    .safeAreaInset(edge:.bottom){Text(diary.t("معاينة للمؤشر فقط؛ الكاميرا غير مشغّلة","Guide preview only; camera is inactive")).luqmaFont(.caption).foregroundStyle(Theme.text).multilineTextAlignment(.center).padding(16).frame(maxWidth:.infinity).background(Theme.background)}
            }
            }
        }.allowsHitTesting(false)
    }
    private var previewPortionFood:Food {
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
    private var bottomNavigation:some View {
        HStack(alignment:.center,spacing:4){
            navigationButton(0,title:diary.t("اليوم","Today"),symbol:"house")
            navigationButton(1,title:diary.t("مطبخي","Kitchen"),symbol:"fork.knife")
            Button{adding=true}label:{Image(systemName:"plus").font(.system(size:27,weight:.medium)).foregroundStyle(Theme.text).frame(width:54,height:54).background(Theme.accent,in:RoundedRectangle(cornerRadius:17,style:.continuous))}.buttonStyle(.plain).frame(maxWidth:.infinity,minHeight:54).accessibilityLabel(diary.t("إضافة طعام إلى اليوم","Add food to today")).accessibilityIdentifier("nav.add")
            navigationButton(2,title:diary.t("تقدّمي","Progress"),symbol:"chart.bar")
            navigationButton(3,title:diary.t("الإعدادات","Settings"),symbol:"gearshape")
        }.padding(.horizontal,10).padding(.vertical,6)
            .background(Theme.surface,in:RoundedRectangle(cornerRadius:24,style:.continuous))
            .padding(.horizontal,16).padding(.top,6).padding(.bottom,4).background(Theme.background)
    }
    private func navigationButton(_ value:Int,title:String,symbol:String)->some View {
        Button{tab=value}label:{VStack(spacing:3){
            Image(systemName:tab == value && value == 0 ? "house.fill":symbol).font(.system(size:21,weight:.regular))
                .foregroundStyle(tab == value ? Theme.text:Theme.muted).frame(width:44,height:34)
                .background(tab == value ? Theme.background:Color.clear,in:RoundedRectangle(cornerRadius:12,style:.continuous))
            Capsule().fill(tab == value ? Theme.accent:Color.clear).frame(width:18,height:3)
        }.frame(maxWidth:.infinity,minHeight:54).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityLabel(title).accessibilityAddTraits(tab == value ? .isSelected:[])
            .accessibilityIdentifier(["nav.today","nav.kitchen","nav.progress","nav.settings"][value])
    }
}
