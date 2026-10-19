import XCTest
@testable import LuqmaCore

final class FitnessAssessmentTests: XCTestCase {
    private let day = "2026-10-19"
    private func answers(goal: FitnessGoal = .fatLoss) -> FitnessAnswers {
        FitnessAnswers(sex: .male, age: 35, heightCM: 175, weightKG: 80, goal: goal,
                       pace: .gentle, activity: .light, safety: .generalAdult)
    }
    private func plan(_ value: FitnessAnswers) throws -> FitnessPlan {
        try FitnessEstimator.makePlan(profile: FitnessProfile(answers: value, updatedDay: day), day: day)
    }
    private func populatedDiary() throws -> DiarySnapshot {
        var snapshot = DiarySnapshot()
        let food = Food(catalogID: "custom:keep", name: "Personal food", nutrition: Nutrition(kcal: 120, protein: 5, carbs: 16, fat: 4), source: "Your food")
        snapshot.entries = [try DiaryEntry(food: food, amount: 130, unit: .g, meal: .lunch, day: day, language: .en)]
        snapshot.products = [food]; snapshot.searchHistory = [food]; snapshot.barcodeHistory = [food]; snapshot.customFoods = [food]
        snapshot.recipes = [Recipe(id: UUID(), name: "Saved recipe", type: "recipe",
            ingredients: [Ingredient(id: UUID(), name: "Ingredient", amount: 100, unit: .g, kcal: 120, protein: 5, carbs: 16, fat: 4)], portions: 2, notes: "Keep this recipe")]
        snapshot.weights = [WeightReading(day: "2026-10-18", kg: 80, source: "Manual")]
        snapshot.language = .en
        snapshot.weightPlan = WeightPlan(age: 35, height: 175, weight: 80, targetWeight: 75, startDay: day, targetDay: "2027-02-01")
        snapshot.adaptive = true
        return snapshot
    }
    private func assertHistory(_ actual: DiarySnapshot, matches original: DiarySnapshot, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.entries, original.entries, file: file, line: line)
        XCTAssertEqual(actual.recipes, original.recipes, file: file, line: line)
        XCTAssertEqual(actual.weights, original.weights, file: file, line: line)
        XCTAssertEqual(actual.products, original.products, file: file, line: line)
        XCTAssertEqual(actual.searchHistory, original.searchHistory, file: file, line: line)
        XCTAssertEqual(actual.barcodeHistory, original.barcodeHistory, file: file, line: line)
        XCTAssertEqual(actual.customFoods, original.customFoods, file: file, line: line)
        XCTAssertEqual(actual.language, original.language, file: file, line: line)
        XCTAssertEqual(actual.weightPlan, original.weightPlan, file: file, line: line)
    }

    func testOriginalMifflinCoefficientsAndPALHaveIndependentKnownAnswer() throws {
        let result = try plan(answers())
        // Original paper coefficients, not a golden value computed through the production helper.
        XCTAssertEqual(result.bmr, 1725.75, accuracy: 0.000001)
        XCTAssertEqual(result.tdee, 2761.2, accuracy: 0.000001)
        XCTAssertEqual(result.goals.kcal, 2490)
        XCTAssertEqual(result.goals.protein, 155.625, accuracy: 0.000001)
        XCTAssertEqual(result.goals.carbs, 280.125, accuracy: 0.000001)
        XCTAssertEqual(result.goals.fat, 83, accuracy: 0.000001)
        XCTAssertEqual(result.goals.macroCalories, result.goals.kcal, accuracy: 0.000001)
        XCTAssertFalse(result.calorieFloorApplied)
    }
    func testSexIsAnExplicitEquationInputAndMaintenanceIsNotADeficit() throws {
        var value = answers(goal: .maintenance); value.sex = .female
        let result = try plan(value)
        XCTAssertEqual(result.bmr, 1559.75, accuracy: 0.000001)
        XCTAssertEqual(result.tdee, 2495.6, accuracy: 0.000001)
        XCTAssertEqual(result.goals.kcal, 2500)
        XCTAssertEqual(result.goals.protein, 125)
        XCTAssertEqual(result.goals.carbs, 312.5)
    }
    func testGoalPaceAndActivityChangeEstimatesWithoutPromisingATimeline() throws {
        let gentle = try plan(answers())
        var moderate = answers(); moderate.pace = .moderate
        XCTAssertLessThan(try plan(moderate).goals.kcal, gentle.goals.kcal)
        var gain = answers(goal: .muscleGain); gain.pace = .moderate
        XCTAssertGreaterThan(try plan(gain).goals.kcal, gentle.tdee)
        XCTAssertLessThanOrEqual(try plan(gain).energyAdjustment, 255) // 10-kcal display rounding.
        var active = answers(goal: .maintenance); active.activity = .active
        XCTAssertGreaterThan(try plan(active).tdee, gentle.tdee)
        XCTAssertEqual(try plan(answers(goal: .recomposition)).goals.kcal, 2760)
    }
    func testMacroSharesStayWithinGeneralAMDRAndEnergyStaysBalanced() throws {
        for goal in FitnessGoal.allCases {
            for sex in FitnessSex.allCases {
                var value = answers(goal: goal); value.sex = sex
                let result = try plan(value), nutrition = result.goals
                XCTAssertTrue(((0.10 - 1e-9)...(0.35 + 1e-9)).contains(nutrition.protein * 4 / nutrition.kcal))
                XCTAssertTrue(((0.45 - 1e-9)...(0.65 + 1e-9)).contains(nutrition.carbs * 4 / nutrition.kcal))
                XCTAssertTrue(((0.20 - 1e-9)...(0.35 + 1e-9)).contains(nutrition.fat * 9 / nutrition.kcal))
                XCTAssertEqual(nutrition.macroCalories, nutrition.kcal, accuracy: 0.000001)
            }
        }
    }
    func testExplicitSuitabilityIsRequiredAndUnsupportedCasesDoNotMutateDiary() throws {
        let original = try populatedDiary()
        var rejected: [FitnessAnswers] = []
        var value = answers(); value.safety = nil; rejected.append(value)
        value = answers(); value.safety = .pregnantOrBreastfeeding; rejected.append(value)
        value = answers(); value.safety = .medicalDiet; rejected.append(value)
        value = answers(); value.age = 17; rejected.append(value)
        value = answers(); value.heightCM = .nan; rejected.append(value)
        value = answers(); value.weightKG = 400; rejected.append(value)
        for input in rejected {
            var current = original
            XCTAssertThrowsError(try FitnessAssessmentState.preview(input, in: &current, day: day))
            XCTAssertEqual(current.goals, original.goals)
            XCTAssertNil(current.fitnessProfile); XCTAssertNil(current.proposedFitnessPlan)
            assertHistory(current, matches: original)
        }
    }
    func testUnderweightAndContradictoryTargetsAreNotConvertedIntoPlans() throws {
        var value = answers(); value.weightKG = 45
        XCTAssertThrowsError(try plan(value))
        value = answers(); value.targetWeightKG = 45
        XCTAssertThrowsError(try plan(value))
        value.targetWeightKG = 85
        XCTAssertThrowsError(try plan(value))
        value = answers(goal: .muscleGain); value.targetWeightKG = 70
        XCTAssertThrowsError(try plan(value))
    }
    func testConservativeFloorNeverRoundsBelowRestingEstimateOrProductFloor() throws {
        var value = answers(); value.sex = .female; value.age = 100; value.heightCM = 120; value.weightKG = 35; value.activity = .sedentary
        let result = try plan(value)
        XCTAssertTrue(result.calorieFloorApplied)
        XCTAssertGreaterThanOrEqual(result.goals.kcal, 1200)
        XCTAssertGreaterThanOrEqual(result.goals.kcal, result.bmr)
    }
    func testOptionalPreferencesAreRetainedWithoutPretendingTheyAreMedicalOrExerciseMeasurements() throws {
        var value = answers(); value.diet = .vegan; value.allergies = "Peanuts"; value.restrictions = "Prefer home-cooked food"
        value.trainingDays = 7; value.sessionMinutes = 180; value.experience = .beginner
        value.exercise = [.walking, .strength]; value.trainingPlace = .home; value.sleepHours = 5
        let result = try plan(value)
        XCTAssertEqual(result.answers, value)
        XCTAssertEqual(result.activity.trainingDays, 4)
        XCTAssertEqual(result.activity.sessionMinutes, 45)
        XCTAssertEqual(result.activity.strengthDays, 2)
        XCTAssertEqual(result.activity.weeklyCardioMinutes, 150)
        XCTAssertEqual(result.activity.sleepHours, 7)
        XCTAssertEqual(result.goals, try plan(answers()).goals)
    }
    func testDraftPersistsIncompleteAnswersAndExactQuestionAcrossRestart() throws {
        var state = try populatedDiary(), input = FitnessAnswers()
        input.age = 3; input.heightCM = 17; input.allergies = "Sesame"
        let draft = FitnessAssessmentDraft(answers: input, step: .nutrition, updatedDay: day, pageIndex: 17)
        try FitnessAssessmentState.saveDraft(draft, in: &state)
        let restored = try Backup.decode(Backup.encode(state))
        XCTAssertEqual(restored.fitnessDraft, draft)
        XCTAssertNil(restored.fitnessProfile); XCTAssertNil(restored.proposedFitnessPlan)
        XCTAssertEqual(restored.goals, state.goals)
    }
    func testDraftRejectsBrokenClockPageAndUnboundedNotes() throws {
        for clock in ["24:00", "7:30", "08:60", "٠٨:٣٠", "08:30:00"] {
            var value = FitnessAnswers(); value.bedtime = clock
            XCTAssertThrowsError(try value.validate(), clock)
        }
        for clock in ["00:00", "08:30", "23:59"] { XCTAssertTrue(FitnessAnswers.validTime(clock)) }
        var draft = FitnessAssessmentDraft(); draft.pageIndex = 31
        XCTAssertThrowsError(try draft.validate())
        draft.pageIndex = 0; draft.answers.allergies = String(repeating: "x", count: 1001)
        XCTAssertThrowsError(try draft.validate())
    }
    func testPreviewApplyEditAndDeletePreserveAllExistingDiaryResources() throws {
        let original = try populatedDiary(); var state = original
        try FitnessAssessmentState.preview(answers(), in: &state, day: day)
        XCTAssertEqual(state.goals, original.goals); XCTAssertTrue(state.adaptive)
        assertHistory(state, matches: original)
        let proposed = try XCTUnwrap(state.proposedFitnessPlan)
        try FitnessAssessmentState.apply(in: &state)
        XCTAssertEqual(state.goals, proposed.goals); XCTAssertFalse(state.adaptive)
        XCTAssertTrue(FitnessAssessmentState.hasAppliedGoals(state))
        XCTAssertEqual(state.appliedFitnessPlan, proposed); XCTAssertNil(state.proposedFitnessPlan)
        assertHistory(state, matches: original)
        var edited = answers(goal: .maintenance); edited.weightKG = 78
        try FitnessAssessmentState.preview(edited, in: &state, day: day)
        XCTAssertEqual(state.goals, proposed.goals)
        XCTAssertEqual(state.appliedFitnessPlan, proposed)
        XCTAssertEqual(state.fitnessProfile?.revision, proposed.profileRevision + 1)
        assertHistory(state, matches: original)
        FitnessAssessmentState.deleteProfile(in: &state)
        XCTAssertNil(state.fitnessProfile); XCTAssertNil(state.fitnessDraft)
        XCTAssertNil(state.appliedFitnessPlan); XCTAssertNil(state.proposedFitnessPlan)
        XCTAssertEqual(state.goals, proposed.goals)
        assertHistory(state, matches: original)
    }
    func testPlanAndAppliedGoalsSurviveBackupRoundTripAndManualOverrideRemainsExplicit() throws {
        var state = try populatedDiary()
        try FitnessAssessmentState.preview(answers(), in: &state, day: day)
        try FitnessAssessmentState.apply(in: &state)
        let restored = try Backup.decode(Backup.encode(state))
        XCTAssertEqual(restored.fitnessProfile, state.fitnessProfile)
        XCTAssertEqual(restored.appliedFitnessPlan, state.appliedFitnessPlan)
        XCTAssertTrue(FitnessAssessmentState.hasAppliedGoals(restored))
        state.goals = Nutrition.initial
        XCTAssertFalse(FitnessAssessmentState.hasAppliedGoals(state))
        XCTAssertNotNil(state.appliedFitnessPlan) // Historical result is not falsely shown as the active goal.
    }
    func testLatestWeightStagesFreshPreviewAndKeepsAppliedGoalsAndDiary() throws {
        var state = try populatedDiary()
        try FitnessAssessmentState.preview(answers(), in: &state, day: "2026-10-18")
        try FitnessAssessmentState.apply(in: &state)
        let applied = try XCTUnwrap(state.appliedFitnessPlan)
        state.weights.append(WeightReading(day: day, kg: 78, source: "Manual"))
        let history = state
        FitnessAssessmentState.stageLatestWeight(in: &state, day: day)
        XCTAssertEqual(state.fitnessProfile?.answers.weightKG, 78)
        XCTAssertEqual(state.fitnessProfile?.revision, applied.profileRevision + 1)
        XCTAssertEqual(state.proposedFitnessPlan?.answers.weightKG, 78)
        XCTAssertEqual(state.goals, applied.goals)
        XCTAssertEqual(state.appliedFitnessPlan, applied)
        assertHistory(state, matches: history)
        try DiaryValidation.check(state)
    }
    func testUnsupportedNewWeightIsSavedButDoesNotCreateAnUnsafeProposal() throws {
        var state = try populatedDiary()
        try FitnessAssessmentState.preview(answers(), in: &state, day: day)
        try FitnessAssessmentState.apply(in: &state)
        let goals = state.goals
        state.weights.append(WeightReading(day: day, kg: 40, source: "Manual"))
        FitnessAssessmentState.stageLatestWeight(in: &state, day: day)
        XCTAssertEqual(state.weights.last?.kg, 40)
        XCTAssertEqual(state.fitnessProfile?.answers.weightKG, 40)
        XCTAssertNil(state.proposedFitnessPlan)
        XCTAssertEqual(state.goals, goals)
        try DiaryValidation.check(state)
    }
    func testStaleOrTamperedPlanCannotBeAppliedOrImported() throws {
        var state = try populatedDiary()
        try FitnessAssessmentState.preview(answers(), in: &state, day: day)
        state.proposedFitnessPlan?.goals.kcal = 700
        XCTAssertThrowsError(try Backup.encode(state))
        XCTAssertThrowsError(try FitnessAssessmentState.apply(in: &state))
        state.proposedFitnessPlan = nil
        XCTAssertThrowsError(try FitnessAssessmentState.apply(in: &state))
        try FitnessAssessmentState.preview(answers(), in: &state, day: day)
        state.fitnessProfile?.revision += 1
        XCTAssertThrowsError(try Backup.encode(state))
        XCTAssertThrowsError(try FitnessAssessmentState.apply(in: &state))
    }
    func testEditingSavedDraftInvalidatesProposalAndWeightUpdatePreservesOtherDraftAnswers() throws {
        var state = try populatedDiary()
        try FitnessAssessmentState.preview(answers(), in: &state, day: day)
        var edited = answers(); edited.diet = .vegan; edited.allergies = "Sesame"
        let draft = FitnessAssessmentDraft(answers: edited, step: .nutrition, updatedDay: day, pageIndex: 18)
        try FitnessAssessmentState.saveDraft(draft, in: &state)
        XCTAssertNil(state.proposedFitnessPlan)
        XCTAssertThrowsError(try FitnessAssessmentState.apply(in: &state))
        state.weights.append(WeightReading(day: day, kg: 78, source: "Manual"))
        FitnessAssessmentState.stageLatestWeight(in: &state, day: day)
        XCTAssertEqual(state.fitnessDraft, draft)
        XCTAssertEqual(state.proposedFitnessPlan?.answers.weightKG, 78)
        XCTAssertThrowsError(try FitnessAssessmentState.apply(in: &state))
        XCTAssertEqual(state.goals, Nutrition.initial)
        try DiaryValidation.check(state)
    }
    func testOldBackupWithoutNewKeysRemainsReadableAndMergeKeepsExistingAssessment() throws {
        let original = try populatedDiary()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Backup.encode(original)) as? [String: Any])
        for key in ["fitnessDraft", "fitnessProfile", "proposedFitnessPlan", "appliedFitnessPlan", "fitnessOnboardingDismissed"] { object.removeValue(forKey: key) }
        let old = try Backup.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.fitnessDraft); XCTAssertNil(old.fitnessProfile)
        var current = original
        try FitnessAssessmentState.preview(answers(), in: &current, day: day)
        let merged = try Backup.merge(old, into: current)
        XCTAssertEqual(merged.fitnessProfile, current.fitnessProfile)
        XCTAssertEqual(merged.proposedFitnessPlan, current.proposedFitnessPlan)
        assertHistory(merged, matches: original)
    }
    func testImportValidatesAssessmentAndRestoresItWithoutRemovingUnrelatedEntries() throws {
        let current = try populatedDiary()
        var incoming = DiarySnapshot()
        try FitnessAssessmentState.preview(answers(), in: &incoming, day: day)
        let merged = try Backup.merge(try Backup.decode(Backup.encode(incoming)), into: current)
        XCTAssertEqual(merged.fitnessProfile, incoming.fitnessProfile)
        XCTAssertEqual(merged.proposedFitnessPlan, incoming.proposedFitnessPlan)
        assertHistory(merged, matches: current)
        incoming.fitnessDraft?.pageIndex = -1
        XCTAssertThrowsError(try Backup.merge(incoming, into: current))
    }
    func testUntrustedBackupCannotInjectMinorProfileOrAlterCalories() throws {
        var state = try populatedDiary()
        try FitnessAssessmentState.preview(answers(), in: &state, day: day)
        let encoded = try Backup.encode(state)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var profile = try XCTUnwrap(object["fitnessProfile"] as? [String: Any])
        var input = try XCTUnwrap(profile["answers"] as? [String: Any])
        input["age"] = 12; profile["answers"] = input; object["fitnessProfile"] = profile
        XCTAssertThrowsError(try Backup.decode(JSONSerialization.data(withJSONObject: object)))
        object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var proposal = try XCTUnwrap(object["proposedFitnessPlan"] as? [String: Any])
        var goals = try XCTUnwrap(proposal["goals"] as? [String: Any])
        goals["kcal"] = 9000; proposal["goals"] = goals; object["proposedFitnessPlan"] = proposal
        XCTAssertThrowsError(try Backup.decode(JSONSerialization.data(withJSONObject: object)))
    }
    func testOlderAdultSleepSuggestionUsesAgeSpecificRange() throws {
        var input = answers(goal: .maintenance); input.age = 70; input.sleepHours = 9
        XCTAssertEqual(try plan(input).activity.sleepHours, 8)
        input.age = 30
        XCTAssertEqual(try plan(input).activity.sleepHours, 9)
    }
    func testDeletingPreviewOnlyProfileDoesNotDisableAnExistingAdvancedPlanPreference() throws {
        let original = try populatedDiary(); var state = original
        try FitnessAssessmentState.preview(answers(), in: &state, day: day)
        FitnessAssessmentState.deleteProfile(in: &state)
        XCTAssertEqual(state.goals, original.goals)
        XCTAssertTrue(state.adaptive)
        assertHistory(state, matches: original)
    }
}
