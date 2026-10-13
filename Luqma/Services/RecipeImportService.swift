import Foundation

private final class RecipeImportTransportDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

actor RecipeImportService {
    static let shared = RecipeImportService()
    private let transport: URLSession
    private var importing = false

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 120; configuration.timeoutIntervalForResource = 180
        transport = URLSession(configuration: configuration, delegate: RecipeImportTransportDelegate(), delegateQueue: nil)
    }

    /// Explicit user action submits only the public URL or pasted recipe text.
    /// This returns a draft; callers must review it before saving a Recipe.
    func extract(url: String, pastedText: String = "", language: AppLanguage) async throws -> RecipeImportDraft {
        let input = try RecipeImport.input(url: url, pastedText: pastedText)
        guard !importing else { throw AppError.invalid("انتظر انتهاء قراءة الوصفة الحالية.", "Wait for the current recipe import.") }
        importing = true; defer { importing = false }
        try Task.checkCancellation()
        let key: String
        do {
            guard let saved = try GeminiCredentialStore.load() else { throw RecipeImport.invalidResult }
            key = saved
        } catch {
            throw AppError.invalid("فعّل اتصال التحليل من الإعدادات ثم حاول مجددًا.", "Activate the analysis connection in Settings and retry.")
        }
        let request = try RecipeImport.request(input, language: language, key: key)
        do {
            let (bytes, response) = try await transport.bytes(for: request)
            defer { bytes.task.cancel() }
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw RecipeImport.invalidResult }
            guard http.statusCode == 200 else { throw GeminiMeal.httpError(http.statusCode) }
            if let size = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init), size > RecipeImport.maximumResponseBytes { throw RecipeImport.invalidResult }
            return try await withTaskCancellationHandler {
                var data = Data(); data.reserveCapacity(64 * 1024)
                for try await byte in bytes {
                    if data.count % 1024 == 0 { try Task.checkCancellation() }
                    guard data.count < RecipeImport.maximumResponseBytes else { throw RecipeImport.invalidResult }
                    data.append(byte)
                }
                try Task.checkCancellation()
                return try RecipeImport.parseResponse(data, input: input, language: language, status: http.statusCode)
            } onCancel: { bytes.task.cancel() }
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if let error = error as? AppError { throw error }
            throw AppError.invalid("تعذّر الاتصال لقراءة الوصفة. حاول مجددًا أو الصق نص المقادير والخطوات.", "The recipe could not be read. Retry or paste the ingredients and steps.")
        }
    }
}
