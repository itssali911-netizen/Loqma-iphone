import Foundation

/// Opaque sRGB values shared by the UI and its contrast checks. Brand fills stay
/// unchanged; foreground roles are chosen for the surface on which they appear.
struct VisualRGB:Equatable,Codable,Sendable {
    let red:Double
    let green:Double
    let blue:Double

    init(hex:UInt32){
        red=Double((hex >> 16) & 255)/255
        green=Double((hex >> 8) & 255)/255
        blue=Double(hex & 255)/255
    }
    private init(red:Double,green:Double,blue:Double){self.red=red;self.green=green;self.blue=blue}
    var hex:String {String(format:"#%02X%02X%02X",Int((red*255).rounded()),Int((green*255).rounded()),Int((blue*255).rounded()))}
    var relativeLuminance:Double {
        func linear(_ value:Double)->Double{value <= 0.04045 ? value/12.92:pow((value+0.055)/1.055,2.4)}
        return 0.2126*linear(red)+0.7152*linear(green)+0.0722*linear(blue)
    }
    func contrastRatio(against other:Self)->Double {
        let first=relativeLuminance,second=other.relativeLuminance
        return (max(first,second)+0.05)/(min(first,second)+0.05)
    }
    func composited(over background:Self,opacity:Double)->Self {
        let alpha=opacity.isFinite ? min(1,max(0,opacity)):1
        return Self(red:red*alpha+background.red*(1-alpha),green:green*alpha+background.green*(1-alpha),blue:blue*alpha+background.blue*(1-alpha))
    }
}

enum VisualDesignTokens {
    static let background=VisualRGB(hex:0x111214)
    static let card=VisualRGB(hex:0x24262B)
    static let surface=VisualRGB(hex:0x393C43)
    static let accent=VisualRGB(hex:0xF97316)
    static let secondaryAccent=VisualRGB(hex:0x2563EB)
    static let text=VisualRGB(hex:0xFFFFFF)
    static let textSecondary=VisualRGB(hex:0xB8BBC2)
    static let onAccent=background
    static let onSecondaryAccent=text
    static let accentText=VisualRGB(hex:0xFDBA74)
    static let secondaryAccentText=VisualRGB(hex:0x93C5FD)
    static let controlBorder=VisualRGB(hex:0x9EA0A5)
    static let divider=VisualRGB(hex:0x545861)
    static let success=VisualRGB(hex:0x86EFAC)
    static let warning=VisualRGB(hex:0xFDE68A)
    static let error=VisualRGB(hex:0xFCA5A5)
    static let errorBackground=VisualRGB(hex:0x450A0A)
    static let errorBorder=VisualRGB(hex:0xEF4444)

    struct ContrastResult:Codable,Equatable {
        let role:String
        let foreground:String
        let background:String
        let ratio:Double
        let minimum:Double
        let passed:Bool
        init(role:String,foreground:String,background:String,ratio:Double,minimum:Double){
            self.role=role;self.foreground=foreground;self.background=background;self.ratio=ratio;self.minimum=minimum
            passed=ratio >= minimum
        }
    }

    /// WCAG 2.2 sRGB luminance/contrast, without rounding before threshold checks.
    /// Normal text uses 4.5:1. Essential control outlines use 3:1. Photographic
    /// backgrounds require separate rendered review; they are not covered here.
    static var contrastAudit:[ContrastResult] {
        var results:[ContrastResult]=[]
        func append(_ role:String,_ foreground:VisualRGB,_ background:VisualRGB,_ minimum:Double=4.5){
            results.append(ContrastResult(role:role,foreground:foreground.hex,background:background.hex,ratio:foreground.contrastRatio(against:background),minimum:minimum))
        }
        let surfaces=[("background",background),("card",card),("surface",surface)]
        for (name,fill) in surfaces{
            for (role,foreground) in [("text",text),("secondary",textSecondary),("accentText",accentText),("secondaryAccentText",secondaryAccentText),("success",success),("warning",warning),("error",error)]{
                append(role+"/"+name,foreground,fill)
            }
            append("controlBorder/"+name,controlBorder,fill,3)
        }
        append("onAccent/accent",onAccent,accent)
        append("onSecondaryAccent/secondaryAccent",onSecondaryAccent,secondaryAccent)
        append("text/errorBackground",text,errorBackground)
        append("error/errorBackground",error,errorBackground)
        append("errorBorder/errorBackground",errorBorder,errorBackground,3)
        return results
    }
}
