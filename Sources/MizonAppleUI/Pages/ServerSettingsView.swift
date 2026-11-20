import SwiftUI
import MizonAppleCore

public struct ServerSettingsView: View {
    @Bindable private var model: LoginViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mizon.serverAddress") private var savedAddress = BackendConfiguration.defaultAddress
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
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            if showsValidation {
                Text(text("InvalidServerAddress")).font(.caption).foregroundStyle(.red).accessibilityIdentifier("server.error")
            }
            Button(text("Save")) {
                do {
                    let config = try BackendConfiguration(address: address)
                    model.serverAddress = config.baseURL.absoluteString
                    savedAddress = model.serverAddress
                    model.dismissError(); dismiss()
                } catch { showsValidation = true }
            }
            .buttonStyle(.glassProminent).tint(.cyan).disabled(model.isLoading)
            #if !os(watchOS)
            .keyboardShortcut(.defaultAction)
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
        .preferredColorScheme(.dark)
    }

    private func text(_ key: String) -> String { localization.string(key, table: "Settings") }
}
