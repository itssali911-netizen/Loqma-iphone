import XCTest
@testable import LuqmaCore

final class MealImageContentTests:XCTestCase {
    func testFeaturelessWhiteBlackAndLowContrastFramesAreRejected() {
        for value in [UInt8(0),127,255] {XCTAssertFalse(MealImageContent.hasVisibleDetail([UInt8](repeating:value,count:1024)))}
        XCTAssertFalse(MealImageContent.hasVisibleDetail((0..<1024).map {UInt8(127+$0%2)}))
        XCTAssertFalse(MealImageContent.hasVisibleDetail([]))
    }
    func testTexturedAndDimFramesRetainDetailsWithoutRequiringHighBrightness() {
        XCTAssertTrue(MealImageContent.hasVisibleDetail((0..<1024).map {UInt8($0%30)}))
        XCTAssertTrue(MealImageContent.hasVisibleDetail((0..<1024).map {UInt8(190+$0%30)}))
    }
}
