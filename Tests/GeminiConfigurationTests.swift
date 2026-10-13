import XCTest
@testable import LuqmaCore

final class GeminiConfigurationTests:XCTestCase {
    private let fakeKey="test_configuration_key_1234567890"
    private func data(model:String=GeminiMeal.modelID,version:Any=1,format:String="luqma-gemini-settings",key:String?=nil)throws->Data {
        try JSONSerialization.data(withJSONObject:["format":format,"version":version,"model":model,"apiKey":key ?? fakeKey])
    }
    func testConfigurationRequiresExactModelAndFormatAndValidKey()throws {
        XCTAssertEqual(try GeminiConfiguration.key(from:data()),fakeKey)
        XCTAssertThrowsError(try GeminiConfiguration.key(from:data(model:"different-model")))
        XCTAssertThrowsError(try GeminiConfiguration.key(from:data(version:2)))
        XCTAssertThrowsError(try GeminiConfiguration.key(from:data(version:true)))
        XCTAssertThrowsError(try GeminiConfiguration.key(from:data(format:"backup")))
        XCTAssertThrowsError(try GeminiConfiguration.key(from:data(key:"short")))
    }
    func testInvalidOrOversizedConfigurationFailsWithoutRevealingKey() {
        for value in [Data(),Data(repeating:65,count:8193),Data("{broken}".utf8)] {
            XCTAssertThrowsError(try GeminiConfiguration.key(from:value))
        }
    }
    func testLegacyConnectionKeySurvivesModelMigration() throws {
        XCTAssertEqual(try GeminiConfiguration.key(from:data(model:"gemini-3.8-flash")),fakeKey)
        XCTAssertEqual(try GeminiConfiguration.key(from:data(model:AnalysisModel.backup.modelID)),fakeKey)
    }
}
