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

        static var title:Self {Self(size:22,weight:.heavy,relativeTo:.title)}
        static var title2:Self {Self(size:22,weight:.heavy,relativeTo:.title2)}
        static var title3:Self {Self(size:18,weight:.bold,relativeTo:.title3)}
        static var headline:Self {Self(size:16,weight:.bold,relativeTo:.headline)}
        static var subheadline:Self {Self(size:15,relativeTo:.subheadline)}
        static var body:Self {Self(size:16,relativeTo:.body)}
        static var callout:Self {Self(size:16,relativeTo:.callout)}
        static var footnote:Self {Self(size:13,relativeTo:.footnote)}
        static var caption:Self {Self(size:12,relativeTo:.caption)}
        static var caption2:Self {Self(size:11,relativeTo:.caption2)}
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
    static var caption:Font {font(size:Descriptor.caption.size,relativeTo:.caption)}
    static var caption2:Font {font(size:Descriptor.caption2.size,relativeTo:.caption2)}

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
    static func uiFont(size:CGFloat,weight:Font.Weight = .regular,relativeTo:UIFont.TextStyle = .body)->UIFont {
        let pair=faces(for:weight)
        let primary=UIFont(name:pair.latin,size:size) ?? UIFont.systemFont(ofSize:size)
        let ctPrimary=CTFontCreateWithName(pair.latin as CFString,size,nil)
        let systemDescriptors=defaultCascade(for:ctPrimary).compactMap{descriptor->UIFontDescriptor? in
            guard let name=CTFontDescriptorCopyAttribute(descriptor,kCTFontNameAttribute) as? String else{return nil}
            return UIFontDescriptor(name:name,size:size)
        }
        let arabic=UIFontDescriptor(name:pair.arabic,size:size)
        let descriptor=primary.fontDescriptor.addingAttributes([.cascadeList:[arabic]+systemDescriptors])
        let unscaled=UIFont(descriptor:descriptor,size:size)
        return UIFontMetrics(forTextStyle:relativeTo).scaledFont(for:unscaled)
    }
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
            .preference(key:LuqmaFontPointSizeKey.self,value:scaledSize)
        #else
        return content.font(Font(LTypography.platformFont(size:scaledSize,weight:weight)))
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
