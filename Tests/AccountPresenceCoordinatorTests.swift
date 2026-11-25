#if os(macOS) || os(iOS)
import Foundation
import MizonAPI
import Testing
@testable import MizonAppleCore

struct AccountPresenceCoordinatorTests {
    @MainActor @Test func activeWindowRequiresConfirmationAndDisconnectClearsPresence() async throws {
        let account = UUID()
        let socket = PresenceTransportFixture(reportedAccount: account)
        var changes: [Bool] = []
        let presence = AccountPresenceCoordinator(transport: socket, clientPublicID: account, retryDelays: [.zero]) {
            changes.append($0)
        }

        presence.setWindowActive(false)
        #expect(await socket.startCount == 0)
        #expect(!presence.isOnline)

        presence.setWindowActive(true)
        #expect(try await waitUntil { presence.isOnline })
        #expect(await socket.requests == [true])

        await socket.emit(.reconnecting)
        #expect(try await waitUntil { !presence.isOnline })
        await socket.emit(.connected)
        #expect(try await waitUntil { presence.isOnline })

        presence.setWindowActive(false)
        #expect(!presence.isOnline)
        #expect(try await waitUntil { await socket.requests == [true, true, false] })
        #expect(changes == [true, false, true, false])

        await presence.stop()
        presence.setWindowActive(true)
        #expect(await socket.didDispose)
        #expect(!presence.isOnline)
    }

    @MainActor @Test func mismatchedAccountStaysOfflineWithBoundedRetries() async throws {
        let socket = PresenceTransportFixture(reportedAccount: UUID())
        var changes: [Bool] = []
        let presence = AccountPresenceCoordinator(transport: socket, clientPublicID: UUID(), retryDelays: [.zero, .zero]) {
            changes.append($0)
        }

        presence.setWindowActive(true)
        #expect(try await waitUntil { await socket.requests.count == 2 })
        await presence.stop()
        #expect(await socket.requests == [true, true])
        #expect(changes.isEmpty)
    }

    @MainActor @Test func inactiveMacFollowsOtherDevicesAndKeepsTheirStateWhenItsWindowLosesFocus() async throws {
        let account = UUID()
        let socket = PresenceTransportFixture(reportedAccount: account, supportsAccountFeed: true)
        var changes: [Bool] = []
        let presence = AccountPresenceCoordinator(transport: socket, clientPublicID: account, retryDelays: [.zero]) {
            changes.append($0)
        }

        presence.observeAccount()
        #expect(try await waitUntil {
            let watches = await socket.watches
            let reports = await socket.requests
            return watches == 1 && reports == [false]
        })
        await socket.emitAccount(account, online: true, revision: 2)
        #expect(try await waitUntil { presence.isOnline })

        presence.setWindowActive(true)
        #expect(try await waitUntil { await socket.requests == [false, true] })
        presence.setWindowActive(false)
        #expect(presence.isOnline)
        #expect(try await waitUntil { await socket.requests == [false, true, false] })

        await socket.emitAccount(account, online: false, revision: 1)
        await socket.emitAccount(UUID(), online: false, revision: 3)
        await socket.emitAccount(account, online: true, revision: 4)
        await socket.emitAccount(account, online: false, revision: 5)
        #expect(try await waitUntil { !presence.isOnline })
        #expect(changes == [true, false])

        await socket.emit(.reconnecting)
        await socket.emit(.connected)
        #expect(try await waitUntil { await socket.watches == 2 })
        await socket.emitAccount(account, online: true, revision: 1)
        #expect(try await waitUntil { presence.isOnline })
        await presence.stop()
        #expect(!presence.isOnline)
    }

    @MainActor @Test func earlierServersStillAcknowledgeLocalFocus() async throws {
        let account = UUID()
        let socket = PresenceTransportFixture(reportedAccount: account)
        let presence = AccountPresenceCoordinator(transport: socket, clientPublicID: account, retryDelays: [.zero]) { _ in }
        presence.observeAccount()
        #expect(try await waitUntil { await socket.watches == 1 })

        presence.setWindowActive(true)
        #expect(try await waitUntil { presence.isOnline })
        presence.setWindowActive(false)
        #expect(!presence.isOnline)
        await presence.stop()
    }

    @MainActor private func waitUntil(_ check: @MainActor () async -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if await check() { return true }
            try await Task.sleep(for: .milliseconds(5))
        }
        return await check()
    }
}

private actor PresenceTransportFixture: AccountPresenceTransport {
    private struct ServerReply: Encodable {
        let clientPublicId: UUID
        let connectionId = "presence-fixture"
        let isOnline: Bool
        let revision: Int
    }

    private let reportedAccount: UUID
    private let supportsAccountFeed: Bool
    private let updates = AsyncStream<MizonSocketEvent>.makeStream()
    private(set) var startCount = 0
    private(set) var watches = 0
    private(set) var requests: [Bool] = []
    private(set) var didDispose = false
    private(set) var windowPresence: ClientWindowPresenceResponse?

    init(reportedAccount: UUID, supportsAccountFeed: Bool = false) {
        self.reportedAccount = reportedAccount
        self.supportsAccountFeed = supportsAccountFeed
    }

    func events() -> AsyncStream<MizonSocketEvent> { updates.stream }

    func start() {
        startCount += 1
        emit(.connected)
    }

    func emit(_ state: HubConnectionState) {
        if state != .connected { windowPresence = nil }
        updates.continuation.yield(.stateChanged(state))
    }

    func setWindowPresence(isActive: Bool) throws {
        requests.append(isActive)
        let reply = ServerReply(clientPublicId: reportedAccount, isOnline: isActive, revision: requests.count)
        windowPresence = try JSONDecoder().decode(ClientWindowPresenceResponse.self, from: JSONEncoder().encode(reply))
    }

    func watchAccountPresence() throws -> ClientAccountPresenceResponse {
        watches += 1
        guard supportsAccountFeed else { throw URLError(.unsupportedURL) }
        return .init(clientPublicId: reportedAccount, isOnline: false, revision: 0)
    }

    func emitAccount(_ account: UUID, online: Bool, revision: Int64) {
        updates.continuation.yield(.accountPresenceChanged(.init(clientPublicId: account, isOnline: online, revision: revision)))
    }

    func dispose() {
        didDispose = true
        updates.continuation.finish()
    }
}
#endif
