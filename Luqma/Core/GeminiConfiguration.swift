import Foundation

enum GeminiConfiguration {
    private struct Payload:Decodable {
        let format:String;let version:Int;let model:String;let apiKey:String
    }
    static func key(from data:Data) throws -> String {
        guard !data.isEmpty,data.count<=8192,
              let payload=try? JSONDecoder().decode(Payload.self,from:data),
              payload.format=="luqma-gemini-settings",payload.version==1,
              [GeminiMeal.modelID,AnalysisModel.backup.modelID,"gemini-3.8-flash"].contains(payload.model) else {
            throw AppError.invalid("اختر ملف إعداد Gemini الخاص بلقمة.","Choose the Luqma Gemini setup file.")
        }
        return try GeminiMeal.validatedKey(payload.apiKey)
    }
}
