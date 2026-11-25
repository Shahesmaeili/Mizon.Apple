#if os(macOS)
import Foundation
import MizonAPI
import Testing
@testable import MizonAppleCore

struct MacProfilePresenceTests {
    @MainActor @Test func activeWindowRequiresConfirmationAndDisconnectClearsPresence() async throws {
        let account = UUID()
        let socket = PresenceTransportFixture(reportedAccount: account)
        var changes: [Bool] = []
        let presence = MacProfilePresence(transport: socket, clientPublicID: account, retryDelays: [.zero]) {
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
        let presence = MacProfilePresence(transport: socket, clientPublicID: UUID(), retryDelays: [.zero, .zero]) {
            changes.append($0)
        }

        presence.setWindowActive(true)
        #expect(try await waitUntil { await socket.requests.count == 2 })
        await presence.stop()
        #expect(await socket.requests == [true, true])
        #expect(changes.isEmpty)
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

private actor PresenceTransportFixture: MacProfilePresenceTransport {
    private struct ServerReply: Encodable {
        let clientPublicId: UUID
        let connectionId = "presence-fixture"
        let isOnline: Bool
        let revision: Int
    }

    private let reportedAccount: UUID
    private let updates = AsyncStream<MizonSocketEvent>.makeStream()
    private(set) var startCount = 0
    private(set) var requests: [Bool] = []
    private(set) var didDispose = false
    private(set) var windowPresence: ClientWindowPresenceResponse?

    init(reportedAccount: UUID) { self.reportedAccount = reportedAccount }

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

    func dispose() {
        didDispose = true
        updates.continuation.finish()
    }
}
#endif
