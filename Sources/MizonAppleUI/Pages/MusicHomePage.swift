#if os(macOS) || os(iOS)
import AVKit
import GameController
import MizonAPIClient
import MizonAppleCore
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum MusicDestination: Hashable, Identifiable {
    case track(UUID), artist(UUID), playlist(UUID), story(UUID)

    var id: Self { self }
}

struct MusicHomePage: View {
    private enum Action: Hashable {
        case search, previousFeature, nextFeature, rotateFeatures, playFeature, likeFeature, openFeature
        case allGenres, genre(UUID), story(UUID), profile(UUID), follow(UUID), artistTrack(UUID)
        case playlist(UUID), library, activity(String), moreActivity, recent, news(Int), transport
        case rhythmDay(Int), previousNews, nextNews, toggleNews, selectNews(Int), spotlightTrack(UUID)
        case addStory, mutePreview, copyFeatureLink, previousSpotlight, nextSpotlight
        case previousArtistRail, nextArtistRail, spotlightProfile(UUID), spotlightFollow(UUID)
        case refresh(MusicHomeService.Section)
    }

    @State private var model: MusicHomeViewModel
    @State private var destination: MusicDestination?
    @State private var showingSearch = false
    @State private var showingLibrary = false
    @State private var selectedRhythmDay = 5
    @State private var selectedGenre: UUID?
    @State private var showingStoryPreview = false
    @State private var copiedFeatureLink = false
    @State private var spotlightIndex = 0
    @State private var artistRailPosition: UUID?
    @State private var featureIndex = 0
    @State private var featurePaused = false
    @State private var heroVisible = false
    @State private var previewPlayer: AVPlayer?
    @State private var previewMuted = true
    @State private var previewVolume: Double = 0.7
    @State private var showingPreviewControls = false
    @State private var fullWindowVideo = false
    @State private var exportRequest: MusicFeatureItemResponse?
    @State private var exportFile: MusicFeatureExport?
    @State private var exportPresented = false
    @State private var exportStatus: String?
    @State private var newsIndex = 0
    @State private var newsPaused = false
    @State private var newsVisible = false
    @State private var article: Int?
    @State private var recentScrollRequest = 0
    @FocusState private var controlFocus: Action?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    private var localization = AuthLocalization()

    let displayName: String?
    let avatar: CGImage?
    let profileTransition: Namespace.ID
    let signOut: () -> Void

    init(session: AuthSession, service: MusicHomeService, displayName: String?, avatar: CGImage?,
         profileTransition: Namespace.ID, signOut: @escaping () -> Void) {
        _model = State(initialValue: MusicHomeViewModel(session: session, service: service))
        self.displayName = displayName
        self.avatar = avatar
        self.profileTransition = profileTransition
        self.signOut = signOut
    }

    private var currentFeature: MusicFeatureItemResponse? {
        model.features.indices.contains(featureIndex) ? model.features[featureIndex] : model.features.first
    }

    private var currentArtist: FeaturedPersonItem? {
        model.artists.indices.contains(spotlightIndex) ? model.artists[spotlightIndex] : model.artists.first
    }

    private var discovery: [MusicDiscoverySample] {
        guard let genre = model.genres.first(where: { $0.publicId == selectedGenre }) else { return MusicDiscoverySample.all }
        let name = normalizedGenre(genre.title)
        let persian = normalizedGenre(genre.persianTitle ?? "")
        let filtered = MusicDiscoverySample.all.filter {
            normalizedGenre($0.genre) == name || normalizedGenre($0.persianGenre) == persian
        }
        return filtered.isEmpty ? MusicDiscoverySample.all : filtered
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in layout(width: geometry.size.width) }
                .navigationTitle(text("PageName"))
                .navigationDestination(item: $destination) { route in
                    MusicHomeDestinationView(route: route, model: model)
                }
                .toolbar { toolbar }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.playingTrack != nil || model.requestingPlayback { transport }
        }
        .environment(\.layoutDirection, localization.isPersian ? .rightToLeft : .leftToRight)
        .task { await model.refresh() }
        .task(id: scenePhase) {
            if scenePhase == .active { await observeGamepad() }
        }
        .sheet(isPresented: $showingSearch) {
            GlobalSearchPage(session: model.session, service: model.service.searchService) { id in
                showingSearch = false
                destination = .track(id)
            }
        }
        .sheet(isPresented: $showingLibrary) {
            MusicLibraryBrowser(model: model) { id in
                showingLibrary = false
                destination = .playlist(id)
            }
        }
        .sheet(isPresented: Binding(get: { article != nil }, set: { if !$0 { article = nil } })) {
            if let article { articleView(article) }
        }
        .alert(text("FeatureServiceFailed"), isPresented: $model.actionFailed) {
            Button(text("Close")) {}
        }
        .alert(text("NewStory"), isPresented: $showingStoryPreview) {
            Button(text("Close"), role: .cancel) {}
        } message: {
            Text(text("StoryPreviewExplanation"))
        }
        .alert(text("LinkCopied"), isPresented: $copiedFeatureLink) {
            Button(text("Close"), role: .cancel) {}
        }
        .fileExporter(isPresented: $exportPresented, item: exportFile,
                      defaultFilename: exportFile?.url.lastPathComponent) { result in
            exportFile = nil
            switch result {
            case .success: exportStatus = "Saved"
            case .failure: exportStatus = "SaveFailed"
            }
        } onCancellation: {
            exportFile = nil
        }
        .alert(text(exportStatus ?? "Saved"), isPresented: Binding(
            get: { exportStatus != nil }, set: { if !$0 { exportStatus = nil } }
        )) { Button(text("Close"), role: .cancel) {} }
        .task(id: exportRequest?.publicId) {
            guard let item = exportRequest else { return }
            defer { if !Task.isCancelled { exportRequest = nil } }
            do {
                let url = try await model.artwork.file(item.mediaPublicId, session: model.session,
                                                       maximumBytes: 128 * 1024 * 1024)
                try Task.checkCancellation()
                exportFile = MusicFeatureExport(url: url)
                exportPresented = true
            } catch {
                if !Task.isCancelled { exportStatus = "SaveFailed" }
            }
        }
        .modifier(MusicFullWindowPresentation(isPresented: $fullWindowVideo) {
            if let previewPlayer {
                VStack(spacing: 12) {
                    VideoPlayer(player: previewPlayer)
                    Button(text("Close")) { fullWindowVideo = false }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                }
                .padding(16)
            }
        })
        .onDisappear { model.stop() }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            control(.search) { Image(systemName: "magnifyingglass") }
                .accessibilityLabel(localization.string("SearchPrompt", table: "Search"))
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                if let displayName, !displayName.isEmpty { Text(displayName) }
                Button(localization.string("SignOut", table: "Settings"), action: signOut)
            } label: {
                WelcomeProfileBadge(avatar: avatar)
                    .frame(width: 28, height: 28)
                    .matchedGeometryEffect(id: "welcome-profile", in: profileTransition)
            }
            .accessibilityLabel(displayName ?? text("Profile"))
        }
    }

    private func layout(width: CGFloat) -> some View {
        let wide = width >= 1440
        let medium = width >= 1040
        let margin: CGFloat = medium ? 28 : 14
        let contentWidth = min(2200, max(0, width - margin * 2))
        let rail = min(320, max(220, contentWidth * 0.2))
        let feedWidth = contentWidth - (wide ? 2 * (rail + 24) : medium ? rail + 20 : 0)
        return HStack(alignment: .top, spacing: wide ? 24 : 20) {
            if wide {
                ScrollView { editorialRail.padding(.bottom, 48) }
                    .scrollIndicators(.hidden)
                    .frame(width: rail)
            }
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        feature(width: feedWidth)
                        artistSpotlight
                        MusicStoryOrbit()
                        stories
                        genres
                        artists
                        discoveryRail(text("DiscoverNext"), subtitle: text("DiscoverNextSubtitle"), icon: "sparkle",
                                      color: musicColor("A9B8FF"), samples: Array(discovery.reversed().prefix(6)), compact: false)
                        discoveryRail(text("ReturnToMood"), subtitle: text("RecentlyPlayed"), icon: "clock.arrow.circlepath",
                                      color: musicColor("8BCBE2"), samples: Array((Array(discovery.dropFirst(2)) + discovery.prefix(2)).prefix(6)),
                                      compact: true)
                            .id(Action.recent)
                        if !medium { communityRail }
                        if !wide { editorialRail }
                        Divider()
                        Text(text("DemoFooter")).font(localization.font(9)).foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 48)
                }
                .scrollIndicators(.hidden)
                .onChange(of: controlFocus) { _, target in
                    if let target, target != .search, target != .recent { reader.scrollTo(target, anchor: .center) }
                }
                .onChange(of: recentScrollRequest) { reader.scrollTo(Action.recent, anchor: .top) }
            }
            if medium {
                ScrollView { communityRail.padding(.bottom, 48) }
                    .scrollIndicators(.hidden)
                    .frame(width: rail)
            }
        }
        .frame(maxWidth: 2200)
        .padding(.horizontal, margin)
        .padding(.top, medium ? 16 : 12)
        .frame(maxWidth: .infinity)
    }

    private func feature(width: CGFloat) -> some View {
        let height = min(340, max(190, width * 360 / 770))
        return Group {
            if let item = currentFeature {
                VStack(spacing: 12) {
                    ZStack(alignment: .bottomLeading) {
                        if let previewPlayer {
                            VideoPlayer(player: previewPlayer).allowsHitTesting(false)
                        } else {
                            MusicArtwork(mediaID: featureArtwork(item), model: model, symbol: "music.note")
                                .frame(height: height).clipped()
                        }
                        LinearGradient(colors: [.black.opacity(0.28), .black.opacity(0.15), .black.opacity(0.84)],
                                       startPoint: .top, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 9) {
                            Text(text("HeroName")).font(localization.font(10, weight: .semibold))
                                .tracking(2).foregroundStyle(musicColor(item.primaryAccentColor, fallback: .white))
                            Text(localized(item.title, item.persianTitle)).font(localization.font(width < 560 ? 23 : 30, weight: .semibold))
                                .lineLimit(2)
                            Text(item.contributors.map { "\($0.firstName) \($0.lastName)" }.joined(separator: " · "))
                                .font(localization.font(13)).foregroundStyle(.secondary).lineLimit(1)
                            HStack(spacing: 8) {
                                control(.playFeature) { Label(text("PlayInMizon"), systemImage: "play.fill") }
                                control(.openFeature) { Text(text("ViewTrack")) }
                                control(.likeFeature) { Image(systemName: item.likedByMe ? "heart.fill" : "heart") }
                                    .disabled(model.updating.contains(item.musicPublicId))
                                    .accessibilityLabel(text(item.likedByMe ? "UnlikeTrack" : "LikeTrack"))
                                if previewPlayer != nil {
                                    control(.mutePreview) {
                                        Image(systemName: previewMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    }
                                    .accessibilityLabel(text(previewMuted ? "UnmuteVideo" : "MuteVideo"))
                                }
                                Button { showingPreviewControls = true } label: {
                                    Image(systemName: "ellipsis")
                                }
                                .accessibilityLabel(text("PlayerControls"))
                                .popover(isPresented: $showingPreviewControls) { presentationControls(item) }
                            }
                            .buttonStyle(.glass)
                        }
                        .foregroundStyle(.white)
                        .padding(22)
                    }
                    .frame(height: height)
                    .clipShape(.rect(cornerRadius: 12))
                    HStack {
                        control(.previousFeature) { Image(systemName: "chevron.backward") }
                            .accessibilityLabel(text("PreviousFeature"))
                        ScrollView(.horizontal) {
                            HStack(spacing: 6) {
                                ForEach(Array(model.features.enumerated()), id: \.element.publicId) { index, preview in
                                    Button { selectFeature(index) } label: {
                                        MusicArtwork(mediaID: featureArtwork(preview),
                                                     model: model, symbol: "music.note")
                                            .frame(width: 52, height: 32)
                                            .clipShape(.rect(cornerRadius: 6))
                                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(
                                                index == featureIndex ? Color.accentColor : Color.clear, lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(localized(preview.title, preview.persianTitle))
                                    .accessibilityAddTraits(index == featureIndex ? .isSelected : [])
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        control(.rotateFeatures) { Image(systemName: featurePaused ? "play.fill" : "pause.fill") }
                            .accessibilityLabel(text(featurePaused ? "ResumePresentation" : "PausePresentation"))
                        control(.nextFeature) { Image(systemName: "chevron.forward") }
                            .accessibilityLabel(text("NextFeature"))
                    }
                    .buttonStyle(.glass)
                }
            } else {
                sectionStatus(.features, empty: "NoFeatures").frame(minHeight: height)
            }
        }
        .onScrollVisibilityChange { heroVisible = $0 }
        .task(id: PreviewIdentity(id: currentFeature?.publicId, visible: heroVisible && scenePhase == .active
                                  && !showingSearch && destination == nil && !model.isPlaying && !showingStoryPreview)) {
            previewPlayer?.pause()
            previewPlayer = nil
            guard heroVisible, scenePhase == .active, !showingSearch, destination == nil, !model.isPlaying, !showingStoryPreview,
                  let item = currentFeature, item.contentTypeCode.lowercased() == "video" else { return }
            do {
                let media = try await model.service.media(item.mediaPublicId, session: model.session)
                let url = try MusicHomeService.storageURL(media.storagePath)
                try Task.checkCancellation()
                let player = AVPlayer(url: url)
                player.isMuted = previewMuted
                player.volume = Float(previewVolume)
                previewPlayer = player
                if !featurePaused && !reduceMotion { player.play() }
            } catch {}
        }
        .task(id: FeatureTimer(index: featureIndex, count: model.features.count,
                               canRotate: heroVisible && !featurePaused && !reduceMotion && scenePhase == .active
                               && !showingPreviewControls && !fullWindowVideo)) {
            guard heroVisible, !featurePaused, !reduceMotion, !showingPreviewControls, !fullWindowVideo, scenePhase == .active,
                  model.features.count > 1, let currentFeature else { return }
            do {
                try await Task.sleep(for: .seconds(min(60, max(3, currentFeature.displaySeconds))))
                selectFeature(featureIndex + 1)
            } catch {}
        }
    }

    private func presentationControls(_ item: MusicFeatureItemResponse) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(text(featurePaused ? "ResumePresentation" : "PausePresentation")) { activate(.rotateFeatures) }
            if let previewPlayer {
                Slider(value: $previewVolume) { Text(text("VideoVolume")) }
                    .onChange(of: previewVolume) { _, value in previewPlayer.volume = Float(value) }
                MusicFeatureScrubber(player: previewPlayer, title: text("PresentationPosition"))
                Button(text("VideoFullWindow")) {
                    showingPreviewControls = false
                    fullWindowVideo = true
                }
            }
            Button(text("PlayInMizon")) {
                showingPreviewControls = false
                activate(.playFeature)
            }
            Button(text("SaveMedia")) {
                showingPreviewControls = false
                exportRequest = item
            }
            .disabled(exportRequest != nil)
            Button(text("CopyMusicLink")) {
                showingPreviewControls = false
                activate(.copyFeatureLink)
            }
            Button(text("RefreshFeatures")) {
                showingPreviewControls = false
                activate(.refresh(.features))
            }
        }
        .buttonStyle(.glass)
        .padding(16)
        .frame(minWidth: 240)
    }

    private struct PreviewIdentity: Equatable {
        let id: UUID?
        let visible: Bool
    }

    private func featureArtwork(_ item: MusicFeatureItemResponse) -> UUID? {
        item.contentTypeCode.lowercased() == "video" ? item.previewMediaPublicId ?? item.coverMediaPublicId : item.mediaPublicId
    }

    private struct FeatureTimer: Equatable {
        let index: Int
        let count: Int
        let canRotate: Bool
    }

    private var artistSpotlight: some View {
        Group {
            if let artist = currentArtist {
                ZStack(alignment: .bottomLeading) {
                    MusicArtwork(mediaID: artist.coverMediaPublicId ?? artist.profileMediaPublicId,
                                 model: model, symbol: "person.fill.viewfinder")
                    LinearGradient(colors: [.clear, .black.opacity(0.76)], startPoint: .top, endPoint: .bottom)
                        .allowsHitTesting(false)
                    if artist.modelMediaPublicId != nil {
                        MusicArtistModel(artist: artist, model: model, rotateHint: text("RotateHint"),
                                         resetLabel: text("ResetModel"))
                            .id(artist.personPublicId)
                            .frame(maxWidth: 320)
                            .padding(.trailing, 12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(text("ArtistLabel")).font(localization.font(11, weight: .semibold))
                        Text(artistName(artist)).font(localization.font(25, weight: .semibold)).lineLimit(1)
                        let genre = localized(artist.genreTitle ?? "", artist.persianGenreTitle)
                        if !genre.isEmpty { Text(genre).font(localization.font(11)).foregroundStyle(.white.opacity(0.7)) }
                        if !artist.latestMusics.isEmpty {
                            ScrollView(.horizontal) {
                                HStack(spacing: 7) {
                                    ForEach(artist.latestMusics.prefix(5), id: \.publicId) { track in
                                        control(.spotlightTrack(track.publicId)) {
                                            HStack(spacing: 5) {
                                                MusicArtwork(mediaID: track.coverMediaPublicId, model: model, symbol: "music.note")
                                                    .frame(width: 24, height: 24).clipShape(.rect(cornerRadius: 4))
                                                Text(localized(track.title, track.persianTitle)).font(localization.font(10))
                                                    .lineLimit(1)
                                            }
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.glass)
                            .scrollIndicators(.hidden)
                        }
                        HStack {
                            control(.spotlightProfile(artist.personPublicId)) { Text(text("ViewProfile")) }
                            if artist.canFollow { followButton(artist, inSpotlight: true) }
                        }
                        .buttonStyle(.glass)
                    }
                    .foregroundStyle(.white)
                    .padding(18)
                    if model.artists.count > 1 {
                        HStack(spacing: 8) {
                            control(.previousSpotlight) { Image(systemName: "chevron.backward") }
                                .accessibilityLabel(text("PreviousArtist"))
                            Text(String(format: "%02d / %02d", spotlightIndex + 1, model.artists.count))
                                .font(.caption.monospacedDigit())
                            control(.nextSpotlight) { Image(systemName: "chevron.forward") }
                                .accessibilityLabel(text("NextArtist"))
                        }
                        .buttonStyle(.glass)
                        .foregroundStyle(.white)
                        .padding(12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .frame(height: 212)
                .clipShape(.rect(cornerRadius: 12))
            } else {
                sectionStatus(.artists, empty: "FeaturedArtistsEmpty").frame(minHeight: 120)
            }
        }
    }

    private var stories: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(text("Stories"), icon: "circle.dashed", color: musicColor("EAA1C8"))
            if model.loading.contains(.stories) || model.failures.contains(.stories) {
                sectionStatus(.stories, empty: "NoStories")
            }
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    control(.addStory) { addStoryCard }
                        .buttonStyle(MusicHoverStyle())
                        .accessibilityLabel(text("AddStory"))
                    ForEach(model.stories, id: \.publicId) { story in
                        control(.story(story.publicId)) { storyCard(story) }
                            .buttonStyle(MusicHoverStyle())
                            .accessibilityHint(text("OpenStoryHelp"))
                    }
                    if model.stories.isEmpty, !model.loading.contains(.stories), !model.failures.contains(.stories) {
                        Text(text("NoStories")).font(localization.font(10)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true).frame(width: 150, alignment: .leading)
                    }
                }
                .padding(.vertical, 7)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var addStoryCard: some View {
        VStack(spacing: 12) {
            Text(text("YourStory")).font(localization.font(9)).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 19)).frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.1), in: .rect(cornerRadius: 8))
                .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor, lineWidth: 0.5) }
            Text(text("AddStory")).font(localization.font(11))
            Spacer(minLength: 0)
            Image(systemName: "plus").font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(12)
        .frame(width: 112, height: 216)
        .musicPanel(cornerRadius: 10)
    }

    private func storyCard(_ story: StoryListItemResponse) -> some View {
        let name = "\(story.creatorFirstName) \(story.creatorLastName)"
        let corners = UnevenRoundedRectangle(topLeadingRadius: 9, topTrailingRadius: 9)
        return VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                MusicArtwork(mediaID: story.previewMediaPublicId, model: model, symbol: "photo")
                LinearGradient(colors: [.black.opacity(0.43), .clear, .black.opacity(0.7)],
                               startPoint: .top, endPoint: .bottom)
                Text(text(story.viewedByMe ? "Viewed" : "New"))
                    .font(localization.font(8)).foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(.black.opacity(0.8), in: .rect(cornerRadius: 5))
                    .padding(8)
                if let title = story.title, !title.isEmpty {
                    Text(title).font(localization.font(9)).lineLimit(1).foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.black.opacity(0.8), in: .rect(cornerRadius: 5))
                        .padding(.bottom, 24).padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .frame(height: 162)
            .clipShape(corners)
            VStack(spacing: 4) {
                Text(name).font(localization.font(9)).lineLimit(1)
                Capsule().fill(Color.accentColor).frame(width: 18, height: 2)
            }
            .padding(.top, 25)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                let initials = [story.creatorFirstName, story.creatorLastName].compactMap(\.first)
                Text(String(initials)).font(localization.font(10, weight: .medium))
                    .frame(width: 40, height: 40)
                    .background(.thickMaterial, in: .rect(cornerRadius: 13))
                    .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(Color.accentColor) }
                    .offset(y: -20)
            }
            Spacer(minLength: 0)
        }
        .frame(width: 132, height: 216)
        .musicPanel(cornerRadius: 10)
        .accessibilityLabel(story.title ?? name)
    }

    private var genres: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                heading(text("MusicGenres"), icon: "music.quarternote.3", color: musicColor("8BCBE2"))
                Spacer(minLength: 8)
                if !model.genres.isEmpty {
                    control(.allGenres) { Label(text("AllGenres"), systemImage: "arrow.backward") }
                        .font(localization.font(10)).buttonStyle(.glass)
                }
            }
            Text(text("GenreHeading")).font(localization.font(11)).foregroundStyle(.secondary)
            if model.genres.isEmpty { sectionStatus(.genres, empty: "NoGenres") }
            if !model.genres.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 10) {
                        ForEach(model.genres, id: \.publicId) { genre in
                            control(.genre(genre.publicId)) { genreCard(genre) }
                                .buttonStyle(MusicHoverStyle())
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func genreCard(_ genre: MusicGenreTypeItemResponse) -> some View {
        let color = musicColor(genre.accentColorHex)
        let isSelected = selectedGenre == genre.publicId
        let title = genre.title.isEmpty ? localized(genre.title, genre.persianTitle) : genre.title
        let waveform = Image(systemName: "waveform")
        return ZStack(alignment: .bottomTrailing) {
            LinearGradient(colors: [color.opacity(0.24), color.opacity(0.01)],
                           startPoint: .topTrailing, endPoint: .bottomLeading)
            waveform.font(.system(size: 66, weight: .light))
                .foregroundStyle(color.opacity(0.12)).offset(x: 4, y: 10)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(localization.font(19, weight: .semibold)).lineLimit(1)
                        if let persian = genre.persianTitle, !persian.isEmpty {
                            Text(persian).font(WindowsTypography.iranSans(11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: genreSymbol(genre.iconSymbol))
                        .font(.system(size: 20)).foregroundStyle(.secondary)
                        .frame(width: 38, height: 38)
                        .background(color.opacity(0.1), in: .rect(cornerRadius: 8))
                        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(color, lineWidth: 0.5) }
                }
                Spacer(minLength: 6)
                HStack(spacing: 5) {
                    HStack(spacing: 5) {
                        Text(genre.musicsCount, format: .number).font(localization.font(12, weight: .semibold))
                        Text(text("Track")).font(localization.font(10)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.white.opacity(0.08), in: .rect(cornerRadius: 6))
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
        .frame(width: 194, height: 138)
        .clipShape(.rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(color.opacity(isSelected ? 0.88 : 0.28)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized(genre.title, genre.persianTitle))
        .accessibilityValue("\(genre.musicsCount.formatted()) \(text("Track"))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func genreSymbol(_ symbol: String) -> String {
        switch symbol.lowercased() {
        case "headphones": "headphones"
        case "drum", "drumkit": "drum"
        case "guitar": "guitars"
        case "piano": "pianokeys"
        case "microphone", "mic": "mic"
        case "soundwave", "waveform", "pulse": "waveform"
        default: "music.note"
        }
    }

    private var artists: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    heading(text("TopArtists"), icon: "headphones", color: musicColor("F1C27D"))
                    Spacer(minLength: 8)
                    artistRailControls
                }
                VStack(alignment: .leading, spacing: 9) {
                    heading(text("TopArtists"), icon: "headphones", color: musicColor("F1C27D"))
                    artistRailControls
                }
            }
            if model.artists.isEmpty { sectionStatus(.artists, empty: "FeaturedArtistsEmpty") }
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(model.artists, id: \.personPublicId) { artist in
                        VStack(alignment: .leading, spacing: 10) {
                            control(.profile(artist.personPublicId)) {
                                MusicArtwork(mediaID: artist.coverMediaPublicId ?? artist.profileMediaPublicId,
                                             model: model, symbol: "person.crop.circle")
                                    .frame(width: 200, height: 128).clipShape(.rect(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            Text(artistName(artist)).font(localization.font(16, weight: .semibold)).lineLimit(1)
                            Text(localized(artist.genreTitle ?? "", artist.persianGenreTitle))
                                .font(localization.font(11)).foregroundStyle(.secondary).lineLimit(1)
                            HStack(spacing: 8) {
                                if artist.canFollow { followButton(artist) }
                                if let track = artist.latestMusics.first {
                                    control(.artistTrack(track.publicId)) { Image(systemName: "play.fill") }
                                        .accessibilityLabel(localized(track.title, track.persianTitle))
                                }
                            }
                            .buttonStyle(.glass)
                        }
                        .padding(12)
                        .frame(width: 224)
                        .musicPanel(cornerRadius: 16)
                        .id(artist.personPublicId)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 6)
            }
            .scrollPosition(id: $artistRailPosition)
            .scrollIndicators(.hidden)
        }
    }

    private var artistRailControls: some View {
        HStack(spacing: 6) {
            control(.previousArtistRail) { Image(systemName: "chevron.backward") }
                .accessibilityLabel(text("PreviousArtists")).disabled(model.artists.count < 2)
            Text(model.artists.count, format: .number)
                .font(localization.font(11)).frame(width: 32)
                .accessibilityLabel(text("ArtistCountHelp"))
                .accessibilityValue(model.artists.count.formatted())
            control(.nextArtistRail) { Image(systemName: "chevron.forward") }
                .accessibilityLabel(text("NextArtists")).disabled(model.artists.count < 2)
        }
        .buttonStyle(.glass)
    }

    private func followButton(_ artist: FeaturedPersonItem, inSpotlight: Bool = false) -> some View {
        control(inSpotlight ? .spotlightFollow(artist.personPublicId) : .follow(artist.personPublicId)) {
            Text(text(artist.isFollowing ? "Following" : "Follow"))
        }
        .disabled(model.updating.contains(artist.personPublicId))
    }

    private var editorialRail: some View {
        VStack(alignment: .leading, spacing: 18) {
            library
            weeklyRhythm
            latestNews
        }
    }

    private var communityRail: some View {
        VStack(alignment: .leading, spacing: 18) {
            trending
            activities
        }
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(widget("LibraryTitle"), icon: "music.note.list", color: musicColor("C7A0F6"))
            Text(widget("LibrarySubtitle")).font(localization.font(11)).foregroundStyle(.secondary)
            if let library = model.library {
                Text(library.totalPlaylistsCount, format: .number)
                    .font(localization.font(35, weight: .light)).foregroundStyle(musicColor("C7A0F6"))
                Text(widget("LibraryPersonal")).font(localization.font(10)).foregroundStyle(.secondary)
                ForEach(library.playlists, id: \.publicId) { playlist in
                    control(.playlist(playlist.publicId)) {
                        HStack(spacing: 8) {
                            MusicArtwork(mediaID: playlist.lastMusicCoverMediaPublicId, model: model, symbol: "music.note.list")
                                .frame(width: 36, height: 36).clipShape(.rect(cornerRadius: 6))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(playlist.title).font(localization.font(12, weight: .semibold)).lineLimit(1)
                                Text(playlist.lastUpdatedAt, format: .dateTime.month().day())
                                    .font(localization.font(10)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Text(playlist.musicsCount, format: .number).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(MusicHoverStyle())
                }
                if library.playlists.isEmpty { Text(widget("LibraryEmpty")).font(localization.font(11)).foregroundStyle(.secondary) }
                if library.totalPlaylistsCount > 0 {
                    control(.library) {
                        Text(widget("LibraryMore").replacingOccurrences(of: "{0:N0}",
                                                                         with: library.totalPlaylistsCount.formatted()))
                    }
                    .buttonStyle(.glass)
                }
            } else {
                sectionStatus(.library, empty: "LibraryError")
            }
            control(.recent) { Label(widget("LibraryRecent"), systemImage: "clock.arrow.circlepath") }
                .buttonStyle(.glass)
        }
        .musicWidget()
    }

    private var weeklyRhythm: some View {
        let days = [(38, 10), (54, 18), (46, 10), (66, 26), (52, 16), (72, 32), (62, 20)]
        return VStack(alignment: .leading, spacing: 12) {
            heading(widget("RhythmTitle"), icon: "chart.bar", color: musicColor("8BCBE2"))
            Text(widget("RhythmSubtitle")).font(localization.font(11)).foregroundStyle(.secondary)
            let total = days.reduce(0) { $0 + $1.0 + $1.1 }
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "%02d:%02d", total / 60, total % 60)).font(localization.font(29, weight: .light))
                    .accessibilityLabel(widget("RhythmHours"))
                Spacer()
                Text("+\(Int((Double(total - 442) / 442 * 100).rounded()))%")
                    .font(localization.font(10, weight: .semibold)).foregroundStyle(musicColor("93D9C0"))
                    .accessibilityHint(widget("RhythmComparison"))
            }
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(Array(days.enumerated()), id: \.offset) { day, minutes in
                    control(.rhythmDay(day)) {
                        VStack(spacing: 5) {
                            VStack(spacing: 2) {
                                Capsule().fill(musicColor("C7A0F6")).frame(width: 12, height: CGFloat(minutes.1) * 0.5)
                                Capsule().fill(musicColor("8BCBE2")).frame(width: 12, height: CGFloat(minutes.0) * 0.5)
                            }
                            Text(widget("Day\(day)Short")).font(localization.font(9)).lineLimit(1)
                        }
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(Color.accentColor.opacity(selectedRhythmDay == day ? 0.17 : 0), in: .rect(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(widget("Day\(day)"))
                    .accessibilityValue(rhythmDuration(minutes.0 + minutes.1))
                    .accessibilityAddTraits(selectedRhythmDay == day ? .isSelected : [])
                }
            }
            let day = days[selectedRhythmDay]
            HStack(spacing: 6) {
                Text(widget("Day\(selectedRhythmDay)"))
                Spacer()
                Text(rhythmDuration(day.0 + day.1)).monospacedDigit()
            }
            .font(localization.font(11, weight: .medium))
            Text(widget("RhythmDemo")).font(localization.font(10)).foregroundStyle(.secondary)
        }
        .musicWidget()
    }

    private func rhythmDuration(_ minutes: Int) -> String {
        String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    private var latestNews: some View {
        let covers = ["slow-motion", "artist-stage-02", "city-lights", "quiet-room"]
        return VStack(alignment: .leading, spacing: 12) {
            heading(widget("NewsTitle"), icon: "newspaper", color: musicColor("F1C27D"))
            Text(widget("NewsSubtitle")).font(localization.font(11)).foregroundStyle(.secondary)
            control(.news(newsIndex)) {
                VStack(alignment: .leading, spacing: 7) {
                    Image(covers[newsIndex], bundle: .module).resizable().scaledToFill()
                        .frame(height: 98).clipped().clipShape(.rect(cornerRadius: 8))
                    Text(widget("News\(newsIndex)Title")).font(localization.font(14, weight: .semibold))
                    Text(widget("News\(newsIndex)Summary")).font(localization.font(11)).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(MusicHoverStyle())
            HStack(spacing: 4) {
                ForEach(covers.indices, id: \.self) { index in
                    control(.selectNews(index)) {
                        Capsule().fill(index == newsIndex ? musicColor("F1C27D") : Color.secondary.opacity(0.34))
                            .frame(height: 3)
                            .padding(.vertical, 8).contentShape(.rect)
                    }
                    .accessibilityLabel(widget("News\(index)Title"))
                    .accessibilityAddTraits(index == newsIndex ? .isSelected : [])
                }
            }
            .buttonStyle(.plain)
            HStack {
                control(.previousNews) { Image(systemName: "chevron.backward") }
                    .accessibilityLabel(widget("NewsPrevious"))
                Spacer()
                control(.toggleNews) { Image(systemName: newsPaused ? "play.fill" : "pause.fill") }
                    .accessibilityLabel(widget(newsPaused ? "NewsResume" : "NewsPause"))
                Spacer()
                control(.nextNews) { Image(systemName: "chevron.forward") }
                    .accessibilityLabel(widget("NewsNext"))
            }
            .buttonStyle(.glass)
            Text(widget("NewsFooter")).font(localization.font(9)).foregroundStyle(.secondary)
        }
        .musicWidget()
        .onScrollVisibilityChange { newsVisible = $0 }
        .task(id: FeatureTimer(index: newsIndex, count: 4,
                              canRotate: newsVisible && !newsPaused && !reduceMotion && scenePhase == .active)) {
            guard newsVisible, !newsPaused, !reduceMotion, scenePhase == .active else { return }
            do {
                try await Task.sleep(for: .seconds(8))
                newsIndex = (newsIndex + 1) % 4
            } catch {}
        }
    }

    private var trending: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(widget("TrendingTitle"), icon: "chart.line.uptrend.xyaxis", color: musicColor("F1C27D"))
            Text(widget("TrendingSubtitle")).font(localization.font(11)).foregroundStyle(.secondary)
            ForEach(Array(discovery.sorted { $0.likes > $1.likes }.prefix(6).enumerated()), id: \.element.id) { rank, sample in
                HStack(spacing: 7) {
                    Text(rank + 1, format: .number).font(localization.font(10)).foregroundStyle(.secondary)
                        .frame(width: 17)
                    Image(sample.image, bundle: .module).resizable().scaledToFill()
                        .frame(width: 37, height: 37).clipped().clipShape(.rect(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(localized(sample.title, sample.persianTitle)).font(localization.font(12, weight: .semibold)).lineLimit(1)
                        Text(sample.artist).font(localization.font(10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .musicWidget()
    }

    private var activities: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(widget("FollowingTitle"), icon: "person.2", color: musicColor("93D9C0"))
            Text(widget("FollowingSubtitle")).font(localization.font(11)).foregroundStyle(.secondary)
            if let activity = model.activity {
                if activity.activities.isEmpty {
                    Text(widget(activity.hasFollowings ? "FollowingEmptyMusicDescription" : "FollowingNoFriendsDescription"))
                        .font(localization.font(11)).foregroundStyle(.secondary)
                }
                ForEach(activity.activities, id: \.activityId) { item in
                    control(.activity(item.activityId)) {
                        HStack(alignment: .top, spacing: 8) {
                            MusicArtwork(mediaID: item.profileMediaPublicId, model: model, symbol: "person.crop.circle.fill")
                                .frame(width: 34, height: 34).clipShape(.circle)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.nickName ?? [item.firstName, item.lastName].compactMap { $0 }.joined(separator: " "))
                                    .font(localization.font(12, weight: .semibold)).lineLimit(1)
                                Text(localized(item.title, item.persianTitle)).font(localization.font(11)).foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(MusicHoverStyle())
                    .disabled(activityDestination(item) == nil)
                }
                if activity.hasMore {
                    control(.moreActivity) { Text(widget("FollowingMore")) }
                        .buttonStyle(.glass).disabled(model.loading.contains(.activity))
                }
            } else {
                sectionStatus(.activity, empty: "FollowingError")
            }
        }
        .musicWidget()
    }

    private var transport: some View {
        HStack(spacing: 14) {
            Image(systemName: "music.note")
            Text(model.playbackTitle).font(localization.font(13, weight: .semibold)).lineLimit(1)
            Spacer()
            if model.requestingPlayback { ProgressView().controlSize(.small) }
            else {
                control(.transport) { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill") }
                    .accessibilityLabel(text(model.isPlaying ? "PausePresentation" : "ResumePresentation"))
                    .buttonStyle(.glass)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 14))
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func articleView(_ index: Int) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(widget("News\(index)Category")).font(localization.font(12)).foregroundStyle(.secondary)
                    Text(widget("News\(index)Title")).font(localization.font(25, weight: .semibold))
                    Text(widget("News\(index)Body")).font(localization.font(14))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            .toolbar { Button(text("Close")) { article = nil } }
        }
        #if os(macOS)
        .frame(minWidth: 430, minHeight: 320)
        #endif
    }

    private func discoveryRail(_ title: String, subtitle: String, icon: String, color: Color,
                               samples: [MusicDiscoverySample], compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(title, icon: icon, color: color)
            Text(subtitle).font(localization.font(10)).foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(samples) { sample in
                        sampleCard(sample, compact: compact)
                    }
                }
                .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func sampleCard(_ sample: MusicDiscoverySample, compact: Bool) -> some View {
        let label = VStack(alignment: .leading, spacing: 4) {
            Text(localized(sample.title, sample.persianTitle)).font(localization.font(14, weight: .semibold)).lineLimit(1)
            Text(sample.artist).font(localization.font(11)).foregroundStyle(.secondary).lineLimit(1)
            Text(localized(sample.genre, sample.persianGenre)).font(localization.font(10)).foregroundStyle(.secondary)
        }
        let artwork = Image(sample.image, bundle: .module).resizable().scaledToFill()
            .frame(width: compact ? 88 : 200, height: compact ? 88 : 156)
            .clipped().clipShape(.rect(cornerRadius: 10))
        return Group {
            if compact {
                HStack(spacing: 12) { label; Spacer(minLength: 0); artwork }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    artwork
                    label
                    Divider()
                    Label(sample.likes.formatted(), systemImage: "heart")
                        .font(localization.font(11)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(width: compact ? 300 : 224, alignment: .leading)
        .musicPanel(cornerRadius: 16)
    }

    private func sectionStatus(_ section: MusicHomeService.Section, empty: String) -> some View {
        HStack(spacing: 10) {
            if model.loading.contains(section) {
                ProgressView().controlSize(.small).accessibilityLabel(text("LoadingMusic"))
            } else {
                if model.failures.contains(section) {
                    let message = switch section {
                    case .features: text("FeaturesFailed")
                    case .artists: text("FeaturedArtistsError")
                    case .stories: text("StoriesFailed")
                    case .genres: text("GenresFailed")
                    case .library: widget("LibraryError")
                    case .activity: widget("FollowingError")
                    }
                    Text(message).foregroundStyle(.secondary)
                    control(.refresh(section)) { Text(text("Retry")) }.buttonStyle(.glass)
                } else {
                    Text(text(empty)).foregroundStyle(.secondary)
                }
            }
        }
        .font(localization.font(12))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heading(_ title: String, icon: String, color: Color) -> some View {
        Label {
            Text(title).font(localization.font(18, weight: .semibold)).foregroundStyle(.primary)
        } icon: {
            Image(systemName: icon).font(.system(size: 15, weight: .medium)).foregroundStyle(color)
        }
        .accessibilityAddTraits(.isHeader)
    }

    private func control<Label: View>(_ action: Action, @ViewBuilder label: () -> Label) -> some View {
        Button { activate(action) } label: { label() }
            .focusable()
            .focused($controlFocus, equals: action)
            .id(action)
            .authHandPointer(enabled: true)
            .overlay {
                if controlFocus == action {
                    RoundedRectangle(cornerRadius: 9).strokeBorder(Color.accentColor, lineWidth: 2).allowsHitTesting(false)
                }
            }
    }

    private func activate(_ action: Action) {
        switch action {
        case .search: showingSearch = true
        case .previousFeature: selectFeature(featureIndex - 1)
        case .nextFeature: selectFeature(featureIndex + 1)
        case .rotateFeatures:
            featurePaused.toggle()
            if featurePaused { previewPlayer?.pause() } else { previewPlayer?.play() }
        case .playFeature:
            if let item = currentFeature {
                destination = .track(item.musicPublicId)
                model.play(item.musicPublicId, title: localized(item.title, item.persianTitle))
            }
        case .openFeature:
            if let item = currentFeature { destination = .track(item.musicPublicId) }
        case .likeFeature:
            if let item = currentFeature { Task { await model.toggleLike(item) } }
        case .mutePreview:
            previewMuted.toggle()
            previewPlayer?.isMuted = previewMuted
        case .copyFeatureLink:
            guard let id = currentFeature?.musicPublicId else { return }
            let link = "mizon://music/\(id.uuidString.lowercased())"
            #if os(macOS)
            NSPasteboard.general.clearContents()
            copiedFeatureLink = NSPasteboard.general.setString(link, forType: .string)
            #else
            UIPasteboard.general.string = link
            copiedFeatureLink = true
            #endif
        case .previousSpotlight, .nextSpotlight:
            guard model.artists.count > 1 else { return }
            let next = spotlightIndex + (action == .nextSpotlight ? 1 : -1)
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                spotlightIndex = (next % model.artists.count + model.artists.count) % model.artists.count
            }
        case .previousArtistRail, .nextArtistRail:
            guard model.artists.count > 1 else { return }
            let index = model.artists.firstIndex { $0.personPublicId == artistRailPosition } ?? 0
            let next = min(model.artists.count - 1, max(0, index + (action == .nextArtistRail ? 1 : -1)))
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                artistRailPosition = model.artists[next].personPublicId
            }
        case .addStory: showingStoryPreview = true
        case .allGenres: selectedGenre = nil
        case .genre(let id): selectedGenre = selectedGenre == id ? nil : id
        case .story(let id): destination = .story(id)
        case .profile(let id), .spotlightProfile(let id): destination = .artist(id)
        case .follow(let id), .spotlightFollow(let id):
            if let item = model.artists.first(where: { $0.personPublicId == id }) { Task { await model.toggleFollow(item) } }
        case .artistTrack(let id), .spotlightTrack(let id): destination = .track(id)
        case .playlist(let id): destination = .playlist(id)
        case .library: showingLibrary = true
        case .activity(let id):
            if let item = model.activity?.activities.first(where: { $0.activityId == id }) { destination = activityDestination(item) }
        case .moreActivity: Task { await model.loadMoreActivity() }
        case .recent: recentScrollRequest += 1
        case .news(let index): article = index
        case .rhythmDay(let index): selectedRhythmDay = index
        case .previousNews: newsIndex = (newsIndex + 3) % 4
        case .nextNews: newsIndex = (newsIndex + 1) % 4
        case .toggleNews: newsPaused.toggle()
        case .selectNews(let index): newsIndex = index
        case .transport: model.togglePlayback()
        case .refresh(let section): Task { await model.refresh(section) }
        }
    }

    private func activityDestination(_ item: FollowingActivityItemResponse) -> MusicDestination? {
        if let id = item.storyPublicId { return .story(id) }
        if let id = item.musicPlaylistPublicId { return .playlist(id) }
        return item.musicPublicId.map(MusicDestination.track)
    }

    private var controllerTargets: [Action] {
        var targets: [Action] = [.search]
        if let item = currentFeature {
            targets += [.previousFeature, .playFeature, .openFeature, .nextFeature, .rotateFeatures]
            if !model.updating.contains(item.musicPublicId) { targets.append(.likeFeature) }
        }
        if previewPlayer != nil { targets.append(.mutePreview) }
        if let artist = currentArtist {
            if model.artists.count > 1 { targets += [.previousSpotlight, .nextSpotlight] }
            targets.append(.spotlightProfile(artist.personPublicId))
            if artist.canFollow, !model.updating.contains(artist.personPublicId) {
                targets.append(.spotlightFollow(artist.personPublicId))
            }
            targets += artist.latestMusics.prefix(5).map { .spotlightTrack($0.publicId) }
        }
        targets.append(.addStory)
        targets += model.stories.map { .story($0.publicId) }
        if !model.genres.isEmpty { targets.append(.allGenres) }
        targets += model.genres.map { .genre($0.publicId) }
        if model.artists.count > 1 { targets += [.previousArtistRail, .nextArtistRail] }
        targets += model.artists.map { .profile($0.personPublicId) }
        targets += model.artists.filter { $0.canFollow && !model.updating.contains($0.personPublicId) }.map { .follow($0.personPublicId) }
        targets += model.artists.compactMap { $0.latestMusics.first.map { .artistTrack($0.publicId) } }
        targets += model.library?.playlists.map { .playlist($0.publicId) } ?? []
        targets += model.activity?.activities.filter { activityDestination($0) != nil }.map { .activity($0.activityId) } ?? []
        if model.activity?.hasMore == true, !model.loading.contains(.activity) { targets.append(.moreActivity) }
        if (model.library?.totalPlaylistsCount ?? 0) > 0 { targets.append(.library) }
        targets += [.recent] + (0..<7).map(Action.rhythmDay)
        targets += [.news(newsIndex), .previousNews, .toggleNews, .nextNews] + (0..<4).map(Action.selectNews)
        if model.playingTrack != nil, !model.requestingPlayback { targets.append(.transport) }
        targets += MusicHomeService.Section.allCases.compactMap { model.failures.contains($0) ? .refresh($0) : nil }
        return targets
    }

    private func observeGamepad() async {
        var previous = 0
        var armed = false
        while !Task.isCancelled {
            if let pad = GCController.controllers().first(where: { $0.extendedGamepad != nil })?.extendedGamepad,
               destination == nil, !showingSearch, !showingLibrary, article == nil, !showingStoryPreview, !copiedFeatureLink, !model.actionFailed, !showingPreviewControls, !fullWindowVideo, !exportPresented {
                let horizontal = pad.dpad.xAxis.value
                let vertical = pad.dpad.yAxis.value
                let control = pad.buttonA.isPressed ? 1 : pad.buttonB.isPressed ? 2
                    : vertical < -0.65 || horizontal > 0.65 ? 3 : vertical > 0.65 || horizontal < -0.65 ? 4 : 0
                if control == 0 { armed = true }
                if armed, control != 0, control != previous {
                    let targets = controllerTargets
                    if control == 1 {
                        if let controlFocus, targets.contains(controlFocus) { activate(controlFocus) }
                        else { controlFocus = targets.first }
                    } else if control == 2 {
                        controlFocus = nil
                    } else if !targets.isEmpty {
                        let index = controlFocus.flatMap { targets.firstIndex(of: $0) }
                        let next = index.map { ($0 + (control == 3 ? 1 : targets.count - 1)) % targets.count } ?? 0
                        controlFocus = targets[next]
                    }
                }
                previous = control
            } else {
                previous = 0
                armed = false
            }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
    }

    private func selectFeature(_ index: Int) {
        guard !model.features.isEmpty else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
            featureIndex = (index + model.features.count) % model.features.count
        }
    }

    private func normalizedGenre(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "").replacingOccurrences(of: "ي", with: "ی")
            .replacingOccurrences(of: "ك", with: "ک").uppercased()
    }

    private func artistName(_ artist: FeaturedPersonItem) -> String { "\(artist.firstName) \(artist.lastName)" }
    private func localized(_ title: String, _ persian: String?) -> String {
        if localization.isPersian, let persian, !persian.isEmpty { return persian }
        return title
    }
    private func text(_ key: String) -> String { localization.string(key, table: "MusicHome") }
    private func widget(_ key: String) -> String { localization.string(key, table: "MusicWidgets") }
}

struct MusicArtwork: View {
    var mediaID: UUID?
    var model: MusicHomeViewModel
    var symbol: String
    @State private var image: CGImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle().fill(.white.opacity(0.05))
                if let image {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                } else {
                    Image(systemName: symbol).font(.system(size: min(30, geometry.size.height * 0.45)))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
        .task(id: mediaID) {
            image = nil
            guard let mediaID else { return }
            let fetched = try? await model.artwork.image(mediaID, session: model.session)
            guard !Task.isCancelled else { return }
            image = fetched
        }
    }
}

struct MusicHoverStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoveredLabel(content: configuration.label, pressed: configuration.isPressed)
    }

    private struct HoveredLabel<Content: View>: View {
        let content: Content
        let pressed: Bool
        @State private var hovered = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            content
                .contentShape(.rect)
                .background(Color.white.opacity(hovered ? 0.07 : 0), in: .rect(cornerRadius: 8))
                .scaleEffect(pressed ? 0.985 : 1)
                .authHandPointer(enabled: true)
                .onHover { hovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
        }
    }
}

extension View {
    func musicPanel(cornerRadius: CGFloat = 12) -> some View {
        background(.white.opacity(0.045), in: .rect(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.white.opacity(0.12)).allowsHitTesting(false))
    }

    func musicWidget() -> some View {
        frame(maxWidth: .infinity, alignment: .leading).padding(18).musicPanel()
    }
}

func musicColor(_ value: String?, fallback: Color = .accentColor) -> Color {
    guard let value else { return fallback }
    let hex = value.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
    guard hex.count == 6, let components = UInt32(hex, radix: 16) else { return fallback }
    return Color(red: Double((components >> 16) & 255) / 255,
                 green: Double((components >> 8) & 255) / 255, blue: Double(components & 255) / 255)
}
#endif
