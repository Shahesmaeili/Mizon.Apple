import CoreGraphics
import Foundation
import MizonAPI
import MizonAPIClient

public struct NearbyProfileArtworkService: Sendable {
    private let api: MizonApi
    private let service: MusicHomeService

    public init(api: MizonApi) {
        self.api = api
        service = MusicHomeService(api: api)
    }

    public static func normalizedUsername(_ username: String?) -> String? {
        guard let username, username.utf16.count <= 128 else { return nil }
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping.lowercased()
        guard (3...32).contains(normalized.utf8.count), AuthIdentifierInput.isAllowed(normalized, allowsEmail: false) else { return nil }
        return normalized
    }

    public func image(for account: String?, session: AuthSession, artwork: MusicArtworkStore) async throws -> CGImage? {
        guard let username = Self.normalizedUsername(account) else { return nil }
        let configuration = try BackendConfiguration(address: session.server.absoluteString)
        let endpoints = Endpoints(baseURL: configuration.baseURL)

        try await checkSession(session)
        guard let clientID = try await service.searchService.exactClientID(forNormalizedUsername: username, endpoints: endpoints) else { return nil }
        try await checkSession(session)
        let profile = try await service.client(clientID, session: session)
        guard profile.clientPublicId == clientID, Self.normalizedUsername(profile.username) == username,
              let mediaID = profile.profileMediaPublicId, mediaID != UUID.emptyPublicIdentifier else { return nil }
        try await checkSession(session)
        let image = try await artwork.profileImage(mediaID, session: session)
        try await checkSession(session)
        return image
    }

    private func checkSession(_ session: AuthSession) async throws {
        try Task.checkCancellation()
        // This lookup uses the already authenticated API and cannot restore credentials after sign-out.
        guard !session.accessToken.isEmpty, await api.getToken() == session.accessToken else { throw CancellationError() }
    }
}

extension UUID {
    static let emptyPublicIdentifier = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}
