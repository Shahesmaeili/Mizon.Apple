#if os(macOS) || os(iOS)
import MizonAPIClient
import MizonAppleCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct MusicPlaylistPage: View {
    private enum Target: Hashable {
        case back, refresh, library, copy, play, track(UUID), previous, next, dismissMessage
    }

    private struct PageRequest: Hashable {
        let page: Int
        let id = UUID()
    }

    private struct Message: Equatable {
        let key: String
        var warning = false
    }

    let playlistID: UUID
    let music: MusicHomeViewModel
    let deepLink: MizonDeepLinkRouter.AuthorizedLink?
    let coverNamespace: Namespace.ID
    let openLibrary: () -> Void
    let openTrack: (UUID) -> Void
    let playPlaylist: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.controllerInputSuspended) private var controllerInputSuspended
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controllerScroll = GamepadScroll()
    @FocusState private var focus: Target?
    @State private var details: MusicPlaylistDetailsViewModel
    @State private var request = PageRequest(page: 0)
    @State private var completedRequest: UUID?
    @State private var resolvedLink: UUID?
    @State private var message: Message?
    @State private var headerPresented = false
    @State private var requestedPlayback = false
    private let localization = AuthLocalization()
    private let accent = musicColor("C7A0F6")

    init(playlistID: UUID, music: MusicHomeViewModel, deepLink: MizonDeepLinkRouter.AuthorizedLink?,
         coverNamespace: Namespace.ID, openLibrary: @escaping () -> Void,
         openTrack: @escaping (UUID) -> Void, playPlaylist: @escaping () -> Void) {
        self.playlistID = playlistID
        self.music = music
        self.deepLink = deepLink
        self.coverNamespace = coverNamespace
        self.openLibrary = openLibrary
        self.openTrack = openTrack
        self.playPlaylist = playPlaylist
        _details = State(initialValue: MusicPlaylistDetailsViewModel(
            playlistID: playlistID, service: music.service, session: music.session))
    }

    private var title: String { details.details?.title ?? text("Title") }
    private var tracks: [MusicTabMusicItemResponse] { details.details?.musics ?? [] }
    private var loading: Bool { details.isLoading || completedRequest != request.id }

    var body: some View {
        GeometryReader { geometry in
            let width = max(0, min(1600, geometry.size.width) - 32)
            let compact = width < 640 || geometry.size.height - 32 < 540
            VStack(spacing: compact ? 10 : 16) {
                header(compact: compact, narrow: width < 420, showLibraryLabel: width >= 640)
                    .opacity(headerPresented || reduceMotion ? 1 : 0)
                tracksSection(compact: compact)
                paging
            }
            .padding(16)
            .frame(maxWidth: 1600)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.layoutDirection, .leftToRight)
        #if os(iOS)
        .background { WindowGlass().ignoresSafeArea(.container, edges: .horizontal) }
        #endif
        .navigationTitle(title)
        .navigationTransition(.automatic)
        #if os(iOS)
        .toolbar(.visible, for: .navigationBar)
        #else
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { dismiss() } label: { Image(systemName: "chevron.backward") }
                    .accessibilityLabel(localization.string("Back", table: "MusicHome"))
                    .accessibilityIdentifier("music.destination.back")
                    .keyboardShortcut(.cancelAction)
                    .focused($focus, equals: .back)
            }
        }
        #endif
        .onAppear {
            guard !headerPresented else { return }
            withAnimation(reduceMotion ? nil : .linear(duration: 0.260)) { headerPresented = true }
        }
        .onChange(of: music.playlistPlaybackStatus) { _, status in
            guard requestedPlayback, status != .preparing else { return }
            requestedPlayback = false
            if status == .unavailable { show(Message(key: "PlaybackFailed", warning: true)) }
        }
        .task(id: request) { await load(request) }
        .task(id: deepLink?.id) {
            guard let deepLink, resolvedLink != deepLink.id, completedRequest == request.id else { return }
            if details.details != nil, !details.hasError { completeLink(deepLink) }
            else { request = PageRequest(page: 0) }
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await observeController() }
        }
        .onDisappear {
            if let deepLink, resolvedLink != deepLink.id {
                resolvedLink = deepLink.id
                MizonDeepLinkRouter.shared.fail(deepLink, code: "page_changed",
                                               message: "The active page changed before navigation completed.")
            }
        }
    }

    private func header(compact: Bool, narrow: Bool, showLibraryLabel: Bool) -> some View {
        VStack(spacing: compact ? 10 : 16) {
            HStack(spacing: compact ? 12 : 24) {
                VStack(alignment: .trailing, spacing: compact ? 6 : 10) {
                    if !compact {
                        HStack(spacing: 6) {
                            Text(text(details.details.map { $0.isOwner ? "Owner" : "Friend" } ?? "Title"))
                                .font(localization.font(10))
                            FluentIcon(symbol: .musicNote1, size: 12)
                        }
                        .foregroundStyle(accent)
                    }
                    Text(title)
                        .font(localization.font(compact ? 20 : 28, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [.primary, musicColor("E7D9FC")],
                                                        startPoint: .leading, endPoint: .trailing))
                        .lineLimit(compact ? 1 : 2)
                        .accessibilityAddTraits(.isHeader)
                    Text(details.details.map { format("TrackCount", number($0.musicsCount)) } ?? text("LoadingTracks"))
                        .font(localization.font(12))
                        .foregroundStyle(Color.primary.opacity(0.65))
                        .lineLimit(2)
                }
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                cover(compact: compact, size: compact ? (narrow ? 64 : 84) : 166)
                    .padding(compact ? 2 : 6)
            }
            HStack(spacing: 8) {
                action(.refresh, text("Refresh"), symbol: .arrowClockwise, iconSize: 16, iconOnly: true)
                    .disabled(loading)
                Spacer(minLength: 0)
                action(.library, text("MyPlaylists"), symbol: .musicNote1, iconSize: 15, iconOnly: !showLibraryLabel)
                action(.copy, text("CopyLink"), symbol: .link, iconSize: 16, iconOnly: true)
                action(.play, text(narrow ? "Play" : "PlayPlaylist"), symbol: .play, iconSize: 16, primary: true)
                    .accessibilityLabel(text("PlayAll"))
                    .disabled(loading || !details.canPlay || music.playlistPlaybackStatus == .preparing)
            }
        }
        .padding(compact ? 14 : 22)
        .background(MusicHomeStyle.secondaryCard, in: .rect(cornerRadius: 20))
        .background {
            RoundedRectangle(cornerRadius: 19).fill(
                LinearGradient(stops: [.init(color: accent.opacity(31 / 255), location: 0),
                                       .init(color: accent.opacity(6 / 255), location: 0.55),
                                       .init(color: .clear, location: 1)],
                               startPoint: .topTrailing, endPoint: .bottomLeading))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(24 / 255))
                .allowsHitTesting(false)
        }
    }

    private func cover(compact: Bool, size: CGFloat) -> some View {
        ZStack {
            coverPlate(fill: 31, stroke: 56).padding(.horizontal, 14).offset(y: -6)
            coverPlate(fill: 25, stroke: 50).padding(.horizontal, 7).offset(y: -3)
            RoundedRectangle(cornerRadius: 16).fill(MusicHomeStyle.inset)
            RoundedRectangle(cornerRadius: 15).fill(
                LinearGradient(colors: [accent.opacity(56 / 255), musicColor("7EBDF5").opacity(8 / 255)],
                               startPoint: .topTrailing, endPoint: .bottomLeading))
            FluentIcon(symbol: .musicNote1, size: compact ? 28 : 46).foregroundStyle(accent.opacity(0.6))
            if let id = details.artworkID {
                MusicArtwork(mediaID: id, model: music, symbol: "").clipShape(.rect(cornerRadius: 16))
            }
            RoundedRectangle(cornerRadius: 16).fill(musicColor("111826").opacity(12 / 255))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(40 / 255)) }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func coverPlate(fill: Double, stroke: Double) -> some View {
        RoundedRectangle(cornerRadius: 16).fill(accent.opacity(fill / 255))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(stroke / 255)) }
    }

    private func tracksSection(compact: Bool) -> some View {
        VStack(spacing: 10) {
            MusicReferenceRailHeading(title: text("Tracks"), symbol: .musicNote1, accent: "C7A0F6",
                                      localization: localization, compact: true)
                .environment(\.layoutDirection, localization.isPersian ? .rightToLeft : .leftToRight)
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(tracks.enumerated()), id: \.element.publicId) { index, track in
                            trackRow(track, rank: details.rank(at: index))
                                .id(Target.track(track.publicId))
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 5)
                    .padding(.bottom, 11)
                }
                .gamepadScrolling(controllerScroll)
                .scrollIndicators(.hidden)
                .accessibilityLabel(text("TrackList"))
                .onChange(of: completedRequest) {
                    if !details.hasError, let first = tracks.first {
                        scroll.scrollTo(Target.track(first.publicId), anchor: .top)
                    }
                }
                .onChange(of: focus) { _, focused in
                    if case .track = focused { scroll.scrollTo(focused, anchor: .center) }
                }
            }
            .overlay {
                if loading {
                    MusicReferenceRailSkeleton(title: text("LoadingTracks"), minimumHeight: compact ? 90 : 160,
                                               localization: localization)
                        .frame(maxHeight: .infinity, alignment: .top)
                } else if details.details?.musicsCount == 0, !details.hasError {
                    VStack(spacing: 14) {
                        FluentIcon(symbol: .musicNote1, size: 28)
                            .foregroundStyle(accent)
                            .frame(width: 62, height: 62)
                            .background(accent.opacity(20 / 255), in: .rect(cornerRadius: 20))
                            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(accent.opacity(36 / 255)) }
                        Text(text("Empty")).font(localization.font(13))
                            .foregroundStyle(Color.primary.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: 340)
                    .padding(16)
                }
            }
            .overlay(alignment: .bottom) {
                if let message { messageBar(message).padding(8) }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func trackRow(_ track: MusicTabMusicItemResponse, rank: Int) -> some View {
        let target = Target.track(track.publicId)
        let trackTitle = localization.isPersian && !((track.persianTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            ? track.persianTitle ?? track.title : track.title
        let artist = track.contributors.map { [$0.firstName, $0.lastName].filter { !$0.isEmpty }.joined(separator: " ") }
            .joined(separator: localization.isPersian ? "، " : ", ")
        return Button { perform(target) } label: {
            HStack(spacing: 10) {
                FluentIcon(symbol: .play, size: 16).foregroundStyle(accent).frame(width: 24)
                HStack(spacing: 5) {
                    FluentIcon(symbol: .heart, size: 12)
                    Text(MusicReferenceRailFormat.compactNumber(track.likesCount, locale: locale))
                        .font(localization.font(11))
                }
                .opacity(0.65)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(trackTitle).font(localization.font(13, weight: .semibold)).lineLimit(1)
                    Text(artist).font(localization.font(11)).foregroundStyle(Color.primary.opacity(0.55)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                trackCover(track)
                Text(String(format: "%02d", rank))
                    .font(localization.font(12)).foregroundStyle(Color.primary.opacity(0.4))
                    .frame(width: 22)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlaylistSurfaceStyle(kind: .row, focused: focus == target))
        .focusable().focused($focus, equals: target)
        .focusEffectDisabled()
        .disabled(loading)
        .help(trackTitle)
        .accessibilityLabel(trackTitle)
        .accessibilityHint(text("OpenTrack"))
        .accessibilityIdentifier("music.playlist.track.\(track.publicId.uuidString.lowercased())")
    }

    private func trackCover(_ track: MusicTabMusicItemResponse) -> some View {
        let image = ZStack {
            RoundedRectangle(cornerRadius: 9).fill(accent.opacity(24 / 255))
            FluentIcon(symbol: .musicNote1, size: 20).foregroundStyle(Color.primary.opacity(0.5))
            if let id = track.coverMediaPublicId { MusicArtwork(mediaID: id, model: music, symbol: "") }
            RoundedRectangle(cornerRadius: 9).strokeBorder(.white.opacity(24 / 255))
        }
        .frame(width: 52, height: 52)
        .clipShape(.rect(cornerRadius: 9))
        .accessibilityHidden(true)
        #if os(iOS)
        return image.matchedTransitionSource(id: track.publicId, in: coverNamespace) { source in
            source.clipShape(.rect(cornerRadius: 9))
        }
        #else
        return image
        #endif
    }

    private var paging: some View {
        HStack(spacing: 10) {
            action(.previous, text("Previous"), symbol: .chevronLeft, iconSize: 12, symbolFirst: true)
                .disabled(loading || !details.canGoBack)
            Text(format("PageNumber", number(details.page + 1)))
                .font(localization.font(11)).foregroundStyle(Color.primary.opacity(0.6))
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("music.playlist.page-number")
            action(.next, text("Next"), symbol: .chevronRight, iconSize: 12)
                .disabled(loading || !details.canGoForward)
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
        .overlay(alignment: .top) { Rectangle().fill(.white.opacity(18 / 255)).frame(height: 1).allowsHitTesting(false) }
    }

    private func action(_ target: Target, _ label: String, symbol: FluentSymbol, iconSize: CGFloat,
                        iconOnly: Bool = false, primary: Bool = false, symbolFirst: Bool = false) -> some View {
        Button { perform(target) } label: {
            HStack(spacing: 7) {
                if symbolFirst { FluentIcon(symbol: symbol, size: iconSize) }
                if !iconOnly { Text(label).font(localization.font(11, weight: primary ? .semibold : .regular)).lineLimit(1) }
                if !symbolFirst { FluentIcon(symbol: symbol, size: iconSize) }
            }
            .padding(.horizontal, iconOnly ? 0 : 12)
            .frame(minWidth: iconOnly ? 38 : 0, minHeight: 38)
        }
        .buttonStyle(PlaylistSurfaceStyle(kind: primary ? .primary : .action, focused: focus == target))
        .focusable().focused($focus, equals: target)
        .focusEffectDisabled()
        .accessibilityLabel(label)
        .accessibilityIdentifier("music.playlist.\(target)")
        .help(label)
    }

    private func messageBar(_ message: Message) -> some View {
        HStack(spacing: 10) {
            action(.dismissMessage, text("Dismiss"), symbol: .dismiss, iconSize: 14, iconOnly: true)
            Text(text(message.key)).font(localization.font(12))
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Image(systemName: message.warning ? "exclamationmark.triangle" : "info.circle")
                .foregroundStyle(message.warning ? .yellow : accent).accessibilityHidden(true)
        }
        .padding(.horizontal, 10)
        .background(MizonPalette.surface, in: .rect(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.16)).allowsHitTesting(false) }
    }

    private func perform(_ target: Target) {
        switch target {
        case .back: dismiss()
        case .refresh:
            guard !loading else { return }
            request = PageRequest(page: 0)
        case .library: openLibrary()
        case .copy:
            let link = MizonDeepLink.playlist(playlistID).canonicalURI
            #if os(macOS)
            NSPasteboard.general.clearContents()
            if !NSPasteboard.general.setString(link, forType: .string) {
                show(Message(key: "CopyFailed", warning: true))
                return
            }
            #else
            UIPasteboard.general.string = link
            #endif
            show(Message(key: "Copied"))
        case .play:
            if !loading, details.canPlay, music.playlistPlaybackStatus != .preparing {
                requestedPlayback = true
                playPlaylist()
            }
        case .track(let id):
            if !loading, tracks.contains(where: { $0.publicId == id }) { openTrack(id) }
        case .previous:
            if !loading, details.canGoBack { request = PageRequest(page: details.page - 1) }
        case .next:
            if !loading, details.canGoForward { request = PageRequest(page: details.page + 1) }
        case .dismissMessage: message = nil
        }
    }

    private func load(_ requested: PageRequest) async {
        guard completedRequest != requested.id else { return }
        let link = deepLink.flatMap { $0.id != resolvedLink ? $0 : nil }
        if let link, !MizonDeepLinkRouter.shared.isActive(link) { return }
        message = nil
        guard let loaded = await details.load(page: requested.page),
              !Task.isCancelled, request == requested else { return }
        completedRequest = requested.id
        if loaded {
            if let link { completeLink(link) }
            AccessibilityNotification.Announcement(format("PageLoaded", title, number(details.page + 1))).post()
        } else {
            if let link, resolvedLink != link.id {
                resolvedLink = link.id
                MizonDeepLinkRouter.shared.fail(link, code: "page_unavailable", message: "The playlist could not be loaded.")
            }
            show(Message(key: "LoadFailed", warning: true))
        }
    }

    private func completeLink(_ link: MizonDeepLinkRouter.AuthorizedLink) {
        guard resolvedLink != link.id, MizonDeepLinkRouter.shared.isActive(link) else { return }
        resolvedLink = link.id
        MizonDeepLinkRouter.shared.complete(link, stage: .completed)
    }

    private func show(_ status: Message) {
        message = status
        AccessibilityNotification.Announcement(text(status.key)).post()
    }

    private var targets: [Target] {
        var items: [Target] = [.back]
        if !loading { items.append(.refresh) }
        items.append(contentsOf: [.library, .copy])
        if !loading {
            if details.canPlay, music.playlistPlaybackStatus != .preparing { items.append(.play) }
            items += tracks.map { .track($0.publicId) }
            if details.canGoBack { items.append(.previous) }
            if details.canGoForward { items.append(.next) }
        }
        if message != nil { items.append(.dismissMessage) }
        return items
    }

    private func observeController() async {
        await GamepadControls.observe(when: { scenePhase == .active && !controllerInputSuspended }) { input in
            if input == .back {
                if message != nil { perform(.dismissMessage) }
                else { dismiss() }
                return
            }
            let available = targets
            if input == .accept {
                if let focus, available.contains(focus) { perform(focus) }
                else { focus = available.first }
            } else if input == .clear, available.contains(.play) {
                perform(.play)
            } else if input == .reveal, available.contains(.copy) {
                perform(.copy)
            } else if input == .primary, available.contains(.play) {
                focus = .play
            } else if input == .reset {
                focus = available.first
            } else if let step = input.scrollStep {
                controllerScroll.move(by: step)
            } else if let step = input.focusStep {
                focus = available.gamepadTarget(from: focus, step: step)
            }
        }
    }

    private var locale: Locale { Locale(identifier: localization.isPersian ? "fa-IR" : "en-US") }
    private func number(_ value: Int) -> String { value.formatted(.number.locale(locale)) }
    private func text(_ key: String) -> String { localization.string(key, table: "MusicPlaylist") }
    private func format(_ key: String, _ values: String...) -> String { MusicReferenceRailFormat.substitute(text(key), with: values) }
}

private struct PlaylistSurfaceStyle: ButtonStyle {
    enum Kind { case row, action, primary }

    let kind: Kind
    let focused: Bool

    func makeBody(configuration: Configuration) -> some View {
        Surface(label: configuration.label, pressed: configuration.isPressed, kind: kind, focused: focused)
    }

    private struct Surface<Label: View>: View {
        let label: Label
        let pressed: Bool
        let kind: Kind
        let focused: Bool
        @State private var hovered = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let accent = musicColor("C7A0F6")
            let shape = RoundedRectangle(cornerRadius: kind == .row ? 13 : 11)
            let active = enabled && hovered
            let fill = kind == .row ? MusicHomeStyle.secondaryCard : kind == .primary ? accent : Color.white.opacity(8 / 255)
            let border = kind == .primary ? musicColor("E4D1FC") : Color.white.opacity(kind == .row ? 13 / 255 : 24 / 255)
            label
                .foregroundStyle(kind == .primary ? musicColor("20152E") : .primary)
                .background(shape.fill(fill))
                .overlay {
                    shape.fill(accent.opacity(enabled ? pressed ? 0.17 : active ? 0.08 : 0 : 0))
                        .overlay { shape.strokeBorder(focused ? accent : active && kind == .row ? accent.opacity(0.22) : border) }
                        .allowsHitTesting(false)
                }
                .contentShape(shape)
                .opacity(enabled ? 1 : 0.45)
                .scaleEffect(kind == .row && !reduceMotion && enabled ? pressed ? 0.995 : active ? 1.003 : 1 : 1)
                .onHover { hovered = $0 }
                .authHandPointer(enabled: enabled)
                .animation(reduceMotion ? nil : .timingCurve(0.18, 0.80, 1, 1, duration: 0.18), value: active)
                .animation(reduceMotion ? nil : .timingCurve(0.18, 0.80, 1, 1, duration: 0.18), value: pressed)
        }
    }
}
#endif
