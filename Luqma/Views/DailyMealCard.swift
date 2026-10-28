import SwiftUI

/// The supplied photographs identify meal categories; the numbers always come
/// from the saved diary. Artwork is never presented as a user's actual photo.
struct DailyMealCard: View {
    let summary: MealDiarySummary
    let language: AppLanguage
    let onAdd: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var artwork: String {
        switch summary.meal {
        case .breakfast: return "DailyMealBreakfast"
        case .lunch: return "DailyMealLunch"
        case .dinner: return "DailyMealDinner"
        case .snack: return "DailyMealSnack"
        }
    }
    private var direction: LayoutDirection { language == .ar ? .rightToLeft : .leftToRight }
    private var mealTitle: String { summary.meal == .snack ? language.text("السناك", "Snack") : summary.meal.label(language) }

    var body: some View {
        Button(action: onAdd) {
            DailyMealCardLayout {
                controls
                information
                macroStrip
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background {
                GeometryReader { geometry in
                    Image(artwork).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .accessibilityHidden(true).allowsHitTesting(false)
                        .overlay {
                            LinearGradient(stops: [.init(color: .black.opacity(0.05), location: 0),
                                                   .init(color: .black.opacity(0.10), location: 0.48),
                                                   .init(color: .black.opacity(0.24), location: 1)],
                                           startPoint: .leading, endPoint: .trailing)
                        }
                }.environment(\.layoutDirection, .leftToRight)
                    .accessibilityHidden(true).allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(hex: 0x35383F), lineWidth: 1) }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(LuqmaPressStyle())
        .accessibilityIdentifier("diary.meal." + summary.meal.rawValue)
        .accessibilityLabel(language.text("إضافة إلى ", "Add to ") + mealTitle)
        .accessibilityValue(accessibilitySummary)
        .accessibilityHint(language.text("صورة توضيحية لنوع الوجبة. الأرقام من الأطعمة المسجلة.", "Illustrative meal-category photograph. Values come from logged foods."))
    }

    private var controls: some View {
        HStack(spacing: 0) {
            // The whole card is the add action, including this 44-point target.
            Image(systemName: "plus").font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white).frame(width: 26, height: 26)
                .background(.black.opacity(0.52), in: Circle())
                .overlay { Circle().strokeBorder(.white.opacity(0.12), lineWidth: 1) }
            Spacer(minLength: 12)
            Image("SandowDinner").renderingMode(.template).resizable().scaledToFit()
                .frame(width: 14, height: 14).foregroundStyle(Color(hex: 0xFFF0DA))
                .frame(width: 27, height: 27)
                .background(Color(hex: 0xD47732), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }.environment(\.layoutDirection, .leftToRight).accessibilityHidden(true)
    }

    private var information: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(mealTitle).luqmaFont(size: 16, weight: .bold, relativeTo: .headline)
                .foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Image("AddMealCalories").renderingMode(.template).resizable().scaledToFit()
                    .frame(width: 12, height: 12).foregroundStyle(Color(hex: 0xD78957))
                Text(DisplayFormat.decimal(summary.nutrition.kcal, digits: 0))
                    .luqmaFont(size: 14, weight: .bold, relativeTo: .subheadline).monospacedDigit()
                    .luqmaNumericMotion(value: summary.nutrition.kcal)
                    .fixedSize(horizontal: false, vertical: true)
                Text(language.text("سعرة", "kcal")).luqmaFont(size: 12, relativeTo: .caption)
            }.environment(\.layoutDirection, direction).foregroundStyle(Color(hex: 0xF7F8FA))
        }.frame(maxWidth: .infinity, alignment: .trailing)
            .environment(\.layoutDirection, .leftToRight)
    }

    private var macroStrip: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 8) { ForEach(MacroKey.allCases) { macro($0) } }
            } else {
                HStack(spacing: 7) {
                    macro(.protein)
                    Rectangle().fill(Color(hex: 0x35383F)).frame(width: 1, height: 12)
                    macro(.carbs)
                    Rectangle().fill(Color(hex: 0x35383F)).frame(width: 1, height: 12)
                    macro(.fat)
                }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(.black.opacity(0.64), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.06), lineWidth: 1) }
        .environment(\.layoutDirection, direction)
    }

    private func macro(_ key: MacroKey) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 3) { macroName(key); macroValue(key) }.fixedSize(horizontal: true, vertical: false)
            VStack(spacing: 1) { macroName(key); macroValue(key) }
        }.frame(maxWidth: .infinity)
    }
    private func macroName(_ key: MacroKey) -> some View {
        HStack(spacing: 3) {
            Image(icon(key)).renderingMode(.template).resizable().scaledToFit()
                .frame(width: 11, height: 11).foregroundStyle(color(key))
            Text(key == .carbs ? language.text("الكارب", "Carbs") : key.label(language))
                .luqmaFont(size: 12, relativeTo: .caption).foregroundStyle(Color(hex: 0xD3D4D9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func macroValue(_ key: MacroKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(grams(summary.nutrition[key]))
                .luqmaFont(size: 12, weight: .bold, relativeTo: .caption).monospacedDigit()
                .luqmaNumericMotion(value: summary.nutrition[key])
            Text(language.text("جم", "g")).luqmaFont(size: 12, relativeTo: .caption)
        }.foregroundStyle(Color(hex: 0xF7F8FA))
    }
    private func icon(_ key: MacroKey) -> String {
        switch key { case .protein: return "AddMealProtein"; case .carbs: return "AddMealCarbs"; case .fat: return "AddMealFat" }
    }
    private func color(_ key: MacroKey) -> Color {
        switch key { case .protein: return Color(hex: 0xC48794); case .carbs: return Color(hex: 0xCEA46E); case .fat: return Color(hex: 0x92A37E) }
    }
    private var mealCount: String {
        let count = summary.entries.count
        if count == 0 { return language.text("أضف أول طعام", "Add your first food") }
        if count == 1 { return language.text("1 طعام مسجل", "1 food logged") }
        return DisplayFormat.decimal(Double(count), digits: 0) + " " + language.text("أطعمة مسجلة", "foods logged")
    }
    private func grams(_ value: Double) -> String {
        let formatted = DisplayFormat.decimal(value)
        return formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted
    }
    private var accessibilitySummary: String {
        let energy = DisplayFormat.decimal(summary.nutrition.kcal, digits: 0) + " " + language.text("سعرة", "kcal")
        let macros = MacroKey.allCases.map { key in
            key.label(language) + " " + grams(summary.nutrition[key]) + " " + language.text("جم", "g")
        }
        return ([mealCount, energy] + macros).joined(separator: ", ")
    }
}

/// Keeps the measured reference ratio as a minimum. Native text may increase
/// the height at narrow widths or accessibility sizes instead of being clipped.
private struct DailyMealCardLayout: Layout {
    private let gap: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(0, proposal.width ?? 330)
        let heights = subviews.map { $0.sizeThatFits(.init(width: width, height: nil)).height }
        return CGSize(width: width, height: max((width + 28) * 337 / 950 - 28, heights.reduce(0, +) + gap * 2))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let sizes = subviews.map { $0.sizeThatFits(.init(width: bounds.width, height: nil)) }
        let lastY = bounds.maxY - sizes[2].height
        let positions = [bounds.minY, lastY - gap - sizes[1].height, lastY]
        for index in subviews.indices {
            subviews[index].place(at: CGPoint(x: bounds.minX, y: positions[index]), anchor: .topLeading,
                                 proposal: .init(width: bounds.width, height: sizes[index].height))
        }
    }
}
