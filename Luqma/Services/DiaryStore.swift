import Foundation
import Combine
import UIKit

@MainActor final class DiaryStore: ObservableObject {
    @Published private(set) var state: DiarySnapshot
    @Published var error: String?
    @Published var adaptiveMessage: String?
    private let file: URL
    private var loadFailed = false
    private var persistenceRevision = 0
    private var fitnessDraftSaveGeneration = 0
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
    }
    #if DEBUG
    // Native visual fixtures use an isolated temporary file, never the user's diary.
    init(previewSnapshot: DiarySnapshot) {
        file = FileManager.default.temporaryDirectory.appendingPathComponent("luqma-preview-\(UUID().uuidString).json")
        state = previewSnapshot
    }
    #endif
    func restoreAfterUnlock() -> Bool {
        guard waitingForUnlock else { return !loadFailed }
        guard UIApplication.shared.isProtectedDataAvailable else { return false }
        do { state = try Backup.decode(Data(contentsOf: file)); persistenceRevision += 1; fitnessDraftSaveGeneration += 1; waitingForUnlock = false; return true }
        catch { loadFailed = true; waitingForUnlock = false; report(error); return false }
    }
    func report(_ e: Error) { error = (e as? AppError)?.message(language) ?? e.localizedDescription }
    private func commit(_ next: DiarySnapshot, recovery: Bool = false) throws {
        try checkWritable(recovery: recovery)
        let data = try Backup.encode(next)
        try commitEncoded(data, next: next, recovery: recovery)
    }
    private func checkWritable(recovery: Bool = false) throws {
        if waitingForUnlock { throw AppError.invalid("افتح قفل الآيفون لإكمال تحديث السجل.", "Unlock your iPhone to finish updating the diary.") }
        if loadFailed && !recovery { throw AppError.invalid("استورد نسخة احتياطية أولًا لحماية السجل الموجود.", "Import a backup first to protect the existing diary.") }
    }
    private func commitEncoded(_ data: Data, next: DiarySnapshot, recovery: Bool = false) throws {
        try checkWritable(recovery: recovery)
        if recovery && loadFailed { try FileManager.default.copyItem(at:file,to:file.deletingLastPathComponent().appendingPathComponent("luqma-recovery-\(UUID().uuidString).json")) }
        try data.write(to: file,options: [.atomic,.completeFileProtection])
        if state.fitnessDraft != next.fitnessDraft || state.fitnessProfile != next.fitnessProfile {
            fitnessDraftSaveGeneration += 1
        }
        state = next; loadFailed = false; persistenceRevision += 1
    }
    func change(_ mutation: (inout DiarySnapshot) throws -> Void) {
        do { var next = state; try mutation(&next); try commit(next) } catch { report(error) }
    }
    @discardableResult func add(_ entries: [DiaryEntry], foods: [Food] = []) -> Bool {
        do {
            var next = state
            next.entries += entries
            for food in foods { try FoodHistory.remember(food, in: &next, barcode: food.barcode != nil) }
            try commit(next)
            return true
        } catch { report(error); return false }
    }
    @discardableResult func resize(_ id: UUID, _ amount: Double) -> Bool {
        do { var next = state; guard let i = next.entries.firstIndex(where: { $0.id == id }) else { return false }; try next.entries[i].resize(amount); try commit(next); return true } catch { report(error); return false }
    }
    func remove(_ id: UUID) { change { $0.entries.removeAll { $0.id == id } } }
    func rememberPersisted(_ food: Food, barcode: Bool) throws {
        var next = state
        try FoodHistory.remember(food, in: &next, barcode: barcode)
        try commit(next)
    }
    func remember(_ food: Food, barcode: Bool) {
        do { try rememberPersisted(food, barcode: barcode) } catch { report(error) }
    }
    var personalFoods: [Food] { FoodHistory.yourFoods(in: state) }
    @discardableResult func removePersonal(_ foodID: String) -> Bool {
        do {
            var next = state
            next.customFoods = (next.customFoods ?? []).filter { $0.id != foodID }
            next.products.removeAll { $0.id == foodID }
            next.searchHistory.removeAll { $0.id == foodID }
            next.barcodeHistory.removeAll { $0.id == foodID }
            // Past diary entries retain the values that were actually logged.
            try commit(next)
            return true
        } catch { report(error); return false }
    }
    func recentFoods(catalog: [Food] = []) -> [Food] {
        FoodHistory.recent(entries: state.entries, foods: FoodHistory.candidates(in: state, catalog: catalog))
    }
    func frequentFoods(catalog: [Food] = []) -> [Food] {
        FoodHistory.frequent(entries: state.entries, foods: FoodHistory.candidates(in: state, catalog: catalog))
    }
    @discardableResult func saveRecipe(_ recipe: Recipe) -> Bool {
        do { var next=state; next.recipes.removeAll { $0.id == recipe.id }; next.recipes.append(recipe); try commit(next); return true } catch { report(error); return false }
    }
    func removeRecipe(_ id: UUID) { change { $0.recipes.removeAll { $0.id == id } } }
    @discardableResult func saveWeight(_ w: WeightReading) -> Bool {
        do {
            var next = state
            next.weights.removeAll { $0.day == w.day }
            next.weights.append(w)
            next.weights.sort { $0.day < $1.day }
            if w.day >= (next.fitnessProfile?.updatedDay ?? DayKey.today) && w.day <= DayKey.today {
                FitnessAssessmentState.stageLatestWeight(in: &next)
            }
            try commit(next)
            adapt()
            return true
        } catch { report(error); return false }
    }
    func removeWeight(_ day: String) { change { $0.weights.removeAll { $0.day == day } }; adapt() }
    func adapt() {
        adaptiveMessage = nil
        guard state.adaptive,let plan=state.weightPlan else { return }
        let average=DiaryValidation.average(state.weights,ending: DayKey.today)
        guard average.count>=3,let kg=average.kg else { adaptiveMessage=t("أضف ٣ قراءات خلال أسبوع لتحديث الهدف.", "Add three readings this week to update the goal."); return }
        do { let goals=try WeightModel.revised(plan,weight:kg,today:DayKey.today); guard !goals.kcal.isNaN else { return }; change { $0.goals=goals }; adaptiveMessage=t("الهدف محسوب من متوسط الوزن خلال الأسبوع.", "The goal uses this week's average weight.") } catch { adaptiveMessage=(error as? AppError)?.message(language) ?? error.localizedDescription }
    }
    @discardableResult func applyPlan(_ p: WeightPlan, _ result: WeightResult) -> Bool {do{var s=state;s.weightPlan=p;s.goals=result.goals;try commit(s);adapt();return true}catch{report(error);return false}}
    @discardableResult func setGoals(_ n: Nutrition) -> Bool {do{var s=state;s.goals=n.balanced();s.adaptive=false;try commit(s);return true}catch{report(error);return false}}
    @discardableResult func saveFitnessDraft(_ draft: FitnessAssessmentDraft) -> Bool {
        fitnessDraftSaveGeneration += 1
        do { var next = state; try FitnessAssessmentState.saveDraft(draft, in: &next); try commit(next); return true }
        catch { report(error); return false }
    }
    /// Validate/encode the potentially large diary away from the UI actor.
    /// Only the atomic replacement is synchronous. If another operation saved
    /// while encoding, rebuild from its latest state instead of overwriting it.
    @discardableResult func saveFitnessDraftInBackground(_ draft: FitnessAssessmentDraft, deferAssessment: Bool = false) async -> Bool {
        if state.fitnessDraft == draft && (!deferAssessment || state.fitnessOnboardingDismissed == true) {
            fitnessDraftSaveGeneration += 1
            return true
        }
        return await commitFitnessChange { next in
            try FitnessAssessmentState.saveDraft(draft, in: &next)
            if deferAssessment { next.fitnessOnboardingDismissed = true }
        }
    }
    @discardableResult func previewFitnessPlanInBackground(_ answers: FitnessAnswers) async -> Bool {
        await commitFitnessChange { next in try FitnessAssessmentState.preview(answers, in: &next) }
    }
    private func commitFitnessChange(_ mutation: (inout DiarySnapshot) throws -> Void) async -> Bool {
        fitnessDraftSaveGeneration += 1
        let generation = fitnessDraftSaveGeneration
        do {
            for _ in 0..<3 {
                try checkWritable()
                let revision = persistenceRevision
                var next = state
                try mutation(&next)
                let snapshot = next
                let data = try await Task.detached(priority: .userInitiated) { try Backup.encode(snapshot) }.value
                // A newer fitness action owns the result. In particular, an
                // old sheet's fallback save must not resurrect deleted data.
                guard fitnessDraftSaveGeneration == generation else { return false }
                guard persistenceRevision == revision else { continue }
                try commitEncoded(data, next: next)
                return true
            }
            throw AppError.invalid("السجل يتحدّث الآن. حاول الحفظ مرة أخرى.", "The diary is updating. Try saving again.")
        } catch { report(error); return false }
    }
    @discardableResult func previewFitnessPlan(_ answers: FitnessAnswers) -> Bool {
        fitnessDraftSaveGeneration += 1
        do { var next = state; try FitnessAssessmentState.preview(answers, in: &next); try commit(next); return true }
        catch { report(error); return false }
    }
    @discardableResult func applyFitnessPlan(calorieOverride: Double? = nil) -> Bool {
        fitnessDraftSaveGeneration += 1
        do {
            var next = state
            try FitnessAssessmentState.apply(in: &next)
            if let calorieOverride, let plan = next.appliedFitnessPlan {
                // The approved +/- control is an explicit manual goal choice.
                // Keep the reproducible calculated plan intact and commit both
                // its application and the chosen targets in one atomic save.
                next.goals = try ApprovedPlanGoals.scaledGoals(for: plan, calorieOverride: calorieOverride)
                next.adaptive = false
            }
            try commit(next)
            adaptiveMessage = nil
            return true
        }
        catch { report(error); return false }
    }
    @discardableResult func discardFitnessDraft() -> Bool {
        fitnessDraftSaveGeneration += 1
        do { var next = state; next.fitnessDraft = nil; try commit(next); return true }
        catch { report(error); return false }
    }
    @discardableResult func deleteFitnessProfile() -> Bool {
        fitnessDraftSaveGeneration += 1
        do { var next = state; FitnessAssessmentState.deleteProfile(in: &next); try commit(next); return true }
        catch { report(error); return false }
    }
    @discardableResult func deferFitnessAssessment() -> Bool {
        do { var next = state; next.fitnessOnboardingDismissed = true; try commit(next); return true }
        catch { report(error); return false }
    }
    func importBackup(_ incoming: DiarySnapshot) -> Bool {
        fitnessDraftSaveGeneration += 1
        do { let next=try Backup.merge(incoming,into:state); try commit(next,recovery:true); adapt(); return true } catch { report(error); return false }
    }
    func total(_ day: String) -> Nutrition { state.entries.filter { $0.day == day }.reduce(.zero) { $0+$1.nutrition } }
    // Legacy activity fields stay decodable for old backups, but cannot alter goals.
    func dailyGoals(_ day: String) -> Nutrition { state.goals }
}
