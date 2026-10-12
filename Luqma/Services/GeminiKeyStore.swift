import Foundation
import Security

/// User-supplied personal key, never compiled into the app, stored in the diary,
/// exported in a backup, synchronized through iCloud or printed in diagnostics.
enum GeminiKeyStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "app.luqma.diary") + ".gemini",
         kSecAttrAccount as String: "personal-api-key",
         kSecAttrSynchronizable as String: false]
    }
    static func read() throws -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else { throw failure }
        return key
    }
    static func save(_ raw: String) throws {
        let key = try GeminiMeal.checkedKey(raw)
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8),
                                       kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw failure }
        } else if status != errSecSuccess { throw failure }
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure }
    }
    private static var failure: AppError {
        .invalid("تعذّر الوصول إلى مفتاح Gemini المحفوظ. افتح قفل الجهاز وحاول مجددًا.",
                 "Could not access the saved Gemini key. Unlock your device and retry.")
    }
}
