import SwiftUI
import MizonAppleCore
#if os(macOS)
import AppKit
#endif

public struct MizonRootView: View {
    @State private var model: LoginViewModel
    // LoginPage.xaml explicitly sets IsFlipped=True (Side2, registration).
    @State private var isFlipped = true
    @State private var loginTask: Task<Void, Never>?
    @FocusState private var focus: Field?
    private enum Field: Hashable { case email(Bool), password(Bool) }
    public init(model: LoginViewModel) { _model = State(initialValue: model) }
    public var body: some View {
        #if os(watchOS)
        WatchLoginPage(model: model)
        #else
        ZStack {
            LoginBackdrop()
            VStack(spacing: 0) {
                ZStack {
                    if model.session == nil {
                        FlipSide(isFlipped: isFlipped) {
                            card(registration: false)
                        } side2: {
                            card(registration: true)
                        }
                    } else {
                        VStack(spacing: 20) {
                            FluentIcon(symbol: .checkmarkCircle, size: 40)
                            Text("وارد شدی")
                            Button("بازگشت به ورود") { loginTask = Task { await model.signOut() } }.buttonStyle(.glass)
                        }.padding(28).glassEffect(.regular, in: .rect(cornerRadius: 8))
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                bottomAppBar
            }
        }
        .font(WindowsTypography.iranSans(14))
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .alert(model.error?.errorDescription ?? "ورود انجام نشد", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.dismissError() } })) {
            Button(model.error?.closeButtonText ?? "بستن") { model.dismissError() }
        } message: { Text(model.error?.details ?? "") }
        #if os(macOS)
        .onChange(of: focus) { _, field in
            // TextBox_GotFocus on Windows Side2 switches to English input.
            if field == .email(true), let context = NSTextInputContext.current,
               let source = context.keyboardInputSources?.first(where: {
                   $0 == "com.apple.keylayout.ABC" || $0 == "com.apple.keylayout.US"
               }) {
                context.selectedKeyboardInputSource = source
            }
        }
        #endif
        .onDisappear { loginTask?.cancel() }
        #endif
    }
    #if !os(watchOS)
    private func card(registration: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(registration ? "ساخت حساب" : "ورود به حساب")
                    .font(WindowsTypography.iranSans(18).bold()).padding(.horizontal, 8)
                FluentIcon(symbol: .personAccounts, size: 20, rightToLeft: true)
            }.frame(height: 28)
            VStack(spacing: 0) {
                AnimatedBrand().padding(18)
                input(registration: registration, password: false).padding(4)
                input(registration: registration, password: true).padding(4)
                Button(action: submit) {
                    ZStack(alignment: .trailing) {
                        Text("ورود").frame(maxWidth: .infinity)
                        if registration && model.isLoading { ProgressView().controlSize(.small).frame(width: 24, height: 24).padding(.trailing, 8) }
                    }.frame(width: 240, height: 32)
                }
                .buttonStyle(ReferenceButtonStyle()).disabled(!model.canSubmit)
                .accessibilityIdentifier(registration ? "registration.submit" : "login.submit")
                .padding(4)
                Button("حساب ندارم") { focus = nil; isFlipped.toggle() }
                    .buttonStyle(.plain).foregroundStyle(Color(red: 0.65, green: 0.8, blue: 1))
                    .frame(width: 240, height: 32).padding(4).disabled(model.isLoading)
                    .accessibilityIdentifier(registration ? "registration.flip" : "login.flip")
            }
            .environment(\.layoutDirection, .leftToRight)
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(width: 304, height: registration ? 500 : 440)
        .glassEffect(.regular, in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(registration ? "registration.card" : "login.card")
    }
    private func input(registration: Bool, password: Bool) -> some View {
        let focused = focus == (password ? .password(registration) : .email(registration))
        return HStack(spacing: 8) {
            FluentIcon(symbol: .inPrivateAccount).padding(.leading, 6)
            Group {
                if password {
                    SecureField("Password", text: $model.password).textContentType(.password)
                        .focused($focus, equals: .password(registration))
                } else {
                    TextField("Email", text: $model.identifier).textContentType(.username)
                        .focused($focus, equals: .email(registration))
                }
            }
            .onSubmit(submit)
            .textFieldStyle(.plain)
            .accessibilityIdentifier((registration ? "registration." : "login.") + (password ? "password" : "identifier"))
            if focused && !(password ? model.password : model.identifier).isEmpty {
                Button { if password { model.password = "" } else { model.identifier = "" } } label: {
                    FluentIcon(symbol: .dismiss, size: 12).frame(width: 30)
                }.buttonStyle(.plain).accessibilityLabel("پاک کردن")
            }
        }
        .padding(.trailing, 8).frame(width: 240, height: 32)
        .background(.white.opacity(0.035), in: .rect(cornerRadius: 4))
        .overlay { RoundedRectangle(cornerRadius: 4).stroke(focused ? Color(red: 0.65, green: 0.8, blue: 1) : .white.opacity(0.09), lineWidth: 1) }
        .disabled(model.isLoading)
        #if os(iOS)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        #endif
    }
    private var bottomAppBar: some View {
        HStack(spacing: 8) {
            footerButton(.webAsset)
            footerButton(.xboxController)
            Spacer()
        }
        .padding(8).frame(maxWidth: .infinity)
        .background(.white.opacity(0.025))
    }
    private func footerButton(_ symbol: FluentSymbol) -> some View {
        Button {} label: {
            VStack(spacing: 0) {
                FluentIcon(symbol: symbol, size: 24)
                Text("وبسایت").font(WindowsTypography.iranSans(12))
            }.padding(.horizontal, 12).padding(.vertical, 6)
        }.buttonStyle(ReferenceButtonStyle())
    }
    private func submit() {
        guard model.canSubmit else { return }
        focus = nil
        loginTask = Task { await model.login() }
    }
    #endif
}
private struct ReferenceButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(WindowsTypography.iranSans(14))
            .opacity(isEnabled ? 1 : 0.4)
            .glassEffect(.regular.interactive(isEnabled), in: .rect(cornerRadius: 4))
            .brightness(configuration.isPressed ? 0.1 : 0)
    }
}
