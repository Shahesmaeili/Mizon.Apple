#if os(macOS) || os(iOS)
import Foundation
import MizonAppleCore
import Testing
@testable import MizonAppleUI

@MainActor
struct NearbyDiscoveryModelTests {
    @Test func startsForForegroundSessionsAndRespectsPersistentOptOut() async throws {
        let preferenceSuite = "mizon.nearby.fixture.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: preferenceSuite))
        defer { defaults.removePersistentDomain(forName: preferenceSuite) }
        let neighbor = NearbyDiscoveredPeer(advertisement: NearbyPresenceAdvertisement(
            id: UUID(), platform: .windows, appVersion: "1.0", deviceName: "Fixture PC", account: "other-account"
        ))
        let service = FixtureNearbyDiscovery(events: [.searching, .peers([neighbor])])
        let model = NearbyDiscoveryModel(service: service, defaults: defaults)
        #expect(model.enabled)
        await model.discover(inForeground: false, publicUsername: "mizon_user", displayName: "Mizon User")
        #expect(service.advertisements.isEmpty)
        #expect(model.status == .off)

        await model.discover(inForeground: true, publicUsername: "mizon_user", displayName: "Mizon User")
        #expect(service.advertisements.last?.account == "mizon_user")
        #expect(model.peers == [neighbor])
        #expect(model.status == .ready)

        await model.discover(inForeground: false, publicUsername: "mizon_user", displayName: "Mizon User")
        #expect(service.advertisements.count == 1)
        #expect(model.peers.isEmpty)
        #expect(model.status == .off)

        await model.discover(inForeground: true, publicUsername: "mizon_user", displayName: "Mizon User")
        #expect(service.advertisements.count == 2)
        #expect(service.advertisements.first?.id != service.advertisements.last?.id)
        model.enabled = false
        let nextSession = NearbyDiscoveryModel(service: service, defaults: defaults)
        #expect(!nextSession.enabled)
        await nextSession.discover(inForeground: true, publicUsername: "mizon_user", displayName: "Mizon User")
        #expect(service.advertisements.count == 2)
    }

    @Test func omitsAnEmailLikeIdentifierAndShowsPermissionDenial() async throws {
        let preferenceSuite = "mizon.nearby.fixture.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: preferenceSuite))
        defer { defaults.removePersistentDomain(forName: preferenceSuite) }
        let service = FixtureNearbyDiscovery(events: [.searching, .permissionDenied])
        let model = NearbyDiscoveryModel(service: service, defaults: defaults)
        await model.discover(inForeground: true, publicUsername: "someone@example.org", displayName: "Public profile")
        #expect(service.advertisements.count == 1)
        #expect(service.advertisements.last?.account == nil)
        #expect(service.advertisements.last?.displayName == "Public profile")
        #expect(model.status == .permissionDenied)
        #expect(model.peers.isEmpty)
    }
}

@MainActor
private final class FixtureNearbyDiscovery: NearbyDiscovering {
    let events: [NearbyDiscoveryEvent]
    private(set) var advertisements: [NearbyPresenceAdvertisement] = []

    init(events: [NearbyDiscoveryEvent]) {
        self.events = events
    }

    func start(advertising advertisement: NearbyPresenceAdvertisement) async -> AsyncStream<NearbyDiscoveryEvent> {
        advertisements.append(advertisement)
        let (stream, continuation) = AsyncStream<NearbyDiscoveryEvent>.makeStream()
        events.forEach { continuation.yield($0) }
        continuation.finish()
        return stream
    }

    func stop() async {}
}
#endif
