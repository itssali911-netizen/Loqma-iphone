import Foundation
import Security

/// A personal key is never included in diary exports, preferences, or logs.
enum GeminiCredentialStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "app.luqma.diary") + ".gemini",
         kSecAttrAccount as String: "personal-api-key",
         kSecAttrSynchronizable as String: false]
    }

    static var isConfigured: Bool { (try? load()) != nil }

    static func load() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, let key = String(data: data, encoding: .utf8) else { throw storageError }
        return try GeminiMeal.validatedKey(key)
    }

    static func save(_ input: String) throws {
        let key = try GeminiMeal.validatedKey(input)
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw storageError }
        let item = query.merging(attributes) { _, new in new }
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw storageError }
    }

    static func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw storageError }
    }

    private static var storageError: AppError {
        .invalid("تعذّر الوصول إلى مفتاح Gemini. افتح قفل الجهاز وأعد المحاولة.", "The Gemini key could not be accessed. Unlock the device and retry.")
    }
}
