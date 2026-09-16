import CryptoKit
import Foundation
import Security
import ChupCore

enum KeyVault {
  static func databaseKey(existing: Bool, account: String = "database-key") throws -> Data {
    if let saved = try read(account: account) { return saved }
    guard !existing else {
      throw WorkspaceError.message(
        "The database key is missing from Keychain. Restore the key; the encrypted database was not replaced."
      )
    }
    let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    try write(key, account: account)
    return key
  }
  static func audioKey(existing: Bool = false, account: String = "audio-key") throws -> SymmetricKey
  {
    if let data = try read(account: account) { return SymmetricKey(data: data) }
    guard !existing else {
      throw WorkspaceError.message(
        "The audio encryption key is missing. Existing recordings were preserved; restore their recovery backup."
      )
    }
    let key = SymmetricKey(size: .bits256)
    try write(key.withUnsafeBytes { Data($0) }, account: account)
    return key
  }
  static func read(account: String) throws -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.chup.mac", kSecAttrAccount as String: account,
      kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else {
      throw WorkspaceError.message("Keychain access failed (\(status)).")
    }
    return result as? Data
  }
  static func write(_ data: Data, account: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.chup.mac", kSecAttrAccount as String: account,
    ]
    let attributes: [String: Any] = [kSecValueData as String: data]
    var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var insert = query
      insert[kSecValueData as String] = data
      insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      status = SecItemAdd(insert as CFDictionary, nil)
    }
    guard status == errSecSuccess else {
      throw WorkspaceError.message("Could not save to Keychain (\(status)).")
    }
  }
}
