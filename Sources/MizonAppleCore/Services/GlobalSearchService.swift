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
    public init() {}

    public func search(_ query: String, session: AuthSession,
                       onResult: @MainActor (GlobalSearchResult) -> Void) async throws {
        let api = MizonApi()
        try await api.setToken(session.accessToken)
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
}
