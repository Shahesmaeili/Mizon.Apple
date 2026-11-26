#if os(macOS) || os(iOS)
import AVKit
import MizonAPIClient
import MizonAppleCore
import Observation
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
import AVFoundation
#endif

struct MusicTrackDetailsView: View {
    enum Target: Hashable {
        case cover, play, waveform, rewind, forward, download, shortcut, floating, copy, support, playlists, output
        case views, live, album, video, like, repeatTrack, volume, lyrics, mix, balance, storyAdd
        case sort, commentNew, repliesBack, more, retry(MusicTrackDetailsViewModel.Section)
        case reaction(UUID), artist(UUID, UUID), story(UUID), related(UUID)
        case pane(MusicTrackDetailsViewModel.Pane), lyric(Int), comment(UUID), vote(UUID, Int), reply(UUID), replies(UUID), tag(UUID)
        case device(String), close, zoomIn, zoomOut, zoomReset, createPlaylist, membership(UUID), saveComposer, cancelComposer, editComposer
    }

    enum Panel: String, Identifiable {
        case support, playlists, output, views, live, shortcut
        var id: Self { self }
    }

    @Observable @MainActor final class Playhead {
        var seconds: Double = 0
    }

    let open: (MusicDestination) -> Void
    let controllerIsCurrent: Bool
    let linkedCommentID: UUID?
    let downloadCompleted: Bool
    @State var details: MusicTrackDetailsViewModel
    @State var focus: Target?
    @State var panel: Panel?
    @State var position = Playhead()
    @State var composer: TrackDiscussionDraft?
    @State var controllerKeyboard: GamepadKeyboard?
    @State var coverOpen = false
    @State var coverZoom: CGFloat = 1
    @GestureState var pinch: CGFloat = 1
    @State var coverDrag: CGSize = .zero
    @GestureState var drag: CGSize = .zero
    @State var lyricsOpen = false
    @State var floating = false
    @State var width: CGFloat = 390
    @State var scroll = GamepadScroll()
    @State var scrollToComment: UUID?
    @State var highlightedComment: UUID?
    @State var playlistName = ""
    @State var createsPlaylist = false
    @State var exporting = false
    @State var contextNotice: String?
    #if os(macOS)
    @State var outputDevices: [TrackAudioOutput] = []
    #endif
    @State var exportDocument: MusicFeatureExport?
    @State var downloading = false
       @State var exportTask: Task<Void, Never>?
    @State var actionsInFlight = TrackPageActions()
    @State var playerVolume = 1.0
    @State var volumeBeforeMute = 1.0
    @Namespace var coverNamespace
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.controllerInputSuspended) var controllerInputSuspended
    #if os(macOS)
    @Environment(\.appearsActive) var appearsActive
    @State var floatWindow = TrackFloatingWindow()
    #endif
    let localization = AuthLocalization()

    init(id: UUID, track: MusicResponse, music: MusicHomeViewModel,
         linkedComment: MusicCommentItemResponse?, downloadCompleted: Bool, controllerIsCurrent: Bool,
         open: @escaping (MusicDestination) -> Void) {
        _details = State(initialValue: MusicTrackDetailsViewModel(id: id, track: track, music: music, linkedComment: linkedComment))
        self.open = open
        self.linkedCommentID = linkedComment?.publicId
        self.downloadCompleted = downloadCompleted
        self.controllerIsCurrent = controllerIsCurrent
    }

    var music: MusicHomeViewModel { details.music }
    var track: MusicResponse { details.track }
    var palette: Color { musicColor(track.musicCover?.primaryAccentColor, fallback: MizonPalette.accent) }
    var rtl: Bool { localization.isPersian }
    var title: String { localized(track.title, track.persianTitle) }
    var isTrackPlaying: Bool { music.playingTrack == details.id && music.isPlaying }
    var metrics: MusicTrackLayoutMetrics { MusicTrackLayoutMetrics(width: width) }
    var wide: Bool { metrics.wide }
    var inset: CGFloat { metrics.inset }
    var outside: CGFloat { metrics.outside }
    var artworkSize: CGFloat { metrics.artwork }
    var canOpenCover: Bool { track.musicCover != nil }
    var animation: Animation? { reduceMotion ? nil : .timingCurve(0.18, 0.80, 1, 1, duration: 0.22) }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 16) {
                        presentation
                        trackInsights
                        storiesRail
                        tabs
                    }
                    .padding(.horizontal, outside)
                    .padding(.top, 16)
                    .padding(.bottom, 60)
                    .frame(maxWidth: 1_920)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(coverOpen)
                }
                .scrollIndicators(.hidden)
                .gamepadScrolling(scroll)
                .onChange(of: focus) { _, next in
                    guard let next, !coverOpen, panel == nil, composer == nil else { return }
                    withAnimation(animation) { proxy.scrollTo(next, anchor: .center) }
                }
                .onChange(of: scrollToComment) { _, id in
                    if let id { withAnimation(animation) { proxy.scrollTo(Target.comment(id), anchor: .center) } }
                }
            }
            .onChange(of: geometry.size.width, initial: true) { _, width in self.width = min(1_920, width) }
            .overlay { if coverOpen { coverPreview } }
        }
        .background(MizonPalette.surface.opacity(0.10))
        .task(id: details.id) {
            playerVolume = Double(music.player.volume)
            if let linkedCommentID {
                highlightedComment = linkedCommentID
                await Task.yield()
                scrollToComment = linkedCommentID
            }
            await details.load()
        }
        .task(id: details.pane) { await details.loadPane() }
        .task(id: controllerIsCurrent && scenePhase == .active) {
            if controllerIsCurrent && scenePhase == .active { await followPlayhead() }
        }
        .task(id: controllerIsCurrent && scenePhase == .active && !controllerInputSuspended) {
            if controllerIsCurrent && scenePhase == .active && !controllerInputSuspended {
                let playhead = position
                await details.observeAudience { playhead.seconds }
            }
        }
        .task(id: canUseController) {
            if canUseController { await watchController() }
        }
        .onDisappear {
            exportTask?.cancel()
            actionsInFlight.cancel()
            #if os(macOS)
            floatWindow.close()
            #endif
        }
        .sheet(item: $panel) { active in panelBody(active) }
        .sheet(item: $composer) { draft in discussionComposer(draft) }
        .alert(text("NewPlaylist"), isPresented: $createsPlaylist) {
            TextField(text("PlaylistTitle"), text: $playlistName)
            Button(text("TrackNewPlaylist")) {
                let title = playlistName
                run { if await details.createPlaylist(title) { playlistName = "" } }
            }
            Button(text("TrackClose"), role: .cancel) {}
        }
        .alert(text(contextNotice ?? "TrackDone"), isPresented: Binding(
            get: { contextNotice != nil }, set: { if !$0 { contextNotice = nil } }
        )) { Button(text("TrackDone"), role: .cancel) {} }
        .fileExporter(isPresented: $exporting, item: exportDocument, defaultFilename: exportDocument?.url.lastPathComponent) { _ in
            exportDocument = nil
        } onCancellation: {
            exportDocument = nil
        }
        .overlay(alignment: .bottom) {
            #if os(iOS)
            if floating { inAppFloatingPlayer }
            #endif
        }
    }

    private var presentation: some View {
        VStack(spacing: 0) {
            Group {
                if wide {
                    HStack(alignment: .top, spacing: 32) {
                        artwork
                        information.padding(.top, 16)
                    }
                } else {
                    VStack(spacing: 24) { artwork; information }
                }
            }
            .padding(.top, 32)
            .padding(.horizontal, inset)
            lyricsArea.padding(.horizontal, inset).padding(.top, 16).padding(.bottom, 12)
            if downloadCompleted {
                Label(text("TrackReadyDownload"), systemImage: "checkmark.circle")
                    .font(localization.font(12)).foregroundStyle(MizonPalette.secondaryText).padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity)
        .background(MusicHomeStyle.secondaryCard, in: .rect(cornerRadius: 8))
        .accessibilityIdentifier("music.track.details")
    }

    private var artwork: some View {
        TrackPulsingArtwork(details: details, position: position, size: artworkSize,
                            namespace: coverNamespace, coverOpen: coverOpen, accent: palette, focus: focus == .cover) {
            if canOpenCover { showCover() }
        }
        .id(Target.cover)
    }

    private var information: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 9) {
                heading
                waveAndTransport
                actions
                contributors
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if metrics.usesVerticalVolume {
                Slider(value: volume, in: 0...1) { Text(text("Volume")) }
                    .tint(MizonPalette.accent)
                    .frame(width: 280)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 32, height: 280)
                    .modifier(TrackFocus(isFocused: focus == .volume))
                    .id(Target.volume)
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(track.title)
                .font(localization.font(24, weight: .bold))
                .textSelection(.enabled)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("music.track.title")
            TrackControlsLayout(horizontal: 8, vertical: 5) {
                if let persian = track.persianTitle, persian != track.title, !persian.isEmpty {
                    Text(persian).font(WindowsTypography.iranSans(22)).lineLimit(1)
                        .textSelection(.enabled)
                }
                if let album = track.musicAlbum {
                    control(.album, text: localized(album.title, album.persianTitle), tint: MizonPalette.accent, font: 20)
                }
                HStack(spacing: 1) {
                    control(.views, text: String(track.viewsCount.formatted()), symbol: "eye", label: text("ViewsAudience"))
                    control(.live, text: details.liveViewers.formatted(), symbol: "dot.radiowaves.left.and.right", label: text("LiveAudience"), tint: musicColor("87D995"))
                }
                .padding(1)
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(MusicHomeChrome.hairline).allowsHitTesting(false))
            }
            if let label = track.musicLabel {
                Text(localized(label.title, label.persianTitle)).font(localization.font(13))
                    .foregroundStyle(MizonPalette.accent)
            }
            if !track.musicGenres.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(track.musicGenres, id: \.publicId) { genre in
                            Text(localized(genre.title, genre.persianTitle))
                                .font(localization.font(11, weight: .semibold))
                                .padding(.vertical, 4).padding(.horizontal, 9)
                                .background(.white.opacity(0.06), in: .capsule)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
    }

    private var waveAndTransport: some View {
        VStack(alignment: .leading, spacing: 5) {
            TrackControlsLayout(horizontal: 4, vertical: 6) {
                control(.play, symbol: isTrackPlaying ? "pause.fill" : "play.fill",
                        label: text(isTrackPlaying ? "Pause" : "Play"), tint: MizonPalette.accent,
                        disabled: music.requestingPlayback, accented: true)
                control(.repeatTrack, symbol: "repeat.1", label: text("Repeat"), tint: music.repeatingTrack == details.id ? MizonPalette.accent : nil)
                control(.rewind, symbol: "gobackward.5", label: text("TrackSeek"), disabled: details.duration == 0)
                control(.forward, symbol: "goforward.5", label: text("TrackSeek"), disabled: details.duration == 0)
                TrackTimeLabel(position: position, duration: details.duration)
                control(.download, symbol: "arrow.down", label: text("Download"), disabled: downloading, accented: true)
                control(.shortcut, symbol: "desktopcomputer", label: text("Shortcut"))
                control(.floating, symbol: "pip", label: text("FloatingPlayer"))
                control(.copy, symbol: "document.on.document", label: text("CopyLink"))
            }
            TrackWaveformPlayback(details: details, position: position,
                                  seek: { details.seek(to: $0, title: title) },
                                  addComment: { if details.duration > 0 { startComment(at: $0) } },
                                  openComment: locateComment)
                .modifier(TrackFocus(isFocused: focus == .waveform))
                .id(Target.waveform)
            if details.failures.contains(.waveform) { control(.retry(.waveform), text: text("TrackRetry"), symbol: "arrow.clockwise") }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 7) {
            TrackControlsLayout {
                control(.support, symbol: "heart.fill", label: text("Support"), tint: MizonPalette.accent)
                control(.playlists, text: text("AddToPlaylist"))
                control(.output, text: text("AudioOutput"), symbol: "speaker.wave.2")
                if track.musicVideo != nil {
                    Button { perform(.video) } label: {
                        HStack(spacing: 7) {
                            MusicArtwork(mediaID: track.musicVideo?.coverMediaPublicId, model: music, symbol: "video")
                                .frame(width: 46, height: 28)
                                .clipShape(.rect(cornerRadius: 5))
                            Text(text("MusicVideo")).font(localization.font(12))
                        }
                        .padding(.horizontal, 5)
                    }
                    .buttonStyle(TrackButtonStyle(focused: focus == .video))
                    .id(Target.video)
                    .accessibilityIdentifier("music.track.video")
                }
                control(.like, text: track.likesCount > 0 ? track.likesCount.formatted() : nil,
                        symbol: track.likedByMe ? "heart.fill" : "heart",
                        label: text(track.likedByMe ? "TrackUnlike" : "TrackLike"),
                        tint: track.likedByMe ? MizonPalette.accent : nil, disabled: details.liking)
            }
            if !details.reactions.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(details.reactions) { reaction in
                            Button { perform(.reaction(reaction.id)) } label: {
                                HStack(spacing: 4) {
                                    Text(reaction.emoji).font(.system(size: 16))
                                    if reaction.count > 0 { Text(reaction.count.formatted()).font(localization.font(14)) }
                                }
                                .padding(.horizontal, 6).padding(.vertical, 4)
                            }
                            .buttonStyle(TrackButtonStyle(focused: focus == .reaction(reaction.id),
                                                          selected: reaction.selected, highlight: musicColor("0078D4")))
                            .disabled(details.busyIDs.contains(reaction.id))
                            .accessibilityAddTraits(reaction.selected ? .isSelected : [])
                            .id(Target.reaction(reaction.id))
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .animation(animation, value: details.reactions.map(\.count))
            }
        }
    }

    private var contributors: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(details.credits.enumerated()), id: \.offset) { index, credit in
                        let target = Target.artist(credit.personPublicId, credit.musicContributorTypePublicId)
                        Button { perform(target) } label: {
                            HStack(spacing: 6) {
                                MusicArtwork(mediaID: credit.profileMediaPublicId, model: music, symbol: "person.fill")
                                    .frame(width: 24, height: 24).clipShape(.circle)
                                Text([credit.firstName, credit.lastName].joined(separator: " "))
                                    .font(localization.font(12)).lineLimit(1)
                                FluentIcon(symbol: .musicNote1, size: 12).opacity(0.75)
                            }
                            .padding(.horizontal, 5).padding(.vertical, 2)
                        }
                        .buttonStyle(TrackButtonStyle(focused: focus == target, radius: 14))
                        .accessibilityHint(localized(credit.musicContributorTypeTitle, credit.musicContributorTypePersianTitle))
                        .id(target)
                    }
                }
            }
            .scrollIndicators(.hidden)
            Label(text("Doughnut"), systemImage: "seal")
                .font(localization.font(12)).foregroundStyle(MizonPalette.secondaryText)
                .padding(8).background(.white.opacity(0.045), in: .rect(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.opacity(0.30)))
        }
        .padding(.top, 3)
    }

    private var lyricsArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            TrackControlsLayout(horizontal: 8) {
                control(.lyrics, text: text("Lyrics"), symbol: "text.aligncenter", selected: lyricsOpen)
                if details.stemMix?.isAvailable == true {
                    if details.mixActive {
                        Slider(value: Binding(get: { details.balance }, set: {
                            details.balance = $0
                            music.updateTrackMixBalance($0, for: details.id)
                        }), in: -100...100) { Text(text("MixBalance")) }
                        .frame(width: 150)
                        .modifier(TrackFocus(isFocused: focus == .balance)).id(Target.balance)
                    }
                    control(.mix, text: text("StemMixer"), symbol: "mic",
                            disabled: details.mixLoading || music.playingTrack != details.id,
                            selected: details.mixActive)
                }
            }
            if !metrics.usesVerticalVolume {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.2")
                    Slider(value: volume, in: 0...1) { Text(text("Volume")) }.tint(MizonPalette.accent)
                        .modifier(TrackFocus(isFocused: focus == .volume)).id(Target.volume)
                }
                .foregroundStyle(MizonPalette.secondaryText)
            }
            if lyricsOpen {
                TrackLyrics(details: details, position: position, focus: focus, select: perform)
                    .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : -4)))
            } else if !details.lyrics.isEmpty {
                TrackCurrentLyric(details: details, position: position)
            }
        }
    }

    private var volume: Binding<Double> {
        Binding(get: { playerVolume }, set: {
            playerVolume = min(1, max(0, $0))
            music.player.volume = Float(playerVolume)
        })
    }

    var canUseController: Bool {
        #if os(macOS)
        scenePhase == .active && controllerIsCurrent && !controllerInputSuspended && (appearsActive || panel != nil || composer != nil)
        #else
        scenePhase == .active && controllerIsCurrent && !controllerInputSuspended
        #endif
    }

    private func followPlayhead() async {
        while !Task.isCancelled {
            let at = music.playingTrack == details.id ? music.player.currentTime().seconds : 0
            if at.isFinite { position.seconds = max(0, at) }
            do { try await Task.sleep(for: isTrackPlaying ? .milliseconds(33) : .milliseconds(220)) }
            catch { return }
        }
    }

    func control(_ target: Target, text title: String? = nil, symbol: String? = nil, label: String? = nil,
                 tint: Color? = nil, font size: CGFloat = 12,
                 disabled: Bool = false, accented: Bool = false, selected: Bool = false) -> some View {
        Button { perform(target) } label: {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 15, weight: .medium)) }
                if let title { Text(title).font(localization.font(size, weight: .semibold)).lineLimit(1) }
            }
            .foregroundStyle(tint ?? MizonPalette.ink)
            .padding(.horizontal, title == nil ? 9 : 10)
            .frame(minWidth: 34, minHeight: 34)
            .contentShape(.rect)
        }
        .buttonStyle(TrackButtonStyle(focused: focus == target, selected: selected, accentFill: accented))
        .disabled(disabled)
        .accessibilityLabel(label ?? title ?? "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .id(target)
    }

    func run(_ work: @escaping @MainActor () async -> Void) {
        actionsInFlight.run(work)
    }

    func localized(_ title: String, _ persian: String?) -> String {
        if rtl, let persian, !persian.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return persian }
        return title
    }

    func text(_ key: String) -> String { localization.string(key, table: "MusicDetails") }

    func format(_ key: String, _ values: String...) -> String {
        MusicReferenceRailFormat.substitute(text(key), with: values)
    }

    static func time(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let seconds = Int(min(value, 1_000_000))
        return seconds >= 3_600 ? String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct MusicTrackLayoutMetrics {
    let width: CGFloat
    var wide: Bool { width > 1_000 }
    var inset: CGFloat { width < 680 ? 16 : 32 }
    var outside: CGFloat { width < 540 ? 14 : 32 }
    var artwork: CGFloat { min(280, max(1, width - outside * 2 - inset * 2)) }
    var usesVerticalVolume: Bool { width >= 680 }

    init(width: CGFloat) {
        self.width = width.isFinite ? max(1, min(1_920, width)) : 390
    }
}

@MainActor
final class TrackPageActions {
    private var running: [UUID: Task<Void, Never>] = [:]

    func run(_ work: @escaping @MainActor () async -> Void) {
        let token = UUID()
        running[token] = Task { [weak self] in
            await work()
            self?.running[token] = nil
        }
    }

    func cancel() {
        for task in running.values { task.cancel() }
        running.removeAll()
    }
}

struct TrackFocus: ViewModifier {
    let isFocused: Bool
    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(isFocused ? MizonPalette.accent : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
    }
}

struct TrackButtonStyle: ButtonStyle {
    var focused = false
    var selected = false
    var radius: CGFloat = 8
    var highlight = MizonPalette.accent
    var accentFill = false

    func makeBody(configuration: Configuration) -> some View {
        Body(label: configuration.label, pressed: configuration.isPressed, style: self)
    }

    private struct Body<Label: View>: View {
        let label: Label
        let pressed: Bool
        let style: TrackButtonStyle
        @State private var hovered = false
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: style.radius)
            label
                .background(style.accentFill ? style.highlight.opacity(0.28) : .white.opacity(hovered ? 0.105 : 0.06), in: shape)
                .overlay { shape.strokeBorder(style.focused || style.selected ? style.highlight : .white.opacity(0.10),
                                              lineWidth: style.focused ? 2 : 1).allowsHitTesting(false) }
                .opacity(enabled ? 1 : 0.45)
                .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
                .contentShape(shape)
                .onHover { hovered = enabled && $0 }
                .authHandPointer(enabled: enabled)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovered)
        }
    }
}
#endif
