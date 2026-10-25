import XCTest
@testable import LuqmaCore

final class SandowDesignSystemTests:XCTestCase {
    func testOriginalGridMaintainsThreeEqualColumnsAndExplicitInsets(){
        let width=SandowLayoutTokens.columnWidth(in:375)
        XCTAssertEqual(width,103.6666666667,accuracy:0.000001)
        XCTAssertEqual(width*3+SandowLayoutTokens.gutter*2+SandowLayoutTokens.margin*2,375,accuracy:0.000001)
        let large=SandowLayoutTokens.columnWidth(in:430)
        XCTAssertEqual(large*3+16*2+16*2,430,accuracy:0.000001)
    }
    func testResponsiveGridNeverPropagatesNegativeOrNonfiniteWidths(){
        for width in [0.0,32.0,-10.0,Double.nan,Double.infinity]{XCTAssertEqual(SandowLayoutTokens.columnWidth(in:width),0)}
    }
    func testCachedButtonVariantRetainsItsActualMetrics(){
        XCTAssertEqual(SandowLayoutTokens.PrimaryButton.height,56)
        XCTAssertEqual(SandowLayoutTokens.PrimaryButton.radius,16)
        XCTAssertEqual(SandowLayoutTokens.PrimaryButton.horizontalPadding,28)
        XCTAssertEqual(SandowLayoutTokens.PrimaryButton.contentGap,12)
        XCTAssertEqual(SandowLayoutTokens.PrimaryButton.fontSize,16)
        XCTAssertEqual(SandowLayoutTokens.PrimaryButton.foreground.hex,"#FFFFFF")
    }
    func testReferenceWhiteOnOrangeContrastIsReportedAsAnException(){
        // The latest request preserves the source's foreground. Do not call
        // the 16-point white-label source button WCAG AA compliant.
        XCTAssertEqual(SandowLayoutTokens.PrimaryButton.contrast,2.803,accuracy:0.001)
        XCTAssertLessThan(SandowLayoutTokens.PrimaryButton.contrast,4.5)
        XCTAssertGreaterThan(VisualDesignTokens.onAccent.contrastRatio(against:SandowPalette.orange50),4.5)
    }
}
