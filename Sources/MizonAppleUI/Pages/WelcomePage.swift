#if !os(watchOS)
import GameController
import SwiftUI
import MizonAppleCore
#if os(macOS)
import AppKit
#endif

struct WelcomePage: View {
    private enum Control: Hashable { case signIn, retry }
    private enum Command: Hashable { case activate, signIn, retry, help, previous, next, focusSignIn, focusRetry }

    @State private var model: WelcomeViewModel
    @State private var attempt = 0
    @State private var entranceVisible = false
    @State private var leaving = false
    @State private var showHelp = false
    @State private var scroll = ScrollPosition()
    @State private var scrollOffset: CGFloat = 0
    @FocusState private var focus: Control?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @Environment(\.appearsActive) private var appearsActive
    #endif
    private var localization = AuthLocalization()
    let profileTransition: Namespace.ID
    let restoreSession: () async throws -> AuthSession?
    let signIn: () async -> Bool
    let accountReady: (AuthSession, WelcomeAccount) -> Void
    let enter: (AuthSession, WelcomeAccount?, CGImage?) -> Void

    init(service: any WelcomeService, profileTransition: Namespace.ID,
         restoreSession: @escaping () async throws -> AuthSession?,
         signIn: @escaping () async -> Bool,
         accountReady: @escaping (AuthSession, WelcomeAccount) -> Void = { _, _ in },
         enter: @escaping (AuthSession, WelcomeAccount?, CGImage?) -> Void) {
        _model = State(initialValue: WelcomeViewModel(service: service))
        self.profileTransition = profileTransition
        self.restoreSession = restoreSession
        self.signIn = signIn
        self.accountReady = accountReady
        self.enter = enter
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = Metrics(height: geometry.size.height)
            let orbitSize = min(layout.orbitSize, max(0, geometry.size.width - 48))
            ScrollView {
                VStack(spacing: layout.spacing) {
                    wordmark(size: layout.brandSize)
                    ZStack {
                        WelcomeOrbit(size: orbitSize, moves: !reduceMotion && isActive)
                        WelcomeProfileBadge(avatar: model.avatar)
                            .frame(width: orbitSize / 4, height: orbitSize / 4)
                            .matchedGeometryEffect(id: "welcome-profile", in: profileTransition)
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title)
                            .font(localization.font(layout.headingSize, weight: .semibold))
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("welcome.title")
                        Text(localization["WelcomeTagline"])
                            .font(localization.font(12)).foregroundStyle(AuthAppearance.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    statusCard
                }
                .environment(\.layoutDirection, localization.isPersian ? .rightToLeft : .leftToRight)
                .frame(maxWidth: 480)
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                .opacity(entranceVisible ? 1 : 0)
            }
            .scrollIndicators(.hidden)
            .scrollPosition($scroll)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top
            } action: { _, offset in
                scrollOffset = offset
            }
            #if os(iOS)
            .overlay(alignment: .topLeading) {
                AuthLanguagePicker()
                    .frame(minHeight: 36)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .environment(\.layoutDirection, .leftToRight)
            }
            #endif
        }
        .environment(\.layoutDirection, .leftToRight)
        .background {
            WindowGlass()
                .overlay(.black.opacity(0.42))
                .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .tint(AuthAppearance.accent)
        .accessibilityIdentifier("welcome")
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.42)) { entranceVisible = true }
        }
        .task(id: attempt) { await prepare() }
        .task(id: isActive) {
            if isActive { await observeController() }
        }
        #if os(macOS)
        .task(id: model.isBusy) { await showDockActivity() }
        #endif
        .onChange(of: model.stage) {
            if model.stage == .connectionError || model.stage == .ready {
                AccessibilityNotification.Announcement(localization[statusKeys.title]).post()
            }
        }
        .alert(localization["GamepadControls"], isPresented: $showHelp) {
            Button(localization["AuthDone"], role: .cancel) {}
        } message: {
            Text(localization["GamepadWelcomeHelp"].split(separator: "\n").prefix(4).joined(separator: "\n"))
        }
    }

    private var isActive: Bool {
        #if os(macOS)
        scenePhase == .active && appearsActive
        #else
        scenePhase == .active
        #endif
    }

    private var title: String {
        guard let account = model.account else { return localization["WelcomeTitle"] }
        if account.displayName.isEmpty { return localization["WelcomeBack"] }
        return localization["WelcomeBackNamed"].replacingOccurrences(of: "{0}", with: account.displayName)
    }

    private var statusKeys: (title: String, detail: String) {
        switch model.stage {
        case .initial: ("WelcomeCheckingTitle", "WelcomeInitialDetail")
        case .checking: ("WelcomeCheckingTitle", "WelcomeCheckingDetail")
        case .profile: ("WelcomeProfileTitle", "WelcomeProfileDetail")
        case .ready: ("WelcomeReadyTitle", "WelcomeReadyDetail")
        case .connectionError: ("WelcomeConnectionErrorTitle", "WelcomeConnectionErrorDetail")
        }
    }

    private var statusCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(localization[statusKeys.title])
                        .font(localization.font(13, weight: .semibold))
                        .accessibilityIdentifier("welcome.status")
                    Text(localization[statusKeys.detail])
                        .font(localization.font(11)).foregroundStyle(AuthAppearance.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    if model.isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 20, height: 20)
                            .accessibilityLabel(localization["WelcomeAccountProgress"])
                    }
                }
                .frame(width: 38, height: 38)
                .background(model.isBusy ? AuthAppearance.accentWash : .clear, in: .rect(cornerRadius: 12))
                .overlay {
                    if model.isBusy {
                        RoundedRectangle(cornerRadius: 12).strokeBorder(AuthAppearance.accentWash)
                    }
                }
            }
            ZStack {
                if model.isBusy {
                    WelcomeProgress(moves: !reduceMotion && isActive)
                        .accessibilityLabel(localization["WelcomeAppProgress"])
                }
            }
            .frame(height: 2)

            if model.stage == .connectionError {
                HStack(spacing: 8) {
                    Button { Task { await goToLogin() } } label: {
                        actionLabel("WelcomeLogin", emphasis: false, control: .signIn)
                    }
                    .focused($focus, equals: .signIn)
                    .authHandPointer(enabled: !leaving && !model.isBusy)
                    .accessibilityIdentifier("welcome.signIn")

                    Button(action: retry) {
                        actionLabel("WelcomeRetry", emphasis: true, control: .retry)
                    }
                    .focused($focus, equals: .retry)
                    .authHandPointer(enabled: !leaving && !model.isBusy)
                    .accessibilityIdentifier("welcome.retry")
                }
                .buttonStyle(.plain)
                .disabled(leaving || model.isBusy)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(AuthAppearance.cardFill, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(AuthAppearance.stroke)
                .allowsHitTesting(false)
        }
    }

    private func actionLabel(_ key: String, emphasis: Bool, control: Control) -> some View {
        Text(localization[key])
            .font(localization.font(11))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(emphasis ? AuthAppearance.accentWash : AuthAppearance.cardFill, in: .rect(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(focus == control ? AuthAppearance.accent : emphasis ? AuthAppearance.accentBorder : AuthAppearance.stroke)
            }
            .contentShape(.rect)
    }

    private func wordmark(size: CGFloat) -> some View {
        HStack(spacing: 10) {
            Rectangle().fill(AuthAppearance.accentTint).frame(width: 28, height: 1)
            Text("MIZON")
                .font(AuthLocalization.englishFont(size, weight: .semibold))
                .tracking(size * 0.16)
                .foregroundStyle(.linearGradient(colors: [AuthAppearance.accent, AuthAppearance.purple],
                                                  startPoint: .topLeading, endPoint: .bottomTrailing))
            Rectangle().fill(AuthAppearance.purple.opacity(50.0 / 255)).frame(width: 28, height: 1)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityHidden(true)
    }

    private func prepare() async {
        let clock = ContinuousClock()
        let started = clock.now
        guard let result = await model.prepare(onAccount: accountReady, session: restoreSession), !Task.isCancelled else { return }
        switch result {
        case .login:
            await goToLogin()
        case .home(let session):
            if !reduceMotion {
                let remaining = max(.milliseconds(900) - started.duration(to: clock.now),
                                    model.avatar == nil ? .zero : .milliseconds(220))
                do { try await Task.sleep(for: remaining) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            enter(session, model.account, model.avatar)
        }
    }

    private func retry() {
        guard !leaving, !model.isBusy, model.stage == .connectionError else { return }
        focus = nil
        attempt += 1
    }

    private func goToLogin() async {
        guard !leaving else { return }
        leaving = true
        defer { leaving = false }
        if !(await signIn()) { model.showConnectionError() }
    }

    private func observeController() async {
        var previous: Set<Command> = []
        var armed = false
        while !Task.isCancelled {
            let pad = GCController.controllers().first(where: { $0.extendedGamepad != nil })?.extendedGamepad
            if let pad {
                let buttons: [(Command, Bool)] = [
                    (.signIn, pad.buttonB.isPressed || pad.leftShoulder.isPressed),
                    (.help, pad.buttonOptions?.isPressed == true),
                    (.retry, pad.buttonMenu.isPressed),
                    (.activate, pad.buttonA.isPressed),
                    (.focusRetry, pad.leftThumbstickButton?.isPressed == true),
                    (.focusSignIn, pad.rightShoulder.isPressed || pad.rightThumbstickButton?.isPressed == true),
                    (.previous, pad.dpad.left.isPressed || pad.dpad.up.isPressed || pad.leftTrigger.isPressed
                        || pad.leftThumbstick.xAxis.value < -0.65 || pad.leftThumbstick.yAxis.value > 0.65),
                    (.next, pad.dpad.right.isPressed || pad.dpad.down.isPressed || pad.rightTrigger.isPressed
                        || pad.leftThumbstick.xAxis.value > 0.65 || pad.leftThumbstick.yAxis.value < -0.65)
                ]
                let pressed = Set(buttons.filter { $0.1 }.map(\.0))
                if pressed.isEmpty { armed = true }
                if armed, let command = buttons.first(where: { $0.1 && !previous.contains($0.0) })?.0 {
                    await apply(command)
                }
                if armed, !showHelp, abs(pad.rightThumbstick.yAxis.value) > 0.65 {
                    let step: CGFloat = pad.rightThumbstick.yAxis.value > 0 ? -12 : 12
                    scroll.scrollTo(y: max(0, scrollOffset + step))
                }
                previous = pressed
            } else {
                armed = false
                previous.removeAll()
            }
            do { try await Task.sleep(for: pad == nil ? .milliseconds(500) : .milliseconds(45)) }
            catch { return }
        }
    }

    private func apply(_ command: Command) async {
        if command == .help {
            showHelp.toggle()
        } else if showHelp {
            if command == .signIn || command == .activate { showHelp = false }
        } else if model.stage == .connectionError && !leaving && !model.isBusy {
            switch command {
            case .signIn: await goToLogin()
            case .retry: retry()
            case .activate:
                if focus == .signIn { await goToLogin() } else if focus == .retry { retry() }
            case .focusSignIn: focus = .signIn
            case .focusRetry: focus = .retry
            case .previous: focus = localization.isPersian ? .retry : .signIn
            case .next: focus = localization.isPersian ? .signIn : .retry
            case .help: break
            }
        }
    }

    #if os(macOS)
    private func showDockActivity() async {
        guard model.isBusy else { return }
        do { try await Task.sleep(for: .milliseconds(650)) }
        catch { return }
        guard model.isBusy else { return }
        let tile = NSApp.dockTile
        let previous = tile.badgeLabel
        tile.badgeLabel = "…"
        defer { if tile.badgeLabel == "…" { tile.badgeLabel = previous } }
        // Cancellation when the account check finishes or Welcome disappears clears the badge.
        try? await Task.sleep(for: .seconds(60))
    }
    #endif

    private struct Metrics {
        let orbitSize: CGFloat
        let spacing: CGFloat
        let headingSize: CGFloat
        let brandSize: CGFloat

        init(height: CGFloat) {
            if height >= 780 {
                (orbitSize, spacing, headingSize, brandSize) = (300, 18, 26, 34)
            } else if height >= 620 {
                (orbitSize, spacing, headingSize, brandSize) = (230, 14, 24, 28)
            } else {
                (orbitSize, spacing, headingSize, brandSize) = (170, 10, 21, 28)
            }
        }
    }
}

private struct WelcomeProgress: View {
    let moves: Bool
    @State private var moved = false
    @Environment(\.layoutDirection) private var direction

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let distance = moved ? width : -width * 0.32
            Capsule().fill(AuthAppearance.accentWash)
                .overlay(alignment: .leading) {
                    Capsule().fill(AuthAppearance.accent)
                        .frame(width: width * 0.32)
                        .offset(x: moves ? (direction == .rightToLeft ? -distance : distance) : 0)
                }
                .clipped()
        }
        .accessibilityElement()
        .accessibilityAddTraits(.updatesFrequently)
        .onChange(of: moves, initial: true) {
            withAnimation(moves ? .linear(duration: 1.3).repeatForever(autoreverses: false) : nil) {
                moved = moves
            }
        }
    }
}
#endif
