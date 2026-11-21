import Foundation
import MizonAPI
import MizonAPIClient

public struct GlobalSearchResult: Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case music = "Music"
        case client = "Client"
    }

    public let publicID: UUID
    public let kind: Kind
    public let title: String
    public let persianTitle: String?
    public var id: String { "\(kind.rawValue):\(publicID)" }
}

public struct GlobalSearchService: Sendable {
    private let api: MizonApi

    public init(api: MizonApi = MizonApi()) { self.api = api }

    public func search(_ query: String, session: AuthSession,
                       onResult: @MainActor (GlobalSearchResult) -> Void) async throws {
        if await api.getToken() != session.accessToken { try await api.setToken(session.accessToken) }
        let operation = GlobalSearchOperation(.init(query: query), endpoints: .init(baseURL: session.server))
        for try await item in await api.sendStreamRequest(operation) {
            try Task.checkCancellation()
            guard let kind = GlobalSearchResult.Kind(rawValue: item.itemType) else { continue }
            let name = [item.firstName, item.lastName].compactMap { $0 }.joined(separator: " ")
            let candidates = kind == .music ? [item.title, item.persianTitle] : [item.nickName, name, item.username]
            guard let title = candidates.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty }) else { continue }
            await onResult(.init(publicID: item.publicId, kind: kind, title: title, persianTitle: item.persianTitle))
        }
    }

    func exactClientID(forNormalizedUsername username: String, endpoints: Endpoints) async throws -> UUID? {
        var operation = GlobalSearchOperation(.init(query: username), endpoints: endpoints)
        operation.apiRequest.callTimeoutDuration = 4

        // The backend interleaves up to ten Client results and ten Music results.
        let results = await api.sendStreamRequest(operation)
        for try await item in results.prefix(20) {
            try Task.checkCancellation()
            guard item.itemType == GlobalSearchResult.Kind.client.rawValue,
                  NearbyProfileArtworkService.normalizedUsername(item.username) == username,
                  item.publicId != UUID.emptyPublicIdentifier else { continue }
            return item.publicId
        }
        try Task.checkCancellation()
        return nil
    }
}
