import Foundation
import Security

public protocol SessionStore: Sendable {
    func load(server: URL) async throws -> AuthSession?
    func save(_ session: AuthSession) async throws
    func remove(server: URL) async throws
}

public extension SessionStore {
    func load(server: URL) async throws -> AuthSession? { nil }
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
    public func load(server: URL) throws -> AuthSession? {
        var lookup = query(server: server)
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var value: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &value)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw LoginFailure.storage(status) }
        guard let data = value as? Data,
              let session = try? JSONDecoder().decode(AuthSession.self, from: data),
              session.server == server, !session.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            // The item cannot be restored. Remove only this server's unusable entry.
            try remove(server: server)
            return nil
        }
        return session
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
