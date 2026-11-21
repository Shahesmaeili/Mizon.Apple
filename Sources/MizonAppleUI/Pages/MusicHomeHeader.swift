#if os(macOS) || os(iOS)
import MizonAPIClient
import MizonAppleCore
import SwiftUI

struct MusicHomeHeader<HomeTab: View, Account: View>: View {
    let width: CGFloat
    let search: MusicHomeSearch
    @ViewBuilder let home: () -> HomeTab
    @ViewBuilder let account: () -> Account
    private var localization = AuthLocalization()

    var body: some View {
        Group {
            if width >= 810 {
                HStack(spacing: 8) {
                    tabs
                    search.frame(maxWidth: 640).frame(maxWidth: .infinity)
                    account()
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        search.frame(maxWidth: .infinity)
                        account()
                    }
                    tabs
                }
            }
        }
        .padding(.horizontal, width >= 1040 ? 24 : 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .zIndex(1)
        .environment(\.layoutDirection, .leftToRight)
    }

    private var tabs: some View {
        ViewThatFits(in: .horizontal) {
            tabStrip(showsMovies: true, showsApps: true, showsVPN: true)
            tabStrip(showsMovies: true, showsApps: true, showsVPN: false)
            tabStrip(showsMovies: true, showsApps: false, showsVPN: false)
            tabStrip(showsMovies: false, showsApps: false, showsVPN: false)
        }
    }

    private func tabStrip(showsMovies: Bool, showsApps: Bool, showsVPN: Bool) -> some View {
        HStack(spacing: 5) {
            FluentIcon(symbol: .arrowLeft, size: 14).foregroundStyle(MusicHomeStyle.tertiary.opacity(0.7))
                .frame(width: 32, height: 36)
                .accessibilityHidden(true)
            home()
            if showsMovies { inactive("ShellMovies", icon: .video) }
            if showsApps { inactive("ShellApps", icon: .apps) }
            if showsVPN { inactive("ShellVPN", icon: .shield) }
            if !showsMovies || !showsApps || !showsVPN {
                Menu {
                    if !showsMovies { overflowItem("ShellMovies", icon: .video) }
                    if !showsApps { overflowItem("ShellApps", icon: .apps) }
                    if !showsVPN { overflowItem("ShellVPN", icon: .shield) }
                } label: {
                    FluentIcon(symbol: .moreHorizontal, size: 16).frame(width: 30, height: 36)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .accessibilityLabel(localization.string("ShellMoreTabs", table: "MusicHome"))
            }
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    private func overflowItem(_ key: String, icon: FluentSymbol) -> some View {
        Button {} label: {
            HStack {
                FluentIcon(symbol: icon, size: 16, usesColor: true)
                Text(localization.string(key, table: "MusicHome"))
            }
        }
        .disabled(true)
    }

    private func inactive(_ key: String, icon: FluentSymbol) -> some View {
        let label = localization.string(key, table: "MusicHome")
        return HStack(spacing: 8) {
            FluentIcon(symbol: icon, size: 18, usesColor: true)
            Text(label).font(localization.font(14)).foregroundStyle(MusicHomeStyle.secondary).lineLimit(1)
        }
        .padding(.horizontal, 10).frame(height: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isStaticText)
    }
}

struct MusicHomeSearch: View {
    let model: MusicHomeViewModel
    @Binding var focusRequest: Int
    let onSelect: (GlobalSearchResult) -> Void
    @FocusState private var focused: Bool
    @State private var query = ""
    @State private var results: [GlobalSearchResult] = []
    @State private var selected: String?
    @State private var loading = false
    @State private var failed = false
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var localization = AuthLocalization()

    private var normalized: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var searchCyan: Color { musicColor("A1E8EE") }

    var body: some View {
        HStack(spacing: 4) {
            FluentIcon(symbol: .mic, size: 16)
                .foregroundStyle(MusicHomeStyle.secondary)
                .frame(width: 28, height: 28)
                .background(.white.opacity(0.042), in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)
            #if os(macOS)
            Text("⌘ K").font(.system(size: 10)).foregroundStyle(MusicHomeStyle.tertiary)
                .padding(.leading, 4).accessibilityHidden(true)
            #endif
            TextField(searchText("ShellSearchPlaceholder"), text: $query)
                .textFieldStyle(.plain)
                .font(localization.font(12))
                .focused($focused)
                .submitLabel(.search)
                .multilineTextAlignment(localization.isPersian ? .trailing : .leading)
                .padding(.horizontal, 7)
                .accessibilityLabel(localization.string("SearchPrompt", table: "Search"))
                .accessibilityIdentifier("music.home.search")
                .onChange(of: query) { _, value in
                    if value.count > 120 { query = String(value.prefix(120)) }
                    expanded = focused
                }
                .onSubmit {
                    if let result = results.first(where: { $0.id == selected }) ?? results.first { choose(result) }
                }
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.escape) {
                    expanded = false
                    focused = false
                    return .handled
                }
            FluentIcon(symbol: .search, size: 16).foregroundStyle(searchCyan)
                .frame(width: 28, height: 28)
                .background(searchCyan.opacity(24.0 / 255), in: .rect(cornerRadius: 8))
                .opacity(focused ? 1 : 0.65)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 5).frame(height: 40)
        .background(MusicHomeStyle.secondaryCard, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(focused ? searchCyan.opacity(0.5) : MusicHomeStyle.stroke)
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: focused)
        .overlay(alignment: .topLeading) {
            if expanded && (focused || loading) && normalized.count >= 2 {
                searchSuggestions.offset(y: 48)
            }
        }
        .background {
            Button { focused = true } label: { EmptyView() }
                .keyboardShortcut("k", modifiers: .command)
                .accessibilityHidden(true).frame(width: 0, height: 0)
        }
        .onChange(of: focusRequest) { _, _ in
            focused = true
            expanded = true
        }
        .onChange(of: focused) { _, value in expanded = value }
        .task(id: normalized) { await find(normalized) }
    }

    private var searchSuggestions: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                FluentIcon(symbol: .search, size: 16).foregroundStyle(searchCyan)
                Text(searchText("ShellSearchResults")).font(localization.font(13, weight: .semibold))
                Spacer()
                if loading { ProgressView().controlSize(.small) }
            }
            .padding(8)
            Rectangle().fill(searchCyan.opacity(0.35)).frame(height: 2)
            if results.isEmpty && !loading {
                Text(localization.string(failed ? "SearchFailed" : "SearchEmpty", table: "Search"))
                    .font(localization.font(11)).foregroundStyle(MusicHomeStyle.secondary)
                    .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(results) { result in
                                Button { choose(result) } label: {
                                    HStack(spacing: 9) {
                                        FluentIcon(symbol: result.kind == .music ? .musicNote1 : .person, size: 16)
                                            .foregroundStyle(searchCyan)
                                            .frame(width: 32, height: 32)
                                            .background(searchCyan.opacity(0.10), in: .rect(cornerRadius: 7))
                                        Text(localization.isPersian ? result.persianTitle ?? result.title : result.title)
                                            .font(localization.font(12)).lineLimit(1)
                                        Spacer()
                                        FluentIcon(symbol: .arrowUpRight, size: 11).foregroundStyle(MusicHomeStyle.secondary)
                                    }
                                    .padding(.horizontal, 6).padding(.vertical, 4)
                                }
                                .buttonStyle(MusicHomeButtonStyle(fill: selected == result.id ? searchCyan.opacity(0.13) : .clear))
                                .id(result.id)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: 256)
                    .onChange(of: selected) { _, selection in
                        if let selection { reader.scrollTo(selection, anchor: .center) }
                    }
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .background(musicColor("1F2230").opacity(0.92), in: .rect(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12)).allowsHitTesting(false) }
        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
    }

    private func searchText(_ key: String) -> String { localization.string(key, table: "MusicHome") }

    private func choose(_ item: GlobalSearchResult) {
        focused = false
        expanded = false
        selected = nil
        query = ""
        onSelect(item)
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard expanded, !results.isEmpty else { return .ignored }
        let position = selected.flatMap { id in results.firstIndex { $0.id == id } }
        let index = position.map { max(0, min(results.count - 1, $0 + step)) } ?? (step > 0 ? 0 : results.count - 1)
        selected = results[index].id
        return .handled
    }

    private func find(_ term: String) async {
        results = []
        selected = nil
        failed = false
        loading = term.count >= 2
        guard loading else { return }
        defer { if !Task.isCancelled && normalized == term { loading = false } }
        do {
            try await Task.sleep(for: .milliseconds(250))
            var seen: Set<String> = []
            try await model.service.searchService.search(term, session: model.session) { item in
                guard !Task.isCancelled, normalized == term, results.count < 24, seen.insert(item.id).inserted else { return }
                results.append(item)
            }
        } catch {
            if !Task.isCancelled && normalized == term { failed = true }
        }
    }
}
struct MusicHomeMoodButton: View {
    let model: MusicHomeViewModel
    @State private var mood: ClientMoodItemResponse?
    @State private var loaded = false
    @State private var failed = false
    @State private var options: [ClientMoodItemResponse] = []
    @State private var showing = false
    @State private var saving = false
    private var localization = AuthLocalization()

    init(model: MusicHomeViewModel, initialMood: ClientMoodItemResponse?) {
        self.model = model
        _mood = State(initialValue: initialMood)
    }

    var body: some View {
        Button {
            showing = true
        } label: {
            Group {
                if let emoji = mood?.emoji, !emoji.isEmpty { Text(emoji).font(.system(size: 20)) }
                else { Image(systemName: "face.smiling").font(.system(size: 18)).foregroundStyle(MusicHomeStyle.secondary) }
            }
            .frame(width: 36, height: 32)
        }
        .padding(.horizontal, 3)
        .buttonStyle(MusicHomeButtonStyle(corner: 10))
        .accessibilityLabel(label("ShellSelectMood"))
        .accessibilityValue(mood.map(title) ?? "")
        .popover(isPresented: $showing, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label("ShellSelectMood")).font(localization.font(14, weight: .semibold))
                if failed {
                    Text(label("FeatureServiceFailed")).font(localization.font(11)).foregroundStyle(MusicHomeStyle.secondary)
                }
                if loaded {
                    ForEach(options, id: \.publicId) { option in
                        Button {
                            set(option.publicId)
                        } label: {
                            HStack {
                                Text(option.emoji)
                                Text(title(option))
                                Spacer()
                                if mood?.publicId == option.publicId { FluentIcon(symbol: .checkmark, size: 12) }
                            }
                            .padding(.horizontal, 8).frame(height: 30)
                        }
                        .buttonStyle(MusicHomeButtonStyle(fill: MusicHomeStyle.inset))
                        .disabled(saving)
                    }
                    if mood != nil {
                        Button(label("ShellClearMood")) { set(nil) }
                            .disabled(saving)
                    }
                } else if failed {
                    Button(label("Retry")) { Task { await load() } }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 240)
            .padding(12)
            .task { if !loaded { await load() } }
        }
    }

    private func load() async {
        failed = false
        do {
            options = try await model.service.moodOptions(session: model.session)
            loaded = true
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }

    private func set(_ id: UUID?) {
        guard !saving else { return }
        saving = true
        failed = false
        Task {
            defer { saving = false }
            do {
                mood = try await model.service.setMood(id, session: model.session)
                showing = false
            } catch {
                failed = true
            }
        }
    }

    private func label(_ key: String) -> String { localization.string(key, table: "MusicHome") }
    private func title(_ mood: ClientMoodItemResponse) -> String {
        localization.isPersian ? mood.persianTitle ?? mood.title : mood.title
    }
}

#endif
