#if os(macOS) || os(iOS)
import MizonAPIClient
import MizonAppleCore
import SwiftUI

struct MusicLibraryBrowser: View {
    let model: MusicHomeViewModel
    let openPlaylist: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var items: [MusicLibraryPlaylistItemResponse] = []
    @State private var failed = false
    @State private var nextCursor: String?
    @State private var page = 0
    @State private var loading = true
    private var localization = AuthLocalization()

    var body: some View {
        NavigationStack {
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
                }
                if loading {
                    ProgressView().frame(maxWidth: .infinity)
                } else if failed {
                    Text(text("LibraryError")).foregroundStyle(.secondary)
                    Button(text("Retry")) { page += 1 }
                } else if nextCursor != nil {
                    Button(text("MorePlaylists")) { page += 1 }
                } else if items.isEmpty {
                    Text(text("LibraryEmpty")).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(text("LibraryTitle"))
            .toolbar { Button(text("Close")) { dismiss() }.keyboardShortcut(.cancelAction) }
        }
        .task(id: page) { await loadPage() }
        .frame(minWidth: 310, minHeight: 300)
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
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }

    private func text(_ key: String) -> String { localization.string(key, table: "MusicWidgets") }
}
#endif
