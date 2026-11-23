#if os(macOS) || os(iOS)
import MizonAPIClient
import MizonAppleCore
import SwiftUI

enum MusicHomeChrome {
    static let controlFill = MizonPalette.ink.opacity(0.07)
    static let hairline = MizonPalette.ink.opacity(0.14)
    static let hint = MizonPalette.ink.opacity(0.62)
}

enum MusicHomeNavigationSection: String, CaseIterable, Identifiable {
    case music, movies, apps, vpn

    var id: Self { self }

    var key: String {
        switch self {
        case .music: "ShellMusic"
        case .movies: "ShellMovies"
        case .apps: "ShellApps"
        case .vpn: "ShellVPN"
        }
    }

    var icon: FluentSymbol {
        switch self {
        case .music: .headphones
        case .movies: .video
        case .apps: .apps
        case .vpn: .shield
        }
    }

    var estimatedWidth: CGFloat {
        switch self {
        case .music: 101
        case .movies: 148
        case .apps: 86
        case .vpn: 85
        }
    }
}

struct MusicHomeNavigationLabel: View {
    let section: MusicHomeNavigationSection
    let compact: Bool
    @ScaledMetric(relativeTo: .body) private var titleHeight: CGFloat = 26

    var body: some View {
        MusicHomeNavigationTitle(section: section, showsText: !compact)
            .padding(.horizontal, compact ? 0 : 16)
            .frame(width: compact ? MusicHomeNavigationLayout.compactMusicWidth : nil,
                   height: compact ? 40 : max(40, titleHeight + 10))
            .contentShape(Rectangle())
    }
}

private struct MusicHomeNavigationTitle: View {
    let section: MusicHomeNavigationSection
    var showsText = true
    var allowsWrapping = false
    private var localization = AuthLocalization()

    var body: some View {
        HStack(spacing: 8) {
            FluentIcon(symbol: section.icon, size: 18, usesColor: true)
                .dynamicTypeSize(.large)
            if showsText {
                Text(localization.string(section.key, table: "MusicHome"))
                    .font(localization.font(14))
                    .foregroundStyle(MizonPalette.ink)
                    .lineLimit(allowsWrapping ? nil : 1)
            }
        }
    }
}

struct MusicHomeOverflowNavigationLabel: View {
    let compact: Bool

    var body: some View {
        FluentIcon(symbol: .moreHorizontal, size: 16)
            .dynamicTypeSize(.large)
            .foregroundStyle(MizonPalette.ink)
            .frame(width: MusicHomeNavigationLayout.overflowWidth(compact: compact), height: 40)
            .contentShape(Rectangle())
    }
}

struct MusicHomeNavigationTabStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        MusicHomeNavigationTabAppearance(
            label: configuration.label,
            selected: selected,
            isPressed: configuration.isPressed
        )
    }
}

private struct MusicHomeNavigationTabAppearance<Label: View>: View {
    let label: Label
    let selected: Bool
    let isPressed: Bool
    @State private var hovered = false

    var body: some View {
        label
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(MizonPalette.ink.opacity(isPressed ? 0.04 : hovered ? 0.07 : 0))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            }
            .overlay(alignment: .bottom) {
                if selected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(MizonPalette.accent)
                        .frame(width: 16, height: 3)
                        .padding(.bottom, 4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onHover { hovered = $0 }
    }
}

struct MusicHomeHeader<Search: View, HomeTab: View, Overflow: View, Account: View>: View {
    let width: CGFloat
    @Binding var showingOverflow: Bool
    let onOverflowAvailabilityChange: (Bool) -> Void
    @ViewBuilder let search: (Bool) -> Search
    @ViewBuilder let home: (Bool) -> HomeTab
    @ViewBuilder let overflow: (MusicHomeOverflowNavigationLabel) -> Overflow
    @ViewBuilder let account: () -> Account
    @State private var measuredTabs: [MusicHomeNavigationSection: CGFloat] = [:]
    @State private var accountWidth: CGFloat = 108
    @State private var hadOverflow = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var localization = AuthLocalization()

    var body: some View {
        let minimumSearch: CGFloat = 32
        let fullSearch: CGFloat = 144
        let regularInset: CGFloat = width >= 960 ? 18 : 8
        let regularGap: CGFloat = 8
        let minimumTabs = MusicHomeNavigationLayout.compactMusicWidth
            + MusicHomeNavigationLayout.overflowWidth(compact: false)
        let tight = width - accountWidth < (regularInset + regularGap) * 2 + minimumSearch + minimumTabs
        let horizontalInset = tight ? 2 : regularInset
        let gap = tight ? 3 : regularGap
        let tabBudget = max(0, width - horizontalInset * 2 - gap * 2 - accountWidth - minimumSearch)
        let layout = MusicHomeNavigationLayout(
            budget: tabBudget,
            widths: measuredTabs,
            compactOverflow: tight,
            restoringAll: hadOverflow
        )
        let hasOverflow = !layout.hidden.isEmpty
        let compactSearch = tabBudget + minimumSearch - layout.width < fullSearch

        HStack(spacing: gap) {
            tabStrip(layout, compactOverflow: tight)
            search(compactSearch)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity, alignment: .trailing)
            account()
                .fixedSize(horizontal: true, vertical: false)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { accountWidth = $0 }
        }
        .padding(.horizontal, horizontalInset)
        .frame(width: width)
        .background(alignment: .leading) { tabMeasurements }
        .environment(\.layoutDirection, .leftToRight)
        .onChange(of: hasOverflow, initial: true) { _, available in
            hadOverflow = available
            if !available { showingOverflow = false }
            onOverflowAvailabilityChange(available)
        }
    }

    private var tabMeasurements: some View {
        HStack(spacing: 0) {
            ForEach(MusicHomeNavigationSection.allCases) { section in
                MusicHomeNavigationLabel(section: section, compact: false)
                    .fixedSize(horizontal: true, vertical: true)
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { measuredTabs[section] = $0 }
            }
        }
        .fixedSize()
        .hidden()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func tabStrip(_ layout: MusicHomeNavigationLayout, compactOverflow: Bool) -> some View {
        HStack(spacing: 0) {
            home(layout.compactMusic)
            ForEach(layout.visible) { section in
                unavailable(section) { MusicHomeNavigationLabel(section: section, compact: false) }
            }
            if !layout.hidden.isEmpty {
                overflow(MusicHomeOverflowNavigationLabel(compact: compactOverflow))
                    .popover(isPresented: $showingOverflow, arrowEdge: .top) {
                        overflowMenu(layout.hidden)
                            .presentationCompactAdaptation(.popover)
                    }
            }
        }
        .fixedSize(horizontal: true, vertical: true)
    }

    private func overflowMenu(_ sections: [MusicHomeNavigationSection]) -> some View {
        VStack(spacing: 0) {
            ForEach(sections) { section in
                unavailable(section) {
                    overflowRow(section)
                }
                .accessibilityIdentifier("music.home.overflow.\(section.rawValue)")
            }
        }
        .padding(.vertical, 2)
        .frame(width: min(272, max(244, width - 20)))
        .background {
            MizonPalette.surface.opacity(reduceTransparency ? 1 : 0.70).ignoresSafeArea()
        }
        .environment(\.layoutDirection, .leftToRight)
        .environment(\.locale, locale)
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .accessibilityIdentifier("music.home.overflow")
    }

    private func overflowRow(_ section: MusicHomeNavigationSection) -> some View {
        let status = Text(localization.string("ShellSectionUnavailable", table: "MusicHome"))
            .font(localization.font(11))
            .foregroundStyle(MusicHomeChrome.hint)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                MusicHomeNavigationTitle(section: section)
                Spacer(minLength: 12)
                status.lineLimit(1)
            }
            .fixedSize(horizontal: true, vertical: false)
            VStack(alignment: .leading, spacing: 2) {
                MusicHomeNavigationTitle(section: section, allowsWrapping: true)
                status.padding(.leading, 26)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 16)
        .padding(.trailing, 20)
        .padding(.vertical, 4)
        .frame(minHeight: 36)
    }

    private func unavailable<Label: View>(
        _ section: MusicHomeNavigationSection,
        @ViewBuilder label: () -> Label
    ) -> some View {
        label()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(localization.string(section.key, table: "MusicHome"))
            .accessibilityValue(localization.string("ShellSectionUnavailable", table: "MusicHome"))
            .accessibilityAddTraits(.isStaticText)
    }
}

struct MusicHomeNavigationLayout {
    static let compactMusicWidth: CGFloat = 36
    let visible: [MusicHomeNavigationSection]
    let hidden: [MusicHomeNavigationSection]
    let compactMusic: Bool
    let width: CGFloat

    static func overflowWidth(compact: Bool) -> CGFloat {
        compact ? 32 : 40
    }

    init(
        budget: CGFloat,
        widths: [MusicHomeNavigationSection: CGFloat],
        compactOverflow: Bool,
        restoringAll: Bool = false
    ) {
        let sections = Array(MusicHomeNavigationSection.allCases.dropFirst())
        let musicWidth = widths[.music] ?? MusicHomeNavigationSection.music.estimatedWidth
        let total = sections.reduce(musicWidth) { $0 + (widths[$1] ?? $1.estimatedWidth) }
        if total + (restoringAll ? 5 : 0) <= budget {
            visible = sections
            hidden = []
            compactMusic = false
            width = total
            return
        }

        let overflowWidth = Self.overflowWidth(compact: compactOverflow)
        compactMusic = musicWidth + overflowWidth > budget
        var used = (compactMusic ? Self.compactMusicWidth : musicWidth) + overflowWidth
        let fitting = sections.prefix {
            let next = widths[$0] ?? $0.estimatedWidth
            guard used + next <= budget else { return false }
            used += next
            return true
        }
        visible = Array(fitting)
        hidden = Array(sections.dropFirst(fitting.count))
        width = used
    }
}

struct MusicHomeSearch: View {
    let model: MusicHomeViewModel
    let viewportWidth: CGFloat
    let compact: Bool
    @Binding var focusRequest: Int
    @Binding var showingSearch: Bool
    let onSelect: (GlobalSearchResult) -> Void
    @FocusState private var focused: Bool
    @State private var query = ""
    @State private var results: [GlobalSearchResult] = []
    @State private var selected: String?
    @State private var loading = false
    @State private var failed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private var localization = AuthLocalization()

    private var normalized: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        Button { showingSearch = true } label: {
            HStack(spacing: 6) {
                if !compact {
                    Text(searchText("ShellSearchPlaceholder"))
                        .font(localization.font(12)).foregroundStyle(MizonPalette.secondaryText).lineLimit(1)
                    Spacer(minLength: 0)
                    #if os(macOS)
                    Text("⌘ K").font(.system(size: 10)).foregroundStyle(MusicHomeChrome.hint)
                    #endif
                }
                FluentIcon(symbol: .search, size: 16)
                    .dynamicTypeSize(.large)
                    .foregroundStyle(MizonPalette.accent)
            }
            .padding(.horizontal, compact ? 8 : 10)
            .frame(height: 32)
            .background(MusicHomeChrome.controlFill, in: .rect(cornerRadius: 9))
            .overlay { RoundedRectangle(cornerRadius: 9).strokeBorder(MusicHomeChrome.hairline).allowsHitTesting(false) }
        }
        .buttonStyle(.plain)
        .authHandPointer(enabled: true)
        .accessibilityLabel(localization.string("SearchPrompt", table: "Search"))
        .accessibilityIdentifier("music.home.search.button")
        .keyboardShortcut("k", modifiers: .command)
        .popover(isPresented: $showingSearch, arrowEdge: .top) {
            VStack(spacing: 8) {
                searchField
                if normalized.count >= 2 { searchSuggestions }
            }
            .padding(10)
            .frame(width: min(420, max(240, viewportWidth - 42)))
            .foregroundStyle(MizonPalette.ink)
            .tint(MizonPalette.accent)
            .background { MizonPalette.surface.opacity(reduceTransparency ? 1 : 0.70).ignoresSafeArea() }
            .presentationCompactAdaptation(.popover)
            .task {
                focused = true
                await Task.yield()
                if !Task.isCancelled { focused = true }
            }
        }
        .onChange(of: focusRequest) { _, _ in showingSearch = true }
        .task(id: normalized) { await find(normalized) }
    }

    private var searchField: some View {
        let placeholder = searchText("ShellSearchPlaceholder")
        return HStack(spacing: 4) {
            FluentIcon(symbol: .mic, size: 16)
                .foregroundStyle(MizonPalette.secondaryText)
                .frame(width: 28, height: 28)
                .background(MusicHomeChrome.controlFill, in: .rect(cornerRadius: 8))
                .accessibilityHidden(true)
            TextField(placeholder, text: $query, prompt: Text(placeholder).foregroundStyle(MizonPalette.secondaryText))
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
                }
                .onSubmit {
                    if let result = results.first(where: { $0.id == selected }) ?? results.first { choose(result) }
                }
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.escape) {
                    showingSearch = false
                    return .handled
                }
            FluentIcon(symbol: .search, size: 16).foregroundStyle(MizonPalette.accent)
                .frame(width: 28, height: 28)
                .background(MizonPalette.accent.opacity(24.0 / 255), in: .rect(cornerRadius: 8))
                .opacity(focused ? 1 : 0.65)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 5).frame(height: 40)
        .background(MusicHomeChrome.controlFill, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(focused ? MizonPalette.accent.opacity(0.5) : MusicHomeChrome.hairline)
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: focused)
    }

    private var searchSuggestions: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                FluentIcon(symbol: .search, size: 16).foregroundStyle(MizonPalette.accent)
                Text(searchText("ShellSearchResults")).font(localization.font(13, weight: .semibold))
                Spacer()
                if loading { ProgressView().controlSize(.small) }
            }
            .padding(8)
            Rectangle().fill(MizonPalette.accent.opacity(0.35)).frame(height: 2)
            if results.isEmpty && !loading {
                Text(localization.string(failed ? "SearchFailed" : "SearchEmpty", table: "Search"))
                    .font(localization.font(11)).foregroundStyle(MizonPalette.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(results) { result in
                                Button { choose(result) } label: {
                                    HStack(spacing: 9) {
                                        FluentIcon(symbol: result.kind == .music ? .musicNote1 : .person, size: 16)
                                            .foregroundStyle(MizonPalette.accent)
                                            .frame(width: 32, height: 32)
                                            .background(MizonPalette.accent.opacity(0.10), in: .rect(cornerRadius: 7))
                                        Text(localization.isPersian ? result.persianTitle ?? result.title : result.title)
                                            .font(localization.font(12)).lineLimit(1)
                                        Spacer()
                                        FluentIcon(symbol: .arrowUpRight, size: 11).foregroundStyle(MizonPalette.secondaryText)
                                    }
                                    .padding(.horizontal, 6).padding(.vertical, 4)
                                }
                                .buttonStyle(MusicHomeButtonStyle(fill: selected == result.id ? MizonPalette.accent.opacity(0.13) : .clear))
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
        .background(MizonPalette.surface.opacity(reduceTransparency ? 1 : 0.58), in: .rect(cornerRadius: 20))
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(MusicHomeChrome.hairline).allowsHitTesting(false) }
        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
    }

    private func searchText(_ key: String) -> String { localization.string(key, table: "MusicHome") }

    private func choose(_ item: GlobalSearchResult) {
        focused = false
        showingSearch = false
        selected = nil
        query = ""
        onSelect(item)
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard showingSearch, !results.isEmpty else { return .ignored }
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
#endif
