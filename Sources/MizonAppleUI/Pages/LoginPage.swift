import SwiftUI
import MizonAppleCore

public struct MizonRootView: View {
    @State private var model: LoginViewModel
    @State private var showSettings = false
    @State private var showRegistration = false
    @State private var revealPassword = false
    @State private var loginTask: Task<Void, Never>?
    @FocusState private var focus: Field?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private enum Field { case identifier, password }
    public init(model: LoginViewModel) { _model = State(initialValue: model) }
    public var body: some View {
        #if os(watchOS)
        WatchLoginPage(model: model)
        #else
        GeometryReader { geometry in
            ZStack {
                LoginBackdrop()
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 12)
                    ScrollView {
                        VStack(spacing: 22) {
                            if model.session == nil { loginCard }
                            else { successCard }
                            HStack(spacing: 7) {
                                Image(systemName: "waveform").font(.system(size: 11))
                                Text("هر صدا، یک جهان.").font(.system(size: 12, weight: .medium))
                            }.foregroundStyle(.white.opacity(0.4))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 24).padding(.vertical, 8)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(maxHeight: geometry.size.height > 800 ? 680 : .infinity)
                    Spacer(minLength: 12)
                    footer.padding(.bottom, 20)
                }
                .padding(.top, 22)
            }
            .foregroundStyle(.white)
            .sheet(isPresented: $showSettings) { ServerSettingsView(model: model) }
            .sheet(isPresented: $showRegistration) { registrationInformation }
            .onDisappear { loginTask?.cancel() }
        }
        .preferredColorScheme(.dark)
        #endif
    }
    #if !os(watchOS)
    private var topBar: some View {
        HStack {
            BrandWordmark()
            Spacer()
            Button { showSettings = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 18, height: 18) }
                .buttonStyle(.glass).controlSize(.large).help("تنظیمات اتصال")
                .accessibilityLabel("تنظیمات اتصال").accessibilityIdentifier("login.settings")
                .disabled(model.isLoading)
        }.padding(.horizontal, 32)
    }
    private var loginCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Spacer()
                Text("ورود به حساب").font(.system(size: 13, weight: .semibold))
                Image(systemName: "person.crop.circle").font(.system(size: 17, weight: .light)).foregroundStyle(.cyan.opacity(0.9))
            }
            .foregroundStyle(.white.opacity(0.72))
            AnimatedBrand().padding(.top, 10)
            Text("خوش برگشتی").font(.system(size: 30, weight: .bold)).padding(.top, 4)
            Text("دنیای موسیقی‌ات منتظر توست.")
                .font(.system(size: 13)).foregroundStyle(.white.opacity(0.54)).padding(.top, 9).padding(.bottom, 30)
            if let error = model.error { errorMessage(error).padding(.bottom, 18) }
            fields
            Button(action: submit) {
                HStack(spacing: 9) {
                    if model.isLoading { ProgressView().controlSize(.small) }
                    Text(model.isLoading ? "در حال ورود…" : "ورود").font(.system(size: 15, weight: .semibold))
                    if !model.isLoading { Image(systemName: "arrow.left").font(.system(size: 13, weight: .semibold)) }
                }
                .frame(maxWidth: .infinity).frame(height: 36)
            }
            .buttonStyle(.glassProminent).controlSize(.large).tint(.cyan)
            .disabled(!model.canSubmit).keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("login.submit").padding(.top, 20)
            if model.isLoading {
                Button("لغو") { loginTask?.cancel() }.buttonStyle(.plain).font(.caption)
                    .foregroundStyle(.secondary).padding(.top, 12)
            }
            Rectangle().fill(.white.opacity(0.09)).frame(height: 1).padding(.vertical, 24)
            HStack(spacing: 7) {
                Button("حساب ندارم") { showRegistration = true }.buttonStyle(.plain).foregroundStyle(.cyan).fontWeight(.medium)
                    .accessibilityIdentifier("login.registration").disabled(model.isLoading)
                Text("هنوز عضو میزون نیستی؟").foregroundStyle(.white.opacity(0.48))
            }.font(.system(size: 12))
        }
        .padding(32)
        .frame(maxWidth: 420)
        .background {
            if reduceTransparency { RoundedRectangle(cornerRadius: 30).fill(Color(red: 0.065, green: 0.08, blue: 0.12)) }
        }
        .glassEffect(reduceTransparency ? .identity : .regular, in: .rect(cornerRadius: 30))
        .overlay { RoundedRectangle(cornerRadius: 30).stroke(LinearGradient(colors: [.white.opacity(0.19), .white.opacity(0.025), .cyan.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1).allowsHitTesting(false) }
        .shadow(color: .black.opacity(0.24), radius: 40, y: 20)
    }
    private var fields: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Text("ایمیل یا نام کاربری").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.64))
            HStack(spacing: 11) {
                Image(systemName: "at").foregroundStyle(.white.opacity(0.4)).frame(width: 17)
                TextField("Email or username", text: $model.identifier)
                    .textContentType(.username).focused($focus, equals: .identifier)
                    .accessibilityLabel("ایمیل یا نام کاربری").accessibilityIdentifier("login.identifier")
                    .onSubmit { focus = .password }
            }
            .modifier(InputSurface(isFocused: focus == .identifier))
            .environment(\.layoutDirection, .leftToRight)
            Text("رمز عبور").font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.64)).padding(.top, 9)
            HStack(spacing: 11) {
                Image(systemName: "lock").foregroundStyle(.white.opacity(0.4)).frame(width: 17)
                Group {
                    if revealPassword { TextField("Password", text: $model.password) }
                    else { SecureField("Password", text: $model.password) }
                }
                .textContentType(.password).focused($focus, equals: .password)
                .accessibilityLabel("رمز عبور").accessibilityIdentifier("login.password")
                .onSubmit(submit)
                Button {
                    revealPassword.toggle(); focus = .password
                } label: { Image(systemName: revealPassword ? "eye.slash" : "eye").font(.system(size: 13)).foregroundStyle(.white.opacity(0.45)) }
                    .buttonStyle(.plain).help(revealPassword ? "پنهان‌کردن رمز عبور" : "نمایش رمز عبور")
                    .accessibilityLabel(revealPassword ? "پنهان‌کردن رمز عبور" : "نمایش رمز عبور")
                    .accessibilityIdentifier("login.revealPassword")
            }
            .modifier(InputSurface(isFocused: focus == .password))
            .environment(\.layoutDirection, .leftToRight)
        }
        .textFieldStyle(.plain).font(.system(size: 14))
        .disabled(model.isLoading)
        #if os(iOS)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        #endif
    }
    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "lock.shield").font(.system(size: 10))
            Text("نشست شما به‌صورت امن روی این دستگاه نگهداری می‌شود.").font(.system(size: 10))
        }
        .foregroundStyle(.white.opacity(0.3))
        .padding(.horizontal, 24)
    }
    private var successCard: some View {
        VStack(spacing: 22) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(.cyan)
            Text("وارد شدی").font(.system(size: 28, weight: .bold))
            Text(model.session?.identifier ?? "").font(.body).foregroundStyle(.secondary).textSelection(.enabled)
            Text("ورود با موفقیت انجام شد. نشست شما به‌صورت امن روی این دستگاه ذخیره شد.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("بازگشت به ورود") { loginTask = Task { await model.signOut() } }.buttonStyle(.glass).disabled(model.isLoading)
        }
        .padding(36).frame(maxWidth: 420)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .accessibilityIdentifier("login.success")
    }
    private func errorMessage(_ error: LoginFailure) -> some View {
        VStack(alignment: .trailing, spacing: 7) {
            HStack(alignment: .top) {
                Button { model.dismissError() } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain).accessibilityLabel(error.closeButtonText)
                Spacer()
                Text(error.errorDescription ?? "ورود انجام نشد").font(.system(size: 12, weight: .semibold))
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red.opacity(0.85))
            }
            if !error.details.isEmpty { Text(error.details).font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.trailing) }
        }
        .padding(13).frame(maxWidth: .infinity, alignment: .trailing)
        .background(.red.opacity(0.07), in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.red.opacity(0.18), lineWidth: 1) }
        .accessibilityIdentifier("login.error")
    }
    private var registrationInformation: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.badge.plus").font(.largeTitle).foregroundStyle(.cyan)
            Text("ساخت حساب").font(.title2.weight(.semibold))
            Text("ساخت حساب هنوز در نسخهٔ مک در دسترس نیست. برای ورود از حساب فعلی میزون استفاده کن.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("متوجه شدم") { showRegistration = false }.buttonStyle(.glassProminent).tint(.cyan)
        }
        .padding(32).frame(maxWidth: 400).preferredColorScheme(.dark)
    }
    private func submit() {
        guard model.canSubmit else { return }
        focus = nil
        loginTask = Task { await model.login() }
    }
    #endif
}

private struct InputSurface: ViewModifier {
    let isFocused: Bool
    func body(content: Content) -> some View {
        content.padding(.horizontal, 14).frame(height: 48)
            .background(.white.opacity(0.035), in: .rect(cornerRadius: 13))
            .overlay { RoundedRectangle(cornerRadius: 13).stroke(isFocused ? .cyan.opacity(0.65) : .white.opacity(0.1), lineWidth: 1) }
    }
}
