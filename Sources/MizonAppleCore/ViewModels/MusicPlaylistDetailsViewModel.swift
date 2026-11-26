import Foundation
import MizonAPIClient
import Observation

@Observable @MainActor
public final class MusicPlaylistDetailsViewModel {
    public static let pageSize = 20

    public private(set) var details: MusicPlaylistDetailsResponse?
    public private(set) var artworkID: UUID?
    public private(set) var page = 0
    public private(set) var isLoading = false
    public private(set) var hasError = false
    private var cursors: [String?] = [nil]

    private let playlistID: UUID
    private let service: MusicHomeService
    private let session: AuthSession
    @ObservationIgnored private var loadID: UUID?

    public init(playlistID: UUID, service: MusicHomeService, session: AuthSession) {
        self.playlistID = playlistID
        self.service = service
        self.session = session
    }

    public var canPlay: Bool { !isLoading && !hasError && (details?.musicsCount ?? 0) > 0 }
    public var canGoBack: Bool { !isLoading && page > 0 }
    public var canGoForward: Bool { !isLoading && !hasError && cursors.indices.contains(page + 1) }

    public func rank(at index: Int) -> Int { page * Self.pageSize + index + 1 }

    public func load(page requestedPage: Int) async -> Bool? {
        guard cursors.indices.contains(requestedPage), !Task.isCancelled else { return nil }
        let cursor = cursors[requestedPage]
        let id = UUID()
        loadID = id
        isLoading = true
        hasError = false
        defer {
            if loadID == id {
                loadID = nil
                isLoading = false
            }
        }
        do {
            let response = try await service.playlist(playlistID, after: cursor, pageSize: Self.pageSize, session: session)
            try Task.checkCancellation()
            guard loadID == id else { return nil }
            guard response.publicId == playlistID else { throw LoginFailure.invalidResponse }
            details = response
            page = requestedPage
            if requestedPage == 0 { artworkID = response.musics.first?.coverMediaPublicId }
            cursors = Array(cursors.prefix(requestedPage + 1))
            if let nextCursor = response.nextCursor, !cursors.contains(nextCursor) {
                cursors.append(nextCursor)
            }
            return true
        } catch {
            guard loadID == id, !Task.isCancelled, !(error is CancellationError) else { return nil }
            hasError = true
            return false
        }
    }
}
