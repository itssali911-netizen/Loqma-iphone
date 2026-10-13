import XCTest
@testable import LuqmaCore

final class RecipeRecalculationTests:XCTestCase {
    private func partial() -> RecipeImportDraft {
        RecipeImportDraft(title:"Rice",servings:2,ingredients:[RecipeImportIngredient(name:"Cooked rice",quantity:nil,unit:.g,unitLabel:"g",nutrition:nil,assumption:"")],steps:["Serve warm."],sourceURL:"https://www.instagram.com/reel/recipe/",assumptions:[],sourceKind:.website)
    }
    func testMissingQuantitiesDoNotBecomeDefaultsAndReviewedAmountsAreExplicitInput() throws {
        var draft=partial();XCTAssertFalse(draft.canRecalculate);XCTAssertThrowsError(try draft.recalculationInput())
        draft.ingredients[0].quantity=200
        XCTAssertTrue(draft.canRecalculate)
        let input=try draft.recalculationInput()
        XCTAssertEqual(input.sourceKind,.pastedText)
        XCTAssertTrue(input.pastedText.contains("200.000000 g Cooked rice"))
        XCTAssertTrue(input.pastedText.contains("Makes 2.000000 servings"))
        XCTAssertFalse(input.pastedText.contains("kcal"))
        draft.servings=nil;XCTAssertFalse(draft.canRecalculate)
    }
    func testRecalculationRetainsOriginalLinkAndPreparationWithReviewNote() {
        let original=partial();var calculated=original
        calculated.sourceURL=nil;calculated.sourceKind = .pastedText;calculated.steps=["Changed model steps"]
        let final=calculated.retainingSource(of:original,language:.en)
        XCTAssertEqual(final.sourceURL,original.sourceURL);XCTAssertEqual(final.sourceKind,.website)
        XCTAssertEqual(final.steps,original.steps)
        XCTAssertTrue(final.assumptions.contains(where:{$0.contains("reviewed quantities")}))
    }
}
