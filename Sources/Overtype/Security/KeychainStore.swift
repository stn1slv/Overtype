import Foundation
import Security

public enum KeychainError: Error, LocalizedError {
  case unhandledError(status: OSStatus)
  case itemNotFound

  // Renders the OSStatus (finding C4): the default bridging produced the
  // opaque "KeychainError error 0.", which left credential failures
  // undiagnosable in Settings and in the logs. Only the status and the
  // system's message text appear here, never a credential value.
  public var errorDescription: String? {
    switch self {
    case .itemNotFound:
      return "No stored value was found in the Keychain for this key."
    case .unhandledError(let status):
      let systemMessage = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
      return "Keychain operation failed: \(systemMessage) (status \(status))."
    }
  }
}

public protocol KeychainStoring {
  func store(key: String, value: String) throws
  func retrieve(key: String) throws -> String
  func delete(key: String) throws
}

public class KeychainStore: KeychainStoring {
  public static let shared = KeychainStore()

  public init() {}

  public func store(key: String, value: String) throws {
    guard let valueData = value.data(using: .utf8) else {
      throw KeychainError.unhandledError(status: errSecParam)
    }

    // Item identity deliberately stays account-only (no kSecAttrService):
    // adding a service attribute would change the identity of every credential
    // existing users already stored and silently orphan them (finding C4).
    let searchQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key,
    ]

    // Update-in-place instead of delete-then-add (finding C4): the old flow
    // deleted first and discarded the delete's status, so a failed add (locked
    // keychain, denied prompt) destroyed the previously working credential,
    // and a failed delete surfaced later as an inexplicable duplicate-item
    // error. The previous value is never removed ahead of a durable write.
    let updateAttributes: [String: Any] = [kSecValueData as String: valueData]
    let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateAttributes as CFDictionary)

    switch updateStatus {
    case errSecSuccess:
      return
    case errSecItemNotFound:
      var addQuery = searchQuery
      addQuery[kSecValueData as String] = valueData
      let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw KeychainError.unhandledError(status: addStatus)
      }
    default:
      throw KeychainError.unhandledError(status: updateStatus)
    }
  }

  public func retrieve(key: String) throws -> String {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var dataTypeRef: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)

    if status == errSecItemNotFound {
      throw KeychainError.itemNotFound
    } else if status != errSecSuccess {
      throw KeychainError.unhandledError(status: status)
    }

    guard let data = dataTypeRef as? Data,
      let result = String(data: data, encoding: .utf8)
    else {
      throw KeychainError.unhandledError(status: errSecDecode)
    }

    return result
  }

  public func delete(key: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key,
    ]

    let status = SecItemDelete(query as CFDictionary)
    if status != errSecSuccess && status != errSecItemNotFound {
      throw KeychainError.unhandledError(status: status)
    }
  }
}
