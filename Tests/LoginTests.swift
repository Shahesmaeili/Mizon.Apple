import Foundation
import Testing
import MizonAPI
import MizonAPIClient
@testable import MizonAppleCore

private actor FakeAuthentication: AuthenticationService {
    var failure: LoginFailure?
    var calls = 0
    init(failure: LoginFailure? = nil) { self.failure = failure }
    func login(configuration: BackendConfiguration, identifier: String, password: String) async throws -> AuthSession {
        calls += 1
        try await Task.sleep(for: .milliseconds(20))
        if let failure { throw failure }
        return AuthSession(accessToken: "access", refreshToken: "refresh", sessionPublicId: UUID(), clientPublicId: UUID(), identifier: identifier, server: configuration.baseURL)
    }
    func signOut(session: AuthSession) {}
}

@MainActor
struct LoginTests {
    @Test func emailDetectionMatchesWindowsAndPasswordIsUntouched() {
        let email = MizonAuthenticationService.loginRequest(identifier: "  ali+music@example.com \n", password: " secret ")
        #expect(email.emailAddress == "ali+music@example.com")
        #expect(email.username == nil); #expect(email.password == " secret ")
        let username = MizonAuthenticationService.loginRequest(identifier: "  alishah  ", password: "password")
        #expect(username.username == "alishah"); #expect(username.emailAddress == nil)
        #expect(MizonAuthenticationService.loginRequest(identifier: "a@local", password: "p").username == "a@local")
    }
    @Test func rejectsUnsafeOrMalformedServerAddresses() throws {
        for address in ["http://example.com", "https://user:pass@example.com", "https://example.com?token=x", "https://example.com#x", "not a URL", "https://"] {
            #expect(throws: LoginFailure.self) { try BackendConfiguration(address: address) }
        }
        #expect(try BackendConfiguration(address: " https://localhost:5128/api ").baseURL.absoluteString == "https://localhost:5128/api")
    }
    @Test func emptyOrWhitespaceIdentifierCannotSubmit() {
        let model = LoginViewModel(authentication: FakeAuthentication())
        #expect(!model.canSubmit)
        model.identifier = " \n "; model.password = "p"; #expect(!model.canSubmit)
        model.identifier = "ali"; #expect(model.canSubmit)
        model.password = ""; #expect(!model.canSubmit)
    }
    @Test func successClearsPasswordAndSupportsLocalSignOut() async {
        let model = LoginViewModel(authentication: FakeAuthentication())
        model.identifier = "ali"; model.password = "secret"
        await model.login()
        #expect(model.session?.identifier == "ali")
        #expect(model.password.isEmpty); #expect(!model.isLoading); #expect(model.error == nil)
        await model.signOut(); #expect(model.session == nil)
    }
    @Test func failureRestoresControlsAndPreservesServerMessage() async {
        let expected = LoginFailure.api(code: 401, title: "ورود ناموفق", details: "اطلاعات ورود را بررسی کنید.", closeButton: "بستن")
        let model = LoginViewModel(authentication: FakeAuthentication(failure: expected))
        model.identifier = "ali"; model.password = "secret"
        await model.login()
        #expect(model.error == expected); #expect(model.session == nil)
        #expect(model.canSubmit); #expect(model.error?.closeButtonText == "بستن")
        model.dismissError(); #expect(model.error == nil)
    }
    @Test func cancellationAndDoubleSubmission() async {
        let service = FakeAuthentication()
        let model = LoginViewModel(authentication: service)
        model.identifier = "ali"; model.password = "p"
        let task = Task { await model.login() }
        while !model.isLoading { await Task.yield() }
        await model.login()
        task.cancel(); await task.value
        #expect(await service.calls == 1)
        #expect(!model.isLoading); #expect(model.error == nil); #expect(model.session == nil)
    }
}
