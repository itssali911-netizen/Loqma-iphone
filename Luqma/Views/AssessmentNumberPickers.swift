import SwiftUI

/// Approved ruler/wheel presentation over the existing single raw input.
/// No persistence or estimation runs during a gesture. A blank answer remains
/// blank until the user types, taps a neighbour, or moves the ruler/wheel.
struct AssessmentNumberPicker: View {
    enum Style { case age, weight, height }
    let title: String
    @Binding var text: String
    let unit: String
    let field: FitnessAssessmentNumberField
    let identifier: String
    let style: Style
    @Binding var displayUnit: ApprovedMeasurementUnit
    @Binding var alternateText:String
    var onInteractionChanged:(Bool)->Void = {_ in}
    @Environment(\.layoutDirection) private var direction
    @ScaledMetric(relativeTo:.body) private var promptPoints:CGFloat=22
    @FocusState private var focused: Bool
    @State private var dragStart: Double?
    private var value: Double? { field.parse(text) }
    private var arabic: Bool { direction == .rightToLeft }
    private var interactionValue: Double { value ?? field.suggestedValue }
    private var visibleUnit: String {
        guard style != .age else{return unit}
        if displayUnit == .imperial{return style == .height ? "in":"lbs"}
        return style == .weight ? "kg":unit
    }
    private var displayBinding: Binding<String> {
        Binding(get: {
            guard style != .age,displayUnit == .imperial else{return text}
            if !alternateText.isEmpty{return alternateText}
            guard let number = Double(text),number.isFinite else{return text}
            return DisplayFormat.decimal(displayUnit.displayed(number, field: field), digits: 1)
        }, set: { proposed in
            let normalized = String(DisplayFormat.westernDigits(proposed).prefix(64))
            if style != .age,displayUnit == .imperial {
                alternateText=normalized
                text=displayUnit.canonicalText(from:normalized,field:field)
            }else if text != normalized{text=normalized}
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            if style == .age {
                ageWheel
                Text(unit).luqmaFont(size:14,weight:.medium,relativeTo:.subheadline).foregroundStyle(Color(hex:0x9EA0A5)).padding(.top,12)
            }
            else {
                unitSelector
                Spacer(minLength: 28)
                readout
                ruler.padding(.top, 18)
                rulerNeighbours.padding(.top, 2)
                Spacer(minLength: 16)
            }
            if value == nil {
                Text(arabic ? "اكتب القيمة أو اسحب للاختيار؛ لم تُحدّد قيمة بعد." : "Type a value or drag to choose; no value has been selected.")
                    .luqmaFont(size: 12, relativeTo: .caption).foregroundStyle(Color(hex: 0x9EA0A5))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            }
        }.frame(maxWidth: .infinity).onDisappear{onInteractionChanged(false)}
            .onChange(of:displayUnit){_,_ in alternateText=""}
            .onChange(of:text){_,_ in if displayUnit == .metric{alternateText=""}}
    }

    private var unitSelector: some View {
        HStack(spacing: 0) {
            ForEach(ApprovedMeasurementUnit.allCases) { option in
                Button { focused = false; displayUnit = option } label: {
                    Text(option.title(for: field)).luqmaFont(size: 14, weight: .bold, relativeTo: .subheadline)
                        .foregroundStyle(displayUnit == option ? Color.white : Color(hex: 0x9EA0A5))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(displayUnit == option ? Color(hex: 0x2563EB) : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }.buttonStyle(LuqmaPressStyle())
                    .accessibilityAddTraits(displayUnit == option ? .isSelected : [])
                    .accessibilityIdentifier("\(identifier).unit.\(option.rawValue)")
            }
        }.padding(4).background(Color(hex: 0x24262B), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .environment(\.layoutDirection, .leftToRight)
            .luqmaMotion(.selection,value:displayUnit)
            .luqmaFeedback(.selection,trigger:displayUnit)
    }

    private var readout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            numericInput(size: style == .weight ? 104 : 84, color: .white)
                .frame(minWidth: 100, maxWidth: 250)
            Text(visibleUnit).luqmaFont(size: style == .weight ? 36 : 28, weight: .semibold, relativeTo: .title2)
                .foregroundStyle(Color(hex: 0x9EA0A5)).fixedSize()
        }.frame(maxWidth: .infinity, minHeight: style == .weight ? 130 : 110)
            .environment(\.layoutDirection, .leftToRight)
    }

    private func numericInput(size: CGFloat, color: Color) -> some View {
        TextField("", text: displayBinding, prompt: Text(arabic ? "أدخل" : "Enter")
            .font(LTypography.font(size:promptPoints,weight:.semibold,relativeTo:.body)).foregroundColor(color.opacity(0.6)))
            .keyboardType(field.integer ? .numberPad : .decimalPad).focused($focused)
            .luqmaFont(size: size, weight: .heavy, relativeTo: .largeTitle)
            .monospacedDigit().multilineTextAlignment(.center).minimumScaleFactor(0.4)
            .foregroundStyle(color).environment(\.layoutDirection, .leftToRight)
            .accessibilityLabel(title + " " + visibleUnit).accessibilityIdentifier(identifier)
    }

    private var ruler: some View {
        ZStack {
            ApprovedRulerTicks().stroke(Color(hex: 0x393C43), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            ApprovedRulerTicks(majorOnly: true).stroke(Color(hex: 0x676C75), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            Image("CFAWeightGlow").resizable().scaledToFit().frame(width: 36, height: 134).accessibilityHidden(true)
            RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white).frame(width: 10, height: 112)
        }.frame(height: 124).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 2).onChanged { gesture in
                focused = false
                if dragStart == nil {dragStart=interactionValue;onInteractionChanged(true)}
                let units = -Double(gesture.translation.width) / 14
                let original = displayUnit.displayed(dragStart ?? interactionValue, field: field)
                let displayed = (original + units).rounded()
                setValue(displayUnit.metric(displayed, field: field), quantize: displayUnit == .metric)
            }.onEnded { _ in dragStart = nil;onInteractionChanged(false) })
            .accessibilityElement(children: .ignore).accessibilityLabel(title + " " + visibleUnit)
            .accessibilityValue(value.map { DisplayFormat.decimal(displayUnit.displayed($0, field: field)) } ?? (arabic ? "لم يُحدّد بعد" : "Not selected"))
            .accessibilityAdjustableAction { adjustment in adjust(increasing: adjustment == .increment) }
            .accessibilityIdentifier("\(identifier).slider")
            .environment(\.layoutDirection, .leftToRight)
    }

    private var rulerNeighbours: some View {
        HStack {
            neighbourButton(increasing: false)
            Spacer()
            neighbourButton(increasing: true)
        }.padding(.horizontal, 52).environment(\.layoutDirection, .leftToRight)
    }

    private func neighbourButton(increasing: Bool) -> some View {
        let metricStep = displayUnit == .metric ? field.step : displayUnit.metric(1, field: field)
        let neighbour = min(field.range.upperBound, max(field.range.lowerBound, interactionValue + (increasing ? metricStep : -metricStep)))
        return Button { adjust(increasing: increasing) } label: {
            Text(DisplayFormat.decimal(displayUnit.displayed(neighbour, field: field)))
                .luqmaFont(size: 14, weight: .semibold, relativeTo: .subheadline).foregroundStyle(Color(hex: 0x9EA0A5))
                .frame(minWidth: 44, minHeight: 44)
        }.buttonStyle(LuqmaPressStyle()).disabled(value.map { increasing ? $0 >= field.range.upperBound : $0 <= field.range.lowerBound } ?? false)
            .accessibilityLabel(arabic ? (increasing ? "زيادة \(title)" : "تقليل \(title)") : (increasing ? "Increase \(title)" : "Decrease \(title)"))
            .accessibilityIdentifier("\(identifier).\(increasing ? "increase" : "decrease")")
    }

    private var ageWheel: some View {
        VStack(spacing: 8) {
            ageRow(offset: -2, fontSize: 30, color: Color(hex: 0x393C43))
            ageRow(offset: -1, fontSize: 56, color: Color(hex: 0x676C75))
            numericInput(size: 128, color: Color(hex: 0x111214))
                .frame(width: 287, height: 162)
                .background(Color(hex: 0xF3F3F4), in: RoundedRectangle(cornerRadius: 38, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 38, style: .continuous).stroke(Color.white, lineWidth: 3).allowsHitTesting(false) }
                .overlay { RoundedRectangle(cornerRadius: 42, style: .continuous).stroke(Color(hex: 0x393C43).opacity(0.55), lineWidth: 4).padding(-2).allowsHitTesting(false) }
            ageRow(offset: 1, fontSize: 56, color: Color(hex: 0x676C75))
            ageRow(offset: 2, fontSize: 30, color: Color(hex: 0x393C43))
        }.frame(maxWidth: .infinity).contentShape(Rectangle())
            // Standard-size assessment pages give the vertical gesture to the
            // wheel instead of a competing parent scroll gesture.
            .highPriorityGesture(DragGesture(minimumDistance: 8).onChanged { gesture in
                focused = false
                if dragStart == nil {dragStart=interactionValue;onInteractionChanged(true)}
                let delta = (-Double(gesture.translation.height) / 36).rounded()
                setValue((dragStart ?? interactionValue) + delta)
            }.onEnded { _ in dragStart = nil;onInteractionChanged(false) })
            // Give the wheel its own accessibility container. Without this,
            // SwiftUI propagates the container identifier onto every child,
            // replacing the editable field and neighbour-button identifiers.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("\(identifier).slider")
    }

    @ViewBuilder private func ageRow(offset: Int, fontSize: CGFloat, color: Color) -> some View {
        let proposed = Int(interactionValue) + offset
        if field.range.contains(Double(proposed)) {
            Button { focused = false; setValue(Double(proposed)) } label: {
                Text("\(proposed)").luqmaFont(size: fontSize, weight: .heavy, relativeTo: .title)
                    .foregroundStyle(color).frame(minHeight: 36)
            }.buttonStyle(LuqmaPressStyle())
                .accessibilityLabel(arabic ? "العمر \(proposed) سنة" : "Age \(proposed) years")
                .accessibilityIdentifier(abs(offset) == 1 ? "\(identifier).\(offset > 0 ? "increase" : "decrease")" : "\(identifier).neighbour.\(offset)")
        } else {
            Color.clear.frame(height: fontSize == 56 ? 67 : 36).accessibilityHidden(true)
        }
    }

    private func adjust(increasing: Bool) {
        focused = false
        let amount = displayUnit == .metric || style == .age ? field.step : displayUnit.metric(1, field: field)
        setValue(interactionValue + (increasing ? amount : -amount), quantize: displayUnit == .metric || style == .age)
    }
    private func setValue(_ proposed: Double, quantize: Bool = true) {
        guard proposed.isFinite else { return }
        alternateText=""
        let bounded = quantize ? field.clampedInteractionValue(proposed) : min(field.range.upperBound, max(field.range.lowerBound, proposed))
        let next = field.displayText(bounded)
        if next != text { text = next }
    }
}

private struct ApprovedRulerTicks: Shape {
    var majorOnly = false
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for offset in -12...12 where !majorOnly || offset % 5 == 0 {
            let x = rect.midX + CGFloat(offset) * 13.5
            let height: CGFloat = offset % 5 == 0 ? 58 : 30
            path.move(to: CGPoint(x: x, y: rect.midY - height / 2))
            path.addLine(to: CGPoint(x: x, y: rect.midY + height / 2))
        }
        return path
    }
}
