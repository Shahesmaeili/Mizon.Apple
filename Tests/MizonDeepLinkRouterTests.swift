#if os(macOS) || os(iOS)
import Foundation
import MizonAppleCore
import Testing
@testable import MizonAppleUI

@MainActor
struct MizonDeepLinkRouterTests {
    @Test func replacesThePreviousRequestAndIgnoresItsLateCompletion() async throws {
        let router = MizonDeepLinkRouter()
        let oldID = UUID()
        let latestID = UUID()
        let oldCaller = Task { await router.result(for: "mizon://music", requestID: oldID) }
        let oldRequest = try await requirePending(router)
        router.dispatch(oldRequest, sessionID: UUID())
        let oldNavigation = try #require(router.authorized)

        let latestCaller = Task { await router.result(for: "mizon://playlists", requestID: latestID) }
        let latest = try await requirePending(router)
        #expect(await oldCaller.value.code == "superseded")
        router.complete(oldNavigation, stage: .opened)
        #expect(router.pending == latest)
        router.dispatch(latest, sessionID: UUID())
        let navigation = try #require(router.authorized)
        router.complete(navigation, stage: .completed)

        let receipt = await latestCaller.value
        #expect(receipt.requestID == latestID)
        #expect(receipt.data?.destination == "playlists")
        #expect(receipt.data?.completionStage == .completed)
        #expect(router.authorized == nil)
    }

    @Test func anInvalidLinkDoesNotClearAnOrdinaryLinkWaitingForSignIn() async throws {
        let router = MizonDeepLinkRouter()
        #expect(router.open(try #require(URL(string: "mizon://music"))))
        let waiting = try #require(router.pending)
        #expect(!waiting.expectsResult)
        let invalid = await router.result(for: "mizon://welcome")
        #expect(invalid.code == "invalid_uri")
        let unsupported = await router.result(for: "mizon://music", version: 2)
        #expect(unsupported.code == "unsupported_version")
        #expect(router.pending == waiting)
    }

    @Test func deadlineClearsARequestThatNeverReachesItsDestination() async {
        let router = MizonDeepLinkRouter(timeout: .milliseconds(25))
        let result = await router.result(for: "mizon://activities")
        #expect(result.code == "timed_out")
        #expect(router.pending == nil)
        #expect(router.authorized == nil)
    }

    @Test func foregroundCancellationDoesNotLeaveAuthorizedNavigation() async throws {
        let router = MizonDeepLinkRouter()
        let caller = Task { await router.result(for: "mizon://home") }
        let waiting = try await requirePending(router)
        router.dispatch(waiting, sessionID: UUID())
        caller.cancel()
        #expect(await caller.value.code == "cancelled")
        #expect(router.authorized == nil)
    }

    private func requirePending(_ router: MizonDeepLinkRouter) async throws -> MizonDeepLinkRouter.Request {
        for _ in 0..<100 {
            if let waiting = router.pending { return waiting }
            try await Task.sleep(for: .milliseconds(2))
        }
        return try #require(router.pending)
    }
}
#endif
