import Foundation
import Security

public protocol SessionStore: Sendable {
    func save(_ session: AuthSession) async throws
    func remove(server: URL) async throws
}

/// Credentials stay in this device's Keychain; passwords are never persisted.
public actor KeychainSessionStore: SessionStore {
    private let service: String
    public init(service: String = "com.shahesmaeili.Mizon.Apple.session") { self.service = service }
    private func query(server: URL) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: server.absoluteString]
    }
    public func save(_ session: AuthSession) throws {
        let data = try JSONEncoder().encode(session)
        let identity = query(server: session.server)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(identity as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = identity
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(item as CFDictionary, nil)
            guard added == errSecSuccess else { throw LoginFailure.storage(added) }
        } else if status != errSecSuccess { throw LoginFailure.storage(status) }
    }
    public func remove(server: URL) throws {
        let status = SecItemDelete(query(server: server) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw LoginFailure.storage(status) }
    }
}
