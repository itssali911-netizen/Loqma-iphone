import Foundation
import Combine
import UserNotifications

enum ReminderAuthorization: Equatable {
    case notDetermined, allowed, quiet, denied, unavailable

    var canSchedule: Bool { self == .allowed || self == .quiet }
}

struct DeliveredReminderNotification: Identifiable {
    let id: String
    let kind: ReminderKind
    let deliveredAt: Date
    let title: String
    let body: String
}

/// Owns only Luqma's five known reminder identifiers. Preferences are device
/// local; notification authorization is always obtained from iOS, never a backup.
@MainActor final class ReminderService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var preferences = ReminderPreferences.defaults
    @Published private(set) var authorization: ReminderAuthorization = .notDetermined
    @Published private(set) var pendingCount = 0
    @Published private(set) var error: String?
    @Published private(set) var isWorking = false
    @Published private(set) var preferencesUnavailable = false
    @Published private(set) var deliveredNotifications: [DeliveredReminderNotification] = []
    @Published var pendingRoute: ReminderKind?

    private let center: UNUserNotificationCenter
    private let fileManager: FileManager
    private let preferencesURL: URL?
    private var language: AppLanguage = .ar
    private var revision: UInt64 = 0
    private var reconciliationTask: Task<Bool, Never>?
    private var requestingPermission = false
    private var deliveredRevision: UInt64 = 0

    init(center: UNUserNotificationCenter = .current(), fileManager: FileManager = .default, preferencesURL: URL? = nil) {
        self.center = center
        self.fileManager = fileManager
        self.preferencesURL = preferencesURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LuqmaReminders", isDirectory: true)
            .appendingPathComponent("preferences.json")
        super.init()
        loadPreferences()
        center.delegate = self
    }

    /// Called on foreground, language and significant-time changes. This method
    /// does not request permission or silently overwrite an unreadable document.
    func refresh(language: AppLanguage) async {
        self.language = language
        if preferencesUnavailable { loadPreferences() }
        if !preferencesUnavailable { error = nil }
        _ = await reconcile()
    }

    /// The sole permission-requesting entry point; invoke only for a user action.
    @discardableResult func requestPermission(language: AppLanguage) async -> Bool {
        self.language = language
        guard !requestingPermission else { return authorization.canSchedule }
        requestingPermission = true
        updateWorkingState()
        defer { requestingPermission = false; updateWorkingState() }
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            do { _ = try await center.requestAuthorization(options: [.alert, .sound]) }
            catch {
                error = language.text("تعذّر طلب إذن الإشعارات. حاول مرة أخرى.", "Notification permission could not be requested. Try again.")
                _ = await reconcile()
                return false
            }
        }
        let reconciled = await reconcile()
        return reconciled && authorization.canSchedule
    }

    /// A true result means the preferences were saved and pending OS requests
    /// reconciled. It does not imply permission was granted: the UI must show the
    /// freshly read authorization state alongside this saved preference.
    @discardableResult func update(_ daily: DailyReminder, language: AppLanguage) async -> Bool {
        self.language = language
        guard !preferencesUnavailable else {
            reportStorageError()
            return false
        }
        var candidate = preferences
        guard let index = candidate.reminders.firstIndex(where: { $0.kind == daily.kind }) else { return false }
        candidate.reminders[index] = daily
        do {
            candidate = try candidate.validated()
            try persist(candidate)
            preferences = candidate
            error = nil
        } catch {
            self.error = language.text("تعذّر حفظ التذكير. لم تُطبّق التغييرات.", "The reminder could not be saved. Your changes were not applied.")
            return false
        }
        return await reconcile()
    }

    /// Explicit recovery only, after a confirmation in the UI. Retain the old
    /// bytes in this excluded device-local directory before replacing settings.
    @discardableResult func recoverPreferences(language: AppLanguage) async -> Bool {
        self.language = language
        guard let preferencesURL else { reportStorageError(); return false }
        do {
            let preservedData: Data?
            do { preservedData = try Data(contentsOf: preferencesURL) }
            catch {
                guard isMissingFile(error), confirmedMissingPath(preferencesURL) else { throw error }
                preservedData = nil
            }
            try prepareDirectory(for: preferencesURL)
            if let preservedData {
                let preserved = preferencesURL.deletingLastPathComponent()
                    .appendingPathComponent("preserved-\(UUID().uuidString).json")
                try preservedData.write(to: preserved, options: [.atomic, .completeFileProtection])
            }
            try persist(.defaults)
            preferences = .defaults
            preferencesUnavailable = false
            error = nil
        } catch {
            reportStorageError()
            return false
        }
        return await reconcile()
    }

    func dismissError() { error = nil }

    func removeDeliveredNotification(id: String) async {
        guard ReminderKind.fromNotificationIdentifier(id) != nil else { return }
        center.removeDeliveredNotifications(withIdentifiers: [id])
        await refreshDeliveredNotifications()
    }

    func clearDeliveredNotifications() async {
        let delivered = await center.deliveredNotifications()
        let identifiers = delivered.compactMap { item -> String? in
            ReminderKind.fromNotificationIdentifier(item.request.identifier) == nil ? nil : item.request.identifier
        }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        await refreshDeliveredNotifications()
    }

    private func loadPreferences() {
        guard let preferencesURL else { preferencesUnavailable = true; reportStorageError(); return }
        do {
            let data = try Data(contentsOf: preferencesURL)
            preferences = try JSONDecoder().decode(ReminderPreferences.self, from: data)
            preferencesUnavailable = false
            error = nil
        } catch {
            if isMissingFile(error), confirmedMissingPath(preferencesURL) {
                preferences = .defaults
                preferencesUnavailable = false
                self.error = nil
                return
            }
            // The disabled defaults are display-only while blocked. Nothing is
            // written, and existing scheduled reminders are removed safely.
            preferencesUnavailable = true
            reportStorageError()
        }
    }

    private func isMissingFile(_ error: Error) -> Bool {
        var candidate = error as NSError
        for _ in 0..<8 {
            if candidate.domain == NSCocoaErrorDomain && candidate.code == CocoaError.Code.fileReadNoSuchFile.rawValue { return true }
            if candidate.domain == NSPOSIXErrorDomain && candidate.code == Int(POSIXErrorCode.ENOENT.rawValue) { return true }
            guard let underlying = candidate.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
            candidate = underlying
        }
        return false
    }

    /// fileExists/isReadableFile return false for permission failures as well as
    /// missing paths. Confirm absence with an actual readable parent listing,
    /// walking up only for a first-launch directory that does not yet exist.
    private func confirmedMissingPath(_ url: URL) -> Bool {
        var candidate = url.standardizedFileURL
        while true {
            let parent = candidate.deletingLastPathComponent()
            guard parent != candidate else { return false }
            do {
                let names = try fileManager.contentsOfDirectory(atPath: parent.path)
                return !names.contains(candidate.lastPathComponent)
            } catch {
                guard isMissingFile(error) else { return false }
                candidate = parent
            }
        }
    }

    private func prepareDirectory(for url: URL) throws {
        var directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.protectionKey: FileProtectionType.complete])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }

    private func persist(_ value: ReminderPreferences) throws {
        guard let preferencesURL else { throw CocoaError(.fileNoSuchFile) }
        let data = try JSONEncoder().encode(value.validated())
        try prepareDirectory(for: preferencesURL)
        try data.write(to: preferencesURL, options: [.atomic, .completeFileProtection])
    }

    private func reportStorageError() {
        error = language.text("تعذّر قراءة إعدادات التذكيرات أو حفظها. احتُفظ بالملف الأصلي؛ أعد المحاولة بعد فتح قفل الجهاز أو أعد ضبط التذكيرات.", "Reminder settings could not be read or saved. The original file was retained. Try again after unlocking your device, or reset reminders.")
    }

    private func updateWorkingState() {
        isWorking = requestingPermission || reconciliationTask != nil
    }

    /// Requests share one serial worker. Any mutation while an OS call is
    /// suspended advances the revision; the worker then reconciles again before
    /// completing. An older add can never win over a later switch-off/time edit.
    private func reconcile() async -> Bool {
        revision &+= 1
        if let reconciliationTask { return await reconciliationTask.value }
        let task = Task<Bool, Never> { @MainActor [weak self] in
            guard let self else { return false }
            let result = await self.runReconciliation()
            self.reconciliationTask = nil
            self.updateWorkingState()
            return result
        }
        reconciliationTask = task
        updateWorkingState()
        return await task.value
    }

    private func runReconciliation() async -> Bool {
        while true {
            let currentRevision = revision
            let currentLanguage = language
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined: authorization = .notDetermined
            case .denied: authorization = .denied
            case .authorized: authorization = settings.alertSetting == .enabled ? .allowed : .quiet
            case .provisional, .ephemeral: authorization = .quiet
            @unknown default: authorization = .unavailable
            }
            if currentRevision != revision { continue }
            let expected = preferencesUnavailable || !authorization.canSchedule ? [] : preferences.reminders.filter(\.isEnabled)
            let pending = await center.pendingNotificationRequests()
            if currentRevision != revision { continue }
            let ownPending = pending.filter { ReminderKind.fromNotificationIdentifier($0.identifier) != nil }
            let removable = ownPending.filter { request in
                guard let desired = expected.first(where: { $0.kind.notificationIdentifier == request.identifier }) else { return true }
                return !matches(request, reminder: desired, language: currentLanguage)
            }.map(\.identifier)
            center.removePendingNotificationRequests(withIdentifiers: removable)
            var successful = !preferencesUnavailable
            for reminder in expected {
                if currentRevision != revision { break }
                if ownPending.contains(where: { $0.identifier == reminder.kind.notificationIdentifier && matches($0, reminder: reminder, language: currentLanguage) }) { continue }
                let content = UNMutableNotificationContent()
                content.title = reminder.kind.title(currentLanguage)
                content.body = reminder.kind.body(currentLanguage)
                content.sound = .default
                content.threadIdentifier = "app.luqma.reminders"
                content.userInfo = ["luqmaReminder": reminder.kind.rawValue]
                // Hour/minute only, without a pinned time zone: each day at the
                // user's local wall-clock time, following Apple's daily example.
                var components = DateComponents()
                components.hour = reminder.hour
                components.minute = reminder.minute
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
                let request = UNNotificationRequest(identifier: reminder.kind.notificationIdentifier, content: content, trigger: trigger)
                do { try await center.add(request) }
                catch {
                    successful = false
                    if currentRevision == revision {
                        error = currentLanguage.text("حُفظ الوقت، لكن تعذّرت جدولة بعض التذكيرات. أعد المحاولة.", "The time was saved, but some reminders could not be scheduled. Try again.")
                    }
                }
            }
            let actual = await center.pendingNotificationRequests()
            await refreshDeliveredNotifications()
            if currentRevision != revision { continue }
            let actualOwn = actual.filter { ReminderKind.fromNotificationIdentifier($0.identifier) != nil }
            pendingCount = actualOwn.count
            if actualOwn.count != expected.count || expected.contains(where: { reminder in
                !actualOwn.contains(where: { matches($0, reminder: reminder, language: currentLanguage) })
            }) {
                successful = false
                error = currentLanguage.text("لم تكتمل جدولة التذكيرات. أعد المحاولة وتحقق من إذن الإشعارات.", "Reminder scheduling is incomplete. Try again and check notification permission.")
            }
            return successful
        }
    }

    private func matches(_ request: UNNotificationRequest, reminder: DailyReminder, language: AppLanguage) -> Bool {
        guard request.identifier == reminder.kind.notificationIdentifier,
              let trigger = request.trigger as? UNCalendarNotificationTrigger,
              trigger.repeats, trigger.dateComponents.hour == reminder.hour,
              trigger.dateComponents.minute == reminder.minute,
              trigger.dateComponents.timeZone == nil,
              trigger.dateComponents.year == nil, trigger.dateComponents.month == nil,
              trigger.dateComponents.day == nil, trigger.dateComponents.weekday == nil else { return false }
        return request.content.title == reminder.kind.title(language) && request.content.body == reminder.kind.body(language)
            && request.content.threadIdentifier == "app.luqma.reminders" && request.content.sound != nil
    }

    private func refreshDeliveredNotifications() async {
        deliveredRevision &+= 1
        let currentRevision = deliveredRevision
        let delivered = await center.deliveredNotifications()
        guard currentRevision == deliveredRevision else { return }
        let records = delivered.compactMap { notification -> DeliveredReminderNotification? in
            guard let kind = ReminderKind.fromNotificationIdentifier(notification.request.identifier) else { return nil }
            return DeliveredReminderNotification(id: notification.request.identifier, kind: kind,
                                                 deliveredAt: notification.date, title: notification.request.content.title,
                                                 body: notification.request.content.body)
        }.sorted { $0.deliveredAt > $1.deliveredAt }
        var seen = Set<String>()
        deliveredNotifications = records.filter { seen.insert($0.id).inserted }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
        Task { @MainActor [weak self] in await self?.refreshDeliveredNotifications() }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                           withCompletionHandler completionHandler: @escaping () -> Void) {
        let kind = ReminderKind.fromNotificationIdentifier(response.notification.request.identifier)
        let opensReminder = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        Task { @MainActor [weak self] in
            if opensReminder, let kind { self?.pendingRoute = kind }
            completionHandler()
            await self?.refreshDeliveredNotifications()
        }
    }
}
