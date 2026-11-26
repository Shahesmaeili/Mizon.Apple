#if os(macOS) || os(iOS)
import AVKit
import MizonAPIClient
import MizonAppleCore
import SwiftUI

struct MusicHomeDestinationView: View {
    private struct LoadIdentity: Equatable {
        let requestID: UUID?
        let retry: Int
        let cancelled: Bool
    }

    private enum ControllerTarget: Hashable {
        case retry, play, like, follow, video, track(UUID), playTrack(UUID)
    }

    private enum Details {
        case track(UUID, MusicResponse)
        case artist(PersonProfileResponse)
        case client(ClientProfileResponse)
        case story(StoryResponse)
        case musicComment(UUID, MusicResponse, MusicCommentItemResponse)
        case musicVideo(MusicResponse)
    }

    let route: MusicDestination
    let model: MusicHomeViewModel
    let deepLink: MizonDeepLinkRouter.AuthorizedLink?
    let controllerIsCurrent: Bool
    let open: (MusicDestination) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.controllerInputSuspended) private var controllerInputSuspended
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(macOS)
    @Environment(\.appearsActive) private var appearsActive
    #endif
    @State private var controllerFocus: ControllerTarget?
    @State private var controllerScroll = ScrollPosition(edge: .top)
    @State private var offset: CGFloat = 0
    @State private var details: Details?
    @State private var tracks: [MusicTabMusicItemResponse] = []
    @State private var loading = true
    @State private var failed = false
    @State private var updating = false
    @State private var video: AVPlayer?
    @State private var loadID = 0
    @State private var artistHeaderWidth: CGFloat = 0
    @State private var resolvedDeepLink: UUID?
    @State private var cancelledDeepLink: UUID?
    @State private var downloadCompleted = false
    private var localization = AuthLocalization()

    init(route: MusicDestination, model: MusicHomeViewModel, deepLink: MizonDeepLinkRouter.AuthorizedLink? = nil,
         controllerIsCurrent: Bool, open: @escaping (MusicDestination) -> Void) {
        self.route = route
        self.model = model
        self.deepLink = deepLink
        self.controllerIsCurrent = controllerIsCurrent
        self.open = open
    }

    var body: some View {
        ScrollViewReader { proxy in
            contentScroll
                .onChange(of: controllerFocus) {
                    guard let controllerFocus else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                        proxy.scrollTo(controllerFocus, anchor: .center)
                    }
                }
        }
        .navigationTitle(title)
        #if os(iOS)
        .toolbar(.visible, for: .navigationBar)
        #else
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
        #endif
        .task(id: loadIdentity) {
            if !loadIdentity.cancelled { await load() }
        }
        .onReceive(MizonDeepLinkRouter.shared.$authorized) { authorized in
            if let deepLink, resolvedDeepLink != deepLink.id, authorized != deepLink {
                cancelledDeepLink = deepLink.id
                loading = false
            }
        }
        .task(id: ownsController) {
            if ownsController { await observeController() }
        }
        .onDisappear {
            video?.pause()
            if let deepLink, resolvedDeepLink != deepLink.id {
                resolvedDeepLink = deepLink.id
                MizonDeepLinkRouter.shared.fail(deepLink, code: "page_changed",
                                               message: "The active page changed before navigation completed.")
            }
        }
    }

    private var contentScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if case .section(let section) = route {
                    sectionLanding(section)
                } else {
                    if let details { content(details) }
                    if loading { ProgressView().accessibilityLabel(text("LoadingMusic")) }
                    if failed {
                        Text(text("FeatureServiceFailed")).foregroundStyle(.secondary)
                        Button(text("Retry")) { loadID += 1 }.buttonStyle(.glass).modifier(outline(.retry))
                    }
                }
            }
            .frame(maxWidth: contentWidth, alignment: .leading)
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .scrollPosition($controllerScroll)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: {
            _, offset in self.offset = offset
        }
    }

    private var loadIdentity: LoadIdentity {
        LoadIdentity(requestID: deepLink?.id, retry: loadID,
                     cancelled: deepLink.map { cancelledDeepLink == $0.id } ?? false)
    }

    private var contentWidth: CGFloat {
        if case .artist(let artist)? = details, artist.modelMediaPublicId != nil { return .infinity }
        return 700
    }

    private var title: String {
        if case .section(let section) = route {
            return localization.string(section.resourceKey + "Title", table: "ShellShortcuts")
        }
        switch details {
        case .track(_, let item), .musicComment(_, let item, _), .musicVideo(let item):
            return localized(item.title, item.persianTitle)
        case .artist(let item): return "\(item.firstName) \(item.lastName)"
        case .client(let item): return item.nickName ?? [item.firstName, item.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        case .story(let item): return item.title ?? text("Story")
        case nil: return text("PageName")
        }
    }

    private func sectionLanding(_ section: ShellShortcutDestination) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: section.symbol)
                .font(.system(size: 44))
                .foregroundStyle(MizonPalette.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(localization.font(24, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(localization.string(section == .vpn ? "VpnUnavailable" : "SectionEmpty", table: "ShellShortcuts"))
                .font(localization.font(13))
                .foregroundStyle(MizonPalette.secondaryText)
        }
        .padding(28)
        .frame(maxWidth: 480, alignment: .leading)
        .background(MusicHomeChrome.controlFill, in: .rect(cornerRadius: 20))
        .frame(maxWidth: .infinity)
        .environment(\.layoutDirection, localization.isPersian ? .rightToLeft : .leftToRight)
        .accessibilityIdentifier("mizon.section.\(section.rawValue)")
    }

    @ViewBuilder private func content(_ details: Details) -> some View {
        switch details {
        case .track(let id, let track):
            trackDetails(track, id: id)
        case .musicComment(let id, let track, let comment):
            highlightedComment(comment)
            trackDetails(track, id: id)
        case .musicVideo(let track):
            if let video {
                VideoPlayer(player: video)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(.rect(cornerRadius: 12))
                    .accessibilityIdentifier("music.destination.video")
                    .modifier(outline(.video))
            }
            Text(localized(track.title, track.persianTitle))
                .font(localization.font(27, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
        case .artist(let artist):
            if let mediaID = artist.modelMediaPublicId {
                artistModelHeader(artist, mediaID: mediaID)
            } else {
                artistCover(artist)
                    .frame(height: 212)
                    .clipShape(.rect(cornerRadius: 12))
                artistIdentity(artist)
            }
            rows
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
        case .client(let item):
            MusicArtwork(mediaID: item.profileMediaPublicId, model: model, symbol: "person.fill")
                .frame(width: 118, height: 118)
                .background(MusicHomeStyle.inset)
                .clipShape(.circle)
            Text(title).font(localization.font(25, weight: .semibold)).accessibilityAddTraits(.isHeader)
            if let username = item.username, !username.isEmpty {
                Text("@" + username).font(localization.font(12)).foregroundStyle(MusicHomeStyle.cyan)
            }
        case .story(let story):
            if let video {
                VideoPlayer(player: video).frame(height: 370).clipShape(.rect(cornerRadius: 12))
                    .modifier(outline(.video))
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
            .buttonStyle(.glass).disabled(updating).modifier(outline(.like))
            ForEach(story.widgets, id: \.publicId) { widget in
                if let music = widget.music {
                    Button { open(.track(music.musicPublicId)) } label: {
                        Label(music.title, systemImage: "music.note")
                    }
                    .modifier(outline(.track(music.musicPublicId)))
                }
            }
        }
    }

    @ViewBuilder private func trackDetails(_ track: MusicResponse, id: UUID) -> some View {
        MusicArtwork(mediaID: track.musicCover?.mediaPublicId, model: model, symbol: "music.note")
            .frame(height: 280).clipShape(.rect(cornerRadius: 12))
        Text(localized(track.title, track.persianTitle)).font(localization.font(27, weight: .semibold))
            .accessibilityAddTraits(.isHeader)
        Text(track.musicGenres.map { localized($0.title, $0.persianTitle) }.joined(separator: " · "))
            .foregroundStyle(.secondary)
        HStack {
            Button { model.play(id, title: title) } label: { Label(text("PlayInMizon"), systemImage: "play.fill") }
                .modifier(outline(.play))
            Button { Task { await like(track, id: id) } } label: {
                Label(text(track.likedByMe ? "UnlikeTrack" : "LikeTrack"), systemImage: track.likedByMe ? "heart.fill" : "heart")
            }
            .disabled(updating)
            .modifier(outline(.like))
        }
        .buttonStyle(.glass)
        if downloadCompleted {
            Label(localization.string("MusicDownloaded", table: "MusicDeepLinks"), systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func highlightedComment(_ comment: MusicCommentItemResponse) -> some View {
        HStack(alignment: .top, spacing: 12) {
            MusicArtwork(mediaID: comment.profileMediaPublicId, model: model, symbol: "person.fill")
                .frame(width: 34, height: 34).clipShape(.circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(localization.string("LinkedComment", table: "MusicDeepLinks"))
                    .font(localization.font(12, weight: .semibold)).accessibilityAddTraits(.isHeader)
                let name = [comment.firstName, comment.lastName].filter { !$0.isEmpty }.joined(separator: " ")
                if !name.isEmpty {
                    Text(name).font(localization.font(13, weight: .semibold))
                } else if let username = comment.username {
                    Text("@" + username).font(localization.font(13, weight: .semibold))
                }
                Text(comment.text).font(localization.font(14)).textSelection(.enabled)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MizonPalette.accent.opacity(0.10), in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(MizonPalette.accent.opacity(0.38)) }
        .environment(\.layoutDirection, localization.isPersian ? .rightToLeft : .leftToRight)
        .accessibilityIdentifier("music.destination.linkedComment")
    }

    private func artistCover(_ artist: PersonProfileResponse) -> some View {
        MusicArtwork(mediaID: artist.coverMediaPublicId ?? artist.profileMediaPublicId,
                     model: model, symbol: "person.crop.circle")
    }

    private func artistIdentity(_ artist: PersonProfileResponse) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title)
                    .font(localization.font(25, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if artist.canFollow {
                    Button(text(artist.isFollowing ? "Following" : "Follow")) { Task { await follow(artist) } }
                        .buttonStyle(.glass)
                        .disabled(updating)
                        .modifier(outline(.follow))
                }
            }
            Label(artist.followersCount.formatted(), systemImage: "person.2").foregroundStyle(.secondary)
        }
    }

    private func artistModelHeader(_ artist: PersonProfileResponse, mediaID: UUID) -> some View {
        let stacked = artistHeaderWidth < 600
        let sizing: (modelHeight: CGFloat, minHeaderHeight: CGFloat?, modelFraction: CGFloat) = switch artistHeaderWidth {
        case ..<600: (220, nil, 1)
        case ..<1040: (288, 336, 1.15 / 2.15)
        case ..<1450: (350, 374, 0.5)
        default: (420, 450, 0.5)
        }
        let layout = stacked
            ? AnyLayout(VStackLayout(spacing: 0))
            : AnyLayout(HStackLayout(spacing: 0))
        let modelWidth = stacked ? nil : artistHeaderWidth * sizing.modelFraction
        let featured = model.artists.first {
            $0.personPublicId == artist.personPublicId && $0.modelMediaPublicId == mediaID
        }
        let yaw = artist.modelYawInDegrees.flatMap { $0.isFinite ? $0 : nil }
            ?? featured.flatMap { $0.modelYawInDegrees.isFinite ? $0.modelYawInDegrees : nil }
            ?? (0.24 * 180 / .pi)
        let configuration = MusicArtistModel.Configuration(
            mediaID: mediaID,
            portraitMediaID: artist.profileMediaPublicId,
            yaw: yaw,
            attribution: featured?.modelAttribution
        )
        return layout {
            artistIdentity(artist)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            MusicArtistModel(configuration: configuration, model: model, rotateHint: text("RotateHint"),
                             resetLabel: text("ResetModel"))
                .frame(maxWidth: .infinity)
                .frame(width: modelWidth, height: sizing.modelHeight)
        }
        .frame(maxWidth: .infinity, minHeight: sizing.minHeaderHeight)
        .background {
            artistCover(artist)
                .overlay {
                    LinearGradient(colors: [MizonPalette.surface.opacity(0.92), MizonPalette.surface.opacity(0.38)],
                                   startPoint: stacked ? .top : .leading,
                                   endPoint: stacked ? .bottom : .trailing)
                }
                .allowsHitTesting(false)
        }
        .clipShape(.rect(cornerRadius: 12))
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { artistHeaderWidth = $0 }
    }

    private var rows: some View {
        LazyVStack(spacing: 8) {
            ForEach(tracks, id: \.publicId) { track in
                HStack {
                    NavigationLink(value: MusicDestination.track(track.publicId)) {
                        HStack(spacing: 10) {
                            MusicArtwork(mediaID: track.coverMediaPublicId, model: model, symbol: "music.note")
                                .frame(width: 44, height: 44).clipShape(.rect(cornerRadius: 8))
                            Text(localized(track.title, track.persianTitle)).lineLimit(1)
                        }
                    }
                    .modifier(outline(.track(track.publicId)))
                    Spacer()
                    Button { model.play(track.publicId, title: localized(track.title, track.persianTitle)) } label: {
                        Image(systemName: "play.fill")
                    }
                    .buttonStyle(.glass).accessibilityLabel(text("PlayInMizon"))
                    .modifier(outline(.playTrack(track.publicId)))
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
            try checkNavigation()
            switch route {
            case .section(let section):
                if section == .vpn, let request = deepLink {
                    resolvedDeepLink = request.id
                    MizonDeepLinkRouter.shared.fail(request, code: "page_unavailable",
                        message: "VPN is not available on this platform.")
                } else {
                    completeDeepLink(stage: .opened)
                }
                return
            case .track(let id):
                let track: MusicResponse
                if case .track(let loadedID, let loadedTrack) = details, loadedID == id {
                    track = loadedTrack
                } else {
                    track = try await model.service.track(id, session: model.session)
                    try checkNavigation()
                    details = .track(id, track)
                }
                try await performTrackAction(id, track: track)
            case .musicComment(let id, let commentID):
                async let info = model.service.track(id, session: model.session)
                let comment = try await model.service.trackComment(commentID, musicID: id, session: model.session)
                let track = try await info
                try checkNavigation()
                guard let comment else { throw LoginFailure.invalidResponse }
                details = .musicComment(id, track, comment)
            case .musicVideo(let id):
                let track = try await model.service.track(id, session: model.session)
                try checkNavigation()
                guard let mediaID = track.musicVideo?.mediaPublicId else { throw LoginFailure.invalidResponse }
                video = try await makeVideo(mediaID)
                details = .musicVideo(track)
            case .client(let id):
                if case .client(let currentProfile) = details, currentProfile.clientPublicId == id { break }
                let client = try await model.service.client(id, session: model.session)
                try checkNavigation()
                guard deepLink == nil || client.clientPublicId == id else { throw LoginFailure.invalidResponse }
                details = .client(client)
            case .artist(let id):
                async let artist = model.service.artist(id, session: model.session)
                async let music = model.service.artistMusic(id, after: nil, session: model.session)
                let profile = try await artist
                try checkNavigation()
                guard deepLink == nil || profile.personPublicId == id else { throw LoginFailure.invalidResponse }
                details = .artist(profile)
                // The profile is a distinct result. The supplementary track list can load independently.
                completeDeepLink(stage: .completed)
                let artistTracks = try await music.musics
                try checkNavigation()
                tracks = artistTracks
            case .playlist, .playlistLibrary:
                return
            case .story(let id):
                let story = try await model.service.story(id, session: model.session)
                try checkNavigation()
                guard deepLink == nil || story.publicId == id else { throw LoginFailure.invalidResponse }
                details = .story(story)
                if story.storyContentTypeTitle.localizedCaseInsensitiveContains("video") {
                    let player = try await makeVideo(story.contentMediaPublicId)
                    try checkNavigation()
                    video = player
                    player.play()
                } else if deepLink != nil {
                    _ = try await model.artwork.image(story.contentMediaPublicId, session: model.session)
                    try checkNavigation()
                }
                if !story.viewedByMe,
                   let viewed = try? await model.service.markStoryViewed(id, session: model.session) {
                    try checkNavigation()
                    model.updateStoryView(viewed)
                    details = .story(viewed)
                }
            }
            try checkNavigation()
            completeDeepLink(stage: .completed)
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled {
                failed = true
                if let request = deepLink, resolvedDeepLink != request.id {
                    resolvedDeepLink = request.id
                    let profile: Bool = switch route {
                    case .artist, .client: true
                    default: false
                    }
                    MizonDeepLinkRouter.shared.fail(
                        request, code: profile ? "profile_unavailable" : "page_unavailable",
                        message: profile ? "The profile could not be loaded." : "The requested content could not be loaded.")
                }
            }
        }
    }

    private func completeDeepLink(stage: MizonDeepLinkResult.Stage) {
        guard let request = deepLink, resolvedDeepLink != request.id else { return }
        resolvedDeepLink = request.id
        MizonDeepLinkRouter.shared.complete(request, stage: stage)
    }

    private func checkNavigation() throws {
        try Task.checkCancellation()
        if let deepLink, resolvedDeepLink != deepLink.id, !MizonDeepLinkRouter.shared.isActive(deepLink) {
            throw CancellationError()
        }
    }

    private func performTrackAction(_ id: UUID, track: MusicResponse) async throws {
        guard let request = deepLink, resolvedDeepLink != request.id, case .track(_, let action) = request.route else { return }
        switch action {
        case .details, .video:
            return
        case .play:
            try await model.playFromDeepLink(id, title: localized(track.title, track.persianTitle)) {
                MizonDeepLinkRouter.shared.isActive(request)
            }
        case .download:
            try await model.artwork.cacheTrack(id, session: model.session)
            try checkNavigation()
            downloadCompleted = true
        }
    }

    private func makeVideo(_ mediaID: UUID) async throws -> AVPlayer {
        let url = try await model.artwork.playableURL(mediaID, session: model.session)
        try checkNavigation()
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else { throw LoginFailure.invalidResponse }
        try checkNavigation()
        return AVPlayer(playerItem: AVPlayerItem(asset: asset))
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
            if case .musicComment(_, _, let comment) = details {
                details = .musicComment(id, updated, comment)
            } else {
                details = .track(id, updated)
            }
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

    private var ownsController: Bool {
        #if os(macOS)
        scenePhase == .active && appearsActive && !controllerInputSuspended && controllerIsCurrent
        #else
        scenePhase == .active && !controllerInputSuspended && controllerIsCurrent
        #endif
    }

    private var controllerTargets: [ControllerTarget] {
        if failed && !loading { return [.retry] }
        switch details {
        case .track, .musicComment: return updating ? [.play] : [.play, .like]
        case .musicVideo: return video == nil ? [] : [.video]
        case .artist(let artist):
            let actions: [ControllerTarget] = artist.canFollow && !updating ? [.follow] : []
            return actions + tracks.flatMap { [.track($0.publicId), .playTrack($0.publicId)] }
        case .story(let story):
            let playback: [ControllerTarget] = video == nil ? [] : [.video]
            let reactions: [ControllerTarget] = updating ? [] : [.like]
            let links: [ControllerTarget] = story.widgets.compactMap { $0.music.map { .track($0.musicPublicId) } }
            return playback + reactions + links
        case .client, nil: return []
        }
    }

    private func observeController() async {
        await GamepadControls.observe(when: { ownsController }) { action in
            switch action {
            case .back: dismiss()
            case .accept, .submit:
                if let controllerFocus, controllerTargets.contains(controllerFocus) { activate(controllerFocus) }
                else { controllerFocus = controllerTargets.first }
            case .primary, .reset: controllerFocus = controllerTargets.first
            case .scroll:
                if let step = action.scrollStep { controllerScroll.scrollTo(y: max(0, offset + step)) }
            default:
                if let step = action.focusStep { controllerFocus = controllerTargets.gamepadTarget(from: controllerFocus, step: step) }
            }
        }
    }

    private func activate(_ target: ControllerTarget) {
        switch target {
        case .retry: loadID += 1
        case .video:
            if video?.rate == 0 { video?.play() } else { video?.pause() }
        case .follow:
            if case .artist(let artist) = details { Task { await follow(artist) } }
        case .play:
            switch details {
            case .track(let id, _), .musicComment(let id, _, _): model.play(id, title: title)
            default: break
            }
        case .like:
            switch details {
            case .track(let id, let track), .musicComment(let id, let track, _): Task { await like(track, id: id) }
            case .story(let story): Task { await like(story) }
            default: break
            }
        case .track(let id): open(.track(id))
        case .playTrack(let id):
            if let track = tracks.first(where: { $0.publicId == id }) {
                model.play(id, title: localized(track.title, track.persianTitle))
            }
        }
    }

    private func outline(_ target: ControllerTarget) -> some ViewModifier {
        ControllerOutline(target: target, focused: controllerFocus == target)
    }

    private struct ControllerOutline: ViewModifier {
        let target: ControllerTarget
        let focused: Bool

        func body(content: Content) -> some View {
            content.overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(focused ? MizonPalette.accent : .clear, lineWidth: 2)
                    .allowsHitTesting(false)
            }
            .id(target)
        }
    }

    private func localized(_ title: String, _ persian: String?) -> String {
        if localization.isPersian, let persian, !persian.isEmpty { return persian }
        return title
    }
    private func text(_ key: String) -> String { localization.string(key, table: "MusicHome") }
}
#endif
