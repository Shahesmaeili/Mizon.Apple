#if os(macOS) || os(iOS)
import AVFoundation
import Foundation
import MizonAPI
import MizonAPIClient
import Observation

@Observable @MainActor
public final class MusicTrackDetailsViewModel {
    public enum Pane: Hashable { case album, contributors, comments }
    public enum Section: Hashable, Sendable { case waveform, lyrics, credits, reactions, stories, related, discussion, playlists }

    public enum CommentSort: String, CaseIterable, Sendable {
        case newest, oldest, likes, dislikes

        public var textKey: String {
            switch self {
            case .newest: "CommentNewest"
            case .oldest: "CommentOldest"
            case .likes: "CommentMostLikes"
            case .dislikes: "CommentMostDislikes"
            }
        }
    }

    public struct Reaction: Identifiable, Sendable {
        public let id: UUID
        public let emoji: String
        public var count: Int
        public var selected: Bool
    }

    public let id: UUID
    public let music: MusicHomeViewModel
    public var track: MusicResponse
    public private(set) var duration: Double = 0
    public private(set) var wave: [TrackWaveformBar] = []
    public private(set) var credits: [MusicContributorItemResponse] = []
    public private(set) var lyrics: [MusicLyricLineItemResponse] = []
    public private(set) var reactions: [Reaction] = []
    public private(set) var listeners: [MusicListenerPresence] = []
    public private(set) var liveViewers = 0
    public private(set) var stories: [StoryListItemResponse] = []
    public private(set) var related: [MusicTabMusicItemResponse] = []
    public private(set) var timedComments: [MusicCommentItemResponse] = []
    public private(set) var comments: [MusicCommentItemResponse] = []
    public private(set) var playlists: [MusicPlaylistListItemResponse] = []
    public private(set) var stemMix: MusicStemMixResponse?
    public private(set) var failures: Set<Section> = []
    public private(set) var loading: Set<Section> = []
    public private(set) var busyIDs: Set<UUID> = []
    public private(set) var parentComment: MusicCommentItemResponse?
    public private(set) var sort = CommentSort.newest
    public private(set) var pane: Pane
    public private(set) var nextComment: UUID?
    public private(set) var posting = false
    public private(set) var changingPlaylists = false
    public private(set) var liking = false
    public private(set) var mixLoading = false
    public var mixActive: Bool { music.stemMixTrack == id }
    public var balance: Double = 0
    public var notice: String?
    @ObservationIgnored private var loadedSections = Set<Section>()
    @ObservationIgnored private var sectionRequests: [Section: UUID] = [:]
    @ObservationIgnored private var recordedView = false
    @ObservationIgnored private var audienceRequest: UUID?

    public init(id: UUID, track: MusicResponse, music: MusicHomeViewModel, linkedComment: MusicCommentItemResponse?) {
        self.id = id
        self.track = track
        self.music = music
        pane = linkedComment != nil ? .comments : track.musicAlbum == nil ? .contributors : .album
        if let linkedComment { comments = [linkedComment] }
        linkedCommentID = linkedComment?.publicId
    }

    private var service: MusicHomeService { music.service }
    private var session: AuthSession { music.session }

    public func load() async {
        await withTaskGroup(of: Void.self) { group in
            for section in [Section.waveform, .lyrics, .credits, .reactions, .stories] {
                group.addTask { await self.load(section) }
            }
            group.addTask { await self.loadPane() }
            if !recordedView {
                recordedView = true
                group.addTask { try? await self.service.recordTrackView(self.id, session: self.session) }
            }
        }
    }

    public func observeAudience(position: @escaping @MainActor @Sendable () -> Double) async {
        let request = UUID()
        audienceRequest = request
        let socket = service.makeWindowPresenceSocket(session: session)
        let track = id
        await withTaskCancellationHandler {
            do {
                let events = await socket.events()
                try await socket.joinEntity("music", entityPublicId: track)
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for await event in events {
                            if Task.isCancelled { return }
                            await self.applyAudience(event, request: request)
                        }
                    }
                    group.addTask {
                        while !Task.isCancelled {
                            let playback = await self.audiencePlayback(position)
                            if let playback {
                                try? await socket.publishMusicPlayback(musicPublicId: track,
                                                                       position: TimeSpan(seconds: playback.0), isPlaying: playback.1)
                            }
                            do { try await Task.sleep(for: .milliseconds(750)) }
                            catch { return }
                        }
                    }
                }
            } catch {}
            await socket.dispose()
        } onCancel: {
            Task { await socket.dispose() }
        }
        if audienceRequest == request {
            audienceRequest = nil
            listeners = []
            liveViewers = 0
        }
    }

    private func audiencePlayback(_ position: @MainActor () -> Double) -> (Double, Bool)? {
        guard music.playingTrack == id else { return nil }
        let value = position()
        return (value.isFinite ? min(max(0, value), 1_000_000) : 0, music.isPlaying)
    }

    private func applyAudience(_ event: MizonSocketEvent, request: UUID) {
        guard audienceRequest == request else { return }
        let selfID = session.clientPublicId
        switch event {
        case .entityViewersCountChanged(let type, let id, let count) where id == self.id && type.lowercased() == "music":
            liveViewers = max(0, count)
        case .musicListenersSnapshot(let id, let received) where id == self.id:
            var ids = Set<UUID>()
            listeners = Array(received.lazy.filter { $0.clientPublicId != selfID && ids.insert($0.clientPublicId).inserted }.prefix(100))
        case .musicListenerUpdated(let id, let listener) where id == self.id && listener.clientPublicId != selfID:
            if let index = listeners.firstIndex(where: { $0.clientPublicId == listener.clientPublicId }) { listeners[index] = listener }
            else if listeners.count < 100 { listeners.append(listener) }
        case .musicListenerRemoved(let id, let client) where id == self.id:
            listeners.removeAll { $0.clientPublicId == client }
        case .stateChanged(.disconnected), .stateChanged(.reconnecting):
            listeners = []
            liveViewers = 0
        default: break
        }
    }

    public func load(_ section: Section, refresh: Bool = false) async {
        if !refresh, loadedSections.contains(section) || loading.contains(section) { return }
        let request = begin(section)
        defer { finish(section, request: request) }
        do {
            switch section {
            case .waveform:
                async let fileRequest = service.trackFile(id, session: session)
                async let stems = try? service.trackStems(id, session: session)
                async let markers = try? service.trackDiscussion(.init(musicPublicId: id, pageSize: 100, timedOnly: true), session: session)
                let file = try await fileRequest
                let wave = try? await service.trackWaveform(file.musicFilePublicId, session: session)
                let (stemsResponse, timed) = await (stems, markers)
                try check(section, request: request)
                duration = max(0, file.duration.totalSeconds)
                self.wave = TrackWaveformBar.sample(wave?.waveforms ?? [], trackID: id)
                stemMix = stemsResponse
                timedComments = timed?.musicComments ?? []
            case .lyrics:
                let languages = try await service.trackLyrics(id, session: session)
                let selected = languages.sorted { lhs, rhs in
                    let l = Self.isPersian(lhs)
                    let r = Self.isPersian(rhs)
                    return l == r ? lhs.languageTitle < rhs.languageTitle : l
                }.first
                let lines: [MusicLyricLineItemResponse]
                if let selected { lines = try await service.trackLyricLines(selected.musicLyricPublicId, session: session) }
                else { lines = [] }
                try check(section, request: request)
                lyrics = lines.sorted { $0.lineOrder < $1.lineOrder }.map { row in
                    var row = row
                    row.musicLyricLineWords.sort { $0.wordOrder < $1.wordOrder }
                    return row
                }
            case .credits:
                let found = try await service.trackCredits(id, session: session)
                try check(section, request: request)
                credits = found
            case .reactions:
                let (types, counts) = try await service.trackReactions(id, session: session)
                try check(section, request: request)
                let indexed = Dictionary(counts.map { ($0.musicReactionTypePublicId, $0) }, uniquingKeysWith: { first, _ in first })
                reactions = types.map {
                    let value = indexed[$0.publicId]
                    return Reaction(id: $0.publicId, emoji: $0.emoji, count: value?.count ?? 0, selected: value?.reactedByMe ?? false)
                }
            case .stories:
                let found = try await service.trackStories(id, session: session)
                try check(section, request: request)
                stories = found
            case .related:
                let found = try await service.relatedTracks(id, album: pane == .album, session: session)
                try check(section, request: request)
                related = found
            case .discussion:
                try await requestComments(after: nil, request: request)
            case .playlists:
                let found = try await service.trackPlaylists(id, session: session)
                try check(section, request: request)
                playlists = found
            }
            loadedSections.insert(section)
        } catch {
            if !Task.isCancelled, !(error is CancellationError), sectionRequests[section] == request {
                failures.insert(section)
                if section == .waveform, wave.isEmpty { wave = TrackWaveformBar.sample([], trackID: id) }
            }
        }
    }

    private static func isPersian(_ item: MusicLyricLanguageResponse) -> Bool {
        item.languagePersianTitle == "فارسی" || item.languageTitle.caseInsensitiveCompare("Persian") == .orderedSame
    }

    public func select(_ pane: Pane) {
        guard self.pane != pane else { return }
        self.pane = pane
        parentComment = nil
        for section in [Section.related, .discussion] {
            sectionRequests[section] = nil
            loading.remove(section)
            loadedSections.remove(section)
        }
        related = []
        comments = []
        nextComment = nil
    }

    public func loadPane() async {
        await load(pane == .comments ? .discussion : .related)
    }

    public func sortDiscussion(_ sort: CommentSort) async {
        guard self.sort != sort else { return }
        self.sort = sort
        nextComment = nil
        await load(.discussion, refresh: true)
    }

    public func showReplies(_ parent: MusicCommentItemResponse?) async {
        if pane != .comments { select(.comments) }
        guard parent?.publicId != parentComment?.publicId else { return }
        parentComment = parent
        comments = []
        nextComment = nil
        await load(.discussion, refresh: true)
    }

    public func showLinkedComment(_ comment: MusicCommentItemResponse) {
        linkedCommentID = comment.publicId
        if !comments.contains(where: { $0.publicId == comment.publicId }) {
            comments.insert(comment, at: 0)
        }
    }

    public func moreComments() async {
        guard pane == .comments, let nextComment, !loading.contains(.discussion) else { return }
        let request = begin(.discussion)
        defer { finish(.discussion, request: request) }
        do { try await requestComments(after: nextComment, request: request) }
        catch {
            if !Task.isCancelled, sectionRequests[.discussion] == request { failures.insert(.discussion) }
        }
    }

    private func requestComments(after cursor: UUID?, request: UUID) async throws {
        let page = try await service.trackDiscussion(.init(musicPublicId: id, parentMusicCommentPublicId: parentComment?.publicId,
                                                            after: cursor, pageSize: 30, sort: sort.rawValue), session: session)
        try check(.discussion, request: request)
        // Preserve an explicitly linked item until its row arrives through the normal discussion listing.
        var next = cursor == nil ? comments.prefix(1).filter { item in
            page.musicComments.contains { $0.publicId == item.publicId } == false && item.publicId == linkedCommentID
        } : comments
        var seen = Set(next.map(\.publicId))
        next.append(contentsOf: page.musicComments.filter { seen.insert($0.publicId).inserted })
        comments = next
        nextComment = cursor == page.next ? nil : page.next
    }

    private var linkedCommentID: UUID?

    public func tagSearch(type: String, text: String) async throws -> [MusicCommentTagItem] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...80).contains(query.count) else { return [] }
        return try await service.searchTrackCommentTags(.init(type: type, query: query), session: session)
    }

    public func submit(_ text: String, parent: UUID?, time: Double?, tags: [MusicCommentTagItem]) async -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !posting, !text.isEmpty, text.utf16.count <= 2_000, tags.count <= 8 else { return false }
        posting = true
        defer { posting = false }
        let time = time.flatMap { $0.isFinite && duration > 0 ? TimeSpan(seconds: min(duration, max(0, $0))) : nil }
        do {
            _ = try await service.postTrackComment(.init(musicPublicId: id, text: text, timestamp: time,
                                                          parentMusicCommentPublicId: parent,
                                                          tags: tags.map { .init(type: $0.type, publicId: $0.publicId) }), session: session)
            if parent == parentComment?.publicId { await load(.discussion, refresh: true) }
            if time != nil { await load(.waveform, refresh: true) }
            return true
        } catch {
            if !Task.isCancelled { notice = "CommentPostFailed" }
            return false
        }
    }

    public func vote(_ comment: MusicCommentItemResponse, vote: Int) async {
        guard [-1, 1].contains(vote), busyIDs.insert(comment.publicId).inserted else { return }
        defer { busyIDs.remove(comment.publicId) }
        do {
            let result = try await service.voteOnTrackComment(.init(musicPublicId: id, musicCommentPublicId: comment.publicId,
                                                                   vote: comment.myVote == vote ? 0 : vote), session: session)
            guard let index = comments.firstIndex(where: { $0.publicId == comment.publicId }) else { return }
            comments[index].likes = result.likes
            comments[index].dislikes = result.dislikes
            comments[index].myVote = result.myVote
        } catch { if !Task.isCancelled { notice = "TrackSectionFailed" } }
    }

    public func like() async {
        guard !liking else { return }
        liking = true
        defer { liking = false }
        do {
            let result = try await service.likeTrack(id, liked: !track.likedByMe, session: session)
            track.likedByMe = result.likedByMe
            track.likesCount = result.likesCount
            music.updateTrackLike(id, result: result)
        } catch { if !Task.isCancelled { notice = "TrackSectionFailed" } }
    }

    public func react(_ reaction: Reaction) async {
        guard let index = reactions.firstIndex(where: { $0.id == reaction.id }), busyIDs.insert(reaction.id).inserted else { return }
        defer { busyIDs.remove(reaction.id) }
        let previous = reactions[index]
        reactions[index].selected.toggle()
        reactions[index].count = max(0, previous.count + (previous.selected ? -1 : 1))
        do { try await service.reactToTrack(id, type: previous.id, reacted: !previous.selected, session: session) }
        catch {
            if let index = reactions.firstIndex(where: { $0.id == previous.id }) { reactions[index] = previous }
            if !Task.isCancelled { notice = "TrackSectionFailed" }
        }
    }

    public func toggleMembership(_ playlist: UUID) async {
        guard !changingPlaylists, let index = playlists.firstIndex(where: { $0.publicId == playlist }) else { return }
        changingPlaylists = true
        defer { changingPlaylists = false }
        var selected = Set(playlists.filter(\.containsCurrentMusic).map(\.publicId))
        let added = !selected.contains(playlist)
        if added { selected.insert(playlist) } else { selected.remove(playlist) }
        do {
            try await service.changeTrackPlaylists(id, selected: selected.sorted { $0.uuidString < $1.uuidString }, session: session)
            if playlists.indices.contains(index), playlists[index].publicId == playlist {
                playlists[index].containsCurrentMusic = added
                playlists[index].musicsCount = max(0, playlists[index].musicsCount + (added ? 1 : -1))
            }
        } catch {
            if !Task.isCancelled { notice = "TrackSectionFailed" }
            await load(.playlists, refresh: true)
        }
    }

    public func createPlaylist(_ title: String) async -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !changingPlaylists, !title.isEmpty, title.utf16.count <= 100 else { return false }
        changingPlaylists = true
        defer { changingPlaylists = false }
        do {
            _ = try await service.createTrackPlaylist(id, title: title, session: session)
            await load(.playlists, refresh: true)
            return true
        } catch {
            if !Task.isCancelled { notice = "TrackSectionFailed" }
            return false
        }
    }

    public func seek(to seconds: Double, startPlayback: Bool = true, title: String) {
        guard seconds.isFinite, duration > 0 else { return }
        music.seekTrack(id, title: title, at: min(duration, max(0, seconds)), startPlayback: startPlayback)
    }

    public func toggleMix() async {
        guard !mixLoading, let stemMix, stemMix.isAvailable,
              let vocals = stemMix.vocalsMediaPublicId, let instrumental = stemMix.instrumentalMediaPublicId else { return }
        if mixActive {
            music.restoreOriginalMix(for: id)
            return
        }
        mixLoading = true
        defer { mixLoading = false }
        do {
            try await music.switchTrackMix(for: id, vocals: vocals, instrumental: instrumental, balance: balance)
        } catch { if !Task.isCancelled { notice = "TrackMixUnavailable" } }
    }

    private func begin(_ section: Section) -> UUID {
        let request = UUID()
        sectionRequests[section] = request
        loading.insert(section)
        failures.remove(section)
        return request
    }

    private func check(_ section: Section, request: UUID) throws {
        try Task.checkCancellation()
        guard sectionRequests[section] == request else { throw CancellationError() }
    }

    private func finish(_ section: Section, request: UUID) {
        guard sectionRequests[section] == request else { return }
        loading.remove(section)
    }
}

public struct TrackWaveformBar: Sendable, Equatable {
    public static let count = 250
    public let top: Int
    public let bottom: Int
    public let energy: Double

    public static func sample(_ source: [WaveformResponse], trackID: UUID) -> [Self] {
        let points = source.sorted { $0.offsetInMilliseconds < $1.offsetInMilliseconds }
        let maxRMS = points.lazy.map { $0.rms.isFinite ? abs($0.rms) : 0 }.max() ?? 0
        let peak = points.lazy.map { abs(Int($0.peak)) }.max() ?? 0
        let scale = maxRMS > 0 ? maxRMS : Float(max(1, peak))
        var seed = withUnsafeBytes(of: trackID.uuid) { $0.reduce(UInt64(7)) { $0 &* 31 &+ UInt64($1) } }
        return (0..<count).map { index in
            let level: Float
            let energy: Float
            if points.isEmpty {
                seed = 2_862_933_555_777_941_757 &* seed &+ 3_037_000_493
                level = Float((seed >> 32) % 1_000) / 1_000
                energy = 0
            } else {
                let raw = points[index * points.count / count].rms
                level = raw.isFinite ? min(1, abs(raw) / scale) : 0
                energy = raw.isFinite ? min(1, abs(raw)) : 0
            }
            let height = 7 + Int(level * 63)
            return Self(top: height, bottom: height / 2, energy: Double(energy))
        }
    }
}
#endif
