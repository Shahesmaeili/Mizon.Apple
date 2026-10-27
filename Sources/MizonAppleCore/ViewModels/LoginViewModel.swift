import Foundation
import Observation

@Observable @MainActor
public final class LoginViewModel {
    public var identifier = ""
    public var password = ""
    public var serverAddress: String
    public private(set) var isLoading = false
    public private(set) var error: LoginFailure?
    public private(set) var session: AuthSession?
    @ObservationIgnored private let authentication: any AuthenticationService
    public var canSubmit: Bool {
        !isLoading && !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }
    public init(authentication: any AuthenticationService = MizonAuthenticationService(), serverAddress: String = BackendConfiguration.defaultAddress) {
        self.authentication = authentication; self.serverAddress = serverAddress
    }
    public func dismissError() { error = nil }
    public func login() async {
        guard canSubmit else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            let config = try BackendConfiguration(address: serverAddress)
            let result = try await authentication.login(configuration: config, identifier: identifier, password: password)
            try Task.checkCancellation()
            session = result; password = ""
        } catch is CancellationError {
            // Dismissing a view or cancelling a request is not an authentication failure.
        } catch let failure as LoginFailure { error = failure }
        catch { self.error = .api(code: 108, title: "ورود انجام نشد", details: error.localizedDescription, closeButton: nil) }
    }
    public func signOut() async {
        guard let session, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do { try await authentication.signOut(session: session); self.session = nil; password = "" }
        catch let failure as LoginFailure { error = failure }
        catch { self.error = .api(code: 108, title: "خروج انجام نشد", details: error.localizedDescription, closeButton: nil) }
    }
}
