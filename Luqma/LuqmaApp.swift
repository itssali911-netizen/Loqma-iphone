import SwiftUI

@main @MainActor struct LuqmaApp:App {
    @StateObject private var diary=DiaryStore()
    @StateObject private var health=HealthService()
    @Environment(\.scenePhase) private var phase
    var body:some Scene {
        WindowGroup {
            RootView().environmentObject(diary).environmentObject(health)
                .environment(\.layoutDirection,diary.language == .ar ? .rightToLeft:.leftToRight)
                .environment(\.locale,Locale(identifier:diary.language == .ar ? "ar_SA":"en_US"))
                .tint(Theme.accent).preferredColorScheme(.dark)
                .task { await health.sync(diary) }
                .onChange(of:phase) { _,value in if value == .active {diary.adapt();Task{await health.sync(diary)}} }
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
