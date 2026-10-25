import XCTest
@testable import LuqmaCore

final class SearchResultPresentationTests:XCTestCase {
    func testTextSimilarityUsesRealNamesAndNormalizedArabic(){
        let food=Food(catalogID:"personal:a",name:"أَرُز دجاج",nameEn:"Chicken Rice",brand:"Brand",source:"Your food")
        XCTAssertEqual(SearchNameSimilarity.percent(query:"دجاج ارز",food:food),100)
        XCTAssertEqual(SearchNameSimilarity.percent(query:"rice chicken",food:food),100)
        XCTAssertNil(SearchNameSimilarity.percent(query:"  ",food:food))
        XCTAssertEqual(SearchNameSimilarity.percent(query:"zzzz",food:food),0)
        XCTAssertEqual(SearchNameSimilarity.percent(query:"Brand",food:food),100)
        XCTAssertEqual(SearchNameSimilarity.percent(query:"Brand Chicken Rice",food:food),100)
    }
    func testPartialAndRepeatedStringsStayBounded(){
        for name in ["a","aaaaa","Apple salad","", "حليب المراعي"]{
            let value=SearchNameSimilarity.percent(query:"apple",food:Food(name:name))
            XCTAssertTrue((0...100).contains(value ?? -1))
        }
        let food=Food(name:"Apple salad")
        let value=SearchNameSimilarity.percent(query:"apple",food:food) ?? 0
        XCTAssertGreaterThan(value,0);XCTAssertLessThan(value,100)
    }
    func testSortingIsStableAndPreservesDatabaseBestMatchOrder(){
        let foods=[Food(catalogID:"a",name:"A"),Food(catalogID:"b",name:"B"),Food(catalogID:"c",name:"C")]
        let scores=[foods[0].id:20,foods[1].id:80,foods[2].id:80]
        XCTAssertEqual(SearchResultOrder.bestMatch.arrange(foods,scores:scores).map(\.id),foods.map(\.id))
        XCTAssertEqual(SearchResultOrder.similarityDescending.arrange(foods,scores:scores).map(\.id),[foods[1].id,foods[2].id,foods[0].id])
        XCTAssertEqual(SearchResultOrder.similarityAscending.arrange(foods,scores:scores).map(\.id),foods.map(\.id))
    }
    func testEmptyResultsRequireACompletedSearchAndErrorsNeverMasqueradeAsNoResults(){
        XCTAssertEqual(SearchScreenPhase.resolve(resultCount:0,isBusy:false,completed:false,hasError:false),.idle)
        XCTAssertEqual(SearchScreenPhase.resolve(resultCount:0,isBusy:true,completed:false,hasError:false),.loading)
        XCTAssertEqual(SearchScreenPhase.resolve(resultCount:0,isBusy:false,completed:true,hasError:false),.empty)
        XCTAssertEqual(SearchScreenPhase.resolve(resultCount:0,isBusy:false,completed:true,hasError:true),.error)
        XCTAssertEqual(SearchScreenPhase.resolve(resultCount:1,isBusy:true,completed:false,hasError:true),.results)
    }
}
