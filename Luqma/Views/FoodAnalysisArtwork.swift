import SwiftUI

/// Scalable paths traced from the supplied LUQMA references. Their local colors
/// intentionally do not change the app's existing global theme or card fills.
struct FoodAnalysisIcon: View {
    enum Kind { case calories, protein, carbs, fat }
    let kind: Kind
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            path.stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                .frame(width: 28, height: 28)
                .scaleEffect(side / 28)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
    private var color: Color {
        switch kind {
        case .calories: return Theme.accent
        case .protein: return Color(hex: 0xD46561)
        case .carbs: return Color(hex: 0xD99A28)
        case .fat: return Color(hex: 0x759A59)
        }
    }
    private var path: AnalysisIconPath { AnalysisIconPath(kind: kind) }
}

private struct AnalysisIconPath: Shape {
    let kind: FoodAnalysisIcon.Kind
    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch kind {
        case .calories:
            p.move(to: CGPoint(x: 14.8, y: 2))
            p.addCurve(to: CGPoint(x: 14, y: 10.5), control1: CGPoint(x: 8, y: 7.3), control2: CGPoint(x: 14.6, y: 7.3))
            p.addCurve(to: CGPoint(x: 7.2, y: 13.7), control1: CGPoint(x: 14, y: 15.8), control2: CGPoint(x: 8.7, y: 17))
            p.addCurve(to: CGPoint(x: 4.6, y: 20), control1: CGPoint(x: 5.2, y: 15.1), control2: CGPoint(x: 4.2, y: 17.3))
            p.addCurve(to: CGPoint(x: 14, y: 26), control1: CGPoint(x: 5.4, y: 24.4), control2: CGPoint(x: 9.2, y: 26.9))
            p.addCurve(to: CGPoint(x: 23.6, y: 17), control1: CGPoint(x: 20.3, y: 25.4), control2: CGPoint(x: 24.7, y: 21.5))
            p.addCurve(to: CGPoint(x: 14.8, y: 2), control1: CGPoint(x: 22.3, y: 10.5), control2: CGPoint(x: 15.2, y: 9))
            p.closeSubpath()
        case .protein:
            p.move(to: CGPoint(x: 4, y: 8))
            p.addCurve(to: CGPoint(x: 22, y: 4), control1: CGPoint(x: 7, y: 1.5), control2: CGPoint(x: 17, y: 1))
            p.addCurve(to: CGPoint(x: 25, y: 19), control1: CGPoint(x: 26, y: 7), control2: CGPoint(x: 26, y: 13))
            p.addCurve(to: CGPoint(x: 13, y: 24), control1: CGPoint(x: 24, y: 26), control2: CGPoint(x: 17, y: 27))
            p.addCurve(to: CGPoint(x: 4, y: 18), control1: CGPoint(x: 9, y: 21), control2: CGPoint(x: 4, y: 22))
            p.addCurve(to: CGPoint(x: 4, y: 8), control1: CGPoint(x: 2, y: 16), control2: CGPoint(x: 2, y: 11))
            p.closeSubpath()
            p.move(to: CGPoint(x: 4, y: 13))
            p.addCurve(to: CGPoint(x: 15, y: 18), control1: CGPoint(x: 9, y: 12), control2: CGPoint(x: 11, y: 16))
            p.addCurve(to: CGPoint(x: 25, y: 15), control1: CGPoint(x: 20, y: 21), control2: CGPoint(x: 24, y: 18))
            p.move(to: CGPoint(x: 9, y: 8))
            p.addCurve(to: CGPoint(x: 21, y: 14), control1: CGPoint(x: 14, y: 6), control2: CGPoint(x: 22, y: 10))
            p.addCurve(to: CGPoint(x: 9, y: 8), control1: CGPoint(x: 19, y: 18), control2: CGPoint(x: 14, y: 10))
            p.move(to: CGPoint(x: 14, y: 8)); p.addLine(to: CGPoint(x: 16, y: 5.5))
        case .fat:
            p.move(to: CGPoint(x: 18, y: 2.5))
            p.addCurve(to: CGPoint(x: 25, y: 17), control1: CGPoint(x: 18, y: 8), control2: CGPoint(x: 26, y: 10))
            p.addCurve(to: CGPoint(x: 12, y: 24), control1: CGPoint(x: 26, y: 24), control2: CGPoint(x: 18, y: 28))
            p.move(to: CGPoint(x: 14, y: 8)); p.addQuadCurve(to: CGPoint(x: 18, y: 2.5), control: CGPoint(x: 17, y: 5))
            p.move(to: CGPoint(x: 8, y: 6))
            p.addCurve(to: CGPoint(x: 3, y: 16), control1: CGPoint(x: 7, y: 10), control2: CGPoint(x: 3, y: 12))
            p.addCurve(to: CGPoint(x: 13, y: 16), control1: CGPoint(x: 3, y: 23), control2: CGPoint(x: 14, y: 23))
            p.addCurve(to: CGPoint(x: 8, y: 6), control1: CGPoint(x: 13, y: 12), control2: CGPoint(x: 9, y: 10))
            p.closeSubpath()
        case .carbs:
            // Rice mound, bowl rim, bowl and foot, with separate rice grains.
            p.move(to: CGPoint(x: 3, y: 12))
            p.addQuadCurve(to: CGPoint(x: 7, y: 7), control: CGPoint(x: 2.5, y: 7))
            p.addQuadCurve(to: CGPoint(x: 13, y: 4), control: CGPoint(x: 9, y: 1))
            p.addQuadCurve(to: CGPoint(x: 20, y: 5), control: CGPoint(x: 18, y: -1))
            p.addQuadCurve(to: CGPoint(x: 24, y: 9), control: CGPoint(x: 25, y: 4))
            p.addQuadCurve(to: CGPoint(x: 26, y: 12), control: CGPoint(x: 26, y: 9))
            p.move(to: CGPoint(x: 2, y: 12))
            p.addQuadCurve(to: CGPoint(x: 26, y: 12), control: CGPoint(x: 14, y: 15))
            p.addCurve(to: CGPoint(x: 2, y: 12), control1: CGPoint(x: 24, y: 27), control2: CGPoint(x: 4, y: 27))
            p.closeSubpath()
            p.move(to: CGPoint(x: 10, y: 24)); p.addLine(to: CGPoint(x: 9.5, y: 26)); p.addLine(to: CGPoint(x: 18.5, y: 26)); p.addLine(to: CGPoint(x: 18, y: 24))
            for (a, b) in [(CGPoint(x: 7.5, y: 10), CGPoint(x: 8.3, y: 9.6)), (CGPoint(x: 11, y: 7.8), CGPoint(x: 11.8, y: 8.2)), (CGPoint(x: 15, y: 6.8), CGPoint(x: 15.8, y: 6.5)), (CGPoint(x: 16.3, y: 10), CGPoint(x: 16.7, y: 10.4)), (CGPoint(x: 20, y: 9.5), CGPoint(x: 20.8, y: 10))] { p.move(to: a); p.addLine(to: b) }
        }
        return p.applying(CGAffineTransform(scaleX: rect.width / 28, y: rect.height / 28))
    }
}

struct FoodScanOverlay: View {
    let startedAt: Date
    let finishingAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let copper = Color(hex: 0xD78957)
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion && finishingAt == nil)) { context in
            GeometryReader { geometry in
                let cycle = 2.1
                let base = max(0, (finishingAt ?? context.date).timeIntervalSince(startedAt)).truncatingRemainder(dividingBy: cycle) / cycle
                let finish = finishingAt.map { min(1, max(0, context.date.timeIntervalSince($0) / 0.24)) } ?? 0
                let progress = reduceMotion ? 0.5 : base + (1 - base) * finish
                let edgeFade = reduceMotion || finishingAt != nil ? 1 : min(1, min(base / 0.06, (1 - base) / 0.06))
                ZStack(alignment: .top) {
                    LinearGradient(colors: [.clear, copper.opacity(0.18)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 52).offset(y: geometry.size.height * progress - 52)
                    Rectangle().fill(copper).frame(height: 1.5)
                        .shadow(color: copper.opacity(0.5), radius: 4)
                        .offset(y: geometry.size.height * progress)
                }.opacity(edgeFade * (1 - finish))
            }.clipped()
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
