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
    public private(set) var updating: Set<UUID> = []
    public var actionFailed = false
    @ObservationIgnored private var sectionRequests: [Section: UUID] = [:]
    @ObservationIgnored private var playbackRequest: Task<Void, Never>?

    public init(session: AuthSession, service: MusicHomeService, peerNetwork: NearbyDiscoveryService? = nil) {
        self.session = session
        self.service = service
        artwork = MusicArtworkStore(service: service, session: session, peerNetwork: peerNetwork)
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

    public func loadMoreActivity() async {
        guard let current = activity, let cursor = current.nextCursor, !loading.contains(.activity) else { return }
        let request = UUID()
        sectionRequests[.activity] = request
        loading.insert(.activity)
        defer {
            if sectionRequests[.activity] == request {
                sectionRequests[.activity] = nil
                loading.remove(.activity)
            }
        }
        do {
            var next = try await service.activity(after: cursor, session: session)
            guard sectionRequests[.activity] == request, !Task.isCancelled else { return }
            let existingIds = Set(current.activities.map(\.activityId))
            next.activities = current.activities + next.activities.filter { !existingIds.contains($0.activityId) }
            activity = next
        } catch {
            if !Task.isCancelled, sectionRequests[.activity] == request { actionFailed = true }
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
        if id == playingTrack, !requestingPlayback {
            togglePlayback()
            return
        }
        playbackRequest?.cancel()
        player.pause()
        isPlaying = false
        requestingPlayback = true
        playbackRequest = Task {
            defer { if !Task.isCancelled { requestingPlayback = false } }
            do {
                let file = try await service.trackFile(id, session: session)
                let url = try await artwork.playableTrack(file, session: session)
                try Task.checkCancellation()
                #if os(iOS)
                let audioSession = AVAudioSession.sharedInstance()
                try audioSession.setCategory(.playback)
                try audioSession.setActive(true)
                #endif
                player.replaceCurrentItem(with: AVPlayerItem(url: url))
                playingTrack = id
                playbackTitle = title
                isPlaying = true
                player.play()
                try? await service.recordPlayback(id, playbackID: UUID(), session: session)
            } catch {
                if !Task.isCancelled { actionFailed = true }
            }
        }
    }

    public func togglePlayback() {
        guard player.currentItem != nil, !requestingPlayback else { return }
        isPlaying.toggle()
        if isPlaying { player.play() } else { player.pause() }
    }

    public func stop() {
        playbackRequest?.cancel()
        playbackRequest = nil
        player.replaceCurrentItem(with: nil)
        playingTrack = nil
        playbackTitle = ""
        isPlaying = false
        requestingPlayback = false
        Task { await artwork.cancel() }
    }
}
#endif
