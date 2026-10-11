import Foundation
import HealthKit
import Combine
import UIKit

@MainActor final class HealthService: ObservableObject {
    enum BackgroundStatus { case inactive, enabled, limited, unavailable }
    @Published private(set) var busy = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var readings = 0
    @Published private(set) var steps: Double?
    @Published private(set) var activeCalories: Double?
    @Published private(set) var heightCM: Double?
    @Published private(set) var message: String?
    @Published private(set) var signingBlocked = false
    @Published private(set) var backgroundStatus: BackgroundStatus = .inactive
    @Published private(set) var waitingForUnlock = false
    private let health = HKHealthStore()
    private let identifiers: [HKQuantityTypeIdentifier] = [.bodyMass, .height, .stepCount, .activeEnergyBurned]
    private var observers: [HKObserverQuery] = []
    private var pending = Set<HKQuantityTypeIdentifier>()
    private var acknowledgements: [() -> Void] = []
    private var draining = false
    private var generation = 0
    private var setup: Task<Void, Never>?
    private var foregroundPoll: Task<Void, Never>?
    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    var installedIdentifier: String { Bundle.main.bundleIdentifier ?? "app.luqma.diary" }
    private var profile: Data? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision") else { return nil }
        return try? Data(contentsOf: url)
    }
    private var profileAllowsHealth: Bool? { profile.flatMap(HealthSigning.profileSupportsHealth) }
    private var profileAllowsBackground: Bool? { profile.flatMap(HealthSigning.profileSupportsBackgroundHealth) }

    private func explainSigning(_ diary: DiaryStore) {
        signingBlocked = true; backgroundStatus = .unavailable
        generation += 1
        stopObservers()
        if UIApplication.shared.isProtectedDataAvailable && !diary.waitingForUnlock { diary.change { $0.healthEnabled = false } }
        message = diary.t("النسخة المثبتة لا تحمل صلاحية HealthKit. يلزم إعادة توقيعها بصلاحية صحتي قبل الربط؛ تغيير أذونات الآيفون وحده لا يكفي.", "This installation lacks the HealthKit entitlement. Re-sign it with Health access before connecting; changing iPhone permissions alone cannot fix it.")
    }
    func checkInstallation(_ diary: DiaryStore) {
        guard available, profileAllowsHealth == false, !signingBlocked else { return }
        explainSigning(diary)
    }
    private func handle(_ error: Error, diary: DiaryStore) {
        let e = error as NSError
        if !UIApplication.shared.isProtectedDataAvailable {
            waitingForUnlock = true
            message = diary.t("سيُستكمل التحديث عند فتح قفل الآيفون. قراءاتك السابقة محفوظة.", "Sync will resume when you unlock your iPhone. Previous readings are preserved.")
        } else if profileAllowsHealth == false || e.localizedDescription.lowercased().contains("entitlement") {
            explainSigning(diary)
        } else { message = (error as? AppError)?.message(diary.language) ?? error.localizedDescription }
    }
    private func restoreCache(_ diary: DiaryStore) {
        let cache = diary.state.healthSync
        if let stamp = cache?.updatedAt { lastSync = Date(timeIntervalSince1970: stamp) }
        heightCM = cache?.heightCM
        if cache?.activityDay == DayKey.today { steps = cache?.steps; activeCalories = cache?.activeCalories }
        else { steps = nil; activeCalories = nil }
        readings = diary.state.weights.filter { $0.source == "Apple Health" }.count
    }

    /// Register synchronously at didFinishLaunching, including a HealthKit background launch.
    func prepare(_ diary: DiaryStore) {
        restoreCache(diary)
        guard diary.state.healthEnabled || (diary.waitingForUnlock && UserDefaults.standard.bool(forKey: "luqma.health.connected")), available else { return }
        guard profileAllowsHealth != false else { explainSigning(diary); return }
        guard observers.isEmpty else { return }
        signingBlocked = false
        let observerGeneration = generation
        for identifier in identifiers {
            guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { continue }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self, weak diary] _, completion, error in
                Task { @MainActor in
                    guard let self, let diary else { completion(); return }
                    guard self.generation == observerGeneration else { completion(); return }
                    if let error { self.handle(error, diary: diary); completion(); return }
                    self.enqueue([identifier], diary: diary, acknowledgement: completion)
                }
            }
            observers.append(query); health.execute(query)
        }
        let token = generation
        setup = Task { await configureBackground(diary, token: token) }
    }
    private func configureBackground(_ diary: DiaryStore, token: Int) async {
        guard profileAllowsBackground != false else { backgroundStatus = .unavailable; return }
        var successes = 0
        for identifier in identifiers {
            guard generation == token, !Task.isCancelled, let type = HKObjectType.quantityType(forIdentifier: identifier) else { return }
            do {
                // iOS still throttles background steps to at most hourly.
                try await health.enableBackgroundDelivery(for: type, frequency: .immediate)
                if generation != token || Task.isCancelled { try? await health.disableBackgroundDelivery(for: type); return }
                successes += 1
            } catch { /* Foreground observation can work without background delivery. */ }
        }
        guard generation == token else { return }
        backgroundStatus = successes == identifiers.count ? .enabled : (successes > 0 ? .limited : .unavailable)
    }
    func connect(_ diary: DiaryStore) async {
        guard !busy else { return }
        guard available else { message = diary.t("Apple Health غير متاح على هذا الجهاز.", "Apple Health is unavailable on this device."); return }
        guard profileAllowsHealth != false else { explainSigning(diary); return }
        message = nil; signingBlocked = false; busy = true
        var types = Set<HKObjectType>(identifiers.compactMap { HKObjectType.quantityType(forIdentifier: $0) })
        if let dob = HKObjectType.characteristicType(forIdentifier: .dateOfBirth) { types.insert(dob) }
        if let sex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) { types.insert(sex) }
        do {
            try await health.requestAuthorization(toShare: [], read: types)
            // Completion is not proof of read access; HealthKit deliberately hides read denial.
            diary.change { $0.healthEnabled = true }; busy = false
            guard diary.state.healthEnabled else { return }
            prepare(diary); becameActive(diary); await sync(diary)
        } catch { busy = false; handle(error, diary: diary) }
    }
    private func stopObservers() {
        setup?.cancel(); setup = nil; foregroundPoll?.cancel(); foregroundPoll = nil
        for query in observers { health.stop(query) }; observers.removeAll()
        pending.removeAll()
        let callbacks = acknowledgements; acknowledgements.removeAll(); callbacks.forEach { $0() }
    }
    func disconnect(_ diary: DiaryStore) async {
        diary.change { $0.healthEnabled = false }
        guard !diary.state.healthEnabled else { return }
        generation += 1; stopObservers(); backgroundStatus = .inactive; waitingForUnlock = false
        try? await health.disableAllBackgroundDelivery()
        message = diary.t("أُوقفت المزامنة التلقائية. السجل السابق محفوظ.", "Automatic sync is off. Previous history is preserved.")
    }
    func becameActive(_ diary: DiaryStore) {
        guard diary.restoreAfterUnlock() else { return }
        waitingForUnlock = false; prepare(diary)
        guard diary.state.healthEnabled, !signingBlocked else { return }
        foregroundPoll?.cancel()
        foregroundPoll = Task { [weak self, weak diary] in
            guard let self, let diary else { return }
            await self.sync(diary)
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 30_000_000_000) } catch { return }
                guard !Task.isCancelled, diary.state.healthEnabled else { return }
                // Save notifications are primary; this check handles delayed saves and midnight.
                await self.refreshActivity(diary)
            }
        }
    }
    func enteredBackground() { foregroundPoll?.cancel(); foregroundPoll = nil }
    func unlocked(_ diary: DiaryStore) {
        guard diary.restoreAfterUnlock() else { return }
        waitingForUnlock = false; prepare(diary)
        if diary.state.healthEnabled { Task { await sync(diary) } }
    }
    func sync(_ diary: DiaryStore) async {
        prepare(diary)
        await withCheckedContinuation { continuation in
            enqueue(Set(identifiers), diary: diary) { continuation.resume() }
        }
    }
    private func refreshActivity(_ diary: DiaryStore) async {
        await withCheckedContinuation { continuation in
            enqueue([.stepCount, .activeEnergyBurned], diary: diary) { continuation.resume() }
        }
    }
    private func enqueue(_ kinds: Set<HKQuantityTypeIdentifier>, diary: DiaryStore, acknowledgement: @escaping () -> Void) {
        guard diary.state.healthEnabled || (diary.waitingForUnlock && UserDefaults.standard.bool(forKey: "luqma.health.connected")), available, !signingBlocked else { acknowledgement(); return }
        guard UIApplication.shared.isProtectedDataAvailable, diary.restoreAfterUnlock() else {
            waitingForUnlock = true; acknowledgement(); return
        }
        pending.formUnion(kinds); acknowledgements.append(acknowledgement)
        guard !draining else { return }
        draining = true
        Task { await drain(diary) }
    }
    private func drain(_ diary: DiaryStore) async {
        busy = true
        defer { draining = false; busy = false }
        while !pending.isEmpty, diary.state.healthEnabled, !signingBlocked {
            let kinds = pending; pending.removeAll()
            let callbacks = acknowledgements; acknowledgements.removeAll()
            let token = generation
            do { try await refresh(kinds, diary: diary, token: token) }
            catch { handle(error, diary: diary) }
            // Exactly once after the fetched changes and anchor are saved, or an error is handled.
            callbacks.forEach { $0() }
        }
        let callbacks = acknowledgements; acknowledgements.removeAll(); callbacks.forEach { $0() }
    }
    private func weightChanges(anchor: HKQueryAnchor?) async throws -> (added: [HealthWeightSample], deleted: Set<UUID>, anchor: HKQueryAnchor?) {
        guard let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return ([], [], anchor) }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: anchor, limit: 1000) { _, samples, deleted, nextAnchor, error in
                if let error { continuation.resume(throwing: error); return }
                let values = (samples as? [HKQuantitySample] ?? []).map { HealthWeightSample(id: $0.uuid, kg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)), end: $0.endDate.timeIntervalSince1970) }
                continuation.resume(returning: (values, Set((deleted ?? []).map(\.uuid)), nextAnchor))
            }
            health.execute(query)
        }
    }
    private func samples(_ identifier: HKQuantityTypeIdentifier, limit: Int = 1) async throws -> [HKQuantitySample] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: limit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, result, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: result as? [HKQuantitySample] ?? []) }
            }; health.execute(query)
        }
    }
    private func todaySum(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let start = Calendar.current.startOfDay(for: Date()), predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit)) }
            }; health.execute(query)
        }
    }
    private func refresh(_ kinds: Set<HKQuantityTypeIdentifier>, diary: DiaryStore, token: Int) async throws {
        var cache = diary.state.healthSync ?? HealthSyncState()
        var added: [HealthWeightSample] = [], deleted = Set<UUID>(), fetchedWeights = false
        if kinds.contains(.bodyMass) {
            var anchor: HKQueryAnchor?
            if let data = cache.anchor { anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data) }
            while true {
                let result = try await weightChanges(anchor: anchor)
                added += result.added; deleted.formUnion(result.deleted); anchor = result.anchor
                guard generation == token, diary.state.healthEnabled else { return }
                guard added.count <= 50000 else { throw AppError.invalid("قراءات صحتي تتجاوز الحد المدعوم. لم يُغيّر السجل.", "Health readings exceed the supported limit. Your diary was not changed.") }
                if result.added.count + result.deleted.count < 1000 { break }
            }
            fetchedWeights = true
            if let anchor { cache.anchor = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true) }
        }
        if kinds.contains(.height) {
            let value = try await samples(.height).first?.quantity.doubleValue(for: .meterUnit(with: .centi))
            cache.heightCM = value.flatMap { $0.isFinite && (120...240).contains($0) ? $0 : nil }
        }
        if cache.activityDay != DayKey.today { cache.steps = nil; cache.activeCalories = nil; cache.activityDay = DayKey.today }
        if kinds.contains(.stepCount) {
            let value = try await todaySum(.stepCount, unit: .count())
            cache.steps = value.flatMap { $0.isFinite && (0...300000).contains($0) ? $0 : nil }
        }
        if kinds.contains(.activeEnergyBurned) {
            let value = try await todaySum(.activeEnergyBurned, unit: .kilocalorie())
            cache.activeCalories = value.flatMap { $0.isFinite && (0...50000).contains($0) ? $0 : nil }
        }
        guard generation == token, diary.state.healthEnabled else { return }
        guard UIApplication.shared.isProtectedDataAvailable else { throw AppError.invalid("افتح قفل الآيفون لإكمال المزامنة.", "Unlock your iPhone to finish syncing.") }
        var weights: [WeightReading]?
        if fetchedWeights {
            // Merge against current diary data, so edits made while queries awaited are preserved.
            let merged = HealthSync.apply(added: added, deleted: deleted, to: cache, weights: diary.state.weights)
            cache = merged.cache; weights = merged.weights
        }
        cache.updatedAt = Date().timeIntervalSince1970
        guard diary.applyHealth(cache, weights: weights) else { message = diary.error; return }
        restoreCache(diary); waitingForUnlock = false
        message = cache.records.isEmpty && cache.steps == nil && cache.activeCalories == nil && cache.heightCM == nil
            ? diary.t("لم تصل قراءات. قد لا توجد بيانات أو لم تسمح بقراءتها. راجع صلاحيات لقمة داخل صحتي.", "No readings received. Data may be absent or read access disabled. Check Luqma permissions in Health.")
            : nil
    }
    func profile() async -> (weight: Double?, height: Double?, age: Double?, sex: String?) {
        guard !signingBlocked, profileAllowsHealth != false else { return (nil, nil, nil, nil) }
        let weight = try? await samples(.bodyMass).first?.quantity.doubleValue(for: .gramUnit(with: .kilo))
        let height = try? await samples(.height).first?.quantity.doubleValue(for: .meterUnit(with: .centi))
        var age: Double?, sex: String?
        if let birth = try? health.dateOfBirthComponents(), let date = Calendar.current.date(from: birth), let years = Calendar.current.dateComponents([.year], from: date, to: Date()).year { age = Double(years) }
        if let biological = try? health.biologicalSex() { if biological.biologicalSex == .male { sex = "male" }; if biological.biologicalSex == .female { sex = "female" } }
        return (weight, height, age, sex)
    }
}
