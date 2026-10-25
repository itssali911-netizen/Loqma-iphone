import SwiftUI
import UIKit
import CoreText

/// Compatibility name for the existing Home. The user's subsequent Sandow
/// v1.2 board supersedes the earlier React-kit palette; layout remains intact
/// where the flattened board supplies no replacement component geometry.
enum NutritionExactTheme {
    private static func color(_ value:VisualRGB)->Color {Color(.sRGB,red:value.red,green:value.green,blue:value.blue,opacity:1)}
    static let background=color(SandowPalette.gray100)
    static let header=color(SandowPalette.gray80)
    static let search=background
    static let card=color(SandowPalette.gray90)
    static let secondaryCard=card
    static let activeCard=header
    static let badge=color(SandowPalette.gray70)
    static let modal=card
    static let orange=color(SandowPalette.orange50)
    static let orangeLink=color(SandowPalette.orange30)
    static let sliderTrack=header
    static let sliderThumb=orange
    static let blue=color(SandowPalette.blue60)
    static let notification=color(SandowPalette.red50)
    static let star=color(SandowPalette.yellow50)
    static let clock=color(SandowPalette.blue50)
    static let primary=Color.white
    static let secondary=color(SandowPalette.gray20)
    static let metadata=secondary
    static let muted=color(SandowPalette.gray30)
    static let subtle=color(SandowPalette.gray40)
    static let divider=badge
    static let notificationBorder=color(SandowPalette.gray60)
    static let horizontal:CGFloat=CGFloat(SandowLayoutTokens.margin)
    static let sectionGap:CGFloat=CGFloat(SandowLayoutTokens.gutter)
    // No numeric gradient specification is available on the supplied board.
    static let cardGradient=orange
}

struct NutritionExactIcon:View {
    var name:String
    var size:CGFloat=16
    var color:Color?=nil
    private var asset:String {
        switch name {
        case "Bell":return "SandowNotification"
        case "Clock","BrowseClock":return "SandowClock"
        case "Check","CheckBold":return "SandowCheck"
        default:return "NutritionExact"+name
        }
    }
    private var tint:Color? {
        if let color{return color}
        switch name {
        case "HeaderFlame":return NutritionExactTheme.orange
        case "BrowseFlame":return NutritionExactTheme.notification
        case "BrowseStar":return NutritionExactTheme.star
        case "BrowseClock":return NutritionExactTheme.clock
        // Original vectors are light-mode ink; invert their semantic tint on
        // the dark surface without rewriting SVG paths/root dimensions.
        case "Bell","Clock","Check","CheckBold":return NutritionExactTheme.primary
        default:return nil
        }
    }
    var body:some View {
        Group{
            if let tint{Image(asset).renderingMode(.template).resizable().foregroundStyle(tint)}
            else{Image(asset).renderingMode(.original).resizable()}
        }.scaledToFit().frame(width:size,height:size).accessibilityHidden(true)
    }
}

/// Use the actual Sandow family in every Latin run, including numeric islands;
/// reuse the existing CoreText Tajawal cascade for Arabic. Keep existing sizes
/// until matching Sandow component text metrics are available.
private struct NutritionExactFont:ViewModifier {
    let size:CGFloat
    let weight:Font.Weight
    let lineHeight:CGFloat
    @Environment(\.layoutDirection) private var direction
    @ScaledMetric(relativeTo:.body) private var scale:CGFloat=1
    func body(content:Content)->some View {
        let points=size*scale
        let face=weight == .heavy || weight == .black ? "Tajawal-ExtraBold":weight == .bold || weight == .semibold ? "Tajawal-Bold":weight == .medium ? "Tajawal-Medium":"Tajawal-Regular"
        let platform=LTypography.platformFont(size:points,weight:weight)
        let font=Font(platform)
        let nativeHeight=direction == .rightToLeft ? (UIFont(name:face,size:points)?.lineHeight ?? points*1.4):CTFontGetAscent(platform)+CTFontGetDescent(platform)+CTFontGetLeading(platform)
        content.font(font).lineSpacing(max(0,points*lineHeight-nativeHeight)).frame(minHeight:points*lineHeight)
    }
}

struct NutritionExactPressStyle:ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration:Configuration)->some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? 0.98:1)
            .animation(reduceMotion ? nil:.easeOut(duration:0.12),value:configuration.isPressed)
    }
}

extension View {
    func nutritionFont(_ size:CGFloat,weight:Font.Weight = .regular,lineHeight:CGFloat=1.5)->some View {modifier(NutritionExactFont(size:size,weight:weight,lineHeight:lineHeight))}
    func nutritionPanel(_ color:Color=NutritionExactTheme.card,radius:CGFloat=18)->some View {background(color,in:RoundedRectangle(cornerRadius:radius,style:.circular))}
}

/// Artwork is an explicitly documented substitute from the existing app, not
/// a claim that a saved recipe has this photograph or that AI analyzed it.
struct NutritionHomeArtwork:View {
    let name:String
    var caption:String?=nil
    var body:some View {
        GeometryReader{g in Image(name).resizable().scaledToFill().frame(width:g.size.width,height:g.size.height).clipped()}
            .overlay(alignment:.bottom){if let caption{Text(caption).nutritionFont(9,weight:.medium).foregroundStyle(.white).padding(.horizontal,4).padding(.vertical,2).background(.black.opacity(0.7),in:RoundedRectangle(cornerRadius:4)).padding(3)}}
            .accessibilityHidden(true).allowsHitTesting(false)
    }
}
