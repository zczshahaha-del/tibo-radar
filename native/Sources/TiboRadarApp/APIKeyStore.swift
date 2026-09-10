import Foundation
import Security

protocol APIKeyStoring: Sendable {
  func read(for provider: AIProvider) throws -> String?
  func save(_ key: String, for provider: AIProvider) throws
  func delete(for provider: AIProvider) throws
}

enum APIKeyStoreError: LocalizedError {
  case keychain(OSStatus)
  case emptyKey

  var errorDescription: String? {
    switch self {
    case .emptyKey:
      "API Key 不能为空。"
    case .keychain(let status):
      if let message = SecCopyErrorMessageString(status, nil) as String? {
        "无法访问 macOS 钥匙串：\(message)"
      } else {
        "无法访问 macOS 钥匙串（\(status)）。"
      }
    }
  }
}

final class KeychainAPIKeyStore: APIKeyStoring, @unchecked Sendable {
  private let service: String

  init(service: String = "com.zc.tiboradar.api-keys") {
    self.service = service
  }

  func read(for provider: AIProvider) throws -> String? {
    var query = baseQuery(for: provider)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw APIKeyStoreError.keychain(status) }
    guard let data = result as? Data,
      let key = String(data: data, encoding: .utf8),
      !key.isEmpty
    else { return nil }
    return key
  }

  func save(_ key: String, for provider: AIProvider) throws {
    let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { throw APIKeyStoreError.emptyKey }
    let data = Data(cleaned.utf8)
    let query = baseQuery(for: provider)
    let update = [kSecValueData as String: data]
    let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
    if status == errSecItemNotFound {
      var insertion = query
      insertion[kSecValueData as String] = data
      insertion[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      let addStatus = SecItemAdd(insertion as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw APIKeyStoreError.keychain(addStatus)
      }
    } else if status != errSecSuccess {
      throw APIKeyStoreError.keychain(status)
    }
  }

  func delete(for provider: AIProvider) throws {
    let status = SecItemDelete(baseQuery(for: provider) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw APIKeyStoreError.keychain(status)
    }
  }

  private func baseQuery(for provider: AIProvider) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: provider.rawValue,
    ]
  }
}
