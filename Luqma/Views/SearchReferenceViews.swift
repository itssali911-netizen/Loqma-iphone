import SwiftUI
import CoreText

/// Values read from renderSearchScreen() in the user's luqma_search_screens.tsx.
/// Scoped to search; unrelated approved screens keep their existing theme.
enum SearchReferenceStyle {
    static let header=Color(hex:0xF6720A),loadingHeader=Color(hex:0xE67824)
    static let background=Color(hex:0x0D0E11),field=Color(hex:0x101114)
    static let card=Color(hex:0x1D2026),iconSurface=Color(hex:0x32363E)
    static let icon=Color(hex:0xD4D7DD),secondary=Color(hex:0x9EA3AE)
    static let input=Color(hex:0xE4E6EB),placeholder=Color(hex:0x9EA2AE)
    static let description=Color(hex:0x969AA3),sort=Color(hex:0x14161B)
    static let border=Color(hex:0x3E424B),sortText=Color(hex:0xC8CBD2)
    static let green=Color(hex:0x4E7D2B),blue=Color(hex:0x1D4ED8),slate=Color(hex:0x4B5262)
    static let spinner=Color(hex:0x35383F),activeDot=Color(hex:0xF07B24)
    static let margin:CGFloat=16,headerMargin:CGFloat=20,rowGap:CGFloat=10
}

private struct SearchReferenceFont:ViewModifier {
    let size:CGFloat,weight:Font.Weight,lineHeight:CGFloat
    @ScaledMetric(relativeTo:.body) private var scale:CGFloat=1
    func body(content:Content)->some View {
        let points=size*scale,font=LTypography.platformFont(size:points,weight:weight)
        let actual=CTFontGetAscent(font)+CTFontGetDescent(font)+CTFontGetLeading(font)
        content.font(Font(font)).lineSpacing(max(0,points*lineHeight-actual)).frame(minHeight:points*lineHeight)
    }
}
extension View {
    func searchReferenceFont(_ size:CGFloat,weight:Font.Weight = .regular,lineHeight:CGFloat=1.5)->some View {
        modifier(SearchReferenceFont(size:size,weight:weight,lineHeight:lineHeight))
    }
}

struct SearchReferenceIcon:View {
    let name:String
    var size:CGFloat=22
    var color:Color=SearchReferenceStyle.icon
    var body:some View {
        Image("SearchReference"+name).renderingMode(.template).resizable().scaledToFit()
            .frame(width:size,height:size).foregroundStyle(color).accessibilityHidden(true)
    }
}

struct SearchReferencePressStyle:ButtonStyle {
    var scale:CGFloat=0.99
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration:Configuration)->some View {
        configuration.label.scaleEffect(configuration.isPressed && !reduceMotion ? scale:1)
            .animation(reduceMotion ? nil:.timingCurve(0.4,0,0.2,1,duration:0.15),value:configuration.isPressed)
    }
}

struct SearchReferenceFoodRow:View {
    let food:Food
    let language:AppLanguage
    var score:Int?
    var bestMatch=false
    var action:()->Void
    @Environment(\.layoutDirection) private var direction
    @Environment(\.dynamicTypeSize) private var typeSize
    private var badge:String {
        if bestMatch{return language.text("أفضل تطابق","Best match")}
        if FoodSearch.isPersonalFood(food){return language.text("أطعمتي","My food")}
        return FoodSearch.isOpenFoodFacts(food) ? language.text("منتج","Product"):language.text("طعام","Food")
    }
    private var badgeColor:Color {bestMatch || FoodSearch.isPersonalFood(food) ? SearchReferenceStyle.green:FoodSearch.isOpenFoodFacts(food) ? SearchReferenceStyle.blue:SearchReferenceStyle.slate}
    private var detail:String {
        if let score{return String(score)+language.text("% تشابه اسم","% Name match")}
        if let value=food.values(for:food.unit){return DisplayFormat.decimal(value.kcal,digits:0)+language.text(" سعرة"," kcal")}
        return language.text("راجع التغذية","Review nutrition")
    }
    var body:some View {
        Button(action:action){
            HStack(spacing:12){
                HStack(spacing:14){
                    SearchReferenceIcon(name:bestMatch ? "Sparkle":"Document")
                        .frame(width:52,height:52)
                        .background(SearchReferenceStyle.iconSurface,in:RoundedRectangle(cornerRadius:16,style:.circular))
                    VStack(alignment:.leading,spacing:6){
                        Text(food.label(language)).searchReferenceFont(14.5,weight:.heavy).tracking(-0.3625)
                            .foregroundStyle(.white).multilineTextAlignment(.leading)
                            .lineLimit(typeSize.isAccessibilitySize ? nil:1)
                        ViewThatFits(in:.horizontal){
                            HStack(spacing:8){badgeView;detailView}
                            VStack(alignment:.leading,spacing:4){badgeView;detailView}
                        }
                    }.frame(maxWidth:.infinity,alignment:.leading)
                }
                SearchReferenceIcon(name:direction == .rightToLeft ? "ChevronLeft":"ChevronRight",size:16,color:SearchReferenceStyle.secondary).padding(.trailing,4)
            }.padding(12).frame(maxWidth:.infinity,minHeight:76,alignment:.leading)
                .background(SearchReferenceStyle.card,in:RoundedRectangle(cornerRadius:22,style:.circular))
                .contentShape(RoundedRectangle(cornerRadius:22,style:.circular))
        }.buttonStyle(SearchReferencePressStyle())
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(food.label(language)+", "+badge+", "+detail+", "+(food.source ?? ""))
            .accessibilityHint(language.text("اختيار الطعام والكمية. تشابه الاسم ليس تأكيدًا لهوية المنتج.","Choose food and quantity. Name similarity does not verify product identity."))
            .accessibilityIdentifier("food.result."+food.id)
    }
    private var badgeView:some View {
        Text(badge).searchReferenceFont(11,weight:.semibold,lineHeight:1.25).foregroundStyle(.white)
            .padding(.horizontal,10).padding(.vertical,3).background(badgeColor,in:RoundedRectangle(cornerRadius:6,style:.circular))
            .fixedSize(horizontal:true,vertical:false)
    }
    private var detailView:some View {
        Text(detail).searchReferenceFont(12,weight:.medium).foregroundStyle(SearchReferenceStyle.secondary)
            .environment(\.layoutDirection,.leftToRight).fixedSize(horizontal:true,vertical:false)
    }
}

struct SearchReferenceEmpty:View {
    let language:AppLanguage
    var body:some View {
        VStack(spacing:0){
            Image("SearchReferenceMagnifier").resizable().scaledToFit().frame(width:220,height:160).padding(.bottom,20)
                .accessibilityHidden(true).environment(\.layoutDirection,.leftToRight)
            HStack(spacing:8){
                Text(language.text("عذراً، لم يتم العثور على نتائج","Woops, Not Found"))
                    .searchReferenceFont(21,weight:.heavy).tracking(-0.525).multilineTextAlignment(.center)
                Text("😢").searchReferenceFont(21,lineHeight:1)
            }.foregroundStyle(.white).padding(.bottom,10)
            Text(language.text("للأسف، الكلمة المفتاحية التي أدخلتها غير موجودة. يرجى تجربة كلمة أخرى أو التحقق مرة ثانية.","Unfortunately, the key you entered cannot be found. Please try another keyword or check again."))
                .searchReferenceFont(13.5,lineHeight:1.55).foregroundStyle(SearchReferenceStyle.description)
                .multilineTextAlignment(.center).frame(maxWidth:285)
        }.padding(.horizontal,12).padding(.top,0).padding(.bottom,24)
            .frame(maxWidth:.infinity).accessibilityIdentifier("search.empty")
    }
}

struct SearchReferenceLoading:View {
    let language:AppLanguage
    var staticRing=false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body:some View {
        VStack(spacing:24){
            TimelineView(.animation(minimumInterval:0.18,paused:staticRing || reduceMotion || scenePhase != .active)){timeline in
                let active=staticRing || reduceMotion ? 0:Int(timeline.date.timeIntervalSinceReferenceDate/0.18)%8
                ZStack{
                    ForEach(0..<8,id:\.self){index in
                        let angle=Double(index)*Double.pi/4-Double.pi/2
                        Circle().fill(index==active ? SearchReferenceStyle.activeDot:SearchReferenceStyle.spinner)
                            .frame(width:19,height:19).offset(x:CGFloat(34*cos(angle)),y:CGFloat(34*sin(angle)))
                    }
                }.frame(width:96,height:96)
                    .animation(staticRing || reduceMotion ? nil:.timingCurve(0.4,0,0.2,1,duration:0.15),value:active)
            }.accessibilityHidden(true)
            Text(language.text("جاري التحميل...","Loading...")).searchReferenceFont(17,weight:.heavy).tracking(-0.425).foregroundStyle(.white)
        }.padding(.bottom,16).frame(maxWidth:.infinity).accessibilityIdentifier("search.loading")
            .accessibilityElement(children:.combine)
    }
}
