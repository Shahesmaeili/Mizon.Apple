#if os(watchOS)
import SwiftUI
import MizonAppleCore

struct WatchLoginPage: View {
    @Bindable var model: LoginViewModel
    let isProfileOnline: Bool
    @State private var request: Task<Void, Never>?
    @State private var settings = false
    @State private var checkedStartup = false
    private let localization = AuthLocalization()
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                BrandWordmark().scaleEffect(0.8)
                Text("ورود به حساب").font(.headline)
                if !checkedStartup {
                    ProgressView()
                } else if model.session != nil {
                    ProfilePresenceBadge(size: 32, isOnline: isProfileOnline) {
                        Circle().fill(MizonPalette.ink.opacity(0.14))
                            .overlay { Image(systemName: "person.fill").font(.system(size: 14)).foregroundStyle(MizonPalette.ink) }
                    }
                    Text("وارد شدی").font(.headline)
                    Text(localization.string(isProfileOnline ? "Online" : "Offline", table: "MenuBarProfile"))
                        .font(.caption2)
                        .foregroundStyle(MizonPalette.secondaryText)
                    Button("بازگشت") { request = Task { await model.signOut() } }.disabled(model.isLoading)
                } else {
                    TextField("Email", text: $model.identifier).textContentType(.username).disabled(model.isLoading)
                    SecureField("Password", text: $model.password).textContentType(.password).disabled(model.isLoading)
                    if let error = model.error {
                        Text(error.errorDescription ?? "ورود انجام نشد").font(.caption2)
                            .foregroundStyle(MizonPalette.negative)
                    }
                    Button(model.isLoading ? "در حال ورود…" : "ورود") { request = Task { await model.login() } }
                        .buttonStyle(.borderedProminent).disabled(!model.canSubmit)
                    if model.isLoading { Button("لغو") { request?.cancel() } }
                }
                Button { settings = true } label: { HStack { FluentIcon(symbol: .networkCheck); Text("اتصال") } }
                    .font(.caption2).disabled(!checkedStartup || model.isLoading)
            }.padding(.horizontal, 4)
        }
        .task {
            guard !checkedStartup else { return }
            _ = try? await model.activeOrRestoredSession()
            if !Task.isCancelled { checkedStartup = true }
        }
        .sheet(isPresented: $settings) { ServerSettingsView(model: model) }
        .onDisappear { request?.cancel() }
    }
}
#endif
