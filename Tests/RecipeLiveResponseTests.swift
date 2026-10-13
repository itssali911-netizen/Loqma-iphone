import XCTest
@testable import LuqmaCore

final class RecipeLiveResponseTests: XCTestCase {
    // Actual REST response to our own recipe text; no copied website recipe.
    func testCapturedTextRecipePreservesWholeAmountsAndTwoServings() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "recipe-pasted-response", withExtension: "json"))
        let input = try RecipeImport.input(url: "", pastedText: "Simple scrambled eggs. Makes 2 servings. Ingredients: 2 large eggs, weighing 100 g in total, and 5 g olive oil. Beat the eggs. Heat the oil in a pan. Cook the eggs until set. Divide into two equal servings.")
        let draft = try RecipeImport.parseResponse(Data(contentsOf: url), input: input, language: .ar)
        XCTAssertEqual(draft.sourceKind, .pastedText)
        XCTAssertEqual(draft.ingredients.count, 2)
        XCTAssertEqual(draft.ingredients.map(\.quantity), [100, 5])
        XCTAssertEqual(draft.total?.kcal, 187)
        XCTAssertEqual(draft.perServing?.kcal, 93.5)
        XCTAssertTrue(draft.readyToSave)
        let recipe = try draft.recipe()
        XCTAssertEqual(recipe.portions, 2)
        XCTAssertEqual(recipe.total.kcal, 187)
        XCTAssertEqual(try recipe.food().total(1, unit: .serving).kcal, 93.5)
        XCTAssertEqual(recipe.importInfo?.steps.count, 4)
        var snapshot = DiarySnapshot(); snapshot.recipes = [recipe]
        let recovered = try Backup.decode(Backup.encode(snapshot))
        XCTAssertEqual(recovered.recipes.first?.importInfo, recipe.importInfo)
    }
}
