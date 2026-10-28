import SwiftUI

/// Directly measured editable dark alert instance 2:9631. Original SVG is unchanged.
struct SandowStateAlert:View {
    let text:String
    var body:some View {
        HStack(alignment:.top,spacing:6){
            Image("SandowWarning").frame(width:20,height:20).accessibilityHidden(true)
            Text(DisplayFormat.westernDigits(text)).luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline)
                .fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
        }.foregroundStyle(Theme.text).padding(12)
            .background(Theme.errorBackground,in:RoundedRectangle(cornerRadius:14))
            .overlay{RoundedRectangle(cornerRadius:14).stroke(Theme.errorBorder,lineWidth:1)}
            .accessibilityElement(children:.combine)
            .luqmaMotionTransition()
            .luqmaFeedback(.error,trigger:text)
    }
}

/// The original loading glyph pulses only while its real operation is visible.
/// No invented progress, completion time, new artwork or layout is introduced.
struct SandowOperationState:View {
    let title:String
    var cancelLabel:String?=nil
    var onCancel:(()->Void)?=nil
    var body:some View {
        HStack(spacing:12){
            Image("SandowLoadingDots").frame(width:24,height:24).padding(6)
                .luqmaLoadingPulse()
                .background(Theme.accent,in:RoundedRectangle(cornerRadius:12)).accessibilityHidden(true)
            Text(title).luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline)
                .fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
            if let cancelLabel,let onCancel{
                Button(cancelLabel,action:onCancel).luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline)
                    .foregroundStyle(Theme.text).frame(minWidth:44,minHeight:44).buttonStyle(LuqmaPressStyle())
            }
        }.padding(12).foregroundStyle(Theme.text)
            .background(Theme.card,in:RoundedRectangle(cornerRadius:20)).accessibilityElement(children:.contain)
            .luqmaMotionTransition()
    }
}

/// Text/action hierarchy of the utility board. Its 3D images exist only inside
/// a flattened board; no stock symbol is passed off as an original illustration.
struct SandowEmptyState:View {
    let title:String
    let message:String
    var actionLabel:String?=nil
    var onAction:(()->Void)?=nil
    var body:some View {
        VStack(spacing:16){
            Text(title).luqmaFont(size:24,weight:.bold,relativeTo:.title2).accessibilityAddTraits(.isHeader)
            Text(message).luqmaFont(size:14,relativeTo:.subheadline).foregroundStyle(Theme.muted)
                .fixedSize(horizontal:false,vertical:true)
            if let actionLabel,let onAction{
                Button(actionLabel,action:onAction).buttonStyle(LuqmaPrimaryButtonStyle()).padding(.top,8)
            }
        }.multilineTextAlignment(.center).frame(maxWidth:.infinity).padding(.vertical,28)
            .luqmaMotionTransition()
    }
}

/// Acknowledgement appears only after the caller's actual operation succeeds.
struct SandowSavedConfirmation:View {
    let text:String
    var body:some View {
        HStack(spacing:10){
            Image("SandowCheck").frame(width:24,height:24).padding(6)
                .background(Theme.accent,in:RoundedRectangle(cornerRadius:12)).accessibilityHidden(true)
            Text(text).luqmaFont(size:14,weight:.semibold,relativeTo:.subheadline)
                .foregroundStyle(Theme.success).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
        }.padding(12).background(Theme.card,in:RoundedRectangle(cornerRadius:14))
            .accessibilityElement(children:.combine)
            .luqmaMotionTransition()
    }
}
