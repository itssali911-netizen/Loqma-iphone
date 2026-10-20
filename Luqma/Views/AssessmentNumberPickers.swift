import SwiftUI

/// All controls share one raw binding. The native horizontal slider does not
/// compete with vertical scrolling, and never accepts a default as an answer.
struct AssessmentNumberPicker: View {
    enum Style { case age, weight, height }
    let title: String
    @Binding var text: String
    let unit: String
    let field: FitnessAssessmentNumberField
    let identifier: String
    let style: Style
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focused: Bool
    private var value: Double? { field.parse(text) }
    private var isArabic: Bool { layoutDirection == .rightToLeft }

    var body: some View {
        VStack(spacing: 20) {
            Text(title).luqmaFont(.label).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                TextField("", text: Binding(get: { text }, set: { new in
                    let normalized = String(DisplayFormat.westernDigits(new).prefix(64))
                    if text != normalized { text = normalized }
                }), prompt: Text(isArabic ? "أدخل" : "Enter")
                    .foregroundColor(style == .age ? Theme.surface : Theme.muted))
                    .keyboardType(field.integer ? .numberPad : .decimalPad)
                    .focused($focused)
                    .luqmaFont(size: dynamicTypeSize.isAccessibilitySize ? 44 : (style == .age ? 80 : 58), weight: .bold, relativeTo: .largeTitle)
                    .monospacedDigit().multilineTextAlignment(.center).minimumScaleFactor(0.5)
                    .foregroundStyle(style == .age ? Theme.onAccent : Theme.text)
                    .environment(\.layoutDirection, .leftToRight)
                    .accessibilityLabel(title).accessibilityIdentifier(identifier)
                Text(unit).luqmaFont(.label)
                    .foregroundStyle(style == .age ? Theme.onAccent : Theme.muted).fixedSize()
            }
            .padding(.horizontal, 24).padding(.vertical, 24)
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(style == .age ? Theme.text : Theme.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Theme.controlBorder, lineWidth: 1) }
            HStack(spacing: 14) {
                adjustmentButton(increasing: false)
                Slider(value: Binding(get: { value ?? field.suggestedValue }, set: { setValue($0) }),
                       in: field.range, step: field.step, onEditingChanged: { active in
                    if active { focused = false }
                })
                .tint(Theme.accent).environment(\.layoutDirection, .leftToRight)
                .accessibilityLabel(title + " " + unit)
                .accessibilityHint(isArabic ? "حرّك أفقيًا أو أدخل الرقم في الحقل أعلاه." : "Move horizontally or type in the field above.")
                .accessibilityIdentifier("\(identifier).slider")
                adjustmentButton(increasing: true)
            }.environment(\.layoutDirection, .leftToRight)
            HStack {
                Text(field.displayText(field.range.lowerBound))
                Spacer()
                Text(field.displayText(field.range.upperBound))
            }.luqmaFont(.helper).monospacedDigit().foregroundStyle(Theme.muted)
                .environment(\.layoutDirection, .leftToRight)
            Text(isArabic ? "اكتب القيمة أو حرّك المؤشر. يمكنك الضبط الدقيق بزرّي + و−." : "Type a value or move the slider. Use + and − for fine adjustments.")
                .luqmaFont(.helper).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if value == nil {
                Text(isArabic ? "لم تُحدّد قيمة بعد؛ موضع المؤشر نقطة بداية فقط." : "No value selected yet; the thumb position is only a starting point.")
                    .luqmaFont(.helper).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }.frame(maxWidth: .infinity)
    }
    private func adjustmentButton(increasing: Bool) -> some View {
        Button {
            focused = false
            setValue((value ?? field.suggestedValue) + (increasing ? field.step : -field.step))
        } label: {
            Image(systemName: increasing ? "plus" : "minus").font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.text).frame(width: 48, height: 48)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }.buttonStyle(.plain)
            .disabled(value.map { increasing ? $0 >= field.range.upperBound : $0 <= field.range.lowerBound } ?? false)
            .accessibilityLabel(isArabic ? (increasing ? "زيادة \(title)" : "تقليل \(title)") : (increasing ? "Increase \(title)" : "Decrease \(title)"))
            .accessibilityIdentifier("\(identifier).\(increasing ? "increase" : "decrease")")
    }
    private func setValue(_ proposed: Double) {
        guard proposed.isFinite else { return }
        let next = field.displayText(field.clampedInteractionValue(proposed))
        if text != next { text = next }
    }
}
