import Foundation
import HealthKit
import Combine

@MainActor final class HealthService: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var lastSync: Date?
    @Published private(set) var readings = 0
    @Published private(set) var steps: Double?
    @Published private(set) var activeCalories: Double?
    @Published private(set) var message: String?
    @Published private(set) var signingBlocked = false
    private let health = HKHealthStore()
    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    private var profileAllowsHealth: Bool? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"), let data = try? Data(contentsOf: url) else { return nil }
        return HealthSigning.profileSupportsHealth(data)
    }
    private func explainSigning(_ diary: DiaryStore) {
        signingBlocked = true
        diary.change { $0.healthEnabled = false }
        message = diary.t("توقيع هذه النسخة لا يتضمن صلاحية HealthKit، لذلك لا يمكن الربط المباشر. استخدم «استيراد بيانات صحتي» أدناه، أو ثبّت نسخة موقّعة بملف يتيح HealthKit. تغيير أذونات صحتي وحده لا يعالج التوقيع.", "This installation's signing profile does not include HealthKit. Use Import Health data below, or install a build signed with a HealthKit-enabled profile. Changing Health permissions alone cannot fix signing.")
    }
    private func handle(_ error: Error, diary: DiaryStore) {
        let e = error as NSError
        if profileAllowsHealth == false || e.localizedDescription.lowercased().contains("entitlement") { explainSigning(diary) }
        else { message = (error as? AppError)?.message(diary.language) ?? error.localizedDescription }
    }
    func connect(_ diary: DiaryStore) async {
        guard !busy else { return }
        guard available else { message=diary.t("Apple Health غير متاح على هذا الجهاز.", "Apple Health is unavailable on this device."); return }
        guard profileAllowsHealth != false else { explainSigning(diary); return }
        message = nil; signingBlocked = false
        busy = true
        let identifiers: [HKQuantityTypeIdentifier] = [.bodyMass,.height,.stepCount,.activeEnergyBurned]
        var types = Set<HKObjectType>(identifiers.compactMap { HKObjectType.quantityType(forIdentifier:$0) })
        if let dob=HKObjectType.characteristicType(forIdentifier:.dateOfBirth) { types.insert(dob) }
        if let sex=HKObjectType.characteristicType(forIdentifier:.biologicalSex) { types.insert(sex) }
        do {
            try await health.requestAuthorization(toShare: [], read: types)
            // Completion only confirms that the authorization flow completed.
            // HealthKit deliberately does not reveal whether reading was allowed.
            diary.change { $0.healthEnabled=true }; busy = false; await sync(diary)
        } catch { busy = false; handle(error, diary: diary) }
    }
    private func samples(_ identifier: HKQuantityTypeIdentifier, predicate: NSPredicate? = nil, limit: Int = HKObjectQueryNoLimit) async throws -> [HKQuantitySample] {
        guard let type=HKObjectType.quantityType(forIdentifier:identifier) else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            let query=HKSampleQuery(sampleType:type,predicate:predicate,limit:limit,sortDescriptors:[NSSortDescriptor(key:HKSampleSortIdentifierEndDate,ascending:false)]) { _,result,error in
                if let error { continuation.resume(throwing:error) } else { continuation.resume(returning:result as? [HKQuantitySample] ?? []) }
            }; health.execute(query)
        }
    }
    private func todaySum(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double? {
        guard let type=HKObjectType.quantityType(forIdentifier:identifier) else { return nil }
        let start=Calendar.current.startOfDay(for:Date()),predicate=HKQuery.predicateForSamples(withStart:start,end:Date(),options:.strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query=HKStatisticsQuery(quantityType:type,quantitySamplePredicate:predicate,options:.cumulativeSum) { _,statistics,error in
                if let error { continuation.resume(throwing:error) } else { continuation.resume(returning:statistics?.sumQuantity()?.doubleValue(for:unit)) }
            }; health.execute(query)
        }
    }
    func sync(_ diary: DiaryStore) async {
        guard profileAllowsHealth != false else { if diary.state.healthEnabled { explainSigning(diary) }; return }
        guard diary.state.healthEnabled,available,!busy else { return }; busy=true; defer { busy=false }
        do {
            let values=try await samples(.bodyMass,limit:50000)
            var daily: [String: WeightReading]=[:]
            for sample in values {
                let kg=sample.quantity.doubleValue(for:.gramUnit(with:.kilo)),day=DayKey.string(sample.endDate)
                guard kg.isFinite,(35...300).contains(kg),daily[day] == nil else { continue }
                daily[day]=WeightReading(day:day,kg:kg,source:"Apple Health",timestamp:sample.endDate.timeIntervalSince1970)
            }
            diary.mergeHealth(Array(daily.values)); readings=daily.count
            async let count=todaySum(.stepCount,unit:.count())
            async let calories=todaySum(.activeEnergyBurned,unit:.kilocalorie())
            steps=try? await count; activeCalories=try? await calories; lastSync=Date()
            message=values.isEmpty ? diary.t("لم تصل قراءات وزن. قد لا توجد بيانات أو لم تسمح بقراءتها. راجع صلاحيات لُقمة داخل تطبيق صحتي.", "No weight readings were received. There may be no data or read access. Check Luqma permissions in Health.") : diary.t("تم تحديث الوزن من صحتي. القراءات اليدوية محفوظة.", "Weight refreshed from Health. Manual readings are preserved.")
        } catch { handle(error, diary: diary) }
    }
    func profile() async -> (weight:Double?,height:Double?,age:Double?,sex:String?) {
        guard !signingBlocked, profileAllowsHealth != false else { return (nil,nil,nil,nil) }
        let weight=try? await samples(.bodyMass,limit:1).first?.quantity.doubleValue(for:.gramUnit(with:.kilo))
        let height=try? await samples(.height,limit:1).first?.quantity.doubleValue(for:.meterUnit(with:.centi))
        var age:Double?,sex:String?
        if let birth=try? health.dateOfBirthComponents(),let date=Calendar.current.date(from:birth),let years=Calendar.current.dateComponents([.year],from:date,to:Date()).year { age=Double(years) }
        if let biological=try? health.biologicalSex() { if biological.biologicalSex == .male { sex="male" }; if biological.biologicalSex == .female { sex="female" } }
        return (weight,height,age,sex)
    }
}
