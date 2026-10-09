import Foundation
import CoreImage
import ImageIO
import Metal
import CryptoKit
import MLX
import MLXLMCommon
import MLXVLM

/// Local generative vision. No image, description or diary data are sent to a server.
actor VisionAnalyzer {
    static let shared = VisionAnalyzer()
    static var supported: Bool { ProcessInfo.processInfo.physicalMemory >= 7_000_000_000 && MTLCreateSystemDefaultDevice() != nil }
    private var running = false
    private struct Manifest: Decodable {
        var id: String; var revision: String; var files: [File]
        struct File: Decodable { var name: String; var bytes: Int64; var sha256: String }
    }
    private func manifest() throws -> Manifest {
        guard let url = Bundle.main.url(forResource: "vision-model", withExtension: "json") else { throw VisionMeal.invalid }
        return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
    }
    func analyze(_ data: Data, description: String, foods: [PhotoFood], allowDownloads: Bool = true, diagnostics: @escaping @Sendable (String) -> Void = { _ in }, progress: @escaping @Sendable (String) -> Void) async throws -> PhotoResult {
        guard Self.supported else { throw AppError.invalid("التحليل المتقدم يحتاج جهازًا بذاكرة ٨ جيجابايت. استخدم التحليل الخفيف على هذا الجهاز.", "Advanced analysis requires a device with 8 GB RAM. Use lightweight analysis on this device.") }
        guard !running else { throw AppError.invalid("انتظر انتهاء التحليل الحالي.", "Wait for the current analysis to finish.") }
        running = true
        defer { running = false; Memory.clearCache() }
        let image = try Self.image(data)
        let spec = try manifest()
        let folder = try await download(spec, allowDownloads: allowDownloads, diagnostics: diagnostics, progress: progress)
        try Task.checkCancellation()
        progress("load")
        Memory.cacheLimit = 32 * 1024 * 1024
        // Local directory loading prevents tokenizer/model network requests after installation.
        let model = try await VLMModelFactory.shared.loadContainer(configuration: ModelConfiguration(directory: folder))
        try Task.checkCancellation()
        // Qwen's Instruct evaluation uses sampling (temperature 0.7 / top-p 0.8).
        // Greedy decoding looped on real fixtures. A modest repetition penalty
        // also prevents a repeated item from consuming the whole output budget.
        let pixels: CGFloat = ProcessInfo.processInfo.physicalMemory >= 11_000_000_000 ? 896 : 672
        let session = ChatSession(model, generateParameters: .init(maxTokens: 700, temperature: 0.7, topP: 0.8, repetitionPenalty: 1.08, repetitionContextSize: 128, prefillStepSize: 128), processing: .init(resize: CGSize(width: pixels, height: pixels)))
        progress("vision")
        do {
            // Observe first, without a menu or numeric example to copy. Ground the
            // subsequent nutrition task in the photograph, not a catalog listing.
            var observations = ""
            for try await chunk in session.streamResponse(to: VisionMeal.observationPrompt(description: description), image: .ciImage(image)) {
                try Task.checkCancellation()
                observations += chunk
                guard observations.utf8.count <= 20_000 else { throw VisionMeal.invalid }
            }
            await session.synchronize()
            diagnostics("IMAGE OBSERVATIONS: " + observations)
            try Task.checkCancellation()
            if observations.trimmingCharacters(in: .whitespacesAndNewlines) == "NO_FOOD" {
                return PhotoResult(parts: [], sauceSuggested: false, unmatched: false)
            }
            session.generateParameters.maxTokens = 2000
            let prompt = VisionMeal.prompt(description: description)
            var answer = "", tokens = 0
            for try await chunk in session.streamResponse(to: prompt) {
                try Task.checkCancellation()
                answer += chunk; tokens += 1
                if tokens % 40 == 0 { progress("vision") }
                guard answer.utf8.count <= 60_000 else { throw VisionMeal.invalid }
            }
            await session.synchronize()
            try Task.checkCancellation()
            progress("validate")
            diagnostics("FIRST OUTPUT: " + answer)
            let first = try? VisionMeal.decode(answer, description: description, foods: foods)
            if let first, first.parts.isEmpty { return first }
            progress("audit")
            var audit = ""
            let correction = first == nil ? "The prior JSON failed validation. Repair duplicates and malformed fields. ALL three weight fields must be NUMBERS, NEVER null. Estimate typical portion masses and use broad numeric bounds if scale is uncertain; exact measurement is not required. " : ""
            for try await chunk in session.streamResponse(to: correction + "Reinspect the original photograph and audit your JSON. Include ONLY observed dishes, not colors of plates. Remove invented sides and repeated foods. Aggregate identical dishes into ONE item with total weight. Include filled wraps as complete dishes, their separate sides and dip containers. Do not separately count ingredients inside a wrap. Return complete compact JSON only, with at most 8 distinct items. Every item MUST have name_en, grams, min_grams, max_grams and count. Retain nutrition_per_100g from the prior JSON for every item, correcting it if necessary; DO NOT drop that field, otherwise unmatched dishes cannot be calculated. No IDs. Preserve factual context and uncertainty.") {
                try Task.checkCancellation(); audit += chunk
                guard audit.utf8.count <= 60_000 else { throw VisionMeal.invalid }
            }
            await session.synchronize()
            try Task.checkCancellation()
            diagnostics("AUDIT OUTPUT: " + audit)
            return try VisionMeal.decode(audit, description: description, foods: foods)
        } catch {
            await session.synchronize()
            throw error
        }
    }
    private static func image(_ data: Data) throws -> CIImage {
        guard !data.isEmpty, data.count <= 40_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 1344] as CFDictionary) else {
            throw AppError.invalid("اختر صورة JPG أو PNG أو HEIC واضحة وأصغر من ٤٠ ميجابايت.", "Choose a clear JPG, PNG or HEIC photo smaller than 40 MB.")
        }
        return CIImage(cgImage: thumbnail)
    }
    private func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { try Task.checkCancellation(); hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private func download(_ spec: Manifest, allowDownloads: Bool, diagnostics: @escaping @Sendable (String) -> Void, progress: @escaping @Sendable (String) -> Void) async throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var folder = base.appendingPathComponent("VisionModels/" + spec.revision, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var attributes = URLResourceValues(); attributes.isExcludedFromBackup = true; try folder.setResourceValues(attributes)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 90; config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let total = spec.files.reduce(Int64(0)) { $0 + $1.bytes }
        var done: Int64 = 0
        for file in spec.files {
            diagnostics("MODEL FILE: " + file.name)
            try Task.checkCancellation()
            let final = folder.appendingPathComponent(file.name)
            let marker = folder.appendingPathComponent(file.name + ".verified")
            let size = (try? final.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            if size == file.bytes, (try? String(contentsOf: marker, encoding: .utf8)) == file.sha256 { done += file.bytes; continue }
            if size == file.bytes {
                progress("verify")
                if try digest(final) == file.sha256 { try file.sha256.write(to: marker, atomically: true, encoding: .utf8); done += file.bytes; continue }
            }
            guard allowDownloads else { throw AppError.invalid("النموذج غير مكتمل على الجهاز. نزّله أولًا للتمكن من التحليل دون إنترنت.", "The local model is incomplete. Download it first to analyze offline.") }
            try? FileManager.default.removeItem(at: final); try? FileManager.default.removeItem(at: marker)
            let partial = folder.appendingPathComponent(file.name + ".partial")
            var offset = (try? partial.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            if offset > file.bytes { try FileManager.default.removeItem(at: partial); offset = 0 }
            while offset < file.bytes {
                try Task.checkCancellation()
                let last = min(offset + 24 * 1024 * 1024 - 1, file.bytes - 1)
                guard let url = URL(string: "https://huggingface.co/\(spec.id)/resolve/\(spec.revision)/\(file.name)") else { throw VisionMeal.invalid }
                var request = URLRequest(url: url)
                request.setValue("bytes=\(offset)-\(last)", forHTTPHeaderField: "Range")
                let baseline = done + offset
                let observer = DownloadProgress { bytes in progress("download:\(min(100, Int(Double(baseline + bytes) / Double(total) * 100)))") }
                let (temporary, response) = try await session.download(for: request, delegate: observer)
                defer { try? FileManager.default.removeItem(at: temporary) }
                try Task.checkCancellation()
                guard let http = response as? HTTPURLResponse, [200, 206].contains(http.statusCode) else {
                    throw AppError.invalid("تعذّر تنزيل النموذج. أعد المحاولة؛ أجزاء التنزيل المكتملة محفوظة.", "Model download failed. Retry; completed download chunks are saved.")
                }
                let bytes = Int64(try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                diagnostics("HTTP \(http.statusCode): \(file.name), expected \(offset)-\(last)/\(file.bytes), got \(http.value(forHTTPHeaderField: "Content-Range") ?? "full file"), bytes \(bytes)")
                if http.statusCode == 200 {
                    guard bytes == file.bytes else { throw VisionMeal.invalid }
                    try? FileManager.default.removeItem(at: partial)
                    try FileManager.default.moveItem(at: temporary, to: partial); offset = file.bytes
                } else {
                    guard bytes == last - offset + 1, http.value(forHTTPHeaderField: "Content-Range") == "bytes \(offset)-\(last)/\(file.bytes)" else { throw VisionMeal.invalid }
                    if !FileManager.default.fileExists(atPath: partial.path) { _ = FileManager.default.createFile(atPath: partial.path, contents: nil) }
                    let writer = try FileHandle(forWritingTo: partial), reader = try FileHandle(forReadingFrom: temporary)
                    do {
                        try writer.seekToEnd()
                        while let chunk = try reader.read(upToCount: 1024 * 1024), !chunk.isEmpty { try writer.write(contentsOf: chunk) }
                        try writer.close(); try reader.close()
                    } catch { try? writer.close(); try? reader.close(); throw error }
                    offset += bytes
                }
                progress("download:\(Int(Double(done + offset) / Double(total) * 100))")
            }
            progress("verify")
            guard try digest(partial) == file.sha256 else {
                try? FileManager.default.removeItem(at: partial)
                throw AppError.invalid("لم ينجح التحقق من ملف النموذج. أعد المحاولة.", "Model integrity verification failed. Retry.")
            }
            try FileManager.default.moveItem(at: partial, to: final)
            try file.sha256.write(to: marker, atomically: true, encoding: .utf8)
            done += file.bytes
        }
        return folder
    }
}

private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let update: @Sendable (Int64) -> Void
    private var previousBytes: Int64 = 0
    init(update: @escaping @Sendable (Int64) -> Void) { self.update = update }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // The session's delegate queue is serial. Avoid flooding the main actor with updates.
        guard totalBytesWritten - previousBytes >= 1024 * 1024 else { return }
        previousBytes = totalBytesWritten; update(totalBytesWritten)
    }
}
