import Foundation

/// Exact labelled swatches from the supplied Sandow v1.2 board.
/// Pixel proof and limits: Docs/SandowComponentSystem/extracted-tokens.json.
enum SandowPalette {
    static let gray100=VisualRGB(hex:0x111214)
    static let gray90=VisualRGB(hex:0x24262B)
    static let gray80=VisualRGB(hex:0x393C43)
    static let gray70=VisualRGB(hex:0x50535B)
    static let gray60=VisualRGB(hex:0x676C75)
    static let gray50=VisualRGB(hex:0x81858D)
    static let gray40=VisualRGB(hex:0x9EA0A5)
    static let gray30=VisualRGB(hex:0xBABBBE)
    static let gray20=VisualRGB(hex:0xD7D8D9)
    static let gray10=VisualRGB(hex:0xF3F3F4)
    static let orange100=VisualRGB(hex:0x431407)
    static let orange90=VisualRGB(hex:0x7C2D12)
    static let orange80=VisualRGB(hex:0x9A3412)
    static let orange70=VisualRGB(hex:0xC2410C)
    static let orange60=VisualRGB(hex:0xEA580C)
    static let orange50=VisualRGB(hex:0xF97316)
    static let orange40=VisualRGB(hex:0xFB923C)
    static let orange30=VisualRGB(hex:0xFDBA74)
    static let orange20=VisualRGB(hex:0xFED7AA)
    static let orange10=VisualRGB(hex:0xFFEDD5)
    static let yellow100=VisualRGB(hex:0x422006)
    static let yellow90=VisualRGB(hex:0x713F12)
    static let yellow80=VisualRGB(hex:0x854D0E)
    static let yellow70=VisualRGB(hex:0xA16207)
    static let yellow60=VisualRGB(hex:0xCA8A04)
    static let yellow50=VisualRGB(hex:0xEAB308)
    static let yellow40=VisualRGB(hex:0xFACC15)
    static let yellow30=VisualRGB(hex:0xFDE047)
    static let yellow20=VisualRGB(hex:0xFEF08A)
    static let yellow10=VisualRGB(hex:0xFEF9C3)
    static let blue100=VisualRGB(hex:0x172554)
    static let blue90=VisualRGB(hex:0x1E3A8A)
    static let blue80=VisualRGB(hex:0x1E40AF)
    static let blue70=VisualRGB(hex:0x1D4ED8)
    static let blue60=VisualRGB(hex:0x2563EB)
    static let blue50=VisualRGB(hex:0x3B82F6)
    static let blue40=VisualRGB(hex:0x60A5FA)
    static let blue30=VisualRGB(hex:0x93C5FD)
    static let blue20=VisualRGB(hex:0xBFDBFE)
    static let blue10=VisualRGB(hex:0xDBEAFE)
    static let red100=VisualRGB(hex:0x450A0A)
    static let red90=VisualRGB(hex:0x7F1D1D)
    static let red80=VisualRGB(hex:0x991B1B)
    static let red70=VisualRGB(hex:0xB91C1C)
    static let red60=VisualRGB(hex:0xDC2626)
    static let red50=VisualRGB(hex:0xEF4444)
    static let red40=VisualRGB(hex:0xF87171)
    static let red30=VisualRGB(hex:0xFCA5A5)
    static let red20=VisualRGB(hex:0xFECACA)
    static let red10=VisualRGB(hex:0xFEE2E2)
    static let green100=VisualRGB(hex:0x1A2E05)
    static let green90=VisualRGB(hex:0x365314)
    static let green80=VisualRGB(hex:0x3F6212)
    static let green70=VisualRGB(hex:0x4D7C0F)
    static let green60=VisualRGB(hex:0x65A30D)
    static let green50=VisualRGB(hex:0x84CC16)
    static let green40=VisualRGB(hex:0xA3E635)
    static let green30=VisualRGB(hex:0xBEF264)
    static let green20=VisualRGB(hex:0xD9F99D)
    static let green10=VisualRGB(hex:0xECFCCB)
    static let purple100=VisualRGB(hex:0x3B0764)
    static let purple90=VisualRGB(hex:0x581C87)
    static let purple80=VisualRGB(hex:0x6B21A8)
    static let purple70=VisualRGB(hex:0x7E22CE)
    static let purple60=VisualRGB(hex:0x9333EA)
    static let purple50=VisualRGB(hex:0xA855F7)
    static let purple40=VisualRGB(hex:0xC084FC)
    static let purple30=VisualRGB(hex:0xD8B4FE)
    static let purple20=VisualRGB(hex:0xE9D5FF)
    static let purple10=VisualRGB(hex:0xF3E8FF)
    static let white=VisualRGB(hex:0xFFFFFF)
}

enum SandowLayoutTokens {
    static let referenceWidth:Double=375
    static let referenceHeight:Double=812
    static let gridColumns=3
    static let margin:Double=16
    static let gutter:Double=16
    static let spacing:[Double]=[2,4,6,8,16,32,64,128]
    /// Responsive extension of the visibly labelled three-column grid.
    static func columnWidth(in width:Double)->Double {
        guard width.isFinite else{return 0}
        return max(0,(width-2*margin-Double(gridColumns-1)*gutter)/Double(gridColumns))
    }
    enum PrimaryButton {
        // Actual cached 2:9760 variant, not an inference from bitmap size.
        static let height:Double=56
        static let radius:Double=16
        static let horizontalPadding:Double=28
        static let contentGap:Double=12
        static let fontSize:Double=16
        static let foreground=SandowPalette.white
        static let disabledForeground=SandowPalette.gray30
        static let disabledBackground=SandowPalette.gray10
        /// Explicit reference exception, not a claim of WCAG AA compliance.
        static var contrast:Double {foreground.contrastRatio(against:SandowPalette.orange50)}
    }
}
