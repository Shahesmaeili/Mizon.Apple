#if os(macOS) || os(iOS)
import AVFoundation
import Foundation
import MizonAPIClient
import Observation
import OSLog

@Observable @MainActor
public final class MusicHomeViewModel {
    public typealias Section = MusicHomeService.Section

    private static let log = Logger(subsystem: "com.shahesmaeili.Mizon.Apple", category: "MusicPlayback")

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
    public var repeatingTrack: UUID?
    public private(set) var stemMixTrack: UUID?
    @ObservationIgnored private var playbackEndObserver: (any NSObjectProtocol)?
    public private(set) var requestingPlayback = false
    public enum PlaylistPlaybackStatus { case preparing, unavailable }
    public private(set) var playlistPlaybackStatus: PlaylistPlaybackStatus?
    @ObservationIgnored private var playlistPlayback: Task<Void, Never>?
    @ObservationIgnored private var playlistRequestID: UUID?
    @ObservationIgnored private var playlistEndObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private var playlistContinuation: AsyncStream<Bool>.Continuation?
    @ObservationIgnored private var originalMix: AVPlayerItem?
    @ObservationIgnored private var stemTracks: (AVCompositionTrack, AVCompositionTrack)?
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
        cancelPlaylist()
        if id == playingTrack, !requestingPlayback {
            togglePlayback()
            return
        }
        beginPlayback(id, title: title, requireConfirmation: false)
    }

    public func playFromDeepLink(_ id: UUID, title: String, authorized: @escaping @MainActor () -> Bool) async throws {
        try Task.checkCancellation()
        guard authorized() else { throw CancellationError() }
        cancelPlaylist()
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

    public func playPlaylist(_ id: UUID, title: @escaping @MainActor (MusicTabMusicItemResponse) -> String,
                             onTrackSelected: @escaping @MainActor (_ trackID: UUID, _ previousTrackID: UUID?) -> Void) {
        guard id != .emptyPublicIdentifier, playlistPlaybackStatus != .preparing else { return }
        cancelPlaylist()
        playbackRequest?.cancel()
        let requestID = UUID()
        playlistRequestID = requestID
        playlistPlaybackStatus = .preparing
        playlistPlayback = Task { [weak self] in
            await self?.runPlaylist(id, requestID: requestID, title: title, onTrackSelected: onTrackSelected)
        }
    }

    private func runPlaylist(_ id: UUID, requestID: UUID,
                             title: @MainActor (MusicTabMusicItemResponse) -> String,
                             onTrackSelected: @MainActor (UUID, UUID?) -> Void) async {
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
                    onTrackSelected(track.publicId, previousTrack)
                    previousTrack = track.publicId
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
            if !Task.isCancelled, playlistRequestID == requestID {
                playlistPlaybackStatus = .unavailable
                if previousTrack != nil { actionFailed = true }
            }
        }
    }

    private func observePlaylistEnd(_ item: AVPlayerItem, continuation: AsyncStream<Bool>.Continuation) {
        let events: [Notification.Name] = [.AVPlayerItemDidPlayToEndTime, .AVPlayerItemFailedToPlayToEndTime]
        playlistEndObservers = events.map { name in
            NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if name == .AVPlayerItemDidPlayToEndTime, self?.repeatIfNeeded() == true { return }
                    continuation.yield(name == .AVPlayerItemDidPlayToEndTime)
                    continuation.finish()
                }
            }
        }
    }

    private func removePlaylistEndObservers() {
        playlistContinuation = nil
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

    @discardableResult
    private func beginPlayback(_ id: UUID, title: String, requireConfirmation: Bool,
                               allowCurrentItem: Bool = true, authorized: @escaping @MainActor () -> Bool = { true },
                               prepareItem: (@MainActor (AVPlayerItem) -> Void)? = nil,
                               initialTime: Double? = nil) -> Task<Bool, Never> {
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
                if let initialTime {
                    await item.seek(to: CMTime(seconds: initialTime, preferredTimescale: 1_000),
                                    toleranceBefore: .zero, toleranceAfter: .zero)
                    try Task.checkCancellation()
                    guard playbackRequestID == requestID, authorized(), player.currentItem === item else { return false }
                }
                if !reused { originalMix = nil; stemTracks = nil; stemMixTrack = nil }
                if prepareItem == nil { observeTrackEnd(item) }
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
                if !(error is CancellationError), !Task.isCancelled {
                    let failure = error as NSError
                    Self.log.error("Audio could not start (\(failure.domain, privacy: .public):\(failure.code, privacy: .public)).")
                    if !requireConfirmation { actionFailed = true }
                }
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

    public func seekTrack(_ id: UUID, title: String, at seconds: Double, startPlayback: Bool) {
        guard seconds.isFinite, seconds >= 0, !requestingPlayback else { return }
        if playingTrack == id, player.currentItem != nil {
            let time = CMTime(seconds: seconds, preferredTimescale: 1_000)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            if startPlayback && !isPlaying { togglePlayback() }
        } else if startPlayback {
            cancelPlaylist()
            beginPlayback(id, title: title, requireConfirmation: false, initialTime: seconds)
        }
    }

    public func switchTrackMix(for id: UUID, vocals: UUID, instrumental: UUID, balance: Double) async throws {
        guard playingTrack == id, let current = player.currentItem, !requestingPlayback, originalMix == nil else {
            throw LoginFailure.invalidResponse
        }
        async let vocalsURL = artwork.file(vocals, session: session, maximumBytes: PeerMediaTransfer.maximumFileSize)
        async let instrumentalURL = artwork.file(instrumental, session: session, maximumBytes: PeerMediaTransfer.maximumFileSize)
        let sources = try await [AVURLAsset(url: vocalsURL), AVURLAsset(url: instrumentalURL)]
        let mix = AVMutableComposition()
        var audio: [AVCompositionTrack] = []
        for asset in sources {
            let source = try await asset.loadTracks(withMediaType: .audio).first
            guard let source, let lane = mix.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw LoginFailure.invalidResponse
            }
            let range = try await source.load(.timeRange)
            try lane.insertTimeRange(range, of: source, at: .zero)
            audio.append(lane)
        }
        try Task.checkCancellation()
        guard playingTrack == id, player.currentItem === current, !requestingPlayback else { throw CancellationError() }
        let replacement = AVPlayerItem(asset: mix)
        originalMix = current
        stemTracks = (audio[0], audio[1])
        stemMixTrack = id
        replacement.audioMix = makeStemBalance(balance)
        switchMixItem(replacement)
    }

    public func updateTrackMixBalance(_ balance: Double, for id: UUID) {
        guard playingTrack == id, originalMix != nil else { return }
        player.currentItem?.audioMix = makeStemBalance(balance)
    }

    public func restoreOriginalMix(for id: UUID) {
        guard playingTrack == id, let originalMix else { return }
        self.originalMix = nil
        stemTracks = nil
        stemMixTrack = nil
        switchMixItem(originalMix)
    }

    private func switchMixItem(_ item: AVPlayerItem) {
        let position = player.currentTime()
        let wasPlaying = isPlaying
        if let continuation = playlistContinuation { observePlaylistEnd(item, continuation: continuation) }
        else { observeTrackEnd(item) }
        player.replaceCurrentItem(with: item)
        player.seek(to: position, toleranceBefore: .zero, toleranceAfter: .zero)
        if wasPlaying { player.play() }
    }

    private func makeStemBalance(_ balance: Double) -> AVAudioMix? {
        guard let (voice, backing) = stemTracks else { return nil }
        let value = min(1, max(-1, balance / 100))
        let voiceParameters = AVMutableAudioMixInputParameters(track: voice)
        voiceParameters.setVolume(Float(min(1, 1 + value)), at: .zero)
        let backingParameters = AVMutableAudioMixInputParameters(track: backing)
        backingParameters.setVolume(Float(min(1, 1 - value)), at: .zero)
        let mix = AVMutableAudioMix()
        mix.inputParameters = [voiceParameters, backingParameters]
        return mix
    }

    private func observeTrackEnd(_ item: AVPlayerItem) {
        if let playbackEndObserver { NotificationCenter.default.removeObserver(playbackEndObserver) }
        playbackEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                                     object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.playlistContinuation == nil else { return }
                if !self.repeatIfNeeded() { self.isPlaying = false }
            }
        }
    }

    private func repeatIfNeeded() -> Bool {
        guard !requestingPlayback, let repeatingTrack, repeatingTrack == playingTrack, player.currentItem != nil else { return false }
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
        isPlaying = true
        return true
    }

    public func togglePlayback() {
        guard let item = player.currentItem, !requestingPlayback else { return }
        isPlaying.toggle()
        if isPlaying {
            let duration = item.duration.seconds
            if duration.isFinite, duration > 0, player.currentTime().seconds >= duration - 0.05 {
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
            }
            player.play()
        } else { player.pause() }
    }

    public func stop() {
        cancelPlaylist()
        playbackRequest?.cancel()
        playbackRequest = nil
        playbackRecord?.cancel()
        playbackRecord = nil
        playbackRequestID = nil
        restorePreviousPlayback = nil
        if let playbackEndObserver { NotificationCenter.default.removeObserver(playbackEndObserver) }
        playbackEndObserver = nil
        player.replaceCurrentItem(with: nil)
        stemMixTrack = nil
        repeatingTrack = nil
        originalMix = nil
        stemTracks = nil
        playingTrack = nil
        playbackTitle = ""
        isPlaying = false
        requestingPlayback = false
        Task { await artwork.cancel() }
    }
}
#endif
