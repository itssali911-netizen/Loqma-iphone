import SwiftUI

/// Editorial illustrations are bundled, decorative and never meal/result data.
enum EditorialArtwork:String,CaseIterable {
    case breakfast="LuqmaEditorialBreakfast"
    case lunch="LuqmaEditorialLunch"
    case dinner="LuqmaEditorialDinner"
    case snack="LuqmaEditorialSnack"
    case kitchen="LuqmaEditorialKitchen"
    case fitness="LuqmaEditorialFitness"
}

/// The parent supplies the bounds. Large source dimensions never affect layout.
struct EditorialFill:View {
    let artwork:EditorialArtwork
    var body:some View {
        GeometryReader{geometry in
            Image(artwork.rawValue).resizable().scaledToFill()
                .frame(width:geometry.size.width,height:geometry.size.height)
                .clipped()
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct EditorialPanel:View {
    let artwork:EditorialArtwork
    let height:CGFloat
    var cornerRadius:CGFloat=20
    var body:some View {
        Group{
            if artwork == .kitchen{
                Image(artwork.rawValue).resizable().scaledToFit()
                    .frame(maxWidth:.infinity,maxHeight:.infinity)
            }else{EditorialFill(artwork:artwork)}
        }.frame(height:height)
            .clipShape(RoundedRectangle(cornerRadius:cornerRadius,style:.continuous))
            .accessibilityHidden(true).allowsHitTesting(false)
    }
}
