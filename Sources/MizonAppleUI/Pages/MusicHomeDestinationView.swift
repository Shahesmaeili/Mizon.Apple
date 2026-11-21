#if os(macOS) || os(iOS)
import AVKit
import GameController
import MizonAPIClient
import MizonAppleCore
import SwiftUI

struct MusicHomeDestinationView: View {
    private enum Details {
        case track(UUID, MusicResponse)
        case artist(PersonProfileResponse)
        case client(ClientProfileResponse)
        case playlist(MusicPlaylistDetailsResponse)
        case story(StoryResponse)
    }

    let route: MusicDestination
    let model: MusicHomeViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var details: Details?
    @State private var tracks: [MusicTabMusicItemResponse] = []
    @State private var nextCursor: String?
    @State private var loading = true
    @State private var failed = false
    @State private var updating = false
    @State private var video: AVPlayer?
    @State private var loadID = 0
    private var localization = AuthLocalization()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let details { content(details) }
                if loading { ProgressView().accessibilityLabel(text("LoadingMusic")) }
                if failed {
                    Text(text("FeatureServiceFailed")).foregroundStyle(.secondary)
                    Button(text("Retry")) { loadID += 1 }.buttonStyle(.glass)
                }
            }
            .frame(maxWidth: 700, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(title)
        #if os(iOS)
        .toolbar(.visible, for: .navigationBar)
        #endif
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.backward")
                }
                .accessibilityLabel(text("Back"))
                .accessibilityIdentifier("music.destination.back")
                .keyboardShortcut(.cancelAction)
            }
        }
        .task(id: loadID) { await load() }
        .task(id: scenePhase) {
            if scenePhase == .active { await observeBack() }
        }
        .onDisappear { video?.pause() }
    }

    private var title: String {
        switch details {
        case .track(_, let item): localized(item.title, item.persianTitle)
        case .artist(let item): "\(item.firstName) \(item.lastName)"
        case .client(let item): item.nickName ?? [item.firstName, item.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        case .playlist(let item): item.title
        case .story(let item): item.title ?? text("Story")
        case nil: text("PageName")
        }
    }

    @ViewBuilder private func content(_ details: Details) -> some View {
        switch details {
        case .track(let id, let track):
            MusicArtwork(mediaID: track.musicCover?.mediaPublicId, model: model, symbol: "music.note")
                .frame(height: 280).clipShape(.rect(cornerRadius: 12))
            Text(localized(track.title, track.persianTitle)).font(localization.font(27, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(track.musicGenres.map { localized($0.title, $0.persianTitle) }.joined(separator: " · "))
                .foregroundStyle(.secondary)
            HStack {
                Button { model.play(id, title: title) } label: { Label(text("PlayInMizon"), systemImage: "play.fill") }
                Button { Task { await like(track, id: id) } } label: {
                    Label(text(track.likedByMe ? "UnlikeTrack" : "LikeTrack"), systemImage: track.likedByMe ? "heart.fill" : "heart")
                }
                .disabled(updating)
            }
            .buttonStyle(.glass)
        case .artist(let artist):
            MusicArtwork(mediaID: artist.coverMediaPublicId ?? artist.profileMediaPublicId, model: model, symbol: "person.crop.circle")
                .frame(height: 212).clipShape(.rect(cornerRadius: 12))
            HStack {
                Text(title).font(localization.font(25, weight: .semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                if artist.canFollow {
                    Button(text(artist.isFollowing ? "Following" : "Follow")) { Task { await follow(artist) } }
                        .buttonStyle(.glass).disabled(updating)
                }
            }
            Label(artist.followersCount.formatted(), systemImage: "person.2").foregroundStyle(.secondary)
            rows
        case .client(let item):
            MusicArtwork(mediaID: item.profileMediaPublicId, model: model, symbol: "person.fill")
                .frame(width: 118, height: 118)
                .background(MusicHomeStyle.inset)
                .clipShape(.circle)
            Text(title).font(localization.font(25, weight: .semibold)).accessibilityAddTraits(.isHeader)
            if let username = item.username, !username.isEmpty {
                Text("@" + username).font(localization.font(12)).foregroundStyle(MusicHomeStyle.cyan)
            }
        case .playlist(let playlist):
            Text(playlist.title).font(localization.font(25, weight: .semibold)).accessibilityAddTraits(.isHeader)
            rows
            if let nextCursor {
                Button(localization.string("LibraryMore", table: "MusicWidgets")) {
                    Task { await morePlaylist(playlist.publicId, cursor: nextCursor) }
                }
                .buttonStyle(.glass).disabled(loading)
            }
        case .story(let story):
            if let video {
                VideoPlayer(player: video).frame(height: 370).clipShape(.rect(cornerRadius: 12))
            } else {
                MusicArtwork(mediaID: story.contentMediaPublicId, model: model, symbol: "photo")
                    .frame(height: 370).clipShape(.rect(cornerRadius: 12))
            }
            Text("\(story.creatorFirstName) \(story.creatorLastName)")
                .font(localization.font(14, weight: .semibold))
            if let title = story.title, !title.isEmpty { Text(title).font(localization.font(16)) }
            Button {
                Task { await like(story) }
            } label: {
                Label(story.likesCount.formatted(), systemImage: story.likedByMe ? "heart.fill" : "heart")
            }
            .buttonStyle(.glass).disabled(updating)
            ForEach(story.widgets, id: \.publicId) { widget in
                if let music = widget.music {
                    NavigationLink(destination: MusicHomeDestinationView(route: .track(music.musicPublicId), model: model)) {
                        Label(music.title, systemImage: "music.note")
                    }
                }
            }
        }
    }

    private var rows: some View {
        LazyVStack(spacing: 8) {
            ForEach(tracks, id: \.publicId) { track in
                HStack {
                    NavigationLink(destination: MusicHomeDestinationView(route: .track(track.publicId), model: model)) {
                        HStack(spacing: 10) {
                            MusicArtwork(mediaID: track.coverMediaPublicId, model: model, symbol: "music.note")
                                .frame(width: 44, height: 44).clipShape(.rect(cornerRadius: 8))
                            Text(localized(track.title, track.persianTitle)).lineLimit(1)
                        }
                    }
                    Spacer()
                    Button { model.play(track.publicId, title: localized(track.title, track.persianTitle)) } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.glass).accessibilityLabel(text("PlayInMizon"))
                }
                .padding(8)
                .musicPanel()
            }
        }
    }

    private func load() async {
        failed = false
        loading = true
        defer { if !Task.isCancelled { loading = false } }
        do {
            switch route {
            case .track(let id):
                details = .track(id, try await model.service.track(id, session: model.session))
            case .client(let id):
                details = .client(try await model.service.client(id, session: model.session))
            case .artist(let id):
                async let artist = model.service.artist(id, session: model.session)
                async let music = model.service.artistMusic(id, after: nil, session: model.session)
                details = .artist(try await artist)
                tracks = try await music.musics
            case .playlist(let id):
                let playlist = try await model.service.playlist(id, after: nil, session: model.session)
                details = .playlist(playlist)
                tracks = playlist.musics
                nextCursor = playlist.nextCursor
            case .story(let id):
                let story = try await model.service.story(id, session: model.session)
                details = .story(story)
                if !story.viewedByMe,
                   let viewed = try? await model.service.markStoryViewed(id, session: model.session), !Task.isCancelled {
                    model.updateStoryView(viewed)
                    details = .story(viewed)
                }
                if story.storyContentTypeTitle.localizedCaseInsensitiveContains("video") {
                    let media = try await model.service.media(story.contentMediaPublicId, session: model.session)
                    let player = AVPlayer(url: try MusicHomeService.storageURL(media.storagePath))
                    video = player
                    player.play()
                }
            }
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }

    private func morePlaylist(_ id: UUID, cursor: String) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await model.service.playlist(id, after: cursor, session: model.session)
            let existing = Set(tracks.map(\.publicId))
            tracks += page.musics.filter { !existing.contains($0.publicId) }
            nextCursor = page.nextCursor
        } catch { model.actionFailed = true }
    }

    private func like(_ item: MusicResponse, id: UUID) async {
        guard !updating else { return }
        updating = true
        defer { updating = false }
        do {
            let response = try await model.service.likeTrack(id, liked: !item.likedByMe, session: model.session)
            model.updateTrackLike(id, result: response)
            var updated = item
            updated.likedByMe = response.likedByMe
            updated.likesCount = response.likesCount
            details = .track(id, updated)
        } catch { model.actionFailed = true }
    }

    private func like(_ item: StoryResponse) async {
        guard !updating else { return }
        updating = true
        defer { updating = false }
        do {
            let response = try await model.service.likeStory(item.publicId, liked: !item.likedByMe, session: model.session)
            model.updateStoryView(response)
            details = .story(response)
        } catch { model.actionFailed = true }
    }

    private func follow(_ item: PersonProfileResponse) async {
        guard !updating else { return }
        updating = true
        defer { updating = false }
        do {
            let response = try await model.service.followArtist(item.personPublicId, following: !item.isFollowing,
                                                                session: model.session)
            model.updateArtistFollow(item.personPublicId, result: response)
            var updated = item
            updated.isFollowing = response.isFollowing
            updated.followersCount = response.followersCount
            details = .artist(updated)
        } catch { model.actionFailed = true }
    }

    private func observeBack() async {
        var owner: GCController?
        var armed = false
        while !Task.isCancelled {
            let controller = GCController.controllers().first { $0.extendedGamepad != nil }
            if owner !== controller {
                owner = controller
                armed = false
            }
            if let gamepad = controller?.extendedGamepad {
                if !gamepad.buttonB.isPressed {
                    armed = true
                } else if armed {
                    dismiss()
                    return
                }
            }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
    }

    private func localized(_ title: String, _ persian: String?) -> String {
        if localization.isPersian, let persian, !persian.isEmpty { return persian }
        return title
    }
    private func text(_ key: String) -> String { localization.string(key, table: "MusicHome") }
}
#endif
