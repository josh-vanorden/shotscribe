import Foundation
import Security

/// Where a secret lives. The Keychain in the app; memory in tests, so a test
/// never writes into the operator's login keychain.
public protocol SecretStore: Sendable {
    func get(_ account: String) -> String?
    func set(_ value: String?, for account: String)
}

public enum Secrets {
    public static var store: SecretStore = KeychainStore()
    /// The one secret ShotScribe keeps: the API key for the endpoint titler.
    public static let endpointKeyAccount = "endpoint-api-key"
}

/// Generic-password items under ShotScribe's own service name.
public struct KeychainStore: SecretStore {
    public let service: String
    public init(service: String = ShotScribeDefaults.appBundleID) { self.service = service }

    public func get(_ account: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public func set(_ value: String?, for account: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        SecItemAdd(add as CFDictionary, nil)
    }
}

public final class MemoryStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    public init() {}
    public func get(_ account: String) -> String? { lock.lock(); defer { lock.unlock() }; return values[account] }
    public func set(_ value: String?, for account: String) {
        lock.lock(); defer { lock.unlock() }
        if let value, !value.isEmpty { values[account] = value } else { values[account] = nil }
    }
}
