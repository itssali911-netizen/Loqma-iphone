// Review-only native host. This file is never part of Luqma's production target.
// It compiles the exact DailyCalorieCard.swift; it does not duplicate its layout.
import SwiftUI
import UIKit

@main struct CalorieCardReviewApp: App {
    var body: some Scene { WindowGroup { CalorieCardReviewCanvas() } }
}

private struct CalorieCardReviewCanvas: View {
    private let arguments = ProcessInfo.processInfo.arguments
    private func option(_ name: String, fallback: String) -> String {
        guard let index = arguments.firstIndex(of: "--"+name), arguments.indices.contains(index+1) else { return fallback }
        return arguments[index+1]
    }
    private var state: String { option("state",fallback: "zero") }
    private var language: AppLanguage { option("language",fallback: "ar") == "en" ? .en : .ar }
    private var width: CGFloat { CGFloat(min(430,max(320,Double(option("width",fallback: "390")) ?? 390))) }
    private var largeText: Bool { option("dynamic-type",fallback: "large") == "accessibility3" }
    private var target: Nutrition {
        switch state {
        case "missing": return .zero
        case "long": return Nutrition(kcal: 100000,protein: 8000,carbs: 11600,fat: 2400)
        default: return Nutrition(kcal: 1500,protein: 120,carbs: 174,fat: 36)
        }
    }
    private var consumed: Nutrition {
        switch state {
        case "partial", "missing": return Nutrition(kcal: 600,protein: 48,carbs: 69.6,fat: 14.4)
        case "met": return target
        case "exceeded": return target.scaled(1.2)
        case "long": return target.scaled(0.5)
        default: return .zero
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading,spacing: 16) {
                Text(language.text("فحص مكوّن أصلي · بيانات اختبار", "Native component review · synthetic data"))
                    .luqmaFont(size: 12,relativeTo: .caption).foregroundStyle(.gray)
                DailyCalorieCard(consumed: consumed,goals: target,language: language,isLoading: state == "loading",showHistory: false)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.task { record(geometry.frame(in: .global)) }
                        }
                    }
                Text("\(state) · \(Int(width)) pt · \(largeText ? "accessibility3" : "large")")
                    .font(.caption).foregroundStyle(.gray).accessibilityIdentifier("review.fixture")
            }.padding(.horizontal,16).padding(.vertical,20).frame(width: width)
                .frame(maxWidth: .infinity,alignment: .center)
        }.background(Color(red:17/255.0,green:20/255.0,blue:22/255.0).ignoresSafeArea())
            .preferredColorScheme(.dark)
            .environment(\.layoutDirection,language == .ar ? .rightToLeft:.leftToRight)
            .environment(\.locale,DisplayFormat.locale(language))
            .environment(\.dynamicTypeSize,largeText ? .accessibility3:.large)
    }
    private func record(_ frame: CGRect) {
        // Geometry belongs to this synthetic harness only, never the user's app.
        let data: [String: Any] = ["scope":"native component harness; synthetic inputs", "state":state,
            "language":language.rawValue,"canvas_width":Double(width),"scale":Double(UIScreen.main.scale),
            "dynamic_type":largeText ? "accessibility3":"large", "card_frame":["x":frame.minX,"y":frame.minY,"width":frame.width,"height":frame.height]]
        guard let url = FileManager.default.urls(for: .documentDirectory,in: .userDomainMask).first?.appendingPathComponent("review-geometry.json"),
              let json = try? JSONSerialization.data(withJSONObject:data,options:.sortedKeys) else { return }
        try? json.write(to:url,options:.atomic)
    }
}
