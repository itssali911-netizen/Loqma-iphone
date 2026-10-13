import Foundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

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
    private struct CachedResult { let expiry: Date; let result: PhotoResult }
    private var recent: [String: CachedResult] = [:]

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = AnalysisAttemptPolicy.photoTimeout
        configuration.timeoutIntervalForResource = 30
        transport = URLSession(configuration: configuration, delegate: GeminiTransportDelegate(), delegateQueue: nil)
    }

    /// Call only after the user agrees to send this photo and description to Google.
    func analyze(imageData: Data, context: String, language: AppLanguage) async throws -> PhotoResult {
        guard !analyzing else { throw AppError.invalid("انتظر انتهاء التحليل الحالي.", "Wait for the current analysis.") }
        analyzing = true
        defer { analyzing = false }
        try Task.checkCancellation()
        let saved: String?
        do {
            saved = try GeminiCredentialStore.load()
        } catch {
            throw AppError.invalid("تعذّر الوصول إلى اتصال التحليل. افتح قفل الجهاز وراجع إعدادات تحليل الوجبات.", "The analysis connection could not be accessed. Unlock the device and check meal analysis settings.")
        }
        guard let key = saved else { throw AppError.invalid("فعّل تحليل الوجبات من الإعدادات أولًا.", "Enable meal analysis in Settings first.") }
        let jpeg = try Self.preparedJPEG(imageData)
        var identity = Data(SHA256.hash(data: jpeg))
        identity.append(Data(String(context.prefix(1000)).utf8))
        identity.append(Data(language.rawValue.utf8))
        identity.append(Data(SHA256.hash(data: Data(key.utf8))))
        let cacheKey = SHA256.hash(data: identity).map { String(format: "%02x", $0) }.joined()
        recent = recent.filter { $0.value.expiry > Date() }
        if let cached = recent[cacheKey] { return cached.result }
        try Task.checkCancellation()
        for (attempt, model) in AnalysisModel.allCases.enumerated() {
            var request = try GeminiMeal.request(imageData: jpeg, context: context, language: language, key: key, model: model)
            if attempt > 0 { request.timeoutInterval = AnalysisAttemptPolicy.backupTimeout }
            do {
                let result = try await recognize(request, attempt: attempt)
                if recent.count >= 4 { recent.removeAll() }
                recent[cacheKey] = CachedResult(expiry: Date().addingTimeInterval(180), result: result)
                return result
            } catch is TryBackup { try Task.checkCancellation(); continue }
            catch {
                if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
                if let appError = error as? AppError { throw appError }
                if (error as? URLError)?.code == .timedOut {
                    throw AppError.invalid("استغرق التحليل وقتًا أطول من المتوقع. حاول مجددًا.", "Analysis took longer than expected. Retry.")
                }
                throw AppError.invalid("تعذّر الاتصال بخدمة التحليل. تحقق من الإنترنت وحاول مجددًا.", "Meal analysis could not be reached. Check your internet connection and retry.")
            }
        }
        throw GeminiMeal.httpError(503)
    }

    private struct TryBackup: Error {}
    private func recognize(_ request: URLRequest, attempt: Int) async throws -> PhotoResult {
            let result: (URLSession.AsyncBytes, URLResponse)
            do { result = try await transport.bytes(for: request) }
            catch {
                if AnalysisAttemptPolicy.shouldFallback(error: error, attempt: attempt) { throw TryBackup() }
                throw error
            }
            let (bytes, response) = result
            defer { bytes.task.cancel() }
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else {
                throw AppError.invalid("تعذّر الاتصال بخدمة تحليل الوجبات.", "Meal analysis could not be reached.")
            }
            if AnalysisAttemptPolicy.shouldFallback(status: http.statusCode, attempt: attempt) { throw TryBackup() }
            guard http.statusCode == 200 else { throw GeminiMeal.httpError(http.statusCode) }
            if let length = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init), length > GeminiMeal.maximumResponseBytes {
                throw AppError.invalid("نتيجة التحليل أكبر من المتوقع. حاول مجددًا.", "The analysis result was larger than expected. Retry.")
            }
            return try await withTaskCancellationHandler {
                var data = Data()
                data.reserveCapacity(32 * 1024)
                for try await byte in bytes {
                    if data.count % 1024 == 0 { try Task.checkCancellation() }
                    guard data.count < GeminiMeal.maximumResponseBytes else {
                        throw AppError.invalid("نتيجة التحليل أكبر من المتوقع. حاول مجددًا.", "The analysis result was larger than expected. Retry.")
                    }
                    data.append(byte)
                }
                try Task.checkCancellation()
                return try GeminiMeal.parseResponse(data, status: http.statusCode)
            } onCancel: {
                bytes.task.cancel()
            }
    }

    private static func preparedJPEG(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= 40 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1280
              ] as CFDictionary) else { throw imageError }
        var samples=[UInt8](repeating:0,count:32*32)
        let detailed=samples.withUnsafeMutableBytes { buffer -> Bool in
            guard let context=CGContext(data:buffer.baseAddress,width:32,height:32,bitsPerComponent:8,bytesPerRow:32,
                                        space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(image,in:CGRect(x:0,y:0,width:32,height:32))
            return true
        }
        guard detailed,MealImageContent.hasVisibleDetail(samples) else {
            throw AppError.invalid("الصورة لا تحتوي تفاصيل كافية للتقدير. صوّر الوجبة كاملة بإضاءة واضحة.", "The image has too little detail for an estimate. Photograph the whole meal in clear light.")
        }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, UTType.jpeg.identifier as CFString, 1, nil) else { throw imageError }
        // Encode the rendered pixels only. Original EXIF, location, and filename
        // metadata are not copied into the request sent to Google.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.78] as CFDictionary)
        guard CGImageDestinationFinalize(destination), encoded.length <= GeminiMeal.maximumImageBytes else { throw imageError }
        return encoded as Data
    }

    private static var imageError: AppError {
        .invalid("تعذّر تجهيز الصورة. اختر صورة JPEG أو PNG أو HEIC أصغر.", "The image could not be prepared. Choose a smaller JPEG, PNG, or HEIC image.")
    }
}
