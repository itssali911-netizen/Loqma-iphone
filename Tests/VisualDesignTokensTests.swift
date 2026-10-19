import Foundation
import XCTest
@testable import LuqmaCore

final class VisualDesignTokensTests:XCTestCase {
    func testContrastReferenceAndSymmetry(){
        let black=VisualRGB(hex:0),white=VisualRGB(hex:0xFFFFFF)
        XCTAssertEqual(black.relativeLuminance,0)
        XCTAssertEqual(white.relativeLuminance,1,accuracy:0.0000001)
        XCTAssertEqual(white.contrastRatio(against:black),21,accuracy:0.0000001)
        XCTAssertEqual(black.contrastRatio(against:white),21,accuracy:0.0000001)
        XCTAssertEqual(VisualDesignTokens.card.contrastRatio(against:VisualDesignTokens.card),1)
    }
    func testSRGBTransferFunctionOnBothSidesOfThreshold(){
        XCTAssertEqual(VisualRGB(hex:0x0A0A0A).relativeLuminance,(10.0/255)/12.92,accuracy:0.0000001)
        XCTAssertEqual(VisualRGB(hex:0x0B0B0B).relativeLuminance,pow(((11.0/255)+0.055)/1.055,2.4),accuracy:0.0000001)
    }
    func testOriginalSandowIdentityIsPreserved(){
        XCTAssertEqual(VisualDesignTokens.background.hex,"#111214")
        XCTAssertEqual(VisualDesignTokens.card.hex,"#24262B")
        XCTAssertEqual(VisualDesignTokens.surface.hex,"#393C43")
        XCTAssertEqual(VisualDesignTokens.accent.hex,"#F97316")
        XCTAssertEqual(VisualDesignTokens.secondaryAccent.hex,"#2563EB")
    }
    func testTextAndEssentialControlRolesMeetTheirContrastRequirements(){
        let audit=VisualDesignTokens.contrastAudit
        XCTAssertFalse(audit.isEmpty)
        for result in audit{
            let required=result.role.hasPrefix("controlBorder/") || result.role == "errorBorder/errorBackground" ? 3.0:4.5
            XCTAssertEqual(result.minimum,required,"A role must not lower its acceptance threshold: "+result.role)
            XCTAssertGreaterThanOrEqual(result.ratio,required,result.role+" "+result.foreground+" on "+result.background)
            XCTAssertTrue(result.passed,result.role)
        }
        XCTAssertTrue(audit.contains{$0.role == "secondary/surface"})
        XCTAssertTrue(audit.contains{$0.role == "onAccent/accent"})
        XCTAssertTrue(audit.contains{$0.role == "onSecondaryAccent/secondaryAccent"})
    }
    func testOrdinaryOrangeButtonTextUsesInkInsteadOfWhite(){
        let orange=VisualDesignTokens.accent
        XCTAssertLessThan(VisualDesignTokens.text.contrastRatio(against:orange),3,"White is insufficient even for large orange-button text")
        XCTAssertGreaterThanOrEqual(VisualDesignTokens.onAccent.contrastRatio(against:orange),4.5)
        XCTAssertEqual(VisualDesignTokens.text.contrastRatio(against:orange),2.803,accuracy:0.001)
    }
    func testPressedPrimaryActionRetainsReadableTextOnEachSupportedSurface(){
        for background in [VisualDesignTokens.background,VisualDesignTokens.card,VisualDesignTokens.surface]{
            let foreground=VisualDesignTokens.onAccent.composited(over:background,opacity:0.8)
            let fill=VisualDesignTokens.accent.composited(over:background,opacity:0.8)
            XCTAssertGreaterThanOrEqual(foreground.contrastRatio(against:fill),4.5,"Pressed primary button on "+background.hex)
        }
    }
    func testAuditEncodingIncludesActualOutcome()throws{
        let result=try XCTUnwrap(VisualDesignTokens.contrastAudit.first)
        let encoded=try JSONSerialization.jsonObject(with:JSONEncoder().encode(result)) as? [String:Any]
        XCTAssertEqual(encoded?["passed"] as? Bool,true)
        XCTAssertEqual(encoded?["ratio"] as? Double,result.ratio)
        XCTAssertEqual(encoded?["minimum"] as? Double,result.minimum)
    }
}
