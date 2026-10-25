import SwiftUI
import UIKit

struct RemindersView:View {
    @EnvironmentObject private var diary:DiaryStore
    @EnvironmentObject private var reminders:ReminderService
    @Environment(\.openURL) private var openURL
    @State private var editing:DailyReminder?
    @State private var confirmation:String?
    @State private var confirmRecovery=false
    var body:some View {
        ScrollView{VStack(alignment:.leading,spacing:24){
            permissionCard
            if reminders.preferencesUnavailable{
                SandowStateAlert(text:diary.t("تعذّرت قراءة إعدادات التذكيرات. بقي الملف الأصلي محفوظًا؛ لم نغيّر سجلّك الغذائي.","Reminder settings could not be read. The original file was preserved; your food diary was not changed."))
                Button(diary.t("إعادة ضبط التذكيرات فقط","Reset reminders only")){confirmRecovery=true}.buttonStyle(LuqmaSecondaryButtonStyle())
            }else{
                VStack(alignment:.leading,spacing:12){
                    Text(diary.t("تذكيراتك اليومية","Your daily reminders")).luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline).accessibilityAddTraits(.isHeader)
                    ForEach(reminders.preferences.reminders){reminder in reminderRow(reminder)}
                }
                HStack(spacing:10){
                    Text(diary.t("التذكيرات المجدولة على هذا الجهاز","Reminders scheduled on this device")).luqmaFont(size:13,relativeTo:.footnote)
                    Spacer(minLength:4)
                    Text(String(reminders.pendingCount)).luqmaFont(size:16,weight:.bold,relativeTo:.headline).monospacedDigit()
                        .accessibilityIdentifier("reminders.pendingCount")
                }.foregroundStyle(Theme.muted)
            }
            if let confirmation{SandowSavedConfirmation(text:confirmation).accessibilityIdentifier("reminders.savedConfirmation")}
            if let error=reminders.error{SandowStateAlert(text:error)}
            if reminders.isWorking{SandowOperationState(title:diary.t("تحديث التذكيرات…","Updating reminders…"))}
            Notice(text:diary.t("الأوقات محلية لجهازك. تبقى الإعدادات على هذا الجهاز، ولا تُصدَّر في نسخة سجل الطعام. قد يؤخر نمط التركيز أو الملخص المجدول عرض التنبيه.","Times follow this device’s local time. Settings stay on this device and are not part of a food diary backup. Focus or Scheduled Summary may delay an alert."))
        }.padding(16).padding(.vertical,8)}.appBackground()
            .sandowNavigation(diary.t("التذكيرات","Reminders"),backLabel:diary.t("رجوع","Back"))
            .task{await reminders.refresh(language:diary.language)}
            .sheet(item:$editing){reminder in ReminderTimeEditor(reminder:reminder){confirmation=diary.t("حُفظ وقت التذكير.","Reminder time saved.")}}
            .confirmationDialog(diary.t("إعادة ضبط التذكيرات؟","Reset reminders?"),isPresented:$confirmRecovery,titleVisibility:.visible){
                Button(diary.t("إعادة الضبط","Reset"),role:.destructive){Task{if await reminders.recoverPreferences(language:diary.language){confirmation=diary.t("أُعيد ضبط التذكيرات وهي معطّلة.","Reminders were reset and are switched off.")}}}
                Button(diary.t("إلغاء","Cancel"),role:.cancel){}
            } message:{Text(diary.t("سيستبدل هذا إعدادات التذكيرات فقط. لن يُحذف سجل الطعام.","This replaces reminder settings only. Your food diary will remain intact."))}
    }
    private var permissionCard:some View {
        VStack(alignment:.leading,spacing:14){
            HStack(spacing:12){
                Image("SandowNotification").frame(width:24,height:24).padding(10).background(Theme.accent,in:RoundedRectangle(cornerRadius:14)).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:4){
                    Text(diary.t("إشعارات لقمة","Luqma notifications")).luqmaFont(size:18,weight:.bold,relativeTo:.title3)
                    Text(permissionDescription).luqmaFont(size:13,relativeTo:.footnote).foregroundStyle(Theme.muted)
                        .accessibilityIdentifier("reminders.permissionStatus").accessibilityValue(permissionValue)
                }
            }
            if reminders.authorization == .notDetermined{
                Button(diary.t("السماح بالإشعارات","Allow notifications")){Task{confirmation=nil;await reminders.requestPermission(language:diary.language)}}
                    .buttonStyle(LuqmaPrimaryButtonStyle()).accessibilityIdentifier("reminders.enablePermission").disabled(reminders.isWorking)
            }else if reminders.authorization == .denied || reminders.authorization == .quiet{
                Button(diary.t("فتح إعدادات الإشعارات","Open notification settings")){if let url=URL(string:UIApplication.openNotificationSettingsURLString){openURL(url)}}
                    .buttonStyle(LuqmaSecondaryButtonStyle()).accessibilityIdentifier("reminders.openSettings")
            }
        }.luqmaCard()
    }
    private var permissionDescription:String {
        switch reminders.authorization{
        case .notDetermined:return diary.t("اضبط الأوقات ثم اسمح بالتنبيهات عندما تكون جاهزًا.","Set your times, then allow alerts when you are ready.")
        case .allowed:return diary.t("الإشعارات مسموحة من إعدادات iOS.","Notifications are allowed in iOS Settings.")
        case .quiet:return diary.t("الإشعارات تصل بهدوء. راجع إعدادات النظام لتفعيل التنبيه.","Notifications arrive quietly. Review system settings to enable alerts.")
        case .denied:return diary.t("الإشعارات مرفوضة. اسمح بها من إعدادات الآيفون لتصلك التذكيرات.","Notifications are denied. Allow them in iPhone Settings to receive reminders.")
        case .unavailable:return diary.t("تعذّرت معرفة حالة الإشعارات. حاول مجددًا.","Notification status is unavailable. Try again.")
        }
    }
    private var permissionValue:String {
        switch reminders.authorization{case .notDetermined:return "notDetermined";case .allowed:return "allowed";case .quiet:return "quiet";case .denied:return "denied";case .unavailable:return "unavailable"}
    }
    private func reminderRow(_ reminder:DailyReminder)->some View {
        VStack(alignment:.leading,spacing:10){
            Toggle(isOn:Binding(get:{reminders.preferences.reminders.first(where:{$0.kind==reminder.kind})?.isEnabled ?? false},set:{enabled in
                var changed=reminder;changed.isEnabled=enabled;confirmation=nil
                Task{if await reminders.update(changed,language:diary.language){confirmation=enabled ? diary.t("حُفظ التذكير. راجع حالة الإذن أعلاه للتأكد من وصوله.","Reminder saved. Check permission status above to confirm it can be delivered."):diary.t("أُوقف التذكير.","Reminder switched off.")}}
            })){HStack(spacing:10){
                Image(reminder.kind == .nutritionReview ? "SandowNotification":"SandowDinner").frame(width:24,height:24).padding(8)
                    .background(Theme.accent,in:RoundedRectangle(cornerRadius:13)).accessibilityHidden(true)
                Text(reminder.kind.label(diary.language)).luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline).foregroundStyle(Theme.text)
            }}.tint(Theme.accent).accessibilityIdentifier("reminders.toggle."+reminder.kind.rawValue).disabled(reminders.isWorking)
            HStack{
                Text(diary.t("كل يوم","Every day")).luqmaFont(size:12,relativeTo:.caption).foregroundStyle(Theme.muted)
                Spacer(minLength:8)
                Button{confirmation=nil;editing=reminder}label:{HStack(spacing:6){
                    Text(String(format:"%02d:%02d",reminder.hour,reminder.minute)).luqmaFont(size:16,weight:.bold,relativeTo:.headline).monospacedDigit().environment(\.layoutDirection,.leftToRight)
                    Image("SandowClock").frame(width:24,height:24)
                }.foregroundStyle(Theme.background).padding(.horizontal,10).frame(minHeight:44).background(Theme.accent,in:RoundedRectangle(cornerRadius:12))}
                    .buttonStyle(.plain).accessibilityLabel(diary.t("تعديل الوقت — ","Edit time — ")+reminder.kind.label(diary.language))
                    .accessibilityValue(String(format:"%02d:%02d",reminder.hour,reminder.minute))
                    .accessibilityIdentifier("reminders.time."+reminder.kind.rawValue).disabled(reminders.isWorking)
            }
        }.padding(12).background(Theme.card,in:RoundedRectangle(cornerRadius:20))
    }
}

private struct ReminderTimeEditor:View {
    let reminder:DailyReminder
    let onSaved:()->Void
    @EnvironmentObject private var diary:DiaryStore
    @EnvironmentObject private var reminders:ReminderService
    @Environment(\.dismiss) private var dismiss
    @State private var time:Date
    init(reminder:DailyReminder,onSaved:@escaping()->Void){
        self.reminder=reminder;self.onSaved=onSaved
        _time=State(initialValue:Calendar.current.date(from:DateComponents(year:2026,month:1,day:15,hour:reminder.hour,minute:reminder.minute)) ?? Date())
    }
    var body:some View {
        NavigationStack{ScrollView{VStack(alignment:.leading,spacing:24){
            Text(reminder.kind.label(diary.language)).luqmaFont(size:24,weight:.bold,relativeTo:.title2)
            DatePicker(diary.t("وقت التذكير","Reminder time"),selection:$time,displayedComponents:.hourAndMinute)
                .datePickerStyle(.wheel).environment(\.locale,Locale(identifier:"en_GB")).labelsHidden()
                .accessibilityIdentifier("reminders.timePicker").frame(maxWidth:.infinity)
            Notice(text:diary.t("يُطبَّق الوقت يوميًا حسب التوقيت المحلي للجهاز.","The time applies daily in this device’s local time zone."))
            if let error=reminders.error{SandowStateAlert(text:error)}
        }.padding(16)}.appBackground()
            .sandowNavigation(diary.t("وقت التذكير","Reminder time"),backLabel:diary.t("إلغاء","Cancel"),actionLabel:diary.t("حفظ","Save"),actionEnabled:!reminders.isWorking,actionIdentifier:"reminders.saveTime",onAction:{
                let parts=Calendar.current.dateComponents([.hour,.minute],from:time)
                var changed=reminder;changed.hour=parts.hour ?? reminder.hour;changed.minute=parts.minute ?? reminder.minute
                Task{if await reminders.update(changed,language:diary.language){onSaved();dismiss()}}
            })}
    }
}

struct NotificationsView:View {
    @EnvironmentObject private var diary:DiaryStore
    @EnvironmentObject private var reminders:ReminderService
    @State private var selected=0
    @State private var confirmClear=false
    private var visible:[DeliveredReminderNotification]{reminders.deliveredNotifications.filter{Calendar.current.isDateInToday($0.deliveredAt) == (selected==0)}}
    var body:some View {
        ScrollView{VStack(alignment:.leading,spacing:20){
            HStack(alignment:.firstTextBaseline){
                Text(diary.t("الإشعارات","Notifications")).luqmaFont(size:24,weight:.bold,relativeTo:.title2).accessibilityAddTraits(.isHeader)
                Text(String(reminders.deliveredNotifications.count)).luqmaFont(size:12,weight:.semibold,relativeTo:.caption).foregroundStyle(Theme.muted)
                Spacer(minLength:0)
                if !reminders.deliveredNotifications.isEmpty{Button(diary.t("مسح الكل","Clear all")){confirmClear=true}.luqmaFont(size:12,weight:.semibold,relativeTo:.caption).foregroundStyle(Theme.muted)}
            }
            Picker(diary.t("الفترة","Period"),selection:$selected){Text(diary.t("اليوم","Today")).tag(0);Text(diary.t("السابقة","Past")).tag(1)}.pickerStyle(.segmented)
            if visible.isEmpty{
                SandowEmptyState(title:diary.t("لا توجد إشعارات هنا","No notifications here"),message:diary.t("تظهر هنا تذكيرات لقمة التي وصلت وما زالت في مركز الإشعارات. اضبط تذكيرات الوجبات من الإعدادات.","Delivered Luqma reminders still in Notification Center appear here. Set your meal reminders in settings."))
                NavigationLink{RemindersView()}label:{Text(diary.t("إعداد التذكيرات","Set up reminders"))}.buttonStyle(LuqmaPrimaryButtonStyle())
            }else{
                ForEach(visible){notification in Button{
                    reminders.pendingRoute=notification.kind
                    Task{await reminders.removeDeliveredNotification(id:notification.id)}
                }label:{HStack(alignment:.top,spacing:12){
                    Image(notification.kind == .nutritionReview ? "SandowNotification":"SandowDinner").frame(width:24,height:24).padding(10)
                        .background(Theme.accent,in:RoundedRectangle(cornerRadius:16)).accessibilityHidden(true)
                    VStack(alignment:.leading,spacing:4){
                        Text(notification.title).luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline).foregroundStyle(Theme.text)
                        Text(notification.body).luqmaFont(size:12,relativeTo:.caption).foregroundStyle(Theme.muted).fixedSize(horizontal:false,vertical:true)
                        Text(DisplayFormat.date(notification.deliveredAt,template:"MMMdhm",language:diary.language)).luqmaFont(size:10,relativeTo:.caption2).foregroundStyle(Theme.muted)
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }.padding(12).background(Theme.card,in:RoundedRectangle(cornerRadius:20))}.buttonStyle(.plain)}
            }
            if let error=reminders.error{SandowStateAlert(text:error)}
        }.padding(16).padding(.vertical,8)}.appBackground()
            .sandowNavigation(diary.t("الإشعارات","Notifications"),backLabel:diary.t("رجوع","Back"))
            .task{await reminders.refresh(language:diary.language)}.refreshable{await reminders.refresh(language:diary.language)}
            .confirmationDialog(diary.t("مسح الإشعارات التي وصلت؟","Clear delivered notifications?"),isPresented:$confirmClear,titleVisibility:.visible){
                Button(diary.t("مسح الكل","Clear all"),role:.destructive){Task{await reminders.clearDeliveredNotifications()}}
                Button(diary.t("إلغاء","Cancel"),role:.cancel){}
            } message:{Text(diary.t("لن تتغير التذكيرات اليومية المجدولة.","Scheduled daily reminders will remain unchanged."))}
    }
}
