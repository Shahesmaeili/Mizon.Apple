#if os(macOS) || os(iOS)
import GameController
import MizonAPIClient
import MizonAppleCore
import SwiftUI

struct MusicLibraryBrowser: View {
    private enum Target: Hashable { case playlist(UUID), more, retry, close }

    let model: MusicHomeViewModel
    let deepLink: MizonDeepLinkRouter.AuthorizedLink?
    var inNavigationStack = false
    let openPlaylist: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focus: Target?
    @State private var items: [MusicLibraryPlaylistItemResponse] = []
    @State private var failed = false
    @State private var nextCursor: String?
    @State private var page = 0
    @State private var loading = true
    @State private var linkResolved = false
    private var localization = AuthLocalization()

    var body: some View {
        Group {
            if inNavigationStack { library }
            else { NavigationStack { library } }
        }
        .task(id: page) { await loadPage() }
        .task(id: scenePhase) {
            if scenePhase == .active { await observeController() }
        }
        .onDisappear {
            if let deepLink, !linkResolved {
                linkResolved = true
                MizonDeepLinkRouter.shared.fail(deepLink, code: "page_changed",
                                               message: "The active page changed before navigation completed.")
            }
        }
        .frame(minWidth: 310, minHeight: 300)
    }

    private var library: some View {
        ScrollViewReader { scroll in
            List {
                ForEach(items, id: \.publicId) { playlist in
                    Button { openPlaylist(playlist.publicId) } label: {
                        HStack(spacing: 10) {
                            MusicArtwork(mediaID: playlist.lastMusicCoverMediaPublicId, model: model, symbol: "music.note.list")
                                .frame(width: 44, height: 44).clipShape(.rect(cornerRadius: 7))
                            Text(playlist.title)
                            Spacer()
                            Text(playlist.musicsCount, format: .number).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .authHandPointer(enabled: true)
                    .focusable().focused($focus, equals: .playlist(playlist.publicId))
                    .id(Target.playlist(playlist.publicId))
                }
                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if failed {
                    Text(text("LibraryError")).foregroundStyle(.secondary)
                    Button(text("Retry")) { page += 1 }
                        .focusable().focused($focus, equals: .retry).id(Target.retry)
                } else if nextCursor != nil {
                    Button(text("MorePlaylists")) { page += 1 }
                        .focusable().focused($focus, equals: .more).id(Target.more)
                } else if items.isEmpty {
                    Text(text("LibraryEmpty")).foregroundStyle(.secondary)
                }
            }
            .onChange(of: focus) { _, target in
                if let target, target != .close { scroll.scrollTo(target, anchor: .center) }
            }
        }
        .navigationTitle(text("LibraryTitle"))
        #if os(macOS)
        .navigationBarBackButtonHidden(inNavigationStack)
        #endif
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .navigation) {
                if inNavigationStack {
                    Button { dismiss() } label: { Image(systemName: "chevron.backward") }
                        .accessibilityLabel(localization.string("Back", table: "MusicHome"))
                        .accessibilityIdentifier("music.destination.back")
                        .keyboardShortcut(.cancelAction)
                }
            }
            #endif
            ToolbarItem {
                if !inNavigationStack {
                    Button(text("Close")) { dismiss() }.keyboardShortcut(.cancelAction)
                        .focusable().focused($focus, equals: .close)
                }
            }
        }
    }

    private func loadPage() async {
        loading = true
        failed = false
        defer { if !Task.isCancelled { loading = false } }
        let cursor = nextCursor
        do {
            let response = try await model.service.library(after: cursor, pageSize: 20, session: model.session)
            try Task.checkCancellation()
            var known = Set(items.map(\.publicId))
            items += response.playlists.filter { known.insert($0.publicId).inserted }
            nextCursor = response.nextCursor == cursor ? nil : response.nextCursor
            if let deepLink, !linkResolved {
                linkResolved = true
                MizonDeepLinkRouter.shared.complete(deepLink, stage: .completed)
            }
        } catch {
            if !Task.isCancelled {
                failed = true
                if let deepLink, !linkResolved {
                    linkResolved = true
                    MizonDeepLinkRouter.shared.fail(deepLink, code: "page_unavailable",
                                                   message: "The playlists could not be loaded.")
                }
            }
        }
    }

    private var targets: [Target] {
        var controls: [Target] = (inNavigationStack ? [] : [.close]) + items.map { .playlist($0.publicId) }
        if !loading {
            if failed { controls.append(.retry) }
            else if nextCursor != nil { controls.append(.more) }
        }
        return controls
    }

    private func observeController() async {
        var previous: GCExtendedGamepad?
        var armed = false
        var held = false
        while !Task.isCancelled {
            let current = GCController.controllers().first(where: { $0.extendedGamepad != nil })?.extendedGamepad
            if current !== previous {
                previous = current
                armed = false
                held = false
            }
            if let pad = current {
                let up = max(pad.dpad.yAxis.value, pad.leftThumbstick.yAxis.value)
                let down = min(pad.dpad.yAxis.value, pad.leftThumbstick.yAxis.value)
                let active = pad.buttonB.isPressed || pad.buttonA.isPressed || up > 0.65 || down < -0.65
                if !active { armed = true; held = false }
                if armed, !held, active {
                    held = true
                    if pad.buttonB.isPressed { dismiss(); return }
                    let controls = targets
                    if pad.buttonA.isPressed {
                        switch focus {
                        case .close: dismiss(); return
                        case .playlist(let id) where controls.contains(.playlist(id)): openPlaylist(id); return
                        case .more where controls.contains(.more), .retry where controls.contains(.retry): page += 1
                        default: focus = controls.first
                        }
                    } else {
                        let next = focus.flatMap { controls.firstIndex(of: $0) }
                            .map { min(controls.count - 1, max(0, $0 + (up > 0.65 ? -1 : 1))) } ?? 0
                        focus = controls[next]
                    }
                }
            }
            do { try await Task.sleep(for: .milliseconds(current == nil ? 350 : 45)) }
            catch { return }
        }
    }

    private func text(_ key: String) -> String { localization.string(key, table: "MusicWidgets") }
}
#endif
