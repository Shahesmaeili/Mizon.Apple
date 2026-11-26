#if os(macOS) || os(iOS)
import AVFoundation
import Foundation
import MizonAPIClient
import Observation

@Observable @MainActor
public final class MusicHomeViewModel {
    public typealias Section = MusicHomeService.Section

    public let session: AuthSession
    public let service: MusicHomeService
    public let artwork: MusicArtworkStore
    public let player = AVPlayer()
    public private(set) var features: [MusicFeatureItemResponse] = []
    public private(set) var artists: [FeaturedPersonItem] = []
    public private(set) var stories: [StoryListItemResponse] = []
    public private(set) var genres: [MusicGenreTypeItemResponse] = []
    public private(set) var library: MusicLibraryResponse?
    public private(set) var activity: FollowingActivitiesResponse?
    public private(set) var failures: Set<Section> = []
    public private(set) var loading = Set(Section.allCases)
    public private(set) var playingTrack: UUID?
    public private(set) var playbackTitle = ""
    public private(set) var isPlaying = false
    public private(set) var requestingPlayback = false
    #if os(macOS)
    public enum PlaylistPlaybackStatus { case preparing, unavailable }
    public private(set) var playlistPlaybackStatus: PlaylistPlaybackStatus?
    @ObservationIgnored private var playlistPlayback: Task<Void, Never>?
    @ObservationIgnored private var playlistRequestID: UUID?
    @ObservationIgnored private var playlistEndObservers: [any NSObjectProtocol] = []
    #endif
    public private(set) var updating: Set<UUID> = []
    public var actionFailed = false
    @ObservationIgnored private var sectionRequests: [Section: UUID] = [:]
    @ObservationIgnored private var playbackRequest: Task<Bool, Never>?
    @ObservationIgnored private var playbackRecord: Task<Void, Never>?
    @ObservationIgnored private var playbackRequestID: UUID?
    @ObservationIgnored private var restorePreviousPlayback: (() -> Void)?

    public convenience init(session: AuthSession, service: MusicHomeService, peerNetwork: NearbyDiscoveryService? = nil) {
        self.init(session: session, service: service,
                  artwork: MusicArtworkStore(service: service, session: session, peerNetwork: peerNetwork))
    }

    init(session: AuthSession, service: MusicHomeService, artwork: MusicArtworkStore) {
        self.session = session
        self.service = service
        self.artwork = artwork
    }

    public func moodAnimationURL(_ mediaID: UUID) async throws -> URL {
        try await artwork.moodAnimationURL(mediaID, session: session)
    }

    public func refresh() async {
        await withTaskGroup(of: Void.self) { group in
            for section in Section.allCases {
                group.addTask { await self.refresh(section) }
            }
        }
    }

    public func refresh(_ section: Section) async {
        let request = UUID()
        sectionRequests[section] = request
        loading.insert(section)
        failures.remove(section)
        defer {
            if sectionRequests[section] == request {
                loading.remove(section)
                sectionRequests[section] = nil
            }
        }

        do {
            let contents = try await service.load(section, session: session)
            try Task.checkCancellation()
            guard sectionRequests[section] == request else { return }
            switch contents {
            case .features(let items): features = items
            case .artists(let items): artists = items
            case .stories(let items): stories = items
            case .genres(let items): genres = items
            case .library(let response): library = response
            case .activity(let response): activity = response
            }
        } catch {
            if !Task.isCancelled, sectionRequests[section] == request { failures.insert(section) }
        }
    }

    public func toggleLike(_ item: MusicFeatureItemResponse) async {
        let id = item.musicPublicId
        guard updating.insert(id).inserted else { return }
        defer { updating.remove(id) }
        do {
            let result = try await service.likeTrack(id, liked: !item.likedByMe, session: session)
            updateTrackLike(id, result: result)
        } catch {
            if !Task.isCancelled { actionFailed = true }
        }
    }

    public func toggleFollow(_ item: FeaturedPersonItem) async {
        let id = item.personPublicId
        guard item.canFollow, updating.insert(id).inserted else { return }
        defer { updating.remove(id) }
        do {
            let result = try await service.followArtist(id, following: !item.isFollowing, session: session)
            updateArtistFollow(id, result: result)
        } catch {
            if !Task.isCancelled { actionFailed = true }
        }
    }

    public func updateTrackLike(_ id: UUID, result: MusicLikeResponse) {
        for index in features.indices where features[index].musicPublicId == id {
            features[index].likedByMe = result.likedByMe
            features[index].likesCount = result.likesCount
        }
    }

    public func updateArtistFollow(_ id: UUID, result: PersonFollowResponse) {
        guard let index = artists.firstIndex(where: { $0.personPublicId == id }) else { return }
        artists[index].isFollowing = result.isFollowing
        artists[index].followersCount = result.followersCount
    }

    public func updateStoryView(_ story: StoryResponse) {
        guard let index = stories.firstIndex(where: { $0.publicId == story.publicId }) else { return }
        stories[index].viewedByMe = story.viewedByMe
    }

    public func play(_ id: UUID, title: String) {
        #if os(macOS)
        cancelPlaylist()
        #endif
        if id == playingTrack, !requestingPlayback {
            togglePlayback()
            return
        }
        beginPlayback(id, title: title, requireConfirmation: false)
    }

    public func playFromDeepLink(_ id: UUID, title: String, authorized: @escaping @MainActor () -> Bool) async throws {
        try Task.checkCancellation()
        guard authorized() else { throw CancellationError() }
        #if os(macOS)
        cancelPlaylist()
        #endif
        let request = beginPlayback(id, title: title, requireConfirmation: true, authorized: authorized)
        let started = await withTaskCancellationHandler {
            await request.value
        } onCancel: {
            request.cancel()
        }
        try Task.checkCancellation()
        guard authorized() else { throw CancellationError() }
        guard started else { throw LoginFailure.invalidResponse }
    }

    #if os(macOS)
    public func playPlaylist(_ id: UUID, title: @escaping @MainActor (MusicTabMusicItemResponse) -> String,
                             onTrackStarted: @escaping @MainActor (_ trackID: UUID, _ previousTrackID: UUID?) -> Void) {
        guard id != .emptyPublicIdentifier, playlistPlaybackStatus != .preparing else { return }
        cancelPlaylist()
        playbackRequest?.cancel()
        let requestID = UUID()
        playlistRequestID = requestID
        playlistPlaybackStatus = .preparing
        playlistPlayback = Task { [weak self] in
            await self?.runPlaylist(id, requestID: requestID, title: title, onTrackStarted: onTrackStarted)
        }
    }

    private func runPlaylist(_ id: UUID, requestID: UUID,
                             title: @MainActor (MusicTabMusicItemResponse) -> String,
                             onTrackStarted: @MainActor (UUID, UUID?) -> Void) async {
        defer {
            if playlistRequestID == requestID {
                removePlaylistEndObservers()
                playlistPlayback = nil
                playlistRequestID = nil
            }
        }
        var previousTrack: UUID?
        var cursor: String?
        do {
            repeat {
                let page = try await service.playlist(id, after: cursor, session: session)
                try Task.checkCancellation()
                guard playlistRequestID == requestID else { return }
                guard page.publicId == id else { throw LoginFailure.invalidResponse }
                for track in page.musics where track.publicId != .emptyPublicIdentifier {
                    try Task.checkCancellation()
                    let ended = AsyncStream.makeStream(of: Bool.self, bufferingPolicy: .bufferingNewest(1))
                    let request = beginPlayback(track.publicId, title: title(track), requireConfirmation: true,
                                                allowCurrentItem: false, authorized: { [weak self] in
                        self?.playlistRequestID == requestID
                    }, prepareItem: { [weak self] item in
                        self?.observePlaylistEnd(item, continuation: ended.continuation)
                    })
                    let started = await withTaskCancellationHandler { await request.value } onCancel: { request.cancel() }
                    try Task.checkCancellation()
                    guard playlistRequestID == requestID else { return }
                    guard started else { throw LoginFailure.invalidResponse }
                    playlistPlaybackStatus = nil
                    onTrackStarted(track.publicId, previousTrack)
                    previousTrack = track.publicId

                    var events = ended.stream.makeAsyncIterator()
                    let finished = await events.next()
                    try Task.checkCancellation()
                    guard playlistRequestID == requestID else { return }
                    removePlaylistEndObservers()
                    isPlaying = false
                    guard finished == true else { throw LoginFailure.invalidResponse }
                }
                guard page.nextCursor != cursor else { break }
                cursor = page.nextCursor
            } while cursor != nil
            if previousTrack == nil { playlistPlaybackStatus = .unavailable }
        } catch {
            if !Task.isCancelled, playlistRequestID == requestID { playlistPlaybackStatus = .unavailable }
        }
    }

    private func observePlaylistEnd(_ item: AVPlayerItem, continuation: AsyncStream<Bool>.Continuation) {
        let events: [Notification.Name] = [.AVPlayerItemDidPlayToEndTime, .AVPlayerItemFailedToPlayToEndTime]
        playlistEndObservers = events.map { name in
            NotificationCenter.default.addObserver(forName: name, object: item, queue: nil) { _ in
                continuation.yield(name == .AVPlayerItemDidPlayToEndTime)
                continuation.finish()
            }
        }
    }

    private func removePlaylistEndObservers() {
        for observer in playlistEndObservers { NotificationCenter.default.removeObserver(observer) }
        playlistEndObservers.removeAll()
    }

    private func cancelPlaylist() {
        playlistRequestID = nil
        playlistPlayback?.cancel()
        playlistPlayback = nil
        playlistPlaybackStatus = nil
        removePlaylistEndObservers()
    }
    #endif

    @discardableResult
    private func beginPlayback(_ id: UUID, title: String, requireConfirmation: Bool,
                               allowCurrentItem: Bool = true, authorized: @escaping @MainActor () -> Bool = { true },
                               prepareItem: (@MainActor (AVPlayerItem) -> Void)? = nil) -> Task<Bool, Never> {
        playbackRequest?.cancel()
        restorePreviousPlayback?()
        restorePreviousPlayback = nil
        let requestID = UUID()
        playbackRequestID = requestID
        if !requireConfirmation {
            player.pause()
            isPlaying = false
        }
        requestingPlayback = true
        let request = Task {
            var started = false
            defer {
                if playbackRequestID == requestID {
                    if !started { restorePreviousPlayback?() }
                    restorePreviousPlayback = nil
                    playbackRequest = nil
                    playbackRequestID = nil
                    requestingPlayback = false
                }
            }
            do {
                let currentItem = player.currentItem
                let wasPlaying = isPlaying
                let reused = requireConfirmation && allowCurrentItem && id == playingTrack
                    && currentItem?.status != .failed && currentItem != nil
                let item: AVPlayerItem
                if reused, let currentItem {
                    item = currentItem
                } else {
                    let file = try await service.trackFile(id, session: session)
                    let url = try await artwork.playableTrack(file, session: session)
                    item = AVPlayerItem(url: url)
                }
                try Task.checkCancellation()
                guard authorized(), playbackRequestID == requestID else { return false }
                #if os(iOS)
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playback)
                try audioSession.setActive(true)
                #endif
                if requireConfirmation {
                    restorePreviousPlayback = {
                        if self.player.currentItem !== currentItem { self.player.replaceCurrentItem(with: currentItem) }
                        if wasPlaying { self.player.play() } else { self.player.pause() }
                    }
                }
                prepareItem?(item)
                if !reused { player.replaceCurrentItem(with: item) }
                player.play()
                if requireConfirmation {
                    try await confirmPlayback(item, authorized: authorized)
                    try Task.checkCancellation()
                    guard authorized(), playbackRequestID == requestID else { return false }
                }
                playingTrack = id
                playbackTitle = title
                isPlaying = true
                started = true
                if !reused {
                    playbackRecord?.cancel()
                    playbackRecord = Task { [service, session] in
                        try? await service.recordPlayback(id, playbackID: UUID(), session: session)
                    }
                }
                return true
            } catch {
                if !requireConfirmation && !Task.isCancelled { actionFailed = true }
                return false
            }
        }
        playbackRequest = request
        return request
    }

    private func confirmPlayback(_ item: AVPlayerItem, authorized: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        repeat {
            try Task.checkCancellation()
            guard authorized(), player.currentItem === item else { throw CancellationError() }
            if player.timeControlStatus == .playing { return }
            if item.status == .failed { throw LoginFailure.invalidResponse }
            try await Task.sleep(for: .milliseconds(75))
        } while ContinuousClock.now < deadline
        throw LoginFailure.invalidResponse
    }

    public func togglePlayback() {
        guard player.currentItem != nil, !requestingPlayback else { return }
        isPlaying.toggle()
        if isPlaying { player.play() } else { player.pause() }
    }

    public func stop() {
        #if os(macOS)
        cancelPlaylist()
        #endif
        playbackRequest?.cancel()
        playbackRequest = nil
        playbackRecord?.cancel()
        playbackRecord = nil
        playbackRequestID = nil
        restorePreviousPlayback = nil
        player.replaceCurrentItem(with: nil)
        playingTrack = nil
        playbackTitle = ""
        isPlaying = false
        requestingPlayback = false
        Task { await artwork.cancel() }
    }
}
#endif
