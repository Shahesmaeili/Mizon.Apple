#if os(macOS) || os(iOS)
import AVKit
import GameController
import ImageIO
import MizonAPIClient
import MizonAppleCore
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

#if os(iOS)
private struct MusicHomePhoneHeaderGlass: View {
    let isRevealed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private let fadeDepth: CGFloat = 26

    var body: some View {
        Group {
            if reduceTransparency {
                MizonPalette.surface
            } else {
                WindowGlass(tintOpacity: 0.40)
                    .mask {
                        VStack(spacing: 0) {
                            Color.white
                            LinearGradient(stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white.opacity(0.86), location: 0.25),
                                .init(color: .white.opacity(0.45), location: 0.55),
                                .init(color: .white.opacity(0.12), location: 0.8),
                                .init(color: .clear, location: 1)
                            ], startPoint: .top, endPoint: .bottom)
                            .frame(height: fadeDepth)
                        }
                    }
                    .padding(.bottom, -fadeDepth)
                    .opacity(isRevealed ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isRevealed)
            }
        }
        .ignoresSafeArea(.container, edges: [.top, .horizontal])
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif

enum MusicDestination: Hashable, Identifiable {
    case track(UUID), artist(UUID), client(UUID), playlist(UUID), story(UUID)

    var id: Self { self }
}

struct MusicHomePage: View {
    enum Action: Hashable {
        case search, home, navigationOverflow, nearby, mood, previousFeature, nextFeature, rotateFeatures, playFeature, likeFeature, openFeature
        case featureControls, featureThumbnail(Int), retryFeatureMedia
        case allGenres, genre(UUID), story(UUID), profile(UUID), follow(UUID)
        case playlist(UUID), library, activity(String), moreActivity, recent, news(Int), transport
        case rhythmDay(Int), previousNews, nextNews, toggleNews, selectNews(Int), spotlightTrack(UUID)
        case addStory, mutePreview, copyFeatureLink, previousSpotlight, nextSpotlight
        case previousArtistRail, nextArtistRail, spotlightProfile(UUID), spotlightFollow(UUID)
        case refresh(MusicHomeService.Section)
    }

    @State var model: MusicHomeViewModel
    @State private var destination: MusicDestination?
    @State private var showingLibrary = false
    @State private var showingAllMusicActivity = false
    @State var selectedRhythmDay = 5
    @State private var selectedGenre: UUID?
    @State private var showingStoryPreview = false
    @State private var copiedFeatureLink = false
    @State private var spotlightIndex = 0
    @State private var spotlightDirection = 0
    @State private var artistRailPosition: UUID?
    @State private var featureIndex = 0
    @State private var featureDirection = 1
    @State private var heroHovered = false
    @State private var heroArtwork: FeatureArtwork?
    @State private var outgoingHeroArtwork: FeatureArtwork?
    @State private var heroArtworkStatus = FeatureMediaStatus.waiting
    @State private var heroVideoStatus = FeatureMediaStatus.waiting
    @State private var heroVideoEnded = false
    @State private var heroMediaRetry = 0
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
    @State var newsIndex = 0
    @State var newsPaused = false
    @State private var article: Int?
    @State private var recentScrollRequest = 0
    @State private var scrollHomeRequest = 0
    @State private var searchFocusRequest = 0
    @State private var pointer = MusicHomePointer()
    #if os(macOS)
    @State private var headerViewport = CGSize(width: 960, height: 700)
    @State private var pendingHeroVisibility: Bool?
    @State private var resumePreviewAfterScroll = false
    #else
    @State private var phoneHeaderHasScrolled = false
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif
    @State private var showingSearch = false
    @State private var showingNavigationOverflow = false
    @State private var navigationHasOverflow = false
    @State private var showingMoodPicker = false
    @State private var moodPress: UInt = 0
    @State private var nearbyAvatars = NearbyAvatarModel()
    @State private var showingNearby = false
    @State private var nearbyPress: UInt = 0
    @State private var navigationFocus = MusicHomeFocus()
    @FocusState private var controlFocus: Action?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var localization = AuthLocalization()

    let displayName: String?
    let nearby: NearbyDiscoveryModel
    let avatar: CGImage?
    let profileTransition: ProfilePictureTransition
    let initialMood: ClientMoodItemResponse?
    let signOut: () -> Void

    init(session: AuthSession, service: MusicHomeService, displayName: String?, nearby: NearbyDiscoveryModel,
         avatar: CGImage?, profileTransition: ProfilePictureTransition,
         initialMood: ClientMoodItemResponse? = nil, signOut: @escaping () -> Void) {
        _model = State(initialValue: MusicHomeViewModel(session: session, service: service, peerNetwork: nearby.peerNetwork))
        self.displayName = displayName
        self.nearby = nearby
        self.avatar = avatar
        self.profileTransition = profileTransition
        self.initialMood = initialMood
        self.signOut = signOut
    }

    private var currentFeature: MusicFeatureItemResponse? {
        model.features.indices.contains(featureIndex) ? model.features[featureIndex] : model.features.first
    }

    private var heroMediaFailed: Bool {
        guard let feature = currentFeature else { return false }
        return (isVideo(feature) ? heroVideoStatus : heroArtworkStatus) == .failed
    }

    private var currentArtist: FeaturedPersonItem? {
        model.artists.indices.contains(spotlightIndex) ? model.artists[spotlightIndex] : model.artists.first
    }

    var discovery: [MusicDiscoverySample] {
        guard let genre = model.genres.first(where: { $0.publicId == selectedGenre }) else { return MusicDiscoverySample.all }
        let name = normalizedGenre(genre.title)
        let persian = normalizedGenre(genre.persianTitle ?? "")
        let filtered = MusicDiscoverySample.all.filter {
            normalizedGenre($0.genre) == name || normalizedGenre($0.persianGenre) == persian
        }
        return filtered.isEmpty ? MusicDiscoverySample.all : filtered
    }

    private var discoveryRecommended: [MusicDiscoverySample] { Array(discovery.reversed().prefix(6)) }
    private var discoveryRecent: [MusicDiscoverySample] { Array((Array(discovery.dropFirst(2)) + discovery.prefix(2)).prefix(6)) }

    #if os(iOS)
    private var usesPhoneHeader: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    #endif

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                #if os(iOS)
                let feed = AnyView(layout(width: geometry.size.width))
                let topBar = AnyView(header(viewport: geometry.size, width: geometry.size.width))
                if usesPhoneHeader {
                    feed.safeAreaBar(edge: .top, spacing: 0) {
                        topBar
                            .padding(.top, verticalSizeClass == .compact ? 8 : 0)
                            .background {
                                MusicHomePhoneHeaderGlass(isRevealed: phoneHeaderHasScrolled)
                            }
                    }
                    .scrollEdgeEffectHidden(true, for: .top)
                } else {
                    feed.safeAreaInset(edge: .top, spacing: 0) { topBar }
                }
                #else
                layout(width: geometry.size.width)
                #endif
            }
                .coordinateSpace(.named(MusicHomePointer.coordinateSpace))
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location) where scenePhase == .active: pointer.location = location
                    default: pointer.location = nil
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { pointer.location = nil }
                }
                .onDisappear { pointer.location = nil }
                .environment(pointer)
                .navigationTitle("")
                #if os(macOS)
                .background {
                    MusicHomeFocusInput(input: navigationFocus).frame(width: 0, height: 0)
                }
                .onGeometryChange(for: CGSize.self, of: \.size) { headerViewport = $0 }
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        header(viewport: headerViewport, width: min(1120, max(230, headerViewport.width - 168)))
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
                #else
                .toolbar(.hidden, for: .navigationBar)
                .scrollContentBackground(.hidden)
                .containerBackground(for: .navigation) {
                    if usesPhoneHeader {
                        WindowGlass().ignoresSafeArea(.container, edges: .horizontal)
                    } else {
                        WindowGlass()
                    }
                }
                #endif
                .navigationDestination(item: $destination) { route in
                    MusicHomeDestinationView(route: route, model: model)
                }
        }
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.playingTrack != nil || model.requestingPlayback { transport }
        }
        .task { await model.refresh() }
        .task(id: nearbyAvatarUsernames) { [usernames = nearbyAvatarUsernames] in
            let service = model.service.nearbyProfileArtworkService
            let session = model.session
            let artwork = model.artwork
            await nearbyAvatars.load(for: usernames) { username in
                try await service.image(for: username, session: session, artwork: artwork)
            }
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await observeGamepad() }
        }
        .sheet(isPresented: $showingLibrary) {
            MusicLibraryBrowser(model: model) { id in
                showingLibrary = false
                destination = .playlist(id)
            }
        }
        .sheet(isPresented: $showingAllMusicActivity) {
            MusicHomeAllActivityPage(model: model) { item in
                showingAllMusicActivity = false
                destination = activityDestination(item)
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
                                                       maximumBytes: PeerMediaTransfer.maximumFileSize)
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

    private func header(viewport: CGSize, width: CGFloat) -> some View {
        let accountShape = UnevenRoundedRectangle(
            topLeadingRadius: 8, bottomLeadingRadius: 8, bottomTrailingRadius: 16, topTrailingRadius: 16)
        return MusicHomeHeader(width: width, showingOverflow: $showingNavigationOverflow,
                               onOverflowAvailabilityChange: setNavigationOverflowAvailability) { compactSearch in
            focusableControl(.search, cornerRadius: 8) {
                MusicHomeSearch(model: model, viewportWidth: viewport.width, compact: compactSearch,
                                focusRequest: $searchFocusRequest, showingSearch: $showingSearch) { result in
                    destination = result.kind == .music ? .track(result.publicID) : .client(result.publicID)
                }
            }
        } home: { compactTab in
            control(.home) {
                MusicHomeNavigationLabel(section: .music, compact: compactTab)
            }
            .buttonStyle(MusicHomeNavigationTabStyle(selected: true))
            .accessibilityLabel(text("ShellMusic"))
            .accessibilityAddTraits(.isSelected)
            .accessibilityIdentifier("music.home.tab")
        } overflow: { label in
            control(.navigationOverflow) { label }
                .buttonStyle(MusicHomeNavigationTabStyle(selected: false))
                .accessibilityLabel(text("ShellMoreTabs"))
                .accessibilityIdentifier("music.home.menu")
        } account: {
            HStack(spacing: 0) {
                nearbyControl(viewport: viewport)
                focusableControl(.mood, cornerRadius: 8) {
                    MusicHomeMoodButton(model: model, initialMood: initialMood, viewport: viewport,
                                        controllerPress: moodPress) { showingMoodPicker = $0 }
                        #if os(macOS)
                        .environment(navigationFocus)
                        #endif
                }
                Menu {
                    if let displayName, !displayName.isEmpty { Text(displayName) }
                    Button(text("Profile")) { destination = .client(model.session.clientPublicId) }
                    Button(localization.string("SignOut", table: "Settings"), action: signOut)
                } label: {
                    Color.clear
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 32, height: 32)
                // The native Mac menu can snapshot its label. Keep the portrait live as the session photo loads.
                .overlay {
                    MusicHomeProfilePicture(avatar: avatar, displayName: displayName)
                        .opacity(profileTransition.isInFlight ? 0 : 1)
                        .allowsHitTesting(false)
                }
                .background { profileTransition.anchor(.header) }
                .accessibilityLabel(displayName ?? text("Profile"))
                .accessibilityIdentifier("music.home.profile")
            }
            .background(MusicHomeChrome.controlFill, in: accountShape)
            .overlay { accountShape.strokeBorder(MusicHomeChrome.hairline).allowsHitTesting(false) }
        }
    }

    private func setNavigationOverflowAvailability(_ available: Bool) {
        navigationHasOverflow = available
        if !available {
            showingNavigationOverflow = false
            if controlFocus == .navigationOverflow { controlFocus = .home }
        }
    }

    private func nearbyControl(viewport: CGSize) -> some View {
        @Bindable var model = nearby
        return focusableControl(.nearby, cornerRadius: 8) {
            NearbyDevicesControl(peers: model.peers, avatars: nearbyAvatars.images, enabled: $model.enabled,
                                 status: model.status, viewport: viewport, controllerPress: nearbyPress) { showingNearby = $0 }
        }
    }

    private var nearbyAvatarUsernames: [String] {
        guard showingNearby, scenePhase != .background, nearby.enabled, nearby.status == .ready else { return [] }
        return NearbyAvatarModel.usernames(for: nearby.peers)
    }

    private func layout(width: CGFloat) -> some View {
        let wide = width >= 1440
        let medium = width >= 1040
        let margin: CGFloat = medium ? 28 : 14
        let topMargin: CGFloat = medium ? 16 : 12
        #if os(iOS)
        let scrollTopMargin: CGFloat? = usesPhoneHeader ? topMargin : nil
        let outerTopMargin = usesPhoneHeader ? 0 : topMargin
        #else
        let outerTopMargin = topMargin
        #endif
        let contentWidth = min(2200, max(0, width - margin * 2))
        let rail = min(320, max(220, contentWidth * 0.2))
        let feedWidth = max(0, contentWidth - (wide ? 2 * rail : medium ? rail : 0))
        return HStack(alignment: .top, spacing: 0) {
            if wide {
                ScrollView {
                    windowsEditorialRail(width: rail - 24)
                        .padding(.bottom, 48)
                        #if os(macOS)
                        .background { MusicHomeScrollSpeed().frame(width: 0, height: 0) }
                        #endif
                }
                    #if os(iOS)
                    .contentMargins(.top, scrollTopMargin, for: .scrollContent)
                    #endif
                    .scrollIndicators(.hidden)
                    .frame(width: rail - 24)
                    .padding(.trailing, 24)
            }
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        // Keep each deep section out of the feed's composite layout metadata.
                        AnyView(feature(width: feedWidth)).id(Action.home)
                        AnyView(artistSpotlight(width: feedWidth))
                        MusicStoryOrbit()
                        AnyView(stories)
                        AnyView(genres)
                        AnyView(artists)
                        AnyView(centralRails.discovery(title: text("DiscoverNext"), subtitle: text("DiscoverNextSubtitle"),
                                                      samples: discoveryRecommended, compact: false))
                        AnyView(centralRails.discovery(title: text("ReturnToMood"), subtitle: text("RecentlyPlayed"),
                                                      samples: discoveryRecent, compact: true)).id(Action.recent)
                        if !medium { AnyView(windowsCommunityRail(width: feedWidth)) }
                        if !wide { AnyView(windowsEditorialRail(width: feedWidth)) }
                        Rectangle().fill(MusicHomeChrome.hairline).frame(height: 1)
                        HStack(alignment: .top, spacing: 12) {
                            Text("MADE FOR YOUR MOMENTS").font(localization.font(9)).tracking(1.44)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(text("DemoFooter")).font(localization.font(9))
                                .frame(maxWidth: 220, alignment: .trailing)
                        }
                        .foregroundStyle(MizonPalette.secondaryText)
                    }
                    .frame(width: feedWidth, alignment: .leading)
                    .padding(.bottom, 48)
                    #if os(macOS)
                    .background { MusicHomeScrollSpeed().frame(width: 0, height: 0) }
                    #endif
                }
                .scrollClipDisabled()
                #if os(macOS)
                .onScrollPhaseChange { oldPhase, newPhase in
                    if oldPhase.isScrolling != newPhase.isScrolling {
                        pointer.setScrolling(newPhase.isScrolling)
                        if !newPhase.isScrolling { settleFeatureViewport() }
                    }
                }
                .onDisappear {
                    pointer.setScrolling(false)
                    pendingHeroVisibility = nil
                    resumePreviewAfterScroll = false
                }
                #else
                .contentMargins(.top, scrollTopMargin, for: .scrollContent)
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    usesPhoneHeader && geometry.contentOffset.y + geometry.contentInsets.top > 1
                } action: { _, hasScrolled in
                    phoneHeaderHasScrolled = hasScrolled
                }
                #endif
                .frame(width: feedWidth)
                .scrollIndicators(.hidden)
                .onChange(of: controlFocus) { _, target in
                    if navigationFocus.showsNavigationFocus, let target,
                       target != .search, target != .home, target != .navigationOverflow, target != .nearby,
                       target != .mood, target != .recent {
                        reader.scrollTo(target, anchor: .center)
                    }
                }
                .onChange(of: scrollHomeRequest) { reader.scrollTo(Action.home, anchor: .top) }
                .onChange(of: recentScrollRequest) { reader.scrollTo(Action.recent, anchor: .top) }
            }
            if medium {
                let gutter: CGFloat = wide ? 24 : 20
                ScrollView {
                    windowsCommunityRail(width: rail - gutter)
                        .padding(.bottom, 48)
                        #if os(macOS)
                        .background { MusicHomeScrollSpeed().frame(width: 0, height: 0) }
                        #endif
                }
                    #if os(iOS)
                    .contentMargins(.top, scrollTopMargin, for: .scrollContent)
                    #endif
                    .scrollIndicators(.hidden)
                    .frame(width: rail - gutter)
                    .padding(.leading, gutter)
            }
        }
        .frame(maxWidth: 2200)
        .padding(.horizontal, margin)
        .padding(.top, outerTopMargin)
        .frame(maxWidth: .infinity)
        #if os(macOS)
        .clipped()
        #endif
    }

    private func feature(width: CGFloat) -> some View {
        let surface = max(0, width - 16)
        let compact = surface < 560
        let height = min(340, max(190, surface * 360 / 770))
        return Group {
            if let item = currentFeature {
                heroSurface(item, compact: compact)
                    .frame(height: height)
                    .clipShape(.rect(cornerRadius: MusicFeaturedArtworkShadow.cornerRadius, style: .circular))
                    .background {
                        if let heroArtwork {
                            MusicFeaturedArtworkShadow(color: heroArtwork.edgeColor?.color ?? .black)
                        }
                    }
                    .modifier(MusicHeroLighting(active: canPresentFeature && !fullWindowVideo, palette: heroArtwork?.palette))
            } else if model.loading.contains(.features) {
                MusicHomeSkeleton(height: 300, label: text("LoadingFeatures"))
            } else {
                VStack(spacing: 12) {
                    Text(text(model.failures.contains(.features) ? "FeaturesFailed" : "NoFeatures"))
                        .font(localization.font(11))
                        .foregroundStyle(MusicHomeStyle.secondary)
                    control(.refresh(.features)) {
                        Label(text("Refresh"), systemImage: "arrow.clockwise")
                            .font(localization.font(10)).padding(.horizontal, 10).frame(height: 28)
                    }
                    .buttonStyle(MusicHomeButtonStyle(fill: MusicHomeStyle.inset, stroke: MusicHomeStyle.stroke))
                    .accessibilityLabel(text("RefreshMizonFeatures"))
                }
                .frame(maxWidth: .infinity, minHeight: 190)
                .background(MusicHomeStyle.secondaryCard, in: .rect(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .environment(\.layoutDirection, .leftToRight)
        .onHover { heroHovered = $0 }
        .onScrollVisibilityChange { featureViewportChanged($0) }
        .task(id: PreviewIdentity(id: currentFeature?.publicId, visible: canPresentFeature, retry: heroMediaRetry)) {
            await presentFeatureVideo()
        }
        .task(id: PreviewIdentity(id: currentFeature?.publicId, visible: canPresentFeature, retry: heroMediaRetry)) {
            await presentFeatureArtwork()
        }
        .task(id: FeatureTimer(index: featureIndex, count: model.features.count, canRotate: canRotateImage)) {
            guard canRotateImage, model.features.count > 1, let currentFeature else { return }
            do {
                try await Task.sleep(for: .seconds(min(120, max(3, currentFeature.displaySeconds))))
                selectFeature(featureIndex + 1)
            } catch {}
        }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { event in
            guard let item = event.object as? AVPlayerItem, item === previewPlayer?.currentItem else { return }
            heroVideoEnded = true
            advanceFinishedVideo()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification)) { event in
            guard let item = event.object as? AVPlayerItem, item === previewPlayer?.currentItem else { return }
            previewPlayer?.pause()
            previewPlayer = nil
            heroVideoStatus = .failed
        }
        .onChange(of: canRotateFeatures) { _, canRotate in
            if canRotate { advanceFinishedVideo() }
        }
    }

    private func featureViewportChanged(_ visible: Bool) {
        #if os(macOS)
        if pointer.scrollStartedAt != nil {
            // Match WinUI's settled viewport check. Pause playback immediately, but let the
            // same AVPlayer and its surface survive a transient exit during scrolling.
            pendingHeroVisibility = visible
            if !visible, let previewPlayer, previewPlayer.timeControlStatus != .paused {
                resumePreviewAfterScroll = true
                previewPlayer.pause()
            }
            return
        }
        #endif
        heroVisible = visible
    }

    #if os(macOS)
    private func settleFeatureViewport() {
        if let pendingHeroVisibility {
            heroVisible = pendingHeroVisibility
            self.pendingHeroVisibility = nil
        }
        if resumePreviewAfterScroll, canPresentFeature, !featurePaused, !heroVideoEnded {
            previewPlayer?.play()
        }
        resumePreviewAfterScroll = false
    }
    #endif

    private func presentFeatureArtwork() async {
        guard canPresentFeature, let item = currentFeature else { return }
        if heroArtwork?.id == item.publicId, heroArtworkStatus == .ready { return }
        heroArtworkStatus = .loading
        for id in featureArtworkIDs(item) {
            do {
                let artwork = try await model.artwork.imageWithSource(id, session: model.session)
                let image = artwork.image
                try Task.checkCancellation()
                async let palette = MusicHeroPalette.extract(from: image)
                let edgeColor = await Self.featureArtworkEdgeColor(at: artwork.source)
                let colors = await palette
                try Task.checkCancellation()
                let animate = !reduceMotion && !fullWindowVideo
                outgoingHeroArtwork = animate ? heroArtwork : nil
                heroArtwork = FeatureArtwork(id: item.publicId, image: image, palette: colors, edgeColor: edgeColor,
                                             stretch: !isVideo(item), direction: featureDirection,
                                             revealStart: animate ? Date() : nil)
                heroArtworkStatus = .ready
                return
            } catch {
                if Task.isCancelled { return }
            }
        }
        heroArtworkStatus = .failed
    }

    @concurrent
    private static func featureArtworkEdgeColor(at url: URL) async -> MusicArtworkEdgeColor? {
        guard !Task.isCancelled, let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let dimensions = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = dimensions[kCGImagePropertyPixelWidth as String] as? Int,
              let height = dimensions[kCGImagePropertyPixelHeight as String] as? Int,
              width > 0, height > 0, width <= 16_777_216 / height,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return await MusicArtworkEdgeColor.extract(from: image)
    }

    private func presentFeatureVideo() async {
        previewPlayer?.pause()
        previewPlayer = nil
        #if os(macOS)
        resumePreviewAfterScroll = false
        #endif
        heroVideoStatus = .waiting
        heroVideoEnded = false
        guard canPresentFeature, let item = currentFeature, isVideo(item) else { return }
        heroVideoStatus = .loading
        do {
            let url = try await model.artwork.playableURL(item.mediaPublicId, session: model.session)
            try Task.checkCancellation()
            let media = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: media)
            player.isMuted = previewMuted
            player.volume = Float(previewVolume)
            previewPlayer = player
            for await status in media.publisher(for: \.status, options: [.initial, .new]).values {
                try Task.checkCancellation()
                if status == .failed { throw media.error ?? CocoaError(.fileReadCorruptFile) }
                if status == .readyToPlay, heroVideoStatus == .loading {
                    heroVideoStatus = .ready
                    if !featurePaused && !reduceMotion {
                        #if os(macOS)
                        if pendingHeroVisibility == false {
                            resumePreviewAfterScroll = true
                        } else {
                            player.play()
                        }
                        #else
                        player.play()
                        #endif
                    }
                }
            }
        } catch {
            if !Task.isCancelled {
                previewPlayer?.pause()
                previewPlayer = nil
                heroVideoStatus = .failed
            }
        }
    }

    private func advanceFinishedVideo() {
        guard heroVideoEnded, canRotateFeatures, model.features.count > 1 else { return }
        heroVideoEnded = false
        selectFeature(featureIndex + 1)
    }

    private var canPresentFeature: Bool {
        heroVisible && scenePhase == .active && !showingLibrary && !showingAllMusicActivity
            && destination == nil && !model.isPlaying && !showingStoryPreview && article == nil
    }

    private var canRotateFeatures: Bool {
        canPresentFeature && !featurePaused && !reduceMotion && !showingPreviewControls && !fullWindowVideo
            && !heroHovered && !featureHasFocus && exportRequest == nil
    }

    private var canRotateImage: Bool {
        guard canRotateFeatures, let item = currentFeature, !isVideo(item) else { return false }
        return heroArtwork?.id == item.publicId || heroArtworkStatus == .failed
    }

    private var featureHasFocus: Bool {
        switch controlFocus {
        case .featureControls, .previousFeature, .nextFeature, .featureThumbnail, .openFeature, .likeFeature, .retryFeatureMedia: true
        default: false
        }
    }

    private func heroSurface(_ item: MusicFeatureItemResponse, compact: Bool) -> some View {
        let inset: CGFloat = compact ? 12 : 20
        return ZStack(alignment: .bottom) {
            musicColor("090C0F")
            Group {
                if let heroArtwork {
                    artworkReveal(heroArtwork)
                }
                if let previewPlayer, heroVideoStatus == .ready {
                    MusicInlineVideo(player: previewPlayer)
                }
            }
            .allowsHitTesting(false)
            let slate = musicColor("141B24")
            LinearGradient(stops: [
                .init(color: slate.opacity(112.0 / 255), location: 0),
                .init(color: slate.opacity(72.0 / 255), location: 0.28),
                .init(color: slate.opacity(56.0 / 255), location: 0.5),
                .init(color: musicColor("10161E").opacity(120.0 / 255), location: 0.78),
                .init(color: musicColor("090C0F").opacity(176.0 / 255), location: 1)
            ], startPoint: .top, endPoint: .bottom)
            Button { activate(.openFeature) } label: {
                Color.clear.contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
            .authHandPointer(enabled: true)
            heroInformation(item, compact: compact)
                .padding(.horizontal, inset)
                .padding(.bottom, compact ? 66 : 91)
                .allowsHitTesting(false)
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    musicColor("12BA70").frame(width: geometry.size.width * 0.46)
                    musicColor("3B4147").frame(width: geometry.size.width * 0.22)
                    musicColor("0697EA")
                }
            }
            .frame(height: 3)
            .clipShape(.capsule)
            .padding(.horizontal, inset)
            .padding(.bottom, compact ? 53 : 70)
            .allowsHitTesting(false)
            heroActions(item, compact: compact)
                .padding(.horizontal, inset)
                .padding(.bottom, inset)
            VStack {
                heroHeader(item, compact: compact)
                if heroMediaFailed || heroMediaLoading(item) {
                    HStack(spacing: 8) {
                        Text(text(heroMediaFailed ? (isVideo(item) ? "VideoFailed" : "FeatureImageFailed")
                                                  : (isVideo(item) ? "DownloadingVideo" : "DownloadingImage")))
                            .font(localization.font(11))
                        Spacer(minLength: 4)
                        if heroMediaFailed {
                            control(.retryFeatureMedia) { Text(text("Retry")).font(localization.font(11, weight: .semibold)) }
                                .buttonStyle(MusicHomeButtonStyle(corner: 6))
                                .accessibilityLabel(text("RetryMedia"))
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(musicColor("1A2635").opacity(0.85), in: .rect(cornerRadius: 8))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, inset)
            .padding(.top, inset)
        }
        .foregroundStyle(.white)
        .overlay(alignment: .top) {
            if isVideo(item), heroVideoStatus == .loading {
                ProgressView().progressViewStyle(.linear).tint(musicColor("A1E8EE"))
                    .frame(height: 2).clipped()
                    .accessibilityLabel(text("DownloadingVideo"))
                    .allowsHitTesting(false)
            }
        }
    }

    private func heroMediaLoading(_ item: MusicFeatureItemResponse) -> Bool {
        (isVideo(item) ? heroVideoStatus : heroArtworkStatus) == .loading
    }

    @ViewBuilder
    private func artworkReveal(_ artwork: FeatureArtwork) -> some View {
        if let start = artwork.revealStart, !reduceMotion, canPresentFeature, !fullWindowVideo,
           Date().timeIntervalSince(start) < FeatureArtwork.revealDuration {
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
                let phase = min(1, max(0, timeline.date.timeIntervalSince(start) / FeatureArtwork.revealDuration))
                ZStack {
                    if let outgoingHeroArtwork { artworkImage(outgoingHeroArtwork) }
                    artworkImage(artwork)
                        .scaleEffect(1 + 0.055 * (1 - Self.artworkRevealCurve.value(at: phase)),
                                     anchor: UnitPoint(x: artwork.direction < 0 ? 0.78 : 0.22, y: 0.5))
                        .opacity(phase < 0.72 ? 0.96 * Self.artworkRevealCurve.value(at: phase / 0.72)
                                 : 0.96 + 0.04 * Self.artworkRevealCurve.value(at: (phase - 0.72) / 0.28))
                }
            }
            .task(id: start) {
                do {
                    try await Task.sleep(for: .seconds(max(0, FeatureArtwork.revealDuration + start.timeIntervalSinceNow)))
                    guard heroArtwork?.revealStart == start else { return }
                    heroArtwork?.revealStart = nil
                    outgoingHeroArtwork = nil
                } catch {}
            }
        } else {
            artworkImage(artwork)
        }
    }

    @ViewBuilder
    private func artworkImage(_ artwork: FeatureArtwork) -> some View {
        let image = Image(decorative: artwork.image, scale: 1).resizable()
        if artwork.stretch { image } else { image.scaledToFit() }
    }

    private static let artworkRevealCurve = UnitCurve.bezier(startControlPoint: UnitPoint(x: 0.18, y: 0.72),
                                                            endControlPoint: .bottomTrailing)

    private func heroHeader(_ item: MusicFeatureItemResponse, compact: Bool) -> some View {
        let size: CGFloat = compact ? 24 : 30
        return HStack(spacing: 8) {
            control(.featureControls) {
                FluentIcon(symbol: .headphones, size: 14).frame(width: 30, height: 30)
            }
            .buttonStyle(MusicHomeButtonStyle(fill: musicColor("202428")))
            .accessibilityLabel(text("PlayerControls"))
            .help(text("PlayerControlsHelp"))
            .popover(isPresented: $showingPreviewControls, arrowEdge: .top) { presentationControls(item) }

            VStack(alignment: .leading, spacing: 2) {
                if !compact {
                    Text("MIZON SELECT").font(localization.font(8)).foregroundStyle(musicColor("B6C0CC"))
                }
                Text(MusicHomeStyle.duration(seconds: item.durationSeconds))
                    .font(localization.font(11, weight: .semibold)).monospacedDigit()
            }
            Spacer(minLength: 0)
            HStack(spacing: compact ? 5 : 8) {
                heroArrow(.previousFeature, icon: .chevronLeft, label: "PreviousFeature")
                ForEach(visibleThumbnailIndices, id: \.self) { index in
                    let preview = model.features[index]
                    control(.featureThumbnail(index)) {
                        MusicArtwork(mediaID: featureArtworkIDs(preview).first, model: model, symbol: "",
                                     fallbacks: Array(featureArtworkIDs(preview).dropFirst()))
                            .clipShape(.rect(cornerRadius: 7)).padding(1)
                            .frame(width: size, height: size)
                    }
                    .buttonStyle(featureThumbnailStyle(selected: index == featureIndex))
                    .accessibilityLabel(localized(preview.title, preview.persianTitle))
                    .accessibilityAddTraits(index == featureIndex ? .isSelected : [])
                    .help(localized(preview.title, preview.persianTitle))
                }
                heroArrow(.nextFeature, icon: .chevronRight, label: "NextFeature")
            }
        }
    }

    private var visibleThumbnailIndices: Range<Int> {
        let count = min(3, model.features.count)
        let start = min(max(0, featureIndex - 1), max(0, model.features.count - count))
        return start..<(start + count)
    }

    private func featureThumbnailStyle(selected: Bool) -> MusicHomeButtonStyle {
        let stroke = musicColor("4E555D").opacity(80.0 / 255)
        #if os(macOS)
        return MusicHomeButtonStyle(fill: selected ? MizonPalette.ink.opacity(0.17) : .clear, stroke: stroke, corner: 8)
        #else
        return MusicHomeButtonStyle(stroke: selected ? musicColor("0697EA") : stroke, corner: 8)
        #endif
    }

    private func heroArrow(_ action: Action, icon: FluentSymbol, label: String) -> some View {
        control(action) { FluentIcon(symbol: icon, size: 12).frame(width: 22, height: 28) }
            .buttonStyle(MusicHomeButtonStyle(corner: 6))
            .accessibilityLabel(text(label))
            .help(text(label))
            .disabled(model.features.count < 2)
    }

    private func heroInformation(_ item: MusicFeatureItemResponse, compact: Bool) -> some View {
        let badge: CGFloat = compact ? 28 : 40
        let person = item.contributors.first
        let byline = item.contributors.map { [$0.firstName, $0.lastName].filter { !$0.isEmpty }.joined(separator: " ") }
            .filter { !$0.isEmpty }.joined(separator: " · ")
        let genre = item.genres.first.map { localized($0.title, $0.persianTitle).uppercased() } ?? ""
        return HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                heroBadge(item.coverMediaPublicId, size: badge, imageSize: 21, symbol: "music.note")
                Text(genre).font(localization.font(9)).tracking(0.58).foregroundStyle(musicColor("B6C0CC")).lineLimit(1)
                Text(item.title).font(localization.font(compact ? 16 : 22, weight: .semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !compact {
                VStack(spacing: 3) {
                    if let translation = item.persianTitle, !translation.isEmpty {
                        Text(translation).font(WindowsTypography.iranSans(10)).foregroundStyle(musicColor("B6C0CC"))
                            .lineLimit(1).frame(maxWidth: 165)
                    }
                    Text(MusicHomeStyle.duration(seconds: item.durationSeconds))
                        .font(localization.font(15, weight: .semibold)).monospacedDigit()
                }
                .frame(maxWidth: .infinity)
            }
            VStack(alignment: .trailing, spacing: 7) {
                heroBadge(person?.profileMediaPublicId, size: badge, imageSize: 26, symbol: "person.fill")
                    .padding(.bottom, 3)
                Text(text("ArtistLabel")).font(localization.font(9)).tracking(0.58).foregroundStyle(musicColor("B6C0CC"))
                Text(byline).font(localization.font(compact ? 15 : 21, weight: .light)).lineLimit(1)
                    .foregroundStyle(musicColor("E1E3E6"))
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func heroBadge(_ mediaID: UUID?, size: CGFloat, imageSize: CGFloat, symbol: String) -> some View {
        MusicArtwork(mediaID: mediaID, model: model, symbol: symbol)
            .frame(width: imageSize, height: imageSize)
            .clipShape(.circle)
            .frame(width: size, height: size)
            .background(musicColor("15171D"), in: .circle)
            .overlay { Circle().strokeBorder(musicColor("303137")) }
    }

    private func heroActions(_ item: MusicFeatureItemResponse, compact: Bool) -> some View {
        let border = musicColor("2D3034")
        let fill = musicColor("0C1013").opacity(149.0 / 255)
        return HStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: -5) {
                    heroAudienceAvatar("friend-amir")
                    heroAudienceAvatar("friend-sara")
                    if !compact {
                        heroAudienceAvatar("friend-amir")
                        Text("+8").font(localization.font(7)).frame(width: 22, height: 22)
                            .background(musicColor("27313B"), in: .circle)
                            .overlay { Circle().strokeBorder(musicColor("161B20")) }
                    }
                }
                if !compact {
                    Text(text("WithYou")).font(localization.font(9)).foregroundStyle(musicColor("B6C0CC"))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(fill, in: .capsule)
            .overlay { Capsule().strokeBorder(border) }
            .accessibilityHidden(true)
            .frame(maxWidth: .infinity, alignment: .leading)
            control(.openFeature) {
                HStack(spacing: 7) {
                    if !compact { FluentIcon(symbol: .musicNote1, size: 13) }
                    Text(text("DiscoverTrack")).font(localization.font(compact ? 9 : 10)).lineLimit(1)
                    if !compact {
                        Text(String(format: "%02d / %02d", featureIndex + 1, model.features.count))
                            .font(localization.font(9)).foregroundStyle(musicColor("B6C0CC")).monospacedDigit()
                    }
                }
                .padding(.horizontal, compact ? 8 : 15)
                .frame(height: 32)
            }
            .buttonStyle(MusicHomeButtonStyle(fill: musicColor("090C0F"), stroke: border, corner: 16))
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
            .accessibilityLabel(text("ViewTrack"))
            control(.likeFeature) {
                HStack(spacing: 7) {
                    FluentIcon(symbol: .heart, size: 12, filled: item.likedByMe)
                        .foregroundStyle(item.likedByMe ? musicColor("FF9BBE") : Color.white)
                    Text(item.likesCount, format: .number).font(localization.font(10))
                    if !compact {
                        HStack(spacing: -5) {
                            heroAudienceAvatar("friend-sara")
                            heroAudienceAvatar("friend-amir")
                        }
                    }
                }
                .padding(.horizontal, compact ? 8 : 10)
                .frame(height: 32)
            }
            .buttonStyle(MusicHomeButtonStyle(fill: fill, stroke: border, corner: 16))
            .accessibilityLabel(text(item.likedByMe ? "UnlikeTrack" : "LikeTrack"))
            .accessibilityAddTraits(item.likedByMe ? .isSelected : [])
            .disabled(model.updating.contains(item.musicPublicId))
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func heroAudienceAvatar(_ asset: String) -> some View {
        MusicLocalArtwork(asset, maximumPixelSize: 96).scaledToFill().frame(width: 22, height: 22)
            .clipShape(.circle)
            .overlay { Circle().strokeBorder(musicColor("161B20")) }
    }

    private func presentationControls(_ item: MusicFeatureItemResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(text("DisplayControls")).font(localization.font(13, weight: .semibold))
            HStack(spacing: 8) {
                Button { activate(.rotateFeatures) } label: {
                    FluentIcon(symbol: featurePaused ? .play : .pause, size: 16).frame(width: 32, height: 32)
                }
                .accessibilityLabel(text(featurePaused ? "ResumePresentation" : "PausePresentation"))
                if previewPlayer != nil {
                    Button { activate(.mutePreview) } label: {
                        FluentIcon(symbol: previewMuted ? .speakerMute : .speaker2, size: 16).frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(text(previewMuted ? "UnmuteVideo" : "MuteVideo"))
                    Slider(value: $previewVolume) { Text(text("VideoVolume")) }
                        .onChange(of: previewVolume) { _, value in previewPlayer?.volume = Float(value) }
                }
            }
            if let previewPlayer {
                MusicFeatureScrubber(player: previewPlayer, title: text("PresentationPosition"))
            }
            heroMenuButton("PlayInMizon") { activate(.playFeature) }
            if previewPlayer != nil {
                heroMenuButton("VideoFullWindow") { fullWindowVideo = true }
            }
            heroMenuButton("SaveMedia") { exportRequest = item }.disabled(exportRequest != nil)
            heroMenuButton("CopyMusicLink") { activate(.copyFeatureLink) }
            heroMenuButton("RefreshFeatures") { activate(.refresh(.features)) }
        }
        .buttonStyle(MusicHomeButtonStyle(fill: MusicHomeStyle.inset, stroke: MusicHomeStyle.stroke, corner: 8))
        .frame(width: 260)
        .padding(12)
    }

    private func heroMenuButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button {
            showingPreviewControls = false
            action()
        } label: {
            Text(text(label)).font(localization.font(11)).frame(maxWidth: .infinity, minHeight: 32)
        }
    }

    private struct PreviewIdentity: Equatable {
        let id: UUID?
        let visible: Bool
        var retry = 0
    }

    private enum FeatureMediaStatus { case waiting, loading, ready, failed }

    private struct FeatureArtwork {
        static let revealDuration = 0.430
        let id: UUID
        let image: CGImage
        let palette: MusicHeroPalette?
        let edgeColor: MusicArtworkEdgeColor?
        let stretch: Bool
        let direction: Int
        var revealStart: Date?
    }

    private func isVideo(_ item: MusicFeatureItemResponse) -> Bool {
        item.contentTypeCode.caseInsensitiveCompare("video") == .orderedSame
    }

    private func featureArtworkIDs(_ item: MusicFeatureItemResponse) -> [UUID] {
        let primary = isVideo(item) ? item.previewMediaPublicId : item.mediaPublicId
        let empty = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        return [primary, item.coverMediaPublicId == primary ? nil : item.coverMediaPublicId]
            .compactMap { $0 }.filter { $0 != empty }
    }

    private struct FeatureTimer: Equatable {
        let index: Int
        let count: Int
        let canRotate: Bool
    }

    private func artistSpotlight(width: CGFloat) -> some View {
        let compact = width < 640
        return Group {
            if let artist = currentArtist {
                let accent = musicColor(artist.accentColor, fallback: musicColor("A6C8FF"))
                let portraitWidth = width * (compact ? 0.325 : 0.25)
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        spotlightStage(artist, accent: accent, compact: compact)
                            .frame(width: portraitWidth)
                        if !compact {
                            ZStack {
                                spotlightTracks(artist, accent: accent, horizontal: false)
                                    .id(artist.personPublicId)
                                    .transition(spotlightReveal(x: 12, y: 4))
                            }
                            .animation(spotlightAnimation(0.36), value: artist.personPublicId)
                            .frame(width: width / 3)
                        }
                        spotlightInformation(artist, accent: accent, compact: compact)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: compact ? 168 : 220)
                    if compact {
                        ZStack {
                            spotlightTracks(artist, accent: accent, horizontal: true)
                                .id(artist.personPublicId).transition(spotlightReveal(x: 12, y: 4))
                        }
                        .animation(spotlightAnimation(0.36), value: artist.personPublicId)
                        .frame(height: 76)
                    }
                }
                .background(MusicHomeStyle.secondaryCard, in: .rect(cornerRadius: 18))
                .clipShape(.rect(cornerRadius: 18))
                .environment(\.layoutDirection, .leftToRight)
            } else if model.loading.contains(.artists) {
                MusicHomeSkeleton(height: 212, label: text("LoadingArtists"))
            } else {
                sectionStatus(.artists, empty: "FeaturedArtistsEmpty")
            }
        }
    }

    private func spotlightReveal(x: CGFloat, y: CGFloat) -> AnyTransition {
        guard !reduceMotion, spotlightDirection != 0 else { return .identity }
        return .asymmetric(insertion: .opacity.combined(with: .offset(x: CGFloat(spotlightDirection) * x, y: y)),
                           removal: .identity)
    }

    private func spotlightAnimation(_ duration: Double) -> Animation? {
        reduceMotion || spotlightDirection == 0 ? nil : .timingCurve(0.16, 0.85, 1, 1, duration: duration)
    }

    private func spotlightStage(_ artist: FeaturedPersonItem, accent: Color, compact: Bool) -> some View {
        let orbit: CGFloat = compact ? 118 : 174
        return GeometryReader { geometry in
            ZStack {
                Ellipse()
                    .fill(.radialGradient(colors: [accent.opacity(0.24), accent.opacity(0.03), .clear],
                                          center: .center, startRadius: 8, endRadius: 96))
                    .frame(height: 100)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 8)
                    .allowsHitTesting(false)
                ZStack(alignment: .trailing) {
                    Circle().fill(accent.opacity(0.055))
                    Circle().strokeBorder(accent.opacity(0.22))
                    Circle().strokeBorder(accent.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [1, 8]))
                        .padding(17)
                    Circle().strokeBorder(accent.opacity(0.12), lineWidth: 0.5).padding(38)
                    Circle().fill(accent).frame(width: 5, height: 5).offset(x: 2)
                }
                .frame(width: orbit, height: orbit)
                .allowsHitTesting(false)
                ZStack {
                    Group {
                        if let mediaID = artist.modelMediaPublicId {
                            MusicArtistModel(configuration: .init(mediaID: mediaID, portraitMediaID: artist.profileMediaPublicId,
                                                                  yaw: artist.modelYawInDegrees, zoom: artist.modelViewScale,
                                                                  verticalFocus: artist.modelVerticalFocus,
                                                                  attribution: artist.modelAttribution),
                                             model: model, rotateHint: text("RotateHint"), resetLabel: text("ResetModel"),
                                             showsRotationHint: !compact, isInMusicFeed: true)
                        } else {
                            spotlightPortrait(artist, size: min(118, orbit * 0.82))
                        }
                    }
                    .id(artist.personPublicId)
                    .transition(spotlightReveal(x: 24, y: 0))
                }
                .animation(spotlightAnimation(0.42), value: artist.personPublicId)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    if !compact {
                        Text(text("ArtistLabel")).font(localization.font(8)).tracking(1.84)
                            .foregroundStyle(MusicHomeStyle.secondary)
                    }
                    Text(String(format: "%02d / %02d", spotlightIndex + 1, model.artists.count))
                        .font(localization.font(11, weight: .semibold)).monospacedDigit().foregroundStyle(accent)
                }
                .padding(compact ? 10 : 14)
                .allowsHitTesting(false)
            }
            .clipped()
        }
    }

    private func spotlightPortrait(_ artist: FeaturedPersonItem, size: CGFloat) -> some View {
        MusicArtwork(mediaID: artist.profileMediaPublicId, model: model, symbol: "person.fill")
            .frame(width: size, height: size)
            .background(MusicHomeStyle.inset)
            .clipShape(.circle)
    }

    private func spotlightInformation(_ artist: FeaturedPersonItem, accent: Color, compact: Bool) -> some View {
        VStack(spacing: compact ? 8 : 10) {
            ZStack {
                spotlightMetrics(artist, accent: accent, compact: compact)
                    .id(artist.personPublicId)
                    .transition(spotlightReveal(x: 10, y: 8))
            }
            .animation(spotlightAnimation(0.33), value: artist.personPublicId)
            .frame(maxHeight: .infinity)
            spotlightActions(artist, compact: compact, accent: accent)
        }
        .padding(.leading, compact ? 4 : 12)
        .padding(.trailing, compact ? 10 : 16)
        .padding(.vertical, compact ? 8 : 14)
    }

    private func spotlightMetrics(_ artist: FeaturedPersonItem, accent: Color, compact: Bool) -> some View {
        VStack(spacing: compact ? 3 : 4) {
            HStack(spacing: 9) {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(artistName(artist)).font(localization.font(compact ? 19 : 24, weight: .bold)).lineLimit(1)
                        .accessibilityAddTraits(.isHeader)
                    let genre = localized(artist.genreTitle ?? "", artist.persianGenreTitle)
                    if !genre.isEmpty {
                        HStack(spacing: 5) {
                            FluentIcon(symbol: .musicNote1, size: 9)
                            Text(genre).font(localization.font(9)).lineLimit(1)
                        }
                        .foregroundStyle(accent)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(MusicHomeStyle.inset, in: .rect(cornerRadius: 5))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                Button { activate(.spotlightProfile(artist.personPublicId)) } label: {
                    spotlightPortrait(artist, size: 40).frame(width: 44, height: 44)
                }
                .buttonStyle(MusicHomeButtonStyle(corner: 22))
                .accessibilityLabel(text("ViewProfile"))
                Capsule().fill(accent.opacity(0.75)).frame(width: 3, height: 39)
            }
            HStack(spacing: 5) {
                spotlightMetric("WeeklyArtistPlays", value: artist.dailyPlays.reduce(0, +), icon: .star,
                                accent: MusicHomeStyle.gold, compact: compact, numberColor: MusicHomeStyle.gold)
                spotlightMetric("Followers", value: artist.followersCount, icon: .people, accent: accent, compact: compact)
                spotlightMetric("Track", value: artist.musicsCount, icon: .musicNote1, accent: accent, compact: compact)
            }
            .frame(height: compact ? 49 : 54)
            if !compact {
                HStack(spacing: 6) {
                    spotlightChart(plays: artist.dailyPlays, color: accent)
                        .frame(width: 48, height: 16)
                        .accessibilityHidden(true)
                    Text(artist.monthlyListenersCount.formatted() + " " + text("MonthlyListeners"))
                        .foregroundStyle(MusicHomeStyle.secondary).font(localization.font(8)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    FluentIcon(symbol: .headphones, size: 11).foregroundStyle(accent)
                }
                .padding(.horizontal, 6).frame(height: 25)
                .background(MusicHomeStyle.inset, in: .rect(cornerRadius: 7))
            }
        }
    }

    private func spotlightMetric(_ name: String, value: Int, icon: FluentSymbol, accent: Color,
                                 compact: Bool, numberColor: Color = .white) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 3) {
                FluentIcon(symbol: icon, size: 9).foregroundStyle(accent)
                Text(text(name)).font(localization.font(8)).foregroundStyle(MusicHomeStyle.secondary).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: 12)
            Text(value, format: .number.notation(.compactName))
                .font(localization.font(compact ? 16 : 18, weight: .semibold)).foregroundStyle(numberColor)
                .lineLimit(1).minimumScaleFactor(0.72)
        }
        .padding(.horizontal, compact ? 5 : 8).padding(.vertical, 6)
        .frame(maxHeight: .infinity)
        .background(MusicHomeStyle.inset, in: .rect(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(MusicHomeStyle.stroke) }
        .accessibilityElement(children: .combine)
    }

    private func spotlightChart(plays: [Int], color: Color) -> some View {
        Canvas { context, size in
            let values = Array(plays.suffix(7))
            guard values.count > 1, let peak = values.max(), peak > 0 else { return }
            let shape = Path { path in
                for (i, value) in values.enumerated() {
                    let point = CGPoint(x: size.width * CGFloat(i) / CGFloat(values.count - 1),
                                        y: 1 + (size.height - 2) * (1 - CGFloat(max(0, value)) / CGFloat(peak)))
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
            }
            context.stroke(shape, with: .color(color.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
    }

    private func spotlightActions(_ artist: FeaturedPersonItem, compact: Bool, accent: Color) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                spotlightArrow(.previousSpotlight, direction: .chevronLeft, label: "PreviousArtist")
                Rectangle().fill(.white.opacity(0.095)).frame(width: 1, height: 16)
                spotlightArrow(.nextSpotlight, direction: .chevronRight, label: "NextArtist")
            }
            .frame(width: 58, height: 32)
            .background(MusicHomeStyle.inset, in: .rect(cornerRadius: 10))
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(MusicHomeStyle.stroke) }
            control(.spotlightProfile(artist.personPublicId)) {
                HStack(spacing: 5) {
                    FluentIcon(symbol: .person, size: 12)
                    if !compact { Text(text("Profile")).font(localization.font(10)).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(MusicHomeButtonStyle(fill: MusicHomeStyle.inset, stroke: MusicHomeStyle.stroke, corner: 10))
            .accessibilityLabel(text("ViewProfile"))
            control(.spotlightFollow(artist.personPublicId)) {
                Text(text(artist.isFollowing ? "Following" : "Follow"))
                    .font(localization.font(10, weight: .semibold)).foregroundStyle(musicColor("111924"))
                    .frame(width: compact ? 70 : 84, height: 32)
                    .lineLimit(1)
            }
            .buttonStyle(MusicHomeButtonStyle(fill: accent, corner: 10))
            .disabled(!artist.canFollow || model.updating.contains(artist.personPublicId))
        }
    }

    private func spotlightArrow(_ action: Action, direction: FluentSymbol, label: String) -> some View {
        control(action) { FluentIcon(symbol: direction, size: 11).frame(width: 27, height: 30) }
            .buttonStyle(MusicHomeButtonStyle(corner: 8))
            .accessibilityLabel(text(label))
            .disabled(model.artists.count < 2)
    }

    private func spotlightTracks(_ artist: FeaturedPersonItem, accent: Color, horizontal: Bool) -> some View {
        VStack(alignment: .trailing, spacing: horizontal ? 2 : 8) {
            HStack {
                FluentIcon(symbol: .musicNote1, size: 10).foregroundStyle(accent)
                Spacer(minLength: 2)
                Text(text("LatestTracks")).font(localization.font(11)).foregroundStyle(MusicHomeStyle.secondary)
            }
            if artist.latestMusics.isEmpty {
                Text(text("NoFeaturedArtistTracks")).font(localization.font(11)).foregroundStyle(MusicHomeStyle.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 8)
            } else {
                ScrollView(horizontal ? .horizontal : .vertical) {
                    if horizontal {
                        LazyHStack(spacing: 6) { spotlightTrackButtons(artist, accent: accent, horizontal: true) }
                    } else {
                        LazyVStack(spacing: 6) { spotlightTrackButtons(artist, accent: accent, horizontal: false) }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, horizontal ? 12 : 10)
        .padding(.top, horizontal ? 0 : 16)
        .padding(.bottom, horizontal ? 6 : 16)
    }

    private func spotlightTrackButtons(_ artist: FeaturedPersonItem, accent: Color, horizontal: Bool) -> some View {
        ForEach(artist.latestMusics.prefix(5), id: \.publicId) { track in
            let title = localized(track.title, track.persianTitle)
            control(.spotlightTrack(track.publicId)) {
                HStack(spacing: 6) {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(title).font(localization.font(10)).lineLimit(1)
                        HStack {
                            Text(MusicHomeStyle.duration(seconds: track.duration?.totalSeconds)).font(localization.font(8))
                                .foregroundStyle(MusicHomeStyle.secondary).monospacedDigit()
                            Spacer(minLength: 3)
                            FluentIcon(symbol: .heart, size: 9).foregroundStyle(accent.opacity(0.75))
                            Text(track.likesCount, format: .number).font(localization.font(8)).foregroundStyle(MusicHomeStyle.secondary)
                        }
                    }
                    MusicArtwork(mediaID: track.coverMediaPublicId, model: model, symbol: "music.note")
                        .frame(width: 32, height: 32).clipShape(.rect(cornerRadius: 7))
                }
                .padding(.horizontal, 7).frame(height: 44)
                .frame(minWidth: horizontal ? 156 : 0, maxWidth: horizontal ? 180 : .infinity)
            }
            .buttonStyle(MusicHomeButtonStyle(fill: MusicHomeStyle.inset, stroke: MusicHomeStyle.stroke, corner: 8))
            .accessibilityLabel(title)
            .help(title)
        }
    }

    private var centralRails: MusicHomeRails { MusicHomeRails(model: model, localization: localization) }

    private var stories: some View {
        centralRails.stories {
            control(.addStory) { centralRails.addStoryCard }
                .buttonStyle(MusicReferenceStoryStyle(restingOpacity: 0.8))
                .accessibilityLabel(text("AddStory"))
        } story: { item in
            control(.story(item.publicId)) { centralRails.storyCard(item) }
                .buttonStyle(MusicReferenceStoryStyle())
                .accessibilityHint(text("OpenStoryHelp"))
        } retry: {
            railRetry(.stories, label: "RefreshStories")
        }
    }

    private var genres: some View {
        centralRails.genres {
            control(.allGenres) { centralRails.clearGenresLabel }
                .buttonStyle(MusicReferenceRailActionStyle())
        } genre: { item in
            control(.genre(item.publicId)) { centralRails.genreCard(item, isSelected: selectedGenre == item.publicId) }
                .buttonStyle(MusicReferenceGenreStyle(accent: musicColor(item.accentColorHex)))
        } retry: {
            railRetry(.genres, label: "RefreshGenres")
        }
    }

    private var artists: some View {
        centralRails.artists(position: $artistRailPosition) {
            artistRailControls
        } profile: { artist in
            control(.profile(artist.personPublicId)) { centralRails.artistProfile(artist) }
                .buttonStyle(.plain)
        } follow: { artist in
            control(.follow(artist.personPublicId)) { centralRails.artistFollow(artist) }
                .buttonStyle(MusicReferenceRailActionStyle())
                .disabled(!artist.canFollow || model.updating.contains(artist.personPublicId))
        } retry: {
            railRetry(.artists, label: "FeaturedArtistsRetry")
        }
    }

    private func railRetry(_ section: MusicHomeService.Section, label: String) -> some View {
        control(.refresh(section)) {
            Text(text("Retry")).font(localization.font(10, weight: .semibold))
                .padding(.horizontal, 10).frame(height: 28)
        }
        .buttonStyle(MusicReferenceRailActionStyle())
        .accessibilityLabel(text(label))
    }

    private var artistRailControls: some View {
        HStack(spacing: 6) {
            control(.previousArtistRail) { FluentIcon(symbol: .chevronLeft, size: 12).frame(width: 30, height: 30) }
                .buttonStyle(MusicReferenceRailActionStyle(square: true))
                .accessibilityLabel(text("PreviousArtists")).disabled(model.artists.count < 2)
            Text(model.artists.count, format: .number)
                .font(localization.font(11, weight: .semibold)).frame(width: 32, height: 24)
                .background(MusicHomeStyle.inset, in: .rect(cornerRadius: 6))
                .accessibilityLabel(text("ArtistCountHelp"))
                .accessibilityValue(model.artists.count.formatted())
            control(.nextArtistRail) { FluentIcon(symbol: .chevronRight, size: 12).frame(width: 30, height: 30) }
                .buttonStyle(MusicReferenceRailActionStyle(square: true))
                .accessibilityLabel(text("NextArtists")).disabled(model.artists.count < 2)
        }
    }

    private var transport: some View {
        let shape = RoundedRectangle(cornerRadius: 14)
        return HStack(spacing: 14) {
            Image(systemName: "music.note")
                .foregroundStyle(MizonPalette.accent)
            Text(model.playbackTitle).font(localization.font(13, weight: .semibold)).lineLimit(1)
            Spacer()
            if model.requestingPlayback { ProgressView().controlSize(.small) }
            else {
                control(.transport) { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill") }
                    .accessibilityLabel(text(model.isPlaying ? "PausePresentation" : "ResumePresentation"))
                    .buttonStyle(.glass)
                    .foregroundStyle(MizonPalette.accent)
            }
        }
        .foregroundStyle(MizonPalette.ink)
        .tint(MizonPalette.accent)
        .padding(12)
        .glassEffect(.regular.tint(MizonPalette.surface.opacity(0.55)), in: shape)
        .overlay { shape.strokeBorder(MusicHomeChrome.hairline).allowsHitTesting(false) }
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
                    Text(message).foregroundStyle(MizonPalette.secondaryText)
                    control(.refresh(section)) { Text(text("Retry")) }.buttonStyle(.glass)
                } else {
                    Text(text(empty)).foregroundStyle(MizonPalette.secondaryText)
                }
            }
        }
        .font(localization.font(12))
        .tint(MizonPalette.accent)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func control<Label: View>(_ action: Action, @ViewBuilder label: () -> Label) -> some View {
        focusableControl(action, cornerRadius: 9) {
            Button { activate(action) } label: { label() }
        }
        .id(action)
        .authHandPointer(enabled: true)
    }

    private func focusableControl<Content: View>(_ action: Action, cornerRadius: CGFloat,
                                                 @ViewBuilder content: () -> Content) -> some View {
        content()
            .focusable()
            .focused($controlFocus, equals: action)
            #if os(macOS)
            .focusEffectDisabled()
            #endif
            .overlay {
                #if os(macOS)
                MusicHomeFocusOutline(isFocused: controlFocus == action, cornerRadius: cornerRadius, input: navigationFocus)
                #else
                if action != .search, controlFocus == action {
                    let themed = action == .home || action == .navigationOverflow || action == .transport
                        || action == .mood || action == .nearby
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(themed ? MizonPalette.accent : Color.accentColor, lineWidth: 2)
                        .allowsHitTesting(false)
                }
                #endif
            }
    }

    private func activate(_ action: Action) {
        switch action {
        case .search: searchFocusRequest += 1
        case .home: scrollHomeRequest += 1
        case .navigationOverflow:
            if navigationHasOverflow { showingNavigationOverflow.toggle() }
        case .nearby: nearbyPress &+= 1
        case .mood: moodPress &+= 1
        case .featureControls: showingPreviewControls = true
        case .featureThumbnail(let index): selectFeature(index)
        case .retryFeatureMedia: heroMediaRetry += 1
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
            spotlightDirection = action == .nextSpotlight ? 1 : -1
            let next = spotlightIndex + spotlightDirection
            spotlightIndex = (next % model.artists.count + model.artists.count) % model.artists.count
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
        case .spotlightTrack(let id): destination = .track(id)
        case .playlist(let id): destination = .playlist(id)
        case .library: showingLibrary = true
        case .activity(let id):
            if let item = model.activity?.activities.first(where: { $0.activityId == id }) { destination = activityDestination(item) }
        case .moreActivity: showingAllMusicActivity = true
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

    func activityDestination(_ item: FollowingActivityItemResponse) -> MusicDestination? {
        if let id = item.storyPublicId { return .story(id) }
        if let id = item.musicPlaylistPublicId { return .playlist(id) }
        return item.musicPublicId.map(MusicDestination.track)
    }

    var newsWidgetHasFocus: Bool {
        switch controlFocus {
        case .news, .previousNews, .nextNews, .toggleNews, .selectNews: true
        default: false
        }
    }

    private var controllerTargets: [Action] {
        var targets: [Action] = [.home]
        if navigationHasOverflow { targets.append(.navigationOverflow) }
        targets += [.search, .nearby, .mood]
        if let item = currentFeature {
            targets.append(.featureControls)
            if model.features.count > 1 {
                targets += [.previousFeature] + visibleThumbnailIndices.map(Action.featureThumbnail) + [.nextFeature]
            }
            targets.append(.openFeature)
            if heroMediaFailed { targets.append(.retryFeatureMedia) }
            if !model.updating.contains(item.musicPublicId) { targets.append(.likeFeature) }
        }
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
        targets += model.library?.playlists.map { .playlist($0.publicId) } ?? []
        targets += model.activity?.activities.prefix(4).filter { activityDestination($0) != nil }.map { .activity($0.activityId) } ?? []
        if let activity = model.activity, activity.hasMore || activity.activities.count > 4 { targets.append(.moreActivity) }
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
               destination == nil, !showingLibrary, !showingAllMusicActivity, article == nil, !showingStoryPreview,
               !copiedFeatureLink, !model.actionFailed, !showingPreviewControls, !fullWindowVideo, !exportPresented,
               !showingNearby, !showingMoodPicker, !showingSearch {
                let horizontal = pad.dpad.xAxis.value
                let vertical = pad.dpad.yAxis.value
                let control = pad.buttonA.isPressed ? 1 : pad.buttonB.isPressed ? 2
                    : vertical < -0.65 || horizontal > 0.65 ? 3 : vertical > 0.65 || horizontal < -0.65 ? 4 : 0
                if control == 0 { armed = true }
                if armed, control != 0, control != previous {
                    #if os(macOS)
                    navigationFocus.updateForNavigation(true)
                    #endif
                    if showingNavigationOverflow {
                        if control == 2 {
                            showingNavigationOverflow = false
                            controlFocus = navigationHasOverflow ? .navigationOverflow : .home
                        }
                    } else if control == 1 {
                        let targets = controllerTargets
                        if let controlFocus, targets.contains(controlFocus) { activate(controlFocus) }
                        else { controlFocus = targets.first }
                    } else if control == 2 {
                        controlFocus = nil
                    } else {
                        let targets = controllerTargets
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
        featureDirection = index >= featureIndex ? 1 : -1
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.43)) {
            featureIndex = (index % model.features.count + model.features.count) % model.features.count
        }
    }

    private func normalizedGenre(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{200C}", with: "").replacingOccurrences(of: "ي", with: "ی")
            .replacingOccurrences(of: "ك", with: "ک").uppercased()
    }

    private func artistName(_ artist: FeaturedPersonItem) -> String { "\(artist.firstName) \(artist.lastName)" }
    func localized(_ title: String, _ persian: String?) -> String {
        if localization.isPersian, let persian, !persian.isEmpty { return persian }
        return title
    }
    func text(_ key: String) -> String { localization.string(key, table: "MusicHome") }
    func widget(_ key: String) -> String { localization.string(key, table: "MusicWidgets") }
}

struct MusicArtwork: View {
    var mediaID: UUID?
    var model: MusicHomeViewModel
    var symbol: String
    var stretch = false
    var fallbacks: [UUID] = []
    @State private var image: CGImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Rectangle().fill(.white.opacity(0.05))
                if let image {
                    if stretch { Image(decorative: image, scale: 1).resizable() }
                    else { Image(decorative: image, scale: 1).resizable().scaledToFill() }
                } else if !symbol.isEmpty {
                    Image(systemName: symbol).font(.system(size: min(30, geometry.size.height * 0.45)))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
        .task(id: [mediaID].compactMap { $0 } + fallbacks) {
            image = nil
            for id in [mediaID].compactMap({ $0 }) + fallbacks {
                let fetched = try? await model.artwork.image(id, session: model.session)
                guard !Task.isCancelled else { return }
                if let fetched {
                    image = fetched
                    return
                }
            }
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
