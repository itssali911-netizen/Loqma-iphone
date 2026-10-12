import SwiftUI
import UIKit

@MainActor final class AppServices {
    static let shared = AppServices()
    let diary = DiaryStore()
    let health = HealthService()
}

@MainActor final class HealthAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let services = AppServices.shared
        services.health.prepare(services.diary)
        return true
    }
    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        let services = AppServices.shared
        services.health.unlocked(services.diary)
    }
}

@main @MainActor struct LuqmaApp:App {
    @UIApplicationDelegateAdaptor(HealthAppDelegate.self) private var delegate
    @StateObject private var diary=AppServices.shared.diary
    @StateObject private var health=AppServices.shared.health
    @Environment(\.scenePhase) private var phase
    init(){
        let navigation=UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor=UIColor(Theme.background)
        navigation.titleTextAttributes=[.foregroundColor:UIColor(Theme.text)]
        navigation.largeTitleTextAttributes=[.foregroundColor:UIColor(Theme.text)]
        UINavigationBar.appearance().standardAppearance=navigation
        UINavigationBar.appearance().scrollEdgeAppearance=navigation
        UISegmentedControl.appearance().selectedSegmentTintColor=UIColor(Theme.text)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor:UIColor(Theme.card)],for:.selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor:UIColor(Theme.muted)],for:.normal)
    }
    var body:some Scene {
        WindowGroup {
            RootView().foregroundStyle(Theme.text).environmentObject(diary).environmentObject(health)
                .environment(\.layoutDirection,diary.language == .ar ? .rightToLeft:.leftToRight)
                .environment(\.locale,Locale(identifier:diary.language == .ar ? "ar_SA":"en_US"))
                .tint(Theme.accent).preferredColorScheme(.dark)
                .onChange(of:phase, initial:true) { _,value in
                    // SwiftUI scenes own foreground transitions; app-delegate launch
                    // registration remains synchronous for HealthKit background delivery.
                    if value == .active { diary.adapt(); health.becameActive(diary) }
                    else if value == .background { health.enteredBackground() }
                }
                .alert(diary.t("تنبيه","Notice"),isPresented:Binding(get:{diary.error != nil},set:{if !$0 {diary.error=nil}})) {Button(diary.t("حسنًا","OK")){diary.error=nil}} message:{Text(diary.error ?? "")}
        }
    }
}
struct RootView:View {
    @EnvironmentObject var diary:DiaryStore
    @State private var tab:Int
    @State private var adding=false
    init(){
        var selected=0
        #if DEBUG
        let arguments=ProcessInfo.processInfo.arguments
        if let index=arguments.firstIndex(of:"-loqma-preview-tab"),arguments.indices.contains(index+1),let value=Int(arguments[index+1]),(0...3).contains(value){selected=value}
        #endif
        _tab=State(initialValue:selected)
    }
    var body:some View {
        TabView(selection:$tab) {
            NavigationStack{DiaryView()}.tabItem{Label(diary.t("اليوم","Today"),systemImage:"house")}.tag(0)
            NavigationStack{KitchenView()}.tabItem{Label(diary.t("مطبخي","Kitchen"),systemImage:"fork.knife")}.tag(1)
            NavigationStack{ProgressViewScreen()}.tabItem{Label(diary.t("تقدّمي","Progress"),systemImage:"chart.bar")}.tag(2)
            NavigationStack{SettingsView()}.tabItem{Label(diary.t("الإعدادات","Settings"),systemImage:"gearshape")}.tag(3)
        }.toolbar(.hidden,for:.tabBar)
            .safeAreaInset(edge:.bottom,spacing:0){bottomNavigation}
            .sheet(isPresented:$adding){FoodAddView(onPhotoCommit:{foods,meal in
                do{let entries=try foods.map{try DiaryEntry(food:$0.0,amount:$0.1,unit:$0.2,meal:meal,day:DayKey.today,language:diary.language)};return diary.add(entries,foods:foods.map{$0.0})}catch{diary.report(error);return false}
            }){food,amount,unit,meal in
                do{return diary.add([try DiaryEntry(food:food,amount:amount,unit:unit,meal:meal,day:DayKey.today,language:diary.language)],foods:[food])}catch{diary.report(error);return false}
            }}
    }
    private var bottomNavigation:some View {
        HStack(alignment:.center,spacing:4){
            navigationButton(0,title:diary.t("اليوم","Today"),symbol:"house")
            navigationButton(1,title:diary.t("مطبخي","Kitchen"),symbol:"fork.knife")
            Button{adding=true}label:{Image(systemName:"plus").font(.system(size:27,weight:.light)).foregroundStyle(Theme.card).frame(width:52,height:52).background(Theme.text,in:RoundedRectangle(cornerRadius:17))}.buttonStyle(.plain).frame(maxWidth:.infinity).accessibilityLabel(diary.t("إضافة طعام إلى اليوم","Add food to today"))
            navigationButton(2,title:diary.t("تقدّمي","Progress"),symbol:"chart.bar")
            navigationButton(3,title:diary.t("الإعدادات","Settings"),symbol:"gearshape")
        }.padding(.horizontal,14).padding(.top,14).padding(.bottom,8)
            .background(Theme.card,in:UnevenRoundedRectangle(topLeadingRadius:24,topTrailingRadius:24))
            .overlay(alignment:.top){Rectangle().fill(Theme.stroke).frame(height:0.5).padding(.horizontal,24)}
            .background(Theme.card.ignoresSafeArea(edges:.bottom))
    }
    private func navigationButton(_ value:Int,title:String,symbol:String)->some View {
        Button{tab=value}label:{VStack(spacing:7){
            Image(systemName:tab == value && value == 0 ? "house.fill":symbol).font(.system(size:22,weight:.regular)).frame(height:24)
                .shadow(color:tab == value ? Theme.accent.opacity(0.55):.clear,radius:10,y:5)
            Text(title).font(.system(size:10,weight:tab == value ? .semibold:.regular)).lineLimit(1).minimumScaleFactor(0.75)
            Capsule().fill(tab == value ? Theme.accent:Color.clear).frame(width:18,height:3)
        }.foregroundStyle(tab == value ? Theme.text:Theme.muted).frame(maxWidth:.infinity,minHeight:54).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityAddTraits(tab == value ? .isSelected:[])
    }
}
