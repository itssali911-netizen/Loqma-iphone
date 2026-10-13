import XCTest
@testable import LuqmaCore

final class HealthActivityTests: XCTestCase {
    private let day = "2026-10-13"
    private func snapshot(active: Double = 1000) -> DiarySnapshot {
        var state = DiarySnapshot()
        var plan = WeightPlan()
        plan.age = 30; plan.height = 180; plan.weight = 90; plan.targetWeight = 80
        plan.startDay = "2026-10-01"; plan.targetDay = "2027-02-01"; plan.pal = 1.6
        state.weightPlan = plan; state.healthEnabled = true
        state.healthSync = HealthSyncState(activityDay: day, steps: 12000, activeCalories: active,
                                          distanceKM: 8, exerciseMinutes: 45, workoutCount: 2, adjustmentEnabled: true, planGoalAssociated: true)
        return state
    }
    func testDailySnapshotReplacesDeletedActivityAndKeepsWeightCursorAndPreference() {
        let id = UUID()
        let old = HealthSyncState(anchor: Data([1, 2]), activityDay: "2026-10-12", steps: 9000,
                                  activeCalories: 500, distanceKM: 7, exerciseMinutes: 30, workoutCount: 2, adjustmentEnabled: true)
        let updated = HealthActivity.update(old, day: day, steps: 0, activeCalories: 100,
                                            distanceKM: 0.5, exerciseMinutes: nil, workoutIDs: [id, id])
        XCTAssertEqual(updated.activityDay, day)
        XCTAssertEqual(updated.steps, 0)
        XCTAssertEqual(updated.workoutCount, 1)
        XCTAssertNil(updated.exerciseMinutes)
        XCTAssertEqual(updated.anchor, old.anchor)
        XCTAssertEqual(updated.adjustmentEnabled, true)
        XCTAssertEqual(HealthActivity.update(updated, day: day, steps: 0, activeCalories: 100,
                                              distanceKM: 0.5, exerciseMinutes: nil, workoutIDs: [id]), updated)
        let deleted = HealthActivity.update(updated, day: day, steps: nil, activeCalories: nil,
                                            distanceKM: nil, exerciseMinutes: nil, workoutIDs: [])
        XCTAssertNil(deleted.steps); XCTAssertNil(deleted.activeCalories); XCTAssertNil(deleted.workoutCount)
    }
    func testInvalidReadingsRemainUnknownAndKnownZeroIsPreserved() {
        let cache = HealthActivity.update(HealthSyncState(), day: day, steps: .infinity,
                                         activeCalories: -1, distanceKM: .nan, exerciseMinutes: 1441, workoutIDs: [])
        XCTAssertNil(cache.steps); XCTAssertNil(cache.activeCalories)
        XCTAssertNil(cache.distanceKM); XCTAssertNil(cache.exerciseMinutes)
        XCTAssertEqual(HealthActivity.valid(0, maximum: 1440), 0)
        XCTAssertNil(HealthActivity.valid(nil, maximum: 1440))
    }
    func testPlannedActivityUsesSavedPhysicalActivityAndChange() throws {
        var state = snapshot()
        state.weightPlan?.activityChange = 20
        let plan = try XCTUnwrap(state.weightPlan)
        let model = WeightModel.baseline(plan)
        XCTAssertEqual(try XCTUnwrap(HealthActivity.plannedCalories(state, day: day)),
                       max(0, (0.9 * model.maintenance - model.resting) * 1.2), accuracy: 0.000001)
        state.adaptive = true
        state.weights = [WeightReading(day: "2026-10-11", kg: 80), WeightReading(day: "2026-10-12", kg: 81), WeightReading(day: day, kg: 82)]
        var revised = plan; revised.weight = 81
        XCTAssertEqual(try XCTUnwrap(HealthActivity.plannedCalories(state, day: day)),
                       WeightModel.baseline(revised).activity * 81 * 1.2, accuracy: 0.000001)
    }
    func testOnlyActivityAbovePlanAddsCaloriesAndNoStepOrWorkoutDoubleCount() throws {
        var state = snapshot()
        let planned = try XCTUnwrap(HealthActivity.plannedCalories(state, day: day))
        state.healthSync?.activeCalories = planned + 120.9
        XCTAssertEqual(HealthActivity.adjustment(state, day: day, today: day), 120)
        state.healthSync?.steps = 250000; state.healthSync?.workoutCount = 500; state.healthSync?.exerciseMinutes = 1400
        XCTAssertEqual(HealthActivity.adjustment(state, day: day, today: day), 120)
        state.healthSync?.activeCalories = planned - 1
        XCTAssertEqual(HealthActivity.adjustment(state, day: day, today: day), 0)
        state.healthSync?.activeCalories = nil
        XCTAssertEqual(HealthActivity.adjustment(state, day: day, today: day), 0)
    }
    func testAdjustmentIsOffByDefaultAndRequiresCurrentConnectedDayAndKnownPlan() {
        var state = snapshot()
        state.healthSync?.adjustmentEnabled = nil
        XCTAssertEqual(HealthActivity.adjustment(state, day: day, today: day), 0)
        state.healthSync?.adjustmentEnabled = true; state.healthEnabled = false
        XCTAssertEqual(HealthActivity.adjustment(state, day: day, today: day), 0)
        state.healthEnabled = true; state.healthSync?.activityDay = "2026-10-12"
        XCTAssertEqual(HealthActivity.adjustment(state, day: day, today: day), 0)
        state.healthSync?.activityDay = day
        XCTAssertEqual(HealthActivity.adjustment(state, day: day, today: "2026-10-14"), 0)
        state.weightPlan = nil
        XCTAssertEqual(HealthActivity.adjustment(state, day: day, today: day), 0)
        XCTAssertNil(HealthActivity.plannedCalories(state, day: day))
    }
    func testAdjustedGoalsKeepMacroSplitAndSavedGoalsAndLimit() {
        var state = snapshot(active: 50000)
        let original = state.goals
        let result = HealthActivity.goals(state, day: day, today: day)
        XCTAssertEqual(result.kcal, 10000)
        XCTAssertEqual(result.protein / original.protein, result.kcal / original.kcal, accuracy: 0.000001)
        XCTAssertEqual(result.carbs / original.carbs, result.kcal / original.kcal, accuracy: 0.000001)
        XCTAssertEqual(result.fat / original.fat, result.kcal / original.kcal, accuracy: 0.000001)
        XCTAssertEqual(state.goals, original)
        state.healthSync?.activeCalories = .infinity
        XCTAssertEqual(HealthActivity.goals(state, day: day, today: day), original)
    }
    func testActivityBackupFieldsMigrateAndValidate() throws {
        var state = snapshot()
        let encoded = try Backup.encode(state)
        XCTAssertEqual(try Backup.decode(encoded).healthSync, state.healthSync)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var oldCache = try XCTUnwrap(object["healthSync"] as? [String: Any])
        for key in ["distanceKM", "exerciseMinutes", "workoutCount", "adjustmentEnabled", "planGoalAssociated"] { oldCache.removeValue(forKey: key) }
        object["healthSync"] = oldCache
        let migrated = try Backup.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(migrated.healthSync?.distanceKM)
        XCTAssertNil(migrated.healthSync?.adjustmentEnabled)
        XCTAssertNil(migrated.healthSync?.planGoalAssociated)
        XCTAssertNil(HealthActivity.plannedCalories(migrated, day: day))
        state.healthSync?.exerciseMinutes = -1
        XCTAssertThrowsError(try Backup.encode(state))
        state.healthSync?.exerciseMinutes = 30; state.healthSync?.distanceKM = .infinity
        XCTAssertThrowsError(try Backup.encode(state))
    }
    func testBackupMergeRetainsLocalActivityButRequiresNewOptInForImportedGoals() throws {
        let current = snapshot()
        var incoming = DiarySnapshot(); incoming.goals = Nutrition(kcal: 1800, protein: 100, carbs: 215, fat: 60)
        incoming.healthSync = HealthSyncState(activityDay: day, steps: 5, activeCalories: 5, adjustmentEnabled: true)
        let merged = try Backup.merge(incoming, into: current)
        XCTAssertEqual(merged.healthSync?.steps, current.healthSync?.steps)
        XCTAssertEqual(merged.healthSync?.activeCalories, current.healthSync?.activeCalories)
        XCTAssertEqual(merged.healthSync?.adjustmentEnabled, false)
        XCTAssertEqual(merged.healthSync?.planGoalAssociated, false)
        var forcedOptIn = merged; forcedOptIn.healthSync?.adjustmentEnabled = true
        XCTAssertNil(HealthActivity.plannedCalories(forcedOptIn, day: day))
        XCTAssertEqual(HealthActivity.adjustment(forcedOptIn, day: day, today: day), 0)
    }
    func testManualGoalOverrideInvalidatesRetainedPlanAndCannotForceOptIn() {
        var state = snapshot(active: 5000)
        XCTAssertGreaterThan(HealthActivity.adjustment(state, day: day, today: day), 0)
        state.goals = Nutrition(kcal: 1800, protein: 100, carbs: 215, fat: 60)
        HealthActivity.setGoalAssociation(false, in: &state)
        XCTAssertNotNil(state.weightPlan)
        XCTAssertEqual(state.healthSync?.planGoalAssociated, false)
        XCTAssertEqual(state.healthSync?.adjustmentEnabled, false)
        state.healthSync?.adjustmentEnabled = true
        XCTAssertNil(HealthActivity.plannedCalories(state, day: day))
        XCTAssertEqual(HealthActivity.adjustment(state, day: day, today: day), 0)
    }
    func testAppliedPlanAssociationIsExplicitAndDoesNotEnableAdjustment() {
        var state = snapshot(active: 5000)
        state.healthSync?.planGoalAssociated = nil; state.healthSync?.adjustmentEnabled = nil
        XCTAssertNil(HealthActivity.plannedCalories(state, day: day))
        HealthActivity.setGoalAssociation(true, in: &state)
        XCTAssertNotNil(HealthActivity.plannedCalories(state, day: day))
        XCTAssertNil(state.healthSync?.adjustmentEnabled)
        XCTAssertEqual(HealthActivity.adjustment(state, day: day, today: day), 0)
        state.healthSync?.adjustmentEnabled = true
        XCTAssertGreaterThan(HealthActivity.adjustment(state, day: day, today: day), 0)
    }
}
