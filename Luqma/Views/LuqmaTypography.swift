import SwiftUI
import UIKit

enum LTypography {
    // The reference uses Gilroy. Tajawal is the licensed Arabic/Latin companion
    // distributed with this app; both scripts and western digits use one family.
    static func font(size:CGFloat,weight:Font.Weight = .regular,relativeTo:Font.TextStyle = .body)->Font {
        .custom(face(for:weight),size:size,relativeTo:relativeTo)
    }

    static var title:Font {font(size:22,weight:.heavy,relativeTo:.title)}
    static var title2:Font {font(size:22,weight:.heavy,relativeTo:.title2)}
    static var title3:Font {font(size:18,weight:.bold,relativeTo:.title3)}
    static var headline:Font {font(size:16,weight:.bold,relativeTo:.headline)}
    static var subheadline:Font {font(size:15,relativeTo:.subheadline)}
    static var body:Font {font(size:16,weight:.light,relativeTo:.body)}
    static var callout:Font {font(size:16,relativeTo:.callout)}
    static var footnote:Font {font(size:13,relativeTo:.footnote)}
    static var caption:Font {font(size:12,relativeTo:.caption)}
    static var caption2:Font {font(size:11,relativeTo:.caption2)}

    static func uiFont(size:CGFloat,weight:Font.Weight = .regular,relativeTo:UIFont.TextStyle = .body)->UIFont {
        let base=UIFont(name:face(for:weight),size:size) ?? UIFont.systemFont(ofSize:size)
        return UIFontMetrics(forTextStyle:relativeTo).scaledFont(for:base)
    }

    static let bundledFontNames=["Tajawal-Light","Tajawal-Regular","Tajawal-Medium","Tajawal-Bold","Tajawal-ExtraBold"]

    private static func face(for weight:Font.Weight)->String {
        switch weight {
        case .ultraLight,.thin,.light:return "Tajawal-Light"
        case .medium:return "Tajawal-Medium"
        case .semibold,.bold:return "Tajawal-Bold"
        case .heavy,.black:return "Tajawal-ExtraBold"
        default:return "Tajawal-Regular"
        }
    }
}
