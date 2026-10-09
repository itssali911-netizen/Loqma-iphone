import Foundation
import Combine
import UIKit

@MainActor final class DiaryStore: ObservableObject {
    @Published private(set) var state: DiarySnapshot
    @Published var error: String?
    @Published var adaptiveMessage: String?
    private let file: URL
    private var loadFailed = false
    private(set) var waitingForUnlock = false
    var language: AppLanguage { state.language }
    func t(_ ar: String, _ en: String) -> String { language.text(ar,en) }
    init() {
        let folder = FileManager.default.urls(for: .documentDirectory,in: .userDomainMask)[0]
        file = folder.appendingPathComponent("luqma-diary.json"); state = DiarySnapshot()
        if FileManager.default.fileExists(atPath: file.path) {
            do { state = try Backup.decode(Data(contentsOf: file)) }
            catch {
                if !UIApplication.shared.isProtectedDataAvailable { waitingForUnlock = true }
                else { loadFailed = true; self.error = "تعذّر فتح السجل. أعد تشغيل التطبيق أو استورد نسخة احتياطية؛ الملف الأصلي محفوظ. / Could not open the diary. Restart or import a backup; the original file is preserved." }
            }
        }
        if !waitingForUnlock && !loadFailed { UserDefaults.standard.set(state.healthEnabled, forKey: "luqma.health.connected") }
    }
    func restoreAfterUnlock() -> Bool {
        guard waitingForUnlock else { return !loadFailed }
        guard UIApplication.shared.isProtectedDataAvailable else { return false }
        do { state = try Backup.decode(Data(contentsOf: file)); waitingForUnlock = false; return true }
        catch { loadFailed = true; waitingForUnlock = false; report(error); return false }
    }
    func report(_ e: Error) { error = (e as? AppError)?.message(language) ?? e.localizedDescription }
    private func commit(_ next: DiarySnapshot, recovery: Bool = false) throws {
        if waitingForUnlock { throw AppError.invalid("افتح قفل الآيفون لإكمال تحديث السجل.", "Unlock your iPhone to finish updating the diary.") }
        if loadFailed && !recovery { throw AppError.invalid("استورد نسخة احتياطية أولًا لحماية السجل الموجود.", "Import a backup first to protect the existing diary.") }
        let data = try Backup.encode(next)
        if recovery && loadFailed { try FileManager.default.copyItem(at:file,to:file.deletingLastPathComponent().appendingPathComponent("luqma-recovery-\(UUID().uuidString).json")) }
        try data.write(to: file,options: [.atomic,.completeFileProtection]); state = next; loadFailed = false
        UserDefaults.standard.set(next.healthEnabled, forKey: "luqma.health.connected")
    }
    func change(_ mutation: (inout DiarySnapshot) throws -> Void) {
        do { var next = state; try mutation(&next); try commit(next) } catch { report(error) }
    }
    @discardableResult func add(_ entries: [DiaryEntry]) -> Bool {
        do { var next=state; next.entries += entries; try commit(next); return true } catch { report(error); return false }
    }
    @discardableResult func resize(_ id: UUID, _ amount: Double) -> Bool {
        do { var next = state; guard let i = next.entries.firstIndex(where: { $0.id == id }) else { return false }; try next.entries[i].resize(amount); try commit(next); return true } catch { report(error); return false }
    }
    func remove(_ id: UUID) { change { $0.entries.removeAll { $0.id == id } } }
    func remember(_ food: Food, barcode: Bool) { change { s in
        s.products.removeAll { $0.id == food.id }; s.products.append(food); s.products = Array(s.products.suffix(1000))
        if barcode { s.barcodeHistory.removeAll { $0.id == food.id }; s.barcodeHistory.append(food); s.barcodeHistory = Array(s.barcodeHistory.suffix(30)) }
        else { s.searchHistory.removeAll { $0.id == food.id }; s.searchHistory.append(food); s.searchHistory = Array(s.searchHistory.suffix(30)) }
    } }
    @discardableResult func saveRecipe(_ recipe: Recipe) -> Bool {
        do { var next=state; next.recipes.removeAll { $0.id == recipe.id }; next.recipes.append(recipe); try commit(next); return true } catch { report(error); return false }
    }
    func removeRecipe(_ id: UUID) { change { $0.recipes.removeAll { $0.id == id } } }
    @discardableResult func saveWeight(_ w: WeightReading) -> Bool {do{var s=state;s.weights.removeAll{$0.day==w.day};s.weights.append(w);s.weights.sort{$0.day<$1.day};try commit(s);adapt();return true}catch{report(error);return false}}
    func removeWeight(_ day: String) { change { $0.weights.removeAll { $0.day == day } }; adapt() }
    func mergeHealth(_ readings: [WeightReading]) { change { s in
        for w in readings { if let i=s.weights.firstIndex(where: { $0.day == w.day }) { if s.weights[i].source == "Apple Health" && (w.timestamp ?? 0) >= (s.weights[i].timestamp ?? 0) { s.weights[i]=w } } else { s.weights.append(w) } }; s.weights.sort { $0.day < $1.day }
    }; adapt() }
    @discardableResult func applyHealth(_ cache: HealthSyncState, weights: [WeightReading]?) -> Bool {
        do { var next = state; next.healthSync = cache; if let weights { next.weights = weights }; try commit(next); if weights != nil { adapt() }; return true }
        catch { report(error); return false }
    }
    @discardableResult func importHealthWeights(_ readings: [WeightReading]) -> Bool {
        do {
            var next = state
            for w in readings {
                if let i = next.weights.firstIndex(where: { $0.day == w.day }) {
                    if next.weights[i].source == "Apple Health", (w.timestamp ?? 0) >= (next.weights[i].timestamp ?? 0) { next.weights[i] = w }
                } else { next.weights.append(w) }
            }
            next.weights.sort { $0.day < $1.day }; try commit(next); adapt(); return true
        } catch { report(error); return false }
    }
    func adapt() {
        adaptiveMessage = nil
        guard state.adaptive,let plan=state.weightPlan else { return }
        let average=DiaryValidation.average(state.weights,ending: DayKey.today)
        guard average.count>=3,let kg=average.kg else { adaptiveMessage=t("أضف ٣ قراءات خلال أسبوع لتحديث الهدف.", "Add three readings this week to update the goal."); return }
        do { let goals=try WeightModel.revised(plan,weight:kg,today:DayKey.today); guard !goals.kcal.isNaN else { return }; change { $0.goals=goals }; adaptiveMessage=t("الهدف محسوب من متوسط الوزن خلال الأسبوع.", "The goal uses this week's average weight.") } catch { adaptiveMessage=(error as? AppError)?.message(language) ?? error.localizedDescription }
    }
    @discardableResult func applyPlan(_ p: WeightPlan, _ result: WeightResult) -> Bool {do{var s=state;s.weightPlan=p;s.goals=result.goals;try commit(s);adapt();return true}catch{report(error);return false}}
    @discardableResult func setGoals(_ n: Nutrition) -> Bool {do{var s=state;s.goals=n.balanced();s.adaptive=false;try commit(s);return true}catch{report(error);return false}}
    func importBackup(_ incoming: DiarySnapshot) -> Bool {
        do { let next=try Backup.merge(incoming,into:state); try commit(next,recovery:true); adapt(); return true } catch { report(error); return false }
    }
    func total(_ day: String) -> Nutrition { state.entries.filter { $0.day == day }.reduce(.zero) { $0+$1.nutrition } }
}
