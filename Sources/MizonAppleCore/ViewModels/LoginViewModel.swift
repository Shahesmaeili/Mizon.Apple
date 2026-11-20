import Foundation
import Observation
import MizonAPI

@Observable @MainActor
public final class LoginViewModel {
    public var identifier = "" { didSet { if identifier != oldValue { dismissError() } } }
    public var password = "" { didSet { if password != oldValue { dismissError() } } }
    public var registration = Registration() { didSet { if registration != oldValue { dismissError() } } }
    public var confirmation = "" { didSet { if confirmation != oldValue { dismissError() } } }
    public private(set) var validationKey: String?
    public var canRegister: Bool {
        !isLoading && [registration.firstName, registration.lastName, registration.username, registration.emailAddress]
            .allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && !registration.password.isEmpty && !confirmation.isEmpty
    }

    public var serverAddress: String
    public private(set) var isLoading = false
    public private(set) var error: LoginFailure?
    public private(set) var session: AuthSession?
    @ObservationIgnored private let authentication: any AuthenticationService
    @ObservationIgnored public let welcomeService: any WelcomeService
    public var canSubmit: Bool {
        !isLoading && !identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }
    public convenience init(serverAddress: String = BackendConfiguration.defaultAddress) {
        let api = MizonApi()
        self.init(authentication: MizonAuthenticationService(api: api),
                  welcomeService: MizonWelcomeService(api: api), serverAddress: serverAddress)
    }

    public init(authentication: any AuthenticationService, welcomeService: any WelcomeService,
                serverAddress: String = BackendConfiguration.defaultAddress) {
        self.authentication = authentication
        self.welcomeService = welcomeService
        self.serverAddress = serverAddress
    }

    public func activeOrRestoredSession() async throws -> AuthSession? {
        if let session { return session }
        guard let configuration = try? BackendConfiguration(address: serverAddress) else { return nil }
        let restored = try await authentication.restore(configuration: configuration)
        try Task.checkCancellation()
        session = restored
        return restored
    }
    public func dismissError() { error = nil; validationKey = nil }
    public func clearSensitiveInputs() {
        password = ""
        registration.password = ""
        confirmation = ""
    }

    public func register() async {
        guard canRegister else { return }
        dismissError()
        validationKey = registration.validationError(confirmation: confirmation)
        guard validationKey == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let config = try BackendConfiguration(address: serverAddress)
            let result = try await authentication.register(configuration: config, registration: registration)
            try Task.checkCancellation()
            session = result
            clearSensitiveInputs()
        } catch is CancellationError {
            clearSensitiveInputs()
        } catch let failure as LoginFailure {
            error = failure
        } catch {
            self.error = .invalidResponse
        }
    }
    public func login() async {
        guard canSubmit else { return }
        dismissError()
        guard AuthIdentifierInput.isAllowed(identifier, allowsEmail: true) else {
            validationKey = "AuthInvalidIdentifierError"
            return
        }
        isLoading = true
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
        dismissError()
        isLoading = true
        defer { isLoading = false }
        do { try await authentication.signOut(session: session); self.session = nil; password = "" }
        catch let failure as LoginFailure { error = failure }
        catch { self.error = .api(code: 108, title: "خروج انجام نشد", details: error.localizedDescription, closeButton: nil) }
    }
}
