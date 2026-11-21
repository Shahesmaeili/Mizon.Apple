import CoreGraphics
import Foundation
import ImageIO
import MizonAPI
import MizonAPIClient

public struct MusicHomeService: Sendable {
    public enum Section: String, CaseIterable, Sendable {
        case features, artists, stories, genres, library, activity
    }

    public enum Content: Sendable {
        case features([MusicFeatureItemResponse])
        case artists([FeaturedPersonItem])
        case stories([StoryListItemResponse])
        case genres([MusicGenreTypeItemResponse])
        case library(MusicLibraryResponse)
        case activity(FollowingActivitiesResponse)
    }

    private let api: MizonApi

    public init(api: MizonApi = MizonApi()) { self.api = api }

    public var searchService: GlobalSearchService { GlobalSearchService(api: api) }

    public func load(_ section: Section, session: AuthSession) async throws -> Content {
        let endpoints = Endpoints(baseURL: session.server)
        switch section {
        case .features:
            return .features(try await request(MusicFeaturesOperation(.init(limit: 12), endpoints: endpoints)).items)
        case .artists:
            return .artists(try await request(FeaturedPersonsOperation(.init(typeCode: "music"), endpoints: endpoints)).persons)
        case .stories:
            return .stories(try await request(StoriesOperation(endpoints: endpoints)).stories)
        case .genres:
            return .genres(try await request(MusicGenreTypesOperation(.init(), endpoints: endpoints)).musicGenreTypes)
        case .library:
            return .library(try await library(after: nil, pageSize: 5, session: session))
        case .activity:
            return .activity(try await activity(after: nil, session: session))
        }
    }

    public func library(after cursor: String?, pageSize: Int, session: AuthSession) async throws -> MusicLibraryResponse {
        try await request(MusicLibraryOperation(.init(pageSize: pageSize, cursor: cursor),
                                               endpoints: .init(baseURL: session.server)))
    }

    public func activity(after cursor: String?, session: AuthSession) async throws -> FollowingActivitiesResponse {
        try await request(FollowingActivitiesOperation(.init(scope: "music", pageSize: 20, cursor: cursor),
                                                       endpoints: .init(baseURL: session.server)))
    }

    public func track(_ id: UUID, session: AuthSession) async throws -> MusicResponse {
        try await request(MusicOperation(.init(musicPublicId: id), endpoints: .init(baseURL: session.server)))
    }

    public func client(_ id: UUID, session: AuthSession) async throws -> ClientProfileResponse {
        try await request(ClientProfileOperation(.init(clientPublicId: id), endpoints: .init(baseURL: session.server)))
    }

    public func moodOptions(session: AuthSession) async throws -> [ClientMoodItemResponse] {
        try await request(ClientMoodTypesOperation(.init(), endpoints: .init(baseURL: session.server))).items
    }

    public func setMood(_ id: UUID?, session: AuthSession) async throws -> ClientMoodItemResponse? {
        try await request(ClientMoodOperation(.init(clientMoodTypePublicId: id), endpoints: .init(baseURL: session.server))).currentMood
    }

    public func artist(_ id: UUID, session: AuthSession) async throws -> PersonProfileResponse {
        try await request(PersonProfileOperation(.init(personPublicId: id), endpoints: .init(baseURL: session.server)))
    }

    public func artistMusic(_ id: UUID, after cursor: UUID?, session: AuthSession) async throws -> PersonMusicsResponse {
        try await request(PersonMusicsOperation(.init(personPublicId: id, beforeMusicPublicId: cursor),
                                                endpoints: .init(baseURL: session.server)))
    }

    public func playlist(_ id: UUID, after cursor: String?, session: AuthSession) async throws -> MusicPlaylistDetailsResponse {
        try await request(MusicPlaylistDetailsOperation(.init(musicPlaylistPublicId: id, cursor: cursor),
                                                       endpoints: .init(baseURL: session.server)))
    }

    public func story(_ id: UUID, session: AuthSession) async throws -> StoryResponse {
        try await request(StoryDetailsOperation(.init(storyPublicId: id), endpoints: .init(baseURL: session.server)))
    }

    public func markStoryViewed(_ id: UUID, session: AuthSession) async throws -> StoryResponse {
        try await request(StoryViewOperation(.init(storyPublicId: id), endpoints: .init(baseURL: session.server)))
    }

    public func likeStory(_ id: UUID, liked: Bool, session: AuthSession) async throws -> StoryResponse {
        try await request(StoryLikeOperation(.init(storyPublicId: id, liked: liked), endpoints: .init(baseURL: session.server)))
    }

    public func likeTrack(_ id: UUID, liked: Bool, session: AuthSession) async throws -> MusicLikeResponse {
        try await request(MusicLikeOperation(.init(musicPublicId: id, liked: liked), endpoints: .init(baseURL: session.server)))
    }

    public func followArtist(_ id: UUID, following: Bool, session: AuthSession) async throws -> PersonFollowResponse {
        try await request(PersonFollowOperation(.init(personPublicId: id, following: following), endpoints: .init(baseURL: session.server)))
    }

    public func recordPlayback(_ id: UUID, playbackID: UUID, session: AuthSession) async throws {
        _ = try await request(MusicPlayOperation(.init(musicPublicId: id, playbackPublicId: playbackID), endpoints: .init(baseURL: session.server)))
    }

    public func trackFile(_ id: UUID, session: AuthSession) async throws -> MusicFileResponse {
        try await request(MusicFileOperation(.init(musicPublicId: id), endpoints: .init(baseURL: session.server)))
    }

    public func media(_ id: UUID, session: AuthSession) async throws -> MediaResponse {
        try await request(MediaOperation(.init(mediaPublicId: id), endpoints: .init(baseURL: session.server)))
    }

    public static func storageURL(_ address: String) throws -> URL {
        guard let components = URLComponents(string: address), components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty, components.user == nil, components.password == nil,
              let url = components.url else { throw LoginFailure.invalidResponse }
        return url
    }

    private func request<Operation: APIOperation>(_ operation: Operation) async throws -> Operation.Response {
        try Task.checkCancellation()
        let response = await api.sendRequest(operation)
        try Task.checkCancellation()
        guard response.isSuccess, let content = response.content else { throw LoginFailure.invalidResponse }
        return content
    }
}

public actor MusicArtworkStore {
    private let downloader: MediaDownloader
    private let service: MusicHomeService
    private let cache = NSCache<NSUUID, CGImage>()
    private var requests: [UUID: Task<CGImage, Error>] = [:]

    public init(service: MusicHomeService, session: AuthSession) {
        self.service = service
        let directory = URL.cachesDirectory.appending(path: "Mizon/Music/\(session.clientPublicId)", directoryHint: .isDirectory)
        downloader = MediaDownloader(cacheRoot: directory)
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    public func image(_ id: UUID, session: AuthSession) async throws -> CGImage {
        let key = id as NSUUID
        if let image = cache.object(forKey: key) { return image }
        if let request = requests[id] { return try await request.value }
        let request = Task { [service, downloader] in
            let media = try await service.media(id, session: session)
            guard media.fileSize > 0, media.fileSize <= 24 * 1024 * 1024 else { throw LoginFailure.invalidResponse }
            let storage = try MusicHomeService.storageURL(media.storagePath)
            let path = try await downloader.downloadToCache(media, storageURL: storage)
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithURL(path as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 960
                  ] as CFDictionary) else { throw LoginFailure.invalidResponse }
            return image
        }
        requests[id] = request
        defer { requests[id] = nil }
        let image = try await request.value
        cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }

    public func file(_ id: UUID, session: AuthSession, maximumBytes: Int64) async throws -> URL {
        let media = try await service.media(id, session: session)
        guard media.fileSize > 0, media.fileSize <= maximumBytes else { throw LoginFailure.invalidResponse }
        let storage = try MusicHomeService.storageURL(media.storagePath)
        return try await downloader.downloadToCache(media, storageURL: storage)
    }

    public func cancel() {
        for request in requests.values { request.cancel() }
        requests.removeAll()
    }
}
