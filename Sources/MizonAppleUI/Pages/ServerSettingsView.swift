import SwiftUI
import MizonAppleCore

public struct ServerSettingsView: View {
    @Bindable private var model: LoginViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mizon.serverAddress") private var savedAddress = BackendConfiguration.defaultAddress
    @State private var address: String
    @State private var validation: String?
    public init(model: LoginViewModel) {
        self.model = model; _address = State(initialValue: model.serverAddress)
    }
    public var body: some View {
        VStack(alignment: .trailing, spacing: 20) {
            HStack {
                Button { dismiss() } label: { FluentIcon(symbol: .dismiss) }.buttonStyle(.glass).accessibilityLabel("بستن تنظیمات")
                Spacer()
                HStack { FluentIcon(symbol: .networkCheck); Text("اتصال به میزون") }.font(.title3.weight(.semibold))
            }
            Text("آدرس سرور").font(.subheadline.weight(.medium))
            TextField("https://…", text: $address)
                #if !os(watchOS)
                .textFieldStyle(.roundedBorder)
                #endif
                .environment(\.layoutDirection, .leftToRight)
                .accessibilityIdentifier("server.address")
            Text("آدرس HTTPS سرویس میزون را وارد کنید. روی آیفون و ساعت باید از آدرسی استفاده کنید که از آن دستگاه قابل دسترسی باشد.")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            if let validation { Text(validation).font(.caption).foregroundStyle(.red).accessibilityIdentifier("server.error") }
            Button("ذخیره") {
                do {
                    let config = try BackendConfiguration(address: address)
                    model.serverAddress = config.baseURL.absoluteString
                    savedAddress = model.serverAddress
                    model.dismissError(); dismiss()
                } catch { validation = "یک آدرس HTTPS معتبر وارد کنید." }
            }
            .buttonStyle(.glassProminent).tint(.cyan).disabled(model.isLoading)
            #if !os(watchOS)
            .keyboardShortcut(.defaultAction)
            #endif
        }
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
}
