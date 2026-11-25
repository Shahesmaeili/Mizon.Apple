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
    private var localization = AuthLocalization()
    public init(model: LoginViewModel) {
        self.model = model; _address = State(initialValue: model.serverAddress)
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                HStack { FluentIcon(symbol: .networkCheck); Text(text("ServerConnection")) }.font(.title3.weight(.semibold))
                Spacer()
                Button { dismiss() } label: { FluentIcon(symbol: .dismiss) }
                    .buttonStyle(.glass).accessibilityLabel(text("CloseServerSettings"))
            }
            Text(text("ServerAddress")).font(.subheadline.weight(.medium))
            TextField("https://…", text: $address)
                #if !os(watchOS)
                .textFieldStyle(.roundedBorder)
                #endif
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityIdentifier("server.address")
            Text(text("ServerAddressHelp"))
                .font(.caption).foregroundStyle(MizonPalette.secondaryText).multilineTextAlignment(.leading)
            if showsValidation {
                Text(text("InvalidServerAddress")).font(.caption).foregroundStyle(MizonPalette.negative)
                    .accessibilityIdentifier("server.error")
            }
            Button(text("Save")) {
                do {
                    let config = try BackendConfiguration(address: address)
                    model.serverAddress = config.baseURL.absoluteString
                    savedAddress = model.serverAddress
                    model.dismissError(); dismiss()
                } catch { showsValidation = true }
            }
            .buttonStyle(.glassProminent).tint(MizonPalette.accent).disabled(model.isLoading)
            #if !os(watchOS)
            .keyboardShortcut(.defaultAction)
            #endif
            #if os(macOS)
            Toggle(localization.string("ShowMenuBarProfile", table: "MenuBarProfile"), isOn: $showsMenuBarProfile)
                .onChange(of: showsMenuBarProfile) { _, visible in MacMenuBarProfile.shared.setEnabled(visible) }
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

    private func text(_ key: String) -> String { localization.string(key, table: "Settings") }
}
