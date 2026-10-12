import Foundation
import ImageIO
import UniformTypeIdentifiers

private final class GeminiTransportDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Do not forward a personal API key to a redirect destination.
        completionHandler(nil)
    }
}

actor GeminiMealService {
    static let shared = GeminiMealService()
    static let modelID = GeminiMeal.modelID
    private let transport: URLSession
    private var analyzing = false

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 120
        transport = URLSession(configuration: configuration, delegate: GeminiTransportDelegate(), delegateQueue: nil)
    }

    /// Call only after the user agrees to send this photo and description to Google.
    func analyze(imageData: Data, context: String, language: AppLanguage) async throws -> PhotoResult {
        guard !analyzing else { throw AppError.invalid("انتظر انتهاء التحليل الحالي.", "Wait for the current analysis.") }
        analyzing = true
        defer { analyzing = false }
        try Task.checkCancellation()
        guard let key = try GeminiCredentialStore.load() else {
            throw AppError.invalid("أضف مفتاح Gemini من إعدادات تحليل الوجبات أولًا.", "Add your Gemini key in meal analysis settings first.")
        }
        let jpeg = try Self.preparedJPEG(imageData)
        let request = try GeminiMeal.request(imageData: jpeg, context: context, language: language, key: key)
        try Task.checkCancellation()
        do {
            let (bytes, response) = try await transport.bytes(for: request)
            defer { bytes.task.cancel() }
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else {
                throw AppError.invalid("تعذّر الاتصال بخدمة Gemini.", "The Gemini service could not be reached.")
            }
            guard http.statusCode == 200 else { throw GeminiMeal.httpError(http.statusCode) }
            if let length = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init), length > GeminiMeal.maximumResponseBytes {
                throw AppError.invalid("نتيجة Gemini أكبر من المتوقع. حاول مجددًا.", "The Gemini response was larger than expected. Retry.")
            }
            return try await withTaskCancellationHandler {
                var data = Data()
                data.reserveCapacity(32 * 1024)
                for try await byte in bytes {
                    if data.count % 1024 == 0 { try Task.checkCancellation() }
                    guard data.count < GeminiMeal.maximumResponseBytes else {
                        throw AppError.invalid("نتيجة Gemini أكبر من المتوقع. حاول مجددًا.", "The Gemini response was larger than expected. Retry.")
                    }
                    data.append(byte)
                }
                try Task.checkCancellation()
                return try GeminiMeal.parseResponse(data, status: http.statusCode)
            } onCancel: {
                bytes.task.cancel()
            }
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if let appError = error as? AppError { throw appError }
            if (error as? URLError)?.code == .timedOut {
                throw AppError.invalid("استغرق Gemini وقتًا طويلًا. تحقق من الاتصال وحاول مجددًا.", "Gemini took too long. Check your connection and retry.")
            }
            throw AppError.invalid("تعذّر الاتصال بخدمة Gemini. تحقق من الإنترنت وحاول مجددًا.", "Gemini could not be reached. Check your internet connection and retry.")
        }
    }

    private static func preparedJPEG(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= 40 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary) else { throw imageError }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil) else { throw imageError }
        // Encode the rendered pixels only. Original EXIF, location, and filename
        // metadata are not copied into the request sent to Google.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination), encoded.length <= GeminiMeal.maximumImageBytes else { throw imageError }
        return encoded as Data
    }

    private static var imageError: AppError {
        .invalid("تعذّر تجهيز الصورة. اختر صورة JPEG أو PNG أو HEIC أصغر.", "The image could not be prepared. Choose a smaller JPEG, PNG, or HEIC image.")
    }
}
