import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#endif

enum LTypography {
    struct Descriptor {
        var size:CGFloat
        var weight:Font.Weight = .regular
        var relativeTo:Font.TextStyle = .body
        var requestedWeight:Font.Weight

        init(size:CGFloat,weight:Font.Weight = .regular,relativeTo:Font.TextStyle = .body){
            self.size=max(12,size.isFinite ? size:16)
            requestedWeight=weight
            self.weight=LTypography.readableWeight(weight)
            self.relativeTo=relativeTo
        }

        static var title:Self {Self(size:22,weight:.heavy,relativeTo:.title)}
        static var title2:Self {Self(size:22,weight:.heavy,relativeTo:.title2)}
        static var title3:Self {Self(size:18,weight:.bold,relativeTo:.title3)}
        static var headline:Self {Self(size:16,weight:.bold,relativeTo:.headline)}
        static var subheadline:Self {Self(size:15,relativeTo:.subheadline)}
        static var body:Self {Self(size:16,relativeTo:.body)}
        static var callout:Self {Self(size:16,relativeTo:.callout)}
        static var footnote:Self {Self(size:13,relativeTo:.footnote)}
        static var caption:Self {Self(size:12,weight:.medium,relativeTo:.caption)}
        static var caption2:Self {Self(size:12,weight:.medium,relativeTo:.caption2)}
        static var display:Self {Self(size:36,weight:.heavy,relativeTo:.largeTitle)}
        static var screenTitle:Self {Self(size:24,weight:.bold,relativeTo:.title2)}
        static var sectionTitle:Self {Self(size:18,weight:.bold,relativeTo:.title3)}
        static var metric:Self {Self(size:32,weight:.bold,relativeTo:.largeTitle)}
        static var label:Self {Self(size:14,weight:.medium,relativeTo:.subheadline)}
        static var helper:Self {Self(size:13,relativeTo:.footnote)}
        static var button:Self {Self(size:16,weight:.semibold,relativeTo:.headline)}
    }

    static func descriptor(size:CGFloat,weight:Font.Weight = .regular,relativeTo:Font.TextStyle = .body)->Descriptor {
        Descriptor(size:size,weight:weight,relativeTo:relativeTo)
    }

    // Compatibility for existing call sites while the views migrate to
    // .luqmaFont. These are platform-font snapshots; the modifier below owns
    // SwiftUI's live Dynamic Type scaling.
    static func font(size:CGFloat,weight:Font.Weight = .regular,relativeTo:Font.TextStyle = .body)->Font {
        Font(platformFont(size:size,weight:weight))
    }
    static var title:Font {font(size:Descriptor.title.size,weight:.heavy,relativeTo:.title)}
    static var title2:Font {font(size:Descriptor.title2.size,weight:.heavy,relativeTo:.title2)}
    static var title3:Font {font(size:Descriptor.title3.size,weight:.bold,relativeTo:.title3)}
    static var headline:Font {font(size:Descriptor.headline.size,weight:.bold,relativeTo:.headline)}
    static var subheadline:Font {font(size:Descriptor.subheadline.size,relativeTo:.subheadline)}
    static var body:Font {font(size:Descriptor.body.size,relativeTo:.body)}
    static var callout:Font {font(size:Descriptor.callout.size,relativeTo:.callout)}
    static var footnote:Font {font(size:Descriptor.footnote.size,relativeTo:.footnote)}
    static var caption:Font {font(size:Descriptor.caption.size,weight:Descriptor.caption.weight,relativeTo:.caption)}
    static var caption2:Font {font(size:Descriptor.caption2.size,weight:Descriptor.caption2.weight,relativeTo:.caption2)}

    /// Keep original Light faces available to the low-level renderer and font
    /// verification, while app text never relies on fragile thin strokes.
    static func readableWeight(_ weight:Font.Weight)->Font.Weight {
        switch weight{case .ultraLight,.thin,.light:return .regular;default:return weight}
    }

    static let bundledFontNames=[
        "WorkSans-Light","WorkSans-Regular","WorkSans-Medium","WorkSans-SemiBold","WorkSans-Bold","WorkSans-ExtraBold",
        "Tajawal-Light","Tajawal-Regular","Tajawal-Medium","Tajawal-Bold","Tajawal-ExtraBold"
    ]

    private final class FontCacheEntry:NSObject {
        let font:CTFont
        init(_ font:CTFont) {self.font=font}
    }
    // NSCache synchronizes access and bounds retained descriptors. Preserve the
    // exact point size: rounding here would distort live Dynamic Type scaling.
    private static let fontCache:NSCache<NSString,FontCacheEntry> = {
        let cache=NSCache<NSString,FontCacheEntry>()
        cache.countLimit=256
        return cache
    }()

    static func platformFont(size:CGFloat,weight:Font.Weight = .regular)->CTFont {
        let pair=faces(for:weight)
        let key="\(pair.latin)|\(pair.arabic)|\(Double(size).bitPattern)" as NSString
        if let cached=fontCache.object(forKey:key) {return cached.font}
        let primary=CTFontCreateWithName(pair.latin as CFString,size,nil)
        let arabic=CTFontCreateWithName(pair.arabic as CFString,size,nil)
        let cascade=[CTFontCopyFontDescriptor(arabic)]+defaultCascade(for:primary)
        let attributes=[kCTFontCascadeListAttribute as String:cascade] as CFDictionary
        let descriptor=CTFontDescriptorCreateCopyWithAttributes(CTFontCopyFontDescriptor(primary),attributes)
        let font=CTFontCreateWithFontDescriptor(descriptor,size,nil)
        fontCache.setObject(FontCacheEntry(font),forKey:key)
        return font
    }

    private static func defaultCascade(for primary:CTFont)->[CTFontDescriptor] {
        (CTFontCopyDefaultCascadeListForLanguages(primary,["ar","en"] as CFArray) as? [CTFontDescriptor]) ?? []
    }

    #if canImport(UIKit)
    static func uiFont(size:CGFloat,weight:Font.Weight = .regular,relativeTo:UIFont.TextStyle = .body,compatibleWith traits:UITraitCollection?=nil)->UIFont {
        let pair=faces(for:readableWeight(weight))
        let primary=UIFont(name:pair.latin,size:size) ?? UIFont.systemFont(ofSize:size)
        let ctPrimary=CTFontCreateWithName(pair.latin as CFString,size,nil)
        let systemDescriptors=defaultCascade(for:ctPrimary).compactMap{descriptor->UIFontDescriptor? in
            guard let name=CTFontDescriptorCopyAttribute(descriptor,kCTFontNameAttribute) as? String else{return nil}
            return UIFontDescriptor(name:name,size:size)
        }
        let arabic=UIFontDescriptor(name:pair.arabic,size:size)
        let descriptor=primary.fontDescriptor.addingAttributes([.cascadeList:[arabic]+systemDescriptors])
        let unscaled=UIFont(descriptor:descriptor,size:size)
        return UIFontMetrics(forTextStyle:relativeTo).scaledFont(for:unscaled,compatibleWith:traits)
    }

    #if DEBUG
    struct RuntimeFontAudit:Codable {
        let source:String
        let contentSizeCategory:String
        let minimumBaseTextPoints:Double
        let bodyBaseTextPoints:Double
        let trackingPoints:Double
        let lineSpacingMultiplier:Double
        let entries:[RuntimeFontAuditEntry]
        let emojiFonts:[String]
        let passed:Bool
    }
    struct RuntimeFontAuditEntry:Codable {
        let role:String
        let requestedWeight:String
        let effectiveWeight:String
        let requestedLatinPostScript:String
        let requestedArabicPostScript:String
        let resolvedLatinPostScript:String
        let resolvedArabicPostScript:String
        let uiFontPostScript:String
        let uiFontFamily:String
        let basePoints:Double
        let scaledPoints:Double
        let lineHeight:Double
        let latinRuns:[String]
        let arabicRuns:[String]
        let mixedRuns:[String]
        let missingGlyphs:Int
        let registered:Bool
        let passed:Bool
    }
    /// Native capture calls this after the app/font resources have loaded. This
    /// records UIKit's actual registered faces and CoreText's shaped glyph runs;
    /// listing a bundled filename alone is not evidence that the font rendered.
    @MainActor static func runtimeFontAudit(category:UIContentSizeCategory?=nil)->RuntimeFontAudit {
        let category=category ?? UIApplication.shared.preferredContentSizeCategory
        let traits=UITraitCollection(preferredContentSizeCategory:category)
        let roles:[(String,Descriptor)]=[
            ("display",.display),("screenTitle",.screenTitle),("sectionTitle",.sectionTitle),
            ("headline",.headline),("body",.body),("subheadline",.subheadline),
            ("helper",.helper),("caption",.caption),("caption2",.caption2),
            ("button",.button),("metric",.metric),
            ("legacyLightPromoted",Descriptor(size:12,weight:.light,relativeTo:.caption))
        ]
        let entries=roles.map{role,descriptor->RuntimeFontAuditEntry in
            let requested=faces(for:descriptor.requestedWeight),resolved=faces(for:descriptor.weight)
            let font=uiFont(size:descriptor.size,weight:descriptor.weight,relativeTo:uiTextStyle(descriptor.relativeTo),compatibleWith:traits)
            let rendered=platformFont(size:font.pointSize,weight:descriptor.weight)
            let latin=shapedFonts("123 Protein",font:rendered)
            let arabic=shapedFonts("البروتين",font:rendered)
            let mixed=shapedFonts("123 Protein البروتين",font:rendered)
            let latinFont=UIFont(name:resolved.latin,size:descriptor.size)
            let arabicFont=UIFont(name:resolved.arabic,size:descriptor.size)
            let registered=latinFont?.fontName == resolved.latin && arabicFont?.fontName == resolved.arabic
            let missing=latin.missing+arabic.missing+mixed.missing
            let passed=registered && font.fontName == resolved.latin && latin.names == [resolved.latin] && arabic.names == [resolved.arabic] && Set(mixed.names) == Set([resolved.latin,resolved.arabic]) && missing == 0
            return RuntimeFontAuditEntry(role:role,requestedWeight:weightName(descriptor.requestedWeight),effectiveWeight:weightName(descriptor.weight),
                requestedLatinPostScript:requested.latin,requestedArabicPostScript:requested.arabic,
                resolvedLatinPostScript:latinFont?.fontName ?? "unavailable",resolvedArabicPostScript:arabicFont?.fontName ?? "unavailable",
                uiFontPostScript:font.fontName,uiFontFamily:font.familyName,
                basePoints:Double(descriptor.size),scaledPoints:Double(font.pointSize),lineHeight:Double(font.lineHeight),
                latinRuns:latin.names,arabicRuns:arabic.names,mixedRuns:mixed.names,missingGlyphs:missing,registered:registered,passed:passed)
        }
        let emoji=shapedFonts("🥙",font:platformFont(size:18))
        return RuntimeFontAudit(source:"Actual UIKit fonts and CoreText shaped runs from LuqmaTypography",contentSizeCategory:category.rawValue,
            minimumBaseTextPoints:12,bodyBaseTextPoints:Double(Descriptor.body.size),trackingPoints:0,lineSpacingMultiplier:0.12,
            entries:entries,emojiFonts:emoji.missing == 0 ? emoji.names:[],
            passed:entries.allSatisfy(\.passed) && emoji.missing == 0 && emoji.names.contains(where:{$0.lowercased().contains("emoji")}))
    }
    private static func shapedFonts(_ text:String,font:CTFont)->(names:[String],missing:Int){
        let attributes=[NSAttributedString.Key(kCTFontAttributeName as String):font]
        let line=CTLineCreateWithAttributedString(NSAttributedString(string:text,attributes:attributes) as CFAttributedString)
        let runs=CTLineGetGlyphRuns(line) as! [CTRun]
        var names=Set<String>(),missing=0
        for run in runs{
            let attributes=CTRunGetAttributes(run) as NSDictionary
            guard let fontValue=attributes[kCTFontAttributeName as String] else{missing+=1;continue}
            names.insert(CTFontCopyPostScriptName(fontValue as! CTFont) as String)
            var glyphs=[CGGlyph](repeating:0,count:CTRunGetGlyphCount(run))
            if !glyphs.isEmpty{
                glyphs.withUnsafeMutableBufferPointer{buffer in CTRunGetGlyphs(run,CFRange(location:0,length:0),buffer.baseAddress!)}
                missing+=glyphs.filter{$0 == 0}.count
            }
        }
        return (names.sorted(),missing)
    }
    private static func uiTextStyle(_ style:Font.TextStyle)->UIFont.TextStyle {
        switch style{
        case .largeTitle:return .largeTitle
        case .title:return .title1
        case .title2:return .title2
        case .title3:return .title3
        case .headline:return .headline
        case .subheadline:return .subheadline
        case .callout:return .callout
        case .footnote:return .footnote
        case .caption:return .caption1
        case .caption2:return .caption2
        default:return .body
        }
    }
    private static func weightName(_ weight:Font.Weight)->String {
        switch weight{
        case .ultraLight:return "ultraLight"
        case .thin:return "thin"
        case .light:return "light"
        case .medium:return "medium"
        case .semibold:return "semibold"
        case .bold:return "bold"
        case .heavy:return "heavy"
        case .black:return "black"
        default:return "regular"
        }
    }
    #endif
    #endif

    private static func faces(for weight:Font.Weight)->(latin:String,arabic:String) {
        switch weight {
        case .ultraLight,.thin,.light:return ("WorkSans-Light","Tajawal-Light")
        case .medium:return ("WorkSans-Medium","Tajawal-Medium")
        case .semibold:return ("WorkSans-SemiBold","Tajawal-Bold")
        case .bold:return ("WorkSans-Bold","Tajawal-Bold")
        case .heavy,.black:return ("WorkSans-ExtraBold","Tajawal-ExtraBold")
        default:return ("WorkSans-Regular","Tajawal-Regular")
        }
    }
}

private struct LuqmaFontModifier:ViewModifier {
    @ScaledMetric private var scaledSize:CGFloat
    private let weight:Font.Weight

    init(_ descriptor:LTypography.Descriptor) {
        _scaledSize=ScaledMetric(wrappedValue:descriptor.size,relativeTo:descriptor.relativeTo)
        weight=descriptor.weight
    }

    func body(content:Content)->some View {
        #if LUQMA_FONT_PROBE
        // The native probe reads the actual modifier's resolved metric after
        // SwiftUI installs its environment. This hook is absent from the app.
        return content.font(Font(LTypography.platformFont(size:scaledSize,weight:weight)))
            .tracking(0).lineSpacing(scaledSize*0.12)
            .preference(key:LuqmaFontPointSizeKey.self,value:scaledSize)
        #else
        return content.font(Font(LTypography.platformFont(size:scaledSize,weight:weight)))
            .tracking(0).lineSpacing(scaledSize*0.12)
        #endif
    }
}

#if LUQMA_FONT_PROBE
struct LuqmaFontPointSizeKey:PreferenceKey {
    static var defaultValue:CGFloat {0}
    static func reduce(value:inout CGFloat,nextValue:()->CGFloat) {value=nextValue()}
}
#endif

extension View {
    func luqmaFont(_ descriptor:LTypography.Descriptor)->some View {
        modifier(LuqmaFontModifier(descriptor))
    }

    func luqmaFont(size:CGFloat,weight:Font.Weight = .regular,relativeTo:Font.TextStyle = .body)->some View {
        luqmaFont(LTypography.descriptor(size:size,weight:weight,relativeTo:relativeTo))
    }
}
