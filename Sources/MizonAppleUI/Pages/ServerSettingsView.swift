import SwiftUI
import MizonAppleCore

public struct ServerSettingsView: View {
    @Bindable private var model: LoginViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mizon.serverAddress") private var savedAddress = BackendConfiguration.defaultAddress
    #if os(macOS)
    @AppStorage(MacMenuBarProfile.preferenceKey) private var showsMenuBarProfile = true
    #endif
    @State private var address: String
    @State private var showsValidation = false
    #if os(macOS) || os(iOS)
    private enum ControllerTarget: Hashable { case close, address, save, menuBarProfile }
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @Environment(\.appearsActive) private var appearsActive
    #endif
    @State private var controllerFocus: ControllerTarget?
    @State private var controllerKeyboard: GamepadKeyboard?
    #endif
    private var localization = AuthLocalization()
    public init(model: LoginViewModel) {
        self.model = model; _address = State(initialValue: model.serverAddress)
    }
    public var body: some View {
        #if os(macOS) || os(iOS)
        Group {
            if let controllerKeyboard {
                AuthGamepadKeyboard(keyboard: controllerKeyboard, value: address,
                                    prompt: text("ServerAddress"), activate: useControllerKey)
                    .frame(minHeight: 310)
            } else {
                settingsForm
            }
        }
        .task(id: controllerActive) {
            if controllerActive { await observeController() }
        }
        #else
        settingsForm
        #endif
    }

    private var settingsForm: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                HStack { FluentIcon(symbol: .networkCheck); Text(text("ServerConnection")) }.font(.title3.weight(.semibold))
                Spacer()
                Button { dismiss() } label: { FluentIcon(symbol: .dismiss) }
                    .buttonStyle(.glass).accessibilityLabel(text("CloseServerSettings"))
                    #if os(macOS) || os(iOS)
                    .overlay { controllerOutline(.close) }
                    #endif
            }
            Text(text("ServerAddress")).font(.subheadline.weight(.medium))
            TextField("https://…", text: $address)
                #if !os(watchOS)
                .textFieldStyle(.roundedBorder)
                #endif
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityIdentifier("server.address")
                #if os(macOS) || os(iOS)
                .overlay { controllerOutline(.address) }
                #endif
            Text(text("ServerAddressHelp"))
                .font(.caption).foregroundStyle(MizonPalette.secondaryText).multilineTextAlignment(.leading)
            if showsValidation {
                Text(text("InvalidServerAddress")).font(.caption).foregroundStyle(MizonPalette.negative)
                    .accessibilityIdentifier("server.error")
            }
            Button(text("Save"), action: save)
            .buttonStyle(.glassProminent).tint(MizonPalette.accent).disabled(model.isLoading)
            #if os(macOS) || os(iOS)
            .keyboardShortcut(.defaultAction)
            .overlay { controllerOutline(.save) }
            #endif
            #if os(macOS)
            Toggle(localization.string("ShowMenuBarProfile", table: "MenuBarProfile"), isOn: $showsMenuBarProfile)
                .onChange(of: showsMenuBarProfile) { _, visible in MacMenuBarProfile.shared.setEnabled(visible) }
                .overlay { controllerOutline(.menuBarProfile) }
            #endif
        }
        .environment(\.layoutDirection, localization.isPersian ? .rightToLeft : .leftToRight)
        #if os(watchOS)
        .padding(12)
        #else
        .padding(28)
        #endif
        #if os(macOS)
        .frame(width: 420)
        #endif
        .foregroundStyle(MizonPalette.ink)
        .background { WindowGlass().ignoresSafeArea() }
        .preferredColorScheme(.dark)
    }

    private func save() {
        guard !model.isLoading else { return }
        do {
            let config = try BackendConfiguration(address: address)
            model.serverAddress = config.baseURL.absoluteString
            savedAddress = model.serverAddress
            model.dismissError()
            dismiss()
        } catch { showsValidation = true }
    }

    #if os(macOS) || os(iOS)
    private var controllerActive: Bool {
        #if os(macOS)
        scenePhase == .active && appearsActive
        #else
        scenePhase == .active
        #endif
    }

    private var controllerTargets: [ControllerTarget] {
        var targets: [ControllerTarget] = [.close, .address]
        if !model.isLoading { targets.append(.save) }
        #if os(macOS)
        targets.append(.menuBarProfile)
        #endif
        return targets
    }

    private func controllerOutline(_ target: ControllerTarget) -> some View {
        RoundedRectangle(cornerRadius: 7)
            .strokeBorder(controllerFocus == target ? MizonPalette.accent : .clear, lineWidth: 2)
            .allowsHitTesting(false)
    }

    private func observeController() async {
        await GamepadControls.observe(scope: { controllerActive ? (controllerKeyboard != nil) : nil },
                                      onReset: { controllerKeyboard = nil }) { action, _ in
            if var keyboard = controllerKeyboard {
                let key = keyboard.key(for: action)
                controllerKeyboard = keyboard
                if let key { useControllerKey(key) }
                return
            }
            switch action {
            case .back: dismiss()
            case .submit: save()
            case .accept:
                switch controllerFocus {
                case .close: dismiss()
                case .address:
                    controllerKeyboard = GamepadKeyboard(allowsPersian: false, masksValue: false,
                                                          persian: false, length: address.count)
                case .save: save()
                case .menuBarProfile:
                    #if os(macOS)
                    showsMenuBarProfile.toggle()
                    #endif
                    break
                case nil: controllerFocus = .address
                }
            case .primary: if !model.isLoading { controllerFocus = .save }
            case .reset: controllerFocus = .address
            default:
                if let step = action.focusStep {
                    controllerFocus = controllerTargets.gamepadTarget(from: controllerFocus, step: step)
                }
            }
        }
    }

    private func useControllerKey(_ key: GamepadKeyboard.Key) {
        guard var keyboard = controllerKeyboard else { return }
        if key == .done || key == .close { controllerKeyboard = nil; return }
        if let value = keyboard.edit(key, value: address, accepts: { $0.utf16.count <= 2_048 }) { address = value }
        controllerKeyboard = keyboard
    }
    #endif

    private func text(_ key: String) -> String { localization.string(key, table: "Settings") }
}
