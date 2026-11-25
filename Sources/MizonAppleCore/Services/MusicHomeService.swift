import CoreGraphics
import Foundation
import ImageIO
import MizonAPI
import MizonAPIClient
import UniformTypeIdentifiers

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
    public var nearbyProfileArtworkService: NearbyProfileArtworkService { NearbyProfileArtworkService(api: api) }

    #if os(macOS)
    public func makeWindowPresenceSocket(session: AuthSession) -> MizonSocket {
        MizonSocket(mizonApi: api, hubURL: Endpoints(baseURL: session.server).mizonHubURL)
    }
    #endif

    public func nearbyMediaAccess(session: AuthSession) -> NearbyMediaAccess {
        NearbyMediaAccess(api: api, session: session)
    }

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
        try await followingActivity(scope: "music", after: cursor, session: session)
    }

    public func allFollowingActivity(after cursor: String?, session: AuthSession) async throws -> FollowingActivitiesResponse {
        try await followingActivity(scope: "all", after: cursor, session: session)
    }

    private func followingActivity(scope: String, after cursor: String?, session: AuthSession) async throws -> FollowingActivitiesResponse {
        try await request(FollowingActivitiesOperation(.init(scope: scope, pageSize: 20, cursor: cursor),
                                                       endpoints: .init(baseURL: session.server)))
    }

    public func track(_ id: UUID, session: AuthSession) async throws -> MusicResponse {
        try await request(MusicOperation(.init(musicPublicId: id), endpoints: .init(baseURL: session.server)))
    }

    public func trackComment(_ commentID: UUID, musicID: UUID, session: AuthSession) async throws -> MusicCommentItemResponse? {
        let request = MusicCommentsRequest(musicPublicId: musicID, musicCommentPublicId: commentID, pageSize: 1)
        let response = try await self.request(MusicCommentsOperation(request, endpoints: .init(baseURL: session.server)))
        return response.musicComments.first { $0.publicId == commentID }
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
        guard await api.getToken() == session.accessToken else { throw CancellationError() }
        _ = try await request(MusicPlayOperation(.init(musicPublicId: id, playbackPublicId: playbackID), endpoints: .init(baseURL: session.server)))
    }

    public func trackFile(_ id: UUID, session: AuthSession) async throws -> MusicFileResponse {
        try await request(MusicFileOperation(.init(musicPublicId: id), endpoints: .init(baseURL: session.server)))
    }

    public func media(_ id: UUID, session: AuthSession) async throws -> MediaResponse {
        try await request(MediaOperation(.init(mediaPublicId: id), endpoints: .init(baseURL: session.server)))
    }

    fileprivate func cacheMedia(_ info: MediaResponse, session: AuthSession, downloader: MediaDownloader,
                                maximumBytes: Int64, peerNetwork: NearbyDiscoveryService? = nil) async throws -> URL {
        guard info.fileSize > 0, info.fileSize <= maximumBytes else { throw LoginFailure.invalidResponse }
        if let peerNetwork,
           let manifest = try await peerManifest(info, session: session, downloader: downloader, network: peerNetwork) {
            return try await downloadVerified(info, manifest: manifest, session: session, downloader: downloader, network: peerNetwork)
        }
        return try await downloader.downloadToCache(info, api: api, endpoints: .init(baseURL: session.server))
    }

    fileprivate func peerManifest(_ info: MediaResponse, session: AuthSession, downloader: MediaDownloader,
                                  network: NearbyDiscoveryService) async throws -> VerifiedMediaManifest? {
        guard info.fileSize <= PeerMediaTransfer.maximumFileSize,
              await network.canFetchPeerMedia(sessionID: session.sessionPublicId),
              await api.getToken() == session.accessToken else { return nil }
        do {
            return try await downloader.peerManifest(for: info, api: api, endpoints: .init(baseURL: session.server))
        } catch {
            try Task.checkCancellation()
            // The authenticated origin download remains available when peer authorization is unavailable.
            return nil
        }
    }

    fileprivate func downloadVerified(_ info: MediaResponse, manifest: VerifiedMediaManifest, session: AuthSession,
                                      downloader: MediaDownloader, network: NearbyDiscoveryService) async throws -> URL {
        try Task.checkCancellation()
        guard manifest.matches(info), await api.getToken() == session.accessToken else { throw LoginFailure.invalidResponse }
        let endpoints = Endpoints(baseURL: session.server)
        let origin = PeerMediaChunkProvider { index in
            guard await api.getToken() == session.accessToken else { throw CancellationError() }
            return try await downloader.readOriginPiece(for: info, manifest: manifest, index: index, api: api, endpoints: endpoints)
        }
        let destination = try await downloader.getCachedFilePath(info)
        return try await network.downloadPeerMedia(manifest, mediaID: info.mediaPublicId, destination: destination,
                                                   sessionID: session.sessionPublicId, origin: origin)
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
    private struct ArtistModelRequest {
        let task: Task<URL, Error>
        var viewers: Set<UUID>
    }

    private final class CachedArtwork: Sendable {
        let contents: (image: CGImage, source: URL)

        init(image: CGImage, source: URL) {
            contents = (image, source)
        }
    }

    private let downloader: MediaDownloader
    private let service: MusicHomeService
    private let accountID: UUID
    private let server: URL
    private let peerNetwork: NearbyDiscoveryService?
    private let cache = NSCache<NSUUID, CachedArtwork>()
    private let profileThumbnails = NSCache<NSUUID, CGImage>()
    private var requests: [UUID: Task<CachedArtwork, Error>] = [:]
    private var artistModelRequests: [UUID: ArtistModelRequest] = [:]

    public init(service: MusicHomeService, session: AuthSession, cacheRoot: URL? = nil,
                peerNetwork: NearbyDiscoveryService? = nil) {
        self.service = service
        self.peerNetwork = peerNetwork
        accountID = session.clientPublicId
        server = session.server
        let directory = cacheRoot ?? Self.cacheDirectory(for: session)
        downloader = MediaDownloader(cacheRoot: directory)
        cache.totalCostLimit = 32 * 1024 * 1024
        profileThumbnails.totalCostLimit = 2 * 1024 * 1024
    }

    static func cacheDirectory(for session: AuthSession) -> URL {
        URL.cachesDirectory.appending(path: "Mizon/Music/\(session.clientPublicId)", directoryHint: .isDirectory)
    }

    public func moodAnimationURL(_ id: UUID, session: AuthSession) async throws -> URL {
        let source = try await file(id, session: session, maximumBytes: Int64(MoodAnimationAsset.maximumBytes))
        return try await MoodAnimationAsset.jsonFile(for: source)
    }

    public func image(_ id: UUID, session: AuthSession) async throws -> CGImage {
        try await imageWithSource(id, session: session).image
    }

    public func imageWithSource(_ id: UUID, session: AuthSession) async throws -> (image: CGImage, source: URL) {
        try Task.checkCancellation()
        guard session.clientPublicId == accountID, session.server == server else { throw CancellationError() }
        let key = id as NSUUID
        if let artwork = cache.object(forKey: key) { return artwork.contents }
        if let request = requests[id] { return try await request.value.contents }
        let request = Task { [service, downloader] in
            let media = try await service.media(id, session: session)
            let path = try await service.cacheMedia(media, session: session, downloader: downloader,
                                                   maximumBytes: 24 * 1024 * 1024)
            try Task.checkCancellation()
            guard let source = CGImageSourceCreateWithURL(path as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 960,
                    kCGImageSourceShouldCacheImmediately: true
                  ] as CFDictionary) else { throw LoginFailure.invalidResponse }
            return CachedArtwork(image: image, source: path)
        }
        requests[id] = request
        defer { requests[id] = nil }
        let artwork = try await request.value
        let image = artwork.contents.image
        cache.setObject(artwork, forKey: key, cost: image.bytesPerRow * image.height)
        return artwork.contents
    }

    func profileImage(_ id: UUID, session: AuthSession) async throws -> CGImage {
        try Task.checkCancellation()
        guard session.clientPublicId == accountID, session.server == server else { throw CancellationError() }
        let key = id as NSUUID
        if let image = profileThumbnails.object(forKey: key) { return image }

        let media = try await service.media(id, session: session)
        guard media.mediaPublicId == id else { throw LoginFailure.invalidResponse }
        let path = try await service.cacheMedia(media, session: session, downloader: downloader, maximumBytes: 4 * 1024 * 1024)
        try Task.checkCancellation()

        guard let source = CGImageSourceCreateWithURL(path as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let contentType = CGImageSourceGetType(source) as String?, UTType(contentType)?.conforms(to: .image) == true,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 128,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw LoginFailure.invalidResponse }

        try Task.checkCancellation()
        profileThumbnails.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }

    public func file(_ id: UUID, session: AuthSession, maximumBytes: Int64) async throws -> URL {
        let media = try await service.media(id, session: session)
        return try await service.cacheMedia(media, session: session, downloader: downloader,
                                            maximumBytes: maximumBytes, peerNetwork: peerNetwork)
    }

    public func artistModelFile(_ id: UUID, session: AuthSession) async throws -> URL {
        try Task.checkCancellation()
        guard session.clientPublicId == accountID, session.server == server else { throw CancellationError() }
        while let request = artistModelRequests[id], request.task.isCancelled {
            _ = await request.task.result
            try Task.checkCancellation()
        }
        let viewer = UUID()
        let task: Task<URL, Error>
        if let request = artistModelRequests[id] {
            task = request.task
            artistModelRequests[id]?.viewers.insert(viewer)
        } else {
            task = Task {
                defer { artistModelRequests[id] = nil }
                let media = try await service.media(id, session: session)
                guard media.mediaPublicId == id else { throw LoginFailure.invalidResponse }
                return try await service.cacheMedia(media, session: session, downloader: downloader,
                                                    maximumBytes: 32 * 1024 * 1024, peerNetwork: peerNetwork)
            }
            artistModelRequests[id] = ArtistModelRequest(task: task, viewers: [viewer])
        }
        return try await withTaskCancellationHandler {
            let path = try await task.value
            try Task.checkCancellation()
            return path
        } onCancel: {
            Task { await self.cancelArtistModelViewer(viewer, mediaID: id) }
        }
    }

    private func cancelArtistModelViewer(_ viewer: UUID, mediaID: UUID) {
        guard artistModelRequests[mediaID]?.viewers.remove(viewer) != nil,
              let request = artistModelRequests[mediaID], request.viewers.isEmpty else { return }
        request.task.cancel()
    }

    public func playableURL(_ id: UUID, session: AuthSession) async throws -> URL {
        let media = try await service.media(id, session: session)
        if let peerNetwork,
           let manifest = try await service.peerManifest(media, session: session, downloader: downloader, network: peerNetwork) {
            return try await service.downloadVerified(media, manifest: manifest, session: session, downloader: downloader, network: peerNetwork)
        }
        if URL(string: media.storagePath)?.isFileURL == true {
            return try await service.cacheMedia(media, session: session, downloader: downloader,
                                                maximumBytes: PeerMediaTransfer.maximumFileSize)
        }
        return try MusicHomeService.storageURL(media.storagePath)
    }

    public func playableTrack(_ file: MusicFileResponse, session: AuthSession) async throws -> URL {
        let info = file.registeredMedia
        if info.fileSize > 0, (try? await downloader.isCached(info)) == true {
            return try await downloader.getCachedFilePath(info)
        }
        if let peerNetwork,
           let manifest = try await service.peerManifest(info, session: session, downloader: downloader, network: peerNetwork) {
            let media = try await service.media(file.mediaPublicId, session: session)
            return try await service.downloadVerified(media, manifest: manifest, session: session, downloader: downloader, network: peerNetwork)
        }
        if URL(string: file.storagePath)?.isFileURL == true {
            let media = try await service.media(file.mediaPublicId, session: session)
            return try await service.cacheMedia(media, session: session, downloader: downloader,
                                                maximumBytes: PeerMediaTransfer.maximumFileSize)
        }
        return try MusicHomeService.storageURL(file.storagePath)
    }

    public func cacheTrack(_ musicID: UUID, session: AuthSession) async throws {
        let track = try await service.trackFile(musicID, session: session)
        guard track.mediaPublicId != UUID.emptyPublicIdentifier else { throw LoginFailure.invalidResponse }
        _ = try await service.cacheMedia(track.registeredMedia, session: session, downloader: downloader,
                                         maximumBytes: PeerMediaTransfer.maximumFileSize, peerNetwork: peerNetwork)
        try Task.checkCancellation()
    }

    public func cancel() {
        for request in requests.values { request.cancel() }
        requests.removeAll()
    }
}

private extension MusicFileResponse {
    var registeredMedia: MediaResponse {
        MediaResponse(mediaPublicId: mediaPublicId, totalChunks: totalChunks, chunkSize: chunkSize,
                      fileHash: fileHash, fileName: fileName, fileSize: fileSize, storagePath: storagePath)
    }
}
