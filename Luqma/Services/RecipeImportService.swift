import Foundation
import Darwin
import CryptoKit

private final class RecipeImportTransportDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private final class RecipeDNSCompletion: @unchecked Sendable {
    private let lock=NSLock()
    private var result:Bool?
    private var continuation:CheckedContinuation<Bool,Never>?
    func install(_ value:CheckedContinuation<Bool,Never>) {
        lock.lock()
        if let result {lock.unlock();value.resume(returning:result)}
        else {continuation=value;lock.unlock()}
    }
    func finish(_ value:Bool) {
        lock.lock()
        guard result == nil else {lock.unlock();return}
        result=value;let pending=continuation;continuation=nil;lock.unlock()
        pending?.resume(returning:value)
    }
}

actor RecipeImportService {
    static let shared = RecipeImportService()
    private let transport: URLSession
    private let sourceTransport: URLSession
    private var importing = false
    private struct CachedDraft { let draft: RecipeImportDraft; let storedAt: Date }
    private var cache: [String: CachedDraft] = [:]

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil; configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = AnalysisAttemptPolicy.recipeTimeout
        configuration.timeoutIntervalForResource = 45
        transport = URLSession(configuration: configuration, delegate: RecipeImportTransportDelegate(), delegateQueue: nil)
        let source = URLSessionConfiguration.ephemeral
        source.urlCache = nil; source.httpCookieStorage = nil; source.httpShouldSetCookies = false
        source.timeoutIntervalForRequest = 8; source.timeoutIntervalForResource = 10
        sourceTransport = URLSession(configuration: source, delegate: RecipeImportTransportDelegate(), delegateQueue: nil)
    }

    /// Explicit user action submits only the public URL or pasted recipe text.
    /// This returns a draft; callers must review it before saving a Recipe.
    func extract(url: String, pastedText: String = "", language: AppLanguage,
                 onStage: @escaping @Sendable (RecipeImportStage) -> Void = { _ in }) async throws -> RecipeImportDraft {
        var input = try RecipeImport.input(url: url, pastedText: pastedText)
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
        // Short-lived, bounded memory cache only. A repeated import reuses the
        // already reviewed source calculation without another network request.
        let identityText = key + "|" + language.rawValue + "|" + (input.sourceURL?.absoluteString ?? "") + "|" + input.pastedText
        let identity = SHA256.hash(data: Data(identityText.utf8)).map { String(format: "%02x", $0) }.joined()
        if let saved = cache[identity], Date().timeIntervalSince(saved.storedAt) < 300 {
            var draft = saved.draft
            for index in draft.ingredients.indices { draft.ingredients[index].id = UUID() }
            return draft
        }
        if input.sourceKind != .pastedText, input.sourceKind != .youtube, let source = input.sourceURL {
            onStage(.readingSource)
            do {
                let (content, finalURL) = try await capturedContent(source)
                if let content {
                    input = try input.withCapturedSource(content, finalURL: finalURL)
                } else {
                    // Resolved public share links are a better tool reference
                    // than the short redirect URL; keep exact-source checks.
                    input = RecipeImport.Input(sourceURL: finalURL, pastedText: "",
                        sourceKind: RecipeImport.isYouTube(finalURL) ? .youtube : .website)
                }
            } catch is CancellationError { throw CancellationError() }
            catch SourceReadError.unsafe { throw AppError.invalid("الرابط لا يشير إلى مصدر عام آمن. استخدم رابط المنشور العام أو الصق الوصفة.", "This link does not point to a safe public source. Use the public post link or paste the recipe.") }
            catch { /* One bounded provider retrieval may read a public page that rejects a direct mobile fetch. */ }
        }
        try Task.checkCancellation()
        onStage(.calculating)
        do {
            for (attempt, model) in AnalysisModel.allCases.enumerated() {
                try Task.checkCancellation()
                do {
                    let request = try RecipeImport.request(input, language: language, key: key, model: model)
                    let draft = try await generate(request, input: input, language: language, attempt: attempt)
                    if cache.count >= 4, let oldest = cache.min(by: { $0.value.storedAt < $1.value.storedAt })?.key { cache.removeValue(forKey: oldest) }
                    cache[identity] = CachedDraft(draft: draft, storedAt: Date())
                    return draft
                } catch ProviderBeforeResponse.retryable {
                    guard attempt == 0 else { throw GeminiMeal.httpError(503) }
                }
            }
            throw GeminiMeal.httpError(503)
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if let error = error as? AppError { throw error }
            throw AppError.invalid("تعذّر الاتصال لقراءة الوصفة. حاول مجددًا أو الصق نص المقادير والخطوات.", "The recipe could not be read. Retry or paste the ingredients and steps.")
        }
    }

    private enum ProviderBeforeResponse: Error { case retryable }
    private func generate(_ request: URLRequest, input: RecipeImport.Input, language: AppLanguage, attempt: Int) async throws -> RecipeImportDraft {
        let result: (URLSession.AsyncBytes, URLResponse)
        do { result = try await transport.bytes(for: request) }
        catch {
            if AnalysisAttemptPolicy.shouldFallback(error: error, attempt: attempt) { throw ProviderBeforeResponse.retryable }
            throw error
        }
        let (bytes, response) = result
        defer { bytes.task.cancel() }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw RecipeImport.invalidResult }
        if AnalysisAttemptPolicy.shouldFallback(status: http.statusCode, attempt: attempt) { throw ProviderBeforeResponse.retryable }
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
            // Invalid JSON, denied source, partial stream and implausible
            // nutrients never trigger another request or a guessed recipe.
            return try RecipeImport.parseResponse(data, input: input, language: language, status: http.statusCode)
        } onCancel: { bytes.task.cancel() }
    }

    private enum SourceReadError: Error { case unsafe, unavailable }

    private func capturedContent(_ source: URL) async throws -> (RecipeSourceContent?, URL) {
        let deadline = Date().addingTimeInterval(8)
        if let embed = RecipeSource.tikTokEmbedURL(source),
           let page = try? await readPublicPage(embed, deadline: deadline),
           let content = RecipeSource.content(page.data, mimeType: page.mimeType, socialCaption: true) {
            try Task.checkCancellation()
            return (content, source)
        }
        try Task.checkCancellation()
        let page = try await readPublicPage(source, deadline: deadline)
        let social = RecipeSource.isTikTok(page.url) || RecipeSource.isInstagram(page.url)
        if let content = RecipeSource.content(page.data, mimeType: page.mimeType, socialCaption: social) { return (content, page.url) }
        if let embed = RecipeSource.tikTokEmbedURL(page.url), source != page.url,
           let result = try? await readPublicPage(embed, deadline: deadline),
           let content = RecipeSource.content(result.data, mimeType: result.mimeType, socialCaption: true) {
            try Task.checkCancellation()
            return (content, page.url)
        }
        return (nil, page.url)
    }

    private struct SourcePage { let data: Data; let mimeType: String?; let url: URL }
    private func readPublicPage(_ original: URL, deadline: Date) async throws -> SourcePage {
        var url = original
        var visited = Set<URL>()
        for _ in 0...3 {
            try Task.checkCancellation()
            guard deadline.timeIntervalSinceNow > 0, visited.insert(url).inserted else { throw SourceReadError.unavailable }
            // oEmbed's outer fixed URL has a nested source parameter by design.
            // The source was canonicalized before constructing this endpoint.
            guard (try? RecipeImport.canonicalURL(url.absoluteString)) != nil else { throw SourceReadError.unsafe }
            let host = url.host ?? ""
            let publicHost = await Self.publicHost(host,timeout:min(2,max(0.1,deadline.timeIntervalSinceNow)))
            try Task.checkCancellation()
            guard publicHost else { throw SourceReadError.unsafe }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData,
                                     timeoutInterval: max(0.5, min(6, deadline.timeIntervalSinceNow)))
            request.setValue("text/html,application/ld+json,application/json,text/plain;q=0.9", forHTTPHeaderField: "Accept")
            request.setValue("Luqma/1.9 (public recipe import)", forHTTPHeaderField: "User-Agent")
            // No API key, cookie, authorization or account credential is ever
            // attached to arbitrary source URLs or followed redirects.
            let (bytes, response) = try await sourceTransport.bytes(for: request)
            defer { bytes.task.cancel() }
            guard let http = response as? HTTPURLResponse else { throw SourceReadError.unavailable }
            if [301, 302, 303, 307, 308].contains(http.statusCode) {
                guard let location = http.value(forHTTPHeaderField: "Location"),
                      let destination = URL(string: location, relativeTo: url)?.absoluteURL,
                      let canonical = try? RecipeImport.canonicalURL(destination.absoluteString) else { throw SourceReadError.unsafe }
                url = canonical
                continue
            }
            guard http.statusCode == 200 else { throw SourceReadError.unavailable }
            if let count = http.value(forHTTPHeaderField: "Content-Length").flatMap(Int.init), count > RecipeSource.maximumPageBytes {
                throw SourceReadError.unavailable
            }
            var data = Data(); data.reserveCapacity(32 * 1024)
            let finalURL = url
            return try await withTaskCancellationHandler {
                for try await byte in bytes {
                    if data.count % 1024 == 0 {
                        try Task.checkCancellation()
                        guard deadline.timeIntervalSinceNow > 0 else { throw SourceReadError.unavailable }
                    }
                    guard data.count < RecipeSource.maximumPageBytes else { throw SourceReadError.unavailable }
                    data.append(byte)
                }
                try Task.checkCancellation()
                return SourcePage(data: data, mimeType: http.mimeType, url: finalURL)
            } onCancel: { bytes.task.cancel() }
        }
        throw SourceReadError.unavailable
    }

    nonisolated private static func publicHost(_ host:String,timeout:TimeInterval) async -> Bool {
        let completion=RecipeDNSCompletion()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                completion.install(continuation)
                DispatchQueue.global(qos:.utility).async {completion.finish(resolvesPublicly(host))}
                DispatchQueue.global(qos:.utility).asyncAfter(deadline:.now()+timeout) {completion.finish(false)}
            }
        } onCancel: {completion.finish(false)}
    }

    nonisolated private static func resolvesPublicly(_ host: String) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        var list: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, "443", &hints, &list) == 0, let first = list else { return false }
        defer { freeaddrinfo(first) }
        var current: UnsafeMutablePointer<addrinfo>? = first
        var found = false
        while let entry = current {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard let address = entry.pointee.ai_addr,
                  getnameinfo(address, entry.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0,
                  RecipeSource.isPublicAddress(String(cString: buffer)) else { return false }
            found = true
            current = entry.pointee.ai_next
        }
        return found
    }
}
