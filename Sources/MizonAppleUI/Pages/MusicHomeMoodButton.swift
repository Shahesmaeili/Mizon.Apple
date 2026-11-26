#if os(macOS) || os(iOS)
import MizonAPIClient
import MizonAppleCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct MusicHomeMoodButton: View {
    private enum PickerMode: Equatable { case hover, direct, controller }
    private enum HoverWork: Equatable { case none, open, close }

    let model: MusicHomeViewModel
    let viewport: CGSize
    let controllerPress: UInt
    let onPickerVisibilityChange: (Bool) -> Void
    private let initialMood: ClientMoodItemResponse?

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    #if os(macOS)
    @Environment(\.appearsActive) private var appearsActive
    @Environment(MusicHomeFocus.self) private var navigationFocus
    #endif
    @State private var mood: ClientMoodItemResponse?
    @State private var catalog: [ClientMoodItemResponse]?
    @State private var catalogLoadedAt: Date?
    @State private var indexedCatalog: [MoodSearchEntry] = []
    @State private var catalogLoadID: UUID?
    @State private var catalogFailed = false
    @State private var catalogRetry = 0
    @State private var pickerMode: PickerMode?
    @State private var query = ""
    @State private var filteredQuery = ""
    @State private var pendingSave: UUID?
    @State private var saveFailed = false
    @State private var hovered = false
    @State private var pickerHovered = false
    @State private var suppressHover = false
    @State private var loop: LoopAsset?
    @State private var readyLoop: UUID?
    @State private var effectChoice: EffectChoice?
    @State private var effectAsset: URL?
    @State private var effectLoadFailed = false
    @State private var effectRetry = 0
    @State private var effectRequest: UUID?
    @State private var shownEffect: MoodEffectPresentation?
    @State private var waitForPickerDismissal = false
    @FocusState private var searchFocused: Bool
    @FocusState private var selectedTile: UUID?
    private var localization = AuthLocalization()

    init(model: MusicHomeViewModel, initialMood: ClientMoodItemResponse?,
         viewport: CGSize = CGSize(width: 376, height: 490), controllerPress: UInt = 0,
         onPickerVisibilityChange: @escaping (Bool) -> Void = { _ in }) {
        self.model = model
        self.viewport = viewport
        self.controllerPress = controllerPress
        self.onPickerVisibilityChange = onPickerVisibilityChange
        self.initialMood = initialMood
        _mood = State(initialValue: initialMood)
    }

    private var canPlay: Bool {
        #if os(macOS)
        scenePhase == .active && appearsActive && !reduceMotion
        #else
        scenePhase == .active && !reduceMotion
        #endif
    }

    private var pickerWidth: CGFloat { max(1, min(344, viewport.width - 32)) }
    private var pickerHeight: CGFloat { max(180, min(390, viewport.height - 100)) }
    private var selectedMoodFill: Color {
        #if os(macOS)
        MizonPalette.ink.opacity(0.14)
        #else
        Color.accentColor.opacity(0.18)
        #endif
    }

    private var pickerBinding: Binding<Bool> {
        Binding(get: { pickerMode != nil }, set: { if !$0 { pickerMode = nil } })
    }

    private var hoverWork: HoverWork {
        if hovered && !suppressHover && pickerMode == nil { return .open }
        if !hovered && !pickerHovered && pickerMode == .hover && pendingSave == nil { return .close }
        return .none
    }

    private var catalogRequest: CatalogRequest {
        CatalogRequest(needed: pickerMode != nil || (mood == nil && catalog == nil), retry: catalogRetry)
    }

    private var effectLoadKey: EffectLoadKey {
        EffectLoadKey(choice: effectChoice, active: canPlay, retry: effectRetry)
    }

    private var matches: [ClientMoodItemResponse] {
        guard !filteredQuery.isEmpty else { return catalog ?? [] }
        return indexedCatalog.filter { $0.contains(filteredQuery) }.map(\.mood)
    }

    var body: some View {
        anchor
        .task(id: catalogRequest) {
            guard catalogRequest.needed else { return }
            await loadCatalog()
        }
        .task(id: mood?.animationMediaPublicId) {
            await loadLoop()
        }
        .task(id: effectLoadKey) {
            await prepareEffect(effectLoadKey)
        }
        .task(id: hoverWork) {
            await runHoverWork(hoverWork)
        }
        .task(id: pendingSave) {
            if let id = pendingSave { await save(id) }
        }
        .onChange(of: mood?.publicId, initial: true) { resetEffectChoice() }
        .onChange(of: effectAsset) { startPreparedEffect() }
        .task(id: shownEffect?.id) {
            guard let id = shownEffect?.id else { return }
            do {
                try await Task.sleep(for: .seconds(25))
                completeEffect(id)
            } catch { }
        }
        .onChange(of: canPlay) {
            if !canPlay {
                effectRequest = nil
                waitForPickerDismissal = false
                shownEffect = nil
            }
        }
        .onChange(of: pickerMode != nil) { _, visible in
            if !visible && hovered { suppressHover = true }
            onPickerVisibilityChange(visible)
        }
        .onChange(of: initialMood?.publicId) { mood = initialMood }
        .onChange(of: controllerPress) { openPicker(.controller) }
        .onDisappear {
            onPickerVisibilityChange(false)
            effectRequest = nil
            shownEffect = nil
        }
    }

    private var anchor: some View {
        Button(action: playEffect) { badge }
            .buttonStyle(MoodButtonStyle())
            .padding(.horizontal, 3)
            .accessibilityIdentifier("music.home.mood")
            .accessibilityLabel(text("ShellSelectMood"))
            .accessibilityValue(mood.map(title) ?? "")
            .accessibilityHint(text("ShellMoodEffectHint"))
            .accessibilityAction(named: Text(text("ShellSelectMood"))) { openPicker(.direct) }
            .onKeyPress(keys: [.downArrow, KeyEquivalent("\u{F707}")], phases: .down) { _ in
                openPicker(.direct)
                return .handled
            }
            #if os(macOS)
            .gesture(MoodSecondaryClick { openPicker(.direct) })
            .onHover { over in
                hovered = over
                if !over { suppressHover = false }
            }
            #else
            .highPriorityGesture(LongPressGesture(minimumDuration: 0.28).onEnded { _ in openPicker(.direct) })
            #endif
            .background {
                if let shownEffect {
                    MoodEffectAnchor(effect: shownEffect, onCompletion: completeEffect)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .popover(isPresented: pickerBinding, arrowEdge: .top) {
                picker
                    #if os(macOS)
                    .background {
                        MusicHomeFocusInput(input: navigationFocus).frame(width: 0, height: 0)
                    }
                    #endif
                    .presentationCompactAdaptation(.popover)
                    .onAppear {
                        if pickerMode == .direct { searchFocused = true }
                        if pickerMode == .controller { focusCurrentMood() }
                    }
                    .onDisappear {
                        pickerHovered = false
                        searchFocused = false
                        selectedTile = nil
                        if waitForPickerDismissal {
                            waitForPickerDismissal = false
                            startPreparedEffect()
                        }
                    }
            }
    }

    private var badge: some View {
        ZStack {
            if let mood, readyLoop != mood.animationMediaPublicId {
                Text(mood.emoji).font(.system(size: 20))
            } else if mood == nil {
                Text("🤢").font(.system(size: 20))
            }
            if let loop, loop.media == mood?.animationMediaPublicId {
                MoodLottieView(file: loop.file, playback: .loop, playing: canPlay, onReady: {
                    if mood?.animationMediaPublicId == loop.media { readyLoop = loop.media }
                })
                .id(loop.media)
            }
        }
        .frame(width: MoodLottiePlayback.badgeSize.width, height: MoodLottiePlayback.badgeSize.height)
        .clipped()
        .frame(width: 36, height: 32)
        .accessibilityHidden(true)
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                FluentIcon(symbol: .emoji, size: 21)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 36, height: 36)
                    .background(MusicHomeStyle.secondaryCard, in: .rect(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(text("ShellMoodTitle")).font(localization.font(16, weight: .semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(text("ShellMoodSubtitle")).font(localization.font(10))
                        .foregroundStyle(MusicHomeStyle.secondary)
                }
                Spacer(minLength: 0)
            }

            TextField(text("ShellMoodSearchHint"), text: $query)
                .textFieldStyle(.plain)
                .font(localization.font(12))
                .multilineTextAlignment(.trailing)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(MusicHomeStyle.inset, in: .rect(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(MusicHomeStyle.stroke) }
                .environment(\.layoutDirection, .leftToRight)
                .focused($searchFocused)
                .disabled(pendingSave != nil)
                .accessibilityIdentifier("music.home.mood.search")
                .accessibilityLabel(text("ShellMoodSearch"))
                .accessibilityHint(text("ShellMoodSearchHelp"))
                .onKeyPress(.downArrow) {
                    guard !matches.isEmpty else { return .ignored }
                    moveFocus(by: 0)
                    return .handled
                }
                .onChange(of: searchFocused) {
                    if searchFocused { openPicker(.direct) }
                }

            pickerGrid
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    if pendingSave != nil {
                        ProgressView().progressViewStyle(.linear).frame(height: 2)
                            .accessibilityLabel(text("ShellMoodSaving"))
                    }
                }

            VStack(alignment: .leading, spacing: 6) {
                if saveFailed {
                    Text(text("ShellMoodSaveFailed"))
                        .font(localization.font(11)).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Rectangle().fill(MusicHomeStyle.stroke).frame(height: 1)
                Text(text("ShellMoodFooter")).font(localization.font(10))
                    .foregroundStyle(MusicHomeStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(width: pickerWidth, height: pickerHeight)
        .background {
            if reduceTransparency {
                Color(white: 0.15)
            } else {
                Rectangle().fill(.regularMaterial)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .onHover { over in pickerHovered = over }
        .onKeyPress(.escape) {
            pickerMode = nil
            return .handled
        }
        .task(id: query) {
            let input = query
            do {
                try await Task.sleep(for: .milliseconds(120))
                filteredQuery = MoodSearchEntry.normalize(input)
            } catch { }
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await observeController() }
        }
    }

    @ViewBuilder
    private var pickerGrid: some View {
        if catalog == nil {
            VStack(spacing: catalogLoadID != nil || !catalogFailed ? 12 : 10) {
                if catalogFailed {
                    FluentIcon(symbol: .search, size: 26).foregroundStyle(MusicHomeStyle.secondary)
                    Text(text("ShellMoodLoadFailed"))
                        .font(localization.font(12)).multilineTextAlignment(.center)
                    Button(text("Retry")) { catalogRetry += 1 }
                        .font(localization.font(12))
                        .buttonStyle(.bordered)
                } else {
                    ProgressView().controlSize(.regular)
                        .frame(width: 28, height: 28)
                        .accessibilityLabel(text("ShellMoodLoading"))
                    Text(text("ShellMoodLoading")).font(localization.font(11))
                        .foregroundStyle(MusicHomeStyle.secondary)
                }
            }
        } else if matches.isEmpty {
            VStack(spacing: 10) {
                FluentIcon(symbol: .search, size: 26).foregroundStyle(MusicHomeStyle.secondary)
                Text(text("ShellMoodEmpty")).font(localization.font(12))
            }
        } else {
            ScrollViewReader { reader in
                ScrollView {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 0) {
                        ForEach(matches, id: \.publicId) { item in
                            Button { choose(item) } label: {
                                MoodTilePreview(item: item, model: model, selected: item.publicId == mood?.publicId)
                                    .frame(width: 44, height: 44)
                                    .background(item.publicId == mood?.publicId ? selectedMoodFill : .clear,
                                                in: .rect(cornerRadius: 12))
                                    .overlay {
                                        #if os(macOS)
                                        MusicHomeFocusOutline(
                                            isFocused: selectedTile == item.publicId, cornerRadius: 12, input: navigationFocus
                                        )
                                        #else
                                        if selectedTile == item.publicId {
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(Color.accentColor, lineWidth: 2)
                                        }
                                        #endif
                                    }
                            }
                            .buttonStyle(MusicHomeButtonStyle(corner: 12))
                            .padding(2)
                            .focused($selectedTile, equals: item.publicId)
                            #if os(macOS)
                            .focusEffectDisabled()
                            #endif
                            .accessibilityIdentifier("music.home.mood.option")
                            .accessibilityLabel(title(item))
                            .accessibilityAddTraits(item.publicId == mood?.publicId ? .isSelected : [])
                            .help(title(item))
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
                .disabled(pendingSave != nil)
                .onAppear {
                    if pickerMode == .controller, selectedTile == nil { focusCurrentMood() }
                    if let selectedTile { reader.scrollTo(selectedTile, anchor: .center) }
                }
                .onChange(of: selectedTile) {
                    if let selectedTile { reader.scrollTo(selectedTile, anchor: .center) }
                }
                .onChange(of: filteredQuery) {
                    if let first = matches.first { reader.scrollTo(first.publicId, anchor: .top) }
                }
            }
        }
    }

    private var columnCount: Int { max(1, Int(max(1, pickerWidth - 28) / 48)) }
    private var columns: [GridItem] { Array(repeating: GridItem(.fixed(48), spacing: 0), count: columnCount) }

    private func loadCatalog() async {
        if let catalogLoadedAt, Date().timeIntervalSince(catalogLoadedAt) < 600 { return }
        let id = UUID()
        catalogLoadID = id
        catalogFailed = false
        defer { if catalogLoadID == id { catalogLoadID = nil } }
        do {
            let received = try await model.service.moodOptions(session: model.session)
            try Task.checkCancellation()
            guard catalogLoadID == id else { return }
            catalog = received
            indexedCatalog = received.map(MoodSearchEntry.init)
            catalogLoadedAt = Date()
            // The Windows shell picks its default locally without writing account state.
            if mood == nil { mood = received.first { $0.emoji == "🤢" } ?? received.first }
        } catch {
            if !Task.isCancelled && catalogLoadID == id && catalog == nil { catalogFailed = true }
        }
    }

    private func loadLoop() async {
        guard let id = mood?.animationMediaPublicId, id != UUID.zeroMoodID else {
            loop = nil
            readyLoop = nil
            return
        }
        if loop?.media == id { return }
        loop = nil
        readyLoop = nil
        guard let file = try? await model.moodAnimationURL(id),
              !Task.isCancelled, mood?.animationMediaPublicId == id else { return }
        loop = LoopAsset(media: id, file: file)
    }

    private func resetEffectChoice() {
        effectChoice = mood.flatMap { mood in
            let media = mood.effectMediaPublicIds.filter { $0 != .zeroMoodID }.randomElement() ?? mood.animationMediaPublicId
            return media == .zeroMoodID ? nil : EffectChoice(mood: mood.publicId, media: media)
        }
        effectAsset = nil
        effectRequest = nil
        shownEffect = nil
        effectLoadFailed = false
        waitForPickerDismissal = false
    }

    private func prepareEffect(_ key: EffectLoadKey) async {
        guard key.active, let choice = key.choice, choice.media != UUID.zeroMoodID, effectAsset == nil else { return }
        effectLoadFailed = false
        do {
            let file = try await model.moodAnimationURL(choice.media)
            _ = try await MoodLottieView.decode(file)
            try Task.checkCancellation()
            guard effectChoice == choice else { return }
            effectAsset = file
        } catch {
            if !Task.isCancelled && effectChoice == choice {
                effectLoadFailed = true
                effectRequest = nil
            }
        }
    }

    private func runHoverWork(_ work: HoverWork) async {
        do {
            switch work {
            case .none: return
            case .open:
                try await Task.sleep(for: .milliseconds(280))
                if hoverWork == .open { openPicker(.hover) }
            case .close:
                try await Task.sleep(for: .milliseconds(450))
                if hoverWork == .close { pickerMode = nil }
            }
        } catch { }
    }

    private func openPicker(_ mode: PickerMode) {
        guard pickerMode == nil || pickerMode == .hover else { return }
        pickerMode = mode
    }

    private func playEffect() {
        suppressHover = true
        let hadPicker = pickerMode != nil
        if hadPicker {
            // Delay the overlay until the picker has released its presentation.
            waitForPickerDismissal = canPlay
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { pickerMode = nil }
        }
        guard canPlay, effectChoice != nil else { return }
        effectRequest = UUID()
        if effectLoadFailed { effectRetry += 1 }
        if !hadPicker { startPreparedEffect() }
    }

    private func startPreparedEffect() {
        guard canPlay, !waitForPickerDismissal, let effectRequest, let effectAsset else { return }
        shownEffect = MoodEffectPresentation(id: effectRequest, file: effectAsset)
        self.effectRequest = nil
    }

    private func completeEffect(_ id: UUID) {
        if shownEffect?.id == id { shownEffect = nil }
    }

    private func choose(_ item: ClientMoodItemResponse) {
        guard pendingSave == nil else { return }
        saveFailed = false
        pendingSave = item.publicId
    }

    private func save(_ id: UUID) async {
        defer { if pendingSave == id { pendingSave = nil } }
        do {
            let result = try await model.service.setMood(id, session: model.session)
            try Task.checkCancellation()
            guard pendingSave == id else { return }
            mood = result
            #if os(macOS)
            MacMenuBarProfile.shared.updateMood(result, sessionID: model.session.sessionPublicId)
            #endif
            AccessibilityNotification.Announcement(text("ShellMoodSaved")).post()
            suppressHover = true
            pickerMode = nil
        } catch {
            if !Task.isCancelled && pendingSave == id {
                saveFailed = true
                AccessibilityNotification.Announcement(text("ShellMoodSaveFailed")).post()
            }
        }
    }

    private func observeController() async {
        await GamepadControls.observe(scope: {
            scenePhase == .active && pickerMode != nil ? (pendingSave == nil) : nil
        }) { input, _ in
            if input == .back { pickerMode = nil; return }
            guard pendingSave == nil else { return }
            switch input {
            case .move(.left): moveFocus(by: -1)
            case .move(.right): moveFocus(by: 1)
            case .move(.up), .scroll(.up): moveFocus(by: -columnCount)
            case .move(.down), .scroll(.down): moveFocus(by: columnCount)
            case .previousSection, .previousField: moveFocus(by: -1)
            case .nextSection, .nextField: moveFocus(by: 1)
            case .accept:
                if let tile = matches.first(where: { $0.publicId == selectedTile }) ?? matches.first { choose(tile) }
            case .reset, .primary: focusCurrentMood()
            default: break
            }
        }
    }

    private func moveFocus(by offset: Int) {
        let visible = matches
        guard !visible.isEmpty else { return }
        #if os(macOS)
        navigationFocus.updateForNavigation(true)
        #endif
        searchFocused = false
        guard let index = visible.firstIndex(where: { $0.publicId == selectedTile }) else {
            selectedTile = visible.first?.publicId
            return
        }
        selectedTile = visible[max(0, min(visible.count - 1, index + offset))].publicId
    }

    private func focusCurrentMood() {
        searchFocused = false
        selectedTile = matches.first(where: { $0.publicId == mood?.publicId })?.publicId ?? matches.first?.publicId
    }

    private func text(_ key: String) -> String { localization.string(key, table: "MusicHome") }

    private func title(_ item: ClientMoodItemResponse) -> String {
        if localization.isPersian, let persian = item.persianTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           !persian.isEmpty {
            return persian
        }
        return item.title
    }

    private struct CatalogRequest: Equatable {
        let needed: Bool
        let retry: Int
    }

    private struct LoopAsset {
        let media: UUID
        let file: URL
    }

    private struct EffectChoice: Equatable {
        let mood: UUID
        let media: UUID
    }

    private struct EffectLoadKey: Equatable {
        let choice: EffectChoice?
        let active: Bool
        let retry: Int
    }
}

private struct MoodSearchEntry {
    let mood: ClientMoodItemResponse
    let title: String
    let persian: String

    init(_ mood: ClientMoodItemResponse) {
        self.mood = mood
        title = Self.normalize(mood.title)
        persian = Self.normalize(mood.persianTitle ?? "")
    }

    func contains(_ query: String) -> Bool {
        mood.emoji.contains(query) || title.contains(query) || persian.contains(query)
    }

    static func normalize(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "ي", with: "ی")
            .replacingOccurrences(of: "ك", with: "ک")
            .replacingOccurrences(of: "\u{200c}", with: " ")
            .lowercased()
    }
}

private struct MoodTilePreview: View {
    let item: ClientMoodItemResponse
    let model: MusicHomeViewModel
    let selected: Bool
    @State private var image: CGImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else if item.previewMediaPublicId == nil || failed {
                Text(item.emoji).font(.system(size: 24))
            }
        }
        .frame(width: 32, height: 32)
        .opacity(selected ? 1 : 0.88)
        .accessibilityHidden(true)
        .task(id: item.previewMediaPublicId) {
            image = nil
            failed = false
            guard let media = item.previewMediaPublicId, media != UUID.zeroMoodID else {
                failed = true
                return
            }
            let preview = try? await model.artwork.image(media, session: model.session)
            guard !Task.isCancelled else { return }
            image = preview
            failed = preview == nil
        }
    }
}

private struct MoodButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isFocused) private var focused
    @State private var over = false

    func makeBody(configuration: Configuration) -> some View {
        let highlighted = over || focused
        let scale: CGFloat = configuration.isPressed ? 0.90 : highlighted ? 1.09 : 1
        let light = configuration.isPressed ? 0.04 : highlighted ? 0.16 : 0

        configuration.label
            .scaleEffect(scale)
            .animation(reduceMotion ? nil : .timingCurve(0.2, 0.8, 1, 1, duration: 0.16), value: scale)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(light))
                    .animation(reduceMotion ? nil : .linear(duration: 0.16), value: light)
            }
            .contentShape(.rect(cornerRadius: 10))
            .onHover { over = $0 }
            .authHandPointer(enabled: true)
    }
}

private extension UUID {
    static let zeroMoodID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

#if os(macOS)
private struct MoodSecondaryClick: NSGestureRecognizerRepresentable {
    let action: () -> Void

    func makeNSGestureRecognizer(context: Context) -> NSClickGestureRecognizer {
        let gesture = NSClickGestureRecognizer()
        gesture.buttonMask = 0x2
        return gesture
    }

    func handleNSGestureRecognizerAction(_ gesture: NSClickGestureRecognizer, context: Context) {
        if gesture.state == .ended { action() }
    }
}
#endif
#endif
