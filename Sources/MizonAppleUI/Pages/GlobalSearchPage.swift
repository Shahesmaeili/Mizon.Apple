#if os(macOS) || os(iOS)
import SwiftUI
import MizonAppleCore

struct GlobalSearchPage: View {
    let session: AuthSession
    let service: GlobalSearchService
    let openTrack: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    private var localization = AuthLocalization()
    @State private var query = ""
    @State private var results: [GlobalSearchResult] = []
    @State private var loading = false
    @State private var failed = false

    private var normalizedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isPersian: Bool { localization.isPersian }

    var body: some View {
        NavigationStack {
            List(results) { result in
                Group {
                    if result.kind == .music {
                        Button { openTrack(result.publicID) } label: { label(for: result) }
                            .buttonStyle(.plain)
                    } else {
                        label(for: result)
                    }
                }
                .listRowBackground(AuthAppearance.cardFill)
            }
            .scrollContentBackground(.hidden)
            .overlay {
                if loading && results.isEmpty {
                    ProgressView()
                } else if failed {
                    ContentUnavailableView(
                        text("SearchFailed"),
                        systemImage: "exclamationmark.circle")
                } else if results.isEmpty {
                    ContentUnavailableView(
                        text(normalizedQuery.count < 2 ? "SearchHint" : "SearchEmpty"),
                        systemImage: "magnifyingglass")
                }
            }
            .navigationTitle("Mizon")
            .searchable(text: $query, prompt: Text(text("SearchPrompt")))
            .toolbar {
                Button(localization["AuthDone"]) { dismiss() }
            }
            .task(id: normalizedQuery) {
                await search(normalizedQuery)
            }
        }
        .environment(\.layoutDirection, isPersian ? .rightToLeft : .leftToRight)
    }

    private func text(_ key: String) -> String { localization.string(key, table: "Search") }

    private func label(for result: GlobalSearchResult) -> some View {
        Label {
            Text(isPersian ? result.persianTitle.flatMap { $0.isEmpty ? nil : $0 } ?? result.title : result.title)
        } icon: {
            Image(systemName: result.kind == .music ? "music.note" : "person.crop.circle")
                .foregroundStyle(MizonPalette.accent)
        }
    }

    private func search(_ term: String) async {
        results = []
        failed = false
        loading = term.count >= 2
        guard loading else { return }
        defer {
            if !Task.isCancelled && normalizedQuery == term { loading = false }
        }

        do {
            try await Task.sleep(for: .milliseconds(250))
            var seen: Set<String> = []
            try await service.search(term, session: session) { result in
                guard !Task.isCancelled, normalizedQuery == term, seen.insert(result.id).inserted else { return }
                results.append(result)
            }
        } catch {
            if !Task.isCancelled && normalizedQuery == term { failed = true }
        }
    }
}
#endif
