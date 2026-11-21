import Foundation
import Testing
import MizonAPI
@testable import MizonAppleCore

private actor MemorySessionStore: SessionStore {
    var saved: AuthSession?
    let fails: Bool
    init(fails: Bool = false) { self.fails = fails }
    func save(_ session: AuthSession) throws {
        if fails { throw LoginFailure.storage(-1) }
        saved = session
    }
    func load(server: URL) -> AuthSession? {
        saved?.server == server ? saved : nil
    }
    func remove(server: URL) { saved = nil }
}
private final class AuthProtocol: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var response = ""
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var lastRequest: URLRequest?
    static func configure(_ text: String, code: Int = 200) {
        lock.lock(); defer { lock.unlock() }
        response = text; status = code; lastRequest = nil
    }
    static func capturedRequest() -> URLRequest? { lock.lock(); defer { lock.unlock() }; return lastRequest }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); let text = Self.response; let code = Self.status; Self.lastRequest = request; Self.lock.unlock()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@Suite(.serialized)
struct AuthenticationIntegrationTests {
    private let validResponse = #"{"content":{"accessToken":"test-access","refreshToken":"test-refresh","sessionPublicId":"12345678-1234-1234-1234-123456789abc","clientPublicId":"22345678-1234-1234-1234-123456789abc"}}"#
    private func network() -> URLSession {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [AuthProtocol.self]
        return URLSession(configuration: config)
    }
    @Test func usesRealSDKLoginOperationAndStoresReturnedSession() async throws {
        AuthProtocol.configure(validResponse)
        let http = network(); defer { http.invalidateAndCancel() }
        let api = MizonApi(session: http)
        let store = MemorySessionStore()
        let service = MizonAuthenticationService(api: api, store: store, installationID: "installation-test")
        let session = try await service.login(configuration: BackendConfiguration(address: "https://example.com/api"), identifier: " ali@example.com ", password: "test-only")
        #expect(session.identifier == "ali@example.com")
        #expect(await store.saved == session)
        #expect(await api.getToken() == "test-access")
        let request = AuthProtocol.capturedRequest()
        #expect(request?.url?.path == "/api/Clients/Login")
        #expect(request?.httpMethod == "POST")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request?.value(forHTTPHeaderField: "Content-Encoding") == "gzip")
        #expect(request?.value(forHTTPHeaderField: "Mizon-Device-Identifier") == "installation-test")
        try await service.signOut(session: session)
        #expect(await api.getToken() == nil); #expect(await store.saved == nil)
    }
    @Test func registrationPostsToTheServerAndStartsTheSession() async throws {
        AuthProtocol.configure(validResponse)
        let http = network()
        defer { http.invalidateAndCancel() }
        let api = MizonApi(session: http)
        let store = MemorySessionStore()
        let service = MizonAuthenticationService(api: api, store: store, installationID: "apple-test")
        let session = try await service.register(
            configuration: BackendConfiguration(address: "https://example.com/api"),
            registration: registration())
        #expect(session.identifier == "mizon.user")
        #expect(await store.saved == session)
        #expect(await api.getToken() == session.accessToken)
        let request = try #require(AuthProtocol.capturedRequest())
        #expect(request.url?.path == "/api/Clients/Register")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "Content-Encoding") == "gzip")
        #expect(request.value(forHTTPHeaderField: "Mizon-Device-Username")?.isEmpty == false)
    }

    @Test func restoresTheServerScopedSessionAndChecksTheRealMeOperation() async throws {
        let http = network()
        defer { http.invalidateAndCancel() }
        let api = MizonApi(session: http)
        let store = MemorySessionStore()
        let config = try BackendConfiguration(address: "https://example.com/api")
        let session = AuthSession(accessToken: "test-access", refreshToken: "test-refresh",
                                  sessionPublicId: UUID(), clientPublicId: UUID(), identifier: "ali", server: config.baseURL)
        try await store.save(session)
        let auth = MizonAuthenticationService(api: api, store: store, installationID: "welcome-test")
        let otherServer = try BackendConfiguration(address: "https://other.example.com")
        #expect(try await auth.restore(configuration: otherServer) == nil)
        let restored = try #require(try await auth.restore(configuration: config))
        #expect(restored == session)

        AuthProtocol.configure(#"{"content":{"firstName":"Ali","lastName":"Test","nickName":"  Mizon User  "}}"#)
        let service = MizonWelcomeService(api: api)
        let account = try await service.account(for: restored)
        #expect(account.displayName == "Mizon User")
        #expect(account.avatarID == nil)
        let request = try #require(AuthProtocol.capturedRequest())
        #expect(request.url?.path == "/api/Clients/Me")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-access")
        #expect(request.value(forHTTPHeaderField: "Mizon-Device-Identifier") == "welcome-test")

        AuthProtocol.configure(#"{"error":{"code":20000,"title":"Expired"}}"#)
        await #expect(throws: WelcomeFailure.sessionExpired) { try await service.account(for: restored) }
    }

    @Test func authenticationIdentifiersUseTheWindowsASCIIAllowList() {
        #expect(AuthIdentifierInput.isAllowed("ALi.09_dev", allowsEmail: false))
        #expect(AuthIdentifierInput.isAllowed("ali+dev%tag@example-domain.com", allowsEmail: true))
        #expect(!AuthIdentifierInput.isAllowed("ali+dev@example.com", allowsEmail: false))
        for value in ["علی", "ali 1", "ali۱", "ali🙂", "café", "ali\n", "ali!"] {
            #expect(!AuthIdentifierInput.isAllowed(value, allowsEmail: true))
        }
    }

    @Test func musicHomeLoadsTheWindowsHeroThroughTheSharedSDK() async throws {
        let http = network()
        defer { http.invalidateAndCancel() }
        let api = MizonApi(session: http)
        try await api.setToken("fixture-access")
        let server = try #require(URL(string: "https://example.com/api"))
        let session = AuthSession(accessToken: "fixture-access", refreshToken: "fixture-refresh", sessionPublicId: UUID(),
                                  clientPublicId: UUID(), identifier: "fixture", server: server)
        AuthProtocol.configure(#"{"content":{"items":[{"publicId":"12345678-1234-1234-1234-123456789abc","title":"Fixture feature","contentTypeCode":"video"}]}}"#)
        let service = MusicHomeService(api: api)
        let content = try await service.load(.features, session: session)
        guard case .features(let items) = content else { Issue.record("Expected the featured widget"); return }
        #expect(items.first?.title == "Fixture feature")
        #expect(items.first?.contentTypeCode == "video")
        let request = try #require(AuthProtocol.capturedRequest())
        #expect(request.url?.path == "/api/Musics/MusicFeatures")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-access")
        #expect(request.assumesHTTP3Capable)
        AuthProtocol.configure(#"{"error":{"code":404,"title":"Unavailable"}}"#, code: 404)
        await #expect(throws: LoginFailure.invalidResponse) { try await service.load(.library, session: session) }
    }

    @Test func registrationChecksConfirmationAndIdentifierRules() {
        var value = registration()
        value.username = "mizon.user"
        #expect(value.validationError(confirmation: value.password) == nil)
        #expect(value.validationError(confirmation: "secret-test") == "AuthPasswordMismatchError")
        value.username = "نام"
        #expect(value.validationError(confirmation: value.password) == "AuthInvalidUsernameError")
        value.username = "mizon.user"
        value.emailAddress = "a..b@example.com"
        #expect(value.validationError(confirmation: value.password) == "AuthInvalidEmailError")
    }

    private func registration() -> Registration {
        var value = Registration()
        value.firstName = "Ali"
        value.lastName = "Test"
        value.username = " mizon.user "
        value.emailAddress = "test@example.com"
        value.password = " secret-test "
        return value
    }

    @Test func failedSecureStorageClearsTheSDKToken() async throws {
        AuthProtocol.configure(validResponse)
        let http = network(); defer { http.invalidateAndCancel() }
        let api = MizonApi(session: http)
        let service = MizonAuthenticationService(api: api, store: MemorySessionStore(fails: true))
        do {
            _ = try await service.login(configuration: BackendConfiguration(address: "https://example.com"), identifier: "ali", password: "test-only")
            Issue.record("Expected storage failure")
        } catch { #expect(error as? LoginFailure == .storage(-1)) }
        #expect(await api.getToken() == nil)
    }
    @Test func backendErrorsPreserveTheirMessageAndDoNotStoreSession() async throws {
        AuthProtocol.configure(#"{"error":{"code":42,"title":"ورود ناموفق","details":"اطلاعات ورود را بررسی کنید.","closeButtonText":"بستن"}}"#)
        let http = network(); defer { http.invalidateAndCancel() }
        let store = MemorySessionStore()
        let service = MizonAuthenticationService(api: MizonApi(session: http), store: store)
        do {
            _ = try await service.login(configuration: BackendConfiguration(address: "https://example.com"), identifier: "ali", password: "test-only")
            Issue.record("Expected API failure")
        } catch let error as LoginFailure { #expect(error.errorDescription == "ورود ناموفق"); #expect(error.closeButtonText == "بستن") }
        #expect(await store.saved == nil)
    }
    @Test func missingSuccessContentIsRejected() async throws {
        AuthProtocol.configure(#"{"content":null,"error":null}"#)
        let http = network(); defer { http.invalidateAndCancel() }
        let service = MizonAuthenticationService(api: MizonApi(session: http), store: MemorySessionStore())
        do {
            _ = try await service.login(configuration: BackendConfiguration(address: "https://example.com"), identifier: "ali", password: "test-only")
            Issue.record("Expected incomplete response failure")
        } catch { #expect(error as? LoginFailure == .invalidResponse) }
    }
}
