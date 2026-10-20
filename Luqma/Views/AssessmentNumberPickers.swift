import SwiftUI

/// Adopts the supplied Sandow age wheel and measurement ruler while retaining
/// a real text field. Raw input remains available to the form's validation.
struct AssessmentNumberPicker: View {
    enum Style: Equatable { case age, weight, height }

    let title: String
    @Binding var text: String
    let unit: String
    let range: ClosedRange<Double>
    let step: Double
    let identifier: String
    let style: Style
    var onEditingChanged: (Bool) -> Void = { _ in }

    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focused: Bool
    @State private var dragStart: Double?
    @ScaledMetric(relativeTo: .largeTitle) private var selectedAgeHeight: CGFloat = 162

    private var value: Double? {
        TextSearch.number(text).flatMap { $0.isFinite ? $0 : nil }
    }
    private var increment: Double { step.isFinite && step > 0 ? step : 1 }
    private var precision: Int {
        (0...6).first { abs(increment * pow(10, Double($0)) - (increment * pow(10, Double($0))).rounded()) < 0.000001 } ?? 6
    }
    private var isArabic: Bool { layoutDirection == .rightToLeft }

    var body: some View {
        VStack(spacing: style == .age ? 16 : 24) {
            Text(title).luqmaFont(.label).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            if style == .age { ageWheel }
            else { measurementRuler }
        }
        .frame(maxWidth: .infinity)
        .onChange(of: focused) { _, active in onEditingChanged(active) }
    }

    private var ageWheel: some View {
        VStack(spacing: 8) {
            adjacentAge(offset: -2, size: 30)
            adjacentAge(offset: -1, size: 56)
            VStack(spacing: 0) {
                numberField(size: dynamicTypeSize.isAccessibilitySize ? 80 : 112, color: Theme.onAccent)
                    .padding(.horizontal, 20)
                    .frame(minHeight: selectedAgeHeight)
            }
            .frame(maxWidth: 287)
            .background(Theme.text, in: RoundedRectangle(cornerRadius: 38, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .stroke(Theme.controlBorder, lineWidth: 3)
            }
            adjacentAge(offset: 1, size: 56)
            adjacentAge(offset: 2, size: 30)
            Text(unit).luqmaFont(.label).foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .simultaneousGesture(DragGesture(minimumDistance: 18)
            .onChanged { gesture in
                guard !focused, abs(gesture.translation.height) > abs(gesture.translation.width), let value else { return }
                if dragStart == nil { dragStart = value }
                let steps = (-Double(gesture.translation.height) / 36).rounded()
                setValue((dragStart ?? value) + steps * increment)
            }
            .onEnded { _ in dragStart = nil })
    }

    @ViewBuilder private func adjacentAge(offset: Int, size: CGFloat) -> some View {
        if let value, range.contains(value + Double(offset) * increment) {
            let candidate = value + Double(offset) * increment
            Button {
                focused = false
                setValue(candidate)
            } label: {
                Text(formatted(candidate)).luqmaFont(size: size, weight: .bold, relativeTo: .title)
                    .monospacedDigit().foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(formatted(candidate)) \(unit)")
            .accessibilityIdentifier("\(identifier).adjacent.\(offset)")
        } else {
            // No invented age is shown before the user has entered a value.
            Color.clear.frame(height: offset.magnitude == 1 ? 56 : 44).accessibilityHidden(true)
        }
    }

    private var measurementRuler: some View {
        VStack(spacing: 18) {
            Text(unit).luqmaFont(.button).foregroundStyle(Theme.onSecondaryAccent)
                .padding(.horizontal, 28).padding(.vertical, 12)
                .background(Theme.secondaryAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            numberField(size: 88, color: Theme.text)
                .frame(maxWidth: .infinity, minHeight: 100)
            ruler
            HStack(spacing: 16) {
                adjustmentButton(increasing: false)
                Spacer(minLength: 0)
                Text(unit).luqmaFont(.label).foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
                adjustmentButton(increasing: true)
            }
            .padding(.horizontal, 24)
        }
    }

    private func numberField(size: CGFloat, color: Color) -> some View {
        TextField("—", text: Binding(
            get: { DisplayFormat.westernDigits(text) },
            set: { text = DisplayFormat.westernDigits($0) }
        ), prompt: Text("—").foregroundColor(style == .age ? Theme.surface : Theme.muted))
        .keyboardType(style == .age ? .numberPad : .decimalPad)
        .focused($focused)
        .luqmaFont(size: size, weight: .bold, relativeTo: .largeTitle)
        .monospacedDigit().foregroundStyle(color)
        .multilineTextAlignment(.center).minimumScaleFactor(0.4)
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityLabel(title).accessibilityIdentifier(identifier)
    }

    private var ruler: some View {
        ZStack {
            Canvas { context, size in
                let spacing: CGFloat = 14
                let position = (value ?? 0) / increment
                // Bound the decorative tick phase before converting to Int;
                // typing an invalid or very large number never traps rendering.
                let phase = position.isFinite ? position.truncatingRemainder(dividingBy: 5) : 0
                for index in -20...20 {
                    let x = size.width / 2 + CGFloat(Double(index) - phase) * spacing
                    guard x >= 0, x <= size.width else { continue }
                    let major = index.isMultiple(of: 5)
                    let height: CGFloat = major ? 58 : 30
                    var tick = Path()
                    tick.move(to: CGPoint(x: x, y: (size.height - height) / 2))
                    tick.addLine(to: CGPoint(x: x, y: (size.height + height) / 2))
                    context.stroke(tick, with: .color(major ? Theme.controlBorder : Theme.surface),
                                   style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                }
            }
            Image("CFAWeightGlow").resizable().scaledToFit()
                .frame(width: 40, height: 124).accessibilityHidden(true)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Theme.text).frame(width: 10, height: 112)
        }
        .frame(height: 124).clipped().contentShape(Rectangle())
        .environment(\.layoutDirection, .leftToRight)
        .simultaneousGesture(DragGesture(minimumDistance: 14)
            .onChanged { gesture in
                guard abs(gesture.translation.width) > abs(gesture.translation.height), let value else { return }
                if dragStart == nil { dragStart = value; focused = false }
                let steps = (-Double(gesture.translation.width) / 14).rounded()
                setValue((dragStart ?? value) + steps * increment)
            }
            .onEnded { _ in dragStart = nil })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value.map { formatted($0) + " " + unit } ?? "—")
        .accessibilityHint(isArabic ? "اسحب لتغيير القيمة أو أدخلها في الحقل." : "Drag to adjust, or enter the value in the field.")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(by: increment)
            case .decrement: adjust(by: -increment)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("\(identifier).ruler")
    }

    private func adjustmentButton(increasing: Bool) -> some View {
        Button { adjust(by: increasing ? increment : -increment) } label: {
            Image(systemName: increasing ? "plus" : "minus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.text).frame(width: 48, height: 48)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain).disabled(value == nil)
        .accessibilityLabel(isArabic ? (increasing ? "زيادة \(title)" : "تقليل \(title)") : (increasing ? "Increase \(title)" : "Decrease \(title)"))
        .accessibilityIdentifier("\(identifier).\(increasing ? "increase" : "decrease")")
    }

    private func adjust(by delta: Double) {
        guard let value else { return }
        focused = false
        setValue(value + delta)
    }
    private func setValue(_ proposed: Double) {
        guard proposed.isFinite else { return }
        let clamped = min(range.upperBound, max(range.lowerBound, proposed))
        let quantized = (clamped / increment).rounded() * increment
        guard quantized.isFinite else { return }
        text = formatted(min(range.upperBound, max(range.lowerBound, quantized)))
    }
    private func formatted(_ number: Double) -> String {
        DisplayFormat.decimal(number, digits: precision)
    }
}
