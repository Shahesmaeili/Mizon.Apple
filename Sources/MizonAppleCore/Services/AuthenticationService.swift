import Foundation
import MizonAPI
import MizonAPIClient

public protocol AuthenticationService: Sendable {
    func login(configuration: BackendConfiguration, identifier: String, password: String) async throws -> AuthSession
    func signOut(session: AuthSession) async throws
}

public actor MizonAuthenticationService: AuthenticationService {
    private let api: MizonApi
    private let store: any SessionStore
    private let installationID: String
    public init(api: MizonApi = MizonApi(), store: any SessionStore = KeychainSessionStore(), installationID: String = UUID().uuidString) {
        self.api = api; self.store = store; self.installationID = installationID
    }
    /// This matches LoginPageViewModel.IsEmail in the Windows reference.
    public nonisolated static func loginRequest(identifier: String, password: String) -> LoginRequest {
        let value = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let isEmail = value.range(of: #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#, options: .regularExpression) != nil
        return LoginRequest(username: isEmail ? nil : value, emailAddress: isEmail ? value : nil, password: password)
    }
    public func login(configuration: BackendConfiguration, identifier: String, password: String) async throws -> AuthSession {
        try Task.checkCancellation()
        let os = ProcessInfo.processInfo.operatingSystemVersion
        #if os(macOS)
        let model = "Mac"
        #elseif os(watchOS)
        let model = "Apple Watch"
        #else
        let model = "iPhone or iPad"
        #endif
        // The version ID is the reference backend contract ID, not an App Store version.
        // Register an Apple-specific version with the backend before production rollout.
        await api.setDeviceInformation(osVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)", deviceIdentifier: installationID,
            deviceModel: model, deviceName: model, deviceUsername: "",
            platformVersion: UUID(uuidString: "0195dd3c-9a3e-7c4a-8c6f-2e9c0f6b1a72")!)
        let response = await api.sendRequest(LoginOperation(Self.loginRequest(identifier: identifier, password: password), endpoints: Endpoints(baseURL: configuration.baseURL)))
        try Task.checkCancellation()
        if let error = response.error {
            if error.code == 105 { throw CancellationError() }
            throw LoginFailure.api(code: error.code, title: error.title, details: error.details, closeButton: error.closeButtonText)
        }
        guard let content = response.content, !content.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LoginFailure.invalidResponse
        }
        let session = AuthSession(accessToken: content.accessToken, refreshToken: content.refreshToken,
            sessionPublicId: content.sessionPublicId, clientPublicId: content.clientPublicId,
            identifier: identifier.trimmingCharacters(in: .whitespacesAndNewlines), server: configuration.baseURL)
        do { try await store.save(session) }
        catch { await api.clearToken(); throw error }
        return session
    }
    public func signOut(session: AuthSession) async throws {
        try await store.remove(server: session.server)
        await api.clearToken()
    }
}
