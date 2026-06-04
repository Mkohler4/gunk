import Foundation
import Security

protocol SecretStore {
  func secret(for account: String) throws -> String?
  func setSecret(_ secret: String?, for account: String) throws
}

enum SecretStoreError: Error, Equatable {
  case unexpectedStatus(OSStatus)
  case invalidData
}

final class KeychainStore: SecretStore {
  private let service: String

  init(service: String = "app.gunk.llm") {
    self.service = service
  }

  func secret(for account: String) throws -> String? {
    var query = baseQuery(account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    if status == errSecItemNotFound {
      return nil
    }

    guard status == errSecSuccess else {
      throw SecretStoreError.unexpectedStatus(status)
    }

    guard let data = result as? Data,
          let secret = String(data: data, encoding: .utf8) else {
      throw SecretStoreError.invalidData
    }

    return secret
  }

  func setSecret(_ secret: String?, for account: String) throws {
    guard let secret, !secret.isEmpty else {
      let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
      if status != errSecSuccess && status != errSecItemNotFound {
        throw SecretStoreError.unexpectedStatus(status)
      }
      return
    }

    let data = Data(secret.utf8)
    var query = baseQuery(account: account)
    let attributes = [kSecValueData as String: data]

    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecSuccess {
      return
    }

    guard updateStatus == errSecItemNotFound else {
      throw SecretStoreError.unexpectedStatus(updateStatus)
    }

    query[kSecValueData as String] = data
    let addStatus = SecItemAdd(query as CFDictionary, nil)

    guard addStatus == errSecSuccess else {
      throw SecretStoreError.unexpectedStatus(addStatus)
    }
  }

  private func baseQuery(account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
  }
}

final class InMemorySecretStore: SecretStore {
  private var secrets: [String: String] = [:]

  func secret(for account: String) throws -> String? {
    secrets[account]
  }

  func setSecret(_ secret: String?, for account: String) throws {
    if let secret, !secret.isEmpty {
      secrets[account] = secret
    } else {
      secrets.removeValue(forKey: account)
    }
  }
}
