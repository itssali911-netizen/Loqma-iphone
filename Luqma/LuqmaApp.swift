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
    func applicationDidBecomeActive(_ application: UIApplication) {
        let services = AppServices.shared
        services.health.becameActive(services.diary)
    }
    func applicationDidEnterBackground(_ application: UIApplication) { AppServices.shared.health.enteredBackground() }
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
                .onChange(of:phase) { _,value in if value == .active {diary.adapt()} }
                .alert(diary.t("تنبيه","Notice"),isPresented:Binding(get:{diary.error != nil},set:{if !$0 {diary.error=nil}})) {Button(diary.t("حسنًا","OK")){diary.error=nil}} message:{Text(diary.error ?? "")}
        }
    }
}
struct RootView:View {
    @EnvironmentObject var diary:DiaryStore
    var body:some View {
        TabView {
            NavigationStack{DiaryView()}.tabItem{Label(diary.t("اليوم","Diary"),systemImage:"square.grid.2x2")}
            NavigationStack{KitchenView()}.tabItem{Label(diary.t("مطبخي","Kitchen"),systemImage:"fork.knife")}
            NavigationStack{ProgressViewScreen()}.tabItem{Label(diary.t("تقدّمي","Progress"),systemImage:"chart.xyaxis.line")}
            NavigationStack{SettingsView()}.tabItem{Label(diary.t("الإعدادات","Settings"),systemImage:"slider.horizontal.3")}
        }
    }
}
