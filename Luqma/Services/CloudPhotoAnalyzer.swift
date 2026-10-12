import Foundation

/// Normalizes orientation, downsizes and re-encodes into a new JPEG. EXIF,
/// location and other source metadata are never copied into the upload.
actor CloudPhotoAnalyzer {
    static let shared = CloudPhotoAnalyzer()
    private var running = false
    func analyze(_ data: Data, description: String, key: String,
                 progress: @escaping @Sendable (String) -> Void) async throws -> PhotoResult {
        guard !running else { throw AppError.invalid("انتظر انتهاء التحليل الحالي.", "Wait for the current analysis to finish.") }
        running = true
        defer { running = false }
        try Task.checkCancellation()
        progress("prepare-cloud")
        let jpeg = try CloudPhotoImage.jpeg(data)
        progress("cloud")
        let result = try await Self.client().analyze(jpeg: jpeg, description: description, key: key)
        progress("validate-cloud")
        return result
    }
    static func client() -> GeminiClient {
        GeminiClient { request in
            let config = URLSessionConfiguration.ephemeral
            config.urlCache = nil
            config.httpCookieStorage = nil
            config.urlCredentialStorage = nil
            config.httpShouldSetCookies = false
            config.timeoutIntervalForRequest = 90
            config.timeoutIntervalForResource = 120
            let session = URLSession(configuration: config, delegate: NoCloudRedirect(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            do {
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse, data.count <= GeminiMeal.maxResponseBytes else { throw GeminiMeal.invalid }
                return (data, http.statusCode)
            } catch let error as URLError {
                if error.code == .cancelled || Task.isCancelled { throw CancellationError() }
                // Never expose the raw request/response/underlying error: it can
                // contain keys, photo data or the factual meal description.
                throw AppError.invalid("تعذّر الاتصال بـ Gemini. تحقق من الإنترنت ثم أعد المحاولة أو اختر التحليل على الجهاز.",
                                       "Could not connect to Gemini. Check internet and retry or choose on-device analysis.")
            }
        }
    }
}

private final class NoCloudRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // The endpoint is fixed. Never forward the user's key to a redirect.
        completionHandler(nil)
    }
}
