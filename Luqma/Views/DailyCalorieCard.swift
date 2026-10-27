import SwiftUI

/// Reference-card tokens are deliberately local. No application theme is changed.
private enum CalorieCardStyle {
    static let surface = Color(red: 24/255.0, green: 26/255.0, blue: 29/255.0)
    static let border = Color(red: 53/255.0, green: 56/255.0, blue: 63/255.0)
    static let track = Color(red: 54/255.0, green: 55/255.0, blue: 62/255.0)
    static let text = Color(red: 247/255.0, green: 248/255.0, blue: 250/255.0)
    static let secondary = Color(red: 176/255.0, green: 179/255.0, blue: 189/255.0)
    static let accent = Color(red: 1, green: 117/255.0, blue: 21/255.0)
    static func color(_ key: MacroKey) -> Color {
        switch key {
        case .protein: return Color(red: 239/255.0, green: 121/255.0, blue: 142/255.0)
        case .carbs: return Color(red: 232/255.0, green: 179/255.0, blue: 76/255.0)
        case .fat: return Color(red: 143/255.0, green: 190/255.0, blue: 99/255.0)
        }
    }
    static func icon(_ key: MacroKey) -> String {
        switch key { case .protein: return "CalorieCardProtein"; case .carbs: return "CalorieCardCarbs"; case .fat: return "CalorieCardFat" }
    }
}

/// Native text, vectors and bars. Inputs come from the existing diary aggregation.
struct DailyCalorieCard: View {
    let consumed: Nutrition
    let goals: Nutrition
    let language: AppLanguage
    var isLoading = false
    var showHistory = true
    var onHistory: () -> Void = {}
    var onEditGoal: () -> Void = {}
    @Environment(\.dynamicTypeSize) private var typeSize

    private var direction: LayoutDirection { language == .ar ? .rightToLeft : .leftToRight }
    private var alignment: HorizontalAlignment { .leading }
    private var current: Double? { available(consumed.kcal) }
    private var target: Double? { positive(goals.kcal) }
    private var difference: Double? { guard let current, let target else { return nil }; return target-current }
    private var exceeded: Bool { (difference ?? 0) < 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            CalorieMetricLayout(rightToLeft: language == .ar, stacked: typeSize.isAccessibilitySize, spacing: 12) {
                consumedGroup.environment(\.layoutDirection, direction)
                remainingGroup.environment(\.layoutDirection, direction)
            }.environment(\.layoutDirection, .leftToRight).padding(.top, 10)
            CalorieCardBar(value: current, goal: target, color: CalorieCardStyle.accent, height: 6,
                           label: language.text("التقدّم نحو هدف السعرات", "Daily calorie progress"),
                           identifier: "diary.summary.progress", loading: isLoading)
                .padding(.top, 12)
            Rectangle().fill(CalorieCardStyle.border).frame(height: 1).padding(.vertical, 16)
            if typeSize.isAccessibilitySize {
                VStack(spacing: 16) { ForEach(MacroKey.allCases) { macro($0) } }
            } else {
                HStack(alignment: .top, spacing: 16) { ForEach(MacroKey.allCases) { macro($0) } }
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CalorieCardStyle.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(CalorieCardStyle.border, lineWidth: 1) }
        .foregroundStyle(CalorieCardStyle.text)
        .environment(\.layoutDirection, direction)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diary.calorieGoal")
        .accessibilityValue(number(target))
        .accessibilityAction(named: Text(language.text("تعديل هدف السعرات", "Edit calorie goal")), onEditGoal)
    }

    @ViewBuilder private var header: some View {
        if showHistory {
            Button(action: onHistory) { heading }
                .buttonStyle(.plain).accessibilityIdentifier("diary.calorieDetails")
                .accessibilityLabel(language.text("ملخص السعرات اليوم", "Daily calorie summary"))
                .accessibilityHint(language.text("عرض استهلاك آخر 7 أيام", "View the last seven days"))
        } else { heading }
    }
    private var heading: some View {
        HStack(spacing: 12) {
            Text(language.text("ملخص السعرات اليوم", "Daily calorie summary"))
                .luqmaFont(size: 14, weight: .medium, relativeTo: .subheadline)
                .foregroundStyle(CalorieCardStyle.secondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("diary.summary.title")
            Spacer(minLength: 0)
            Image("CalorieCardFlame").renderingMode(.template).resizable().scaledToFit()
                .frame(width: 24, height: 24).foregroundStyle(CalorieCardStyle.accent).accessibilityHidden(true)
        }.frame(minHeight: 32).contentShape(Rectangle().inset(by: -6))
    }

    private var consumedGroup: some View {
        VStack(alignment: alignment, spacing: 2) {
            ViewThatFits(in: .horizontal) {
                consumptionRatio.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: alignment, spacing: 2) {
                    consumedNumber
                    goalAndUnit
                }
            }
            Text(isLoading ? language.text("جارٍ تحميل السعرات…", "Loading calories…") : target == nil
                 ? language.text("لم يُحدد الهدف", "No target set")
                 : language.text("المستهلك من هدفك اليومي", "Consumed from your daily target"))
                .luqmaFont(size: 12, relativeTo: .caption).foregroundStyle(CalorieCardStyle.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var consumptionRatio: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) { consumedNumber; goalAndUnit }
    }
    private var consumedNumber: some View {
        Text(number(current)).luqmaFont(size: 40, weight: .bold, relativeTo: .largeTitle).monospacedDigit()
            .fixedSize().accessibilityIdentifier("diary.summary.consumed")
            .accessibilityHint(language.text("السعرات المستهلكة", "Calories consumed"))
    }
    private var goalAndUnit: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("/").luqmaFont(size: 18, weight: .medium, relativeTo: .subheadline).accessibilityHidden(true)
            Text(number(target)).luqmaFont(size: 18, weight: .semibold, relativeTo: .subheadline)
                .monospacedDigit().accessibilityIdentifier("diary.summary.target")
                .accessibilityHint(language.text("هدف السعرات", "Calorie target"))
            Text(language.text("سعرة", "kcal")).luqmaFont(size: 12, relativeTo: .caption)
        }.foregroundStyle(CalorieCardStyle.secondary).fixedSize(horizontal: true, vertical: false)
    }
    private var remainingGroup: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(number(difference.map(abs))).luqmaFont(size: 29, weight: .bold, relativeTo: .largeTitle)
                .monospacedDigit().foregroundStyle(CalorieCardStyle.accent).fixedSize()
                .accessibilityIdentifier("diary.summary.remaining")
                .accessibilityHint(exceeded ? language.text("السعرات فوق الهدف", "Calories above target") : language.text("السعرات المتبقية", "Calories remaining"))
            Text(isLoading ? language.text("جارٍ التحميل", "Loading") : difference == nil
                 ? language.text("لم يُحدد الهدف", "No target set")
                 : exceeded ? language.text("متجاوز بـ", "Over by") : language.text("متبقية", "Remaining"))
                .luqmaFont(size: 12, relativeTo: .caption).foregroundStyle(CalorieCardStyle.secondary)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("diary.summary.balanceLabel")
        }
    }
    private func macro(_ key: MacroKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(CalorieCardStyle.icon(key)).renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 20, height: 20).foregroundStyle(CalorieCardStyle.color(key)).accessibilityHidden(true)
                Text(key.label(language)).luqmaFont(size: 12, weight: .medium, relativeTo: .caption)
                    .foregroundStyle(CalorieCardStyle.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            ViewThatFits(in: .horizontal) {
                macroRatio(key).fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 3) {
                    Text(number(available(consumed[key]))).luqmaFont(size: 17, weight: .medium, relativeTo: .headline)
                        .monospacedDigit().accessibilityIdentifier("diary.summary."+key.rawValue+".consumed")
                    macroTarget(key)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            CalorieCardBar(value: available(consumed[key]), goal: positive(goals[key]), color: CalorieCardStyle.color(key), height: 4,
                           label: key.label(language)+" "+language.text("التقدّم اليومي", "daily progress"),
                           identifier: "diary.summary."+key.rawValue+".progress", loading: isLoading)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).accessibilityElement(children: .contain)
    }
    private func macroRatio(_ key: MacroKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(number(available(consumed[key]))).luqmaFont(size: 17, weight: .medium, relativeTo: .headline)
                .monospacedDigit().accessibilityIdentifier("diary.summary."+key.rawValue+".consumed")
            macroTarget(key)
        }
    }
    private func macroTarget(_ key: MacroKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("/").luqmaFont(size: 15, relativeTo: .caption).accessibilityHidden(true)
            Text(number(available(goals[key]))).luqmaFont(size: 17, weight: .semibold, relativeTo: .headline)
                .monospacedDigit().accessibilityIdentifier("diary.summary."+key.rawValue+".target")
            Text(language.text("جم", "g")).luqmaFont(size: 12, relativeTo: .caption)
        }
    }
    private func available(_ value: Double) -> Double? { !isLoading && value.isFinite && value >= 0 ? value : nil }
    private func positive(_ value: Double) -> Double? { guard let value = available(value), value > 0 else { return nil }; return value }
    private func number(_ value: Double?) -> String { value.map { DisplayFormat.decimal($0, digits: 0) } ?? "—" }
}

private struct CalorieCardBar: View {
    let value: Double?
    let goal: Double?
    let color: Color
    let height: CGFloat
    let label: String
    let identifier: String
    let loading: Bool
    private var fraction: Double {
        guard let value, let goal, value.isFinite, goal.isFinite, goal > 0 else { return 0 }
        return min(1, max(0, value/goal))
    }
    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(CalorieCardStyle.track).overlay(alignment: .leading) {
                if fraction > 0 { Capsule().fill(color).frame(width: geometry.size.width*fraction) }
            }
        }.frame(height: height).accessibilityElement(children: .ignore)
            .accessibilityLabel(label).accessibilityValue(loading || value == nil || goal == nil ? "—" : DisplayFormat.decimal(fraction*100, digits: 0)+"%")
            .accessibilityIdentifier(identifier)
    }
}

/// Measures native text before positioning. Large values or Dynamic Type reflow
/// instead of clipping, scaling the reference typography down, or fixing height.
private struct CalorieMetricLayout: Layout {
    var rightToLeft: Bool
    var stacked: Bool
    var spacing: CGFloat
    private func arrangement(_ proposal: ProposedViewSize, _ subviews: Subviews) -> (CGSize, CGSize, CGFloat, Bool, CGFloat) {
        let width = proposal.width ?? 330
        let first = subviews[0].sizeThatFits(.unspecified), second = subviews[1].sizeThatFits(.unspecified)
        let vertical = stacked || first.width+second.width+spacing > width
        if vertical {
            let a = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let b = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
            return (a,b,width,true,0)
        }
        let baselineA = subviews[0].dimensions(in: .unspecified)[VerticalAlignment.firstTextBaseline]
        let baselineB = subviews[1].dimensions(in: .unspecified)[VerticalAlignment.firstTextBaseline]
        return (first,second,width,false,max(0,baselineA-baselineB-3))
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let (a,b,width,vertical,offset) = arrangement(proposal,subviews)
        return CGSize(width: width, height: vertical ? a.height+spacing+b.height : max(a.height,b.height+offset))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let (a,b,_,vertical,offset) = arrangement(ProposedViewSize(width: bounds.width,height: nil),subviews)
        let firstX = rightToLeft ? bounds.maxX-a.width : bounds.minX
        let secondX = rightToLeft ? bounds.minX : bounds.maxX-b.width
        subviews[0].place(at: CGPoint(x: firstX,y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(a))
        subviews[1].place(at: CGPoint(x: vertical ? (rightToLeft ? bounds.maxX-b.width : bounds.minX) : secondX,
                                     y: vertical ? bounds.minY+a.height+spacing : bounds.minY+offset),
                          anchor: .topLeading, proposal: ProposedViewSize(b))
    }
}
