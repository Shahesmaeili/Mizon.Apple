import SwiftUI
import MizonAppleCore
#if os(iOS)
import UIKit
#endif
#if !os(watchOS)
import GameController
#if os(macOS)
import AppKit
#endif
#endif

public struct MizonRootView: View {
    @State private var model: LoginViewModel
    #if !os(watchOS)
    @State private var profileTransition = ProfilePictureTransition()
    @State private var checkedStartup = false
    @State private var home: HomeEntrance?
    @State private var nearby = NearbyDiscoveryModel()
    @State private var nearbyIdentity: NearbyIdentity?
    @ObservedObject private var shellShortcuts = MizonShellShortcuts.shared
    @State private var authShortcut: ShellShortcutRequest?
    @State private var accountSheet: ShellShortcutRequest?
    @State private var sectionShortcut: ShellShortcutRequest?
    @State private var signingOut = false
    private var localization = AuthLocalization()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    @State private var nearbyInForeground = false
    #endif

    private struct HomeEntrance {
        let sessionID: UUID
        let account: WelcomeAccount?
        var avatar: CGImage?
    }

    private struct NearbyIdentity: Equatable {
        let sessionID: UUID
        let username: String?
        let displayName: String
    }

    private var discoverableIdentity: NearbyIdentity? {
        #if os(iOS)
        guard nearbyInForeground else { return nil }
        #endif
        guard nearby.enabled, let nearbyIdentity, nearbyIdentity.sessionID == model.session?.sessionPublicId else { return nil }
        return nearbyIdentity
    }
    #endif

    public init(model: LoginViewModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ZStack { content }
            .foregroundStyle(MizonPalette.ink)
            .tint(MizonPalette.accent)
            .preferredColorScheme(.dark)
            .background { WindowGlass().ignoresSafeArea() }
            #if os(iOS)
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active { nearbyInForeground = true }
                if phase == .background {
                    nearbyInForeground = false
                    profileTransition.cancel()
                }
            }
            #endif
            #if os(macOS) || os(iOS)
            .task(id: home?.sessionID) { await profileTransition.play() }
            .task(id: home?.sessionID) { await loadMissingHomeAvatar() }
            .onChange(of: reduceMotion) { _, enabled in
                if enabled { profileTransition.cancel() }
            }
            .onDisappear { profileTransition.cancel() }
            .onChange(of: shellContext, initial: true) { _, _ in
                updateShortcutMenu()
                openPendingShortcut()
            }
            .onChange(of: shellShortcuts.pending) { openPendingShortcut() }
            .onChange(of: localization.isPersian) { updateShortcutMenu() }
            .onChange(of: model.session?.sessionPublicId) {
                accountSheet = nil
                authShortcut = nil
            }
            .sheet(item: $accountSheet, onDismiss: model.dismissError) { request in
                AuthenticationPage(model: model, shellRequest: request) { accountSheet = nil }
                    .safeAreaInset(edge: .top, spacing: 0) {
                        Button(localization["AuthDone"]) { accountSheet = nil }
                            .buttonStyle(.glass)
                            .keyboardShortcut(.cancelAction)
                            .disabled(model.isLoading)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(12)
                    }
                    .interactiveDismissDisabled(model.isLoading)
                    #if os(macOS)
                    .frame(minWidth: 410, idealWidth: 490, minHeight: 520, idealHeight: 650)
                    #endif
            }
            .task(id: discoverableIdentity) { [identity = discoverableIdentity] in
                let mediaAccess: NearbyMediaAccess?
                if let identity, let session = model.session, identity.sessionID == session.sessionPublicId {
                    mediaAccess = model.musicHomeService.nearbyMediaAccess(session: session)
                } else {
                    mediaAccess = nil
                }
                await nearby.discover(inForeground: identity != nil,
                                      publicUsername: identity?.username, displayName: identity?.displayName,
                                      mediaAccess: mediaAccess)
            }
            #endif
            #if os(macOS)
            .toolbar {
                if showingAuthentication {
                    ToolbarSpacer(.flexible, placement: .primaryAction)
                    ToolbarItem(placement: .primaryAction) {
                        AuthLanguagePicker()
                    }
                    .sharedBackgroundVisibility(.hidden)
                }
            }
            .toolbarBackground(.hidden, for: .windowToolbar)
            .environment(\.layoutDirection, .leftToRight)
            #endif
    }

    #if os(macOS) || os(iOS)
    private var shellContext: ShellShortcutContext {
        if signingOut { return .signingOut }
        if model.isLoading { return .busy }
        guard let session = model.session else { return checkedStartup ? .signedOut : .restoring }
        return home?.sessionID == session.sessionPublicId ? .home : .preparingHome
    }

    private func updateShortcutMenu() {
        guard checkedStartup || model.session != nil else { return }
        shellShortcuts.configure(signedIn: model.session != nil, language: localization.isPersian ? "fa" : "en")
    }

    private func openPendingShortcut() {
        guard let request = shellShortcuts.pending else { return }
        switch shellContext.action(for: request.destination) {
        case .wait:
            return
        case .showSignIn:
            // Keep the requested section until the existing Welcome flow validates the session.
            if authShortcut?.id != request.id {
                authShortcut = ShellShortcutRequest(id: request.id, destination: .login)
            }
            return
        case .discard:
            break
        case .account:
            if model.session == nil {
                authShortcut = request
                checkedStartup = true
            } else {
                accountSheet = request
            }
        case .section:
            accountSheet = nil
            sectionShortcut = request
        }
        shellShortcuts.complete(request)
    }

    private func loadMissingHomeAvatar() async {
        guard let session = model.session, let home, home.sessionID == session.sessionPublicId,
              home.avatar == nil, let avatarID = home.account?.avatarID,
              let avatar = try? await model.welcomeService.avatar(for: avatarID, session: session),
              !Task.isCancelled, model.session?.sessionPublicId == session.sessionPublicId,
              self.home?.sessionID == session.sessionPublicId else { return }
        self.home?.avatar = avatar
    }
    #endif

    #if os(macOS)
    private var showingAuthentication: Bool {
        home == nil || home?.sessionID != model.session?.sessionPublicId
    }
    #endif

    @ViewBuilder
    private var content: some View {
        #if os(watchOS)
        WatchLoginPage(model: model)
        #else
        if let session = model.session, let home, home.sessionID == session.sessionPublicId {
            MusicHomePage(session: session, service: model.musicHomeService, displayName: home.account?.displayName,
                          nearby: nearby, avatar: home.avatar, profileTransition: profileTransition,
                          initialMood: home.account?.mood, shellRequest: $sectionShortcut,
                          shellAccountOpen: accountSheet != nil) {
                guard !signingOut else { return }
                signingOut = true
                Task {
                    defer { signingOut = false }
                    await model.signOut()
                    if model.session == nil { self.home = nil }
                }
            }
            .alert(model.error?.errorDescription ?? "Sign out failed", isPresented: Binding(
                get: { accountSheet == nil && model.error != nil },
                set: { if !$0 { model.dismissError() } }
            )) {
                Button(model.error?.closeButtonText ?? "OK") { model.dismissError() }
            } message: {
                Text(model.error?.details ?? "")
            }
        } else if model.session != nil || !checkedStartup {
            WelcomePage(
                service: model.welcomeService,
                profileTransition: profileTransition,
                restoreSession: { try await model.activeOrRestoredSession() },
                signIn: {
                    await model.signOut()
                    guard model.session == nil else { return false }
                    checkedStartup = true
                    home = nil
                    return true
                },
                accountReady: { session, account in
                    guard model.session?.sessionPublicId == session.sessionPublicId else { return }
                    nearbyIdentity = NearbyIdentity(sessionID: session.sessionPublicId, username: account.publicUsername,
                                                    displayName: account.displayName)
                },
                enter: { session, account, avatar in
                    guard model.session == session else { return }
                    model.dismissError()
                    profileTransition.prepare(avatar: avatar, displayName: account?.displayName, reduceMotion: reduceMotion)
                    checkedStartup = true
                    home = HomeEntrance(sessionID: session.sessionPublicId, account: account, avatar: avatar)
                }
            )
        } else {
            AuthenticationPage(model: model, shellRequest: authShortcut)
        }
        #endif
    }
}

#if !os(watchOS)
private struct AuthenticationPage: View {
    private enum GamepadAction: Hashable {
        case back, help, submit, accept, next, previous, clear, reveal, switchMode, reset, primary
    }

    private enum Field: String, Sendable {
        case identifier, loginPassword, firstName, lastName, username, email, password, confirmation

        var helpKey: String {
            switch self {
            case .identifier: "AuthLoginIdentifierHelp"
            case .loginPassword: "AuthLoginPasswordHelp"
            case .firstName: "AuthFirstNameHelp"
            case .lastName: "AuthLastNameHelp"
            case .username: "AuthUsernameHelp"
            case .email: "AuthEmailHelp"
            case .password: "AuthRegisterPasswordHelp"
            case .confirmation: "AuthConfirmPasswordHelp"
            }
        }

        nonisolated func accepts(_ text: String) -> Bool {
            switch self {
            case .identifier: text.utf16.count <= 256 && AuthIdentifierInput.isAllowed(text, allowsEmail: true)
            case .username: text.utf16.count <= 32 && AuthIdentifierInput.isAllowed(text, allowsEmail: false)
            case .email: text.utf16.count <= 128 && AuthIdentifierInput.isAllowed(text, allowsEmail: true)
            case .firstName, .lastName: text.utf16.count <= 60
            case .password, .confirmation: text.utf16.count <= 128
            case .loginPassword: true
            }
        }
    }

    @Bindable var model: LoginViewModel
    var shellRequest: ShellShortcutRequest? = nil
    var closeShortcut: (() -> Void)? = nil
    private var localization = AuthLocalization()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var swiftUIFocus: Field?
    #if os(macOS)
    @State private var nativeFocus: Field?
    #elseif os(iOS)
    @State private var passwordFocused = false
    #endif
    private var focus: Field? {
        get {
            #if os(macOS)
            nativeFocus ?? swiftUIFocus
            #elseif os(iOS)
            passwordFocused ? .loginPassword : swiftUIFocus
            #else
            swiftUIFocus
            #endif
        }
        nonmutating set {
            #if os(macOS)
            nativeFocus = newValue.flatMap { usesNativeInput($0) ? $0 : nil }
            swiftUIFocus = nativeFocus == nil ? newValue : nil
            #elseif os(iOS)
            passwordFocused = newValue == .loginPassword
            if !passwordFocused { swiftUIFocus = newValue }
            #else
            swiftUIFocus = newValue
            #endif
        }
    }
    @State private var flip = FlipSelection()
    private var registration: Bool { flip.showsBack }
    @State private var revealPassword = false
    @GestureState private var peeking: Field?
    @State private var request: Task<Void, Never>?
    @State private var gamepadRevealedField: Field?
    @State private var showsControllerHelp = false
    @FocusState private var primaryFocusMode: Bool?
    @FocusState private var modeActionFocus: Bool?
    private var primaryFocused: Bool {
        get { primaryFocusMode == registration }
        nonmutating set { primaryFocusMode = newValue ? registration : nil }
    }
    @State private var scene = AuthScene.music
    @State private var previousScene: AuthScene?
    @State private var showcaseStart = Date()
    @State private var showcaseHovered = false
    @State private var hoveredField: Field?
    @State private var entranceVisible = false
    @FocusState private var showcaseFocused: AuthScene?
    #if os(iOS)
    private enum TapSpace { case authentication }
    @State private var showsSettings = false
    @State private var inputFrames: [Field: CGRect] = [:]
    #endif

    private var isPersian: Bool { localization.isPersian }
    private func text(_ key: String) -> String { localization[key] }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            #if os(macOS)
            let height = geometry.size.height
            #else
            let height = geometry.size.height - 48
            #endif
            let wide = width >= 900 && height >= 550
            let split = wide || (width >= 680 && height >= 420)
            let bottomInset: CGFloat = wide ? 14 : 8
            let sideInset: CGFloat = wide ? 40 : split ? 24 : 16
            let columnSpacing: CGFloat = wide ? 32 : split ? 20 : 0
            let available = max(0, min(1040, width - sideInset * 2) - columnSpacing)
            let artWidth = split ? available * (wide ? 1.1 / 2.1 : 0.9 / 1.9) : 0
            let formWidth = available - artWidth

            VStack(spacing: 0) {
                #if os(iOS)
                header
                #endif
                if !split { wordmark.padding(.bottom, 6) }
                HStack(spacing: columnSpacing) {
                    if split {
                        showcase(wide: wide)
                            .frame(maxWidth: 430)
                            .frame(width: artWidth)
                    }
                    ScrollViewReader { proxy in
                        ScrollView {
                            FlipSide(selection: $flip) {
                                form(wide: wide, registration: false)
                            } side2: {
                                form(wide: wide, registration: true)
                            }
                                .id("auth-form")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 24)
                                .frame(minHeight: max(0, height - bottomInset - (split ? 0 : 46)))
                        }
                        .scrollIndicators(.hidden)
                        .defaultScrollAnchor(.top)
                        .onChange(of: registration) {
                            withAnimation(nil) {
                                proxy.scrollTo("auth-form", anchor: .top)
                            }
                        }
                    }
                    .frame(maxWidth: 448)
                    .frame(width: formWidth)
                }
                .padding(.bottom, bottomInset)
                .opacity(entranceVisible ? 1 : 0)
                .offset(y: entranceVisible ? 0 : 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        #if os(macOS)
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(MizonPalette.negative, lineWidth: 1)
                .opacity(errorKey == nil ? 0 : 1)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: errorKey != nil)
        }
        #endif
        #if os(iOS)
        .contentShape(.rect)
        .coordinateSpace(.named(TapSpace.authentication))
        .simultaneousGesture(
            SpatialTapGesture(coordinateSpace: .named(TapSpace.authentication))
                .onEnded { tap in
                    guard let focus, inputFrames[focus] != nil,
                          !fieldOrder.contains(where: { inputFrames[$0]?.contains(tap.location) == true }) else { return }
                    self.focus = nil
                },
            isEnabled: focus != nil
        )
        .sheet(isPresented: $showsSettings) {
            NavigationStack {
                ServerSettingsView(model: model)
                    .toolbar {
                        Button(text("AuthDone")) { showsSettings = false }
                    }
            }
        }
        #endif
        .alert(text("GamepadControls"), isPresented: $showsControllerHelp) {
            Button(text("AuthDone")) {}
        } message: {
            Text(text("GamepadHelpApple"))
        }
        .task(id: scenePhase) {
            if scenePhase == .active { await observeGamepad() }
        }
        .onChange(of: shellRequest, initial: true) {
            if let shellRequest, registration != (shellRequest.destination == .register) { switchMode() }
        }
        .environment(\.layoutDirection, .leftToRight)
        .onAppear {
            withAnimation(reduceMotion ? nil : .timingCurve(0.16, 0.8, 1, 1, duration: 0.42)) {
                entranceVisible = true
            }
        }
        .onChange(of: focus) {
            if focus != gamepadRevealedField { gamepadRevealedField = nil }
        }
        .onChange(of: scenePhase) {
            if scenePhase != .active {
                revealPassword = false
                gamepadRevealedField = nil
            }
        }
        .onDisappear {
            if model.session == nil { request?.cancel() }
            model.clearSensitiveInputs()
        }
        #if os(macOS)
        .task { focus = .identifier }
        #endif
    }

    #if os(iOS)
    private var header: some View {
        HStack {
            AuthLanguagePicker()
            Spacer()
            Button {
                focus = nil
                showsSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.glass)
            .disabled(model.isLoading)
            .accessibilityLabel(localization.string("ServerSettings", table: "Settings"))
        }
        .padding(.horizontal, 24)
        .frame(height: 48)
    }
    #endif

    private var wordmark: some View {
        HStack(spacing: 10) {
            FluentIcon(symbol: .headphones, size: 24, usesColor: true)
            Text("MIZON").tracking(2.99).font(englishFont(23, weight: .semibold))
        }
        .foregroundStyle(AuthAppearance.accent)
        .accessibilityLabel("Mizon")
    }

    private func form(wide: Bool, registration: Bool) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    FluentIcon(symbol: .person, size: 13)
                    Text(text("AuthAccountLabel")).font(authFont(11))
                }
                .foregroundStyle(AuthAppearance.accent)
                Text(text(registration ? "AuthRegisterHeading" : "AuthLoginHeading"))
                    .font(authFont(27, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Text(text(registration ? "AuthRegisterDescription" : "AuthLoginDescription"))
                    .font(authFont(12))
                    .foregroundStyle(MizonPalette.secondaryText)
            }
            VStack(alignment: .leading, spacing: registration ? 12 : 16) {
                if registration {
                    HStack(alignment: .top, spacing: 12) {
                        input(.firstName, label: "AuthFirstNameLabel", value: $model.registration.firstName, type: .givenName)
                        input(.lastName, label: "AuthLastNameLabel", value: $model.registration.lastName, type: .familyName)
                    }
                    input(.username, label: "AuthUsernameLabel", value: $model.registration.username,
                          type: .username, hint: "AuthUsernameHint")
                    input(.email, label: "AuthEmailLabel", value: $model.registration.emailAddress, type: .emailAddress)
                    input(.password, label: "AuthPasswordLabel", value: $model.registration.password,
                          type: .newPassword, hint: "AuthRegisterPasswordHelp", secure: true)
                    input(.confirmation, label: "AuthConfirmPasswordLabel", value: $model.confirmation,
                          type: .newPassword, secure: true)
                } else {
                    input(.identifier, label: "AuthLoginIdentifierLabel", value: $model.identifier, type: .username)
                    input(.loginPassword, label: "AuthPasswordLabel", value: $model.password, type: .password, secure: true)
                }
            }
            if self.registration == registration, let key = errorKey {
                AuthErrorCard(title: text(registration ? "AuthRegisterErrorTitle" : "AuthLoginErrorTitle"),
                              message: text(key))
            }
            Button(action: submit) {
                HStack(spacing: 10) {
                    FluentIcon(symbol: .arrowLeft, size: 17).frame(width: 20)
                    Text(text(submitKey(registration: registration)))
                        .font(authFont(13, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .environment(\.layoutDirection, isPersian ? .rightToLeft : .leftToRight)
                        .frame(maxWidth: .infinity)
                    if model.isLoading && self.registration == registration {
                        ProgressView()
                            .controlSize(.small)
                            .tint(MizonPalette.surface)
                            .frame(width: 20, height: 18)
                    } else {
                        Color.clear.frame(width: 20, height: 1)
                    }
                }
                .environment(\.layoutDirection, .leftToRight)
            }
            .buttonStyle(AuthActionStyle(primary: true, reduceMotion: reduceMotion, focused: primaryFocusMode == registration))
            .focused($primaryFocusMode, equals: registration)
            .accessibilityHint(text(registration ? "AuthRegisterSubmitHelp" : "AuthLoginSubmitHelp"))
            .disabled(registration ? !model.canRegister : !model.canSubmit)

            VStack(spacing: 12) {
                Rectangle().fill(AuthAppearance.divider).frame(height: 1)
                Button(action: switchMode) {
                    HStack(spacing: 9) {
                        FluentIcon(symbol: .personAdd, size: 16)
                        Text(text(registration ? "AuthSignInAccount" : "AuthCreateAccount"))
                            .font(authFont(13, weight: .semibold))
                    }
                }
                .buttonStyle(AuthActionStyle(primary: false, reduceMotion: reduceMotion, focused: modeActionFocus == registration))
                .focused($modeActionFocus, equals: registration)
                .accessibilityHint(text("AuthModeSwitchHelp"))
                .disabled(model.isLoading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, wide ? 30 : 22)
        .padding(.vertical, wide ? 32 : 24)
        .background(AuthAppearance.cardFill, in: .rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(AuthAppearance.accentTint)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(AuthAppearance.accentBorder)
                        .opacity(formHasFocus(registration: registration) ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: formHasFocus(registration: registration))
                }
                .allowsHitTesting(false)
        }
        .environment(\.layoutDirection, isPersian ? .rightToLeft : .leftToRight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(registration ? "registration.card" : "login.card")
    }

    private func formHasFocus(registration: Bool) -> Bool {
        self.registration == registration && (focus != nil || primaryFocusMode == registration || modeActionFocus == registration)
    }

    private func submitKey(registration: Bool) -> String {
        let loading = model.isLoading && registration == self.registration
        if registration { return loading ? "AuthRegisterProgress" : "AuthRegisterSubmit" }
        return loading ? "AuthLoginProgress" : "AuthLoginSubmit"
    }

    private func englishFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        AuthLocalization.englishFont(size, weight: weight)
    }

    private func authFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        localization.font(size, weight: weight)
    }

    private var errorKey: String? {
        if let validation = model.validationKey { return validation }
        guard let error = model.error else { return nil }
        if case .api(let code, _, _, _) = error {
            switch code {
            case 21000: return "AuthInvalidRegistrationError"
            case 21001: return "AuthUsernameTakenError"
            case 21002: return "AuthEmailTakenError"
            case 21003: return "AuthRegistrationUnavailableError"
            case 401, 1001: return "AuthInvalidCredentialsError"
            case 1000: return "AuthUpdateRequiredError"
            case 101, 102, 104...107: return "AuthConnectionError"
            case 429: return "AuthTooManyAttemptsError"
            default: break
            }
        }
        if error == .invalidServer { return "AuthConnectionError" }
        return registration ? "AuthRegistrationFailedError" : "AuthLoginFailedError"
    }

    private func input(_ field: Field, label: String, value: Binding<String>, type: AuthContentType,
                       hint: String? = nil, secure: Bool = false) -> some View {
        let editable = Binding(get: { value.wrappedValue }, set: { proposed in
            guard field.accepts(proposed) else { return }
            value.wrappedValue = proposed
        })
        let hasClear = !secure && focus == field && !value.wrappedValue.isEmpty
        let hasPeek = secure && field != .loginPassword && focus == field && !value.wrappedValue.isEmpty
        let hasAction = hasClear || hasPeek || field == .loginPassword
        let localizedRow = field == .firstName || field == .lastName || field == .loginPassword
        return VStack(alignment: .leading, spacing: registration ? 6 : 7) {
            Text(text(label)).font(authFont(12))
            HStack(spacing: 4) {
                let showPeek = scenePhase == .active && field != .loginPassword
                    && (peeking == field || gamepadRevealedField == field)
                if usesNativeInput(field) {
                    #if os(macOS)
                    FilteredAuthField(text: value,
                                      isFocused: Binding(get: { nativeFocus == field }, set: {
                                          if $0 { nativeFocus = field }
                                          else if nativeFocus == field { nativeFocus = nil }
                                      }),
                                      label: text(label), help: text(field.helpKey),
                                      identifier: field.rawValue, contentType: type,
                                      font: nativeInputFont, accepts: field.accepts, submit: submit)
                        .frame(height: 24)
                        .accessibilityIdentifier(field.rawValue)
                    #elseif os(iOS)
                    LoginPasswordField(text: editable, isFocused: $passwordFocused,
                                       dismissesFocus: focus == nil, isSecure: !revealPassword,
                                       label: text(label), help: text(field.helpKey), identifier: field.rawValue,
                                       font: passwordInputFont, textColor: UIColor(MizonPalette.ink), submit: submit)
                        .frame(height: 24)
                    #endif
                } else {
                    Group {
                        if secure && (field != .loginPassword || !revealPassword) {
                            SecureField("", text: editable)
                        } else {
                            TextField("", text: editable)
                        }
                    }
                    .font(authFont(14))
                    .textContentType(type)
                    .textFieldStyle(.plain)
                    .focused($swiftUIFocus, equals: field)
                    .accessibilityLabel(text(label))
                    .accessibilityHint(text(field.helpKey))
                    .accessibilityIdentifier(field.rawValue)
                    .environment(\.layoutDirection, isPersian && (field == .firstName || field == .lastName)
                                 ? .rightToLeft : .leftToRight)
                    .onSubmit(submit)
                    .opacity(showPeek ? 0 : 1)
                    .overlay(alignment: .leading) {
                        if showPeek {
                            Text(value.wrappedValue)
                                .font(authFont(14))
                                .lineLimit(1)
                                .truncationMode(.head)
                                .accessibilityHidden(true)
                                .allowsHitTesting(false)
                        }
                    }
                    #if os(iOS)
                    .textInputAutocapitalization(field == .firstName || field == .lastName ? .words : .never)
                    .autocorrectionDisabled()
                    .keyboardType(field == .email ? .emailAddress : .default)
                    #endif
                }

                if hasClear {
                    Button {
                        value.wrappedValue = ""
                    } label: {
                        FluentIcon(symbol: .dismiss, size: 12)
                    }
                    .buttonStyle(AuthFieldActionStyle(isClear: true))
                    .focusable(false)
                    .accessibilityLabel(text("ClearInputName"))
                    .accessibilityHint(text("ClearInputHelp"))
                    .help(text("ClearInputName"))
                }
                if field == .loginPassword {
                    Button {
                        revealPassword.toggle()
                        focus = .loginPassword
                    } label: {
                        FluentIcon(symbol: revealPassword ? .eyeOff : .eye, size: 17)
                    }
                    .buttonStyle(AuthFieldActionStyle(isClear: false))
                    .accessibilityLabel(text(revealPassword ? "AuthHidePassword" : "AuthShowPassword"))
                    .accessibilityHint(text("AuthPasswordRevealHelp"))
                } else if hasPeek {
                    FluentIcon(symbol: showPeek ? .eyeOff : .eye, size: 17)
                        .foregroundStyle(AuthAppearance.accent)
                        .frame(width: 32, height: 32)
                        .contentShape(.circle)
                        .authHandPointer(enabled: !model.isLoading)
                        .gesture(DragGesture(minimumDistance: 0).updating($peeking) { _, state, _ in
                            state = field
                        })
                        .accessibilityHidden(true)
                        .help(text("AuthPasswordPeekHelp"))
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, hasAction ? 6 : 12)
            .environment(\.layoutDirection, isPersian && localizedRow ? .rightToLeft : .leftToRight)
            .frame(minHeight: 44)
            #if os(iOS)
            .onGeometryChange(for: CGRect.self) { geometry in
                geometry.frame(in: .named(TapSpace.authentication))
            } action: { frame in
                inputFrames[field] = frame
            }
            #endif
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AuthAppearance.inputFill(focused: focus == field, hovered: hoveredField == field, disabled: model.isLoading))
                    .contentShape(.rect)
                    .onTapGesture {
                        guard !model.isLoading, focus != field else { return }
                        focus = field
                    }
                    .accessibilityHidden(true)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(AuthAppearance.inputBorder(focused: focus == field, hovered: hoveredField == field, disabled: model.isLoading))
                    .allowsHitTesting(false)
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: focus == field)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: hoveredField == field)
            .onHover { if $0 { hoveredField = field } else if hoveredField == field { hoveredField = nil } }
            if let hint { Text(text(hint)).font(authFont(10)).foregroundStyle(MizonPalette.secondaryText) }
        }
        .frame(maxWidth: .infinity)
        .disabled(model.isLoading)
    }

    private func usesNativeInput(_ field: Field) -> Bool {
        #if os(macOS)
        field == .identifier || field == .username || field == .email
        #elseif os(iOS)
        field == .loginPassword
        #else
        false
        #endif
    }

    #if os(macOS)
    private var nativeInputFont: NSFont {
        WindowsTypography.inputFontName(isPersian: isPersian)
            .flatMap { NSFont(name: $0, size: 14) } ?? .systemFont(ofSize: 14)
    }
    #elseif os(iOS)
    private var passwordInputFont: UIFont {
        WindowsTypography.inputFontName(isPersian: isPersian)
            .flatMap { UIFont(name: $0, size: 14) } ?? .systemFont(ofSize: 14)
    }
    #endif

    private func submit() {
        guard registration ? model.canRegister : model.canSubmit else { return }
        focus = nil
        revealPassword = false
        gamepadRevealedField = nil
        request = Task {
            if registration { await model.register() } else { await model.login() }
            if model.error != nil || model.validationKey != nil {
                AccessibilityNotification.Announcement(errorKey.map(text) ?? "").post()
                #if os(macOS)
                focus = registration ? .firstName : .loginPassword
                #endif
            }
        }
    }

    private func switchMode() {
        model.clearSensitiveInputs()
        model.dismissError()
        revealPassword = false
        gamepadRevealedField = nil
        focus = nil
        primaryFocusMode = nil
        modeActionFocus = nil
        flip.toggle(at: ContinuousClock().now, animated: !reduceMotion)
        AccessibilityNotification.Announcement(text(registration ? "AuthModeRegister" : "AuthModeLogin")).post()
    }

    private var fieldOrder: [Field] {
        registration ? [.firstName, .lastName, .username, .email, .password, .confirmation]
            : [.identifier, .loginPassword]
    }

    private func observeGamepad() async {
        var previous: Set<GamepadAction> = []
        var armed = false
        while !Task.isCancelled {
            let pad = GCController.controllers().first(where: { $0.extendedGamepad != nil })?.extendedGamepad
            if let pad {
                let inputs: [(GamepadAction, Bool)] = [
                    (.back, pad.buttonB.isPressed),
                    (.help, pad.buttonOptions?.isPressed == true),
                    (.submit, pad.buttonMenu.isPressed),
                    (.accept, pad.buttonA.isPressed),
                    (.next, pad.dpad.down.isPressed || pad.dpad.right.isPressed
                        || pad.rightTrigger.isPressed || pad.leftThumbstick.yAxis.value < -0.65),
                    (.previous, pad.dpad.up.isPressed || pad.dpad.left.isPressed || pad.leftTrigger.isPressed
                        || pad.leftThumbstick.yAxis.value > 0.65),
                    (.clear, pad.buttonX.isPressed),
                    (.reveal, pad.buttonY.isPressed),
                    (.switchMode, pad.leftShoulder.isPressed || pad.rightShoulder.isPressed),
                    (.primary, pad.leftThumbstickButton?.isPressed == true),
                    (.reset, pad.rightThumbstickButton?.isPressed == true)
                ]
                let pressed = Set(inputs.filter { $0.1 }.map { $0.0 })
                if pressed.isEmpty { armed = true }
                if armed, !model.isLoading,
                   let action = inputs.first(where: { $0.1 && !previous.contains($0.0) })?.0 {
                    applyGamepad(action)
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

    private func applyGamepad(_ action: GamepadAction) {
        if showsControllerHelp {
            if action == .back || action == .help { showsControllerHelp = false }
            return
        }
        switch action {
        case .back:
            if let closeShortcut {
                if focus == nil { closeShortcut() }
                else { focus = nil; revealPassword = false }
            }
            else if registration { switchMode() }
            else { focus = nil; revealPassword = false }
        case .help:
            showsControllerHelp = true
        case .submit:
            submit()
        case .accept where primaryFocused:
            submit()
        case .accept, .next, .previous:
            if primaryFocused {
                if action == .previous { focus = fieldOrder.last }
            } else if let field = focus, let index = fieldOrder.firstIndex(of: field) {
                let target = index + (action == .previous ? -1 : 1)
                if fieldOrder.indices.contains(target) { focus = fieldOrder[target] }
                else if target == fieldOrder.count { primaryFocused = true }
            } else {
                focus = fieldOrder.first
            }
        case .clear:
            switch focus {
            case .identifier: model.identifier = ""
            case .loginPassword: model.password = ""
            case .firstName: model.registration.firstName = ""
            case .lastName: model.registration.lastName = ""
            case .username: model.registration.username = ""
            case .email: model.registration.emailAddress = ""
            case .password: model.registration.password = ""
            case .confirmation: model.confirmation = ""
            case nil: break
            }
        case .reveal:
            if focus == .loginPassword { revealPassword.toggle() }
            else if focus == .password || focus == .confirmation {
                gamepadRevealedField = gamepadRevealedField == focus ? nil : focus
            }
        case .switchMode:
            switchMode()
            focus = fieldOrder.first
        case .reset:
            focus = fieldOrder.first
        case .primary:
            primaryFocused = true
        }
    }

    private func showcase(wide: Bool) -> some View {
        let height: CGFloat = wide ? 280 : 160
        return VStack(spacing: 14) {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(.linearGradient(colors: [.clear, AuthAppearance.accent.opacity(56.0 / 255)],
                                          startPoint: .leading, endPoint: .trailing))
                    .frame(height: 1)
                Text("MIZON").font(englishFont(29, weight: .semibold))
                    .tracking(4.35).foregroundStyle(AuthAppearance.brand)
            }

            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { context in
                showcaseScene(height: height, time: context.date)
            }

            HStack(spacing: 6) {
                ForEach(AuthScene.allCases) { item in
                    Button {
                        selectScene(item)
                    } label: {
                        HStack(spacing: 5) {
                            FluentIcon(symbol: item.selectorIcon, size: 16)
                            Text(text(item.key))
                                .font(item == .vpn ? englishFont(11) : authFont(11))
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .foregroundStyle(item.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 9)
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(AuthSceneButtonStyle(color: item.color, selected: item == scene,
                                                     focused: showcaseFocused == item, reduceMotion: reduceMotion))
                    .focused($showcaseFocused, equals: item)
                    .accessibilityIdentifier("showcase.\(item.rawValue)")
                    .accessibilityLabel(text(item.key + "Action"))
                    .accessibilityAddTraits(item == scene ? [.isSelected] : [])
                }
            }
            .environment(\.layoutDirection, isPersian ? .rightToLeft : .leftToRight)
        }
        .onHover { showcaseHovered = $0 }
        .task(id: canRotateShowcase) {
            guard canRotateShowcase else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(6)) }
                catch { return }
                selectScene(scene.next)
            }
        }
    }

    private func selectScene(_ next: AuthScene) {
        guard scene != next else { return }
        previousScene = scene
        showcaseStart = Date()
        scene = next
    }

    private func showcaseScene(height: CGFloat, time: Date) -> some View {
        let elapsed = max(0, time.timeIntervalSince(showcaseStart))
        let outgoing = reduceMotion || elapsed >= 0.45 ? nil : previousScene
        let progress = outgoing == nil ? 1 : Self.showcaseEasing.value(at: elapsed / 0.45)
        let scenes = AuthScene.allCases
        let direction: CGFloat = outgoing.map {
            (scenes.firstIndex(of: scene) ?? 0) > (scenes.firstIndex(of: $0) ?? 0) ? -1 : 1
        } ?? 1
        let caption = elapsed < 0.15 ? (outgoing ?? scene) : scene
        let captionOpacity = outgoing == nil ? 1 : elapsed < 0.15 ? 1 - elapsed / 0.15 :
            min(1, (elapsed - 0.15) / 0.24)

        return VStack(spacing: 14) {
            ZStack {
                if let outgoing {
                    AuthShowcaseArtwork(scene: outgoing, elapsed: 0, moves: false)
                        .scaleEffect(1 - 0.02 * progress)
                        .offset(x: 12 * direction * progress)
                        .opacity(1 - progress)
                }
                AuthShowcaseArtwork(scene: scene, elapsed: elapsed, moves: !reduceMotion)
                    .scaleEffect(0.965 + 0.035 * progress)
                    .offset(x: -18 * direction * (1 - progress))
                    .opacity(progress)
            }
            .scaleEffect(height / 400)
            .frame(width: height, height: height)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text(text(caption.key + "Title")).font(authFont(24, weight: .semibold))
                Text(text(caption.key + "Description")).font(authFont(12)).foregroundStyle(MizonPalette.secondaryText)
            }
            .opacity(captionOpacity)
            .frame(maxWidth: .infinity, minHeight: 106, alignment: .topLeading)
            .environment(\.layoutDirection, isPersian ? .rightToLeft : .leftToRight)
        }
    }

    private static let showcaseEasing = UnitCurve.bezier(
        startControlPoint: UnitPoint(x: 0.2, y: 0.7), endControlPoint: UnitPoint(x: 0.2, y: 1)
    )

    private var canRotateShowcase: Bool {
        scenePhase == .active && !reduceMotion && !showcaseHovered && showcaseFocused == nil
    }
}

#if os(macOS)
private typealias AuthContentType = NSTextContentType
#else
private typealias AuthContentType = UITextContentType
#endif
#endif
