import Foundation
import CoreImage
import CoreGraphics
import Darwin

// Only a public-domain USDA fixture is logged; the iPhone app has no diagnostic logger.
private func trace(_ value: String) { try? FileHandle.standardError.write(contentsOf: Data((value + "\n").utf8)) }

@main struct ModelCheck {
    static func main() async {
        let destination = URL(fileURLWithPath: CommandLine.arguments[2])
        do { try await check(destination) }
        catch {
            trace("RUNTIME TEST ERROR: \(error)")
            if !FileManager.default.fileExists(atPath: destination.path) {
                let report: [String: Any] = ["tested": false, "passed": false, "error": String(describing: error)]
                try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted]).write(to: destination)
            }
            exit(1)
        }
    }
    private static func check(_ destination: URL) async throws {
        guard VisionAnalyzer.supported else {
            let report: [String: Any] = ["tested": false, "reason": "Metal GPU or memory unavailable on this runner"]
            try JSONSerialization.data(withJSONObject: report).write(to: destination)
            trace("Model runtime unavailable on this runner."); return
        }
        let foods = try JSONDecoder().decode([PhotoFood].self, from: Data(contentsOf: Bundle.module.url(forResource: "photo-foods", withExtension: "json")!))
        let image = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let compact = CommandLine.arguments.contains("--compact")
        let start = Date()
        let result = try await VisionAnalyzer.shared.analyze(image, description: "", foods: foods, preferCompact: compact, diagnostics: trace) { stage in
            if !stage.hasPrefix("download:") { trace("STAGE: " + stage) }
        }
        let components = result.parts.map { ["id": $0.food.id, "grams": $0.grams, "low": $0.low, "high": $0.high] as [String: Any] }
        trace("RESULT COMPONENTS: " + result.parts.map { $0.food.id + "=" + String($0.grams) }.joined(separator: ", "))
        var report: [String: Any] = ["tested": true, "passed": false, "platform": "macOS Apple Silicon Metal", "fixture": "USDA 20241025-USDA-FNS-UNK-0017 (public domain)", "image_sha256": "8c6f9cd2cdc344817c70091072a2c42f86c39ac83807040c184c137da1560b2d", "components": components, "limits": "Runtime fixture check only; not measured calorie accuracy, comparative benchmark, or physical-iPhone validation."]
        report["model_requested"] = compact ? "Qwen3-VL-2B" : "Qwen3-VL-4B"
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: destination)
        // The photograph proves broad visible dishes, not a particular shawarma
        // recipe or the identity of the white dip. Accept honestly marked unknown
        // recipes, but require all four major visible categories and reject the
        // original failure modes (fries, fruit or rice that are absent here).
        let names = result.parts.map { TextSearch.normalized($0.food.nameEn) }
        let hasWrap = result.parts.contains { PhotoMeal.family($0.food.id) == "wrap" } || names.contains { $0.contains("wrapped") || $0.contains("wrap") || ($0.contains("pita") && $0.contains("meat")) }
        let hasMeat = result.parts.contains { PhotoMeal.family($0.food.id) == "chicken" } || names.contains {
            // The visible meat need not be labelled with a specific cooking method.
            // Standalone breast slices are valid; fillings/toppings are not a separate meat item.
            !$0.contains("wrap") && !$0.contains("pita") && !$0.contains("sandwich") && !$0.contains("flatbread") &&
            ($0.contains("chicken strips") || $0.contains("chicken breast") || $0.contains("chicken slices") ||
             $0.contains("sliced chicken") || ($0.contains("grilled") && ($0.contains("chicken") || $0.contains("meat"))))
        }
        let hasDip = result.parts.contains { PhotoMeal.family($0.food.id) == "sauce" || VisionMeal.isDip($0.food.nameEn) }
        let hasBread = result.parts.contains { $0.food.id == "172816" }
        let inventedSide = result.parts.contains { ["169836", "169097", "169757", "169704"].contains($0.food.id) }
        report["categories"] = ["wrap": hasWrap, "standalone_meat": hasMeat, "standalone_dip": hasDip, "plain_pita": hasBread, "absent_side_invented": inventedSide]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: destination)
        guard result.parts.count >= 4, hasWrap, hasMeat, hasDip, hasBread, !inventedSide else {
            throw AppError.invalid("لم يتعرف النموذج على مكونات صورة الاختبار.", "The model did not recognize the mixed-food fixture components.")
        }
        let blank = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 512, height: 512))
        let png = CIContext().pngRepresentation(of: blank, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())!
        let empty = try await VisionAnalyzer.shared.analyze(png, description: "", foods: foods, allowDownloads: false, preferCompact: compact, diagnostics: trace) { stage in trace("CACHED STAGE: " + stage) }
        guard empty.parts.isEmpty else { throw AppError.invalid("اختلق النموذج طعامًا في صورة فارغة.", "The model invented food in an empty fixture.") }
        report["passed"] = true; report["cached_without_downloads"] = true; report["no_food_fixture_rejected"] = true
        report["elapsed_seconds"] = Date().timeIntervalSince(start)
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: destination)
        trace("Mixed-meal, cached inference and non-food runtime checks passed.")
    }
}
