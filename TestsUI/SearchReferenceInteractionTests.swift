import XCTest

final class SearchReferenceInteractionTests:XCTestCase {
    private let app=XCUIApplication()
    override func setUpWithError()throws{continueAfterFailure=false}
    override func tearDownWithError()throws {
        if let testRun,testRun.failureCount>0{print(app.debugDescription);capture("Failed search screen")}
        app.terminate()
    }
    private func launch(_ language:String="en",query:String?=nil){
        app.launchArguments=["-AppleLanguages","("+language+")","-AppleLocale",language=="en" ? "en_US":"ar_SA"]
        app.launchArguments.append(language=="en" ? "-loqma-ui-test-en":"-loqma-ui-test-ar")
        if let query{app.launchArguments += ["-loqma-preview-search","-loqma-preview-search-query",query]}
        app.launch()
    }
    private var results:XCUIElementQuery {app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","food.result."))}
    private func capture(_ name:String){let item=XCTAttachment(screenshot:app.screenshot());item.name=name;item.lifetime = .keepAlways;add(item)}
    func testHomeSearchTypingSelectionAndReturn()throws {
        launch()
        let open=app.buttons["diary.search"]
        XCTAssertTrue(open.waitForExistence(timeout:25));open.tap()
        let query=app.textFields["search.query"]
        XCTAssertTrue(query.waitForExistence(timeout:10));query.tap();query.typeText("milk")
        XCTAssertTrue(results.firstMatch.waitForExistence(timeout:15),app.debugDescription)
        capture("Live search with keyboard")
        results.firstMatch.tap()
        let amount=app.textFields["portion.amount"]
        XCTAssertTrue(amount.waitForExistence(timeout:15));XCTAssertEqual(amount.value as? String,"1")
        XCTAssertTrue(app.buttons["portion.unit.serving"].isSelected)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(query.waitForExistence(timeout:10));XCTAssertEqual(query.value as? String,"milk")
        XCTAssertTrue(results.firstMatch.waitForExistence(timeout:10));capture("Returned search preserves query")
        app.buttons["search.close"].tap()
        XCTAssertTrue(open.waitForExistence(timeout:10))
    }
    func testFiltersAndSortUseActualResults()throws {
        launch(query:"milk")
        XCTAssertTrue(results.firstMatch.waitForExistence(timeout:20))
        let query=app.textFields["search.query"]
        let initialCount=results.count
        app.buttons["search.sort"].tap()
        app.buttons["Name similarity: lowest first"].tap()
        XCTAssertEqual(query.value as? String,"milk")
        XCTAssertEqual(results.count,initialCount)
        let own=app.buttons["search.filter.3"]
        if !own.isHittable{app.buttons["search.filter.1"].swipeLeft()}
        own.tap()
        XCTAssertTrue(app.otherElements["search.empty"].waitForExistence(timeout:10))
        XCTAssertEqual(results.count,0)
        let all=app.buttons["search.filter.0"]
        if !all.isHittable{app.buttons["search.filter.2"].swipeRight()}
        all.tap()
        XCTAssertTrue(results.firstMatch.waitForExistence(timeout:10));XCTAssertEqual(query.value as? String,"milk")
        capture("Actual source filters restored")
    }
    func testArabicSearchMirrorsOnlyDirectionalLayout()throws {
        launch("ar",query:"حليب")
        let query=app.textFields["search.query"],back=app.buttons["search.close"]
        XCTAssertTrue(query.waitForExistence(timeout:15));XCTAssertTrue(results.firstMatch.waitForExistence(timeout:20))
        XCTAssertEqual(query.value as? String,"حليب")
        XCTAssertGreaterThan(back.frame.midX,app.frame.midX,"Arabic back control must be on the leading RTL edge")
        XCTAssertLessThan(app.buttons["search.submit"].frame.midX,query.frame.midX)
        capture("Actual Arabic RTL food search")
    }
}
