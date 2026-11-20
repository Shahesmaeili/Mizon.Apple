#if os(macOS) || os(iOS)
import SwiftUI
import MizonAppleCore

struct GlobalSearchPage: View {
    let session: AuthSession
    let displayName: String?
    let avatar: CGImage?
    let profileTransition: Namespace.ID
    let signOut: () -> Void

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
                Label {
                    Text(isPersian ? result.persianTitle.flatMap { $0.isEmpty ? nil : $0 } ?? result.title : result.title)
                } icon: {
                    Image(systemName: result.kind == .music ? "music.note" : "person.crop.circle")
                }
            }
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
                Menu {
                    if let displayName, !displayName.isEmpty { Text(displayName) }
                    Button(localization.string("SignOut", table: "Settings"), action: signOut)
                } label: {
                    WelcomeProfileBadge(avatar: avatar)
                        .frame(width: 28, height: 28)
                        .matchedGeometryEffect(id: "welcome-profile", in: profileTransition)
                }
                .accessibilityLabel(displayName.flatMap { $0.isEmpty ? nil : $0 } ?? text("Profile"))
            }
            .task(id: normalizedQuery) {
                await search(normalizedQuery)
            }
        }
        .environment(\.layoutDirection, isPersian ? .rightToLeft : .leftToRight)
    }

    private func text(_ key: String) -> String { localization.string(key, table: "Search") }

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
            try await GlobalSearchService().search(term, session: session) { result in
                guard !Task.isCancelled, normalizedQuery == term, seen.insert(result.id).inserted else { return }
                results.append(result)
            }
        } catch {
            if !Task.isCancelled && normalizedQuery == term { failed = true }
        }
    }
}
#endif
