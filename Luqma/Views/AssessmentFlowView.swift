import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: 1)
    }
}

/// The approved package's entry point uses the existing transactional flow.
/// It deliberately does not introduce its older, parallel onboarding model.
struct AssessmentFlowView: View {
    var body: some View { FitnessAssessmentView() }
}

struct CFACrescentChevron: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.minX - 2, y: rect.midY))
        return path
    }
}

struct CFARadioIndicator: View {
    let isSelected: Bool
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color.white, lineWidth: 2).frame(width: 22, height: 22)
            if isSelected {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(Color.white).frame(width: 9, height: 9)
            }
        }.accessibilityHidden(true)
    }
}

struct ApprovedAssessmentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.luqmaFont(size: 16, weight: .bold, relativeTo: .body)
            .foregroundStyle(Color.white).frame(maxWidth: .infinity, minHeight: 56)
            .background(Color(hex: 0xF97316), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .opacity(isEnabled ? 1 : 0.6)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
    }
}

/// Original quadratic arc and handle; the approved screenshot also includes
/// five perpendicular ticks, absent from the supplied helper implementation.
struct SandowFitnessArcSlider: View {
    @Binding var level: Int
    let label: String
    var hasSelection = true
    var onChanged: () -> Void = {}
    var onInteractionChanged:(Bool)->Void = {_ in}
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width, height = geo.size.height
            let start = CGPoint(x: 18, y: height - 24)
            let end = CGPoint(x: width - 6, y: 18)
            let control = CGPoint(x: width * 0.22, y: height * 0.18)
            let t = CGFloat(min(5, max(1, level)) - 1) / 4 * 0.72 + 0.14
            let thumb = point(t: t, start: start, control: control, end: end)
            ZStack(alignment: .bottomTrailing) {
                Path { path in
                    path.move(to: start)
                    path.addQuadCurve(to: end, control: control)
                }.stroke(Color(hex: 0x24262B), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                Path { path in
                    for index in 0..<5 {
                        let fraction = CGFloat(index) / 4
                        let location = point(t: fraction, start: start, control: control, end: end)
                        let dx = 2 * (1 - fraction) * (control.x - start.x) + 2 * fraction * (end.x - control.x)
                        let dy = 2 * (1 - fraction) * (control.y - start.y) + 2 * fraction * (end.y - control.y)
                        let length = max(1, hypot(dx, dy))
                        let normal = CGPoint(x: -dy / length * 16, y: dx / length * 16)
                        path.move(to: CGPoint(x: location.x - normal.x, y: location.y - normal.y))
                        path.addLine(to: CGPoint(x: location.x + normal.x, y: location.y + normal.y))
                    }
                }.stroke(Color(hex: 0x676C75), lineWidth: 1.5)
                Path { path in
                    path.move(to: start)
                    path.addQuadCurve(to: thumb, control: CGPoint(x: start.x + (control.x - start.x) * t, y: start.y + (control.y - start.y) * t))
                }.stroke(Color(hex: 0xF97316), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0xF97316))
                        .frame(width: 58, height: 58)
                        .overlay { RoundedRectangle(cornerRadius: 21, style: .continuous).stroke(Color(hex: 0x7C2D12).opacity(0.65), lineWidth: 4).padding(-2) }
                        .rotationEffect(.degrees(42))
                    Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 18, weight: .bold)).foregroundStyle(Color.white)
                }.position(thumb)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(level)").luqmaFont(size: 168, weight: .heavy, relativeTo: .largeTitle).foregroundStyle(Color.white).monospacedDigit()
                    Text(label).luqmaFont(size: 20, weight: .bold, relativeTo: .title3).foregroundStyle(Color(hex: 0xD7D8D9))
                        .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                }.padding(.trailing, 18).padding(.bottom, 18).allowsHitTesting(false)
            }.contentShape(Rectangle())
                .highPriorityGesture(DragGesture(minimumDistance: 2).onChanged { value in
                    onInteractionChanged(true)
                    let progress = min(1, max(0, 1 - value.location.y / max(1, height)))
                    select(min(5, max(1, Int((progress * 4).rounded()) + 1)))
                }.onEnded{_ in onInteractionChanged(false)})
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(direction == .rightToLeft ? "مستوى النشاط" : "Activity level")
                .accessibilityValue(hasSelection ? "\(level) · \(label)" : (direction == .rightToLeft ? "لم يُحدّد بعد" : "Not selected"))
                .accessibilityAdjustableAction { adjustment in select(level + (adjustment == .increment ? 1 : -1)) }
                .accessibilityIdentifier("assessment.activity.slider")
        }.environment(\.layoutDirection, .leftToRight).onDisappear{onInteractionChanged(false)}
    }
    private func select(_ proposed: Int) {
        let next = min(5, max(1, proposed))
        if next != level || !hasSelection { level = next; onChanged() }
    }
    private func point(t: CGFloat, start: CGPoint, control: CGPoint, end: CGPoint) -> CGPoint {
        let inverse = 1 - t
        return CGPoint(x: inverse * inverse * start.x + 2 * inverse * t * control.x + t * t * end.x,
                       y: inverse * inverse * start.y + 2 * inverse * t * control.y + t * t * end.y)
    }
}

struct CFAScanBracketsShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let corner: CGFloat = 52, radius: CGFloat = 34
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + corner))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + corner, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - corner, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + corner))
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY - corner))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + corner, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX - corner, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - radius), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - corner))
        return path
    }
}
