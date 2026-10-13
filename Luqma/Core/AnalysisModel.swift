import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Stable fast extraction with one bounded provider-outage fallback.
/// Names stay in implementation and never enter meal/recipe presentation.
enum AnalysisModel: CaseIterable {
    case fast, backup

    var modelID: String { self == .fast ? "gemini-3.1-flash-lite" : "gemini-3.5-flash-lite" }
    var endpoint: URL { URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(modelID):generateContent")! }

    func generationConfig(schema: [String: Any], maxOutputTokens: Int) -> [String: Any] {
        var result: [String: Any] = [
            "maxOutputTokens": maxOutputTokens,
            "thinkingConfig": ["thinkingLevel": "MINIMAL", "includeThoughts": false]
        ]
        if self == .fast {
            result["responseMimeType"] = "application/json"
            result["responseJsonSchema"] = schema
        } else {
            result["responseFormat"] = ["text": ["mimeType": "APPLICATION_JSON", "schema": schema]]
        }
        return result
    }
}

enum AnalysisAttemptPolicy {
    static let photoTimeout: TimeInterval = 22
    static let recipeTimeout: TimeInterval = 28
    static let videoTimeout: TimeInterval = 40
    static let backupTimeout: TimeInterval = 15
    static func shouldFallback(status: Int, attempt: Int) -> Bool {
        attempt == 0 && [404, 500, 502, 503, 504].contains(status)
    }
    static func shouldFallback(error: Error, attempt: Int) -> Bool {
        attempt == 0 && (error as? URLError)?.code == .timedOut && !Task.isCancelled
    }
}
