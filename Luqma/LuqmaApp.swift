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
    var body:some Scene {
        WindowGroup {
            RootView().environmentObject(diary).environmentObject(health)
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
    var body:some View {
        TabView {
            NavigationStack{DiaryView().toolbar{settingsLink}}.tabItem{Label(diary.t("اليوم","Today"),systemImage:"square.grid.2x2")}
            NavigationStack{KitchenView().toolbar{settingsLink}}.tabItem{Label(diary.t("مطبخي","Kitchen"),systemImage:"fork.knife")}
            NavigationStack{ProgressViewScreen().toolbar{settingsLink}}.tabItem{Label(diary.t("تقدّمي","Progress"),systemImage:"chart.xyaxis.line")}
        }
    }
    private var settingsLink:some ToolbarContent {
        ToolbarItem(placement:.topBarTrailing){
            NavigationLink{SettingsView()}label:{Image(systemName:"gearshape")}
                .accessibilityLabel(diary.t("الإعدادات","Settings"))
        }
    }
}
