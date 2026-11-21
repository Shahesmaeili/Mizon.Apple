import CoreGraphics
import Foundation
import Testing
import MizonAppleCore

private actor WelcomeStub: WelcomeService {
    var failure: WelcomeFailure?
    var accountRequests = 0
    var avatarRequests = 0

    init(failure: WelcomeFailure? = nil) { self.failure = failure }

    func recover() { failure = nil }

    func account(for session: AuthSession) async throws -> WelcomeAccount {
        accountRequests += 1
        if let failure { throw failure }
        return WelcomeAccount(displayName: "Test", avatarID: UUID())
    }

    func avatar(for mediaID: UUID, session: AuthSession) async throws -> CGImage? {
        avatarRequests += 1
        throw WelcomeFailure.accountUnavailable
    }
}

@MainActor
struct WelcomeTests {
    private var session: AuthSession {
        AuthSession(accessToken: "fixture", refreshToken: "fixture", sessionPublicId: UUID(),
                    clientPublicId: UUID(), identifier: "test", server: URL(string: "https://example.com")!)
    }

    @Test func absentSessionGoesStraightToSignIn() async {
        let service = WelcomeStub()
        let model = WelcomeViewModel(service: service)
        guard case .login? = await model.prepare(session: { nil }) else {
            Issue.record("Expected sign-in route")
            return
        }
        #expect(await service.accountRequests == 0)
        #expect(!model.isBusy)
    }

    @Test func retryOpensHomeEvenWhenAvatarCannotLoad() async {
        let service = WelcomeStub(failure: .accountUnavailable)
        let model = WelcomeViewModel(service: service)
        let active = session
        #expect(await model.prepare(session: { active }) == nil)
        #expect(model.stage == .connectionError)
        #expect(!model.isBusy)

        await service.recover()
        var readySessions: [UUID] = []
        guard case .home(let accepted)? = await model.prepare(onAccount: { session, account in
            #expect(model.stage == .profile)
            #expect(account.displayName == "Test")
            readySessions.append(session.sessionPublicId)
        }, session: { active }) else {
            Issue.record("Expected home with the current session")
            return
        }
        #expect(accepted == active)
        #expect(readySessions == [active.sessionPublicId])
        #expect(model.stage == .ready)
        #expect(model.account?.displayName == "Test")
        #expect(model.avatar == nil)
        #expect(await service.accountRequests == 2)
        #expect(await service.avatarRequests == 1)
    }

    @Test func expiredSessionGoesBackToSignIn() async {
        let model = WelcomeViewModel(service: WelcomeStub(failure: .sessionExpired))
        guard case .login? = await model.prepare(session: { session }) else {
            Issue.record("Expected sign-in for an expired token")
            return
        }
        #expect(!model.isBusy)
        #expect(model.account == nil)
    }

    @Test func cancellationDoesNotShowAConnectionError() async {
        let service = WelcomeStub()
        let model = WelcomeViewModel(service: service)
        let active = session
        let task = Task {
            await model.prepare {
                try await Task.sleep(for: .seconds(30))
                return active
            }
        }
        while !model.isBusy { await Task.yield() }
        task.cancel()
        #expect(await task.value == nil)
        #expect(!model.isBusy)
        #expect(model.stage != .connectionError)
        #expect(await service.accountRequests == 0)
    }
}
