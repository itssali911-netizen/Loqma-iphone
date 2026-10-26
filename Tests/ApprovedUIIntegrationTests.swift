import XCTest
@testable import LuqmaCore

final class ApprovedUIIntegrationTests:XCTestCase {
    private let day="2026-10-21"
    private func plan(sex:FitnessSex = .male)throws->FitnessPlan {
        let answers=FitnessAnswers(sex:sex,age:35,heightCM:175,weightKG:80,goal:.fatLoss,pace:.gentle,activity:.light,safety:.generalAdult)
        return try FitnessEstimator.makePlan(profile:FitnessProfile(answers:answers,updatedDay:day),day:day)
    }
    func testNoManualAdjustmentKeepsEveryEstimatedValueExactly()throws {
        let original=try plan()
        XCTAssertEqual(try ApprovedPlanGoals.scaledGoals(for:original,calorieOverride:nil),original.goals)
        XCTAssertEqual(try ApprovedPlanGoals.scaledGoals(for:original,calorieOverride:original.goals.kcal),original.goals)
        try original.validate()
    }
    func testManualTargetPreservesMacroSharesAndEnergyBalance()throws {
        let original=try plan()
        let adjusted=try ApprovedPlanGoals.scaledGoals(for:original,calorieOverride:2540)
        XCTAssertEqual(adjusted.kcal,2540,accuracy:1e-9)
        XCTAssertEqual(adjusted.protein*4/adjusted.kcal,0.25,accuracy:1e-9)
        XCTAssertEqual(adjusted.fat*9/adjusted.kcal,0.30,accuracy:1e-9)
        XCTAssertEqual(adjusted.carbs*4/adjusted.kcal,0.45,accuracy:1e-9)
        XCTAssertEqual(adjusted.macroCalories,adjusted.kcal,accuracy:1e-9)
        XCTAssertEqual(original.goals.kcal,2490)
        try original.validate()
    }
    func testManualTargetsRejectNonFiniteOutsideRangeAndBelowFloor()throws {
        let original=try plan()
        XCTAssertEqual(ApprovedPlanGoals.minimumCalories(for:original),1730)
        for calories in [Double.nan,.infinity,-.infinity,0,1729.9,10000.1]{
            XCTAssertThrowsError(try ApprovedPlanGoals.scaledGoals(for:original,calorieOverride:calories))
        }
        XCTAssertNoThrow(try ApprovedPlanGoals.scaledGoals(for:original,calorieOverride:1730))
        XCTAssertNoThrow(try ApprovedPlanGoals.scaledGoals(for:original,calorieOverride:10000))
    }
    func testFemaleFloorUsesActualRestingEstimateWhenHigherThanProductFloor()throws {
        let original=try plan(sex:.female)
        XCTAssertEqual(original.bmr,1559.75,accuracy:1e-9)
        XCTAssertEqual(ApprovedPlanGoals.minimumCalories(for:original),1560)
        XCTAssertThrowsError(try ApprovedPlanGoals.scaledGoals(for:original,calorieOverride:1550))
    }
    func testInvalidEstimateCannotCreateAnUnboundedOrNonFiniteOverride()throws {
        var original=try plan()
        original.bmr = .nan
        XCTAssertThrowsError(try ApprovedPlanGoals.scaledGoals(for:original,calorieOverride:2500))
        original.bmr=10001
        XCTAssertThrowsError(try ApprovedPlanGoals.scaledGoals(for:original,calorieOverride:10000))
        original.bmr=1725.75;original.goals.kcal=0
        XCTAssertThrowsError(try ApprovedPlanGoals.scaledGoals(for:original,calorieOverride:2500))
    }
    func testManualGoalsRoundTripWithoutChangingComputedPlanOrHistory()throws {
        let original=try plan()
        var state=DiarySnapshot()
        state.weights=[WeightReading(day:day,kg:80,source:"Manual")]
        try FitnessAssessmentState.preview(original.answers,in:&state,day:day)
        let proposal=try XCTUnwrap(state.proposedFitnessPlan)
        let adjusted=try ApprovedPlanGoals.scaledGoals(for:proposal,calorieOverride:2540)
        try FitnessAssessmentState.apply(in:&state)
        state.goals=adjusted
        let restored=try Backup.decode(Backup.encode(state))
        XCTAssertEqual(restored.goals,adjusted)
        XCTAssertEqual(restored.appliedFitnessPlan,proposal)
        XCTAssertEqual(restored.weights,state.weights)
        XCTAssertFalse(FitnessAssessmentState.hasAppliedGoals(restored))
        XCTAssertNil(restored.proposedFitnessPlan)
        try XCTUnwrap(restored.appliedFitnessPlan).validate()
    }
    func testApprovedUnitsConvertQuantitiesWithoutChangingStoredMetricMeaning(){
        XCTAssertEqual(ApprovedMeasurementUnit.imperial.displayed(45.359237,field:.weight),100,accuracy:1e-9)
        XCTAssertEqual(ApprovedMeasurementUnit.imperial.metric(100,field:.weight),45.359237,accuracy:1e-9)
        XCTAssertEqual(ApprovedMeasurementUnit.imperial.displayed(177.8,field:.height),70,accuracy:1e-9)
        XCTAssertEqual(ApprovedMeasurementUnit.imperial.metric(70,field:.height),177.8,accuracy:1e-9)
        XCTAssertEqual(ApprovedMeasurementUnit.metric.metric(175.5,field:.height),175.5)
        XCTAssertEqual(ApprovedCalorieUnit.joules.value(for:1550),6485200)
        XCTAssertEqual(ApprovedCalorieUnit.kcal.value(for:1550),1550)
    }
    func testPresentationUnitPreferenceSurvivesDraftAndBackup(){
        var state=DiarySnapshot()
        state.fitnessDraft=FitnessAssessmentDraft(answers:FitnessAnswers(),step:.basics,updatedDay:day,pageIndex:3,pageID:"height",numericInputs:["height":"175.5","unit.height":"imperial"])
        XCTAssertNoThrow(try {
            let restored=try Backup.decode(Backup.encode(state))
            XCTAssertEqual(restored.fitnessDraft?.numericInputs?["height"],"175.5")
            XCTAssertEqual(restored.fitnessDraft?.numericInputs?["unit.height"],"imperial")
            XCTAssertEqual(restored.fitnessDraft?.resolvedPage,.height)
        }())
    }
    func testImperialPartialInputAndCanonicalQuantitySurviveBackAndResume()throws {
        let unit=ApprovedMeasurementUnit.imperial
        let canonical=unit.canonicalText(from:"100.",field:.weight)
        XCTAssertEqual(try XCTUnwrap(FitnessAssessmentNumberField.weight.parse(canonical)),45.359237,accuracy:1e-9)
        var draft=FitnessAssessmentDraft(updatedDay:day,pageIndex:4,pageID:"weight",numericInputs:["weight":canonical,"unit.weight":"imperial","input.imperial.weight":"100."])
        draft.pageID="height";draft.pageIndex=3
        let returned=try JSONDecoder().decode(FitnessAssessmentDraft.self,from:JSONEncoder().encode(draft))
        XCTAssertEqual(returned.numericInputs?["input.imperial.weight"],"100.")
        XCTAssertEqual(returned.numericInputs?["weight"],canonical)
        XCTAssertEqual(returned.numericInputs?["unit.weight"],"imperial")
        var state=DiarySnapshot();state.fitnessDraft=returned
        let resumed=try Backup.decode(Backup.encode(state))
        XCTAssertEqual(resumed.fitnessDraft?.numericInputs,returned.numericInputs)
        let invalid=unit.canonicalText(from:"999",field:.weight)
        XCTAssertNil(FitnessAssessmentNumberField.weight.parse(invalid))
        XCTAssertEqual(unit.canonicalText(from:"1e2",field:.weight),"1e2")
        XCTAssertEqual(unit.canonicalText(from:"NaN",field:.weight),"NaN")
        XCTAssertEqual(try XCTUnwrap(FitnessAssessmentNumberField.height.parse(unit.canonicalText(from:"٧٠٫٥",field:.height))),179.07,accuracy:1e-9)
    }
    func testCurrentPresentationMetadataFitsFullFutureDraftWithoutLosingKeys()throws {
        var raw=Dictionary(uniqueKeysWithValues:(0..<32).map{("future\($0)","unfinished?")})
        for field in FitnessAssessmentNumberField.allCases{raw[field.rawValue]=""}
        for key in ApprovedAssessmentMetadata.keys{raw[key]="imperial"}
        let draft=FitnessAssessmentDraft(updatedDay:day,numericInputs:raw)
        try draft.validate()
        XCTAssertEqual(raw.count,47)
        var state=DiarySnapshot();state.fitnessDraft=draft
        XCTAssertEqual(try Backup.decode(Backup.encode(state)).fitnessDraft?.numericInputs,raw)
        raw["extraUnknown"]=""
        XCTAssertThrowsError(try FitnessAssessmentDraft(updatedDay:day,numericInputs:raw).validate())
    }
}
