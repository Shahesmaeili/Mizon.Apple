#if os(watchOS)
import SwiftUI
import MizonAppleCore

struct WatchLoginPage: View {
    @Bindable var model: LoginViewModel
    @State private var request: Task<Void, Never>?
    @State private var settings = false
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                BrandWordmark().scaleEffect(0.8)
                Text("ورود به حساب").font(.headline)
                if model.session != nil {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.cyan)
                    Text("وارد شدی").font(.headline)
                    Button("بازگشت") { request = Task { await model.signOut() } }
                } else {
                    TextField("Email or username", text: $model.identifier).textContentType(.username).disabled(model.isLoading)
                    SecureField("Password", text: $model.password).textContentType(.password).disabled(model.isLoading)
                    if let error = model.error { Text(error.errorDescription ?? "ورود انجام نشد").font(.caption2).foregroundStyle(.red) }
                    Button(model.isLoading ? "در حال ورود…" : "ورود") { request = Task { await model.login() } }
                        .buttonStyle(.borderedProminent).tint(.cyan).disabled(!model.canSubmit)
                    if model.isLoading { Button("لغو") { request?.cancel() } }
                }
                Button { settings = true } label: { Label("اتصال", systemImage: "network") }.font(.caption2).disabled(model.isLoading)
            }.padding(.horizontal, 4)
        }
        .sheet(isPresented: $settings) { ServerSettingsView(model: model) }
        .onDisappear { request?.cancel() }
    }
}
#endif
